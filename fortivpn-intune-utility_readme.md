# FortiVPN Intune Utility

## Synopsis

This PowerShell-based utility automates the creation of FortiClient VPN packages, ready for deployment via Microsoft Intune. It streamlines the process of exporting profiles, securely managing credentials, and generating a complete, self-healing application package for each customer.

---

## Key Features

- **Modular Design:**  
  Separates configuration data (`config.json`), sensitive secrets (`secrets.json`), and script templates for a clean and scalable project structure.

- **Secure Credential Handling:**  
  Passwords are stored in a separate `secrets.json` file, outside of the main script.

- **Automated Packaging:**  
  Generates a single `.intunewin` file for each customer, including a self-healing detection script and automated install/uninstall process.

- **Self-Healing Capabilities:**  
  The generated `check.ps1` script can automatically detect and re-import a missing VPN profile, ensuring a consistent user experience.

---

## Prerequisites

- **PowerShell 5.1 or newer:**  
  The script is built on modern PowerShell cmdlets.

- **FortiClientVPN.exe:**  
  The FortiClient VPN installer file must be placed in the `BaseFiles` directory.

- **IntuneWinAppUtil.exe:**  
  The Microsoft Intune App Packaging Tool must be present in the `intunewin` directory.

- **Pre-configured FortiClient:**  
  The FortiClient application must be installed on the machine running the script, and the VPN profile(s) you wish to export must be manually configured within the client beforehand.

---

## Project Structure

The project uses a clear and logical folder structure to keep all files organized:

```md
.
├── FortiClient-Intune-Packager.ps1         # Main automation script
├── config.json                             # Main customer configurations
├── secrets.json                            # Passwords and sensitive data
├── intunewin/
│   └── IntuneWinAppUtil.exe                # Microsoft Intune Packaging Tool
├── BaseFiles/
│   ├── FortiClientVPN.exe                  # Main installer, copied to each customer folder
│   └── Instructions.md                     # Deployment instructions for engineers
└── Templates/
    ├── check_template.ps1                  # Template for the detection script
    ├── install_template.ps1                # Template for the installation script
    ├── uninstall_template.ps1              # Template for the uninstallation script
    └── intune_deployment_template.txt      # Template for deployment commands
```

---

## How to Use

### 1. Configure `config.json` and `secrets.json`

- **config.json:**  
  Add the name, VPN profile, and target version for each customer.

- **secrets.json:**  
  Add the password for each corresponding VPN profile.

### 2. Run the Script

Open PowerShell, navigate to the project directory, and run:

```powershell
.\FortiClient-Intune-Packager.ps1
```

The script will guide you through the process, creating a new folder for each customer under the `Output` directory with all the necessary files for Intune deployment.

---

### Command-Line Parameters

You can also use command-line parameters for automated execution:

- `-AutoApprove`  
  Skips the manual confirmation prompts during the export process.

- `-SkipIntuneWin`  
  Skips the generation of the `.intunewin` file.

- `-ConfigPath <path>`  
  Specifies a custom path for the configuration file.

- `-SecretsPath <path>`  
  Specifies a custom path for the secrets file.

---
