# README: Enabling 2FA for SSH on Ubuntu Servers

This document outlines the standard procedure for enhancing server security by requiring Two-Factor Authentication (2FA) for SSH access. This setup uses the `google-authenticator` Pluggable Authentication Module (PAM) to require a Time-based One-Time Password (TOTP) from an authenticator app, in addition to the user's SSH key.

This guide assumes you are operating as an administrative user with sudo privileges (referred to as `adminuser` in this guide, matching the `AllowUsers` directive in the provided `sshd_config`).

## Prerequisites

*   **Ubuntu Server**: A running instance of Ubuntu Server (22.04 or newer recommended).
*   **Sudo Access**: An account (`adminuser`) with `sudo` privileges.
*   **SSH Key Pair**: You must have an SSH key pair configured for `adminuser` for server access, as the provided `sshd_config` mandates public key authentication followed by the TOTP.
*   **Authenticator App**: An authenticator application on a mobile device or desktop (e.g., Google Authenticator, Authy, Microsoft Authenticator).
*   **Pre-configured Files**:
    *   `sshd`: Your customized replacement configuration file for `/etc/pam.d/sshd`.
    *   `sshd_config`: Your customized replacement configuration file for `/etc/ssh/sshd_config`.

## Step 0: Transfer Configuration Files to the Server

Before configuring the server, copy your pre-made `sshd` and `sshd_config` files to the `adminuser`'s home directory on the server.

1.  On your local machine, open a terminal and navigate to the directory containing your `sshd` and `sshd_config` files.
2.  Run the following `scp` command, replacing `<server_ip_or_hostname>` with your server's actual IP address or hostname:
    ```bash
    scp sshd sshd_config adminuser@<server_ip_or_hostname>:~
    ```
3.  After the transfer is complete, SSH into the remote server as `adminuser` to continue the setup.

## Step 1: Install the Google Authenticator PAM Module

First, install the necessary library from the official Ubuntu repositories.


```bash
sudo apt update
sudo apt install libpam-google-authenticator

Step 2: Configure 2FA for Your User Account
Run the google-authenticator command as the user you want to enroll in 2FA (e.g., adminuser). Do not run this with sudo.

bash
sudo apt install libpam-google-authenticator
```

## Step 2: Configure 2FA for Your User Account

Run the `google-authenticator` command as the user you want to enroll in 2FA (e.g., `adminuser`). **Do not run this with `sudo`**.

```bash
google-authenticator
```

This will launch an interactive setup process:

*   Scan the QR code with your authenticator app.
*   Save the emergency scratch codes in a secure location.
*   Answer the configuration questions. These are the recommended answers based on common practice:
Do you want me to update your "/home/adminuser/.google_authenticator" file? (y/n) y
Do you want to disallow multiple uses of the same authentication token? This restricts you to one login every 30 seconds, but it increases your chances to notice or even prevent man-in-the-middle attacks (y/n) y
By default, tokens are good for 30 seconds and in order to compensate for possible time-skew between client and server, we allow an extra token before and after the current time. If you experience problems with poor time synchronization, you can increase the window from its default size of 1:30min to about 4min. Do you want to do so? (y/n) n
If the computer clock drifts significantly, it could result in failing logins. In this case, please contact your administrator and ask them to synchronize the clock. If you enable rate-limiting, the authentication module will reject logins from attackers who try to brute-force the secret key. Do you want to enable rate-limiting for the authentication module? (y/n) y
Step 3: Deploy the SSH PAM Configuration
Move the sshd file you uploaded into the /etc/pam.d/ directory. This file configures PAM to use pam_google_authenticator.so.

Back up the original file:
bash
*   Scan the QR code with your authenticator app.
*   Save the emergency scratch codes in a secure location.
*   Answer the configuration questions. These are the recommended answers based on common practice:
    *   `Do you want me to update your "/home/adminuser/.google_authenticator" file? (y/n)` **y**
    *   `Do you want to disallow multiple uses of the same authentication token? This restricts you to one login every 30 seconds, but it increases your chances to notice or even prevent man-in-the-middle attacks (y/n)` **y**
    *   `By default, tokens are good for 30 seconds and in order to compensate for possible time-skew between client and server, we allow an extra token before and after the current time. If you experience problems with poor time synchronization, you can increase the window from its default size of 1:30min to about 4min. Do you want to do so? (y/n)` **n**
    *   `If the computer clock drifts significantly, it could result in failing logins. In this case, please contact your administrator and ask them to synchronize the clock. If you enable rate-limiting, the authentication module will reject logins from attackers who try to brute-force the secret key. Do you want to enable rate-limiting for the authentication module? (y/n)` **y**

## Step 3: Deploy the SSH PAM Configuration

Move the `sshd` file you uploaded into the `/etc/pam.d/` directory. This file configures PAM to use `pam_google_authenticator.so`.

1.  Back up the original file:
    ```bash
sudo cp /etc/pam.d/sshd /etc/pam.d/sshd.bak
Move the new configuration file into place:
bash
    ```
2.  Move the new configuration file into place:
    ```bash
sudo mv ~/sshd /etc/pam.d/sshd
Set the correct ownership and permissions, which is critical for security:
bash
    ```
3.  Set the correct ownership and permissions, which is critical for security:
    ```bash
sudo chown root:root /etc/pam.d/sshd
sudo chmod 644 /etc/pam.d/sshd
Step 4: Deploy the SSH Daemon Configuration
Next, deploy the sshd_config file you uploaded. This file configures the SSH daemon to use public key authentication followed by keyboard-interactive authentication (which PAM will handle for the TOTP).

Back up the original configuration:
bash
    ```

## Step 4: Deploy the SSH Daemon Configuration

Next, deploy the `sshd_config` file you uploaded. This file configures the SSH daemon to use public key authentication followed by keyboard-interactive authentication (which PAM will handle for the TOTP).

1.  Back up the original configuration:
    ```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
Move the new configuration file into place:
bash
    ```
2.  Move the new configuration file into place:
    ```bash
sudo mv ~/sshd_config /etc/ssh/sshd_config
Set the correct ownership and permissions:
bash
    ```
3.  Set the correct ownership and permissions:
    ```bash
sudo chown root:root /etc/ssh/sshd_config
sudo chmod 600 /etc/ssh/sshd_config
Step 5: Restart and Enable the SSH Service
Apply all the changes by restarting the SSH service.

bash
    ```

## Step 5: Restart and Enable the SSH Service

Apply all the changes by restarting the SSH service.

```bash
sudo systemctl restart sshd
```

It is also highly recommended to ensure the SSH service starts on boot:

bash
```bash
sudo systemctl enable sshd
```

**Important:** Before disconnecting your current session, test the SSH login from a new terminal window to ensure 2FA is working as expected and you are not locked out.

The New Login Process
With the provided sshd_config (which includes AuthenticationMethods publickey,keyboard-interactive) and sshd PAM configuration, the login process will be:

You will first authenticate using your SSH key as usual.
After successful SSH key authentication, you will be prompted for a Verification code:.
Enter the 6-digit code from your authenticator app to complete the login.
## The New Login Process

With the provided `sshd_config` (which includes `AuthenticationMethods publickey,keyboard-interactive`) and `sshd` PAM configuration, the login process will be:

1.  You will first authenticate using your SSH key as usual.
2.  After successful SSH key authentication, you will be prompted for a `Verification code:`.
3.  Enter the 6-digit code from your authenticator app to complete the login.

This configuration enforces that both a valid SSH key and a valid TOTP are required for access.

