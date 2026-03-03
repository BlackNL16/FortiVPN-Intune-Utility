<#
.SYNOPSIS
    Detection and self-healing for FortiClient VPN.
.DESCRIPTION
    Checks FortiClient executable and VPN profile.
    If VPN profile is missing, automatically re-imports it using FCConfig.exe.
.EXAMPLE
    .\check.ps1
#>

param(
    [string]$ProfileName = '{{VpnProfile}}',
    [string]$TargetVersion = '{{Version}}',
    [string]$Password = '{{Password}}',
    [string]$ConfigFile = '{{CustomerName}}_VPN.conf'
)

$ErrorActionPreference = 'Stop'

try {
    # --- Detect FortiClient path ---
    $PossiblePaths = @(
        "C:\Program Files\Fortinet\FortiClient\FortiClient.exe",
        "C:\Program Files (x86)\Fortinet\FortiClient\FortiClient.exe"
    )

    $ProgramPath = $PossiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $ProgramPath) {
        Write-Host "FortiClient not found."
        exit 1
    }

    # --- Check version ---
    $ProgramVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ProgramPath).FileVersion
    Write-Host "Detected version: $ProgramVersion"

    $VersionMatch = $false
    if ($TargetVersion.Contains('*')) {
        # Wildcard match (e.g., "7.4.*")
        if ($ProgramVersion -like $TargetVersion) {
            $VersionMatch = $true
        }
    }
    else {
        # Exact or newer version is acceptable — prevents detection failures
        # when FortiClient auto-updates ahead of the Intune package
        try {
            $VersionMatch = ([version]$ProgramVersion -ge [version]$TargetVersion)
        }
        catch {
            # Fallback to string comparison if version parsing fails
            $VersionMatch = ($ProgramVersion -eq $TargetVersion)
        }
    }

    if (-not $VersionMatch) {
        Write-Host "Version mismatch: found $ProgramVersion, expected $TargetVersion or newer"
        exit 1
    }

    # --- Check the VPN profile ---
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\$ProfileName"
    if (-not (Test-Path $RegPath)) {
        Write-Host "VPN profile '$ProfileName' missing. Attempting self-healing..."

        # Detect FCConfig.exe path
        $ConfigToolPaths = @(
            "C:\Program Files\Fortinet\FortiClient\FCConfig.exe",
            "C:\Program Files (x86)\Fortinet\FortiClient\FCConfig.exe"
        )
        $ConfigToolPath = $ConfigToolPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $ConfigToolPath) { throw "FCConfig.exe not found for self-healing" }

        # Import VPN configuration
        $ConfigFilePath = Join-Path $PSScriptRoot $ConfigFile
        if (-not (Test-Path $ConfigFilePath)) { throw "Configuration file not found: $ConfigFilePath" }

        Write-Host "Re-importing VPN profile..."
        Start-Process $ConfigToolPath -ArgumentList "-m vpn -f `"$ConfigFilePath`" -o import -p `"$Password`"" -Wait
        Start-Sleep -Seconds 3
    }

    # --- Check the profile again ---
    if (Test-Path $RegPath) {
        Write-Host "FortiClient VPN detected with profile '$ProfileName'."
        exit 0
    }
    else {
        Write-Host "Self-healing of VPN profile failed."
        exit 1
    }
}
catch {
    Write-Error "Detection/self-healing failed: $_"
    exit 1
}
finally {
    # Optional: logging or cleanup actions
}
