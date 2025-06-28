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
#   - `curl` for API calls.
#   - `kubectl` and `helm` installed and configured to point to your cluster.
#   - `envsubst` (usually available via gettext package).
#   - `gh` CLI and `jq` for automatic GitHub secret configuration (optional).

set -e # Exit immediately if a command exits with a non-zero status.

# --- DEBUG MODE ---
DEBUG_MODE=false
if [[ "$1" == "--debug" ]]; then
    DEBUG_MODE=true
    shift # Remove --debug from arguments, so the rest of the script processes them normally
fi

if $DEBUG_MODE; then
    set -x # Echo commands before execution
fi

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

success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

# Function to verify GitHub PAT has the required scopes
verify_github_pat_scopes() {
    local token_to_check="$1"
    local required_scope="read:packages"
    
    info "Verifying that the provided GitHub PAT has the '${required_scope}' scope..."

    # Use curl to get the response headers from a simple API call
    local headers
    headers=$(curl -s -I -H "Authorization: token ${token_to_check}" https://api.github.com/user)
    
    # Check for a 200 OK status first to ensure the token is valid at all
    if ! echo "$headers" | grep -q -E "HTTP/(1.1|2) 200"; then
        warn "The provided PAT is not valid or could not be used to authenticate. Please provide a valid token."
        return 1
    fi

    # Extract the scopes from the X-OAuth-Scopes header
    local scopes
    scopes=$(echo "$headers" | grep -i "x-oauth-scopes:" | awk -F': ' '{print $2}' | tr -d '\r')

    # Check if the required scope is in the list of scopes
    if [[ "$scopes" == *"$required_scope"* ]]; then
        success "PAT has the required '${required_scope}' scope."
        return 0
    else
        warn "The provided PAT is missing the required '${required_scope}' scope."
        warn "Current scopes found: ${scopes:-'None'}"
        warn "Please generate a new PAT with the 'read:packages' scope from https://github.com/settings/tokens"
        return 1
    fi
}

# --- Source Environment Variables ---
if [ ! -f "../arc_env.sh" ]; then
    error "Configuration file 'arc_env.sh' not found. Please create it before running this script."
fi
# shellcheck source=arc_env.sh
source ../arc_env.sh
info "Loaded configuration from arc_env.sh"

# --- Function Definitions ---

# Check for core dependencies
check_deps() {
    info "Checking for core dependencies..."
    local missing_deps=()
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    if ! command -v envsubst &> /dev/null; then
        missing_deps+=("envsubst (from gettext package)")
    fi
    if ! command -v "${KUBECTL_CMD%% *}" &> /dev/null; then
        missing_deps+=("${KUBECTL_CMD%% *}")
    fi
    if ! command -v "${HELM_CMD%% *}" &> /dev/null; then
        missing_deps+=("${HELM_CMD%% *}")
    fi
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "The following required tools are not installed or not in your PATH: ${missing_deps[*]}. Please install them to continue."
    fi
    info "All core dependencies found."
}

# Step 1: Create Namespace and Secrets
setup_prerequisites() {
    info "--- Step 1: Setting up Namespace and Secrets ---"

    info "Creating namespace '${ARC_NAMESPACE}' if it doesn't exist..."
    local namespace_yaml
    namespace_yaml=$(${KUBECTL_CMD} create namespace "${ARC_NAMESPACE}" --dry-run=client -o yaml)
    if $DEBUG_MODE; then
        info "Applying namespace YAML:\n$namespace_yaml"
    fi
    echo "$namespace_yaml" | ${KUBECTL_CMD} apply -f -

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

        # FIX: Sanitize input to remove leading/trailing single/double quotes
        # that cause parsing errors in the controller.
        CLEAN_GITHUB_APP_ID=$(echo "${GITHUB_APP_ID}" | tr -d "'\"")
        CLEAN_GITHUB_APP_INSTALLATION_ID=$(echo "${GITHUB_APP_INSTALLATION_ID}" | tr -d "'\"")

        info "Creating secret '${ARC_CONTROLLER_SECRET_NAME}' in namespace '${ARC_NAMESPACE}'..."
        ${KUBECTL_CMD} create secret generic "${ARC_CONTROLLER_SECRET_NAME}" \
            -n "${ARC_NAMESPACE}" \
            --from-literal=github_app_id="${CLEAN_GITHUB_APP_ID}" \
            --from-literal=github_app_installation_id="${CLEAN_GITHUB_APP_INSTALLATION_ID}" \
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
        
        # Loop until we have a valid token with the correct scope
        while true; do
            if [ -z "$GITHUB_USER" ]; then
                read -rp "Enter your GitHub Username: " GITHUB_USER
            fi
            if [ -z "$GITHUB_TOKEN" ]; then
                echo "The PAT requires the 'read:packages' scope."
                read -rsp "Enter your GitHub PAT: " GITHUB_TOKEN; echo ""
            fi

            if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
                error "GitHub credentials for Image Pull Secret cannot be empty."
            fi

            # Verify the token's scopes
            if verify_github_pat_scopes "$GITHUB_TOKEN"; then
                break # Exit loop if token is valid
            else
                # If non-interactive and failed, exit.
                if [ -n "$CFG_GITHUB_TOKEN" ]; then
                    error "The pre-configured GITHUB_TOKEN in arc_env.sh is invalid or missing the 'read:packages' scope."
                fi
                # Reset token to re-prompt the user
                GITHUB_TOKEN=""
                warn "Please try again."
            fi
        done
        
        info "Creating 'ghcr-io-pull-secret' in namespace '${ARC_NAMESPACE}'..."
        local secret_yaml
        secret_yaml=$(${KUBECTL_CMD} create secret docker-registry ghcr-io-pull-secret \
            --namespace="${ARC_NAMESPACE}" \
            --docker-server="https://ghcr.io" \
            --docker-username="${GITHUB_USER}" \
            --docker-password="${GITHUB_TOKEN}" \
            --dry-run=client -o yaml)
        if $DEBUG_MODE; then
            info "Applying secret YAML:\n$secret_yaml"
        fi
        echo "$secret_yaml" | ${KUBECTL_CMD} apply -f -
    fi
    
    # Create Harbor Image Pull Secret for application deployments
    info "Checking for Harbor image pull secret 'harbor-credentials' in namespace '${RUNNER_NAMESPACE}'..."
    if ${KUBECTL_CMD} get secret "harbor-credentials" -n "${RUNNER_NAMESPACE}" &>/dev/null; then
        warn "Secret 'harbor-credentials' already exists in '${RUNNER_NAMESPACE}'. Skipping creation."
    else
        info "To allow Kubernetes to pull images from your private Harbor registry, a secret with Harbor credentials is required."
        
        # --- Robustly prompt for Harbor credentials ---
        HARBOR_URL=${CFG_HARBOR_URL}
        while [ -z "$HARBOR_URL" ]; do
            read -rp "Enter your Harbor registry URL (e.g., harbor.your-domain.com): " HARBOR_URL
            if [ -z "$HARBOR_URL" ]; then
                warn "Harbor URL cannot be empty. Please try again."
            fi
        done

        HARBOR_USERNAME=${CFG_HARBOR_USERNAME}
        while [ -z "$HARBOR_USERNAME" ]; do
            read -rp "Enter the Harbor Robot Account Name for Kubernetes image pull (e.g., 'robot\$my-app-github-actions-builder'): " HARBOR_USERNAME
            if [ -z "$HARBOR_USERNAME" ]; then
                warn "Harbor Robot Account Name cannot be empty. Please try again."
            fi
        done

        HARBOR_PASSWORD=${CFG_HARBOR_PASSWORD}
        while [ -z "$HARBOR_PASSWORD" ]; do
            read -rsp "Enter Harbor password/robot secret (will not be echoed): " HARBOR_PASSWORD; echo ""
            if [ -z "$HARBOR_PASSWORD" ]; then
                warn "Harbor password cannot be empty. Please try again."
            fi
        done

        # --- Confirmation Step ---
        info "You have provided the following credentials for the 'harbor-credentials' secret:"
        echo "  - Harbor URL:      $HARBOR_URL"
        echo "  - Harbor Username: $HARBOR_USERNAME"
        echo "  - Harbor Password: [hidden]"
        
        local confirm_creation
        read -rp "Proceed with creating the secret in namespace '${RUNNER_NAMESPACE}'? [Y/n]: " confirm_creation
        confirm_creation=${confirm_creation:-Y} # Default to Yes

        if [[ ! "$confirm_creation" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            warn "Secret creation cancelled by user. Application deployments from Harbor may fail."
            # We return 0 to allow the rest of the script to proceed if the user wishes.
            return 0
        fi

        # The original check for empty variables is now redundant due to the while loops.

        info "Creating 'harbor-credentials' secret in namespace '${RUNNER_NAMESPACE}'..."
        local secret_yaml
        secret_yaml=$(${KUBECTL_CMD} create secret docker-registry harbor-credentials \
            --namespace="${RUNNER_NAMESPACE}" \
            --docker-server="${HARBOR_URL}" \
            --docker-username="${HARBOR_USERNAME}" \
            --docker-password="${HARBOR_PASSWORD}" \
            --dry-run=client -o yaml)
        if $DEBUG_MODE; then
            info "Applying secret YAML:\n$secret_yaml"
        fi
        echo "$secret_yaml" | ${KUBECTL_CMD} apply -f -
    fi

    # Patch the default service account in RUNNER_NAMESPACE to use the Harbor image pull secret.
    # This is crucial for application pods deployed by the workflow.
    info "Patching service account in '${RUNNER_NAMESPACE}' to use 'harbor-credentials'..."
    # This patch command is designed to ADD the secret if it's not there, without removing others.
    # It uses strategic merge patch to append to the imagePullSecrets array.
    ${KUBECTL_CMD} patch serviceaccount default -n "${RUNNER_NAMESPACE}" -p '{"imagePullSecrets": [{"name": "harbor-credentials"}]}'


    info "Waiting for the default service account to be created in '${ARC_NAMESPACE}'..."
    local timeout_seconds=60
    local end_time=$(( $(date +%s) + timeout_seconds ))
    local sa_found=false

    while [[ $(date +%s) -lt ${end_time} ]]; do
        if ${KUBECTL_CMD} get serviceaccount default -n "${ARC_NAMESPACE}" &>/dev/null; then
            sa_found=true
            info "Default service account found."
            break
        fi
        sleep 2
    done

    if [[ "${sa_found}" = false ]]; then
        error "Timed out waiting for the default service account in namespace '${ARC_NAMESPACE}' to be created."
    fi
    # <<< INSERT THIS FIX >>>
    info "Waiting for the default service account to be created in '${RUNNER_NAMESPACE}'..."
    local runner_sa_found=false
    local runner_end_time=$(( $(date +%s) + 60 ))
    while [[ $(date +%s) -lt ${runner_end_time} ]]; do
        if ${KUBECTL_CMD} get serviceaccount default -n "${RUNNER_NAMESPACE}" &>/dev/null; then
            runner_sa_found=true
            break
        fi
        sleep 2
    done
    if [[ "${runner_sa_found}" = false ]]; then
        error "Timed out waiting for the default service account in namespace '${RUNNER_NAMESPACE}'."
    fi
    # <<< END OF FIX >>>


    info "Patching service account in '${ARC_NAMESPACE}' to use the image pull secret..."
    ${KUBECTL_CMD} patch serviceaccount default -n "${ARC_NAMESPACE}" -p '{"imagePullSecrets": [{"name": "ghcr-io-pull-secret"}]}'
    
    # Also ensure the secret is available for the runners themselves if they are in a different namespace.
    if [[ "${ARC_NAMESPACE}" != "${RUNNER_NAMESPACE}" ]]; then
        info "Runner namespace ('${RUNNER_NAMESPACE}') is different from ARC namespace. Ensuring image pull secret is synced."

        # To make this copy idempotent and avoid conflicts, we get the secret, strip server-managed fields with jq,
        # update the namespace, and then apply it. This safely creates or updates the secret in the target namespace.
        info "Copying/updating image pull secret 'ghcr-io-pull-secret' to '${RUNNER_NAMESPACE}'..."
        local copied_secret_yaml
        copied_secret_yaml=$(${KUBECTL_CMD} get secret ghcr-io-pull-secret -n "${ARC_NAMESPACE}" -o json | \
            jq --arg new_ns "${RUNNER_NAMESPACE}" 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields) | .metadata.namespace = $new_ns')
        if $DEBUG_MODE; then
            info "Applying copied secret YAML:\n$copied_secret_yaml"
        fi
        echo "$copied_secret_yaml" | ${KUBECTL_CMD} apply -f -

        # If RUNNER_NAMESPACE is different, ensure it also has the ghcr-io-pull-secret.
        # We need to ensure both ghcr-io-pull-secret and harbor-credentials are present.
        info "Patching service account in '${RUNNER_NAMESPACE}' to use 'ghcr-io-pull-secret' (if not already present)..."
        # This patch command is designed to ADD the secret if it's not there, without removing others.
        ${KUBECTL_CMD} patch serviceaccount default -n "${RUNNER_NAMESPACE}" -p '{"imagePullSecrets": [{"name": "ghcr-io-pull-secret"}]}'
    fi

    info "Prerequisites configured successfully."
}


# --- Add this function to your setup_arc.sh script ---

# Programmatically checks if the ARC webhook is healthy and attempts a fix if not.
# This is designed to solve the "connect: connection refused" error on the webhook service.
function ensure_arc_webhook_is_healthy() {
  info "--- Starting ARC Webhook Health Check ---"
  local webhook_svc="actions-runner-controller-webhook"
  local arc_ns="actions-runner-system"
  local webhook_url="https://${webhook_svc}.${arc_ns}.svc:443/healthz"
  local tester_pod_name="webhook-tester-$(date +%s)"
  
  info "Creating a temporary pod '${tester_pod_name}' to test webhook connectivity..."
  
  # Use a here-document to create the tester pod. We use busybox for its small size.
  # The pod is created in the same namespace as the controller.
  cat <<EOF | ${KUBECTL_CMD} apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${tester_pod_name}
  namespace: ${arc_ns}
spec:
  containers:
  - name: tester
    image: busybox:1.36
    command: ["/bin/sh", "-c", "sleep 3600"]
  restartPolicy: Never
EOF

  # Wait for the tester pod to be running
  info "Waiting for tester pod to be ready..."
  ${KUBECTL_CMD} wait --for=condition=Ready pod/${tester_pod_name} -n ${arc_ns} --timeout=2m

  info "Performing health check against: ${webhook_url}"
  
  local timeout_seconds=180 # 3 minutes total timeout
  local interval_seconds=10 # Check every 10 seconds
  local end_time=$(( $(date +%s) + timeout_seconds ))
  local webhook_ready=false

  while [[ $(date +%s) -lt ${end_time} ]]; do
    # We use --no-check-certificate because this is an internal, self-signed cert.
    # We are testing L4 connectivity (connection refused) and basic L7 response, not TLS trust.
    # The command returns exit code 0 on success (HTTP 200).
    if ${KUBECTL_CMD} exec -n ${arc_ns} ${tester_pod_name} -- wget -q --spider --timeout=5 --no-check-certificate "${webhook_url}"; then
      webhook_ready=true
      success "ARC webhook is healthy and responsive."
      break
    else
      warn "Webhook not ready yet. Retrying in ${interval_seconds}s..."
      sleep ${interval_seconds}
    fi
  done

  # Cleanup the tester pod regardless of the outcome
  info "Cleaning up tester pod..."
  ${KUBECTL_CMD} delete pod ${tester_pod_name} -n ${arc_ns} --ignore-not-found=true

  if [[ "${webhook_ready}" = false ]]; then
    error "ARC webhook did not become healthy within the timeout."
    read -rp "Do you want to attempt an automated fix by re-initializing MicroK8s networking? (y/N): " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      attempt_microk8s_network_fix
      # After the fix, we call this function again to re-verify.
      ensure_arc_webhook_is_healthy
    else
      error "Automated fix declined. Cannot proceed."
      exit 1
    fi
  fi
}

# Encapsulates the MicroK8s networking fix in its own function
function attempt_microk8s_network_fix() {
  warn "--- Attempting to fix MicroK8s internal networking ---"
  info "This requires sudo and will briefly interrupt cluster networking."
  
  # 1. Disable Calico
  info "Disabling Calico..."
  sudo microk8s disable calico
  sleep 10 # Give it a moment to tear down

  # 2. Re-enable Calico. This forces a fresh configuration.
  info "Re-enabling Calico..."
  sudo microk8s enable calico
  sleep 10 # Give it a moment to initialize

  # 3. Re-enable DNS afterwards, as it depends on the CNI.
  info "Re-enabling DNS..."
  sudo microk8s enable dns

  # 4. Wait for core components to be ready
  info "Waiting for Calico and CoreDNS pods to restart..."
  sleep 15
  ${KUBECTL_CMD} wait --for=condition=Available deployment/coredns -n kube-system --timeout=5m
  
  # 5. Restart the ARC controller to ensure it uses the new network config.
  info "Restarting the ARC controller pod..."
  ${KUBECTL_CMD} delete pod -n ${ARC_NAMESPACE} -l app.kubernetes.io/name=actions-runner-controller
  
  info "Network fix applied. Waiting for ARC to become ready before re-checking..."
  ${KUBECTL_CMD} wait --for=condition=Available --namespace ${ARC_NAMESPACE} deployment/actions-runner-controller --timeout=5m
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
    ensure_arc_webhook_is_healthy
}

# Step 3: Deploy the Self-Hosted Runner
deploy_runner() {
    info "--- Step 3: Deploying the RunnerDeployment ---"

    # The webhook needs a TLS certificate to function. We must wait for cert-manager
    # to issue it before the webhook can start serving traffic. This prevents the
    # "connection refused" error when creating the RunnerDeployment.
    info "Waiting for ARC webhook's TLS certificate to be issued by cert-manager..."
    local cert_name="${ARC_HELM_RELEASE_NAME}-serving-cert"
    ${KUBECTL_CMD} wait --for=condition=Ready=true \
        --namespace "${ARC_NAMESPACE}" \
        certificate.cert-manager.io/"${cert_name}" \
        --timeout=5m
    info "Webhook certificate is ready."

    # Now, wait for the webhook pod to be ready and have its endpoint registered.
    info "Waiting for ARC webhook service to have active endpoints..."
    local webhook_service_name="${ARC_HELM_RELEASE_NAME}-webhook"
    timeout_seconds=120
    start_time=$(date +%s)

    while true; do
        # Check if the endpoints for the webhook service have been populated.
        # The 'subsets' field will be non-empty when the pod is ready and registered.
        local endpoints_ready
        endpoints_ready=$(${KUBECTL_CMD} get endpoints -n "${ARC_NAMESPACE}" "${webhook_service_name}" -o jsonpath='{.subsets}' 2>/dev/null)

        if [ -n "$endpoints_ready" ]; then
            info "ARC webhook is ready."
            break
        fi

        current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

        if [ "$elapsed_time" -ge "$timeout_seconds" ]; then
            error "Timed out waiting for ARC webhook to become available."
        fi

        info "Webhook not ready yet, checking again in 5 seconds..."
        sleep 5
    done

    # Final check: ensure the webhook server inside the pod is actually listening.
    # This addresses the "connection refused" error directly.
    info "Performing active readiness check on ARC webhook endpoint..."
    local webhook_pod_ip
    local webhook_port="9443" # Default webhook port for ARC
    local webhook_healthz_path="/healthz" # Common health check endpoint for Kubernetes webhooks
    timeout_seconds=120
    start_time=$(date +%s)

    while true; do
        # Get the IP of the ARC controller pod (which hosts the webhook)
        webhook_pod_ip=$(${KUBECTL_CMD} get pod -l app.kubernetes.io/name=actions-runner-controller -n "${ARC_NAMESPACE}" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)

        if [ -n "$webhook_pod_ip" ]; then
            # Use curl to hit the healthz endpoint. -k for insecure (self-signed cert), --connect-timeout for quick failure
            if curl -k --connect-timeout 5 "https://${webhook_pod_ip}:${webhook_port}${webhook_healthz_path}" &>/dev/null; then
                success "ARC webhook endpoint is actively listening."
                break
            fi
        fi

        current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

        if [ "$elapsed_time" -ge "$timeout_seconds" ]; then
            error "Timed out waiting for ARC webhook endpoint to become actively listening."
        fi

        info "Webhook endpoint not actively listening yet, checking again in 5 seconds..."
        sleep 5
    done

    if [ ! -f "${RUNNER_DEPLOYMENT_TEMPLATE_FILE}" ]; then
        error "Runner deployment template file not found at '${RUNNER_DEPLOYMENT_TEMPLATE_FILE}'"
    fi

    info "Creating runner namespace '${RUNNER_NAMESPACE}' if it doesn't exist..."
    local runner_namespace_yaml
    runner_namespace_yaml=$(${KUBECTL_CMD} create namespace "${RUNNER_NAMESPACE}" --dry-run=client -o yaml)
    if $DEBUG_MODE; then
        info "Applying runner namespace YAML:\n$runner_namespace_yaml"
    fi
    echo "$runner_namespace_yaml" | ${KUBECTL_CMD} apply -f -

    info "Substituting variables into '${RUNNER_DEPLOYMENT_TEMPLATE_FILE}' and applying..."
    # Export all relevant variables for envsubst
    export GITHUB_REPOSITORY RUNNER_DEPLOYMENT_NAME RUNNER_NAMESPACE RUNNER_REPLICAS
    local runner_deployment_yaml
    runner_deployment_yaml=$(envsubst < "${RUNNER_DEPLOYMENT_TEMPLATE_FILE}")
    if $DEBUG_MODE; then
        info "Applying RunnerDeployment YAML:\n$runner_deployment_yaml"
    fi
    echo "$runner_deployment_yaml" | ${KUBECTL_CMD} apply -f -

    info "RunnerDeployment '${RUNNER_DEPLOYMENT_NAME}' applied successfully."
    info "ARC will now provision ${RUNNER_REPLICAS} runner(s) in the '${RUNNER_NAMESPACE}' namespace."
}

# Step 4: Configure GitHub Secrets and generate workflow
configure_github_extras() {
    info "--- Step 4: Configuring GitHub Secrets & Workflow ---"

    local missing_packages=()
    if ! command -v gh &> /dev/null; then
        missing_packages+=("gh")
    fi
    if ! command -v jq &> /dev/null; then
        missing_packages+=("jq")
    fi

    if [ ${#missing_packages[@]} -gt 0 ]; then
        warn "The following required tools are not installed: ${missing_packages[*]}. They are needed for automatic GitHub secret configuration."
        read -rp "Do you want to attempt to install them now using 'apt'? (Y/n): " install_response
        install_response=${install_response:-y} # Default to 'y'

        if [[ "$install_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            info "Attempting to install missing packages via apt..."
            if ! sudo -n true 2>/dev/null; then
                info "This script needs sudo privileges to install packages. Please enter your password."
            fi
            sudo apt-get update -y || warn "Failed to update apt package lists. Continuing with install attempt..."
            
            info "Running: sudo apt-get install -y ${missing_packages[*]}"
            sudo apt-get install -y "${missing_packages[@]}" || error "Failed to install required packages. Please try installing them manually."

            # Re-check after installation to ensure they are now in the PATH
            if ! command -v gh &> /dev/null || ! command -v jq &> /dev/null; then
                error "Installation seems to have failed or commands are still not available in PATH. Please install 'gh' and 'jq' manually and re-run."
            fi
            info "Successfully installed required tools."
        else
            warn "Skipping automatic GitHub secret configuration and workflow generation because required tools are missing."
            warn "You will need to configure the required secrets in your repository manually."
            return 0
        fi
    fi
    
    read -rp "Do you want to automatically configure GitHub repository secrets (Harbor, Docker Hub, Kubeconfig)? (y/N): " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Logging into GitHub CLI..."
        # Use device-based login without attempting to open a browser,
        # which is suitable for headless servers.
        gh auth login -h github.com -p https

        info "Configuring secrets in '${GITHUB_REPOSITORY}'..."

        # Use environment variables from arc_env.sh if set, otherwise prompt the user.
        HARBOR_URL=${CFG_HARBOR_URL}
        HARBOR_USERNAME=${CFG_HARBOR_USERNAME}
        HARBOR_PASSWORD=${CFG_HARBOR_PASSWORD}

        if [ -z "$HARBOR_URL" ]; then read -rp "Enter your Harbor registry URL (e.g., my-harbor.my-domain.com): " HARBOR_URL; fi
        if [ -z "$HARBOR_USERNAME" ]; then read -rp "Enter the Harbor Robot Account Name for the HARBOR_USERNAME secret (e.g., 'robot\$my-app-github-actions-builder'): " HARBOR_USERNAME; fi
        if [ -z "$HARBOR_PASSWORD" ]; then read -rsp "Enter Harbor password/robot secret: " HARBOR_PASSWORD; echo ""; fi

        if [ -n "$HARBOR_URL" ] && [ -n "$HARBOR_USERNAME" ] && [ -n "$HARBOR_PASSWORD" ]; then
            gh secret set HARBOR_URL --body "${HARBOR_URL}" --repo "${GITHUB_REPOSITORY}"
            gh secret set HARBOR_USERNAME --body "${HARBOR_USERNAME}" --repo "${GITHUB_REPOSITORY}"
            gh secret set HARBOR_PASSWORD --body "${HARBOR_PASSWORD}" --repo "${GITHUB_REPOSITORY}"
            info "Secrets HARBOR_URL, HARBOR_USERNAME, and HARBOR_PASSWORD have been set."
        else
            warn "One or more Harbor credentials were not provided. Skipping Harbor secret creation."
        fi

        # Create Docker Hub secrets if enabled
        if [[ "${CFG_CONFIGURE_DOCKERHUB_SECRET,,}" == "true" || "${CFG_CONFIGURE_DOCKERHUB_SECRET,,}" == "yes" ]]; then
            info "Configuring Docker Hub secrets as requested..."
            DOCKERHUB_USERNAME=${CFG_DOCKERHUB_USERNAME}
            DOCKERHUB_TOKEN=${CFG_DOCKERHUB_TOKEN}

            if [ -z "$DOCKERHUB_USERNAME" ]; then read -rp "Enter your Docker Hub Username: " DOCKERHUB_USERNAME; fi
            if [ -z "$DOCKERHUB_TOKEN" ]; then read -rsp "Enter your Docker Hub Access Token: " DOCKERHUB_TOKEN; echo ""; fi

            if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
                gh secret set DOCKERHUB_USERNAME --body "${DOCKERHUB_USERNAME}" --repo "${GITHUB_REPOSITORY}"
                gh secret set DOCKERHUB_TOKEN --body "${DOCKERHUB_TOKEN}" --repo "${GITHUB_REPOSITORY}"
                success "Secrets DOCKERHUB_USERNAME and DOCKERHUB_TOKEN have been set."
            else
                warn "Docker Hub credentials were not provided. Skipping Docker Hub secret creation."
            fi
        else
            info "Skipping Docker Hub secret creation because CFG_CONFIGURE_DOCKERHUB_SECRET is not set to 'true' in arc_env.sh."
        fi


        info "Generating Kubeconfig for GitHub Actions..."
        # WARNING: The following method of generating a kubeconfig is simple and works for many
        # dev environments (like MicroK8s), but it is NOT recommended for production.
        # It often bundles the admin user's full, short-lived credentials.
        # A better approach is to create a dedicated ServiceAccount in Kubernetes for CI/CD,
        # grant it limited permissions, and use its long-lived token as the secret.
        KUBECONFIG_CONTENT=$(${KUBECTL_CMD} config view --raw)
        gh secret set KUBE_CONFIG --body "${KUBECONFIG_CONTENT}" --repo "${GITHUB_REPOSITORY}"
        info "Secret KUBE_CONFIG has been set."
    else
        warn "Skipping automatic secret configuration."
    fi

    info "Generating sample GitHub Actions workflow file from '${WORKFLOW_TEMPLATE_FILE}'..."
    if [ ! -f "${WORKFLOW_TEMPLATE_FILE}" ]; then
        error "Workflow template file not found at '${WORKFLOW_TEMPLATE_FILE}'"
    fi

    mkdir -p "${GENERATED_WORKFLOW_BASE_DIR}"

    local GENERATED_WORKFLOW_FULL_PATH="${GENERATED_WORKFLOW_BASE_DIR}/${GENERATED_WORKFLOW_FILENAME:-deploy.yaml}"
    info "Substituting variables and saving to '${GENERATED_WORKFLOW_FULL_PATH}'..."
    export HARBOR_PROJECT_NAME HARBOR_IMAGE_NAME K8S_DEPLOYMENT_MANIFEST_PATH RUNNER_NAMESPACE RUNNER_DEPLOYMENT_NAME

    envsubst < "${WORKFLOW_TEMPLATE_FILE}" > "${GENERATED_WORKFLOW_FULL_PATH}"
    info "Generated workflow file at '${GENERATED_WORKFLOW_FULL_PATH}'"
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
    if ${HELM_CMD} status "${ARC_HELM_RELEASE_NAME}" -n "${ARC_NAMESPACE}" &>/dev/null; then
        ${HELM_CMD} uninstall "${ARC_HELM_RELEASE_NAME}" -n "${ARC_NAMESPACE}" --wait
    else
        warn "Helm release '${ARC_HELM_RELEASE_NAME}' not found. Skipping uninstall."
    fi
    
    info "Removing ARC Helm repository '${ARC_HELM_REPO_NAME}' from local configuration..."
    ${HELM_CMD} repo remove "${ARC_HELM_REPO_NAME}" || warn "Could not remove Helm repo '${ARC_HELM_REPO_NAME}'. It might have been removed already."

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

    info "Deleting generated workflow directory '${GENERATED_WORKFLOW_BASE_DIR}'..."
    if [ -d "${GENERATED_WORKFLOW_BASE_DIR}" ]; then
        rm -rf "${GENERATED_WORKFLOW_BASE_DIR}"
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

    check_deps

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
