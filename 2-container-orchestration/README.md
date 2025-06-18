# Harbor Installation on MicroK8s

This repository contains a set of scripts to automate the deployment of Harbor, an open-source container image registry, onto a MicroK8s Kubernetes cluster. The installation includes automatic SSL/TLS certificate provisioning from Let's Encrypt using AWS Route53 for DNS-01 challenges.

## Installation Overview

The installation process is divided into several sequential stages, each handled by scripts in correspondingly numbered directories. It's crucial to execute these stages in order, as each builds upon the previous one.

**Before you begin:**
*   Ensure you have an Ubuntu server (e.g., Ubuntu 24.04) where MicroK8s will be installed.
*   You will need an AWS account with a Route53 Hosted Zone for your domain.
*   Prepare AWS IAM credentials with permissions to modify Route53 records for DNS-01 challenges. Details for a restrictive IAM policy can be found in the `install_notes.txt` and are implemented by the script in `2-clusterissuer-install`.

## Installation Stages

Each directory contains its own `README.md` with detailed instructions for that specific stage.

1.  **`1-microk8s-install/`**:
    *   **Purpose**: Installs MicroK8s, configures user permissions, and enables essential MicroK8s addons required for Harbor and cert-manager (e.g., `dns`, `storage`, `ingress`, `helm3`).
    *   **Script**: `initialize-microk8s-cluster.sh`
    *   **Details**: See `1-microk8s-install/README.md`

2.  **`2-clusterissuer-install/`**:
    *   **Purpose**: Installs cert-manager and configures a `ClusterIssuer`. This `ClusterIssuer` uses Let's Encrypt with AWS Route53 for DNS-01 challenges to automatically issue and renew SSL/TLS certificates.
    *   **Script**: `apply-clusterissuer.sh`
    *   **Prerequisites**: Requires AWS credentials (Access Key ID and Secret Access Key) and your Route53 Hosted Zone ID. The script will guide you if the necessary Kubernetes secret for AWS credentials is not found.
    *   **Details**: See `2-clusterissuer-install/README.md`

3.  **`3-storage-config/`**:
    *   **Purpose**: Provisions persistent storage for Harbor's various components (registry, database, jobservice, redis, trivy). It creates `hostPath` based PersistentVolumes (PVs) and their corresponding PersistentVolumeClaims (PVCs) with appropriate permissions.
    *   **Script**: `setup-harbor-storage.sh`
    *   **Important**: This script is not idempotent and should only be run once.
    *   **Details**: See `3-storage-config/README.md`

4.  **`4-core-services-install/`**:
    *   **Purpose**: Deploys Harbor itself using its official Helm chart. This script handles configuration of Harbor (like hostname and admin password management) and integrates it with the previously set up `ClusterIssuer` for HTTPS.
    *   **Script**: `deploy-harbor.sh`
    *   **Values Template**: Uses `harbor-values.template.yaml` for Helm chart configurations.
    *   **Details**: See `4-core-services-install/README.md`

## General Workflow

1.  Start with the `1-microk8s-install` directory and follow its `README.md`.
2.  Proceed to `2-clusterissuer-install` and follow its `README.md`.
3.  Continue to `3-storage-config` and follow its `README.md`.
4.  Finally, go to `4-core-services-install` and follow its `README.md` to deploy Harbor.

## Post-Installation

After running all scripts:

*   **DNS Configuration**: You will need to create an 'A' record in your public DNS (e.g., AWS Route53) pointing your Harbor domain (e.g., `harbor.yourdomain.com`) to the public IP address of your MicroK8s server.
*   **Verification**: The `README.md` in `4-core-services-install/` provides steps to verify the Harbor deployment, including checking pod statuses, certificate issuance, and accessing the Harbor UI.
*   **Firewall (Optional)**: Consider configuring `ufw` or your cloud provider's firewall to allow traffic on ports 80 (HTTP) and 443 (HTTPS), and other necessary MicroK8s ports. Basic `ufw` commands are noted in `install_notes.txt`.

## Un-deployment

The `4-core-services-install/` directory also contains an `un-deploy-harbor.sh` script. This script is designed to completely remove the Harbor installation, including its Helm release, persistent data, secrets, and namespace. Use it with caution if you need to tear down the Harbor deployment.

For a more complete un-deployment, run the following commands:
    ```bash
    sudo rm -rf /var/snap/microk8s/    
    sudo snap remove microk8s --purge
    ```

---

By following the instructions in each subdirectory's `README.md` in sequence, you can achieve a fully functional Harbor installation on MicroK8s with automated HTTPS.