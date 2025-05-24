#!/usr/bin/env bash

# Fixed GitHub Copilot API Testing Script
# Tests tool flow with corrected formats for all models

set -e

# Configuration
API_BASE="https://api.githubcopilot.com"
OUTPUT_DIR="./fixed_copilot_tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get GitHub Copilot token
get_copilot_token() {
    if command -v python3 &> /dev/null; then
        token=$(python3 -c "
import sys
sys.path.insert(0, '.')
try:
    from litellm.llms.github_copilot.authenticator import Authenticator
    auth = Authenticator()
    print(auth.get_api_key())
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    exit(1)
" 2>/dev/null)
        
        if [[ $? -eq 0 && -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi
    
    error "Could not get GitHub Copilot token"
    exit 1
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

# Model configurations with their optimal tool_choice settings
# Format: model_name:tool_choice_type
MODEL_CONFIGS="
gpt-4o:auto
o1:auto
o3-mini:auto
gemini-2.5-pro:auto
claude-3.5-sonnet:force
claude-3.7-sonnet:force
claude-sonnet-4:force
gpt-4.1:auto
o4-mini:auto
"

# Get tool choice for model
get_tool_choice() {
    local model="$1"
    local tool_name="$2"
    local choice_type=$(echo "$MODEL_CONFIGS" | grep "^$model:" | cut -d: -f2)
    
    if [[ "$choice_type" == "force" ]]; then
        echo '{"type": "function", "function": {"name": "'$tool_name'"}}'
    else
        echo '"auto"'
    fi
}

# Test single tool call with optimal settings
test_single_tool_optimized() {
    local model="$1"
    local tool_type="$2"
    local test_name="$3"
    
    log "Testing $model with $tool_type tool (optimized)"
    
    local token=$(get_copilot_token)
    local safe_model=$(echo "$model" | tr '/' '_')
    
    # Determine tool and tool_choice
    local tool_def
    local tool_name
    local tool_choice
    
    if [[ "$tool_type" == "math" ]]; then
        tool_def="$MATH_TOOL"
        tool_name="calculate"
        tool_choice=$(get_tool_choice "$model" "$tool_name")
    else
        tool_def="$FILE_TOOL"
        tool_name="write_file"
        tool_choice=$(get_tool_choice "$model" "$tool_name")
    fi
    
    # Create request payload
    local payload=$(cat << EOF
{
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant. Use the provided tools when appropriate."
    },
    {
      "role": "user",
      "content": "$(if [[ "$tool_type" == "math" ]]; then echo "Calculate 42 * 15"; else echo "Write 'Hello World' to a file called greeting.txt"; fi)"
    }
  ],
  "tools": [$tool_def],
  "tool_choice": $tool_choice
}
EOF
)
    
    # Save request
    local request_file="$OUTPUT_DIR/${safe_model}_${test_name}_opt_request_$TIMESTAMP.json"
    echo "$payload" | jq . > "$request_file"
    
    # Make API call
    local response_file="$OUTPUT_DIR/${safe_model}_${test_name}_opt_response_$TIMESTAMP.json"
    local analysis_file="$OUTPUT_DIR/${safe_model}_${test_name}_opt_analysis_$TIMESTAMP.txt"
    
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
    
    echo "$response_body" | jq . > "$response_file" 2>/dev/null || echo "$response_body" > "$response_file"
    
    # Analyze response
    {
        echo "=== OPTIMIZED ANALYSIS FOR $model - $tool_type TOOL ==="
        echo "HTTP Status: $http_code"
        echo "Tool Choice: $tool_choice"
        echo "Request file: $request_file"
        echo "Response file: $response_file"
        echo ""
        
        if [[ "$http_code" == "200" ]]; then
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
                        
                        echo "    Tool Call $j:"
                        echo "      ID: $call_id"
                        echo "      Type: $call_type"
                        echo "      Function: $func_name"
                        echo "      Arguments: $func_args"
                    done
                fi
                echo ""
            done
        else
            echo "ERROR: $response_body"
        fi
    } > "$analysis_file"
    
    if [[ "$http_code" == "200" ]]; then
        local tool_count=$(echo "$response_body" | jq '.choices[0].message.tool_calls | length' 2>/dev/null || echo "0")
        if [[ "$tool_count" -gt 0 ]]; then
            success "$model $tool_type test completed with tool calls"
        else
            warning "$model $tool_type test completed but no tool calls"
        fi
    else
        error "$model $tool_type test failed (HTTP $http_code)"
    fi
    
    log "Analysis: $analysis_file"
}

# Test comprehensive tool flow
test_comprehensive_flow() {
    local model="$1"
    
    log "Testing comprehensive flow with $model"
    
    local token=$(get_copilot_token)
    local safe_model=$(echo "$model" | tr '/' '_')
    
    # Step 1: Math calculation
    local math_tool_choice=$(get_tool_choice "$model" "calculate")
    local math_payload=$(cat << EOF
{
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant. Use tools when appropriate."
    },
    {
      "role": "user",
      "content": "Calculate 25 * 8"
    }
  ],
  "tools": [$MATH_TOOL],
  "tool_choice": $math_tool_choice
}
EOF
)
    
    local flow_file="$OUTPUT_DIR/${safe_model}_comprehensive_flow_$TIMESTAMP.txt"
    echo "=== COMPREHENSIVE FLOW TEST FOR $model ===" > "$flow_file"
    echo "Math tool choice: $math_tool_choice" >> "$flow_file"
    echo "" >> "$flow_file"
    
    # Make math calculation call
    local math_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$math_payload" \
        "$API_BASE/chat/completions")
    
    local math_http_code=$(echo "$math_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local math_response_body=$(echo "$math_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    
    echo "Step 1: Math calculation" >> "$flow_file"
    echo "HTTP Status: $math_http_code" >> "$flow_file"
    
    if [[ "$math_http_code" == "200" ]]; then
        local math_tool_calls=$(echo "$math_response_body" | jq '.choices[0].message.tool_calls | length' 2>/dev/null || echo "0")
        echo "Tool calls: $math_tool_calls" >> "$flow_file"
        
        if [[ "$math_tool_calls" -gt 0 ]]; then
            # Step 2: File writing
            local file_tool_choice=$(get_tool_choice "$model" "write_file")
            local file_payload=$(cat << EOF
{
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant. Use tools when appropriate."
    },
    {
      "role": "user",
      "content": "Write the result '200' to a file called result.txt"
    }
  ],
  "tools": [$FILE_TOOL],
  "tool_choice": $file_tool_choice
}
EOF
)
            
            echo "" >> "$flow_file"
            echo "Step 2: File writing" >> "$flow_file"
            echo "File tool choice: $file_tool_choice" >> "$flow_file"
            
            local file_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -H "Editor-Version: vscode/1.85.1" \
                -H "Editor-Plugin-Version: copilot/1.155.0" \
                -H "User-Agent: GithubCopilot/1.155.0" \
                -H "Copilot-Integration-Id: vscode-chat" \
                -d "$file_payload" \
                "$API_BASE/chat/completions")
            
            local file_http_code=$(echo "$file_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
            local file_response_body=$(echo "$file_response" | sed 's/HTTPSTATUS:[0-9]*$//')
            
            echo "HTTP Status: $file_http_code" >> "$flow_file"
            
            if [[ "$file_http_code" == "200" ]]; then
                local file_tool_calls=$(echo "$file_response_body" | jq '.choices[0].message.tool_calls | length' 2>/dev/null || echo "0")
                echo "Tool calls: $file_tool_calls" >> "$flow_file"
                
                if [[ "$file_tool_calls" -gt 0 ]]; then
                    echo "Result: COMPLETE SUCCESS - Both tools worked" >> "$flow_file"
                    success "$model comprehensive flow completed successfully"
                else
                    echo "Result: PARTIAL SUCCESS - Math worked, file failed" >> "$flow_file"
                    warning "$model comprehensive flow partially successful"
                fi
            else
                echo "Result: PARTIAL SUCCESS - Math worked, file failed with HTTP $file_http_code" >> "$flow_file"
                warning "$model comprehensive flow partially successful"
            fi
        else
            echo "Result: FAILED - Math tool call failed" >> "$flow_file"
            error "$model comprehensive flow failed at math step"
        fi
    else
        echo "Result: FAILED - Math step failed with HTTP $math_http_code" >> "$flow_file"
        error "$model comprehensive flow failed at math step"
    fi
    
    log "Flow analysis: $flow_file"
}

# Main execution
main() {
    log "Testing GitHub Copilot API with optimized configurations"
    log "Output directory: $OUTPUT_DIR"
    
    # Test all models
    local all_models=$(echo "$MODEL_CONFIGS" | grep -v "^$" | cut -d: -f1 | sort)
    local model_count=$(echo "$all_models" | wc -l)
    
    log "Found $model_count models to test"
    
    for model in $all_models; do
        local config=$(echo "$MODEL_CONFIGS" | grep "^$model:" | cut -d: -f2)
        log "=========================================="
        log "Testing model: $model (config: $config)"
        log "=========================================="
        
        # Test individual tools with optimized settings
        test_single_tool_optimized "$model" "math" "math"
        sleep 2
        test_single_tool_optimized "$model" "file" "file"
        sleep 2
        
        # Test comprehensive flow
        test_comprehensive_flow "$model"
        sleep 3
        
        log "Completed $model"
        log ""
    done
    
    # Generate summary
    local summary_file="$OUTPUT_DIR/fixed_summary_$TIMESTAMP.md"
    {
        echo "# Fixed GitHub Copilot Tool Flow Test Results"
        echo ""
        echo "## Test Configuration"
        echo "- API Base: $API_BASE"
        echo "- Timestamp: $TIMESTAMP"
        echo "- Optimization: Model-specific tool_choice configurations"
        echo ""
        echo "## Model Configurations"
        for model in $all_models; do
            local config=$(echo "$MODEL_CONFIGS" | grep "^$model:" | cut -d: -f2)
            echo "- $model: $config tool choice"
        done
        echo ""
        echo "## Key Insights"
        echo "- Claude models require explicit tool forcing"
        echo "- Other models work with auto tool choice"
        echo "- All requests use proper Copilot headers"
        echo ""
        echo "## Files Generated"
        ls "$OUTPUT_DIR"/*_$TIMESTAMP.* | sort | while read file; do
            echo "- $(basename "$file")"
        done
    } > "$summary_file"
    
    success "Fixed API testing completed!"
    log "Check $OUTPUT_DIR for optimized responses and analysis"
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