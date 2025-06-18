# apply-clusterissuer.sh

This script automates the creation and application of a cert-manager `ClusterIssuer` resource in a MicroK8s Kubernetes cluster. The `ClusterIssuer` is configured to use AWS Route53 for DNS-01 challenges with Let's Encrypt, enabling automatic SSL/TLS certificate issuance for your services.

**Intent** This script is designed to be run AFTER setting up microk8s via the following script:
* ../1-microk8s-install/initialize-microk8s-cluster.sh


## Overview

The script performs the following actions:

1.  **Prerequisite Check**: Verifies the existence of a Kubernetes secret named `harbor-letsencrypt-route53-credentials` in the `cert-manager` namespace. This secret must contain your AWS Secret Access Key.
2.  **Configuration Substitution**: Uses `envsubst` to populate a `ClusterIssuer` template (`letsencrypt-route53-clusterissuer.template.yaml`) with user-defined AWS and Let's Encrypt configuration values.
3.  **Apply ClusterIssuer**: Applies the populated `ClusterIssuer` manifest to your MicroK8s cluster using `microk8s.kubectl apply`.

## Prerequisites

Before running this script, ensure you have the following:

1.  **MicroK8s Installed and Configured**:
    *   MicroK8s should be running.
    *   The `dns`, `storage`, `ingress`, and `helm3` addons should be enabled.
    *   This script is desinged to be the next step after running the `../1-microk8s-install/initialize-microk8s-cluster.sh` script to set up MicroK8s and its dependencies.
2.  **cert-manager Installed**:
    *   cert-manager must be installed in your MicroK8s cluster, typically in the `cert-manager` namespace. The `initialize-microk8s-cluster.sh` script handles this.
3.  **AWS Credentials and Information**:
    *   Your AWS Email Address (for Let's Encrypt registration).
    *   Your AWS Region (e.g., `us-east-1`).
    *   Your AWS Route53 Hosted Zone ID.
    *   Your AWS Access Key ID.
    *   Your AWS Secret Access Key.
4.  **AWS Credentials Secret**:
    *   A Kubernetes secret named `harbor-letsencrypt-route53-credentials` must exist in the `cert-manager` namespace. This secret stores your AWS Secret Access Key.
    *   If this secret does not exist, the script will provide instructions and an example command to create it:
        ```bash
        # 1. Set your AWS secret key as an environment variable:
        read -s -p "Enter AWS Secret Access Key: " AWS_SECRET_KEY && export AWS_SECRET_KEY
        # 1.a. ... or the basic way
        # export AWS_SECRET_KEY='your-super-secret-aws-key-goes-here'

        # 2. Run the microk8s.kubectl command:
        microk8s.kubectl -n cert-manager create secret generic harbor-letsencrypt-route53-credentials \
          --from-literal=harbor-letsencrypt-route53-secret-access-key="$AWS_SECRET_KEY"
        ```

## Configuration

You need to configure your specific values directly within the `apply-clusterissuer.sh` script:

1.  Open `apply-clusterissuer.sh` in a text editor.
2.  Locate the section `--- CONFIGURE YOUR VALUES HERE ---`.
3.  Update the following environment variables with your details:
    *   `YOUR_EMAIL`: Your email address for Let's Encrypt.
    *   `YOUR_AWS_REGION`: The AWS region where your Route53 hosted zone is.
    *   `YOUR_HOSTED_ZONE_ID`: Your AWS Route53 Hosted Zone ID.
    *   `YOUR_ACCESS_KEY_ID`: Your AWS Access Key ID.
    *   `ACME_SERVER`: Choose between Let's Encrypt staging or production ACME server URL. Staging is recommended for testing.
        *   Staging: `https://acme-staging-v02.api.letsencrypt.org/directory`
        *   Production: `https://acme-v02.api.letsencrypt.org/directory` (Comment out the staging line and uncomment the production line to use this).

## Usage

1.  **Ensure Prerequisites**: Verify all prerequisites listed above are met.
2.  **Configure the Script**: Edit `apply-clusterissuer.sh` with your specific values as described in the "Configuration" section.
3.  **Make Executable**: If necessary, make the script executable:
    ```bash
    chmod +x apply-clusterissuer.sh
    ```
4.  **Run the Script**:
    ```bash
    ./apply-clusterissuer.sh
    ```

The script will first check for the AWS credentials secret. If found, it will proceed to substitute your configured values into the `letsencrypt-route53-clusterissuer.template.yaml` and apply the resulting `ClusterIssuer` to your MicroK8s cluster.

You can verify the `ClusterIssuer` creation with:
```bash
microk8s.kubectl get clusterissuer letsencrypt-route53-clusterissuer -o yaml
```
And check its status with:
```bash
microk8s.kubectl describe clusterissuer letsencrypt-route53-clusterissuer
```
Look for a "Ready" status.