#!/bin/bash
# Shared environment variables for Actions Runner Controller setup and deployment scripts.

# --- CONFIGURE ALL USER-DEFINED VALUES HERE ---

# == Shared by arc-setup.sh and apply-runner-deployment.sh ==
# Namespace where Actions Runner Controller is/will be installed.
export ARC_NAMESPACE="actions-runner-system"

# == Used by arc-setup.sh ==
# Helm repository name for ARC
export ARC_HELM_REPO_NAME="actions-runner-controller"
# Helm release name for ARC
export ARC_HELM_RELEASE_NAME="actions-runner-controller"
# Helm repository URL for ARC
export ARC_HELM_REPO_URL="https://actions-runner-controller.github.io/actions-runner-controller"
# Helm chart name for ARC (e.g., repo_name/chart_name) - typically derived, but base components are here
export ARC_HELM_CHART_NAME="${ARC_HELM_REPO_NAME}/actions-runner-controller"


# == Used by apply-runner-deployment.sh ==
# Secret name for the ARC controller manager, which holds the GitHub PAT.
export ARC_CONTROLLER_SECRET_NAME="controller-manager"

# GitHub repository (e.g., your-username/your-repo-name)
export GITHUB_REPOSITORY="your-username/your-repo-name"

# GitHub App ID for your Actions Runner Controller (ARC) app
# GitHub App credentials for the controller-manager secret
CFG_GITHUB_APP_ID=""
CFG_GITHUB_APP_INSTALLATION_ID=""
CFG_GITHUB_APP_PRIVATE_KEY_PATH=""

# GitHub credentials for the ghcr.io image pull secret
CFG_GITHUB_USER=""
CFG_GITHUB_TOKEN=""


# Name for your RunnerDeployment resource
# Default is derived from GITHUB_REPOSITORY (e.g., your-repo-name-runner-deployment)
# You can override this if needed: export RUNNER_DEPLOYMENT_NAME="custom-runner-deployment-name"
export RUNNER_DEPLOYMENT_NAME="${GITHUB_REPOSITORY##*/}-runner-deployment"

# Namespace where the RunnerDeployment will be created
export RUNNER_NAMESPACE="default"
# Number of runner replicas
export RUNNER_REPLICAS="1"

# Harbor project name (e.g., 'myproject') for GitHub Actions workflow
export HARBOR_PROJECT_NAME="your-harbor-project"
# Harbor image name (e.g., 'my-app-image') for GitHub Actions workflow
export HARBOR_IMAGE_NAME="your-harbor-image"
# Path to your Kubernetes deployment manifest within your repository (e.g., k8s/deployment.yaml) for GitHub Actions workflow
export K8S_DEPLOYMENT_MANIFEST_PATH="k8s/deployment.yaml"

# == CLI Commands (allows overriding for non-MicroK8s or specific paths) ==
# Command for kubectl
export KUBECTL_CMD="microk8s.kubectl"
# Command for helm
export HELM_CMD="microk8s.helm3"

# == Used by create-arc-app.sh ==
# Redirect URL used during GitHub App creation manifest and flow.
export APP_CREATION_REDIRECT_URL="http://localhost:8080/"

# == Used by 2-apply-runner-deployment.sh ==
# Path to the RunnerDeployment template file, relative to the script's location.
export RUNNER_DEPLOYMENT_TEMPLATE_FILE="runner-deployment.template.yaml"
# Path to the GitHub Actions workflow template file, relative to the script's location.
export WORKFLOW_TEMPLATE_FILE=".github/workflows/deploy.template.yaml"
# Base directory name for generating the workflow file, relative to the script's location.
export GENERATED_WORKFLOW_BASE_DIR="generated-workflow"
# --------------------------------------