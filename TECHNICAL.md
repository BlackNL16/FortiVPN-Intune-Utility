# FortiVPN Intune Utility — Technical Reference

> This document is intended for IT engineers and technicians who need to understand the internal workings of this utility, deploy the generated packages, or extend the tooling.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                 FortiClient-Intune-Packager.ps1              │
│                      (Orchestrator)                          │
├──────────────┬───────────────┬────────────────┬──────────────┤
│  config.json │  secrets.json │  FortiUtils.psm1  │  Templates/  │
│  (customers) │  (passwords)  │  (shared logging) │  (*_template.*)│
└──────┬───────┴───────┬───────┴────────┬───────────┴──────┬───┘
       │               │                │                  │
       ▼               ▼                ▼                  ▼
  Validation      Password         Color-coded        Auto-discovered
  (Name,VPN,      lookup by        Write-Log with     & variable-
   Version)       VPNProfile       file + console     substituted
                   key match       output             per customer
       │
       ▼
┌──────────────────────────────────────────┐
│          Output/<CustomerName>/          │
├──────────────────────────────────────────┤
│  FortiClientVPN.exe        (from Base)   │
│  <Customer>_VPN.conf       (FCConfig)    │
│  install.ps1               (template)    │
│  uninstall.ps1             (template)    │
│  check.ps1                 (template)    │
│  intune_deployment.txt     (template)    │
│  <Customer>_FortiClientVPN.intunewin     │
└──────────────────────────────────────────┘
```

---

## Script Execution Flow

### `FortiClient-Intune-Packager.ps1`

```
1. Parse parameters (ConfigPath, SecretsPath, CustomerName, AutoApprove, Force, SkipIntuneWin)
2. Set paths relative to script location ($PSScriptRoot)
3. Import FortiUtils.psm1 (shared logging)
4. Load config.json → validate schema (Name, VPNProfile, Version required)
5. Load secrets.json → password lookup table
6. Customer selection:
   ├── If -CustomerName provided → filter directly
   └── Else → show interactive numbered menu (A=all, or comma-separated numbers)
7. For each selected customer:
   │  a. Overwrite protection check (-Force skips prompt)
   │  b. Registry check: HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\<VPNProfile>
   │  c. Export VPN profile via FCConfig.exe -o export
   │  d. Manual verification prompt (unless -AutoApprove)
   │  e. Delete profile from registry (for clean testing)
   │  f. Copy BaseFiles/* to Output/<Customer>/
   │  g. Auto-discover *_template.* files → substitute {{placeholders}} → write output
   │  h. Package with IntuneWinAppUtil.exe (unless -SkipIntuneWin)
   └── Return status string per customer
8. Print summary table (Customer | Status)
9. Write log file (forti_packager.log)
```

---

## FCConfig.exe Reference

The script uses Fortinet's `FCConfig.exe` CLI tool for profile export/import. It is auto-detected at:

```
C:\Program Files\Fortinet\FortiClient\FCConfig.exe
C:\Program Files (x86)\Fortinet\FortiClient\FCConfig.exe
```

### Commands Used

| Operation | Command |
|---|---|
| **Export** | `FCConfig.exe -m vpn -f "<output.conf>" -o export -p "<password>"` |
| **Import** | `FCConfig.exe -m vpn -f "<input.conf>" -o import -p "<password>"` |

The `-p` password is used to encrypt/decrypt the `.conf` file. The same password must be used for both export and import.

---

## Registry Paths

FortiClient stores IPSec VPN tunnel configurations in the Windows Registry:

```
HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels\<ProfileName>
```

The scripts use this path to:
- **Verify** a profile exists before export (`FortiClient-Intune-Packager.ps1`)
- **Delete** a profile after export for clean testing (`FortiClient-Intune-Packager.ps1`)
- **Detect** whether a profile needs re-import on endpoints (`check.ps1`)

---

## Generated Scripts (What Gets Deployed)

### `install.ps1`

Runs on the target machine via Intune. Executes as SYSTEM context.

| Step | Action |
|---|---|
| 1 | Start transcript → `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\FortiClientVPN-install.log` |
| 2 | Run `FortiClientVPN.exe /quiet /norestart` |
| 3 | Wait 5 seconds for installer to finish registering |
| 4 | Locate `FCConfig.exe` (x64/x86) |
| 5 | Import `.conf` file with password |
| 6 | Exit 0 (success) or 1 (failure) |

**Intune install command:**
```
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
```

---

### `uninstall.ps1`

Searches the uninstall registry for FortiClient and removes it silently.

| Step | Action |
|---|---|
| 1 | Start transcript → `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\FortiClientVPN-uninstall.log` |
| 2 | Search `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` (x64 + WOW6432Node) |
| 3 | If MSI-based → `msiexec.exe /x <ProductCode> /qn /norestart` |
| 4 | If EXE-based → `<UninstallString> /quiet /norestart` |
| 5 | Exit 0 always (idempotent — no error if already uninstalled) |

**Intune uninstall command:**
```
powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1
```

---

### `check.ps1` (Detection + Self-Healing)

Used as an Intune **Custom Script Detection Rule**. Runs periodically on the endpoint.

| Step | Action |
|---|---|
| 1 | Locate `FortiClient.exe` (x64/x86) |
| 2 | Read `FileVersion` → compare against `{{Version}}` (supports wildcard with `*`) |
| 3 | Check registry for VPN tunnel profile |
| 4 | **If profile missing** → auto-import `.conf` via FCConfig.exe (self-healing) |
| 5 | Re-check registry |
| 6 | Exit 0 (detected) or 1 (not detected / self-healing failed) |

**Version matching logic:**
- If `Version` contains `*` (e.g., `7.4.*`) → uses `-like` wildcard matching
- If `Version` is exact (e.g., `7.4.3.1790`) → uses `[version]` comparison: **equal or newer passes** (prevents detection failures when FortiClient auto-updates ahead of Intune)

**Intune detection rule:**
- Type: Custom Script
- Upload: `check.ps1`
- Run as: SYSTEM (64-bit)

---

## Template Engine

Templates are any file in `Templates/` matching the pattern `*_template.*`. They are auto-discovered at runtime via `Get-ChildItem -Filter "*_template.*"`.

### Processing Pipeline

```
Templates/check_template.ps1
    │
    ├── Read file line by line
    ├── For each line, replace all {{placeholder}} tokens
    ├── Write to Output/<Customer>/check.ps1  (strip "_template" from name)
    │
    └── Supported placeholders:
        {{CustomerName}}  →  config.json → Name
        {{VpnProfile}}    →  config.json → VPNProfile
        {{Version}}       →  config.json → Version
        {{Password}}      →  secrets.json → <VPNProfile key>
```

### Adding a New Template

1. Create file: `Templates/myfile_template.ext`
2. Use `{{placeholders}}` in the content
3. Run the script — output will be `Output/<Customer>/myfile.ext`

No code changes required.

---

## Intune Deployment Configuration

When creating the Win32 app in Intune, use these settings:

| Setting | Value |
|---|---|
| **App package file** | `<Customer>_FortiClientVPN.intunewin` |
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File .\install.ps1` |
| **Uninstall command** | `powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1` |
| **Install behavior** | System |
| **Detection rules** | Custom script → upload `check.ps1` |
| **Detection script behavior** | Run script as 64-bit process: Yes |
| **Return codes** | 0 = Success, 1 = Failed |

---

## Logging

### Packager Log (Build Machine)

| Log | Location |
|---|---|
| Main packager | `<project>/forti_packager.log` |
| Import test | `<project>/forti_import_test.log` |

Log format: `[2026-03-03 21:00:00] [INFO] Message`

Logs are recreated on each run (previous log is deleted).

### Endpoint Logs (Target Machines)

| Script | Log Location |
|---|---|
| `install.ps1` | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\FortiClientVPN-install.log` |
| `uninstall.ps1` | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\FortiClientVPN-uninstall.log` |
| `check.ps1` | No log file (stdout captured by Intune agent) |

Endpoint logs use `Start-Transcript` for full command tracing.

---

## `import-test.ps1` — Testing Imports

This script tests an exported profile can be re-imported correctly without permanently modifying your FortiClient configuration.

### Execution Flow

```
1. Load config.json + secrets.json
2. If no -ProfileName → show interactive profile selector
3. Locate the exported .conf file in Output/<Customer>/
4. Backup current FortiClient config → %TEMP%\FortiClient_Backup_<timestamp>.conf
5. Import the customer's .conf with password
6. Verify profile exists in registry
7. Wait for user confirmation
8. Restore original config from backup (runs in finally block — always executes)
9. Delete backup file
```

### Parameters

| Parameter | Description |
|---|---|
| `-ProfileName` | Skip the menu and test a specific profile directly |
| `-Verbose` | Show all log messages on screen (normally only written to file) |
| `-Restore` | Skip the test — just restore from a backup .conf file |

---

## Security Considerations

| Concern | Current State | Mitigation |
|---|---|---|
| `secrets.json` in repo | Gitignored, not committed | Ship `secrets.example.json` instead |
| Plaintext passwords in generated scripts | Required by FCConfig.exe | Deploy via Intune (encrypted in transit, SYSTEM-only on endpoint) |
| `.conf` file encryption | Encrypted with password by FCConfig.exe | Password required for import |
| Registry access | HKLM requires admin/SYSTEM | Scripts run as SYSTEM via Intune |

---

## Module: `FortiUtils.psm1`

Shared PowerShell module imported by both scripts.

### Exported Functions

#### `Write-Log`

```powershell
Write-Log -Message "text" -Level "INFO" -LogFile "path.log"
```

| Parameter | Default | Description |
|---|---|---|
| `-Message` | (required) | Log message text |
| `-Level` | `INFO` | One of: `INFO`, `WARN`, `ERROR`, `DEBUG` |
| `-LogFile` | `$null` | If set, appends to this file |

**Console colors:** INFO=Green, WARN=Yellow, ERROR=Red, DEBUG=DarkGray

Both scripts define a local `Write-Log` wrapper that calls `FortiUtils\Write-Log` with the appropriate `$LogPath` for that script.

---
