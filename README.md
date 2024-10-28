
# SIGV4 Token Signer

**SIGV4 Token Signer** is an automation script for self-signing AWS SIGV4 tokens, designed for event-driven architectures. Built by me, this project streamlines the process of generating and managing signed requests for AWS APIs, ensuring secure API interactions. It includes a Bash script for invoking signed API requests (`invoke_it.sh`), which handles the canonical request creation, signing, and execution of the HTTP request using AWS credentials.

## Features

- Automates the AWS SIGV4 signing process for API requests.
- Supports loading credentials from a JSON file for seamless integration.
- Generates and verifies signatures, providing a fully automated solution.
- Executes DELETE API requests (customizable for other methods) with signed authentication.
- Includes a status-checking loop to monitor the completion of API operations.

## Prerequisites

- **jq**: A lightweight and flexible command-line JSON processor.
- **OpenSSL**: Used for HMAC-SHA256 signing of requests.
- **AWS CLI** (optional): If you want to use AWS CLI to configure and verify credentials.

## Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/yourusername/sigv4-token-signer.git
   cd sigv4-token-signer
   ```

2. **Install required tools**:

   - For jq: 
     ```bash
     sudo apt-get install jq  # Debian/Ubuntu
     brew install jq           # macOS
     ```
   - For OpenSSL:
     ```bash
     brew install openssl      # macOS
     sudo apt-get install openssl  # Debian/Ubuntu
     ```

## Usage

### Main Script: `sigv4-token-signer.sh`

This script handles the credential loading, environment setup, and execution of AWS API calls with SIGV4 self-signed authentication.

1. **Prepare a JSON file with AWS credentials**:
   - The script expects the credentials to be stored in a file (`~/.api_creds/env.json`) in the following format:
   
     ```json
     {
       "active_id": "profile1",
       "credential_details": [
         {
           "id": "profile1",
           "name": "default",
           "aws_access_key_id": "your-access-key",
           "aws_secret_access_key": "your-secret-key",
           "aws_session_token": "your-session-token"
         }
       ]
     }
     ```

2. **Prepare a configuration file**:
   - Create a config file with your API details (e.g., `config.json`):
   
     ```json
     {
       "API_ENDPOINT": "your-api-endpoint",
       "RESOURCE_ID": "resource-id-to-delete",
       "REGION": "us-east-1"
     }
     ```

3. **Run the script**:

   ```bash
   ./sigv4-token-signer.sh config.json
   ```

   The script will:
   - Load the credentials from the JSON file.
   - Parse the configuration file for API details.
   - Generate a DELETE request and send it to the specified API endpoint.
   - Check the status of the API operation until it completes.

### Helper Script: `invoke_it.sh`

This script handles the signing and execution of the AWS SIGV4 request. It is automatically called by the main script to create the canonical request, generate the signature, and execute the HTTP request.

1. **Invoke API Request**:
   - This function constructs the HTTP request based on the specified HTTP method and API endpoint.
   - It generates the canonical request, hashes it, and signs it using AWS SIGV4 signing methods.
   - Outputs a cURL command that can be used to execute the signed request.

2. **Usage within the main script**:
   - The `invoke_it.sh` is called internally by `sigv4-token-signer.sh` to handle the signing and execution of the HTTP requests.
   - If needed, you can use this script separately for custom request execution.

## Example

To delete a resource using the API:

1. Ensure your `env.json` contains the correct credentials.
2. Use the `config.json` file to specify the API details.
3. Run the `sigv4-token-signer.sh`:

   ```bash
   ./sigv4-token-signer.sh config.json
   ```

4. Monitor the output to track the status of the delete request.

## Check Out My Medium Post

For a more detailed explanation of how and why I built this project, check out my Medium post [here](https://medium.com/@josh.sternfeld/sigv4-token-signer).

## License

This project is open-source and available under the [Apache License 2.0](LICENSE).

## Contributions

Feel free to contribute to this project by opening an issue or submitting a pull request.

## Contact

For any questions or support, please reach out via GitHub or open an issue.
