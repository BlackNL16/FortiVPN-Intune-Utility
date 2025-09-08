<#
.SYNOPSIS
    Installeert FortiClient VPN en importeert het geconfigureerde VPN-profiel.

.DESCRIPTION
    Dit script is bedoeld voor gebruik met Intune. Het installeert FortiClient VPN in
    stille modus en importeert vervolgens het VPN-profiel en het bijbehorende
    wachtwoord.

.EXAMPLE
    .\install.ps1
#>

param(
    [string]$InstallFile = 'FortiClientVPN.exe',
    [string]$ConfigFile = 'test_VPN.conf',
    [string]$Password = 'P@ssw0rdB'
)

$ErrorActionPreference = 'Stop'
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\FortiClientVPN-install.log"
Start-Transcript -Path $LogPath -Force

try {
    Write-Host "Starting installation of FortiClientVPN..."
    $Installer = Join-Path $PSScriptRoot $InstallFile
    if (-not (Test-Path $Installer)) { throw "Installer not found: $Installer" }

    Start-Process -FilePath $Installer -ArgumentList "/quiet /norestart" -Wait
    Write-Host "FortiClientVPN installed successfully."
    Start-Sleep -Seconds 5

    $PossiblePaths = @(
        "C:\Program Files\Fortinet\FortiClient\FCConfig.exe",
        "C:\Program Files (x86)\Fortinet\FortiClient\FCConfig.exe"
    )
    $ConfigToolPath = $PossiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $ConfigToolPath) { throw "FCConfig.exe not found." }

    $ConfigFilePath = Join-Path $PSScriptRoot $ConfigFile
    if (-not (Test-Path $ConfigFilePath)) { throw "Config file not found: $ConfigFilePath" }

    Write-Host "VPN profile importing..."
    Start-Process $ConfigToolPath -ArgumentList "-m vpn -f `"$ConfigFilePath`" -o import -p `"$Password`"" -Wait
    Write-Host "VPN profile imported successfully."
    exit 0
}
catch {
    Write-Error "Installation failed: $_"
    exit 1
}
finally {
    Stop-Transcript
}
