<#
.SYNOPSIS
    Automates FortiClient VPN export and creates per-customer Intune folders.
.DESCRIPTION
    Uses the script location as base path. Reads customer configuration
    from a JSON file for easy management and retrieves passwords
    from a separate 'secrets.json' file. Generates customer-specific install,
    uninstall, and detection scripts using templates.
.EXAMPLE
    .\FortiClient-Intune-Packager.ps1
    .\FortiClient-Intune-Packager.ps1 -AutoApprove
    .\FortiClient-Intune-Packager.ps1 -CustomerName "customer1","customer2"
    .\FortiClient-Intune-Packager.ps1 -Force -SkipIntuneWin
    .\FortiClient-Intune-Packager.ps1 -ConfigPath "C:\MyConfigs\Customers.json"
#>
param(
    [string]$ConfigPath = "config.json",
    [string]$SecretsPath = "secrets.json",
    [string[]]$CustomerName,
    [switch]$AutoApprove = $false,
    [switch]$SkipIntuneWin = $false,
    [switch]$Force = $false
)

# =========================
# CONFIGURATION
# =========================

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BasePath = $ScriptPath
$BaseFilesPath = Join-Path $BasePath "BaseFiles"
$TemplatesPath = Join-Path $BasePath "Templates"
$OutputPath = Join-Path $BasePath "Output"
$IntuneWinTool = Join-Path $BasePath "intunewin\IntuneWinAppUtil.exe"
$LogPath = Join-Path $BasePath "forti_packager.log"

# Ensure the output directory exists and prepare the log file
if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }
if (Test-Path $LogPath) { Remove-Item $LogPath }

# =========================
# SHARED MODULE
# =========================

Import-Module (Join-Path $BasePath "FortiUtils.psm1") -Force

# Wrap Write-Log to always pass our log file path
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    FortiUtils\Write-Log -Message $Message -Level $Level -LogFile $LogPath
}

# =========================

function Invoke-TemplateProcessor {
    param(
        [string]$TemplateName,
        [string]$CustomerFolder,
        [psobject]$Variables
    )
    $TemplatePath = Join-Path $TemplatesPath "$TemplateName"
    if (Test-Path $TemplatePath) {
        $content = Get-Content $TemplatePath | ForEach-Object {
            $Line = $_
            foreach ($key in $Variables.Keys) {
                $Line = $Line.Replace($key, $Variables[$key])
            }
            $Line
        }
        Set-Content -Path (Join-Path $CustomerFolder $TemplateName.Replace("_template", "")) -Value $content -Encoding UTF8
        Write-Log "Template '$TemplateName' processed."
    }
    else {
        Write-Log "Template '$TemplateName' not found. File generation skipped.", "WARN"
    }
}

function Export-FortiVPNProfile {
    param(
        [psobject]$Customer,
        [string]$Password,
        [string]$ConfFile,
        [switch]$AutoApprove
    )
    
    $ExportApproved = $false
    while (-not $ExportApproved) {
        Write-Log "Exporting VPN profile '$($Customer.VPNProfile)'..."
        $FCConfigPath = Get-Item "C:\Program Files*\Fortinet\FortiClient\FCConfig.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if (-not $FCConfigPath) {
            Write-Log "FCConfig.exe not found. Aborting export.", "ERROR"
            return $false
        }
        
        Start-Process -FilePath $FCConfigPath -ArgumentList "-m vpn -f `"$ConfFile`" -o export -p `"$Password`"" -Wait

        if (Test-Path $ConfFile) {
            Write-Log "Export created: $ConfFile"
            if ($AutoApprove) {
                $ExportApproved = $true
            }
            else {
                $ExportApproved = (Read-Host "Manually verify the export. Is it OK? (Y/N)") -eq 'Y'
            }
            
            if (-not $ExportApproved) {
                Remove-Item $ConfFile -Force -ErrorAction SilentlyContinue
                Write-Log "Export verification failed. Retrying..."
            }
        }
        else {
            Write-Log "Export failed. Check FortiClient logs or try manually again.", "ERROR"
            if ($AutoApprove) { break }
            $Retry = Read-Host "Retry? (Y/N)"
            if ($Retry -ne 'Y') { break }
        }
    }
    return $ExportApproved
}

function New-IntuneWinPackage {
    param(
        [string]$CustomerFolder,
        [string]$CustomerName
    )
    $SetupFile = Join-Path $CustomerFolder "FortiClientVPN.exe"
    
    if ((Test-Path $IntuneWinTool) -and (Test-Path $SetupFile)) {
        Write-Log "Creating IntuneWin package..."
        
        # Step 1: Generate the package in the customer folder with the default name
        & $IntuneWinTool -c $CustomerFolder -s "FortiClientVPN.exe" -o $CustomerFolder -q
        
        $intunewinOriginalPath = Join-Path $CustomerFolder "FortiClientVPN.intunewin"
        $intunewinNewPath = Join-Path $CustomerFolder "$($CustomerName)_FortiClientVPN.intunewin"
        
        # Step 2: Rename the file to the desired name
        if (Test-Path $intunewinOriginalPath) {
            Rename-Item -Path $intunewinOriginalPath -NewName $intunewinNewPath -Force
            Write-Log "IntuneWin package created: $intunewinNewPath"
        }
        else {
            Write-Log "Cannot find the created IntuneWin file to rename. The package may not have been created correctly.", "ERROR"
        }
    }
    else {
        Write-Log "IntuneWinAppUtil.exe or FortiClientVPN.exe not found. Intunewin packaging skipped.", "WARN"
    }
}

function Build-FortiVPNPackage {
    param(
        [psobject]$Customer,
        [string]$Password
    )

    Write-Log "Processing customer: $($Customer.Name)"
    $CustomerFolder = Join-Path $OutputPath $Customer.Name

    # --- Overwrite protection ---
    if (Test-Path $CustomerFolder) {
        if (-not $Force) {
            $Overwrite = Read-Host "Output folder '$($Customer.Name)' already exists. Overwrite? (Y/N)"
            if ($Overwrite -ne 'Y') {
                Write-Log "Skipping $($Customer.Name): existing output not overwritten.", "WARN"
                return 'Skipped (not overwritten)'
            }
        }
        Write-Log "Overwriting existing output for $($Customer.Name)."
    }
    else {
        New-Item -ItemType Directory -Path $CustomerFolder | Out-Null
        Write-Log "Customer folder created: $CustomerFolder"
    }

    $VpnProfile = $Customer.VPNProfile
    $ConfFile = Join-Path $CustomerFolder "$($Customer.Name)_VPN.conf"
    
    # --- Check profile existence ---
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\$VpnProfile"
    if (!(Test-Path $RegPath)) {
        Write-Log "VPN profile '$VpnProfile' does not exist. Please create it manually.", "WARN"
        if (-not $AutoApprove) {
            Read-Host "Press Enter after creating the profile..."
        }
        if (!(Test-Path $RegPath)) {
            Write-Log "Profile still missing. Skipping $($Customer.Name).", "WARN"
            return 'Skipped (profile missing)'
        }
    }

    # --- Export with approval ---
    $ExportApproved = Export-FortiVPNProfile -Customer $Customer -Password $Password -ConfFile $ConfFile -AutoApprove:$AutoApprove

    if ($ExportApproved) {
        # --- Remove profile from FortiClient for testing ---
        Remove-Item -Path $RegPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Profile '$VpnProfile' removed from FortiClient."

        # --- Copy all base files ---
        Copy-Item -Path (Join-Path $BaseFilesPath "*") -Destination $CustomerFolder -Recurse -Force
        Write-Log "Base files copied to $CustomerFolder"

        # --- Template variables ---
        $Variables = @{
            '{{VpnProfile}}'   = $Customer.VPNProfile
            '{{CustomerName}}' = $Customer.Name
            '{{Version}}'      = $Customer.Version
            '{{Password}}'     = $Password
        }

        # --- Auto-discover and process all templates ---
        $TemplateFiles = Get-ChildItem -Path $TemplatesPath -Filter "*_template.*" -File
        foreach ($Template in $TemplateFiles) {
            Invoke-TemplateProcessor -TemplateName $Template.Name -CustomerFolder $CustomerFolder -Variables $Variables
        }

        Write-Log "Customer-specific scripts created for $($Customer.Name)."

        # --- Optionally create .intunewin package ---
        if (-not $SkipIntuneWin) {
            New-IntuneWinPackage -CustomerFolder $CustomerFolder -CustomerName $Customer.Name
        }
        return 'Success'
    }
    else {
        Write-Log "Export not approved. Skipping $($Customer.Name).", "WARN"
        return 'Skipped (export not approved)'
    }
}

# =========================
# MAIN SCRIPT
# =========================

try {
    Write-Log "Starting FortiClient Intune Packager script."
    
    # Check the configuration files
    if (!(Test-Path $ConfigPath)) {
        throw "Configuration file '$ConfigPath' not found."
    }
    if (!(Test-Path $SecretsPath)) {
        throw "Secrets file '$SecretsPath' not found. Cannot load passwords."
    }
    
    $Customers = Get-Content $ConfigPath | Out-String | ConvertFrom-Json
    $Secrets = Get-Content $SecretsPath | Out-String | ConvertFrom-Json
    Write-Log "Customer configuration and secrets loaded."

    # Validate config.json entries
    foreach ($c in $Customers) {
        if (-not $c.Name -or -not $c.VPNProfile -or -not $c.Version) {
            throw "Invalid customer entry in config.json: each entry must have Name, VPNProfile, and Version. Problem entry: $($c | ConvertTo-Json -Compress)"
        }
    }

    # Filter to specific customers
    if ($CustomerName) {
        # Parameter provided — filter directly
        $Customers = $Customers | Where-Object { $CustomerName -contains $_.Name }
        if ($Customers.Count -eq 0) {
            throw "No matching customers found for: $($CustomerName -join ', '). Check your config.json."
        }
        Write-Log "Filtered to $($Customers.Count) customer(s): $($CustomerName -join ', ')"
    }
    else {
        # No parameter — show interactive menu
        Write-Host ""
        Write-Host "Available customers:" -ForegroundColor Cyan
        Write-Host "--------------------" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Customers.Count; $i++) {
            Write-Host "  $($i + 1). $($Customers[$i].Name)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  A. Process ALL customers" -ForegroundColor Green
        Write-Host ""

        $Selection = Read-Host "Select customers (comma-separated numbers, or 'A' for all)"

        if ($Selection -ne 'A' -and $Selection -ne 'a') {
            $Indices = $Selection -split ',' | ForEach-Object {
                $idx = 0
                if ([int]::TryParse($_.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $Customers.Count) {
                    $idx - 1
                }
            }
            if ($Indices.Count -eq 0) {
                throw "Invalid selection. Please enter valid numbers or 'A' for all."
            }
            $Customers = $Customers[$Indices]
            Write-Log "Selected $($Customers.Count) customer(s): $(($Customers | ForEach-Object { $_.Name }) -join ', ')"
        }
        else {
            Write-Log "Processing all $($Customers.Count) customer(s)."
        }
    }

    Write-Log "Configuration validated: $($Customers.Count) customer(s) to process."

    $Total = $Customers.Count
    $Current = 0
    $Results = @()

    foreach ($customer in $Customers) {
        $Current++
        $PercentComplete = [math]::Round(($Current / $Total) * 100)
        Write-Progress -Activity "FortiClient Intune Packager" -Status "Processing $($customer.Name) ($Current of $Total)" -PercentComplete $PercentComplete

        $password = $Secrets.$($customer.VPNProfile)
        if ($password) {
            try {
                $Status = Build-FortiVPNPackage -Customer $customer -Password $password
                $Results += [PSCustomObject]@{ Customer = $customer.Name; Status = $Status }
            }
            catch {
                Write-Log "Error processing $($customer.Name): $_", "ERROR"
                $Results += [PSCustomObject]@{ Customer = $customer.Name; Status = 'Failed' }
            }
        }
        else {
            Write-Log "No password found for VPN profile '$($customer.VPNProfile)'. Skipping customer '$($customer.Name)'.", "WARN"
            $Results += [PSCustomObject]@{ Customer = $customer.Name; Status = 'Skipped (no password)' }
        }
    }

    Write-Progress -Activity "FortiClient Intune Packager" -Completed

    # Print summary table
    Write-Host ""
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "  PACKAGING SUMMARY" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    $Results | Format-Table -AutoSize -Property Customer, Status
    Write-Log "All customer folders created under $OutputPath"
    Write-Log "Script completed successfully."
}
catch {
    Write-Log "An error occurred: $_", "ERROR"
    Write-Log "Script stopped due to an error."
    exit 1
}
finally {
    Write-Log "End of script."
}