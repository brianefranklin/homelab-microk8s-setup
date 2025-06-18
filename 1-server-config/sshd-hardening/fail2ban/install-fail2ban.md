Here are the steps to install and configure Fail2Ban on Ubuntu 24.04 for the OpenSSH service with aggressive blocking:

1.  **Update your package list:**
    ```bash
    sudo apt update
    ```

2.  **Install Fail2Ban:**
    ```bash
    sudo apt install fail2ban
    ```

3.  **Create a local configuration file:**
    Fail2Ban uses `.conf` files for default configurations and `.local` files for overrides. It's best practice to create a `.local` file so your changes aren't overwritten during updates.
    ```bash
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    ```

4.  **Edit the local configuration file:**
    Open the `jail.local` file in a text editor.
    ```bash
    sudo nano /etc/fail2ban/jail.local
    ```

5.  **Configure the `[DEFAULT]` section (Optional but recommended):**
    You can set global parameters here. For aggressive blocking, you might want to decrease `bantime` (how long an IP is banned) and `findtime` (time window for failed attempts) and increase `maxretry` (number of failed attempts before banning).

    Find or add these lines and adjust the values:
    ```ini
    [DEFAULT]
    # Ban time in seconds (e.g., 1 hour)
    bantime = 3600

    # Find time in seconds (e.g., 10 minutes)
    findtime = 600

    # Max retries before banning
    maxretry = 3

    # Action to take (e.g., iptables-allports)
    # action = %(action_)s
    