#!/usr/bin/env bash

# Direct GitHub Copilot API Testing Script
# Tests tool flow: math calculation + file writing

set -e

# Configuration
API_BASE="https://api.githubcopilot.com"
OUTPUT_DIR="./direct_copilot_tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get GitHub Copilot token
get_copilot_token() {
    if command -v python3 &> /dev/null; then
        local result=$(python3 -c "
import sys
sys.path.insert(0, '.')
try:
    from litellm.llms.github_copilot.authenticator import Authenticator
    auth = Authenticator()
    token = auth.get_api_key()
    if token and len(token.strip()) > 0:
        print(token)
    else:
        print('ERROR: Empty token received', file=sys.stderr)
        exit(1)
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    exit(1)
" 2>&1)

        local exit_code=$?
        if [[ $exit_code -eq 0 && -n "$result" && ! "$result" =~ ^ERROR: ]]; then
            echo "$result"
            return 0
        else
            error "Authentication failed: $result"
            return 1
        fi
    else
        error "Python3 not found"
        return 1
    fi
}

# Test authentication before running tests
test_auth() {
    log "Testing GitHub Copilot authentication..."

    local token=$(get_copilot_token)
    if [[ $? -ne 0 ]]; then
        error "Authentication test failed. Cannot proceed with API tests."
        exit 1
    fi

    # Test with a simple API call to models endpoint first
    local auth_test_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        "$API_BASE/models" 2>/dev/null)

    local http_code=$(echo "$auth_test_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)

    if [[ "$http_code" == "200" ]]; then
        success "Authentication successful"
        return 0
    else
        local response_body=$(echo "$auth_test_response" | sed 's/HTTPSTATUS:[0-9]*$//')
        error "Authentication test failed (HTTP $http_code): $response_body"

        # Try a simple chat completion as backup test
        log "Trying chat completion test..."
        auth_test_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -H "Editor-Version: vscode/1.85.1" \
            -H "Editor-Plugin-Version: copilot/1.155.0" \
            -H "User-Agent: GithubCopilot/1.155.0" \
            -H "Copilot-Integration-Id: vscode-chat" \
            -d '{"model": "gpt-4.1", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 5}' \
            "$API_BASE/chat/completions" 2>/dev/null)

        http_code=$(echo "$auth_test_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)

        if [[ "$http_code" == "200" ]]; then
            success "Authentication successful (via chat completion test)"
            return 0
        else
            response_body=$(echo "$auth_test_response" | sed 's/HTTPSTATUS:[0-9]*$//')
            error "Both authentication tests failed (HTTP $http_code): $response_body"
            exit 1
        fi
    fi
}

# Tool definitions
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

# Test models (testing only claude-3.5-sonnet)
MODELS=(
    "gpt-4.1"
)

# Test single tool call
test_single_tool() {
    local model="$1"
    local tool_type="$2"
    local test_name="$3"

    log "Testing $model with $tool_type tool"

    local token=$(get_copilot_token)
    if [[ $? -ne 0 ]]; then
        error "Failed to get authentication token for $model $tool_type test"
        return 1
    fi
    local safe_model=$(echo "$model" | tr '/' '_')

    # Create request payload based on tool type
    local payload
    if [[ "$tool_type" == "math" ]]; then
        payload=$(cat << EOF
{
  "intent": true,
  "n": 1,
  "stream": true,
  "temperature": 0.1,
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a highly skilled software engineer with extensive knowledge in many programming languages, frameworks, design patterns, and best practices.\n\n## Communication\n\n1. Be conversational but professional.\n2. Refer to the user in the second person and you should use the provided tools to help them.\n\nUse the provided tools to complete the user's request."
    },
    {
      "role": "user",
      "content": "Calculate 42 * 15"
    }
  ],
  "tools": [$MATH_TOOL],
  "tool_choice": "auto"
}
EOF
)
    else
        payload=$(cat << EOF
{
  "intent": true,
  "n": 1,
  "stream": true,
  "temperature": 0.1,
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a highly skilled software engineer with extensive knowledge in many programming languages, frameworks, design patterns, and best practices.\n\n## Communication\n\n1. Be conversational but professional.\n2. Refer to the user in the second person and you should use the provided tools to help them.\n\nUse the provided tools to complete the user's request."
    },
    {
      "role": "user",
      "content": "Write 'Hello World' to a file called greeting.txt"
    }
  ],
  "tools": [$FILE_TOOL],
  "tool_choice": "auto"
}
EOF
)
    fi

    # Save request
    local request_file="$OUTPUT_DIR/${safe_model}_${test_name}_request_$TIMESTAMP.json"
    echo "$payload" | jq . > "$request_file"

    # Make API call
    local response_file="$OUTPUT_DIR/${safe_model}_${test_name}_response_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_${test_name}_analysis_$TIMESTAMP.txt"

    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $token" \
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

    # Analyze response
    {
        echo "=== ANALYSIS FOR $model - $tool_type TOOL ==="
        echo "HTTP Status: $http_code"
        echo "Request file: $request_file"
        echo "Response file: $response_file"
        echo ""

        if [[ "$http_code" == "200" ]]; then
            # Check if this is a streaming response
            if echo "$response_body" | grep -q "^data: "; then
                echo "Response type: Streaming (SSE)"

                # Extract tool calls from streaming response
                local tool_call_count=0
                local finish_reason=""
                local tool_function=""
                local tool_args=""

                # Parse streaming response
                while IFS= read -r line; do
                    if [[ "$line" =~ ^data:\ \{.*\}$ ]]; then
                        local json_data="${line#data: }"

                        # Check for tool calls
                        if echo "$json_data" | jq -e '.choices[0].delta.tool_calls[0].function.name' >/dev/null 2>&1; then
                            tool_function=$(echo "$json_data" | jq -r '.choices[0].delta.tool_calls[0].function.name' 2>/dev/null)
                            if [[ -n "$tool_function" && "$tool_function" != "null" ]]; then
                                tool_call_count=1
                                echo "Tool function detected: $tool_function"
                            fi
                        fi

                        # Collect tool arguments
                        if echo "$json_data" | jq -e '.choices[0].delta.tool_calls[0].function.arguments' >/dev/null 2>&1; then
                            local arg_chunk=$(echo "$json_data" | jq -r '.choices[0].delta.tool_calls[0].function.arguments' 2>/dev/null)
                            if [[ -n "$arg_chunk" && "$arg_chunk" != "null" ]]; then
                                tool_args+="$arg_chunk"
                            fi
                        fi

                        # Check for finish reason
                        if echo "$json_data" | jq -e '.choices[0].finish_reason' >/dev/null 2>&1; then
                            finish_reason=$(echo "$json_data" | jq -r '.choices[0].finish_reason' 2>/dev/null)
                        fi
                    fi
                done <<< "$response_body"

                echo "Tool calls detected: $tool_call_count"
                if [[ $tool_call_count -gt 0 ]]; then
                    echo "  Function: $tool_function"
                    echo "  Arguments: $tool_args"

                    # Try to parse the complete arguments as JSON
                    if [[ -n "$tool_args" ]]; then
                        local parsed_args=$(echo "$tool_args" | jq . 2>/dev/null || echo "INVALID_JSON")
                        echo "  Parsed Arguments: $parsed_args"
                    fi
                fi
                echo "Finish reason: $finish_reason"
            else
                # Regular JSON response
                echo "Response type: Regular JSON"
                local choices=$(echo "$response_body" | jq '.choices | length' 2>/dev/null || echo "0")
                echo "Choices count: $choices"

                for ((i=0; i<choices; i++)); do
                    echo "Choice $i:"
                    local role=$(echo "$response_body" | jq -r ".choices[$i].message.role" 2>/dev/null)
                    local content=$(echo "$response_body" | jq -r ".choices[$i].message.content" 2>/dev/null)
                    local tool_calls=$(echo "$response_body" | jq ".choices[$i].message.tool_calls // []" 2>/dev/null)
                    local tool_count=$(echo "$tool_calls" | jq 'length' 2>/dev/null || echo "0")
                    local finish_reason=$(echo "$response_body" | jq -r ".choices[$i].finish_reason" 2>/dev/null)

                    echo "  Role: $role"
                    echo "  Content: ${content:0:100}..."
                    echo "  Tool calls: $tool_count"
                    echo "  Finish reason: $finish_reason"

                    if [[ "$tool_count" -gt 0 ]]; then
                        for ((j=0; j<tool_count; j++)); do
                            local call_id=$(echo "$tool_calls" | jq -r ".[$j].id" 2>/dev/null)
                            local call_type=$(echo "$tool_calls" | jq -r ".[$j].type" 2>/dev/null)
                            local func_name=$(echo "$tool_calls" | jq -r ".[$j].function.name" 2>/dev/null)
                            local func_args=$(echo "$tool_calls" | jq -r ".[$j].function.arguments" 2>/dev/null)
                            local args_type=$(echo "$func_args" | jq -r 'type' 2>/dev/null || echo 'string')

                            echo "    Tool Call $j:"
                            echo "      ID: $call_id"
                            echo "      Type: $call_type"
                            echo "      Function: $func_name"
                            echo "      Arguments: $func_args"
                            echo "      Arguments Type: $args_type"

                            # Try to parse arguments if string
                            if [[ "$args_type" == "string" ]]; then
                                local parsed=$(echo "$func_args" | jq . 2>/dev/null || echo "INVALID_JSON")
                                echo "      Parsed Arguments: $parsed"
                            fi
                        done
                    fi
                    echo ""
                done
            fi
        else
            echo "ERROR: $response_body"
        fi
    } > "$analysis_file"

    if [[ "$http_code" == "200" ]]; then
        success "$model $tool_type test completed"
    else
        error "$model $tool_type test failed (HTTP $http_code)"
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication issue detected. Check your GitHub Copilot subscription and token."
            return 1
        fi
    fi

    log "Analysis: $analysis_file"
}

# Test tool flow (math then file)
test_tool_flow() {
    local model="$1"

    log "Testing tool flow with $model: math -> file"

    local token=$(get_copilot_token)
    if [[ $? -ne 0 ]]; then
        error "Failed to get authentication token for $model flow test"
        return 1
    fi
    local safe_model=$(echo "$model" | tr '/' '_')

    # Step 1: Initial request with both tools
    local payload=$(cat << EOF
{
  "intent": true,
  "n": 1,
  "stream": true,
  "temperature": 0.1,
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a highly skilled software engineer with extensive knowledge in many programming languages, frameworks, design patterns, and best practices.\n\n## Communication\n\n1. Be conversational but professional.\n2. Refer to the user in the second person and you should use the provided tools to help them.\n\nUse the provided tools to complete tasks step by step."
    },
    {
      "role": "user",
      "content": "Calculate 25 * 8 and then write the result to a file called calculation.txt"
    }
  ],
  "tools": [$MATH_TOOL, $FILE_TOOL],
  "tool_choice": "auto"
}
EOF
)

    local flow_file="$OUTPUT_DIR/${safe_model}_flow_analysis_$TIMESTAMP.txt"
    echo "=== TOOL FLOW TEST FOR $model ===" > "$flow_file"
    echo "" >> "$flow_file"

    # Make initial call
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$payload" \
        "$API_BASE/chat/completions")

    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')

    echo "Step 1: Initial request with both tools" >> "$flow_file"
    echo "HTTP Status: $http_code" >> "$flow_file"
    echo "" >> "$flow_file"

    if [[ "$http_code" == "200" ]]; then
        # Save response
        echo "$response_body" > "$OUTPUT_DIR/${safe_model}_flow_step1_$TIMESTAMP.json"

        # Analyze tool calls
        local total_tool_calls=0

        if echo "$response_body" | grep -q "^data: "; then
            echo "Response type: Streaming (SSE)" >> "$flow_file"

            # Parse streaming response for tool calls
            local tool_functions=()
            while IFS= read -r line; do
                if [[ "$line" =~ ^data:\ \{.*\}$ ]]; then
                    local json_data="${line#data: }"

                    # Check for tool calls
                    if echo "$json_data" | jq -e '.choices[0].delta.tool_calls[0].function.name' >/dev/null 2>&1; then
                        local tool_function=$(echo "$json_data" | jq -r '.choices[0].delta.tool_calls[0].function.name' 2>/dev/null)
                        if [[ -n "$tool_function" && "$tool_function" != "null" ]]; then
                            # Check if we already counted this function
                            local found=false
                            for existing_func in "${tool_functions[@]}"; do
                                if [[ "$existing_func" == "$tool_function" ]]; then
                                    found=true
                                    break
                                fi
                            done
                            if [[ "$found" == false ]]; then
                                tool_functions+=("$tool_function")
                                total_tool_calls=$((total_tool_calls + 1))
                                echo "Tool detected: $tool_function" >> "$flow_file"
                            fi
                        fi
                    fi
                fi
            done <<< "$response_body"
        else
            echo "Response type: Regular JSON" >> "$flow_file"
            local choices=$(echo "$response_body" | jq '.choices | length' 2>/dev/null || echo "0")
            echo "Choices: $choices" >> "$flow_file"

            for ((i=0; i<choices; i++)); do
                local tool_calls=$(echo "$response_body" | jq ".choices[$i].message.tool_calls // []" 2>/dev/null)
                local tool_count=$(echo "$tool_calls" | jq 'length' 2>/dev/null || echo "0")
                total_tool_calls=$((total_tool_calls + tool_count))

                echo "Choice $i: $tool_count tool calls" >> "$flow_file"

                for ((j=0; j<tool_count; j++)); do
                    local func_name=$(echo "$tool_calls" | jq -r ".[$j].function.name" 2>/dev/null)
                    echo "  Tool $j: $func_name" >> "$flow_file"
                done
            done
        fi

        echo "" >> "$flow_file"
        echo "Total tool calls: $total_tool_calls" >> "$flow_file"

        if [[ $total_tool_calls -eq 1 ]]; then
            echo "Result: Single tool call (sequential)" >> "$flow_file"
        elif [[ $total_tool_calls -eq 2 ]]; then
            echo "Result: Multiple tool calls (parallel)" >> "$flow_file"
        else
            echo "Result: Unexpected tool call count" >> "$flow_file"
        fi

        success "$model flow test completed"
    else
        echo "ERROR: $response_body" >> "$flow_file"
        error "$model flow test failed (HTTP $http_code)"
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication issue detected. Check your GitHub Copilot subscription and token."
            return 1
        fi
    fi

    log "Flow analysis: $flow_file"
}

# Main execution
main() {
    log "Testing direct GitHub Copilot API with tool flow"
    log "Output directory: $OUTPUT_DIR"

    # Test authentication first
    test_auth

    for model in "${MODELS[@]}"; do
        log "=========================================="
        log "Testing model: $model"
        log "=========================================="

        # Test individual tools
        if test_single_tool "$model" "math" "math"; then
            sleep 2
            if test_single_tool "$model" "file" "file"; then
                sleep 2
                # Test tool flow
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

    # Generate summary
    local summary_file="$OUTPUT_DIR/summary_$TIMESTAMP.md"
    {
        echo "# Direct GitHub Copilot Tool Flow Test Results"
        echo ""
        echo "## Test Configuration"
        echo "- API Base: $API_BASE"
        echo "- Timestamp: $TIMESTAMP"
        echo "- Tools: Math calculation + File writing"
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
    } > "$summary_file"

    success "Direct API testing completed!"
    log "Check $OUTPUT_DIR for raw responses and analysis"
    log "Summary: $summary_file"
}

# Check dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        error "Required command not found: $cmd"
        exit 1
    fi
done

# Run main function
main
