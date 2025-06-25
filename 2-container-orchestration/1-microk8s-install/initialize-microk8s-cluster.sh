#!/bin/bash
#
# Idempotent script to install and configure MicroK8s, Helm, and Cert-Manager.
# This script prepares the environment and automatically handles group permission
# changes to complete the installation in a single run.
#
# If recovering from a failed or misconfigured install:
# sudo snap remove microk8s --purge

set -e # Exit immediately if a command exits with a non-zero status.

# --- Source Environment Configuration ---
CONFIG_FILE="../config/env.sh"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=../config/env.sh
    source "$CONFIG_FILE"
    echo "✅ Loaded configuration from $CONFIG_FILE"
else
    echo "❌ ERROR: Configuration file '$CONFIG_FILE' not found." >&2
    echo "Please create it in the same directory as this script." >&2
    exit 1
fi

# The user running the script, determined by the env file.
CURRENT_USER=${TARGET_USER}
# --- Helper Functions ---
# Function to print a formatted header
print_header() {
    echo ""
    echo "===================================================================="
    echo "=> $1"
    echo "===================================================================="
}

# Function to add an alias to ~/.bash_aliases if it doesn't already exist
add_alias_if_not_exists() {
    local alias_string="$1"
    local alias_file="$HOME/.bash_aliases"
    touch "$alias_file" # Ensure the file exists
    if ! grep -Fq "$alias_string" "$alias_file"; then
        echo "Adding alias to $alias_file: $alias_string"
        echo "$alias_string" >> "$alias_file"
    else
        echo "Alias already exists in $alias_file: $alias_string"
    fi
}


# --- Main Script ---

# Step 1: Install and Configure MicroK8s
print_header "Installing and Configuring MicroK8s"

# Install MicroK8s via Snap. Snap install is idempotent.
echo "Installing microk8s snap..."
sudo snap install microk8s --classic

# Add the current user to the microk8s group if not already a member.
if ! id -nG "$CURRENT_USER" | grep -qw "microk8s"; then
    echo "Adding user '$CURRENT_USER' to the 'microk8s' group..."
    sudo usermod -aG microk8s "$CURRENT_USER"

    # --- AUTOMATIC RE-EXECUTION LOGIC ---
    # The 'usermod' command has run, but the current shell session doesn't have the
    # new group permissions yet. We use 'sg' to re-execute this script with the
    # correct group context. The 'exec' command replaces the current script
    # process with the new one.
    echo "Group membership updated. Re-executing script with new permissions..."
    exec sg microk8s -c "$0 $*"
fi

# The script will continue from here ONLY when it has the correct permissions.
echo "User '$CURRENT_USER' is an active member of the 'microk8s' group."

# Create .kube directory and set permissions.
echo "Ensuring ~/.kube directory exists and has correct ownership..."
mkdir -p "$HOME/.kube"
sudo chown -f -R "$CURRENT_USER" "$HOME/.kube"
# Add kubectl alias.
add_alias_if_not_exists "alias kubectl='${KUBECTL_CMD}'"

# Wait for MicroK8s to be ready before enabling addons.
echo "Waiting for MicroK8s to be ready..."
microk8s status --wait-ready

# Enable required addons. The 'enable' command is idempotent.
echo "Enabling MicroK8s addons: ${MICROK8S_ADDONS[*]}..."
for addon in "${MICROK8S_ADDONS[@]}"; do
    echo "-> Enabling $addon"
    microk8s enable "$addon"
done

echo "Waiting for addon components to become ready..."
${KUBECTL_CMD} wait --for=condition=Ready pod --all -n kube-system --timeout=5m
# The ingress namespace might not exist if 'ingress' is not in the addons list.
if [[ " ${MICROK8S_ADDONS[*]} " =~ " ingress " ]]; then
    ${KUBECTL_CMD} wait --for=condition=Ready pod --all -n ingress --timeout=5m
fi


# Step 2: Configure Helm Alias
print_header "Configuring Helm"

# Add helm alias.
add_alias_if_not_exists "alias helm='${HELM_CMD}'"

echo "Verifying Helm installation..."
${HELM_CMD} version

# Step 3: Install and Configure cert-manager
print_header "Installing and Configuring cert-manager"

# Add the Jetstack Helm repository if it doesn't exist.
if ! ${HELM_CMD} repo list | grep -q "${CERT_MANAGER_HELM_REPO_URL}"; then
    echo "Adding Helm repository '${CERT_MANAGER_HELM_REPO_ALIAS}' from '${CERT_MANAGER_HELM_REPO_URL}'..."
    ${HELM_CMD} repo add "${CERT_MANAGER_HELM_REPO_ALIAS}" "${CERT_MANAGER_HELM_REPO_URL}"
else
    echo "Helm repository '${CERT_MANAGER_HELM_REPO_ALIAS}' already exists."
fi

echo "Updating Helm repositories..."
${HELM_CMD} repo update

# Use 'helm upgrade --install' to make the installation idempotent.
# This will install the chart if it's not present, or upgrade it if it is.
echo "Installing/Upgrading cert-manager..."
${HELM_CMD} upgrade --install "${CERT_MANAGER_HELM_RELEASE_NAME}" "${CERT_MANAGER_HELM_CHART}" \
  --namespace "${CERT_MANAGER_NAMESPACE}" \
  --create-namespace \
  --set crds.enabled=true

echo "Waiting for cert-manager pods to be ready..."
${KUBECTL_CMD} wait --for=condition=Ready pod --all -n "${CERT_MANAGER_NAMESPACE}" --timeout=5m


# --- Final Step: AWS Secret Creation ---
print_header "Final Step: AWS Secret Creation"

# Check if the AWS secret already exists.
if ${KUBECTL_CMD} get secret "${CERT_MANAGER_AWS_SECRET_NAME}" -n "${CERT_MANAGER_NAMESPACE}" &> /dev/null; then
    echo "✅ AWS credentials secret '${CERT_MANAGER_AWS_SECRET_NAME}' already exists. No action needed."
else
    # If the secret doesn't exist, check if the environment variable is set for automatic creation.
    # The AWS_SECRET_ACCESS_KEY is intentionally not a required variable.
    if [ -n "${AWS_SECRET_ACCESS_KEY}" ]; then
        echo "AWS_SECRET_ACCESS_KEY variable is set. Automatically creating the secret..."
        ${KUBECTL_CMD} -n "${CERT_MANAGER_NAMESPACE}" create secret generic "${CERT_MANAGER_AWS_SECRET_NAME}" \
          --from-literal="${CERT_MANAGER_AWS_SECRET_KEY_NAME}=${AWS_SECRET_ACCESS_KEY}"
        echo "✅ AWS credentials secret '${CERT_MANAGER_AWS_SECRET_NAME}' created successfully."
    else
        # If the variable is not set, provide manual instructions.
        echo "⚠️  Action Required: The AWS secret key was not provided for automatic creation."
        echo "   The next script ('apply-clusterissuer.sh') requires this secret to exist."
        echo "   Please create it manually by running the following commands:"
        echo ""
        echo "   # 1. Use the secure prompt to set the key in your shell:"
        echo "   read -s -p \"Enter AWS Secret Access Key: \" AWS_SECRET_KEY && export AWS_SECRET_KEY"
        echo ""
        echo "   # 2. Run the kubectl command:"
        echo "   ${KUBECTL_CMD} -n ${CERT_MANAGER_NAMESPACE} create secret generic ${CERT_MANAGER_AWS_SECRET_NAME} \\"
        echo "     --from-literal=${CERT_MANAGER_AWS_SECRET_KEY_NAME}=\"\$AWS_SECRET_KEY\""
    fi
fi

# --- Final Instructions ---
print_header "INITIALIZATION SCRIPT COMPLETED"

echo ""
echo "1. IMPORTANT: For the 'kubectl' and 'helm' aliases to work, you must either:"
echo "   a) Close and reopen your terminal session."
echo "   b) Or run the following command in your current session: source ~/.bash_aliases"
echo ""
echo "2. AWS Secret Status:"
if ${KUBECTL_CMD} get secret "${CERT_MANAGER_AWS_SECRET_NAME}" -n "${CERT_MANAGER_NAMESPACE}" &> /dev/null; then
    echo "   ✅ The AWS secret '${CERT_MANAGER_AWS_SECRET_NAME}' is present in the cluster."
else
    echo "   ❌ The AWS secret '${CERT_MANAGER_AWS_SECRET_NAME}' is NOT yet present. Please create it using the instructions above."
fi

# End of script
