#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Base URL for GitHub Copilot API
API_BASE="https://api.githubcopilot.com"
# Directory to store test outputs
OUTPUT_DIR="./direct_copilot_tests"
# Timestamp for unique file naming
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Color codes for log output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions for colored output
log()    { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Function to retrieve GitHub Copilot token from Docker volume ONLY
get_copilot_token() {
    # Docker volume mount path
    local volume_path="/var/lib/docker/volumes/litellm_github_copilot_auth/_data"

    # Try JSON token file FIRST (api-key.json style) - this is the preferred format
    local json_token_file="$volume_path/api-key.json"
    if [[ -f "$json_token_file" ]]; then
        # Check if jq is available
        if command -v jq &> /dev/null; then
            # Try top-level .token field
            local token=$(jq -r '.token' "$json_token_file" 2>/dev/null)
            if [[ -n "$token" && "$token" != "null" ]]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # Try access-token file as fallback (simple token format)
    local access_token_file="$volume_path/access-token"
    if [[ -f "$access_token_file" ]]; then
        local token=$(cat "$access_token_file" 2>/dev/null | tr -d '\n\r')
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi

    # If we can't access the volume directly, try using Docker to read it
    if command -v docker &> /dev/null; then
        # Try JSON token through Docker FIRST
        local token=$(docker run --rm -v litellm_github_copilot_auth:/volume alpine sh -c 'cat /volume/api-key.json 2>/dev/null' | jq -r '.token' 2>/dev/null)
        if [[ -n "$token" && "$token" != "null" ]]; then
            echo "$token"
            return 0
        fi

        # Extract token from JSON manually if jq not available in container
        token=$(docker run --rm -v litellm_github_copilot_auth:/volume alpine cat /volume/api-key.json 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi

        # Try access-token through Docker as fallback
        token=$(docker run --rm -v litellm_github_copilot_auth:/volume alpine cat /volume/access-token 2>/dev/null | tr -d '\n\r')
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi

    error "No valid Copilot token found in Docker volume litellm_github_copilot_auth"
    error "Please ensure the volume exists and contains either:"
    error "  - api-key.json file with token field (preferred)"
    error "  - access-token file with the token (fallback)"
    exit 1
}



# Print the Copilot token before running tests (for debugging)
COPILOT_TOKEN=$(get_copilot_token)
echo "[TOKEN] $COPILOT_TOKEN"

# Tool definitions for the API payloads

# Math calculation tool definition
MATH_TOOL='{
  "type": "function",
  "function": {
    "name": "calculate",
    "description": "Perform mathematical calculation",
    "parameters": {
      "type": "object",
      "properties": {
        "expression": {
          "type": "string",
          "description": "Mathematical expression (e.g., 42 * 15)"
        }
      },
      "required": ["expression"]
    }
  }
}'

# File writing tool definition
FILE_TOOL='{
  "type": "function",
  "function": {
    "name": "write_file",
    "description": "Write content to a file",
    "parameters": {
      "type": "object",
      "properties": {
        "filename": {
          "type": "string",
          "description": "Name of the file to write to"
        },
        "content": {
          "type": "string",
          "description": "Content to write to the file"
        }
      },
      "required": ["filename", "content"]
    }
  }
}'

# List of models to test
MODELS=("gpt-4.1" "claude-3.5-sonnet")

# Function to test a single tool (math or file) with the specified model
test_single_tool() {
    local model="$1"
    local tool_type="$2"
    local test_name="$3"
    log "Testing $model with $tool_type tool"
    local safe_model=$(echo "$model" | tr '/' '_')
    local payload
    # Prepare payload based on tool type
    if [[ "$tool_type" == "math" ]]; then
        payload='{"model": "'"$model"'","messages":[{"role":"user","content":"What is 42 * 15?"}],"tools":['"$MATH_TOOL"'],"tool_choice":{"type":"function","function":{"name":"calculate"}},"max_tokens":50,"stream":true}'
    elif [[ "$tool_type" == "file" ]]; then
        payload='{"model": "'"$model"'","messages":[{"role":"user","content":"Write hello world to hello.txt"}],"tools":['"$FILE_TOOL"'],"tool_choice":{"type":"function","function":{"name":"write_file"}},"max_tokens":50,"stream":true}'
    else
        error "Unknown tool type: $tool_type"
        return 1
    fi
    local response_file="$OUTPUT_DIR/${safe_model}_${test_name}_response_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_${test_name}_analysis_$TIMESTAMP.txt"
    # Send request to Copilot API
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $COPILOT_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$response_file"
    echo "HTTP code: $http_code" > "$analysis_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model $tool_type test succeeded"
        echo "Result: Success" >> "$analysis_file"
    else
        error "$model $tool_type test failed (HTTP $http_code)"
        echo "ERROR: $response_body" >> "$analysis_file"
        # Handle authentication errors
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication issue detected. Check your GitHub Copilot subscription and token."
            return 1
        fi
    fi
    log "Analysis: $analysis_file"
}

# Function to test a tool flow: math calculation followed by file writing
test_tool_flow() {
    local model="$1"
    log "Testing tool flow with $model: math -> file"
    local safe_model=$(echo "$model" | tr '/' '_')
    # Prepare payload for tool flow (math then file)
    local payload='{"model": "'"$model"'","messages":[{"role":"user","content":"What is 42 * 15?"},{"role":"assistant","content":"The answer is 630."},{"role":"user","content":"Write hello world to hello.txt"}],"tools":['"$MATH_TOOL"','"$FILE_TOOL"'],"max_tokens":50,"stream":true}'
    local flow_file="$OUTPUT_DIR/${safe_model}_tool_flow_$TIMESTAMP.json"
    # Send request to Copilot API
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $COPILOT_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$flow_file"
    echo "HTTP code: $http_code" >> "$flow_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model flow test completed"
    else
        echo "ERROR: $response_body" >> "$flow_file"
        error "$model flow test failed (HTTP $http_code)"
        # Handle authentication errors
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication issue detected. Check your GitHub Copilot subscription and token."
            return 1
        fi
    fi
    log "Flow analysis: $flow_file"
}

# File to log curl commands for successful requests
CURL_LOG_FILE="$OUTPUT_DIR/curl_commands_$TIMESTAMP.log"

# Function to log curl command to file
log_curl_command() {
    local curl_cmd="$1"
    echo "$curl_cmd" >> "$CURL_LOG_FILE"
}

# Function to test a single tool (math or file) with the specified model
test_single_tool() {
    local model="$1"
    local tool_type="$2"
    local test_name="$3"
    log "Testing $model with $tool_type tool"
    local safe_model=$(echo "$model" | tr '/' '_')
    local payload
    # Prepare payload based on tool type
    if [[ "$tool_type" == "math" ]]; then
        payload='{"model": "'"$model"'","messages":[{"role":"user","content":"What is 42 * 15?"}],"tools":['"$MATH_TOOL"'],"tool_choice":{"type":"function","function":{"name":"calculate"}},"max_tokens":50,"stream":true}'
    elif [[ "$tool_type" == "file" ]]; then
        payload='{"model": "'"$model"'","messages":[{"role":"user","content":"Write hello world to hello.txt"}],"tools":['"$FILE_TOOL"'],"tool_choice":{"type":"function","function":{"name":"write_file"}},"max_tokens":50,"stream":true}'
    else
        error "Unknown tool type: $tool_type"
        return 1
    fi
    local response_file="$OUTPUT_DIR/${safe_model}_${test_name}_response_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_${test_name}_analysis_$TIMESTAMP.txt"
    # Compose the curl command as a string for logging
    local curl_cmd="curl -H \"Authorization: Bearer \$COPILOT_TOKEN\" -H \"Content-Type: application/json\" -H \"Editor-Version: vscode/1.85.1\" -H \"Editor-Plugin-Version: copilot/1.155.0\" -H \"User-Agent: GithubCopilot/1.155.0\" -H \"Copilot-Integration-Id: vscode-chat\" -d '$payload' \"$API_BASE/chat/completions\""
    # Send request to Copilot API
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $COPILOT_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$response_file"
    echo "HTTP code: $http_code" > "$analysis_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model $tool_type test succeeded"
        echo "Result: Success" >> "$analysis_file"
        # Log the curl command for successful requests
        log_curl_command "$curl_cmd"
    else
        error "$model $tool_type test failed (HTTP $http_code)"
        echo "ERROR: $response_body" >> "$analysis_file"
        # Handle authentication errors
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication issue detected. Check your GitHub Copilot subscription and token."
            return 1
        fi
    fi
    log "Analysis: $analysis_file"
}

# Function to test a tool flow: math calculation followed by file writing
test_tool_flow() {
    local model="$1"
    log "Testing tool flow with $model: math -> file"
    local safe_model=$(echo "$model" | tr '/' '_')
    # Prepare payload for tool flow (math then file)
    local payload='{"model": "'"$model"'","messages":[{"role":"user","content":"What is 42 * 15?"},{"role":"assistant","content":"The answer is 630."},{"role":"user","content":"Write hello world to hello.txt"}],"tools":['"$MATH_TOOL"','"$FILE_TOOL"'],"max_tokens":50,"stream":true}'
    local flow_file="$OUTPUT_DIR/${safe_model}_tool_flow_$TIMESTAMP.json"
    # Compose the curl command as a string for logging
    local curl_cmd="curl -H \"Authorization: Bearer \$COPILOT_TOKEN\" -H \"Content-Type: application/json\" -H \"Editor-Version: vscode/1.85.1\" -H \"Editor-Plugin-Version: copilot/1.155.0\" -H \"User-Agent: GithubCopilot/1.155.0\" -H \"Copilot-Integration-Id: vscode-chat\" -d '$payload' \"$API_BASE/chat/completions\""
    # Send request to Copilot API
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $COPILOT_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$flow_file"
    echo "HTTP code: $http_code" >> "$flow_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model flow test completed"
        # Log the curl command for successful requests
        log_curl_command "$curl_cmd"
    else
        echo "ERROR: $response_body" >> "$flow_file"
        error "$model flow test failed (HTTP $http_code)"
        # Handle authentication errors
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication issue detected. Check your GitHub Copilot subscription and token."
            return 1
        fi
    fi
    log "Flow analysis: $flow_file"
}

# Main function to orchestrate all tests and generate summary
main() {
    log "Testing direct GitHub Copilot API with tool flow"
    log "Reading token from Docker volume: litellm_github_copilot_auth"
    log "Output directory: $OUTPUT_DIR"
    for model in "${MODELS[@]}"; do
        log "=========================================="
        log "Testing model: $model"
        log "=========================================="
        # Run math tool test
        if test_single_tool "$model" "math" "math"; then
            sleep 2
            # Run file tool test
            if test_single_tool "$model" "file" "file"; then
                sleep 2
                # Run tool flow test (math -> file)
                test_tool_flow "$model"
                sleep 3
            else
                error "Skipping remaining tests for $model due to file tool test failure"
                continue
            fi
        else
            error "Skipping remaining tests for $model due to math tool test failure"
            continue
        fi
        log "Completed $model"
        log ""
    done
    # Generate summary markdown file with results and file list
    local summary_file="$OUTPUT_DIR/summary_$TIMESTAMP.md"
    {
        echo "# Direct GitHub Copilot Tool Flow Test Results"
        echo ""
        echo "## Test Configuration"
        echo "- API Base: $API_BASE"
        echo "- Timestamp: $TIMESTAMP"
        echo "- Tools: Math calculation + File writing"
        echo "- Token Source: Docker volume litellm_github_copilot_auth"
        echo ""
        echo "## Models Tested"
        for model in "${MODELS[@]}"; do
            echo "- $model"
        done
        echo ""
        echo "## Files Generated"
        ls "$OUTPUT_DIR"/*_$TIMESTAMP.* | sort | while read file; do
            echo "- $(basename "$file")"
        done
        echo ""
        echo "## Curl Commands Log"
        echo "- $(basename "$CURL_LOG_FILE")"
    } > "$summary_file"
    log "Summary written to $summary_file"
}

# Start the script
main
