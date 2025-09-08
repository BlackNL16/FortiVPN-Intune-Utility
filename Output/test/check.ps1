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
    [string]$ProfileName = 'test',
    [string]$TargetVersion = '7.4.*',
    [string]$Password = 'P@ssw0rdB',
    [string]$ConfigFile = 'test_VPN.conf'
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
        Write-Host "FortiClient niet gevonden."
        exit 1
    }

    # --- Check version ---
    $ProgramVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ProgramPath).FileVersion
    Write-Host "Gedetecteerde versie: $ProgramVersion"

    $VersionMatch = $false
    if ($TargetVersion -like '*') {
        if ($ProgramVersion -like $TargetVersion) {
            $VersionMatch = $true
        }
    } else {
        if ($ProgramVersion -eq $TargetVersion) {
            $VersionMatch = $true
        }
    }

    if (-not $VersionMatch) {
        Write-Host "Versie komt niet overeen: verwacht $TargetVersion"
        exit 1
    }

    # --- Controleer het VPN-profiel ---
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\$ProfileName"
    if (-not (Test-Path $RegPath)) {
        Write-Host "VPN-profiel '$ProfileName' ontbreekt. Zelfherstel wordt geprobeerd..."

        # Detecteer FCConfig.exe-pad
        $ConfigToolPaths = @(
            "C:\Program Files\Fortinet\FortiClient\FCConfig.exe",
            "C:\Program Files (x86)\Fortinet\FortiClient\FCConfig.exe"
        )
        $ConfigToolPath = $ConfigToolPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $ConfigToolPath) { throw "FCConfig.exe niet gevonden voor zelfherstel" }

        # Importeer VPN-configuratie
        $ConfigFilePath = Join-Path $PSScriptRoot $ConfigFile
        if (-not (Test-Path $ConfigFilePath)) { throw "Configuratiebestand niet gevonden: $ConfigFilePath" }

        Write-Host "VPN-profiel opnieuw importeren..."
        Start-Process $ConfigToolPath -ArgumentList "-m vpn -f `"$ConfigFilePath`" -o import -p `"$Password`"" -Wait
        Start-Sleep -Seconds 3
    }

    # --- Controleer het profiel opnieuw ---
    if (Test-Path $RegPath) {
        Write-Host "FortiClient VPN gedetecteerd met profiel '$ProfileName'."
        exit 0
    } else {
        Write-Host "Zelfherstel van VPN-profiel is mislukt."
        exit 1
    }
}
catch {
    Write-Error "Detectie/zelfherstel is mislukt: $_"
    exit 1
}
finally {
    # Optioneel: logboekregistratie of opruimacties
}
