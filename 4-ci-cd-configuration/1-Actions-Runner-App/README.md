# Creating a GitHub App for Actions Runner Controller (ARC)

This guide outlines the manual steps required to create a **repository-level GitHub App**. This app is essential for the Actions Runner Controller (ARC) to securely authenticate with the GitHub API and manage self-hosted runners.

You will need to follow these steps to gather three crucial pieces of information that the main `setup_arc.sh` script will ask for:
1.  **App ID**
2.  **Installation ID**
3.  **Private Key** (as a downloaded `.pem` file)

> **Note on Deprecation:** The old `ui-create-arc-app.sh` script is now deprecated. Its functionality has been fully integrated into the main `../2-Actions-Runner-Controller/setup_arc.sh` script for a more streamlined and interactive experience.

## Step 1: Register a New GitHub App

1.  Navigate to your GitHub repository, then go to **Settings** > **Developer settings** > **GitHub Apps**.
2.  Click **New GitHub App**.
3.  Fill out the registration form with the following details:
    *   **GitHub App name**: Give it a descriptive name, e.g., `my-repo-arc-runners`.
    *   **Homepage URL**: You can use the URL of your GitHub repository.
    *   **Webhook**: **Uncheck** the "Active" checkbox. The current setup uses the Installation ID and does not require a webhook.

## Step 2: Configure Permissions

Scroll down to the "Repository permissions" section. This is the most critical part. Grant the following permissions:

*   **Actions**: `Read and write`
    *   *Reason: Allows ARC to manage runners and check workflow run status.*
*   **Administration**: `Read and write`
    *   *Reason: Allows ARC to register and unregister self-hosted runners against the repository.*
*   **Checks**: `Read and write`
    *   *Reason: Allows runners to report check run status back to GitHub.*
*   **Metadata**: `Read-only` (This is a default requirement)
    *   *Reason: Required by the GitHub API for basic app information.*

Leave all other permissions as "No access".

## Step 3: Create and Install the App

1.  Under "Where can this GitHub App be installed?", select **Only on this account**.
2.  Click **Create GitHub App**.

You will be redirected to the app's settings page. Now you need to gather the required credentials.

## Step 4: Gather Credentials

On the app's settings page:

1.  **Note the App ID**: It is displayed at the top of the "General" settings page.

2.  **Generate a Private Key**:
    *   Scroll down to the "Private keys" section.
    *   Click **Generate a private key**.
    *   A `.pem` file will be automatically downloaded by your browser. **Save this file in a secure location.** You will only be able to download it once.

3.  **Install the App**:
    *   In the left sidebar, click on **Install App**.
    *   Click **Install** next to your account name.
    *   On the next screen, select **Only select repositories** and choose the repository where you want to run self-hosted runners.
    *   Click **Install**.

4.  **Note the Installation ID**:
    *   After installing, you will be redirected to a URL like:
      `https://github.com/settings/installations/12345678`
    *   The number at the end of the URL is your **Installation ID**.

## Next Steps

You should now have:
*   The **App ID** (e.g., `123456`).
*   The **Installation ID** (e.g., `12345678`).
*   The path to your downloaded **private key file** (e.g., `/home/user/downloads/my-repo-arc-runners.2023-10-27.private-key.pem`).

With these three pieces of information, you are ready to run the main setup script. Navigate to the `2-Actions-Runner-Controller` directory and execute:

```bash
./setup_arc.sh
```

The script will prompt you for these values to automatically create the required Kubernetes secret for ARC.