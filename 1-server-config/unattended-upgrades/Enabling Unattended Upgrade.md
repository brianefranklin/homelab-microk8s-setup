# configure-unattended-upgrade.sh

This script automates the installation and configuration of `unattended-upgrades` on a Debian-based Linux system (e.g., Ubuntu). It sets up automatic security updates, removal of unused dependencies, scheduled reboots, and a download speed limit.

## Overview

The script performs the following actions:

1.  **Installation**: Installs the `unattended-upgrades` package if it's not already present.
2.  **Initial Configuration**: Runs `sudo dpkg-reconfigure --priority=low unattended-upgrades` to allow for initial setup choices (though the script later overwrites specific settings).
3.  **Backup**: Creates a timestamped backup of the existing `unattended-upgrades` configuration file (`/etc/apt/apt.conf.d/50unattended-upgrades`) in the current user's home directory.
4.  **Configuration Updates**: Modifies `/etc/apt/apt.conf.d/50unattended-upgrades` to:
    *   Enable `Unattended-Upgrade::Remove-Unused-Dependencies "true";`
    *   Enable `Unattended-Upgrade::Automatic-Reboot "true";`
    *   Enable `Unattended-Upgrade::Automatic-Reboot-WithUsers "true";` (Allows reboot even if users are logged in)
    *   Set `Unattended-Upgrade::Automatic-Reboot-Time "05:00";`
    *   Set `Acquire::http::Dl-Limit "50000";` (Download limit in KB/sec, e.g., 50MB/s)
5.  **Verification**:
    *   Displays a `diff` between the backup and the newly modified configuration file.
    *   Runs `sudo unattended-upgrades --dry-run` to test the configuration.

## Prerequisites

*   A Debian-based Linux system (e.g., Ubuntu).
*   `sudo` privileges are required to install packages and modify system configuration files.

## Configuration

The script applies a predefined "production" configuration directly. If you need to change specific values (like the reboot time or download limit), you will need to modify the `sed` commands within the `configure-unattended-upgrade.sh` script itself.

Key hardcoded values:
*   **Automatic Reboot Time**: `05:00`
*   **Download Speed Limit**: `50000` KB/sec

## Usage

1.  **Navigate to Script Directory (Optional)**:
    ```bash
    cd /path/to/script/directory
    ```
2.  **Make Executable**:
    If the script is not already executable, run:
    ```bash
    chmod +x configure-unattended-upgrade.sh
    ```
3.  **Run the Script**:
    Execute the script with `sudo` privileges:
    ```bash
    sudo ./configure-unattended-upgrade.sh
    ```

The script will output the backup location, confirm updates, show the changes made, and then perform a dry run.

## Important Notes

*   **Backup**: A backup of your original `50unattended-upgrades` configuration is created in your home directory (e.g., `~/50unattended-upgrades.bak.YYYYMMDDHHMMSS`).
*   **Automatic Reboots**: This script configures the system to reboot automatically at 5 AM if updates require it. Ensure this is acceptable for your environment.
*   **Review Changes**: Pay attention to the `diff` output to understand exactly what changes were made to your system's configuration.
*   **Dry Run**: The `--dry-run` command at the end helps verify the configuration without actually performing upgrades. Check its output for any errors or warnings. (This command also applies the configuraiton changes by forcing unattended-upgrades to read the current configuration file. )

This script provides a quick way to apply a common set of `unattended-upgrades` settings. Always review configurations applied to your systems.