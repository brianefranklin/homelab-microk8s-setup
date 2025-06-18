#!/bin/bash
# Script to deploy or upgrade Harbor using Helm, with automated password management.
# Note that this script is designed for microk8s.helm3 NOT native helm or helm3.

# If you ever need to reset the Harbor admin password:
# Delete the secret:
# microk8s.kubectl delete secret harbor-admin-password -n harbor
# Then re-run this script to generate a new password and re-deploy Harbor.

# --- CONFIGURE YOUR CORE VALUES HERE ---
# By setting these few base variables, all others will be generated automatically.
export APP_NAME="harbor"
export DOMAIN="yourdomain.com"
export CHART_REPO_NAME="goharbor"
# ----------------------------------------------------

# --- DERIVED VARIABLES (DO NOT EDIT) ---
# These variables are constructed from the core values above.
export HARBOR_HOSTNAME="${APP_NAME}.${DOMAIN}"
export HARBOR_NAMESPACE="${APP_NAME}"
export HELM_RELEASE_NAME="${APP_NAME}"
export SECRET_NAME="${APP_NAME}-admin-password"
export HELM_CHART_NAME="${CHART_REPO_NAME}/${APP_NAME}"
export REPO_NAME="${CHART_REPO_NAME}"
export REPO_URL="https://helm.${CHART_REPO_NAME}.io"
# ----------------------------------------------------

# --- MANAGE HARBOR ADMIN PASSWORD ---
# This block checks if the password secret already exists. If not, it generates one.
# This makes the script safe to re-run for upgrades.

echo "Checking for existing Harbor admin password secret ('$SECRET_NAME')..."

if microk8s.kubectl get secret "$SECRET_NAME" -n "$HARBOR_NAMESPACE" > /dev/null 2>&1; then
    # --- SECRET EXISTS: READ THE EXISTING PASSWORD ---
    echo "✅ Secret found. Reading existing password for upgrade."
    export HARBOR_ADMIN_PASSWORD=$(microk8s.kubectl get secret "$SECRET_NAME" -n "$HARBOR_NAMESPACE" -o jsonpath="{.data.password}" | base64 --decode)

else
    # --- SECRET DOES NOT EXIST: GENERATE AND CREATE A NEW ONE ---
    echo "Secret not found. Generating a new random password..."
    # Generate a new password using openssl
    export HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 16)

    # Inform the user of the new password. THIS IS THE ONLY TIME IT WILL BE DISPLAYED.
    echo "------------------------------------------------------------------"
    echo "IMPORTANT: A new admin password has been generated."
    echo "Harbor Admin Username: admin"
    echo "Harbor Admin Password: $HARBOR_ADMIN_PASSWORD"
    echo "Please save this password in a secure location (e.g., a password manager)."
    echo "------------------------------------------------------------------"

    # Create the Kubernetes secret with the new password
    echo "Creating new secret '$SECRET_NAME'..."
    # Ensure the namespace exists before creating the secret in it
    microk8s.kubectl create namespace "$HARBOR_NAMESPACE" --dry-run=client -o yaml | microk8s.kubectl apply -f -
    
    microk8s.kubectl create secret generic "$SECRET_NAME" -n "$HARBOR_NAMESPACE" \
        --from-literal=password="$HARBOR_ADMIN_PASSWORD"
    echo "✅ New secret created successfully."
fi
echo "---"

# Define the repo name and URL for easy reuse
REPO_NAME="goharbor"
REPO_URL="https://helm.goharbor.io"

# Check if the repository is already added by searching the output of 'helm repo list'
if ! microk8s.helm3 repo list | grep -q "^${REPO_NAME}\s"; then
    # This block runs ONLY if the grep command fails (i.e., the repo is not found)
    echo "Helm repository '$REPO_NAME' not found. Adding it now..."
    microk8s.helm3 repo add "$REPO_NAME" "$REPO_URL"
else
    echo "✅ Helm repository '$REPO_NAME' already configured."
fi

# It's always a good practice to update the repo to ensure you have the latest chart versions
echo "Updating Helm repositories..."
microk8s.helm3 repo update

# --- DEPLOY WITH HELM ---
echo "Deploying Harbor with the following configuration:"
echo "Hostname: $HARBOR_HOSTNAME"
echo "Namespace: $HARBOR_NAMESPACE"
# IMPORTANT: We do NOT echo the password here to avoid exposing it in logs on subsequent runs.
echo "Admin password will be sourced from the '$SECRET_NAME' secret."
echo "---"


# Use envsubst to create the final values file from the template,
# then pipe it to 'helm upgrade --install' using the '-f -' flag.
# 'helm upgrade --install' is idempotent: it will install if it doesn't exist, or upgrade if it does.
envsubst < harbor-values.template.yaml | microk8s.helm3 upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_NAME" \
  --namespace "$HARBOR_NAMESPACE" \
  --create-namespace \
  --atomic \
  --timeout 30m \
  --values -

echo "Harbor deployment script finished. Check above for errors."