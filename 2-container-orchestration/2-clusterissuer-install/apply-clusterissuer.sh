#!/bin/bash

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

# --- Validate Required Variables ---
REQUIRED_VARS=(
    "LETSENCRYPT_EMAIL" "AWS_REGION" "AWS_HOSTED_ZONE_ID" "AWS_ACCESS_KEY_ID" "ACME_SERVER_URL"
    "KUBECTL_CMD" "CERT_MANAGER_NAMESPACE"
    "CERT_MANAGER_AWS_SECRET_NAME" "CERT_MANAGER_AWS_SECRET_KEY_NAME"
)
for VAR_NAME in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR_NAME}" ]; then
        echo "❌ ERROR: Required variable '$VAR_NAME' is not set in '$CONFIG_FILE'." >&2
        exit 1
    fi
done

# --- PREREQUISITE CHECK ---
echo "Checking for prerequisite secret '$CERT_MANAGER_AWS_SECRET_NAME' in namespace '$CERT_MANAGER_NAMESPACE'..."

if ! ${KUBECTL_CMD} get secret "$CERT_MANAGER_AWS_SECRET_NAME" -n "$CERT_MANAGER_NAMESPACE" > /dev/null 2>&1; then
  echo "---"
  echo "❌ ERROR: Prerequisite secret not found."
  echo "The ClusterIssuer requires a secret named '$CERT_MANAGER_AWS_SECRET_NAME' in the '$CERT_MANAGER_NAMESPACE' namespace."
  echo "Please create it first. Here is an example command:"
  echo
  echo "  # 1. Set your AWS secret key as an environment variable:"
  echo "  export AWS_SECRET_KEY='your-super-secret-aws-key-goes-here'"
  echo
  echo "  # 2. Run the kubectl command:"
  echo "  ${KUBECTL_CMD} -n ${CERT_MANAGER_NAMESPACE} create secret generic ${CERT_MANAGER_AWS_SECRET_NAME} \\"
  echo "    --from-literal=${CERT_MANAGER_AWS_SECRET_KEY_NAME}=\"\$AWS_SECRET_KEY\""
  echo
  exit 1
fi

echo "✅ Prerequisite secret found. Proceeding..."
echo "---"

# --- APPLY CLUSTERISSUER ---
# For compatibility with the existing letsencrypt-route53-clusterissuer.template.yaml,
# we export variables with the names the template expects.
export YOUR_EMAIL="${LETSENCRYPT_EMAIL}"
export YOUR_AWS_REGION="${AWS_REGION}"
export YOUR_HOSTED_ZONE_ID="${AWS_HOSTED_ZONE_ID}"
export YOUR_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export ACME_SERVER="${ACME_SERVER_URL}"

echo "Applying ClusterIssuer with the following configuration:"
echo "Email: $LETSENCRYPT_EMAIL"
echo "Region: $AWS_REGION"
echo "Zone ID: $AWS_HOSTED_ZONE_ID"
echo "Access Key ID: $AWS_ACCESS_KEY_ID"
echo "ACME URL: $ACME_SERVER_URL"
echo "---"

# envsubst substitutes the exported variables in the template and pipes the resulting
# valid YAML directly to kubectl. The '-f -' tells kubectl to read from stdin.
envsubst < letsencrypt-route53-clusterissuer.template.yaml | ${KUBECTL_CMD} apply -f -

echo "ClusterIssuer applied. Check above for errors."