# setup-harbor-storage.sh

This script automates the creation of persistent storage for Harbor services running in a MicroK8s Kubernetes environment. It provisions `hostPath` based PersistentVolumes (PVs) and their corresponding PersistentVolumeClaims (PVCs) for each required Harbor component.

**Important:** This script is **not idempotent** and should only be run once to set up the storage. Running it multiple times might lead to errors or unintended configurations.

**Intent** This script is designed to be run AFTER setting up microk8s and the clusterissuer via the following scripts:
* ../1-microk8s-install/initialize-microk8s-cluster.sh
* ../2-clusterissuer-install/apply-clusterissuer.sh


## Overview

The script performs the following actions:

1.  **Configuration Loading**: Sources an environment file (`../harbor_env.sh` by default) to load required variables like instance name, storage paths, and volume sizes. The path to this file can be overridden via a command-line argument.
2.  **Prerequisite Check**: Verifies the existence of `pv.template.yaml` and `pvc.template.yaml` in the current directory.
3.  **Base Directory Creation**: Ensures the main storage directory on the host system (e.g., `/var/snap/microk8s/common/harbor-storage/harbor`) exists.
4.  **Iterative Storage Provisioning**: For each Harbor service (registry, jobservice, database, redis, trivy):
    *   Creates a dedicated subdirectory on the host.
    *   Sets the ownership of the host directory to the specified `HARBOR_STORAGE_VOLUME_OWNER_UID` to ensure Harbor containers have the necessary write permissions.
    *   Uses `envsubst` to populate `pv.template.yaml` with service-specific details (name, storage size, host path) and applies it to create a PersistentVolume.
    *   Ensures the target Kubernetes namespace exists.
    *   Uses `envsubst` to populate `pvc.template.yaml` and applies it to create a PersistentVolumeClaim in the target namespace, which will bind to the newly created PV.

## Prerequisites

Before running this script, ensure you have the following:

1.  **MicroK8s Installed and Configured**:
    *   MicroK8s should be running.
    *   The `hostpath-storage` addon should be enabled in MicroK8s. This is typically handled by the `../1-microk8s-install/initialize-microk8s-cluster.sh` script.
    *   You should have `sudo` privileges to create directories and set permissions on the host.
2.  **Template Files**:
    *   `pv.template.yaml`: A template for creating PersistentVolume resources.
    *   `pvc.template.yaml`: A template for creating PersistentVolumeClaim resources.
    *   These files must be present in the same directory as `setup-harbor-storage.sh`.
3.  **kubectl Access**: The `microk8s.kubectl` command should be accessible and configured to interact with your MicroK8s cluster.

## Configuration

This script is configured via a central environment file, typically located at `../harbor_env.sh`. Before running the script, you must ensure this file exists and contains the necessary variables.

The following variables from `harbor_env.sh` are used by this script:
*   `HARBOR_INSTANCE_NAME`: Used as the base name for the application and Kubernetes namespace.
*   `HARBOR_STORAGE_HOST_PATH_BASE`: The base directory on the host machine where storage subdirectories will be created.
*   `HARBOR_STORAGE_VOLUME_OWNER_UID`: The user ID that will own the storage directories on the host (e.g., "10000").
*   `HARBOR_STORAGE_REGISTRY_SIZE`: Storage size for the Harbor registry.
*   `HARBOR_STORAGE_JOBSERVICE_SIZE`: Storage size for the Harbor jobservice.
*   `HARBOR_STORAGE_DATABASE_SIZE`: Storage size for the Harbor database.
*   `HARBOR_STORAGE_REDIS_SIZE`: Storage size for Harbor's Redis instance.
*   `HARBOR_STORAGE_TRIVY_SIZE`: Storage size for Harbor's Trivy scanner.
*   `KUBECTL_CMD`: The command to use for `kubectl` (e.g., `microk8s.kubectl`).

### Overriding the Configuration File Path

You can specify a different configuration file by passing its path as the first argument to the script. This is useful for managing multiple environments.

```bash
# Run with a custom environment file
sudo ./setup-harbor-storage.sh /path/to/your/custom_harbor_env.sh
```

## Usage

1.  **Ensure Prerequisites**: Verify all prerequisites listed above are met.
2.  **Configure Environment**: Ensure `../harbor_env.sh` (or a custom file) is correctly populated with your desired values.
3.  **Navigate to Script Directory**: Open your terminal and change to the directory containing `setup-harbor-storage.sh`.
    ```bash
    cd /path/to/1-harbor-storage-config
    ```
4.  **Make Executable**: If necessary, make the script executable:
    ```bash
    chmod +x setup-harbor-storage.sh
    ```
5.  **Run the Script**:
    *The script requires `sudo` because it creates directories and changes file ownership in system locations.*
    ```bash
    sudo ./setup-harbor-storage.sh
    ```

After the script completes, it will have:
*   Created directories on your host machine for each Harbor service.
*   Set the correct ownership on these directories.
*   Created PersistentVolumes in Kubernetes pointing to these host directories.
*   Created PersistentVolumeClaims in the specified Kubernetes namespace, bound to the PVs.

## Verification

You can verify the created resources using `microk8s.kubectl`:

*   **Check PersistentVolumes:**
    ```bash
    microk8s.kubectl get pv
    ```
    You should see PVs like `harbor-registry-pv`, `harbor-database-pv`, etc.

*   **Check PersistentVolumeClaims:**
    ```bash
    microk8s.kubectl get pvc -n ${HARBOR_INSTANCE_NAME}
    ```
    You should see PVCs like `harbor-registry-pvc`, `harbor-database-pvc`, etc., with a `Bound` status.

*   **Check Host Directories:**
    ```bash
    ls -l /var/snap/microk8s/common/harbor-storage/${HARBOR_INSTANCE_NAME}/
    ```
    You should see subdirectories for each service, owned by the user ID specified in `HARBOR_STORAGE_VOLUME_OWNER_UID`.

This storage setup is a crucial step before deploying Harbor itself, as Harbor components will rely on these PVCs for their data persistence.