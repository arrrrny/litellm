#!/usr/bin/env bash

set -e

API_BASE="http://litellm-litellm-1:4000"
API_KEY="sk-1234"
OUTPUT_DIR="./litellm_copilot_tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }

mkdir -p "$OUTPUT_DIR"

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

MODELS=("github_copilot/gpt-4.1" "github_copilot/gpt-4o" "github_copilot/claude-3.5-sonnet" "github_copilot/o3-mini")

test_single_tool() {
    local model="$1"
    local tool_type="$2"
    local test_name="$3"
    log "Testing $model with $tool_type tool"
    local safe_model=$(echo "$model" | tr '/' '_')
    local payload
    if [[ "$tool_type" == "math" ]]; then
        payload='{"model": "'"$model"'","messages":[{"role":"user","content":"What is 42 * 15?"}],"tools":['"$MATH_TOOL"'],"tool_choice":{"type":"function","function":{"name":"calculate"}},"max_tokens":100}'
    elif [[ "$tool_type" == "file" ]]; then
        payload='{"model": "'"$model"'","messages":[{"role":"user","content":"Write hello world to hello.txt"}],"tools":['"$FILE_TOOL"'],"tool_choice":{"type":"function","function":{"name":"write_file"}},"max_tokens":100}'
    else
        error "Unknown tool type: $tool_type"
        return 1
    fi
    local response_file="$OUTPUT_DIR/${safe_model}_${test_name}_response_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_${test_name}_analysis_$TIMESTAMP.txt"
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$response_file"
    echo "HTTP code: $http_code" > "$analysis_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model $tool_type test succeeded"
        echo "Result: Success" >> "$analysis_file"
        # Extract tool call from response
        local tool_call=$(echo "$response_body" | jq -r '.choices[0].message.tool_calls[0] // empty' 2>/dev/null)
        if [[ -n "$tool_call" && "$tool_call" != "null" ]]; then
            echo "Tool call extracted: $tool_call" >> "$analysis_file"
        fi
    else
        error "$model $tool_type test failed (HTTP $http_code)"
        echo "ERROR: $response_body" >> "$analysis_file"
    fi
    log "Analysis: $analysis_file"
}

test_tool_flow() {
    local model="$1"
    log "Testing tool flow with $model: math -> file"
    local safe_model=$(echo "$model" | tr '/' '_')
    local payload='{"model": "'"$model"'","messages":[{"role":"user","content":"What is 42 * 15?"},{"role":"assistant","content":"The answer is 630."},{"role":"user","content":"Write hello world to hello.txt"}],"tools":['"$MATH_TOOL,$FILE_TOOL"'],"max_tokens":100}'
    local flow_file="$OUTPUT_DIR/${safe_model}_tool_flow_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_tool_flow_analysis_$TIMESTAMP.txt"
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$flow_file"
    echo "HTTP code: $http_code" > "$analysis_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model flow test completed"
        echo "Result: Success" >> "$analysis_file"
    else
        echo "ERROR: $response_body" >> "$analysis_file"
        error "$model flow test failed (HTTP $http_code)"
    fi
    log "Flow analysis: $analysis_file"
}

test_basic_chat() {
    local model="$1"
    log "Testing basic chat with $model"
    local safe_model=$(echo "$model" | tr '/' '_')
    local payload='{"model": "'"$model"'","messages":[{"role":"user","content":"Hello! Can you help me with a simple task?"}],"max_tokens":50}'
    local chat_file="$OUTPUT_DIR/${safe_model}_basic_chat_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_basic_chat_analysis_$TIMESTAMP.txt"
    local http_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$API_BASE/chat/completions")
    local http_code=$(echo "$http_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$http_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    echo "$response_body" > "$chat_file"
    echo "HTTP code: $http_code" > "$analysis_file"
    if [[ "$http_code" == "200" ]]; then
        success "$model basic chat test succeeded"
        echo "Result: Success" >> "$analysis_file"
    else
        echo "ERROR: $response_body" >> "$analysis_file"
        error "$model basic chat test failed (HTTP $http_code)"
        return 1
    fi
    log "Chat analysis: $analysis_file"
}

main() {
    log "Testing LiteLLM proxy with GitHub Copilot models"
    log "API Base: $API_BASE"
    log "Output directory: $OUTPUT_DIR"
    
    # Test LiteLLM proxy health
    log "Testing LiteLLM proxy health..."
    local health_response=$(curl -s -w "HTTPSTATUS:%{http_code}" -H "Authorization: Bearer $API_KEY" "$API_BASE/models")
    local health_code=$(echo "$health_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    if [[ "$health_code" != "200" ]]; then
        error "LiteLLM proxy health check failed (HTTP $health_code)"
        exit 1
    fi
    success "LiteLLM proxy is healthy"
    
    for model in "${MODELS[@]}"; do
        log "=========================================="
        log "Testing model: $model"
        log "=========================================="
        if test_basic_chat "$model"; then
            sleep 1
            if test_single_tool "$model" "math" "math"; then
                sleep 1
                if test_single_tool "$model" "file" "file"; then
                    sleep 1
                    test_tool_flow "$model"
                    sleep 2
                else
                    error "Skipping tool flow test for $model due to file tool test failure"
                fi
            else
                error "Skipping remaining tests for $model due to math tool test failure"
                continue
            fi
        else
            error "Skipping all tests for $model due to basic chat test failure"
            continue
        fi
        log "Completed $model"
        log ""
    done
    
    local summary_file="$OUTPUT_DIR/summary_$TIMESTAMP.md"
    {
        echo "# LiteLLM GitHub Copilot Tool Flow Test Results"
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
    log "Summary written to $summary_file"
}

main