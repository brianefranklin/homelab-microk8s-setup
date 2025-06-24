#!/bin/bash
#
# Unified Actions Runner Controller (ARC) Setup & Deployment Script
#
# This single script handles the entire setup process for ARC, including:
# 1. Creating the necessary namespace.
# 2. Interactively creating the GitHub App and Image Pull secrets.
# 3. Installing the Actions Runner Controller using its Helm chart.
# 4. Deploying a self-hosted runner instance for a specific repository.
# 5. Optionally configuring GitHub secrets and generating a sample workflow.
#
# It also includes a cleanup function to remove all created resources.
#
# USAGE:
#   - To run the full setup: ./setup_arc.sh
#   - To run non-interactively, set the CONFIGURATION variables below.
#   - To clean up a previous setup: ./setup_arc.sh --cleanup
#
# PREREQUISITES:
#   - A configured `arc_env.sh` file in the same directory.
#   - Your GitHub App ID, Installation ID, and the path to your App's private key file.
#   - `kubectl` and `helm` installed and configured to point to your cluster.
#   - `envsubst` (usually available via gettext package).
#   - `gh` CLI and `jq` for automatic GitHub secret configuration (optional).

set -e # Exit immediately if a command exits with a non-zero status.

# --- CONFIGURATION (for non-interactive use) ---
# Set these variables to run the script without prompts.
# If a variable is empty, the script will prompt for the value.



# --- Helper Functions for Logging ---
info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

warn() {
    echo -e "\033[0;33m[WARN]\033[0m $1"
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1" >&2
    exit 1
}

# --- Source Environment Variables ---
if [ ! -f "../arc_env.sh" ]; then
    error "Configuration file 'arc_env.sh' not found. Please create it before running this script."
fi
# shellcheck source=arc_env.sh
source ../arc_env.sh
info "Loaded configuration from arc_env.sh"

# --- Function Definitions ---

# Step 1: Create Namespace and Secrets
setup_prerequisites() {
    info "--- Step 1: Setting up Namespace and Secrets ---"

    info "Creating namespace '${ARC_NAMESPACE}' if it doesn't exist..."
    ${KUBECTL_CMD} create namespace "${ARC_NAMESPACE}" --dry-run=client -o yaml | ${KUBECTL_CMD} apply -f -

    # Create GitHub App Controller Secret
    info "Checking for GitHub App secret '${ARC_CONTROLLER_SECRET_NAME}'..."
    if ${KUBECTL_CMD} get secret "${ARC_CONTROLLER_SECRET_NAME}" -n "${ARC_NAMESPACE}" &>/dev/null; then
        warn "Secret '${ARC_CONTROLLER_SECRET_NAME}' already exists. Skipping creation."
    else
        info "The ARC Controller requires a secret with your GitHub App credentials."
        # Use environment variables if set, otherwise prompt the user.
        GITHUB_APP_ID=${CFG_GITHUB_APP_ID}
        GITHUB_APP_INSTALLATION_ID=${CFG_GITHUB_APP_INSTALLATION_ID}
        GITHUB_APP_PRIVATE_KEY_PATH=${CFG_GITHUB_APP_PRIVATE_KEY_PATH}

        if [ -z "$GITHUB_APP_ID" ]; then read -rp "Enter your GitHub App ID: " GITHUB_APP_ID; fi
        if [ -z "$GITHUB_APP_INSTALLATION_ID" ]; then read -rp "Enter your GitHub App Installation ID: " GITHUB_APP_INSTALLATION_ID; fi
        if [ -z "$GITHUB_APP_PRIVATE_KEY_PATH" ]; then read -rp "Enter the path to your GitHub App private key PEM file: " GITHUB_APP_PRIVATE_KEY_PATH; fi

        if [ -z "$GITHUB_APP_ID" ] || [ -z "$GITHUB_APP_INSTALLATION_ID" ] || [ -z "$GITHUB_APP_PRIVATE_KEY_PATH" ]; then
            error "GitHub App credentials cannot be empty."
        fi
        if [ ! -f "$GITHUB_APP_PRIVATE_KEY_PATH" ]; then
            error "Private key file not found at '${GITHUB_APP_PRIVATE_KEY_PATH}'"
        fi

        info "Creating secret '${ARC_CONTROLLER_SECRET_NAME}' in namespace '${ARC_NAMESPACE}'..."
        ${KUBECTL_CMD} create secret generic "${ARC_CONTROLLER_SECRET_NAME}" \
            -n "${ARC_NAMESPACE}" \
            --from-literal=github_app_id="${GITHUB_APP_ID}" \
            --from-literal=github_app_installation_id="${GITHUB_APP_INSTALLATION_ID}" \
            --from-file=github_app_private_key="${GITHUB_APP_PRIVATE_KEY_PATH}"
    fi

    # Create Image Pull Secret
    info "Checking for Image Pull secret 'ghcr-io-pull-secret'..."
    if ${KUBECTL_CMD} get secret "ghcr-io-pull-secret" -n "${ARC_NAMESPACE}" &>/dev/null; then
        warn "Image pull secret 'ghcr-io-pull-secret' already exists. Skipping creation."
    else
        info "To avoid ghcr.io rate limits, we need to create a Kubernetes secret with a GitHub Personal Access Token (PAT)."
        
        # Use environment variables if set, otherwise prompt the user.
        GITHUB_USER=${CFG_GITHUB_USER}
        GITHUB_TOKEN=${CFG_GITHUB_TOKEN}

        if [ -z "$GITHUB_USER" ]; then 
            echo "The PAT requires the 'read:packages' scope."
            read -rp "Enter your GitHub Username: " GITHUB_USER; 
        fi
        if [ -z "$GITHUB_TOKEN" ]; then read -rsp "Enter your GitHub PAT (read:packages): " GITHUB_TOKEN; echo ""; fi

        if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
            error "GitHub credentials for Image Pull Secret cannot be empty."
        fi

        info "Creating 'ghcr-io-pull-secret' in namespace '${ARC_NAMESPACE}'..."
        ${KUBECTL_CMD} create secret docker-registry ghcr-io-pull-secret \
            --namespace="${ARC_NAMESPACE}" \
            --docker-server="https://ghcr.io" \
            --docker-username="${GITHUB_USER}" \
            --docker-password="${GITHUB_TOKEN}" \
            --dry-run=client -o yaml | ${KUBECTL_CMD} apply -f -
    fi
    
    info "Patching service account 'default' in '${ARC_NAMESPACE}' to use the image pull secret..."
    ${KUBECTL_CMD} patch serviceaccount default -n "${ARC_NAMESPACE}" -p '{"imagePullSecrets": [{"name": "ghcr-io-pull-secret"}]}'
    
    info "Prerequisites configured successfully."
}


# Step 2: Install the Actions Runner Controller (ARC)
install_arc() {
    info "--- Step 2: Installing Actions Runner Controller ---"

    # Check if Helm release already exists
    if ${HELM_CMD} status "${ARC_HELM_RELEASE_NAME}" -n "${ARC_NAMESPACE}" &>/dev/null; then
        warn "Helm release '${ARC_HELM_RELEASE_NAME}' already exists. Skipping installation."
        info "To recover from a failed state, please run with the --cleanup flag first."
        return 0
    fi

    info "Adding ARC Helm repository..."
    ${HELM_CMD} repo add "${ARC_HELM_REPO_NAME}" "${ARC_HELM_REPO_URL}" --force-update
    info "Updating Helm repositories..."
    ${HELM_CMD} repo update

    info "Installing ARC Helm chart into namespace '${ARC_NAMESPACE}'..."
    ${HELM_CMD} install "${ARC_HELM_RELEASE_NAME}" "${ARC_HELM_CHART_NAME}" \
        --namespace "${ARC_NAMESPACE}" \
        --set image.imagePullSecrets[0].name="ghcr-io-pull-secret" \
        --set authSecret.name="${ARC_CONTROLLER_SECRET_NAME}"

    info "Waiting for ARC controller manager to be ready..."
    ${KUBECTL_CMD} wait --for=condition=Available=true \
        --namespace "${ARC_NAMESPACE}" \
        deployment/"${ARC_HELM_RELEASE_NAME}" \
        --timeout=5m

    info "Actions Runner Controller installed successfully."
}

# Step 3: Deploy the Self-Hosted Runner
deploy_runner() {
    info "--- Step 3: Deploying the RunnerDeployment ---"

    # FIX: Add a delay to allow the webhook service to fully initialize.
    info "Waiting for 15 seconds to allow the ARC webhook to become fully operational..."
    sleep 15

    if [ ! -f "${RUNNER_DEPLOYMENT_TEMPLATE_FILE}" ]; then
        error "Runner deployment template file not found at '${RUNNER_DEPLOYMENT_TEMPLATE_FILE}'"
    fi

    info "Creating runner namespace '${RUNNER_NAMESPACE}' if it doesn't exist..."
    ${KUBECTL_CMD} create namespace "${RUNNER_NAMESPACE}" --dry-run=client -o yaml | ${KUBECTL_CMD} apply -f -

    info "Substituting variables into '${RUNNER_DEPLOYMENT_TEMPLATE_FILE}' and applying..."
    # Export all relevant variables for envsubst
    export GITHUB_REPOSITORY RUNNER_DEPLOYMENT_NAME RUNNER_NAMESPACE RUNNER_REPLICAS
    
    envsubst < "${RUNNER_DEPLOYMENT_TEMPLATE_FILE}" | ${KUBECTL_CMD} apply -f -

    info "RunnerDeployment '${RUNNER_DEPLOYMENT_NAME}' applied successfully."
    info "ARC will now provision ${RUNNER_REPLICAS} runner(s) in the '${RUNNER_NAMESPACE}' namespace."
}

# Step 4: Configure GitHub Secrets and generate workflow
configure_github_extras() {
    info "--- Step 4: Configuring GitHub Secrets & Workflow ---"

    if ! command -v gh &> /dev/null || ! command -v jq &> /dev/null; then
        warn "'gh' CLI or 'jq' is not installed. Skipping automatic GitHub secret configuration and workflow generation."
        warn "You will need to configure the required secrets in your repository manually."
        return 0
    fi

    read -rp "Do you want to automatically configure secrets in the '${GITHUB_REPOSITORY}' repository? (y/N): " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Logging into GitHub CLI..."
        gh auth login -h github.com -p https --web

        info "Configuring secrets in '${GITHUB_REPOSITORY}'..."
        read -rp "Enter your Harbor registry URL (e.g., my-harbor.my-domain.com): " HARBOR_URL
        read -rp "Enter your Harbor username for the secret HARBOR_USERNAME: " HARBOR_USERNAME
        read -rsp "Enter Harbor password/robot secret: " HARBOR_PASSWORD
        echo ""
        
        gh secret set HARBOR_URL --body "${HARBOR_URL}" --repo "${GITHUB_REPOSITORY}"
        gh secret set HARBOR_USERNAME --body "${HARBOR_USERNAME}" --repo "${GITHUB_REPOSITORY}"
        gh secret set HARBOR_PASSWORD --body "${HARBOR_PASSWORD}" --repo "${GITHUB_REPOSITORY}"

        info "Generating Kubeconfig for GitHub Actions..."
        # WARNING: The following method of generating a kubeconfig is simple and works for many
        # dev environments (like MicroK8s), but it is NOT recommended for production.
        # It often bundles the admin user's full, short-lived credentials.
        # A better approach is to create a dedicated ServiceAccount in Kubernetes for CI/CD,
        # grant it limited permissions, and use its long-lived token as the secret.
        KUBECONFIG_CONTENT=$(${KUBECTL_CMD} config view --raw)
        gh secret set KUBE_CONFIG --body "${KUBECONFIG_CONTENT}" --repo "${GITHUB_REPOSITORY}"
        info "Secrets HARBOR_URL, HARBOR_USERNAME, HARBOR_PASSWORD, and KUBE_CONFIG have been set."
    else
        warn "Skipping automatic secret configuration."
    fi

    info "Generating sample GitHub Actions workflow file..."
    if [ ! -f "${WORKFLOW_TEMPLATE_FILE}" ]; then
        error "Workflow template file not found at '${WORKFLOW_TEMPLATE_FILE}'"
    fi

    GENERATED_WORKFLOW_DIR=$(dirname "${GENERATED_WORKFLOW_BASE_DIR}/${WORKFLOW_TEMPLATE_FILE}")
    mkdir -p "${GENERATED_WORKFLOW_DIR}"

    GENERATED_WORKFLOW_PATH="${GENERATED_WORKFLOW_BASE_DIR}/${WORKFLOW_TEMPLATE_FILE}"
    info "Substituting variables into '${WORKFLOW_TEMPLATE_FILE}'..."
    export HARBOR_PROJECT_NAME HARBOR_IMAGE_NAME K8S_DEPLOYMENT_MANIFEST_PATH RUNNER_NAMESPACE

    envsubst < "${WORKFLOW_TEMPLATE_FILE}" > "${GENERATED_WORKFLOW_PATH}"
    info "Generated workflow file at '${GENERATED_WORKFLOW_PATH}'"
    info "Please review this file and commit it to your repository's .github/workflows/ directory."

}


# --- Cleanup Function ---
cleanup() {
    info "--- Running Cleanup ---"
    read -rp "Are you sure you want to remove all ARC components, runners, and secrets configured by this script? (y/N): " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Cleanup cancelled."
        exit 0
    fi

    info "Deleting RunnerDeployment '${RUNNER_DEPLOYMENT_NAME}' from namespace '${RUNNER_NAMESPACE}'..."
    ${KUBECTL_CMD} delete runnerdeployment "${RUNNER_DEPLOYMENT_NAME}" -n "${RUNNER_NAMESPACE}" --ignore-not-found=true

    info "Uninstalling Helm release '${ARC_HELM_RELEASE_NAME}'..."
    ${HELM_CMD} uninstall "${ARC_HELM_RELEASE_NAME}" -n "${ARC_NAMESPACE}" --wait

    info "Deleting ARC controller secret '${ARC_CONTROLLER_SECRET_NAME}'..."
    ${KUBECTL_CMD} delete secret "${ARC_CONTROLLER_SECRET_NAME}" -n "${ARC_NAMESPACE}" --ignore-not-found=true
    
    info "Deleting image pull secret 'ghcr-io-pull-secret'..."
    ${KUBECTL_CMD} delete secret "ghcr-io-pull-secret" -n "${ARC_NAMESPACE}" --ignore-not-found=true

    info "Deleting namespace '${ARC_NAMESPACE}'..."
    ${KUBECTL_CMD} delete namespace "${ARC_NAMESPACE}" --ignore-not-found=true
    
    info "Deleting namespace '${RUNNER_NAMESPACE}' if it's not 'default'..."
    if [[ "${RUNNER_NAMESPACE}" != "default" ]]; then
       ${KUBECTL_CMD} delete namespace "${RUNNER_NAMESPACE}" --ignore-not-found=true
    fi

    info "Cleanup complete."
}


# --- Main Execution Logic ---
main() {
    # Check for --cleanup flag
    if [[ "$1" == "--cleanup" ]]; then
        cleanup
        exit 0
    fi

    # Run setup steps sequentially
    setup_prerequisites
    install_arc
    deploy_runner
    configure_github_extras

    echo ""
    info "🎉 All setup steps completed successfully! 🎉"
    info "Your self-hosted runners should be starting up in the '${RUNNER_NAMESPACE}' namespace."
    info "Run '${KUBECTL_CMD} get pods -n ${RUNNER_NAMESPACE}' to check their status."
}

# Pass all script arguments to main
main "$@"

