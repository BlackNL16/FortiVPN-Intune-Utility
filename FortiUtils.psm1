<#
.SYNOPSIS
    Shared utility functions for the FortiVPN Intune Utility.
.DESCRIPTION
    Contains common functions used across multiple scripts in this project.
    Import this module with: Import-Module (Join-Path $PSScriptRoot "FortiUtils.psm1")
#>

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

    # Color-coded console output based on log level
    switch ($Level) {
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "WARN" { Write-Host $LogMessage -ForegroundColor Yellow }
        "DEBUG" { Write-Host $LogMessage -ForegroundColor DarkGray }
        default { Write-Host $LogMessage -ForegroundColor Green }
    }

    if ($LogFile) {
        Add-Content -Path $LogFile -Value $LogMessage
    }
}

Export-ModuleMember -Function Write-Log
