#!/bin/bash
#
# ARC Doctor - A comprehensive diagnostic script for Actions Runner Controller
#
# This script performs a series of checks to diagnose common issues with ARC,
# particularly when runners are running but jobs remain queued.

# --- Helper Functions for Logging ---
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
check() { echo -e "\n\033[0;36m🔎 [CHECK] $1\033[0m"; }
ok() { echo -e "\033[0;32m✅ [OK]\033[0m $1"; }
warn() { echo -e "\033[0;33m⚠️ [WARN]\033[0m $1"; }
fail() { echo -e "\033[0;31m❌ [FAIL]\033[0m $1"; }
output_header() { echo -e "\n\033[0;35m--- START: $1 ---\033[0m"; }
output_footer() { echo -e "\033[0;35m--- END: $1 ---\033[0m"; }

# Function to run a command and capture its output, including headers
run_and_capture() {
    local title="$1"
    shift
    local cmd="$@"
    output_header "$title"
    echo "Running command: $cmd"
    echo "--------------------------------------------------"
    # Execute command, redirecting stderr to stdout to capture everything
    if ! eval "$cmd" 2>&1; then
        warn "Command failed to execute or returned a non-zero exit code."
    fi
    output_footer "$title"
}

# --- Main Script ---
clear
echo "================================================================="
echo "          Actions Runner Controller (ARC) Doctor"
echo "================================================================="
echo

# --- Source Environment Variables ---
# Determine the configuration file path. Use the first argument if provided, otherwise use the default.
DEFAULT_CONFIG_PATH="../../arc_env.conf"
CONFIG_PATH="${1:-$DEFAULT_CONFIG_PATH}"

if [[ "$1" ]]; then
    info "Using configuration file from command line argument: ${CONFIG_PATH}"
else
    info "Using default configuration file: ${CONFIG_PATH}"
fi

if [ ! -f "${CONFIG_PATH}" ]; then
    fail "Configuration file '${CONFIG_PATH}' not found. Cannot proceed."
    exit 1
fi
# The shellcheck directive below is for static analysis of the default file.
# shellcheck source=../../arc_env.conf
source "${CONFIG_PATH}"
info "Loaded configuration from '${CONFIG_PATH}'."
info "Target GitHub Repository: ${GITHUB_REPOSITORY}"
info "ARC Namespace: ${ARC_NAMESPACE}"
info "Runner Namespace: ${RUNNER_NAMESPACE}"
echo "-----------------------------------------------------------------"
sleep 2

# === LAYER 1: CLUSTER & CORE COMPONENTS HEALTH ===
check "Checking Kubernetes Node Status"
run_and_capture "kubectl get nodes -o wide" "${KUBECTL_CMD} get nodes -o wide"

check "Checking Core System Pod Health (kube-system, cert-manager)"
run_and_capture "kubectl get pods -n kube-system" "${KUBECTL_CMD} get pods -n kube-system"
run_and_capture "kubectl get pods -n cert-manager" "${KUBECTL_CMD} get pods -n cert-manager"


# === LAYER 2: CERT-MANAGER & WEBHOOK HEALTH ===
check "Verifying ARC Certificate Issuance"
CERT_STATUS=$(${KUBECTL_CMD} get certificate -n ${ARC_NAMESPACE} ${ARC_HELM_RELEASE_NAME}-serving-cert -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [[ "$CERT_STATUS" == "True" ]]; then
    ok "ARC Certificate object is 'Ready'."
else
    fail "ARC Certificate object is NOT 'Ready'. Status: ${CERT_STATUS:-'Not Found'}"
fi
run_and_capture "Describe ARC Certificate" "${KUBECTL_CMD} describe certificate -n ${ARC_NAMESPACE} ${ARC_HELM_RELEASE_NAME}-serving-cert"

check "Verifying ARC Webhook TLS Secret"
if ${KUBECTL_CMD} get secret -n ${ARC_NAMESPACE} ${ARC_HELM_RELEASE_NAME}-serving-cert &>/dev/null; then
    ok "ARC webhook TLS secret exists."
else
    fail "ARC webhook TLS secret '${ARC_HELM_RELEASE_NAME}-serving-cert' was NOT found. cert-manager is failing."
fi


# === LAYER 3: ARC CONTROLLER HEALTH & CONFIGURATION ===
check "Checking ARC Controller Pod Status"
ARC_POD=$(${KUBECTL_CMD} get pods -n ${ARC_NAMESPACE} -l app.kubernetes.io/name=actions-runner-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$ARC_POD" ]]; then
    fail "ARC Controller pod not found in namespace '${ARC_NAMESPACE}'."
else
    ok "Found ARC Controller Pod: ${ARC_POD}"
    run_and_capture "Describe ARC Controller Pod" "${KUBECTL_CMD} describe pod -n ${ARC_NAMESPACE} ${ARC_POD}"
    run_and_capture "Logs for ARC Controller Pod (last 100 lines)" "${KUBECTL_CMD} logs -n ${ARC_NAMESPACE} ${ARC_POD} --tail=100"
fi

check "Verifying Credentials in Live Cluster Secret"
output_header "Decoded Secret Credentials"
echo "Comparing live secret data against arc_env.conf..."
echo "--------------------------------------------------"
# App ID
SECRET_APP_ID=$(${KUBECTL_CMD} get secret ${ARC_CONTROLLER_SECRET_NAME} -n ${ARC_NAMESPACE} -o jsonpath='{.data.github_app_id}' 2>/dev/null | base64 --decode)
echo "App ID from Secret:      ${SECRET_APP_ID}"
echo "App ID from arc_env.conf:  ${CFG_GITHUB_APP_ID}"
if [[ "$SECRET_APP_ID" == "$CFG_GITHUB_APP_ID" ]]; then ok "App IDs match."; else fail "App IDs DO NOT MATCH."; fi
# Installation ID
SECRET_INSTALL_ID=$(${KUBECTL_CMD} get secret ${ARC_CONTROLLER_SECRET_NAME} -n ${ARC_NAMESPACE} -o jsonpath='{.data.github_app_installation_id}' 2>/dev/null | base64 --decode)
echo "Install ID from Secret:     ${SECRET_INSTALL_ID}"
echo "Install ID from arc_env.conf: ${CFG_GITHUB_APP_INSTALLATION_ID}"
if [[ "$SECRET_INSTALL_ID" == "$CFG_GITHUB_APP_INSTALLATION_ID" ]]; then ok "Installation IDs match."; else fail "Installation IDs DO NOT MATCH."; fi
# Private Key
echo "Verifying private key integrity..."
LOCAL_KEY_SUM=$(sha256sum "${CFG_GITHUB_APP_PRIVATE_KEY_PATH}" | awk '{print $1}')
SECRET_KEY_SUM=$(${KUBECTL_CMD} get secret ${ARC_CONTROLLER_SECRET_NAME} -n ${ARC_NAMESPACE} -o jsonpath='{.data.github_app_private_key}' 2>/dev/null | base64 --decode | sha256sum | awk '{print $1}')
echo "SHA256 of local key file: ${LOCAL_KEY_SUM}"
echo "SHA256 of key from secret:  ${SECRET_KEY_SUM}"
if [[ "$LOCAL_KEY_SUM" == "$SECRET_KEY_SUM" ]]; then ok "Private key checksums match."; else fail "Private key checksums DO NOT MATCH. The key was likely corrupted during setup."; fi
output_footer "Decoded Secret Credentials"


# === LAYER 4: RUNNER POD ANALYSIS ===
check "Checking for Runner Pod(s)"
RUNNER_POD=$(${KUBECTL_CMD} get pods -n ${RUNNER_NAMESPACE} -l runner-deployment-name=${RUNNER_DEPLOYMENT_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$RUNNER_POD" ]]; then
    fail "No runner pod found for deployment '${RUNNER_DEPLOYMENT_NAME}' in namespace '${RUNNER_NAMESPACE}'. The controller may be failing to create it."
else
    ok "Found Runner Pod: ${RUNNER_POD}"
    run_and_capture "Describe Runner Pod" "${KUBECTL_CMD} describe pod -n ${RUNNER_NAMESPACE} ${RUNNER_POD}"
    run_and_capture "Logs for Runner Container" "${KUBECTL_CMD} logs -n ${RUNNER_NAMESPACE} ${RUNNER_POD} -c runner"
fi


# === LAYER 5: LIVE GITHUB API CHECK ===
check "Querying GitHub API for Live Runner Status"
if [[ -z "$CFG_GITHUB_TOKEN" ]]; then
    warn "CFG_GITHUB_TOKEN is not set in arc_env.conf. Skipping live GitHub API checks."
else
    API_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners"
    info "Querying GitHub API endpoint: ${API_URL}"
    
    # Use curl with -f to fail silently on HTTP errors, allowing us to check the exit code
    API_RESPONSE=$(curl -s -f -H "Authorization: token ${CFG_GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "${API_URL}")
    CURL_EXIT_CODE=$?

    output_header "Live GitHub API Runner List"
    if [[ $CURL_EXIT_CODE -eq 0 ]]; then
        ok "Successfully connected to GitHub API."
        RUNNER_COUNT=$(echo "${API_RESPONSE}" | jq '.total_count')
        echo "API reports ${RUNNER_COUNT} runner(s) for this repository."
        echo "--------------------------------------------------"
        # Pretty-print the relevant details for each runner found
        echo "${API_RESPONSE}" | jq '.runners[] | {id: .id, name: .name, os: .os, status: .status, busy: .busy, labels: [.labels[].name]}'
    else
        fail "Failed to query GitHub API. Exit code: ${CURL_EXIT_CODE}. The PAT may be invalid, lack 'repo' scope, or there could be a network issue."
        if [[ $CURL_EXIT_CODE -eq 22 ]]; then
            # A 404 or other HTTP error occurred. Let's try to get the body.
            error_body=$(curl -s -H "Authorization: token ${CFG_GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "${API_URL}")
            echo "Error body from API: ${error_body}"
        fi
    fi
    output_footer "Live GitHub API Runner List"
fi

echo
echo "================================================================="
info "Diagnostic script finished."
echo "================================================================="
