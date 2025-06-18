# MicroK8s, Helm, and Cert-Manager Setup Script

This script automates the installation and configuration of a complete, ready-to-use MicroK8s environment on a Linux system. It's designed to be idempotent, meaning it can be run multiple times without causing issues, and it automatically handles user permissions for a seamless setup in a single execution.

The script installs and configures the following components:
1.  **MicroK8s:** A lightweight, CNCF-certified Kubernetes distribution.
2.  **Helm:** The package manager for Kubernetes.
3.  **Cert-Manager:** A Kubernetes add-on to automate the management and issuance of TLS certificates.

---
## Features ✨

* **Idempotent:** The script can be run multiple times. It checks for existing installations and configurations and only makes changes when necessary.
* **Automated Permission Handling:** Automatically adds the current user to the `microk8s` group and re-executes itself to apply the new permissions without manual intervention.
* **Component Enablement:** Enables essential MicroK8s add-ons, including `dns`, `hostpath-storage`, `ingress`, and `helm3`.
* **Alias Creation:** Sets up convenient `kubectl` and `helm` aliases in `~/.bash_aliases` to avoid repetitive typing.
* **Status Waits:** Includes waits to ensure that MicroK8s and its components are fully ready before proceeding to the next steps.

---
## Prerequisites

* A Linux system that supports `snap`.
* `sudo` or root privileges.
* The `whoami` and `usermod` commands must be available.

---
## Usage 🚀

1.  **Save the script** to a file named `setup_microk8s.sh`.

2.  **Make the script executable**:
    ```bash
    chmod +x setup_microk8s.sh
    ```

3.  **Run the script**:
    ```bash
    ./setup_microk8s.sh
    ```
    The script will prompt for your password for `sudo` commands.

---
## How It Works ⚙️

The script is divided into several main steps:

### 1. MicroK8s Installation & Configuration

* Installs the MicroK8s snap package.
* Checks if the current user is part of the `microk8s` group.
    * If not, it adds the user to the group and then **re-executes itself** using `sg microk8s -c "$0 $*"`. This is a key step that ensures the rest of the script runs with the correct group permissions, avoiding the need to log out and log back in.
* Creates the `~/.kube` directory and sets the correct ownership.
* Waits for the MicroK8s services to be fully ready.
* Enables the `dns`, `hostpath-storage`, `ingress`, and `helm3` addons.

### 2. Helm Configuration

* Adds a shell alias `helm='microk8s helm3'` to `~/.bash_aliases` for easy access to the Helm binary included with MicroK8s.
* Verifies that Helm is installed and operational.

### 3. Cert-Manager Installation

* Adds the official Jetstack Helm repository, which is required to install Cert-Manager.
* Updates the Helm repositories to ensure the latest chart information is available.
* Installs or upgrades Cert-Manager in its own namespace (`cert-manager`) using the `helm upgrade --install` command, which makes this step idempotent.
* Waits for the Cert-Manager pods to become ready before completing.

---
## ⚠️ Important Post-Installation Steps

After the script finishes, you must perform two manual steps to start using the environment:

1.  **Activate the Aliases**: For the `kubectl` and `helm` aliases to work, you must either:
    * **Close and reopen your terminal**, or
    * Source the aliases file in your current session:
        ```bash
        source ~/.bash_aliases
        ```

2.  **Create AWS Credentials Secret**: To allow Cert-Manager to solve DNS-01 challenges using Route 53, you need to provide it with AWS credentials. Create the Kubernetes secret by running the following command, **replacing `YOUR_AWS_SECRET_ACCESS_KEY` with your actual key**:

    ```bash
    kubectl -n cert-manager create secret generic harbor-letsencrypt-route53-credentials \
      --from-literal=harbor-letsencrypt-route53-secret-access-key='YOUR_AWS_SECRET_ACCESS_KEY'
    ```

---
## Troubleshooting 🔧

If you encounter issues from a previous failed installation, you can completely remove MicroK8s and start over. Run the following command to purge the snap package and all its data:

```bash
sudo snap remove microk8s --purge