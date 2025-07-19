#!/bin/bash
# Script to deploy or upgrade Harbor using Helm, with automated password management.
# Note that this script is designed for microk8s.helm3 NOT native helm or helm3.

# If you ever need to reset the Harbor admin password:
# Delete the secret:
# microk8s.kubectl delete secret harbor-admin-password -n harbor
# Then re-run this script to generate a new password and re-deploy Harbor.

# --- Source Shared Environment Variables ---
if [ -n "$1" ]; then
    HARBOR_ENV_PATH="$1"
    echo "--- Using configuration file from command line argument: $HARBOR_ENV_PATH ---"
else
    HARBOR_ENV_PATH="../harbor_env.sh" # Default path relative to this script
    echo "--- Using default configuration file: $HARBOR_ENV_PATH ---"
fi

if [ -f "$HARBOR_ENV_PATH" ]; then
    # shellcheck source=../harbor_env.sh
    source "$HARBOR_ENV_PATH"
else
    echo "❌ ERROR: Shared environment file '$HARBOR_ENV_PATH' not found." >&2
    exit 1
fi

# --- Validate Required Variables from harbor_env.sh ---
REQUIRED_VARS=(
    "HARBOR_INSTANCE_NAME" "HARBOR_DOMAIN" "HARBOR_PROTOCOL"
    "HARBOR_CHART_REPO_ALIAS" "HARBOR_CHART_REPO_URL" "KUBECTL_CMD" "HELM_CMD"
)
for VAR_NAME in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR_NAME}" ]; then
        echo "❌ ERROR: Required variable '$VAR_NAME' is not set in '$HARBOR_ENV_PATH'." >&2
        exit 1
    fi
done

# --- DERIVED VARIABLES (Constructed from sourced HARBOR_INSTANCE_NAME, HARBOR_DOMAIN, etc.) ---
export HARBOR_HOSTNAME="${HARBOR_INSTANCE_NAME}.${HARBOR_DOMAIN}"
export HARBOR_NAMESPACE="${HARBOR_INSTANCE_NAME}"
export HELM_RELEASE_NAME="${HARBOR_INSTANCE_NAME}"
export SECRET_NAME="${HARBOR_INSTANCE_NAME}-admin-password" # Secret for admin password
export HELM_CHART_NAME="${HARBOR_CHART_REPO_ALIAS}/${HARBOR_INSTANCE_NAME}" # Assumes chart name is 'harbor' or same as instance_name
# ----------------------------------------------------

# --- MANAGE HARBOR ADMIN PASSWORD ---
# This block checks if the password secret already exists. If not, it generates one.
# This makes the script safe to re-run for upgrades.
echo "Checking for existing Harbor admin password secret ('$SECRET_NAME')..."

if $KUBECTL_CMD get secret "$SECRET_NAME" -n "$HARBOR_NAMESPACE" > /dev/null 2>&1; then
    # --- SECRET EXISTS: READ THE EXISTING PASSWORD ---
    echo "✅ Secret found. Reading existing password for upgrade."
    export HARBOR_ADMIN_PASSWORD=$($KUBECTL_CMD get secret "$SECRET_NAME" -n "$HARBOR_NAMESPACE" -o jsonpath="{.data.password}" | base64 --decode)

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
    $KUBECTL_CMD create namespace "$HARBOR_NAMESPACE" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
    
    $KUBECTL_CMD create secret generic "$SECRET_NAME" -n "$HARBOR_NAMESPACE" \
        --from-literal=password="$HARBOR_ADMIN_PASSWORD"
    echo "✅ New secret created successfully."
fi
echo "---"

# Check if the repository is already added by searching the output of 'helm repo list'
if ! $HELM_CMD repo list | grep -q "^${HARBOR_CHART_REPO_ALIAS}\s"; then
    # This block runs ONLY if the grep command fails (i.e., the repo is not found)
    echo "Helm repository '$HARBOR_CHART_REPO_ALIAS' not found. Adding it now from '$HARBOR_CHART_REPO_URL'..."
    $HELM_CMD repo add "$HARBOR_CHART_REPO_ALIAS" "$HARBOR_CHART_REPO_URL"
else
    echo "✅ Helm repository '$HARBOR_CHART_REPO_ALIAS' already configured."
fi

# It's always a good practice to update the repo to ensure you have the latest chart versions
echo "Updating Helm repositories..."
$HELM_CMD repo update

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
envsubst < harbor-values.template.yaml | $HELM_CMD upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_NAME" \
  --namespace "$HARBOR_NAMESPACE" \
  --create-namespace \
  --atomic \
  --timeout 30m \
  --values -

echo "Harbor deployment script finished. Check above for errors."