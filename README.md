# FortiVPN Intune Utility

## What Does This Script Do?

This PowerShell tool automates creating FortiClient VPN deployment packages for Microsoft Intune. Instead of manually setting up VPN profiles on every machine, you configure everything once and the script generates ready-to-deploy packages for each customer.

**In short:** You configure → the script exports → you get a `.intunewin` package → you upload to Intune → done.

---

## Before You Start (Prerequisites)

Make sure you have **all** of the following ready:

| Requirement | Where / How |
|---|---|
| **PowerShell 5.1+** | Comes pre-installed on Windows 10/11. Open PowerShell and type `$PSVersionTable.PSVersion` to check. |
| **FortiClient installed** | Must be installed on the machine where you run this script. |
| **VPN profiles configured** | Each customer's VPN profile must already be manually configured inside FortiClient **before** running the script. |
| **FortiClientVPN.exe** | Place the FortiClient installer `.exe` in the `BaseFiles/` folder. |
| **IntuneWinAppUtil.exe** | Already included in the `intunewin/` folder. |

---

## Quick Start (Step by Step)

### Step 1: Set Up Your Secrets File

The project ships with `secrets.example.json`. You need to create your own `secrets.json`:

1. **Copy** `secrets.example.json` and rename the copy to `secrets.json`
2. **Edit** `secrets.json` and replace the placeholder passwords with real ones

**`secrets.example.json` (template):**
```json
{
    "customer1": "YourPasswordHere",
    "customer2": "YourPasswordHere",
    "vpnuser": "YourPasswordHere"
}
```

**Your `secrets.json` (real passwords):**
```json
{
    "customer1": "ActualP@ssw0rd!",
    "customer2": "An0therP@ss#",
    "vpnuser": "Secr3tP@ss!"
}
```

> ⚠️ **Important:** The key names (e.g. `"customer1"`) must match the `VPNProfile` values in `config.json`. If they don't match, the script will skip that customer.

> ⚠️ **Important:** `secrets.json` is gitignored — it will **not** be uploaded to Git. Never commit real passwords.

---

### Step 2: Configure Your Customers

Edit `config.json` to define your customers. Each customer needs **exactly three fields**:

```json
[
  {
    "Name": "customer1",
    "VPNProfile": "customer1",
    "Version": "7.4.3.1790"
  },
  {
    "Name": "customer2",
    "VPNProfile": "customer2",
    "Version": "7.4.*"
  }
]
```

| Field | What It Does | Example |
|---|---|---|
| `Name` | Folder name in `Output/` and shown in the menu | `"AcmeCorp"` |
| `VPNProfile` | Exact name of the VPN profile in FortiClient | `"AcmeCorp"` |
| `Version` | Expected FortiClient version on target machines. Use `*` as wildcard. | `"7.4.3.1790"` or `"7.4.*"` |

> ⚠️ **Common mistake:** The `VPNProfile` value must exactly match the profile name configured in FortiClient AND the key name in `secrets.json`.

---

### Step 3: Run the Script

Open PowerShell, navigate to the project folder, and run:

```powershell
.\FortiClient-Intune-Packager.ps1
```

**What happens next:**

1. The script loads your config and secrets
2. You see a **customer selection menu**:
   ```
   Available customers:
   --------------------
     1. customer1
     2. customer2
     3. vpnuser

     A. Process ALL customers

   Select customers (comma-separated numbers, or 'A' for all):
   ```
3. Type `A` to process everyone, or type specific numbers like `1,3` to pick only some
4. For each customer, the script:
   - Exports the VPN profile from FortiClient
   - Asks you to verify the export (unless you used `-AutoApprove`)
   - Generates install, uninstall, and detection scripts from templates
   - Creates the `.intunewin` package
5. At the end, a **summary table** is printed:
   ```
   ============================
     PACKAGING SUMMARY
   ============================

   Customer    Status
   --------    ------
   customer1   Success
   customer2   Success
   vpnuser     Skipped (no password)
   ```

---

### Step 4: Upload to Intune

After the script completes, check the `Output/` folder. Each customer gets their own subfolder:

```
Output/
├── customer1/
│   ├── customer1_FortiClientVPN.intunewin   ← Upload this to Intune
│   ├── customer1_VPN.conf                   ← VPN profile config
│   ├── install.ps1                          ← Install command script
│   ├── uninstall.ps1                        ← Uninstall command script
│   ├── check.ps1                            ← Detection/self-healing script
│   └── intune_deployment.txt                ← Copy-paste commands for Intune
```

Open `intune_deployment.txt` for the exact install/uninstall commands to paste into Intune.

---

## Command-Line Parameters

You can skip the interactive menu and automate everything with parameters:

| Parameter | What It Does | Example |
|---|---|---|
| `-CustomerName` | Only process specific customer(s). Skips the menu. | `-CustomerName "customer1","customer2"` |
| `-AutoApprove` | Skips all "Are you sure?" prompts. | `-AutoApprove` |
| `-Force` | Overwrites existing output folders without asking. | `-Force` |
| `-SkipIntuneWin` | Skips creating the `.intunewin` package. | `-SkipIntuneWin` |
| `-ConfigPath` | Use a different config file. | `-ConfigPath "C:\Configs\prod.json"` |
| `-SecretsPath` | Use a different secrets file. | `-SecretsPath "C:\Configs\secrets.json"` |

### Example Commands

```powershell
# Interactive mode (shows menu, asks for approval at each step)
.\FortiClient-Intune-Packager.ps1

# Process only one customer, no prompts, overwrite existing
.\FortiClient-Intune-Packager.ps1 -CustomerName "customer1" -AutoApprove -Force

# Process two customers, skip .intunewin packaging
.\FortiClient-Intune-Packager.ps1 -CustomerName "customer1","customer2" -SkipIntuneWin

# Fully automated: all customers, no prompts, overwrite everything
.\FortiClient-Intune-Packager.ps1 -AutoApprove -Force
```

---

## Testing an Import

Use the included test script to verify that an exported profile can be imported correctly:

```powershell
.\import-test.ps1
```

This will:
1. Back up your current FortiClient configuration
2. Import the selected customer's VPN profile
3. Verify the profile appears in the registry
4. Restore your original configuration when done

---

## Project Structure

```
.
├── FortiClient-Intune-Packager.ps1     # Main script — run this
├── import-test.ps1                     # Test script for verifying imports
├── FortiUtils.psm1                     # Shared logging module (used by both scripts)
├── config.json                         # Your customer definitions
├── secrets.json                        # Your passwords (DO NOT COMMIT)
├── secrets.example.json                # Template — copy this to secrets.json
│
├── BaseFiles/                          # Files copied into every customer folder
│   └── FortiClientVPN.exe              # FortiClient installer
│
├── Templates/                          # Script templates (auto-discovered)
│   ├── check_template.ps1              # → becomes check.ps1
│   ├── install_template.ps1            # → becomes install.ps1
│   ├── uninstall_template.ps1          # → becomes uninstall.ps1
│   └── intune_deployment_template.txt  # → becomes intune_deployment.txt
│
├── intunewin/                          # Intune packaging tool
│   └── IntuneWinAppUtil.exe
│
└── Output/                             # Generated packages (DO NOT COMMIT)
    ├── customer1/
    ├── customer2/
    └── ...
```

---

## Adding New Templates

Want to add another file to every customer's output folder? Just:

1. Create a file in `Templates/` with `_template` in the name  
   Example: `readme_template.md`
2. Use placeholders in the file content (see table below)
3. Run the script — it auto-discovers and processes the new template

| Placeholder | Gets Replaced With |
|---|---|
| `{{CustomerName}}` | Customer name from `config.json` |
| `{{VpnProfile}}` | VPN profile name from `config.json` |
| `{{Version}}` | FortiClient version from `config.json` |
| `{{Password}}` | Password from `secrets.json` |

The output filename has `_template` stripped. For example:
- `check_template.ps1` → `check.ps1`
- `readme_template.md` → `readme.md`

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Script says `secrets.json not found` | Copy `secrets.example.json` to `secrets.json` and fill in real passwords |
| Customer is skipped with `no password` | Make sure the key in `secrets.json` exactly matches the `VPNProfile` value in `config.json` |
| `FCConfig.exe not found` | FortiClient is not installed, or installed in a non-standard location |
| `VPN profile does not exist` | You need to manually configure the VPN profile in FortiClient first |
| `Invalid customer entry in config.json` | Every customer must have `Name`, `VPNProfile`, and `Version` fields |
| Output folder already exists warning | Use `-Force` to overwrite, or delete the old folder first |
| `.intunewin` file not created | Make sure `FortiClientVPN.exe` is in `BaseFiles/` and `IntuneWinAppUtil.exe` is in `intunewin/` |

---

## Console Colors

The script uses colors to help you spot issues quickly:

| Color | Meaning |
|---|---|
| 🟢 Green | INFO — everything is fine |
| 🟡 Yellow | WARN — something was skipped or needs attention |
| 🔴 Red | ERROR — something failed |
| ⚫ Gray | DEBUG — detailed diagnostic info |

---
