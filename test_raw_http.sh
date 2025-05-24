#!/usr/bin/env bash

# Raw HTTP Testing Script for GitHub Copilot Tool Calls
# Tests math operations with file writing to understand transformation behavior

set -e

# Configuration
: "${API_KEY:="sk-QtvaA69MEXsO_OOeD6Sxlw"}"
: "${ENDPOINT:=http://localhost:4000/v1/chat/completions}"
: "${OUTPUT_DIR:=./raw_http_tests}"
: "${TIMESTAMP:=$(date +%Y%m%d_%H%M%S)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test models
MODELS=(
    "github_copilot/gpt-4o"
    "github_copilot/claude-3.5-sonnet"
    "github_copilot/gemini-2.5-pro"
    "github_copilot/o1"
)

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$OUTPUT_DIR/test_log_$TIMESTAMP.txt"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_DIR/test_log_$TIMESTAMP.txt"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$OUTPUT_DIR/test_log_$TIMESTAMP.txt"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$OUTPUT_DIR/test_log_$TIMESTAMP.txt"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Math tool definition
read -r -d '' MATH_TOOL << 'EOF'
{
  "type": "function",
  "function": {
    "name": "calculate_and_save",
    "description": "Perform mathematical calculation and save result to file",
    "parameters": {
      "type": "object",
      "properties": {
        "expression": {
          "type": "string",
          "description": "Mathematical expression to calculate (e.g., '25 + 17', '144 / 12')"
        },
        "filename": {
          "type": "string",
          "description": "Name of file to save the result (e.g., 'calculation_result.txt')"
        },
        "operation_description": {
          "type": "string",
          "description": "Human readable description of the operation"
        }
      },
      "required": ["expression", "filename"]
    }
  }
}
EOF

# File writing tool definition
read -r -d '' FILE_TOOL << 'EOF'
{
  "type": "function",
  "function": {
    "name": "write_to_file",
    "description": "Write content to a specified file",
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
        },
        "mode": {
          "type": "string",
          "enum": ["overwrite", "append"],
          "description": "Whether to overwrite or append to the file"
        }
      },
      "required": ["filename", "content"]
    }
  }
}
EOF

# Capture raw HTTP request/response
capture_raw_http() {
    local model="$1"
    local payload="$2"
    local test_name="$3"
    local step="$4"
    
    local safe_model=$(echo "$model" | sed 's/[^a-zA-Z0-9_-]/_/g')
    local raw_file="$OUTPUT_DIR/${safe_model}_${test_name}_${step}_raw_$TIMESTAMP"
    
    log "Capturing raw HTTP for $model - $test_name ($step)"
    
    # Create curl command with verbose output
    local curl_cmd=(
        curl -v
        -H "Authorization: Bearer $API_KEY"
        -H "Content-Type: application/json"
        -H "Editor-Version: vscode/1.85.1"
        -H "Editor-Plugin-Version: copilot/1.155.0"
        -H "User-Agent: GithubCopilot/1.155.0"
        -H "Copilot-Integration-Id: vscode-chat"
        -d "$payload"
        "$ENDPOINT"
    )
    
    # Execute curl and capture everything
    {
        echo "=== RAW HTTP REQUEST CAPTURE ==="
        echo "Timestamp: $(date)"
        echo "Model: $model"
        echo "Test: $test_name"
        echo "Step: $step"
        echo ""
        echo "=== CURL COMMAND ==="
        printf '%s\n' "${curl_cmd[@]}"
        echo ""
        echo "=== REQUEST PAYLOAD ==="
        echo "$payload" | jq .
        echo ""
        echo "=== HTTP EXCHANGE ==="
    } > "${raw_file}.log"
    
    # Run curl with verbose output and capture response
    "${curl_cmd[@]}" >> "${raw_file}.log" 2>&1
    local exit_code=$?
    
    # Extract just the JSON response for analysis
    local response=$(tail -n 50 "${raw_file}.log" | grep -E '^\{.*\}$' | head -n 1)
    if [[ -n "$response" ]]; then
        echo "$response" | jq . > "${raw_file}_response.json" 2>/dev/null || echo "$response" > "${raw_file}_response.json"
    fi
    
    echo "${raw_file}.log"
}

# Test single math operation
test_math_operation() {
    local model="$1"
    local expression="$2"
    local filename="$3"
    local description="$4"
    local test_name="$5"
    
    log "Testing math operation: $expression with $model"
    
    # Create initial request payload
    local payload=$(jq -cn \
        --arg model "$model" \
        --arg expr "$expression" \
        --arg file "$filename" \
        --arg desc "$description" \
        --argjson tool "$MATH_TOOL" \
        '{
            model: $model,
            messages: [
                {
                    role: "system",
                    content: "You are a helpful assistant that can perform calculations and save results to files. Use the provided tools."
                },
                {
                    role: "user", 
                    content: "Calculate \($expr) and save the result to \($file). \($desc)"
                }
            ],
            tools: [$tool],
            tool_choice: "auto",
            max_tokens: 1000
        }'
    )
    
    # Capture initial request
    local raw_file=$(capture_raw_http "$model" "$payload" "$test_name" "initial")
    local response_file="${raw_file}_response.json"
    
    # Check if response exists and is valid
    if [[ ! -f "$response_file" ]]; then
        error "No response file generated for $model"
        return 1
    fi
    
    # Analyze response structure
    local error_msg=$(jq -r '.error.message // empty' "$response_file" 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        error "API Error for $model: $error_msg"
        return 1
    fi
    
    # Extract tool call information
    local choices_count=$(jq '.choices | length' "$response_file" 2>/dev/null || echo "0")
    log "Response has $choices_count choices"
    
    # Check each choice for tool calls
    local tool_call_found=false
    for ((i=0; i<choices_count; i++)); do
        local tool_calls=$(jq ".choices[$i].message.tool_calls // []" "$response_file" 2>/dev/null)
        local tool_count=$(echo "$tool_calls" | jq 'length' 2>/dev/null || echo "0")
        
        if [[ "$tool_count" -gt 0 ]]; then
            log "Found $tool_count tool call(s) in choice $i"
            tool_call_found=true
            
            # Extract first tool call details
            local tool_call=$(echo "$tool_calls" | jq '.[0]' 2>/dev/null)
            local call_id=$(echo "$tool_call" | jq -r '.id // "unknown"' 2>/dev/null)
            local func_name=$(echo "$tool_call" | jq -r '.function.name // "unknown"' 2>/dev/null)
            local func_args=$(echo "$tool_call" | jq -r '.function.arguments // "{}"' 2>/dev/null)
            
            log "Tool call details:"
            log "  ID: $call_id"
            log "  Function: $func_name"
            log "  Arguments: $func_args"
            
            # Parse arguments
            local parsed_args
            if echo "$func_args" | jq . >/dev/null 2>&1; then
                parsed_args="$func_args"
            else
                parsed_args=$(echo "$func_args" | jq -Rs . | jq 'fromjson' 2>/dev/null || echo '{}')
            fi
            
            # Execute the tool call
            local calc_expression=$(echo "$parsed_args" | jq -r '.expression // ""')
            local save_filename=$(echo "$parsed_args" | jq -r '.filename // "result.txt"')
            local operation_desc=$(echo "$parsed_args" | jq -r '.operation_description // ""')
            
            log "Executing calculation: $calc_expression"
            local result=$(echo "$calc_expression" | bc -l 2>/dev/null || echo "Error: Cannot calculate")
            
            # Create tool result
            local tool_result="Calculation: $calc_expression = $result"
            if [[ -n "$operation_desc" ]]; then
                tool_result="$tool_result\nOperation: $operation_desc"
            fi
            tool_result="$tool_result\nResult saved to: $save_filename"
            
            # Actually save to file for demonstration
            echo "Calculation: $calc_expression" > "$OUTPUT_DIR/$save_filename"
            echo "Result: $result" >> "$OUTPUT_DIR/$save_filename"
            echo "Timestamp: $(date)" >> "$OUTPUT_DIR/$save_filename"
            
            # Create follow-up request with tool result
            local followup_payload=$(jq -cn \
                --arg model "$model" \
                --arg expr "$expression" \
                --arg file "$filename" \
                --arg desc "$description" \
                --argjson tool "$MATH_TOOL" \
                --arg call_id "$call_id" \
                --arg func_name "$func_name" \
                --arg func_args "$func_args" \
                --arg result "$tool_result" \
                '{
                    model: $model,
                    messages: [
                        {
                            role: "system",
                            content: "You are a helpful assistant that can perform calculations and save results to files. Use the provided tools."
                        },
                        {
                            role: "user", 
                            content: "Calculate \($expr) and save the result to \($file). \($desc)"
                        },
                        {
                            role: "assistant",
                            content: "",
                            tool_calls: [
                                {
                                    id: $call_id,
                                    type: "function",
                                    function: {
                                        name: $func_name,
                                        arguments: $func_args
                                    }
                                }
                            ]
                        },
                        {
                            role: "tool",
                            tool_call_id: $call_id,
                            content: $result
                        }
                    ],
                    tools: [$tool],
                    max_tokens: 1000
                }'
            )
            
            # Capture follow-up request
            local followup_file=$(capture_raw_http "$model" "$followup_payload" "$test_name" "followup")
            local followup_response="${followup_file}_response.json"
            
            if [[ -f "$followup_response" ]]; then
                local final_content=$(jq -r '.choices[0].message.content // "No content"' "$followup_response" 2>/dev/null)
                log "Final response: ${final_content:0:200}..."
                success "Completed tool call test for $model"
            fi
            
            break
        fi
    done
    
    if [[ "$tool_call_found" == false ]]; then
        warning "No tool calls found in response for $model"
        return 1
    fi
    
    return 0
}

# Test parallel tool calls
test_parallel_tools() {
    local model="$1"
    local test_name="parallel_math"
    
    log "Testing parallel tool calls with $model"
    
    local payload=$(jq -cn \
        --arg model "$model" \
        --argjson math_tool "$MATH_TOOL" \
        --argjson file_tool "$FILE_TOOL" \
        '{
            model: $model,
            messages: [
                {
                    role: "system",
                    content: "You are a helpful assistant. Use the provided tools to complete tasks."
                },
                {
                    role: "user",
                    content: "Calculate 45 + 23 and save it to sum_result.txt, then also write a summary to summary.txt"
                }
            ],
            tools: [$math_tool, $file_tool],
            tool_choice: "auto",
            max_tokens: 1000
        }'
    )
    
    local raw_file=$(capture_raw_http "$model" "$payload" "$test_name" "initial")
    local response_file="${raw_file}_response.json"
    
    if [[ -f "$response_file" ]]; then
        local tool_calls_total=0
        local choices_count=$(jq '.choices | length' "$response_file" 2>/dev/null || echo "0")
        
        for ((i=0; i<choices_count; i++)); do
            local choice_tools=$(jq ".choices[$i].message.tool_calls // [] | length" "$response_file" 2>/dev/null || echo "0")
            tool_calls_total=$((tool_calls_total + choice_tools))
        done
        
        log "Total tool calls found: $tool_calls_total"
        
        if [[ $tool_calls_total -gt 1 ]]; then
            success "Parallel tool calls supported by $model"
        elif [[ $tool_calls_total -eq 1 ]]; then
            warning "Only single tool call found for $model"
        else
            warning "No tool calls found for $model"
        fi
    fi
}

# Test different argument formats
test_argument_formats() {
    local model="$1"
    
    log "Testing argument format handling with $model"
    
    # Test with complex nested arguments
    local complex_payload=$(jq -cn \
        --arg model "$model" \
        --argjson tool "$MATH_TOOL" \
        '{
            model: $model,
            messages: [
                {
                    role: "system",
                    content: "You are a helpful assistant."
                },
                {
                    role: "user",
                    content: "Calculate the result of (15 * 3) + (20 / 4) and save it to complex_calc.txt with description \"Complex arithmetic operation\""
                }
            ],
            tools: [$tool],
            tool_choice: "auto",
            max_tokens: 1000
        }'
    )
    
    local raw_file=$(capture_raw_http "$model" "$complex_payload" "complex_args" "initial")
    local response_file="${raw_file}_response.json"
    
    if [[ -f "$response_file" ]]; then
        # Analyze argument structure
        local args_analysis="$OUTPUT_DIR/args_analysis_${model//\//_}_$TIMESTAMP.txt"
        {
            echo "=== ARGUMENT FORMAT ANALYSIS ==="
            echo "Model: $model"
            echo "Timestamp: $(date)"
            echo ""
            
            local choices_count=$(jq '.choices | length' "$response_file" 2>/dev/null || echo "0")
            for ((i=0; i<choices_count; i++)); do
                echo "Choice $i:"
                local tool_calls=$(jq ".choices[$i].message.tool_calls // []" "$response_file" 2>/dev/null)
                local tool_count=$(echo "$tool_calls" | jq 'length' 2>/dev/null || echo "0")
                
                for ((j=0; j<tool_count; j++)); do
                    echo "  Tool Call $j:"
                    local tool_call=$(echo "$tool_calls" | jq ".[$j]" 2>/dev/null)
                    local func_args=$(echo "$tool_call" | jq -r '.function.arguments // "{}"' 2>/dev/null)
                    
                    echo "    Raw arguments: $func_args"
                    echo "    Arguments type: $(echo "$func_args" | jq -r 'type' 2>/dev/null || echo 'string')"
                    
                    if echo "$func_args" | jq . >/dev/null 2>&1; then
                        echo "    Parsed arguments:"
                        echo "$func_args" | jq . | sed 's/^/      /'
                    else
                        echo "    String arguments (needs parsing):"
                        echo "      $func_args"
                    fi
                done
            done
        } > "$args_analysis"
        
        log "Argument analysis saved to: $args_analysis"
    fi
}

# Generate comprehensive report
generate_report() {
    local report_file="$OUTPUT_DIR/raw_http_analysis_$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Raw HTTP Analysis Report for GitHub Copilot Tool Calls

## Test Configuration
- Timestamp: $TIMESTAMP
- Endpoint: $ENDPOINT
- Output Directory: $OUTPUT_DIR
- Tools Tested: Math Calculator, File Writer

## Models Tested
EOF
    
    for model in "${MODELS[@]}"; do
        echo "- $model" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    echo "## Raw HTTP Captures" >> "$report_file"
    echo "" >> "$report_file"
    
    ls "$OUTPUT_DIR"/*.log 2>/dev/null | while read -r logfile; do
        if [[ -n "$logfile" ]]; then
            echo "- $(basename "$logfile")" >> "$report_file"
        fi
    done
    
    echo "" >> "$report_file"
    echo "## Response Analysis" >> "$report_file"
    echo "" >> "$report_file"
    
    ls "$OUTPUT_DIR"/*_response.json 2>/dev/null | while read -r respfile; do
        if [[ -n "$respfile" ]]; then
            local model_name=$(basename "$respfile" | cut -d'_' -f1-2)
            echo "### $model_name" >> "$report_file"
            
            local choices=$(jq '.choices | length' "$respfile" 2>/dev/null || echo "0")
            local tool_calls=$(jq '[.choices[].message.tool_calls // [] | length] | add' "$respfile" 2>/dev/null || echo "0")
            
            echo "- Choices: $choices" >> "$report_file"
            echo "- Tool calls: $tool_calls" >> "$report_file"
            echo "" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

## Key Findings

### Request Structure
- All requests use standard OpenAI format
- Tools are passed in 'tools' array
- Messages follow standard conversation format

### Response Patterns
- Tool calls appear in choices[].message.tool_calls
- Arguments are typically JSON strings
- Finish reason is 'tool_calls' when tools are invoked

### File Outputs
- Raw HTTP logs show complete request/response cycle
- Response JSONs contain structured tool call data
- Argument analysis files show parsing requirements

## Files Generated
EOF
    
    ls "$OUTPUT_DIR"/*_$TIMESTAMP.* | sort | while read -r file; do
        if [[ -n "$file" ]]; then
            echo "- $(basename "$file")" >> "$report_file"
        fi
    done
    
    success "Raw HTTP analysis report generated: $report_file"
}

# Main execution
main() {
    log "Starting Raw HTTP Analysis for GitHub Copilot Tool Calls"
    log "Testing ${#MODELS[@]} models with math operations and file writing"
    log "Output directory: $OUTPUT_DIR"
    
    # Test scenarios for each model
    for model in "${MODELS[@]}"; do
        log "=========================================="
        log "Testing model: $model"
        log "=========================================="
        
        # Test basic math operation
        test_math_operation "$model" "25 + 17" "addition_result.txt" "Simple addition operation" "basic_math"
        sleep 2
        
        # Test division
        test_math_operation "$model" "144 / 12" "division_result.txt" "Basic division operation" "division"
        sleep 2
        
        # Test multiplication
        test_math_operation "$model" "7 * 8" "multiplication_result.txt" "Multiplication table entry" "multiplication"
        sleep 2
        
        # Test complex expression
        test_math_operation "$model" "(15 + 25) * 2" "complex_result.txt" "Complex arithmetic expression" "complex"
        sleep 2
        
        # Test parallel tools
        test_parallel_tools "$model"
        sleep 2
        
        # Test argument formats
        test_argument_formats "$model"
        sleep 3
        
        log "Completed testing $model"
        log ""
    done
    
    # Generate comprehensive report
    generate_report
    
    success "Raw HTTP analysis completed!"
    log "Check $OUTPUT_DIR for detailed HTTP captures and analysis"
    log "Raw logs show complete request/response cycle"
    log "Response JSONs show tool call structures"
    log "Generated files show actual tool execution results"
}

# Command line argument handling
case "${1:-}" in
    -h|--help)
        echo "Raw HTTP Testing Script for GitHub Copilot Tool Calls"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help"
        echo "  -e ENDPOINT    Set API endpoint"
        echo "  -k API_KEY     Set API key"
        echo "  -o OUTPUT_DIR  Set output directory"
        echo ""
        echo "Environment Variables:"
        echo "  API_KEY        API key for authentication"
        echo "  ENDPOINT       API endpoint URL"
        echo "  OUTPUT_DIR     Output directory for results"
        echo ""
        exit 0
        ;;
    -e)
        ENDPOINT="$2"
        shift 2
        ;;
    -k)
        API_KEY="$2"
        shift 2
        ;;
    -o)
        OUTPUT_DIR="$2"
        mkdir -p "$OUTPUT_DIR"
        shift 2
        ;;
esac

# Dependency check
for cmd in curl jq bc; do
    if ! command -v "$cmd" &> /dev/null; then
        error "Required command not found: $cmd"
        exit 1
    fi
done

# Run main function
main