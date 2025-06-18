#!/bin/bash
# This script prepares secure, persistent hostPath volumes for all Harbor services.

# This script is not idempotent and should be run only once to set up the storage.

# --- CONFIGURE YOUR CORE VALUES HERE ---
export APP_NAME="harbor"
export K8S_NAMESPACE="harbor"

# Base directory on the host for storage
# Choosing a base directory outside of the default /var/snap/microk8s/common/ might
# break compatibility with strictly confined microk8s installations.
export HOST_PATH_BASE="/var/snap/microk8s/common/harbor-storage"
##export HOST_PATH_BASE="/mnt/k8s-data" 

# The user ID that the Harbor containers run as. This is critical for permissions.
# All Harbor components use the same non-root user.
export VOLUME_OWNER_UID="10000"

# --- CONFIGURE STORAGE SIZES FOR EACH SERVICE ---
export REGISTRY_STORAGE_SIZE="20Gi"
export JOBSERVICE_STORAGE_SIZE="1Gi"
export DATABASE_STORAGE_SIZE="5Gi"
export REDIS_STORAGE_SIZE="1Gi"
export TRIVY_STORAGE_SIZE="5Gi"
# ----------------------------------------------------

# --- SCRIPT LOGIC (DO NOT EDIT BELOW THIS LINE) ---
SERVICES=("registry" "jobservice" "database" "redis" "trivy")
PV_TEMPLATE="pv.template.yaml"
PVC_TEMPLATE="pvc.template.yaml"

# Check if template files exist before starting
if [ ! -f "$PV_TEMPLATE" ] || [ ! -f "$PVC_TEMPLATE" ]; then
    echo "❌ ERROR: Template files ($PV_TEMPLATE or $PVC_TEMPLATE) not found in the current directory."
    exit 1
fi

echo "--- Preparing Persistent Storage for Application: $APP_NAME ---"

# Ensure the base directory exists
echo "Ensuring base host directory exists at ${HOST_PATH_BASE}/${APP_NAME}..."
sudo mkdir -p "${HOST_PATH_BASE}/${APP_NAME}"
echo "---"

# Loop through each service to create its storage
for SERVICE_NAME in "${SERVICES[@]}"; do
    echo "Processing storage for service: $SERVICE_NAME"

    # Dynamically get the storage size for the current service
    size_var_name="${SERVICE_NAME^^}_STORAGE_SIZE" # e.g., DATABASE_STORAGE_SIZE
    export STORAGE_SIZE=${!size_var_name}

    export SERVICE_NAME # Export for envsubst
    export STORAGE_CLASS_NAME="${APP_NAME}-manual-${SERVICE_NAME}"
    DB_HOST_PATH="${HOST_PATH_BASE}/${APP_NAME}/${SERVICE_NAME}"

    # 1. Create Directory on Host
    echo "  -> Creating host directory: ${DB_HOST_PATH}"
    sudo mkdir -p "${DB_HOST_PATH}"

    # 2. Set Secure Permissions
    echo "  -> Setting ownership to UID ${VOLUME_OWNER_UID}"
    sudo chown -R "${VOLUME_OWNER_UID}:${VOLUME_OWNER_UID}" "${DB_HOST_PATH}"

    # 3. Apply PV Manifest
    echo "  -> Applying PersistentVolume manifest..."
    envsubst < "$PV_TEMPLATE" | microk8s.kubectl apply -f -

    # 4. Apply PVC Manifest
    echo "  -> Applying PersistentVolumeClaim manifest in namespace '$K8S_NAMESPACE'..."
    microk8s.kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | microk8s.kubectl apply -f -
    envsubst < "$PVC_TEMPLATE" | microk8s.kubectl apply -f -

    echo "  -> Storage for '$SERVICE_NAME' successfully provisioned."
    echo "---"
done

echo "✅ All storage provisioning complete for '$APP_NAME'."