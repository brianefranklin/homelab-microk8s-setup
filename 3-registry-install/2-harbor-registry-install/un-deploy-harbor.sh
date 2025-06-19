#!/bin/bash

# ---
# Harbor Un-Deployment Script
#
# This script is intended to completely remove a Harbor installation deployed
# via the accompanying `deploy-harbor.sh` script and its related storage
# setup (`setup-harbor-storage.sh`) from a MicroK8s cluster.
#
# It performs the following actions:
# 1. Uninstalls the Harbor Helm release.
# 2. Deletes PersistentVolumeClaims (PVCs) associated with Harbor services.
# 3. Deletes PersistentVolumes (PVs) backing those PVCs.
# 4. Removes the actual data from the host path directories used by the PVs.
# 5. Deletes Kubernetes secrets created for Harbor (e.g., admin password).
# 6. Deletes the Kubernetes namespace where Harbor was deployed.
#
# CAUTION: This script is destructive and will lead to data loss for the
# Harbor instance. Ensure you have backups if needed before running.
# ---

# --- Source Shared Environment Variables ---
HARBOR_ENV_PATH="../harbor_env.sh"
ENV_FILE_SOURCED=false
if [ -f "$HARBOR_ENV_PATH" ]; then
    # shellcheck source=../harbor_env.sh
    source "$HARBOR_ENV_PATH"
    ENV_FILE_SOURCED=true
    echo "ℹ️ Loaded configuration from '$HARBOR_ENV_PATH'."
else
    echo "⚠️ WARNING: Shared environment file '$HARBOR_ENV_PATH' not found."
    echo "   You will be prompted to provide necessary values manually."
fi

# --- Validate Required Variables from harbor_env.sh ---
# If harbor_env.sh was not found or variables are missing, prompt the user.
REQUIRED_VARS=(
    "HARBOR_INSTANCE_NAME" "HARBOR_STORAGE_HOST_PATH_BASE"
    "KUBECTL_CMD" "HELM_CMD"
)
for VAR_NAME in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR_NAME}" ]; then
        echo "---"
        echo "⚠️ Configuration value for '$VAR_NAME' is missing."
        if [ "$VAR_NAME" == "HARBOR_INSTANCE_NAME" ]; then
            echo "   This is the name used for the Harbor Helm release and Kubernetes namespace."
            echo "   You can try to find it by:"
            echo "     - Listing Helm releases: 'helm list -A' (or your HELM_CMD)"
            echo "     - Listing Kubernetes namespaces: 'kubectl get ns' (or your KUBECTL_CMD)"
            read -r -p "   Please enter the HARBOR_INSTANCE_NAME: " HARBOR_INSTANCE_NAME
            if [ -z "$HARBOR_INSTANCE_NAME" ]; then
                echo "❌ ERROR: HARBOR_INSTANCE_NAME is crucial and was not provided. Exiting." >&2
                exit 1
            fi
        elif [ "$VAR_NAME" == "HARBOR_STORAGE_HOST_PATH_BASE" ]; then
            echo "   This is the base directory on your host machine where Harbor's persistent data was stored."
            echo "   Example: '/var/snap/microk8s/common/harbor-storage' or '/mnt/k8s-data/harbor-storage'."
            echo "   If unsure, you might find it by inspecting one of the Harbor PersistentVolumes (PVs) if they still exist:"
            echo "     'kubectl get pv <harbor-pv-name> -o yaml' and look for 'spec.hostPath.path'."
            read -r -p "   Please enter the HARBOR_STORAGE_HOST_PATH_BASE: " HARBOR_STORAGE_HOST_PATH_BASE
            if [ -z "$HARBOR_STORAGE_HOST_PATH_BASE" ]; then
                echo "❌ ERROR: HARBOR_STORAGE_HOST_PATH_BASE is crucial for data cleanup and was not provided. Exiting." >&2
                exit 1
            fi
        elif [ "$VAR_NAME" == "KUBECTL_CMD" ]; then
            DEFAULT_KUBECTL_CMD="kubectl"
            if command -v microk8s &> /dev/null && microk8s status &> /dev/null; then
                DEFAULT_KUBECTL_CMD="microk8s.kubectl"
            fi
            echo "   This is the command to interact with your Kubernetes cluster (e.g., 'kubectl', 'microk8s.kubectl')."
            read -r -p "   Please enter the KUBECTL_CMD [default: ${DEFAULT_KUBECTL_CMD}]: " KUBECTL_CMD_INPUT
            KUBECTL_CMD=${KUBECTL_CMD_INPUT:-$DEFAULT_KUBECTL_CMD}
            if ! command -v "$KUBECTL_CMD" &> /dev/null; then
                 echo "❌ ERROR: KUBECTL_CMD '$KUBECTL_CMD' not found or not executable. Please provide a valid command. Exiting." >&2
                 exit 1
            fi
        elif [ "$VAR_NAME" == "HELM_CMD" ]; then
            DEFAULT_HELM_CMD="helm"
            if command -v microk8s &> /dev/null && microk8s status &> /dev/null; then
                 DEFAULT_HELM_CMD="microk8s.helm3"
            fi
            echo "   This is the command for Helm (e.g., 'helm', 'microk8s.helm3')."
            read -r -p "   Please enter the HELM_CMD [default: ${DEFAULT_HELM_CMD}]: " HELM_CMD_INPUT
            HELM_CMD=${HELM_CMD_INPUT:-$DEFAULT_HELM_CMD}
            if ! command -v "$HELM_CMD" &> /dev/null; then
                 echo "❌ ERROR: HELM_CMD '$HELM_CMD' not found or not executable. Please provide a valid command. Exiting." >&2
                 exit 1
            fi
        fi
        # Re-assign the globally exported variable if it was set via read
        export "$VAR_NAME"="${!VAR_NAME}"
    fi
done
echo "---"
echo "Using the following configuration for un-deployment:"
echo "  HARBOR_INSTANCE_NAME: ${HARBOR_INSTANCE_NAME}"
echo "  HARBOR_STORAGE_HOST_PATH_BASE: ${HARBOR_STORAGE_HOST_PATH_BASE}"
echo "  KUBECTL_CMD: ${KUBECTL_CMD}"
echo "  HELM_CMD: ${HELM_CMD}"
echo "---"

# Define the list of services for which storage was provisioned.
# This should match the SERVICES array in setup-harbor-storage.sh
SERVICES=("registry" "jobservice" "database" "redis" "trivy")

echo "--- Starting Un-Deployment of Harbor: ${HARBOR_INSTANCE_NAME} ---"
echo -e "\033[1;31mCAUTION: This script is destructive and will remove Harbor and its data.\033[0m"
read -p "Are you sure you want to continue? (yes/N): " CONFIRMATION
if [[ "$CONFIRMATION" != "yes" ]]; then
    echo "Un-deployment cancelled by user."
    exit 0
fi

echo "1. Uninstalling Helm release '${HARBOR_INSTANCE_NAME}' from namespace '${HARBOR_INSTANCE_NAME}'..."
$HELM_CMD uninstall "${HARBOR_INSTANCE_NAME}" -n "${HARBOR_INSTANCE_NAME}" --wait || echo "Warning: Helm uninstall failed or release not found. Continuing..."

echo "2. Deleting PersistentVolumeClaims (PVCs) in namespace '${HARBOR_INSTANCE_NAME}'..."
for SERVICE_NAME in "${SERVICES[@]}"; do
    PVC_NAME="${HARBOR_INSTANCE_NAME}-${SERVICE_NAME}-pvc"
    echo "  -> Deleting PVC: ${PVC_NAME}"
    $KUBECTL_CMD delete pvc "${PVC_NAME}" -n "${HARBOR_INSTANCE_NAME}" --ignore-not-found=true
done

echo "3. Deleting PersistentVolumes (PVs)..."
for SERVICE_NAME in "${SERVICES[@]}"; do
    PV_NAME="${HARBOR_INSTANCE_NAME}-${SERVICE_NAME}-pv"
    echo "  -> Deleting PV: ${PV_NAME}"
    $KUBECTL_CMD delete pv "${PV_NAME}" --ignore-not-found=true
done

HOST_DATA_PATH="${HARBOR_STORAGE_HOST_PATH_BASE}/${HARBOR_INSTANCE_NAME}"
echo "4. Deleting host path data at '${HOST_DATA_PATH}'..."
if [ -d "$HOST_DATA_PATH" ]; then
    sudo rm -rf "${HOST_DATA_PATH}"
    echo "  -> Host path data deleted."
else
    echo "  -> Host path data directory not found. Skipping."
fi

echo "5. Deleting Harbor-specific secrets in namespace '${HARBOR_INSTANCE_NAME}'..."
$KUBECTL_CMD delete secret "${HARBOR_INSTANCE_NAME}-admin-password" -n "${HARBOR_INSTANCE_NAME}" --ignore-not-found=true
# Note: The name of the ingress TLS secret can vary based on Helm chart configuration.
# If 'expose.tls.secretName' was set in your values, use that name.
# Otherwise, it might be named like '<releaseName>-harbor-ingress' or similar.
# The original script used 'harbor-ingress'. We'll use a common pattern.
$KUBECTL_CMD delete secret "${HARBOR_INSTANCE_NAME}-ingress" -n "${HARBOR_INSTANCE_NAME}" --ignore-not-found=true # Adjust if your TLS secret name differs

echo "6. Deleting Harbor namespace '${HARBOR_INSTANCE_NAME}'..."
$KUBECTL_CMD delete namespace "${HARBOR_INSTANCE_NAME}" --ignore-not-found=true

echo "✅ Harbor un-deployment for '${HARBOR_INSTANCE_NAME}' complete."
