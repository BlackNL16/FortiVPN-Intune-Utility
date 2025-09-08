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
    .\FortiClient-Intune-Packager.ps1 -ConfigPath "C:\MyConfigs\Customers.json" -SkipIntuneWin
#>
param(
    [string]$ConfigPath = "config.json",
    [string]$SecretsPath = "secrets.json",
    [switch]$AutoApprove = $false,
    [switch]$SkipIntuneWin = $false
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
# FUNCTIONS
# =========================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogPath -Value $LogMessage
}

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
    } else {
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
            } else {
                $ExportApproved = (Read-Host "Manually verify the export. Is it OK? (Y/N)") -eq 'Y'
            }
            
            if (-not $ExportApproved) {
                Remove-Item $ConfFile -Force -ErrorAction SilentlyContinue
                Write-Log "Export verification failed. Retrying..."
            }
        } else {
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
    $IntuneWinTool = Join-Path $BasePath "intunewin\IntuneWinAppUtil.exe"
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
        } else {
            Write-Log "Cannot find the created IntuneWin file to rename. The package may not have been created correctly.", "ERROR"
        }
    } else {
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
    if (!(Test-Path $CustomerFolder)) {
        New-Item -ItemType Directory -Path $CustomerFolder | Out-Null
        Write-Log "Customer folder created: $CustomerFolder"
    }

    $VpnProfile = $Customer.VPNProfile
    $ConfFile = Join-Path $CustomerFolder "$($Customer.Name)_VPN.conf"
    $CheckFile = Join-Path $CustomerFolder "check.ps1"
    $InstallFile = Join-Path $CustomerFolder "install.ps1"
    $UninstallFile = Join-Path $CustomerFolder "uninstall.ps1"
    $TxtFile = Join-Path $CustomerFolder "IntuneDeployment.txt"
    
    # --- Check profile existence ---
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\$VpnProfile"
    if (!(Test-Path $RegPath)) {
        Write-Log "VPN profile '$VpnProfile' does not exist. Please create it manually.", "WARN"
        if (-not $AutoApprove) {
            Read-Host "Press Enter after creating the profile..."
        }
        if (!(Test-Path $RegPath)) {
            Write-Log "Profile still missing. Skipping $($Customer.Name).", "WARN"
            return
        }
    }

    # --- Export with approval (new function) ---
    $ExportApproved = Export-FortiVPNProfile -Customer $Customer -Password $Password -ConfFile $ConfFile -AutoApprove:$AutoApprove

    if ($ExportApproved) {
        # --- Remove profile from FortiClient for testing ---
        Remove-Item -Path $RegPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Profile '$VpnProfile' removed from FortiClient."

        # --- Copy all base files and create customer-specific scripts from templates ---
        Copy-Item -Path (Join-Path $BaseFilesPath "*") -Destination $CustomerFolder -Recurse -Force
        Write-Log "Base files copied to $CustomerFolder"

        # --- Replace template variables in the scripts ---
        $Variables = @{
            '{{VpnProfile}}' = $Customer.VPNProfile
            '{{CustomerName}}' = $Customer.Name
            '{{Version}}' = $Customer.Version
            '{{Password}}' = $Password
        }

        Invoke-TemplateProcessor -TemplateName "check_template.ps1" -CustomerFolder $CustomerFolder -Variables $Variables
        Invoke-TemplateProcessor -TemplateName "install_template.ps1" -CustomerFolder $CustomerFolder -Variables $Variables
        Invoke-TemplateProcessor -TemplateName "uninstall_template.ps1" -CustomerFolder $CustomerFolder -Variables $Variables
        
        # --- Generate IntuneDeployment.txt from template ---
        $IntuneTxtTemplatePath = Join-Path $TemplatesPath "intune_deployment_template.txt"
        if (Test-Path $IntuneTxtTemplatePath) {
            $IntuneDeploymentContent = Get-Content $IntuneTxtTemplatePath
            Set-Content -Path $TxtFile -Value $IntuneDeploymentContent -Encoding UTF8
            Write-Log "IntuneDeployment.txt generated from template."
        } else {
            Write-Log "Intune deployment template not found. Using hardcoded content.", "WARN"
            @"
INSTALL COMMAND:
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1

UNINSTALL COMMAND:
powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1

DETECTION RULE:
Use Custom Script detection.
Upload the included 'check.ps1' to Intune as the detection script.
"@ | Set-Content -Path $TxtFile -Encoding UTF8
        }

        Write-Log "Customer-specific scripts created for $($Customer.Name)."

        # --- Optionally create .intunewin package (new function) ---
        if (-not $SkipIntuneWin) {
            New-IntuneWinPackage -CustomerFolder $CustomerFolder -CustomerName $Customer.Name
        }
    } else {
        Write-Log "Export not approved. Skipping $($Customer.Name).", "WARN"
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

    foreach ($customer in $Customers) {
        $password = $Secrets.$($customer.VPNProfile)
        if ($password) {
            Build-FortiVPNPackage -Customer $customer -Password $password
        } else {
            Write-Log "No password found for VPN profile '$($customer.VPNProfile)'. Skipping customer '$($customer.Name)'.", "WARN"
        }
    }

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