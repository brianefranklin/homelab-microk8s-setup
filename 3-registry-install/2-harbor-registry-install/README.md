# deploy-harbor.sh

This script automates the deployment or upgrade of Harbor, an open-source container image registry, onto a MicroK8s Kubernetes cluster using Helm. It handles the configuration of essential parameters and manages the Harbor admin password securely.

**Intent** This script is designed to be run AFTER setting up microk8s, the clusterissuer, and harbor persistent storage volumes via the following scripts:
* ../1-microk8s-install/initialize-microk8s-cluster.sh
* ../2-clusterissuer-install/apply-clusterissuer.sh
* ../3-storage-config/setup-harbor-storage.sh



## Overview

The `deploy-harbor.sh` script performs the following key actions:

1.  **Configuration**: Sets core variables (`APP_NAME`, `DOMAIN`, `CHART_REPO_NAME`) and derives others like hostname and namespace.
2.  **Configuration Loading**: Sources an environment file (`../harbor_env.sh` by default) to load required variables. The path to this file can be overridden via a command-line argument.
3.  **Admin Password Management**:
    *   Checks for an existing Kubernetes secret (`<APP_NAME>-admin-password`) in the Harbor namespace.
    *   If the secret exists, it reads the password for use in an upgrade.
    *   If the secret does not exist, it generates a new random password, displays it once to the user, and stores it in a new Kubernetes secret.
4.  **Helm Repository Management**:
    *   Adds the specified Harbor Helm chart repository (`goharbor`) if it's not already configured.
    *   Updates Helm repositories to ensure the latest chart versions are available.
5.  **Harbor Deployment/Upgrade**:
    *   Uses `envsubst` to substitute configured environment variables (like hostname and password) into a `harbor-values.template.yaml` file.
    *   Deploys or upgrades Harbor using `microk8s.helm3 upgrade --install`. This command is idempotent, meaning it will install Harbor if it's not present or upgrade an existing installation.
    *   Ensures the target namespace is created if it doesn't exist.

## Prerequisites

Before running this script, ensure the following setup is complete, typically by running the preceding scripts in this repository:

1.  **MicroK8s Cluster**:
    *   A functional MicroK8s cluster.
    *   Necessary addons enabled (`dns`, `hostpath-storage`, `ingress`, `helm3`).
    *   This is typically handled by `../1-microk8s-install/initialize-microk8s-cluster.sh`.
2.  **cert-manager and ClusterIssuer**:
    *   cert-manager installed and a `ClusterIssuer` configured for issuing SSL/TLS certificates (e.g., via Let's Encrypt with AWS Route53).
    *   This is typically handled by `../2-clusterissuer-install/apply-clusterissuer.sh`.
3.  **Harbor Persistent Storage**:
    *   PersistentVolumes (PVs) and PersistentVolumeClaims (PVCs) for Harbor components must be created and correctly permissioned.
    *   This is typically handled by `../3-storage-config/setup-harbor-storage.sh`.
4.  **Harbor Values Template**:
    *   A `harbor-values.template.yaml` file must be present in the same directory as `deploy-harbor.sh`. This file contains the Helm chart value overrides and uses environment variables as placeholders that this script will populate.
5.  **kubectl and Helm Access**:
    *   `microk8s.kubectl` and `microk8s.helm3` commands should be accessible and configured. Aliases for `kubectl` and `helm` might need to be sourced (`source ~/.bash_aliases`) if set up by `initialize-microk8s-cluster.sh`.

## Configuration

This script is configured via a central environment file, typically located at `../harbor_env.sh`. Before running the script, you must ensure this file exists and contains the necessary variables.

The following variables from `harbor_env.sh` are used by this script:
*   `HARBOR_INSTANCE_NAME`: The base name for the Helm release and namespace.
*   `HARBOR_DOMAIN`: Your domain name where Harbor will be accessible.
*   `HARBOR_PROTOCOL`: The protocol to use (e.g., "https").
*   `HARBOR_CHART_REPO_ALIAS`: The local alias for the Helm chart repository.
*   `HARBOR_CHART_REPO_URL`: The URL of the Helm chart repository.
*   `KUBECTL_CMD`: The command to use for `kubectl`.
*   `HELM_CMD`: The command to use for `helm`.

### Overriding the Configuration File Path

You can specify a different configuration file by passing its path as the first argument to the script.

```bash
./deploy-harbor.sh /path/to/your/custom_harbor_env.sh
```

## Usage

1.  **Ensure Prerequisites**: Verify all prerequisites listed above are met.
2.  **Configure Environment**: Ensure `../harbor_env.sh` (or a custom file) is correctly populated.
3.  **Navigate to Script Directory**: Open your terminal and change to the directory containing `deploy-harbor.sh`.
    ```bash
    cd /path/to/2-harbor-registry-install
    ```
4.  **Make Executable**: If necessary, make the script executable:
    ```bash
    chmod +x deploy-harbor.sh
    ```
5.  **Run the Script**:
    ```bash
    ./deploy-harbor.sh
    ```

    *   If this is the first run, the script will generate a new admin password, display it, and create a secret. **Save this password securely.**
    *   On subsequent runs (for upgrades), the script will use the existing password from the secret.

The script will then proceed to add the Helm repository (if needed) and deploy/upgrade Harbor.

## Verification

After the script completes, you can verify the Harbor deployment:

1.  **Check Pods**:
    ```bash
    microk8s.kubectl get pods -n ${HARBOR_INSTANCE_NAME}
    ```
    Wait for all Harbor pods to be in the `Running` state and have their containers ready.

2.  **Check Ingress**:
    ```bash
    microk8s.kubectl get ingress -n ${HARBOR_INSTANCE_NAME}
    ```
    Ensure an Ingress resource is created and has an address.

3.  **Access Harbor UI**:
    Open a web browser and navigate to `https://<HARBOR_INSTANCE_NAME>.<HARBOR_DOMAIN>`. You should see the Harbor login page. Log in with username `admin` and the password that was generated or previously set.

4.  **Check Certificates**:
    Verify that SSL certificates are correctly issued for your Harbor instance.
    ```bash
    microk8s.kubectl describe certificate -n ${HARBOR_INSTANCE_NAME}
    ```

## Un-deployment or Reconfiguration

If you need to completely remove the Harbor installation (e.g., due to a misconfiguration or to start fresh), you can use the `un-deploy-harbor.sh` script located in the same directory. This script will:

*   Uninstall the Harbor Helm release.
*   Delete associated PersistentVolumeClaims (PVCs) and PersistentVolumes (PVs).
*   Remove data from the host path directories.
*   Delete Harbor-specific secrets.
*   Delete the Harbor namespace.

**Caution**: `un-deploy-harbor.sh` is destructive and will lead to data loss for the Harbor instance.

If you only need to reset the admin password, you can delete the secret (`microk8s.kubectl delete secret <APP_NAME>-admin-password -n <APP_NAME>`) and re-run `deploy-harbor.sh`.

```