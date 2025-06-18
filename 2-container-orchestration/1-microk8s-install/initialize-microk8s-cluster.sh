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


# --- Final Instructions ---
print_header "INITIALIZATION SCRIPT COMPLETED"

echo ""
echo "All automated steps are finished. Please complete the following manual steps:"
echo ""
echo "1. IMPORTANT: For the 'kubectl' and 'helm' aliases to work, you must either:"
echo "   a) Close and reopen your terminal session."
echo "   b) Or run the following command in your current session: source ~/.bash_aliases"
echo ""
echo "2. Create the AWS Credentials Secret for cert-manager."
echo "   Replace 'YOUR_AWS_SECRET_ACCESS_KEY' with your actual key and run the following command:"
echo ""
echo "   kubectl -n $CERT_MANAGER_NAMESPACE create secret generic harbor-letsencrypt-route53-credentials \\"
echo "     --from-literal=harbor-letsencrypt-route53-secret-access-key='YOUR_AWS_SECRET_ACCESS_KEY'"
echo ""

# End of script
