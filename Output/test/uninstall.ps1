<#
.SYNOPSIS
    Verwijdert FortiClient VPN en de bijbehorende registry-instellingen.

.DESCRIPTION
    Dit script is bedoeld voor gebruik met Intune. Het zoekt naar de
    uninstaller in het register en voert de verwijdering in stille modus uit.

.EXAMPLE
    .\uninstall.ps1
#>
$ErrorActionPreference = 'Stop'
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\FortiClientVPN-uninstall.log"
Start-Transcript -Path $LogPath -Force

try {
    Write-Host "Starting uninstallation of FortiClientVPN..."
    
    # --- Zoek uninstall registry entries (x64 + x86) ---
    $RegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $UninstallString = $null
    $App = $null

    foreach ($Path in $RegPaths) {
        $App = Get-ItemProperty $Path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "FortiClient*" }
        if ($App -and $App.UninstallString) {
            $UninstallString = $App.UninstallString
            break
        }
    }

    if ($UninstallString) {
        Write-Host "Found uninstall command: $UninstallString"
        if ($UninstallString -match "MsiExec") {
            Start-Process "msiexec.exe" -ArgumentList "/x $($App.PSChildName) /qn /norestart" -Wait
        } else {
            Start-Process "cmd.exe" -ArgumentList "/c `"$UninstallString /quiet /norestart`"" -Wait
        }
        Write-Host "FortiClientVPN uninstalled successfully."
    } else {
        Write-Host "FortiClient not found, nothing to uninstall."
    }
    
    exit 0
}
catch {
    Write-Error "Uninstallation failed: $_"
    exit 1
}
finally {
    Stop-Transcript
}
