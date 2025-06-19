# setup-harbor-storage.sh

This script automates the creation of persistent storage for Harbor services running in a MicroK8s Kubernetes environment. It provisions `hostPath` based PersistentVolumes (PVs) and their corresponding PersistentVolumeClaims (PVCs) for each required Harbor component.

**Important:** This script is **not idempotent** and should only be run once to set up the storage. Running it multiple times might lead to errors or unintended configurations.

**Intent** This script is designed to be run AFTER setting up microk8s and the clusterissuer via the following scripts:
* ../1-microk8s-install/initialize-microk8s-cluster.sh
* ../2-clusterissuer-install/apply-clusterissuer.sh


## Overview

The script performs the following actions:

1.  **Configuration Loading**: Reads user-defined variables for application name, Kubernetes namespace, host path base directory, volume owner UID, and storage sizes for various Harbor services.
2.  **Prerequisite Check**: Verifies the existence of `pv.template.yaml` and `pvc.template.yaml` in the current directory.
3.  **Base Directory Creation**: Ensures the main storage directory on the host system (e.g., `/var/snap/microk8s/common/harbor-storage/harbor`) exists.
4.  **Iterative Storage Provisioning**: For each Harbor service (registry, jobservice, database, redis, trivy):
    *   Creates a dedicated subdirectory on the host.
    *   Sets the ownership of the host directory to the specified `VOLUME_OWNER_UID` (default `10000`) to ensure Harbor containers have the necessary write permissions.
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

You need to configure your specific values directly within the `setup-harbor-storage.sh` script before running it.

1.  Open `setup-harbor-storage.sh` in a text editor.
2.  Locate the section `--- CONFIGURE YOUR CORE VALUES HERE ---` and `--- CONFIGURE STORAGE SIZES FOR EACH SERVICE ---`.
3.  Update the following environment variables as needed:
    *   `APP_NAME`: The application name, used for naming resources (default: "harbor").
    *   `K8S_NAMESPACE`: The Kubernetes namespace where Harbor will be deployed and PVCs will be created (default: "harbor").
    *   `HOST_PATH_BASE`: The base directory on the host machine where storage subdirectories will be created (default: `/var/snap/microk8s/common/harbor-storage`).
        *   **Note**: Changing this to a path outside of MicroK8s's default accessible paths might require additional MicroK8s configuration.
    *   `VOLUME_OWNER_UID`: The user ID that will own the storage directories on the host. This must match the user ID Harbor containers run as (default: "10000").
    *   `REGISTRY_STORAGE_SIZE`: Storage size for the Harbor registry (default: "20Gi").
    *   `JOBSERVICE_STORAGE_SIZE`: Storage size for the Harbor jobservice (default: "1Gi").
    *   `DATABASE_STORAGE_SIZE`: Storage size for the Harbor database (default: "5Gi").
    *   `REDIS_STORAGE_SIZE`: Storage size for Harbor's Redis instance (default: "1Gi").
    *   `TRIVY_STORAGE_SIZE`: Storage size for Harbor's Trivy scanner (default: "5Gi").

## Usage

1.  **Ensure Prerequisites**: Verify all prerequisites listed above are met.
2.  **Configure the Script**: Edit `setup-harbor-storage.sh` with your desired values as described in the "Configuration" section.
3.  **Navigate to Script Directory**: Open your terminal and change to the directory containing `setup-harbor-storage.sh`, `pv.template.yaml`, and `pvc.template.yaml`.
    ```bash
    cd /path/to/harbor-install/3-storage-config
    ```
4.  **Make Executable**: If necessary, make the script executable:
    ```bash
    chmod +x setup-harbor-storage.sh
    ```
5.  **Run the Script**:
    ```bash
    sudo ./setup-harbor-storage.sh
    ```
    The script requires `sudo` because it creates directories and changes file ownership in system locations (e.g., under `/var/snap/microk8s/common/`).

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
    microk8s.kubectl get pvc -n <K8S_NAMESPACE> # Replace <K8S_NAMESPACE> with your configured namespace
    ```
    You should see PVCs like `harbor-registry-pvc`, `harbor-database-pvc`, etc., with a `Bound` status.

*   **Check Host Directories:**
    ```bash
    ls -l <HOST_PATH_BASE>/<APP_NAME>/
    ```
    You should see subdirectories for each service, owned by the `VOLUME_OWNER_UID`.

This storage setup is a crucial step before deploying Harbor itself, as Harbor components will rely on these PVCs for their data persistence.