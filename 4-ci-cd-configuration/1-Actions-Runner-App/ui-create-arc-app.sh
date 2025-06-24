#!/bin/bash
#
# ui-create-arc-app.sh
# This script guides an administrator to create a REPOSITORY-LEVEL GitHub App for ARC
# by instructing them on what values to enter into the GitHub UI.
# After the App is created in the UI, this script will prompt for the
# App ID, Webhook Secret, and Private Key to generate the Kubernetes secret.
#

set -e

# Path to the shared environment file.
# This script is in '1-Actions-Runner-App', arc_env.sh is in the parent '4-ci-cd-configuration' directory.
ARC_ENV_PATH="../arc_env.sh"

# Source shared environment variables.
if [ -f "$ARC_ENV_PATH" ]; then
    # shellcheck source=../arc_env.sh
    source "$ARC_ENV_PATH"
else
    echo "ERROR: Shared environment file not found at '$ARC_ENV_PATH'." >&2
    echo "Please ensure 'arc_env.sh' exists in the parent directory ('4-ci-cd-configuration/') and is configured." >&2
    exit 1
fi

# Validate configuration
if [ "$GITHUB_REPOSITORY" == "your-username/your-repo-name" ] || [ -z "$GITHUB_REPOSITORY" ]; then
    echo "ERROR: GITHUB_REPOSITORY is not configured or still has the default placeholder in '$ARC_ENV_PATH'." >&2
    echo "Please edit '$ARC_ENV_PATH' and set GITHUB_REPOSITORY to your 'owner/repository' slug." >&2
    exit 1
fi

REQUIRED_VARS_UI_CREATE_APP=("ARC_NAMESPACE" "ARC_CONTROLLER_SECRET_NAME" "APP_CREATION_REDIRECT_URL" "KUBECTL_CMD")
for VAR_NAME in "${REQUIRED_VARS_UI_CREATE_APP[@]}"; do
    if [ -z "${!VAR_NAME}" ]; then
        echo "ERROR: Required variable '$VAR_NAME' is not set in '$ARC_ENV_PATH'." >&2
        echo "Please configure this variable in '$ARC_ENV_PATH' before running this script." >&2
        exit 1
    fi
done

echo "--- GitHub App Creation via UI for Repository: ${GITHUB_REPOSITORY} ---"
echo
echo "This script will guide you through creating a GitHub App using the GitHub web UI."
echo "Please open the following URL in your web browser to start:"
echo
echo "https://github.com/settings/apps/new"
echo
echo "--- Fill in the GitHub App registration form as follows: ---"
echo
echo "1.  GitHub App name:"
echo "    Enter: ARC Runner for ${GITHUB_REPOSITORY}"
echo
echo "2.  Homepage URL:"
echo "    Enter: https://github.com/${GITHUB_REPOSITORY}"
echo
echo "3.  Callback URL (Identifying and authorizing users section):"
echo "    Enter: ${APP_CREATION_REDIRECT_URL}"
echo "    (Note: This is primarily for OAuth flows. For ARC's server-to-server auth, it's less critical but good to set.)"
echo
echo "4.  Expire user authorization tokens:"
echo "    Leave UNCHECKED (default)."
echo
echo "5.  Request user authorization (OAuth) during installation:"
echo "    Leave UNCHECKED. (ARC uses server-to-server authentication with a private key)."
echo
echo "6.  Enable Device Flow:"
echo "    Leave UNCHECKED."
echo
echo "7.  Post installation - Setup URL (optional):"
echo "    Leave BLANK."
echo
echo "8.  Post installation - Redirect on update:"
echo "    Leave UNCHECKED."
echo
echo "9.  Webhook:"
echo "    - Active: CHECKED."
echo "    - Webhook URL: You can leave this BLANK for now. You will update this URL later"
echo "      after deploying Actions Runner Controller and exposing its webhook endpoint."
echo "      (It will typically be something like <YOUR_CONTROLLER_INGRESS_ADDRESS>/github-webhook/)"
echo "    - Webhook Secret: Click 'Generate a new secret' or provide your own secure secret."
echo "      IMPORTANT: Copy this secret value and save it. You will be prompted for it by this script later."
echo
echo "10. Permissions -> Repository permissions:"
echo "    - Administration: Select 'Read-only'."
echo "    - Contents: Select 'Read-only'."
echo "    - Pull requests: Select 'Read-only'."
echo "    - Self-hosted runners: Select 'Read and write' (This is essential for ARC)."
echo "    (Leave other Repository, Organization, and Account permissions as 'No access' unless you have specific needs)."
echo
echo "11. Permissions -> Subscribe to events:"
echo "    You can leave this with the default selections based on permissions, or specifically select:"
echo "    - Workflow job (Often used by ARC for scaling runners)."
echo "    (For basic ARC functionality, the permissions granted are key. GitHub will send relevant webhooks.)"
echo
echo "12. Where can this GitHub App be installed?"
echo "    Select 'Only on this account'. (If you are the owner of the repository ${GITHUB_REPOSITORY})."
echo "    If the repository is in an organization you own, you'll select that organization."
echo
echo "13. Click 'Create GitHub App'."
echo
echo "--- After Creating the App ---"
echo "You will be taken to the App's settings page."
echo
echo "14. Generate a Private Key:"
echo "    Scroll down to the 'Private keys' section."
echo "    Click 'Generate a private key'. A .pem file will be downloaded."
echo "    IMPORTANT: Save this .pem file to a known location on your computer."
echo "               You will be prompted for the full path to this file by the script."
echo
echo "15. Note the App ID:"
echo "    At the top of the App's settings page, find the 'App ID'. Copy it."
echo
echo "16. Install the App:"
echo "    In the left sidebar of the App's settings page, click 'Install App'."
echo "    Find your account or organization (owner of ${GITHUB_REPOSITORY}) and click 'Install'."
echo "    On the next page, select 'Only select repositories' and choose '${GITHUB_REPOSITORY}'."
echo "    Click 'Install'."
echo
echo "--- Provide Credentials to This Script ---"
echo "Please enter the following details from the GitHub App you just created:"
echo

read -r -p "Enter the App ID: " APP_ID
while [[ -z "$APP_ID" ]]; do
    read -r -p "App ID cannot be empty. Please enter the App ID: " APP_ID
done

read -r -sp "Enter the Webhook Secret: " WEBHOOK_SECRET_INPUT
echo
while [[ -z "$WEBHOOK_SECRET_INPUT" ]]; do
    read -r -sp "Webhook Secret cannot be empty. Please enter the Webhook Secret: " WEBHOOK_SECRET_INPUT
    echo
done

read -r -p "Enter the full path to the downloaded private key .pem file: " PRIVATE_KEY_PEM_FILE_PATH
while true; do
    if [[ -z "$PRIVATE_KEY_PEM_FILE_PATH" ]]; then
        read -r -p "Private key file path cannot be empty. Please enter the path: " PRIVATE_KEY_PEM_FILE_PATH
    elif [[ ! -f "$PRIVATE_KEY_PEM_FILE_PATH" ]]; then
        if [[ -d "$PRIVATE_KEY_PEM_FILE_PATH" ]]; then
             read -r -p "Path '$PRIVATE_KEY_PEM_FILE_PATH' is a directory, not a file. Please enter a valid file path: " PRIVATE_KEY_PEM_FILE_PATH
        else
             read -r -p "File not found at '$PRIVATE_KEY_PEM_FILE_PATH'. Please enter a valid path: " PRIVATE_KEY_PEM_FILE_PATH
        fi
    elif [[ ! -r "$PRIVATE_KEY_PEM_FILE_PATH" ]]; then
        read -r -p "File at '$PRIVATE_KEY_PEM_FILE_PATH' is not readable. Please check permissions and enter a valid path: " PRIVATE_KEY_PEM_FILE_PATH
    else
        echo "✅ Private key file found and readable: ${PRIVATE_KEY_PEM_FILE_PATH}"
        break 
    fi
done
 
echo
echo "Credentials received."
echo
echo "--- FINAL STEP ---"
echo "Copy the entire '${KUBECTL_CMD}' command below and run it to create the Kubernetes secret for ARC."
echo "--------------------------------------------------------------------------------"
# Generate the final kubectl command.
cat <<FINAL_CMD
${KUBECTL_CMD} create secret generic "${ARC_CONTROLLER_SECRET_NAME}" \\
  --namespace="${ARC_NAMESPACE}" \\
  --from-literal=github_app_id="${APP_ID}" \\
  --from-literal=github_webhook_secret="${WEBHOOK_SECRET_INPUT}" \\
  --from-file=github_private_key="${PRIVATE_KEY_PEM_FILE_PATH}"
FINAL_CMD
echo "--------------------------------------------------------------------------------"
echo
echo "After creating the secret, remember to update the Webhook URL in your GitHub App settings"
echo "once your Actions Runner Controller is deployed and publicly accessible."

exit 0