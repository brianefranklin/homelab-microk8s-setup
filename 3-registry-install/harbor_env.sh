#!/bin/bash
# Shared environment variables for Harbor installation and configuration scripts.

# --- CONFIGURE ALL USER-DEFINED HARBOR VALUES HERE ---

# == General Harbor Settings ==
# Used as the base name for Harbor instance, Kubernetes namespace, Helm release, etc.
export HARBOR_INSTANCE_NAME="harbor"
export HARBOR_DOMAIN="yourdomain.com" # Your public domain for Harbor
export HARBOR_PROTOCOL="https"        # "http" or "https"

# == Helm Configuration (for deploy-harbor.sh) ==
export HARBOR_CHART_REPO_ALIAS="goharbor" # Local alias for the Helm chart repository
export HARBOR_CHART_REPO_URL="https://helm.goharbor.io" # URL of the Helm chart repository
# The actual chart name (e.g., goharbor/harbor) will be derived in deploy-harbor.sh
# using HARBOR_CHART_REPO_ALIAS and HARBOR_INSTANCE_NAME (as the chart is often named 'harbor').

# == Harbor Storage Configuration (for setup-harbor-storage.sh) ==
# The Kubernetes namespace for storage will use HARBOR_INSTANCE_NAME.
export HARBOR_STORAGE_HOST_PATH_BASE="/var/snap/microk8s/common/harbor-storage"
export HARBOR_STORAGE_VOLUME_OWNER_UID="10000" # User ID for Harbor container volumes
export HARBOR_STORAGE_REGISTRY_SIZE="20Gi"
export HARBOR_STORAGE_JOBSERVICE_SIZE="1Gi"
export HARBOR_STORAGE_DATABASE_SIZE="5Gi"
export HARBOR_STORAGE_REDIS_SIZE="1Gi"
export HARBOR_STORAGE_TRIVY_SIZE="5Gi"

# == Harbor API Configuration (for configure_harbor_project.sh) ==
# These variables are directly used by configure_harbor_project.sh if set.
# HARBOR_URL is constructed from protocol, instance name, and domain.
export HARBOR_URL="${HARBOR_PROTOCOL}://${HARBOR_INSTANCE_NAME}.${HARBOR_DOMAIN}"
export HARBOR_ADMIN_USER="admin"
# IMPORTANT: Set HARBOR_ADMIN_PASS after deploy-harbor.sh generates/retrieves it,
# or leave it blank for configure_harbor_project.sh to prompt you.
export HARBOR_ADMIN_PASS=""
export PROJECT_NAME="production-app" # Default project name to be created in Harbor
export ROBOT_NAME="" # Robot account name for CI/CD. If empty, configure_harbor_project.sh defaults or prompts.
export DELETE_OTHER_PROJECTS="no" # Set to "yes" to allow configure_harbor_project.sh to delete other projects.

# == CLI Commands (ensure consistency if also using arc_env.sh) ==
export KUBECTL_CMD="microk8s.kubectl"
export HELM_CMD="microk8s.helm3"
# --- END OF CONFIGURATION ---