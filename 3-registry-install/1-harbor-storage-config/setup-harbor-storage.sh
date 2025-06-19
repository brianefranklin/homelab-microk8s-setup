#!/bin/bash
# This script prepares secure, persistent hostPath volumes for all Harbor services.

# This script is not idempotent and should be run only once to set up the storage.

# --- Source Shared Environment Variables ---
HARBOR_ENV_PATH="../harbor_env.sh" # Path relative to this script

if [ -f "$HARBOR_ENV_PATH" ]; then
    # shellcheck source=../harbor_env.sh
    source "$HARBOR_ENV_PATH"
else
    echo "❌ ERROR: Shared environment file '$HARBOR_ENV_PATH' not found." >&2
    echo "Please ensure it exists and is configured." >&2
    exit 1
fi

# --- Validate Required Variables from harbor_env.sh ---
REQUIRED_VARS=(
    "HARBOR_INSTANCE_NAME" "HARBOR_STORAGE_HOST_PATH_BASE" "HARBOR_STORAGE_VOLUME_OWNER_UID"
    "HARBOR_STORAGE_REGISTRY_SIZE" "HARBOR_STORAGE_JOBSERVICE_SIZE" "HARBOR_STORAGE_DATABASE_SIZE"
    "HARBOR_STORAGE_REDIS_SIZE" "HARBOR_STORAGE_TRIVY_SIZE" "KUBECTL_CMD"
)
for VAR_NAME in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR_NAME}" ]; then
        echo "❌ ERROR: Required variable '$VAR_NAME' is not set in '$HARBOR_ENV_PATH'." >&2
        exit 1
    fi
done

# --- Use Sourced Variables ---
APP_NAME="${HARBOR_INSTANCE_NAME}"
K8S_NAMESPACE="${HARBOR_INSTANCE_NAME}"
HOST_PATH_BASE="${HARBOR_STORAGE_HOST_PATH_BASE}"
VOLUME_OWNER_UID="${HARBOR_STORAGE_VOLUME_OWNER_UID}"

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
sudo mkdir -p "${HOST_PATH_BASE}/${APP_NAME}" # Uses HOST_PATH_BASE from env file
echo "---"

# Loop through each service to create its storage
for SERVICE_NAME in "${SERVICES[@]}"; do
    echo "Processing storage for service: $SERVICE_NAME"

    # Dynamically get the storage size for the current service from HARBOR_STORAGE_*_SIZE variables
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
    envsubst < "$PV_TEMPLATE" | $KUBECTL_CMD apply -f -

    # 4. Apply PVC Manifest
    echo "  -> Applying PersistentVolumeClaim manifest in namespace '$K8S_NAMESPACE'..."
    $KUBECTL_CMD create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
    envsubst < "$PVC_TEMPLATE" | $KUBECTL_CMD apply -f -

    echo "  -> Storage for '$SERVICE_NAME' successfully provisioned."
    echo "---"
done

echo "✅ All storage provisioning complete for '$APP_NAME'."