# Harbor Configuration Script (`configure_harbor_project.sh`)

This script automates the post-deployment configuration of a Harbor instance with best practices tailored for a CI/CD workflow. It sets up a new project, configures security features, creates a robot account for automation, and establishes retention and immutability policies.

## Features

*   **Project Creation**: Creates a new private project in Harbor.
*   **Automated Credential Handling**:
    *   Sources configuration from a central `harbor_env.sh` file.
    *   If the admin password (`HARBOR_ADMIN_PASS`) is not set in the environment file, the script will automatically attempt to retrieve it from the Kubernetes secret created by the `deploy-harbor.sh` script.
    *   Falls back to interactive prompts if credentials cannot be found automatically.
*   **Vulnerability Scanning**:
    *   Enables automatic vulnerability scanning on push.
    *   Prevents pulling of images with vulnerabilities of 'high' severity or worse.
*   **Robot Account**:
    *   Creates a dedicated robot account with push and pull permissions scoped to the new project.
    *   Outputs the robot account name and token (secret) upon creation. **This token is shown only once.**
*   **Retention Policy**:
    *   Sets a tag retention policy to keep only the last 10 pushed artifacts for the project.
    *   Schedules this policy to run daily.
*   **Immutability Rules**:
    *   Creates tag immutability rules to prevent overwriting tags matching `prod-*` and `release-*`.
*   **System-wide Garbage Collection**:
    *   Schedules system-wide garbage collection to run every Tuesday at 4:00 AM.
*   **Idempotency**: The script attempts to be idempotent. If a resource (project, robot account, policy) already exists with the target configuration, it will skip creation and issue a warning.
*   **Optional Project Cleanup**: Provides a configurable option (`DELETE_OTHER_PROJECTS`) to delete all other existing projects. This is a destructive operation and is disabled by default.

## Prerequisites

*   **`curl`**: Used for making API requests to Harbor.
*   **`jq`**: Used for parsing JSON responses from the Harbor API.

The script will check for these dependencies and exit if they are not found.

## Configuration

The script is configured primarily through the central `../harbor_env.sh` file. It will use the values from this file first. If a required variable is empty, the script will fall back to prompting you for the information.

The following variables from `harbor_env.sh` are used:
*   `HARBOR_URL`: The full URL of your Harbor instance (e.g., `https://harbor.yourdomain.com`).
*   `HARBOR_ADMIN_USER`: The username for a Harbor admin account (default: `admin`).
*   `HARBOR_ADMIN_PASS`: The password for the Harbor admin account. **If left empty, the script will try to fetch it from the Kubernetes secret.**
*   `PROJECT_NAME`: The name for the new project to be created.
*   `ROBOT_NAME`: The name for the robot account. If left empty, a default name is generated based on the project name.
*   `DELETE_OTHER_PROJECTS`: Set to `yes` or `y` to enable deletion of all other projects. **Use with extreme caution.**
*   `HARBOR_INSTANCE_NAME`: Used to find the Kubernetes secret for the admin password.
*   `KUBECTL_CMD`: The command to use for `kubectl` (e.g., `microk8s.kubectl`).

### Overriding the Configuration File Path

You can specify a different environment file by passing its path as the first argument to the script.

```bash
./configure_harbor_project.sh /path/to/your/custom_env.sh
```

## Usage

1.  **Configure Environment**: Ensure `../harbor_env.sh` (or a custom file) is correctly populated. For a first run, you can leave `HARBOR_ADMIN_PASS` empty.
2.  **Make Executable**:
    ```bash
    chmod +x configure_harbor_project.sh
    ```
3.  **Run the Script**:
    ```bash
    ./configure_harbor_project.sh
    ```
    The script will wait for Harbor to be ready before proceeding.

    If credentials are not fully specified, you will be prompted to enter them.

### Script Output

*   The script provides informative messages about its progress, including successes, warnings, and errors.
*   **Crucially**, upon successful creation of the robot account, it will display the **Robot Account Name** and **Robot Account Token**.
    ```
    ========================= IMPORTANT =========================
    Robot Account Name: <robot_name>
    Robot Account Token: <robot_token_secret>
    This token is your robot account's password. Harbor will not show it again.
    Save it securely now. You will need it for your GitHub Actions secrets.
    =============================================================
    ```
    **Save this token immediately and securely, as Harbor will not display it again.**

## Important Considerations

*   **Admin Privileges**: The script requires Harbor administrator credentials to perform its operations.
*   **Robot Token Security**: The robot account token displayed by the script is sensitive. Store it securely (e.g., in a password manager or as a CI/CD secret).
*   **`DELETE_OTHER_PROJECTS`**: This option is highly destructive. It will delete **ALL** projects in your Harbor instance except for the `PROJECT_NAME` you are configuring, including the default `library` project.
*   **API Version**: The script uses Harbor API v2.0. Ensure your Harbor instance supports this version.
*   **Error Handling**: The script includes error handling for API calls and will exit if critical operations fail.

## Script Breakdown

1.  **Dependency Check**: Verifies `curl` and `jq` are installed.
2.  **User Prompts/Environment Variable Loading**: Gathers necessary configuration.
3.  **Optional: Delete Other Projects**: If `DELETE_OTHER_PROJECTS` is set to "yes", it attempts to delete all projects except the target `PROJECT_NAME`.
4.  **Harbor Health Check**: Waits for the Harbor API to become available and validates credentials before proceeding.
5.  **Create Project**:
    *   Creates a new private project.
    *   Configures project metadata for auto-scanning, preventing pulling vulnerable images (high severity), and sets the project ID.
6.  **Create Robot Account**:
    *   Creates a robot account with push/pull permissions for the newly created project.
    *   The robot account has an indefinite duration (`duration: -1`).
7.  **Create Retention Policy**:
    *   If no retention policy ID is found in the project's metadata, it creates a policy to retain the last 10 artifacts, applying to all repositories (`**`) and tags (`**`) within the project.
    *   The policy is triggered by a schedule (daily).
8.  **Create Immutability Rules**:
    *   Checks for existing enabled immutability rules for `prod-*` and `release-*` tag patterns.
    *   If not found, creates rules to make tags matching these patterns immutable across all repositories (`**`) in the project.
9.  **Schedule System Garbage Collection**:
    *   Attempts to update (PUT) the system-wide garbage collection schedule.
    *   If no schedule exists (404), it attempts to create (POST) a new schedule.
    *   Sets GC to run weekly: "0 0 4 * * 2" (every Tuesday at 4:00 AM UTC).

## Troubleshooting

*   Ensure `HARBOR_URL` is correct and accessible.
*   Verify `HARBOR_ADMIN_USER` and `HARBOR_ADMIN_PASS` are correct and have admin privileges.
*   Check Harbor logs for more detailed error messages if the script fails.
*   Ensure `curl` and `jq` are installed and in your `PATH`.

```