#!/bin/bash

# Note that this script is designed for microk8s.kubectl NOT native kubectl.

# --- CONFIGURE YOUR VALUES HERE ---
# Set your email address, AWS region, hosted zone ID, and access key ID.
export YOUR_EMAIL="exampleuser@domain.com"
export YOUR_AWS_REGION="us-east-1"
export YOUR_HOSTED_ZONE_ID="Z0123456789ABCDEF"
export YOUR_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"

# Choose ONE OF THE FOLLOWING ACME URLs:
export ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
#export ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"

# Define the secret name and namespace we need to check for.
SECRET_NAME="harbor-letsencrypt-route53-credentials"
NAMESPACE="cert-manager"

# ----------------------------------


# --- PREREQUISITE CHECK ---
echo "Checking for prerequisite secret '$SECRET_NAME' in namespace '$NAMESPACE'..."

# Use 'microk8s.kubectl get' and check its exit code.
# The >/dev/null 2>&1 part silences the command's output so we only see our own messages.
if ! microk8s.kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  # This block executes if the 'microk8s.kubectl get' command fails (secret not found).
  echo "---"
  echo "❌ ERROR: Prerequisite secret not found."
  echo "The ClusterIssuer requires a secret named '$SECRET_NAME' in the '$NAMESPACE' namespace."
  echo "Please create it first. Here is an example command:"
  echo
  echo "  # 1. Set your AWS secret key as an environment variable:"
  echo "  export AWS_SECRET_KEY='your-super-secret-aws-key-goes-here'"
  echo
  echo "  # 2. Run the microk8s.kubectl command:"
  echo "  microk8s.kubectl -n $NAMESPACE create secret generic $SECRET_NAME \\"
  echo "    --from-literal=harbor-letsencrypt-route53-secret-access-key=\"\$AWS_SECRET_KEY\""
  echo
  # Exit the script with an error code.
  exit 1
fi

echo "✅ Prerequisite secret found. Proceeding..."
echo "---"

# --- APPLY CLUSTERISSUER ---


echo "Applying ClusterIssuer with the following configuration:"
echo "Email: $YOUR_EMAIL"
echo "Region: $YOUR_AWS_REGION"
echo "Zone ID: $YOUR_HOSTED_ZONE_ID"
echo "Access Key ID: $YOUR_ACCESS_KEY_ID"
echo "ACME URL: $ACME_SERVER"
echo "---"

# envsubst substitutes the variables in the template and pipes the resulting
# valid YAML directly to microk8s.kubectl. The '-f -' tells microk8s.kubectl to read from stdin.
envsubst < letsencrypt-route53-clusterissuer.template.yaml | microk8s.kubectl apply -f -

echo "ClusterIssuer applied. Check above for errors."