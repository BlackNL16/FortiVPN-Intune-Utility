# Intune Deployment Instructions

This document provides a step-by-step guide for deploying the FortiClient VPN package to the Microsoft Intune Company Portal. All necessary files for deployment are located in the customer's output folder.

---

## Package Contents

The output folder for each customer contains the following files:

- **FortiClientVPN.exe**  
  The installer for the FortiClient VPN client.

- **<customer_name>_VPN.conf**  
  The configuration file for the VPN profile.

- **<customer_name>_FortiClientVPN.intunewin**  
  The complete, ready-to-deploy Intune application package.

- **install.ps1**  
  PowerShell script that performs the installation and imports the VPN profile.

- **uninstall.ps1**  
  PowerShell script that handles the uninstallation of the client.

- **check.ps1**  
  PowerShell script that acts as the detection rule and provides a self-healing function.

- **IntuneDeployment.txt**  
  Text file containing the exact commands required for the Intune application setup.

---

## Deployment Steps

### Step 1: Upload the Application Package

1. Log in to the [Microsoft Endpoint Manager admin center](https://endpoint.microsoft.com/).
2. Navigate to **Apps > All apps** and click **+ Add**.
3. Select **Windows app (Win32)** and click **Select**.
4. In the **App package file** section, click the browse button and upload the `<customer_name>_FortiClientVPN.intunewin` file.

### Step 2: Configure the App

1. On the **Program** tab, copy the **Install command** and **Uninstall command** directly from the `IntuneDeployment.txt` file and paste them into the corresponding fields.
2. Set the **Install behavior** to **System**.

### Step 3: Configure the Detection Rule

1. On the **Detection rules** tab, select **Use a custom detection script**.
2. Click the browse button next to **Script file** and upload the `check.ps1` script.
3. Ensure the settings are correct for your environment and click **OK**.

### Step 4: Finalize and Assign

1. Complete any remaining required fields (e.g., **Description**, **Publisher**, etc.).
2. Review all settings and click **Create** to add the application to Intune.
3. Once created, assign the application to your target user or device groups.

---