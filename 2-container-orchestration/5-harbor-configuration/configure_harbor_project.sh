#!/bin/bash

# ---
# Harbor Configuration Script
#
# This script configures a Harbor instance with best practices for a CI/CD workflow.
# It will:
# 1. Prompt for necessary credentials and names.
# 2. Create a new private project.
# 3. Enable vulnerability scanning and prevent pulling of vulnerable images.
# 4. Create a robot account with push/pull permissions for the CI/CD pipeline.
# 5. Set a retention policy to keep only the last 10 artifacts.
# 6. Set immutability rules for 'prod-*' and 'release-*' tags.
# 7. Schedule system-wide garbage collection for every Tuesday at 4:00 AM.
# ---

# --- Environment Variables ---
# Set these variables in your environment or modify them directly in the script.
# If any of these variables are not set (or are set to an empty string), 
# the script will fall back to prompting the user interactively for that specific 
# piece of information.
#export HARBOR_URL="https://myharbor.example.com"
#export HARBOR_ADMIN_USER="admin"
#export HARBOR_ADMIN_PASS="supersecretpassword"
#export PROJECT_NAME="production-app"
#export ROBOT_NAME="prod-builder-robot"
#export DELETE_OTHER_PROJECTS="no" # Set to "yes" to enable non-interactive deletion of other projects


# --- Color Codes ---
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Function to print messages ---
info() {
    echo -e "${COLOR_CYAN}[INFO] $1${NC}"
}

success() {
    echo -e "${COLOR_GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${COLOR_YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo -e "${COLOR_RED}[ERROR] $1${NC}" >&2
    exit 1
}

# --- Check for dependencies ---
check_deps() {
    info "Checking for dependencies (curl and jq)..."
    if ! command -v curl &> /dev/null; then
        fail "curl could not be found. Please install it to continue."
    fi
    if ! command -v jq &> /dev/null; then
        fail "jq could not be found. Please install it to continue."
    fi
    success "All dependencies are installed."
}

# --- Prompt user for input ---
prompt_user() {
    info "Please provide the following configuration details."
    info "Variables can be pre-set in the environment. Otherwise, you will be prompted."
    info "Press Enter to accept default values in [brackets] if prompted."

    # HARBOR_URL
    if [[ -z "$HARBOR_URL" ]]; then
        read -p "Enter Harbor URL (e.g., https://harbor.mydomain.com): " HARBOR_URL
    else
        info "Using pre-set HARBOR_URL: $HARBOR_URL"
    fi
    if [[ -z "$HARBOR_URL" ]]; then
        fail "Harbor URL cannot be empty."
    fi
    # Remove trailing slash if present first, as it might affect the regex
    HARBOR_URL=${HARBOR_URL%/}

    # Ensure HARBOR_URL starts with http:// or https://, default to https://
    if [[ ! "$HARBOR_URL" =~ ^https?:// ]]; then
        warn "HARBOR_URL '$HARBOR_URL' does not start with http:// or https://. Prepending https://."
        HARBOR_URL="https://$HARBOR_URL"
    fi

    # HARBOR_ADMIN_USER
    if [[ -z "$HARBOR_ADMIN_USER" ]]; then
        read -p "Enter Harbor Admin Username [admin]: " HARBOR_ADMIN_USER_INPUT
        HARBOR_ADMIN_USER=${HARBOR_ADMIN_USER_INPUT:-admin}
    else
        info "Using pre-set HARBOR_ADMIN_USER: $HARBOR_ADMIN_USER"
        HARBOR_ADMIN_USER=${HARBOR_ADMIN_USER:-admin} # Ensure default if pre-set was empty
    fi

    # HARBOR_ADMIN_PASS
    if [[ -z "$HARBOR_ADMIN_PASS" ]]; then
        read -sp "Enter Harbor Admin Password: " HARBOR_ADMIN_PASS
        echo # Newline after secret prompt
    else
        info "Using pre-set HARBOR_ADMIN_PASS (hidden)."
    fi
    if [[ -z "$HARBOR_ADMIN_PASS" ]]; then
        fail "Harbor Admin Password cannot be empty."
    fi

    # PROJECT_NAME
    if [[ -z "$PROJECT_NAME" ]]; then
        read -p "Enter New Project Name [my-app]: " PROJECT_NAME_INPUT
        PROJECT_NAME=${PROJECT_NAME_INPUT:-my-app}
    else
        info "Using pre-set PROJECT_NAME: $PROJECT_NAME"
        PROJECT_NAME=${PROJECT_NAME:-my-app} # Ensure default if pre-set was empty
    fi

    # ROBOT_NAME (default depends on PROJECT_NAME)
    local current_project_name_for_default="$PROJECT_NAME" # Use the finalized project name
    local default_robot_name_val="${current_project_name_for_default}-github-actions-builder"

    if [[ -z "$ROBOT_NAME" ]]; then
        read -p "Enter Robot Account Name [${default_robot_name_val}]: " ROBOT_NAME_INPUT
        ROBOT_NAME=${ROBOT_NAME_INPUT:-$default_robot_name_val}
    else
        info "Using pre-set ROBOT_NAME: $ROBOT_NAME"
        ROBOT_NAME=${ROBOT_NAME:-$default_robot_name_val} # Ensure default if pre-set was empty
    fi

    # DELETE_OTHER_PROJECTS
    if [[ -z "$DELETE_OTHER_PROJECTS" ]]; then
        # Use the finalized PROJECT_NAME in the prompt text
        read -p "Do you want to delete ALL OTHER existing projects (except '$PROJECT_NAME')? This is destructive. [no]: " DELETE_OTHER_PROJECTS_INPUT
        DELETE_OTHER_PROJECTS=${DELETE_OTHER_PROJECTS_INPUT:-no}
    else
        info "Using pre-set DELETE_OTHER_PROJECTS: $DELETE_OTHER_PROJECTS"
        DELETE_OTHER_PROJECTS=${DELETE_OTHER_PROJECTS:-no} # Ensure default if pre-set was empty
    fi
    # Normalize to lowercase
    DELETE_OTHER_PROJECTS=$(echo "$DELETE_OTHER_PROJECTS" | tr '[:upper:]' '[:lower:]')
}

# --- Function to delete other projects if requested ---
delete_other_projects_if_requested() {
    if [[ "$DELETE_OTHER_PROJECTS" != "yes" && "$DELETE_OTHER_PROJECTS" != "y" ]]; then
        info "Skipping deletion of other projects."
        return
    fi

    warn "Attempting to delete other projects as requested. This is a DESTRUCTIVE operation."
    info "The target project '$PROJECT_NAME' will NOT be deleted in this step. All other projects, including 'library' (if it exists and is not the target project), will be considered for deletion."

    # List all projects
    info "Fetching all projects to identify candidates for deletion (checking up to 100 projects)..."
    LIST_PROJECTS_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
        "${HARBOR_URL}/api/v2.0/projects?page_size=100") # Get up to 100 projects
    LIST_PROJECTS_HTTP_CODE=$(echo "$LIST_PROJECTS_FULL_RESPONSE" | tail -n1)
    LIST_PROJECTS_RESPONSE_BODY=$(echo "$LIST_PROJECTS_FULL_RESPONSE" | sed '$d')

    if [[ "$LIST_PROJECTS_HTTP_CODE" -ne 200 ]]; then
        fail "Failed to list projects for deletion. HTTP: $LIST_PROJECTS_HTTP_CODE. Body: $LIST_PROJECTS_RESPONSE_BODY"
    fi

    # Extract project IDs and names
    echo "$LIST_PROJECTS_RESPONSE_BODY" | jq -c '.[]' | while IFS= read -r project_json; do
        local project_id_to_delete=$(echo "$project_json" | jq -r '.project_id')
        local project_name_to_delete=$(echo "$project_json" | jq -r '.name')

        # if [[ "$project_name_to_delete" == "library" ]]; then
        #     info "Skipping deletion of 'library' project." # This line is now effectively removed
        #     continue
        # fi

        if [[ "$project_name_to_delete" == "$PROJECT_NAME" ]]; then
            info "Skipping deletion of the target project '$PROJECT_NAME' in this phase."
            continue
        fi

        info "Attempting to delete project '$project_name_to_delete' (ID: $project_id_to_delete)..."
        
        DELETE_PROJECT_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
            -X DELETE "${HARBOR_URL}/api/v2.0/projects/${project_id_to_delete}")
        
        DELETE_PROJECT_HTTP_CODE=$(echo "$DELETE_PROJECT_FULL_RESPONSE" | tail -n1)
        DELETE_PROJECT_RESPONSE_BODY=$(echo "$DELETE_PROJECT_FULL_RESPONSE" | sed '$d')

        if [[ "$DELETE_PROJECT_HTTP_CODE" -eq 200 ]]; then
            success "Project '$project_name_to_delete' (ID: $project_id_to_delete) deleted successfully."
        elif [[ "$DELETE_PROJECT_HTTP_CODE" -eq 404 ]]; then
            warn "Project '$project_name_to_delete' (ID: $project_id_to_delete) not found. Already deleted?"
        elif [[ "$DELETE_PROJECT_HTTP_CODE" -eq 412 ]]; then # Precondition Failed (e.g., project not empty)
            warn "Failed to delete project '$project_name_to_delete' (ID: $project_id_to_delete). Precondition failed (e.g., project may not be empty or has running tasks). HTTP: $DELETE_PROJECT_HTTP_CODE. Body: $DELETE_PROJECT_RESPONSE_BODY"
        else
            # For other errors, warn but continue to allow the main script logic to proceed if possible
            warn "Failed to delete project '$project_name_to_delete' (ID: $project_id_to_delete). HTTP: $DELETE_PROJECT_HTTP_CODE. Body: $DELETE_PROJECT_RESPONSE_BODY"
        fi
    done
    success "Finished attempting to delete other projects."
}

# --- Main Logic ---
main() {
    check_deps
    prompt_user

    # Delete other projects if requested by the user
    delete_other_projects_if_requested

    # 1. Check Harbor health and authentication
    info "Checking Harbor status at $HARBOR_URL..."
    HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" "${HARBOR_URL}/api/v2.0/systeminfo")
    if [[ "$HEALTH_STATUS" -ne 200 ]]; then
        fail "Could not connect to Harbor or authenticate. HTTP Status: $HEALTH_STATUS. Please check URL and credentials."
    fi
    success "Successfully authenticated with Harbor."

    # 2. Create Project
    info "Creating project '$PROJECT_NAME'..."
    PROJECT_PAYLOAD=$(cat <<EOF
{
  "project_name": "$PROJECT_NAME",
  "public": false,
  "metadata": {
    "auto_scan": "true",
    "prevent_vul": "true",
    "severity": "high"
  }
}
EOF
)
    # Capture full response to parse error message if needed
    CREATE_PROJECT_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
        -X POST -H "Content-Type: application/json" -d "$PROJECT_PAYLOAD" \
        "${HARBOR_URL}/api/v2.0/projects")
    
    CREATE_PROJECT_HTTP_CODE=$(echo "$CREATE_PROJECT_FULL_RESPONSE" | tail -n1)
    CREATE_PROJECT_RESPONSE_BODY=$(echo "$CREATE_PROJECT_FULL_RESPONSE" | sed '$d')

    PROJECT_ID=""
    PROJECT_METADATA_RETENTION_ID=""
    if [[ "$CREATE_PROJECT_HTTP_CODE" -eq 201 ]]; then
        success "Project '$PROJECT_NAME' created and configured for vulnerability scanning."
    elif [[ "$CREATE_PROJECT_HTTP_CODE" -eq 409 ]]; then
        warn "Project '$PROJECT_NAME' already exists. Skipping creation."
    else
        fail "Failed to create project. HTTP Status: $CREATE_PROJECT_HTTP_CODE. Response: $CREATE_PROJECT_RESPONSE_BODY"
    fi

    # Fetch Project ID and existing retention policy ID for the project
    info "Fetching project details for '$PROJECT_NAME' to get ID and check for existing retention policy..."
    PROJECT_NAME_ENCODED=$(printf %s "$PROJECT_NAME" | jq -sRr @uri)
    PROJECT_INFO_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
        "${HARBOR_URL}/api/v2.0/projects?name=${PROJECT_NAME_ENCODED}")
    
    PROJECT_INFO_HTTP_CODE=$(echo "$PROJECT_INFO_RESPONSE" | tail -n1)
    PROJECT_INFO_BODY=$(echo "$PROJECT_INFO_RESPONSE" | sed '$d')

    if [[ "$PROJECT_INFO_HTTP_CODE" -ne 200 ]]; then
        fail "Failed to fetch project info for '$PROJECT_NAME'. HTTP: $PROJECT_INFO_HTTP_CODE. Body: $PROJECT_INFO_BODY"
    fi

    # Assuming the project name is unique, take the first result.
    PROJECT_ID=$(echo "$PROJECT_INFO_BODY" | jq -r --arg projName "$PROJECT_NAME" '.[] | select(.name == $projName) | .project_id // empty')
    if [[ -z "$PROJECT_ID" ]]; then # Fallback if exact name match fails or multiple results and first is not it
      PROJECT_ID=$(echo "$PROJECT_INFO_BODY" | jq -r '.[0].project_id // empty')
    fi
    PROJECT_METADATA_RETENTION_ID=$(echo "$PROJECT_INFO_BODY" | jq -r --arg projName "$PROJECT_NAME" '.[] | select(.name == $projName) | .metadata.retention_id // empty')
     if [[ -z "$PROJECT_METADATA_RETENTION_ID" ]]; then
      PROJECT_METADATA_RETENTION_ID=$(echo "$PROJECT_INFO_BODY" | jq -r '.[0].metadata.retention_id // empty')
    fi

    if [[ -z "$PROJECT_ID" ]]; then
        fail "Could not retrieve Project ID for '$PROJECT_NAME'. Response: $PROJECT_INFO_BODY"
    fi
    success "Using Project ID: $PROJECT_ID for project '$PROJECT_NAME'."

    # 3. Create Robot Account
    info "Creating robot account '$ROBOT_NAME'..."
    ROBOT_PAYLOAD=$(cat <<EOF
{
  "name": "$ROBOT_NAME",
  "duration": -1,
  "level": "system",
  "disable": false,
  "permissions": [
    {
      "kind": "project",
      "namespace": "$PROJECT_NAME",
      "access": [
        { "resource": "repository", "action": "push" },
        { "resource": "repository", "action": "pull" }
      ]
    }
  ]
}
EOF
)
    # Capture full response and HTTP code
    CREATE_ROBOT_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
        -X POST -H "Content-Type: application/json" -d "$ROBOT_PAYLOAD" \
        "${HARBOR_URL}/api/v2.0/robots") # Changed endpoint

    CREATE_ROBOT_HTTP_CODE=$(echo "$CREATE_ROBOT_FULL_RESPONSE" | tail -n1)
    CREATE_ROBOT_RESPONSE_BODY=$(echo "$CREATE_ROBOT_FULL_RESPONSE" | sed '$d')

    if [[ "$CREATE_ROBOT_HTTP_CODE" -eq 201 ]]; then # 201 Created for new robot
        ROBOT_TOKEN=$(echo "$CREATE_ROBOT_RESPONSE_BODY" | jq -r '.secret')
        ROBOT_FULL_NAME=$(echo "$CREATE_ROBOT_RESPONSE_BODY" | jq -r '.name')
        success "Robot account created."
        echo -e "${COLOR_YELLOW}========================= IMPORTANT =========================${NC}"
        echo -e "Robot Account Name: ${COLOR_GREEN}${ROBOT_FULL_NAME}${NC}"
        echo -e "Robot Account Token: ${COLOR_GREEN}${ROBOT_TOKEN}${NC}"
        echo -e "${COLOR_YELLOW}This token is your robot account's password. Harbor will not show it again.${NC}"
        echo -e "${COLOR_YELLOW}Save it securely now. You will need it for your GitHub Actions secrets.${NC}"
        echo -e "${COLOR_YELLOW}=============================================================${NC}"
    elif [[ "$CREATE_ROBOT_HTTP_CODE" -eq 409 ]]; then # 409 Conflict if robot already exists
        # Attempt to parse existing robot name from error if possible, or use the requested name
        EXISTING_ROBOT_MSG=$(echo "$CREATE_ROBOT_RESPONSE_BODY" | jq -r '.errors[0].message // empty')
        if [[ "$EXISTING_ROBOT_MSG" == *"already exist"* || "$EXISTING_ROBOT_MSG" == *"conflict"* ]]; then
            warn "Robot account '$ROBOT_NAME' (or similar) already exists. Skipping creation. Response: $CREATE_ROBOT_RESPONSE_BODY"
        else
            # Generic 409, treat as unexpected
            fail "Failed to create robot account. HTTP Status: $CREATE_ROBOT_HTTP_CODE (Conflict). Response: $CREATE_ROBOT_RESPONSE_BODY"
        fi
    else
        fail "Failed to create robot account. HTTP Status: $CREATE_ROBOT_HTTP_CODE. Response: $CREATE_ROBOT_RESPONSE_BODY"
    fi

    # 4. Create Retention Policy if one doesn't exist
    if [[ -n "$PROJECT_METADATA_RETENTION_ID" && "$PROJECT_METADATA_RETENTION_ID" != "null" ]]; then
        warn "Project '$PROJECT_NAME' (ID: $PROJECT_ID) already has a retention policy (Policy ID from metadata: $PROJECT_METADATA_RETENTION_ID). Skipping creation."
    else
        info "Creating tag retention policy for project '$PROJECT_NAME' (ID: $PROJECT_ID) to keep the last 10 artifacts..."
    RETENTION_PAYLOAD=$(cat <<EOF
{
  "algorithm": "or",
  "rules": [
    {
      "disabled": false,
      "action": "retain",
      "template": "latestPushedK",
      "params": { "latestPushedK": 10 },
      "tag_selectors": [ { "kind": "doublestar", "decoration": "matches", "pattern": "**" } ],
      "scope_selectors": { "repository": [ { "kind": "doublestar", "decoration": "matches", "pattern": "**" } ] }
    }
  ],
  "trigger": { "kind": "Schedule", "settings": { "cron": "0 0 3 * * *" } },
  "scope": { "level": "project", "ref": $PROJECT_ID }
}
EOF
)
        CREATE_RETENTION_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
            -X POST -H "Content-Type: application/json" -d "$RETENTION_PAYLOAD" \
            "${HARBOR_URL}/api/v2.0/retentions")

        CREATE_RETENTION_HTTP_CODE=$(echo "$CREATE_RETENTION_FULL_RESPONSE" | tail -n1)
        CREATE_RETENTION_RESPONSE_BODY=$(echo "$CREATE_RETENTION_FULL_RESPONSE" | sed '$d')

        if [[ "$CREATE_RETENTION_HTTP_CODE" -eq 201 ]]; then
            success "Tag retention policy created for project '$PROJECT_NAME'."
        elif [[ "$CREATE_RETENTION_HTTP_CODE" -eq 409 ]]; then # Harbor might return 409 if a policy for this scope already exists
            warn "Failed to create tag retention policy for project '$PROJECT_NAME', it might already exist or there was a conflict. HTTP Status: $CREATE_RETENTION_HTTP_CODE. Response: $CREATE_RETENTION_RESPONSE_BODY"
        else
            fail "Failed to create tag retention policy for project '$PROJECT_NAME'. HTTP Status: $CREATE_RETENTION_HTTP_CODE. Response: $CREATE_RETENTION_RESPONSE_BODY"
        fi
    fi

    # 5. Create Immutability Rules
    info "Checking/Creating tag immutability rules for project ID '$PROJECT_ID'..."

    LIST_IMMUTABLE_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
        "${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}/immutabletagrules")
    LIST_IMMUTABLE_HTTP_CODE=$(echo "$LIST_IMMUTABLE_FULL_RESPONSE" | tail -n1)
    LIST_IMMUTABLE_RESPONSE_BODY=$(echo "$LIST_IMMUTABLE_FULL_RESPONSE" | sed '$d')

    EXISTING_RULES_JSON=""
    if [[ "$LIST_IMMUTABLE_HTTP_CODE" -eq 200 ]]; then
        EXISTING_RULES_JSON="$LIST_IMMUTABLE_RESPONSE_BODY"
    else
        # If listing fails, we cannot safely ensure idempotency.
        fail "Failed to list existing immutability rules for project ID '$PROJECT_ID'. HTTP: $LIST_IMMUTABLE_HTTP_CODE. Body: $LIST_IMMUTABLE_RESPONSE_BODY. Cannot ensure idempotency."
    fi

    for pattern_to_check in "prod-*" "release-*"; do
        info "Checking/Creating immutability rule for tag pattern '$pattern_to_check'..."

        EXPECTED_TAG_SELECTOR_JSON=$(jq -n --arg p "$pattern_to_check" '{kind: "doublestar", decoration: "matches", pattern: $p}')
        EXPECTED_REPO_SELECTOR_JSON=$(jq -n '{kind: "doublestar", decoration: "matches", pattern: "**"}')

        # Check if an identical, enabled rule already exists.
        # It checks for: not disabled, action IMMUTABLE, template immutable_template,
        # and specific tag_selectors and scope_selectors.repository.
        MATCHING_RULE_ID=$(echo "$EXISTING_RULES_JSON" | jq -r \
            --argjson ts "$EXPECTED_TAG_SELECTOR_JSON" \
            --argjson rs "$EXPECTED_REPO_SELECTOR_JSON" \
            --arg tpl "immutable_template" \
            --arg act "IMMUTABLE" '
            .[] | 
            select(
                .disabled == false and
                .action == $act and
                .template == $tpl and
                (.tag_selectors | length == 1 and .tag_selectors[0] == $ts) and
                (.scope_selectors.repository | length == 1 and .scope_selectors.repository[0] == $rs)
            ) | .id // empty' | head -n 1)

        if [[ -n "$MATCHING_RULE_ID" ]]; then
            warn "An existing enabled immutability rule (ID: $MATCHING_RULE_ID) found for tag pattern '$pattern_to_check'. Skipping creation."
        else
            info "No matching existing immutability rule found for tag pattern '$pattern_to_check'. Creating new rule..."
            IMMUTABLE_PAYLOAD=$(cat <<EOF
{
  "disabled": false,
  "action": "IMMUTABLE",
  "template": "immutable_template",
  "tag_selectors": [ { "kind": "doublestar", "decoration": "matches", "pattern": "$pattern_to_check" } ],
  "scope_selectors": { "repository": [ { "kind": "doublestar", "decoration": "matches", "pattern": "**" } ] }
}
EOF
)
            CREATE_IMMUTABLE_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
                -X POST -H "Content-Type: application/json" -d "$IMMUTABLE_PAYLOAD" \
                "${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}/immutabletagrules") # Use PROJECT_ID
            
            CREATE_IMMUTABLE_HTTP_CODE=$(echo "$CREATE_IMMUTABLE_FULL_RESPONSE" | tail -n1)
            CREATE_IMMUTABLE_RESPONSE_BODY=$(echo "$CREATE_IMMUTABLE_FULL_RESPONSE" | sed '$d')

            if [[ "$CREATE_IMMUTABLE_HTTP_CODE" -eq 201 ]]; then
                success "Immutability rule created for tags matching '$pattern_to_check'."
            elif [[ "$CREATE_IMMUTABLE_HTTP_CODE" -eq 409 ]]; then
                 warn "Conflict (409) when creating immutability rule for '$pattern_to_check'. It might have been created concurrently or a conflict exists. Response: $CREATE_IMMUTABLE_RESPONSE_BODY"
            else
                fail "Failed to create immutability rule for '$pattern_to_check'. HTTP: $CREATE_IMMUTABLE_HTTP_CODE. Body: $CREATE_IMMUTABLE_RESPONSE_BODY"
            fi
        fi
    done

    # 6. Schedule Garbage Collection
    info "Configuring system-wide garbage collection schedule (every Tuesday at 4:00 AM)..."
    GC_SCHEDULE_PAYLOAD='{ "schedule": { "type": "Weekly", "cron": "0 0 4 * * 2" } }'

    info "Attempting to update existing GC schedule (PUT)..."
    UPDATE_GC_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
        -X PUT -H "Content-Type: application/json" -d "$GC_SCHEDULE_PAYLOAD" \
        "${HARBOR_URL}/api/v2.0/system/gc/schedule")
    UPDATE_GC_HTTP_CODE=$(echo "$UPDATE_GC_FULL_RESPONSE" | tail -n1)
    UPDATE_GC_RESPONSE_BODY=$(echo "$UPDATE_GC_FULL_RESPONSE" | sed '$d')

    if [[ "$UPDATE_GC_HTTP_CODE" -eq 200 ]]; then
        success "Garbage collection schedule updated successfully."
    elif [[ "$UPDATE_GC_HTTP_CODE" -eq 404 ]]; then # Not Found, implies no schedule exists to update
        warn "No existing GC schedule found (404). Attempting to create new GC schedule (POST)..."
        CREATE_GC_FULL_RESPONSE=$(curl -s -w "\n%{http_code}" -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
            -X POST -H "Content-Type: application/json" -d "$GC_SCHEDULE_PAYLOAD" \
            "${HARBOR_URL}/api/v2.0/system/gc/schedule")
        CREATE_GC_HTTP_CODE=$(echo "$CREATE_GC_FULL_RESPONSE" | tail -n1)
        CREATE_GC_RESPONSE_BODY=$(echo "$CREATE_GC_FULL_RESPONSE" | sed '$d')

        if [[ "$CREATE_GC_HTTP_CODE" -eq 201 ]]; then
            success "Garbage collection schedule created successfully."
        else
            fail "Failed to create new garbage collection schedule. HTTP: $CREATE_GC_HTTP_CODE. Body: $CREATE_GC_RESPONSE_BODY"
        fi
    elif [[ "$UPDATE_GC_HTTP_CODE" -eq 409 ]]; then
         warn "Conflict (409) when updating GC schedule. Response: $UPDATE_GC_RESPONSE_BODY"
    else
        fail "Failed to update/create garbage collection schedule. PUT HTTP: $UPDATE_GC_HTTP_CODE. Body: $UPDATE_GC_RESPONSE_BODY"
    fi

    echo
    success "Harbor configuration is complete!"
}

# --- Run main function ---
main