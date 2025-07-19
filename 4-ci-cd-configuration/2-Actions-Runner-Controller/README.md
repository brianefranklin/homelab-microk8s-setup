# Unified Actions Runner Controller (ARC) Setup

This directory contains a unified script, `setup_arc.sh`, designed to automate the complete installation and configuration of the Actions Runner Controller (ARC) on a Kubernetes cluster. It streamlines the entire process from creating secrets to deploying runners, providing an interactive experience that can also be run non-interactively for automation.

## Overview

The `setup_arc.sh` script is a one-stop solution for getting self-hosted GitHub Actions runners up and running in your cluster. It handles the complexities of setting up namespaces, secrets, Helm charts, and runner deployments, allowing you to focus on your CI/CD workflows.

## Features

- **Unified Setup**: A single script to manage the entire lifecycle (installation, configuration, and cleanup).
- **Interactive & Non-Interactive Modes**: Guides you through setup with interactive prompts or runs silently using a configuration file.
- **Secret Management**:
  - Creates the controller secret using your GitHub App credentials.
  - Creates image pull secrets for both `ghcr.io` (for ARC components) and a private Harbor registry (for your application images).
  - Automatically patches the necessary service accounts to use these image pull secrets.
- **Helm-based Installation**: Installs ARC using the official Helm chart, ensuring a standard and upgradeable deployment.
- **Webhook Health Check**: Includes a robust, automated check to verify that the ARC webhook is healthy, and even attempts to fix common MicroK8s networking issues that can cause it to fail.
- **Runner Deployment**: Deploys a `RunnerDeployment` resource to provision your self-hosted runners.
- **GitHub Integration (Optional)**: Can use the `gh` CLI to automatically configure required secrets (e.g., `HARBOR_USERNAME`, `KUBE_CONFIG`) in your GitHub repository.
- **Full Cleanup**: A `--cleanup` flag to completely remove all resources created by the script, ensuring a clean state.

## Prerequisites

Before running the script, ensure you have the following:

### 1. Software Dependencies

The script requires the following command-line tools to be installed and available in your `PATH`:
- `kubectl` (or a command specified by `KUBECTL_CMD` in your config)
- `helm` (or a command specified by `HELM_CMD` in your config)
- `curl`
- `jq`
- `envsubst` (part of the `gettext` package on Debian/Ubuntu)
- `gh` (GitHub CLI) - *Optional, but required for automatic repository secret configuration.*

The script can attempt to install `gh` and `jq` via `apt` if they are missing.

### 2. GitHub App Credentials

You must first create a repository-level GitHub App. This provides the credentials ARC uses to authenticate with the GitHub API. Follow the guide here:

*   **Guide: Creating a GitHub App for ARC**

After following the guide, you will have the three required values:
1.  **App ID**
2.  **Installation ID**
3.  **Path to your private key (`.pem`) file**

### 3. Configuration File

The script relies on a central configuration file to load all necessary variables.

- **Default Location**: `../arc_env.conf`
- **Action Required**: You must copy `arc_env.conf.example` to `arc_env.conf` and populate it with your specific values before running the script.

## Configuration (`arc_env.conf`)

This file is the single source of truth for your ARC setup. Key variables to configure include:

- `ARC_NAMESPACE`: The Kubernetes namespace for the ARC controller (e.g., `actions-runner-system`).
- `RUNNER_NAMESPACE`: The Kubernetes namespace where your runner pods will be created (e.g., `default`).
- `GITHUB_REPOSITORY`: The target repository for the runners (e.g., `your-user/your-repo`).
- `CFG_GITHUB_APP_ID`: Your GitHub App ID.
- `CFG_GITHUB_APP_INSTALLATION_ID`: Your GitHub App Installation ID.
- `CFG_GITHUB_APP_PRIVATE_KEY_PATH`: The local filesystem path to your app's `.pem` file.
- `CFG_GITHUB_USER` / `CFG_GITHUB_TOKEN`: Your GitHub username and a Personal Access Token (PAT) with `read:packages` scope for pulling images from `ghcr.io`.
- `CFG_HARBOR_URL` / `CFG_HARBOR_USERNAME` / `CFG_HARBOR_PASSWORD`: Credentials for your Harbor registry. These are used to create secrets in both Kubernetes (for image pulls) and GitHub (for workflows).
- `KUBECTL_CMD` / `HELM_CMD`: Allows you to specify the exact commands, which is useful for environments like MicroK8s (e.g., `microk8s.kubectl`).

If any `CFG_` variables are left empty, the script will prompt you for the values interactively.

## Usage

Navigate to this directory (`4-ci-cd-configuration/2-Actions-Runner-Controller`) to run the script.

---

### Standard Setup (Interactive)

This will run the full setup process and prompt for any missing configuration values.

```bash
chmod +x setup_arc.sh
./setup_arc.sh
```

---

### Specifying a Custom Configuration File

You can point the script to a different configuration file.

```bash
./setup_arc.sh /path/to/my_other_arc_env.conf
```

---

### Full Cleanup

This command will tear down and remove all Kubernetes resources and Helm configurations created by the script.

```bash
./setup_arc.sh --cleanup
```

---

### Debug Mode

Enable `set -x` to see every command the script executes.

```bash
./setup_arc.sh --debug
```

## Script Workflow

The script executes the following major steps in order:

1.  **Argument Parsing & Configuration**: Processes flags (`--cleanup`, `--debug`) and loads the `arc_env.conf` file.
2.  **Dependency Check**: Verifies that all required command-line tools are installed.
3.  **Prerequisites & Secret Setup**:
    - Creates the `ARC_NAMESPACE` and `RUNNER_NAMESPACE`.
    - Creates the `controller-manager` secret with GitHub App credentials.
    - Creates the `ghcr-io-pull-secret` for ARC images.
    - Creates the `harbor-credentials` secret for application images.
    - Patches the `default` service accounts in both namespaces to automatically use the appropriate image pull secrets.
4.  **Install Actions Runner Controller**:
    - Adds the ARC Helm repository.
    - Installs the `actions-runner-controller` Helm chart.
    - Waits for the controller deployment to become available.
5.  **Webhook Health Check**:
    - Runs a dedicated function (`ensure_arc_webhook_is_healthy`) to test connectivity to the ARC admission webhook.
    - If the webhook is unresponsive (a common issue in MicroK8s), it offers an automated fix by restarting the CNI and DNS addons.
6.  **Deploy Runner**:
    - Waits for the webhook's TLS certificate to be issued by cert-manager.
    - Waits for the webhook service endpoint to become active.
    - Applies the `runner-deployment.template.yaml` to create the `RunnerDeployment` resource, which triggers ARC to create runner pods.
7.  **Configure GitHub Extras (Optional)**:
    - Prompts to configure secrets directly in your GitHub repository using the `gh` CLI.
    - Sets `HARBOR_*`, `DOCKERHUB_*`, and `KUBE_CONFIG` secrets for use in your GitHub Actions workflows.

## Verification

After the script completes, you can verify the installation with these commands:

```bash
# Check the status of the ARC controller pods
${KUBECTL_CMD} get pods -n ${ARC_NAMESPACE}

# Check the status of your newly created runner pods
${KUBECTL_CMD} get pods -n ${RUNNER_NAMESPACE}

# Check the status of the RunnerDeployment
${KUBECTL_CMD} get runnerdeployment -n ${RUNNER_NAMESPACE}

# Check the Helm release status
${HELM_CMD} status ${ARC_HELM_RELEASE_NAME} -n ${ARC_NAMESPACE}
```

## Troubleshooting

If you encounter issues where runners are online but jobs are not being picked up, or if the setup fails, a diagnostic script is available.

```bash
cd troubleshooting/
./arc_doctor.sh
```

This "doctor" script runs a series of checks across different layers (cluster health, cert-manager, ARC configuration, live GitHub API) to help pinpoint the problem.
