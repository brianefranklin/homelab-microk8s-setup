#!/bin/bash
#
# Shared configuration for the MicroK8s, Cert-Manager, and ClusterIssuer scripts.
#

# --- General & User Configuration ---
# The user to add to the 'microk8s' group. Defaults to the user running the script.
export TARGET_USER=$(whoami)

# --- Kubernetes / MicroK8s Configuration ---
# The base commands for kubectl and helm.
# Use 'microk8s kubectl' and 'microk8s helm3' for MicroK8s.
# Use 'kubectl' and 'helm' for other distributions.
export KUBECTL_CMD="microk8s kubectl"
export HELM_CMD="microk8s helm3"

# An array of MicroK8s addons to enable.
export MICROK8S_ADDONS=("dns" "hostpath-storage" "ingress" "helm3")

# --- Cert-Manager & Let's Encrypt Configuration ---
# Namespace for cert-manager installation
export CERT_MANAGER_NAMESPACE="cert-manager"

# Helm repository details for cert-manager
export CERT_MANAGER_HELM_REPO_ALIAS="jetstack"
export CERT_MANAGER_HELM_REPO_URL="https://charts.jetstack.io"

# Helm chart and release name for cert-manager
export CERT_MANAGER_HELM_CHART="jetstack/cert-manager"
export CERT_MANAGER_HELM_RELEASE_NAME="cert-manager"

# Let's Encrypt ACME Server URL.
# Use the staging URL for testing to avoid hitting rate limits.
# Use the production URL for real certificates.
# Staging:
export ACME_SERVER_URL="https://acme-staging-v02.api.letsencrypt.org/directory"
# Production (uncomment to use):
# export ACME_SERVER_URL="https://acme-v02.api.letsencrypt.org/directory"

# --- AWS & Route53 Configuration for DNS-01 Challenge ---
# Email address for Let's Encrypt registration and notifications.
export LETSENCRYPT_EMAIL="exampleuser@domain.com"

# AWS Configuration for Route53 DNS-01 challenge.
export AWS_REGION="us-east-1"
export AWS_HOSTED_ZONE_ID="Z0123456789ABCDEF"
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
# The AWS Secret Access Key is not stored in this file. It should be created as a Kubernetes secret.

# The name of the Kubernetes secret that will hold the AWS credentials.
export CERT_MANAGER_AWS_SECRET_NAME="harbor-letsencrypt-route53-credentials"

# The key within the Kubernetes secret that holds the AWS secret access key.
export CERT_MANAGER_AWS_SECRET_KEY_NAME="harbor-letsencrypt-route53-secret-access-key"