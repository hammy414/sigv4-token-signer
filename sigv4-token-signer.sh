#!/bin/bash

# Step 1: Check and load credentials
CRED_FILE="$HOME/.api_creds/env.json"

if [ -f "$CRED_FILE" ]; then
    echo "Found $CRED_FILE"

    # Extract the active profile credentials from the JSON file
    ACTIVE_ID=$(jq -r '.active_id' $CRED_FILE)
    ACTIVE_CREDS=$(jq -c ".credential_details[] | select(.id | contains(\"$ACTIVE_ID\"))" $CRED_FILE)

    ACCESS_KEY=$(echo $ACTIVE_CREDS | jq -r .access_key_id)
    SECRET_KEY=$(echo $ACTIVE_CREDS | jq -r .secret_access_key)
    SESSION_TOKEN=$(echo $ACTIVE_CREDS | jq -r .session_token)
    PROFILE_NAME=$(echo $ACTIVE_CREDS | jq -r .name)

    # Set credentials to the current shell session
    export API_ACCESS_KEY=$ACCESS_KEY
    export API_SECRET_KEY=$SECRET_KEY
    export API_SESSION_TOKEN=$SESSION_TOKEN
    export API_DEFAULT_PROFILE=$PROFILE_NAME

    echo "Credentials loaded and environment configured."
else
    echo "No environment file found. Ensure $CRED_FILE exists and is set up properly."
    exit 2
fi

# Read config file into variables
config_file="$1"

if [ -f "$config_file" ]; then
    API_ENDPOINT=$(jq -r '.API_ENDPOINT' $config_file)
    RESOURCE_ID=$(jq -r '.RESOURCE_ID' $config_file)
    REGION=$(jq -r '.REGION' $config_file)
else
    echo "Configuration file not found at $config_file."
    exit 1
fi

# Step 2: Verify mandatory environment variables
for var in RESOURCE_ID REGION API_ENDPOINT; do
    if [[ -z "${!var}" ]]; then
        echo "Error: $var is not available."
        exit 1
    fi
done

echo "Proceeding with provided Resource ID: $RESOURCE_ID and Region: $REGION and profile $PROFILE_NAME"

SCRIPT_DIR=$(dirname "$0")

# Step 3: Perform the delete API calls
deletion_curl_command=$($SCRIPT_DIR/invoke_it.sh -method DELETE -url "$API_ENDPOINT/resources/$RESOURCE_ID" -profile "$PROFILE_NAME")
echo "Generated deletion curl command: $deletion_curl_command"

# Execute the deletion command and capture only the response headers and body
response=$(eval "$deletion_curl_command" | sed -n '/{/,/}/p')
echo "API Response: $response"

# Validate and parse JSON response
if jq -e . <<< "$response" >/dev/null; then
    execution_id=$(echo "$response" | jq -r '.executionId')
    if [[ -z "$execution_id" || "$execution_id" == "null" ]]; then
        echo "Failed to obtain execution ID from the delete request."
        exit 1
    else
        echo "Delete request submitted, execution ID: $execution_id"
    fi
else
    echo "Invalid JSON response. Exiting."
    exit 1
fi

# Step 4: Function to generate status check command
get_status_curl() {
    echo "DEBUG: $API_ENDPOINT"
    echo "DEBUG: $REGION"
    echo "DEBUG: $execution_id"
    echo "DEBUG: $PROFILE_NAME"

    status_curl_command=$($SCRIPT_DIR/invoke_it.sh -method GET -url "$API_ENDPOINT/executions/$execution_id" -profile "$PROFILE_NAME")
    echo "Generated status check curl command: $status_curl_command"
    echo "Command for status check: $status_curl_command"
    export status_curl_command
}

# Function to perform the status check
check_status(){
    echo "Executing status check..."
    status_response=$(eval "$status_curl_command" | sed -n '/{/,/}/p')
    echo "Status Response: $status_response"

    if jq -e . <<< "$status_response" >/dev/null; then
        status=$(echo "$status_response" | jq -r '.status')
        echo "Deletion Status: $status"
        return 0
    else
        echo "Invalid JSON response during status check."
        return 1  # Return failure in case of invalid JSON
    fi
}

# Initialize and get status check command
get_status_curl

# Step 5: Polling loop for status check
end_time=$((SECONDS + 120))
echo "Now running deletion status checker, will update status every 10 seconds"
while [[ $SECONDS -lt $end_time ]]; do
    if check_status && [[ "$status" == "SUCCEEDED" ]]; then
        echo "Deletion completed successfully."
        exit 0
    elif [[ "$status" == "FAILED" ]]; then
        echo "Deletion failed."
        exit 1
    fi
    sleep 10
done

echo "Timed out waiting for deletion to complete."
exit 1
