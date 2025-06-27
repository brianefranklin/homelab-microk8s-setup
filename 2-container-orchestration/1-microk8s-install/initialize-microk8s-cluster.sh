#!/bin/bash
#
# Idempotent script to install and configure MicroK8s, Helm, and Cert-Manager.
# This script prepares the environment and automatically handles group permission
# changes to complete the installation in a single run.
#
# If recovering from a failed or misconfigured install:
# sudo snap remove microk8s --purge

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
CERT_MANAGER_NAMESPACE="cert-manager"
CURRENT_USER=$(whoami)

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

# Ensures the host system is using iptables-legacy mode, which is required
# by MicroK8s's networking components (kube-proxy/kubelite) to correctly
# program firewall rules for services like NodePorts.
ensure_iptables_legacy_mode() {
    print_header "Verifying Host IPTables Mode for MicroK8s Compatibility"

    # On modern Debian/Ubuntu systems, iptables can operate in two modes:
    # 1. 'nft' (the new default): Rules are managed by the nftables kernel subsystem.
    # 2. 'legacy': Rules are managed by the older, traditional iptables subsystem.
    #
    # MicroK8s's internal kube-proxy is compiled to write its rules to the 'legacy'
    # tables. If the host OS is in 'nft' mode, a "split-brain" occurs: Kubernetes
    # writes rules to one table, but the kernel only enforces the other, empty table.
    # This leads to NodePort services being unreachable.

    if ! update-alternatives --query iptables | grep -q 'Value: /usr/sbin/iptables-legacy'; then
        warn "Host is not using iptables-legacy mode. This can cause NodePort services to fail."
        info "Attempting to switch the system's default to iptables-legacy..."
        
        sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
        sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        success "Switched iptables mode to legacy."
        
        info "Restarting MicroK8s to apply the new networking mode..."
        sudo microk8s stop
        sudo microk8s start
        
        info "Waiting for MicroK8s to stabilize after restart..."
        sudo microk8s status --wait-ready
        
        success "MicroK8s restarted successfully with the correct iptables mode."
    else
        success "Host is already configured for iptables-legacy mode."
    fi
}

# --- Function to create the AWS secret for cert-manager ---
create_aws_secret() {
    print_header "Creating AWS Secret for Cert-Manager DNS-01 Challenge"

    # Source config file to get variable names
    local config_file="../config/env.sh"
    if [ ! -f "$config_file" ]; then
        error "Configuration file '$config_file' not found. Cannot create AWS secret."
    fi
    # shellcheck source=../config/env.sh
    source "$config_file"

    # Check if the secret already exists
    if ${KUBECTL_CMD} get secret "$CERT_MANAGER_AWS_SECRET_NAME" -n "$CERT_MANAGER_NAMESPACE" &>/dev/null; then
        warn "Secret '$CERT_MANAGER_AWS_SECRET_NAME' already exists in namespace '$CERT_MANAGER_NAMESPACE'. Skipping creation."
        return 0
    fi

    # Determine the AWS Secret Access Key
    local aws_secret_key=""
    if [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        info "Using AWS_SECRET_ACCESS_KEY from environment file."
        aws_secret_key="$AWS_SECRET_ACCESS_KEY"
    else
        info "AWS_SECRET_ACCESS_KEY not found in environment file."
        read -sp "Please enter your AWS Secret Access Key (will not be echoed): " aws_secret_key
        echo # Add a newline after the prompt
    fi

    if [ -z "$aws_secret_key" ]; then
        error "AWS Secret Access Key was not provided. Cannot create secret."
    fi

    # Create the secret
    info "Creating secret '$CERT_MANAGER_AWS_SECRET_NAME' in namespace '$CERT_MANAGER_NAMESPACE'..."
    ${KUBECTL_CMD} -n "$CERT_MANAGER_NAMESPACE" create secret generic "$CERT_MANAGER_AWS_SECRET_NAME" \
      --from-literal="$CERT_MANAGER_AWS_SECRET_KEY_NAME"="$aws_secret_key"

    success "AWS secret created successfully."
}

# --- Main Script ---

# Step 1: Install and Configure MicroK8s
print_header "Installing and Configuring MicroK8s"

# Install MicroK8s via Snap. Snap install is idempotent.
echo "Installing microk8s snap..."
sudo snap install microk8s --classic

# Ensure host is using iptables-legacy for MicroK8s compatibility
ensure_iptables_legacy_mode

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
add_alias_if_not_exists "alias kubectl='microk8s kubectl'"

# Wait for MicroK8s to be ready before enabling addons.
echo "Waiting for MicroK8s to be ready..."
microk8s status --wait-ready

# Enable required addons. The 'enable' command is idempotent.
echo "Enabling MicroK8s addons: dns, storage, ingress, helm3..."
microk8s enable dns
microk8s enable hostpath-storage
microk8s enable ingress
microk8s enable helm3 # This also handles Helm installation.

echo "Waiting for addon components to become ready..."
microk8s kubectl wait --for=condition=Ready pod --all -n kube-system --timeout=5m
microk8s kubectl wait --for=condition=Ready pod --all -n ingress --timeout=5m


# Step 2: Configure Helm Alias
print_header "Configuring Helm"

# Add helm alias.
add_alias_if_not_exists "alias helm='microk8s helm3'"

echo "Verifying Helm installation..."
microk8s helm3 version

# Step 3: Install and Configure cert-manager
print_header "Installing and Configuring cert-manager"

# Add the Jetstack Helm repository if it doesn't exist.
if ! microk8s helm3 repo list | grep -q 'https://charts.jetstack.io'; then
    echo "Adding Jetstack Helm repository..."
    microk8s helm3 repo add jetstack https://charts.jetstack.io
else
    echo "Jetstack Helm repository already exists."
fi

echo "Updating Helm repositories..."
microk8s helm3 repo update

# Use 'helm upgrade --install' to make the installation idempotent.
# This will install the chart if it's not present, or upgrade it if it is.
echo "Installing/Upgrading cert-manager..."
microk8s helm3 upgrade --install cert-manager jetstack/cert-manager \
  --namespace "$CERT_MANAGER_NAMESPACE" \
  --create-namespace \
  --set crds.enabled=true

echo "Waiting for cert-manager pods to be ready..."
microk8s kubectl wait --for=condition=Ready pod --all -n "$CERT_MANAGER_NAMESPACE" --timeout=5m

# Step 4: Create AWS Secret for Cert-Manager
create_aws_secret

# --- Final Instructions ---
print_header "INITIALIZATION SCRIPT COMPLETED"

echo ""
echo "All automated steps are finished."
echo ""
echo "IMPORTANT: For the 'kubectl' and 'helm' aliases to work, you must either:"
echo "   a) Close and reopen your terminal session."
echo "   b) Or run the following command in your current session: source ~/.bash_aliases"
echo ""

# End of script
