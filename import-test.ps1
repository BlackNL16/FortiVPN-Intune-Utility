<#
.SYNOPSIS
    Test importing a FortiClient VPN profile with password.

.DESCRIPTION
    This script simulates the behavior of the Intune installation script to check if
    an exported FortiClient VPN profile can be correctly imported with
    customer-specific passwords. It logs the process for debugging.
    
.EXAMPLE
    .\Test-FortiVPNImport.ps1 -ProfileName 'test'
.EXAMPLE
    .\Test-FortiVPNImport.ps1
    (The script will prompt for a profile name)
#>
param(
    [string]$ProfileName,
    [switch]$Verbose,
    [switch]$Restore
)

# =========================
# CONFIGURATION
# =========================

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SecretsPath = Join-Path $BasePath "secrets.json"
$ConfigPath = Join-Path $BasePath "config.json"
$OutputPath = Join-Path $BasePath "Output"
$LogPath = Join-Path $BasePath "forti_import_test.log"

# Ensure the log file is ready
if (Test-Path $LogPath) { Remove-Item $LogPath }

# =========================
# SHARED MODULE
# =========================

Import-Module (Join-Path $BasePath "FortiUtils.psm1") -Force

# Wrap Write-Log: always log to file, only print to console in Verbose mode
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    if ($Verbose) {
        Write-Host $LogMessage
    }
    Add-Content -Path $LogPath -Value $LogMessage
}

# =========================

function Get-Secrets {
    param(
        [string]$SecretsPath,
        [switch]$Verbose
    )
    if (-not (Test-Path $SecretsPath)) {
        Write-Log "Secrets file '$SecretsPath' not found.", "ERROR"
        return $null
    }
    
    $SecretsContent = Get-Content $SecretsPath | Out-String
    
    if ([string]::IsNullOrWhiteSpace($SecretsContent)) {
        Write-Log "Secrets file is empty.", "ERROR"
        return $null
    }
    
    try {
        $Secrets = $SecretsContent | ConvertFrom-Json -ErrorAction Stop
        if ($Verbose) {
            Write-Log "JSON file parsed successfully.", "DEBUG"
        }
    }
    catch {
        Write-Log "Error converting secrets.json. Check the JSON format.", "ERROR"
        if ($Verbose) {
            Write-Log "Details: $_.Exception.Message", "ERROR"
        }
        return $null
    }
    
    # Check if the object is an IDictionary. If not, try to convert it.
    if (-not ($Secrets -is [System.Collections.IDictionary])) {
        Write-Log "Not a valid key/value table. Converting manually.", "WARN"
        $hash = [hashtable]::new()
        foreach ($prop in $Secrets | Get-Member -MemberType NoteProperty) {
            $hash.Add($prop.Name, $Secrets.$($prop.Name))
        }
        return $hash
    }
    
    return $Secrets
}

# =========================
# MAIN SCRIPT
# =========================

$BackupConfPath = $null
$FCConfigPath = Get-Item "C:\Program Files*\Fortinet\FortiClient\FCConfig.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName

if ($Restore) {
    # --- Restore from backup ---
    Write-Log "Restoring FortiClient configuration..."
    
    # Prompt for the backup file path
    $BackupConfPath = Read-Host "Enter the full path of the backup file (e.g. C:\Temp\backup.conf)"
    if ([string]::IsNullOrWhiteSpace($BackupConfPath) -or -not (Test-Path $BackupConfPath)) {
        Write-Log "Invalid or non-existent backup file path. Restore aborted.", "ERROR"
        return
    }

    if ($FCConfigPath) {
        $TemporaryPassword = "TempPassword123!" # Temporary password for the backup
        Start-Process -FilePath $FCConfigPath -ArgumentList "-m vpn -f `"$BackupConfPath`" -o import -p `"$TemporaryPassword`"" -Wait
        Write-Log "Configuration successfully restored."
    }
    else {
        Write-Log "FCConfig.exe not found. Restore failed.", "ERROR"
        return
    }
    
    # --- Remove the backup ---
    Remove-Item $BackupConfPath -Force -ErrorAction SilentlyContinue
    Write-Log "Temporary backup removed."
    return
}

try {
    Write-Log "Starting FortiVPN profile import test."

    # Load configuration and secrets
    $Secrets = Get-Secrets -SecretsPath $SecretsPath -Verbose:$Verbose
    if (-not $Secrets) {
        return
    }

    $ConfigContent = Get-Content $ConfigPath | Out-String
    $Config = $ConfigContent | ConvertFrom-Json

    if (-not $Config) {
        Write-Log "Configuration file '$ConfigPath' cannot be read or is empty.", "ERROR"
        return
    }
    
    # Prompt for profile name if not provided as parameter
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        # Log the raw JSON content if verbose mode is enabled
        if ($Verbose) {
            Write-Log "Raw JSON content:", "DEBUG"
            Write-Log ($Config | ConvertTo-Json), "DEBUG"
        }

        # Prompt the user to choose a profile
        Write-Host ""
        Write-Host "Available profiles:"
        Write-Host "-------------------"

        $AvailableProfiles = @()
        if ($Config -is [System.Collections.IDictionary]) {
            $AvailableProfiles = $Config.Keys | Sort-Object
        }
        elseif ($Config -is [System.Array]) {
            $AvailableProfiles = $Config | ForEach-Object { $_.VPNProfile } | Sort-Object
        }

        if ($Verbose) {
            Write-Log "Found profiles: $($AvailableProfiles -join ', ')", "DEBUG"
        }

        if ($AvailableProfiles.Count -eq 0) {
            Write-Log "No profiles found in config.json.", "ERROR"
            return
        }
        
        for ($i = 0; $i -lt $AvailableProfiles.Count; $i++) {
            Write-Host "$($i + 1). $($AvailableProfiles[$i])"
        }
        Write-Host ""
        
        $Choice = Read-Host "Select a profile by entering the number"
        $ChoiceInt = 0
        
        # Validate the user's choice
        if ([int]::TryParse($Choice, [ref]$ChoiceInt)) {
            if ($ChoiceInt -gt 0 -and $ChoiceInt -le $AvailableProfiles.Count) {
                $ProfileName = $AvailableProfiles[$ChoiceInt - 1]
            }
        }

        if ([string]::IsNullOrWhiteSpace($ProfileName)) {
            Write-Log "Invalid selection. Test cannot be performed.", "ERROR"
            return
        }
    }

    # Find the profile name and password
    $Password = $null
    if ($Secrets.ContainsKey($ProfileName)) {
        $Password = $Secrets.$ProfileName
    }

    if (-not $Password) {
        Write-Log "Password for profile '$ProfileName' not found in secrets.json.", "ERROR"
        return
    }

    # Retrieve data
    $CustomerName = $null
    $CustomerConfig = $Config | Where-Object { $_.VPNProfile -eq $ProfileName }
    if ($CustomerConfig) {
        $CustomerName = $CustomerConfig.Name
    }

    if (-not $CustomerName) {
        Write-Log "No customer name found for profile '$ProfileName' in config.json.", "ERROR"
        return
    }

    $CustomerFolder = Join-Path $OutputPath $CustomerName
    $ConfFile = Join-Path $CustomerFolder "$($CustomerName)_VPN.conf"
    
    # Check if the files exist
    if (-not (Test-Path $ConfFile)) {
        Write-Log "Configuration file '$ConfFile' not found.", "ERROR"
        return
    }
    
    # --- Backup current configuration ---
    Write-Log "Backing up existing FortiClient configuration..."
    if (-not $FCConfigPath) {
        Write-Log "FCConfig.exe not found. Backup cannot be made.", "ERROR"
        return
    }
    
    $BackupConfName = "FortiClient_Backup_$(Get-Date -Format 'yyyyMMddHHmmss').conf"
    $BackupConfPath = Join-Path $env:TEMP $BackupConfName
    
    $TemporaryPassword = "TempPassword123!" # Temporary password for the backup
    Start-Process -FilePath $FCConfigPath -ArgumentList "-m vpn -f `"$BackupConfPath`" -o export -p `"$TemporaryPassword`"" -Wait
    
    if (-not (Test-Path $BackupConfPath)) {
        Write-Log "Backup file could not be created. Continuing without backup.", "WARN"
    }
    else {
        Write-Log "Backup saved at: $BackupConfPath"
    }

    # Search for FCConfig.exe again to ensure the path is correct
    Write-Log "Searching for FCConfig.exe..."
    if (-not $FCConfigPath) {
        Write-Log "FCConfig.exe not found. Import aborted.", "ERROR"
        return
    }
    Write-Log "FCConfig.exe found at: $FCConfigPath"
    
    # Import the profile
    Write-Log "Starting profile import..."
    Start-Process -FilePath $FCConfigPath -ArgumentList "-m vpn -f `"$ConfFile`" -o import -p `"$Password`"" -Wait
    
    Write-Log "Import completed. Checking for profile..."
    
    # Check if the profile was successfully imported in the registry
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\$ProfileName"
    if (Test-Path $RegPath) {
        Write-Log "Profile '$ProfileName' successfully imported. Test passed.", "INFO"
    }
    else {
        Write-Log "Profile '$ProfileName' not found after import. Test failed.", "ERROR"
        return
    }

    Write-Host ""
    Write-Host "The test is complete. To restore the original configuration, press Enter. Otherwise, close the script."
    Write-Host ""
    
    Read-Host
}
catch {
    Write-Log "An error occurred: $_", "ERROR"
    exit 1
}
finally {
    # --- Restore from backup ---
    if ($BackupConfPath -and (Test-Path $BackupConfPath)) {
        Write-Log "Restoring FortiClient configuration..."
        
        # FCConfig.exe path must be checked again
        if ($FCConfigPath) {
            Start-Process -FilePath $FCConfigPath -ArgumentList "-m vpn -f `"$BackupConfPath`" -o import -p `"$TemporaryPassword`"" -Wait
            Write-Log "Configuration successfully restored."
        }
        else {
            Write-Log "FCConfig.exe not found. Restore failed.", "ERROR"
        }
        
        # --- Remove the backup ---
        Remove-Item $BackupConfPath -Force -ErrorAction SilentlyContinue
        Write-Log "Temporary backup removed."
    }
}
Write-Log "End of script."