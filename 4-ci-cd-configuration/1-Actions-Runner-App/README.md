# GitHub App Creation Script for Actions Runner Controller (ARC)

The `ui-create-arc-app.sh` script guides an administrator through the process of creating a **repository-level GitHub App** using the GitHub web interface. This app is specifically configured with the necessary permissions for the Actions Runner Controller (ARC) to manage self-hosted runners for a single GitHub repository.

After the app is created and installed via the UI, the script prompts the user for the App ID, Webhook Secret, and the path to the downloaded private key file. It then uses this information to generate the final `kubectl` command to create the required Kubernetes secret for ARC.

## Features

*   **Guided Setup**: Provides clear, step-by-step instructions for the manual browser-based part of the GitHub App creation and installation.
*   **Clear Instructions**: Details exactly what to enter in each field of the GitHub App registration form, including the correct permissions for ARC.
*   **Secure Credential Handling**: Prompts for credentials and the path to the private key file, using the `--from-file` flag for `kubectl` to ensure the key is handled correctly.
*   **Kubernetes Secret Generation**: Outputs the final `kubectl` command needed to create the Kubernetes secret (default name `controller-manager`, default namespace `actions-runner-system`) for ARC.

## Prerequisites

*   **`bash`**: The script is a bash shell script.
*   **`curl`**: Used to make API requests to GitHub.
*   **`jq`**: Used to parse JSON responses from GitHub and to URL-encode the manifest.
*   Access to a Kubernetes cluster and a configured `kubectl` (or equivalent, like `microk8s.kubectl`).

## Configuration

All configuration is handled in the `../arc_env.sh` file. Before running the script, you **must** ensure that `GITHUB_REPOSITORY` and other variables in `arc_env.sh` are set correctly.

## Usage

1.  **Configure the environment**: Edit `../arc_env.sh` and set the `GITHUB_REPOSITORY` and other variables as needed.
2.  **Make the script executable**:
    ```bash
    chmod +x ui-create-arc-app.sh
    ```
3.  **Run the script**:
    ```bash
    ./ui-create-arc-app.sh
    ```
4.  **Follow the on-screen instructions**:
    *   The script will provide a URL to open in your browser to begin creating a new GitHub App.
    *   It will then list all the values you need to enter into the GitHub UI form, including permissions and webhook settings.
    *   After creating the app, you will be instructed to:
        *   Generate and download a private key (`.pem` file).
        *   Note the App ID.
        *   Note the Webhook Secret.
        *   Install the app on your target repository.

5.  **Provide Credentials to the Script**:
    *   The script will prompt you to enter the App ID, Webhook Secret, and the full path to the `.pem` file you downloaded.

6.  **Create the Kubernetes Secret**:
    *   Copy the entire `kubectl` command provided by the script.
    *   Run this command in your terminal against the Kubernetes cluster where ARC is or will be installed. This creates the necessary secret for ARC to authenticate with GitHub.

    Example output:
    ```
    --------------------------------------------------------------------------------
    microk8s.kubectl create secret generic controller-manager \
      --namespace=actions-runner-system \
      --from-literal=github_app_id="1234567" \
      --from-literal=github_webhook_secret="a_very_secret_webhook_string" \
      --from-file=github_private_key="/path/to/your/downloaded-private-key.pem"
    --------------------------------------------------------------------------------
    ```

## Important Notes

*   **Private Key Security**: The private key you download is highly sensitive. The `kubectl` command uses it to create a secret. Ensure your Kubernetes secrets are managed securely and handle the `.pem` file with care.