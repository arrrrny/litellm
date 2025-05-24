#!/usr/bin/env bash

# GitHub Copilot Tool Call Testing Script
# Tests tool calls across different providers (OpenAI, Anthropic, Google)
# to understand response structures and improve transformation robustness

# CONFIGURATION
: "${API_KEY:="sk-QtvaA69MEXsO_OOeD6Sxlw"}"
: "${ENDPOINT:=http://localhost:4000/v1/chat/completions}"
: "${OUTPUT_DIR:=./tool_test_results}"
: "${TIMESTAMP:=$(date +%Y%m%d_%H%M%S)}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Common headers
HEADERS=(
  "-H" "Authorization: Bearer ${API_KEY}"
  "-H" "Content-Type: application/json"
  "-H" "Editor-Version: vscode/1.85.1"
  "-H" "Editor-Plugin-Version: copilot/1.155.0"
  "-H" "User-Agent: GithubCopilot/1.155.0"
  "-H" "Copilot-Integration-Id: vscode-chat"
)

# Define test models by provider (using arrays for compatibility)
MODEL_KEYS=(
  "openai_gpt4o"
  "openai_gpt41"
  "openai_o1"
  "openai_o3mini"
  "openai_o4mini"
  "anthropic_claude35"
  "anthropic_claude37"
  "anthropic_claude4"
  "google_gemini20"
  "google_gemini25"
)

MODEL_VALUES=(
  "github_copilot/gpt-4o"
  "github_copilot/gpt-4.1"
  "github_copilot/o1"
  "github_copilot/o3-mini"
  "github_copilot/o4-mini"
  "github_copilot/claude-3.5-sonnet"
  "github_copilot/claude-3.7-sonnet"
  "github_copilot/claude-sonnet-4"
  "github_copilot/gemini-2.0-flash-001"
  "github_copilot/gemini-2.5-pro"
)

# Helper function to get model value by key
get_model_value() {
    local key="$1"
    for i in "${!MODEL_KEYS[@]}"; do
        if [[ "${MODEL_KEYS[$i]}" == "$key" ]]; then
            echo "${MODEL_VALUES[$i]}"
            return 0
        fi
    done
    return 1
}

# Tool definitions for different testing scenarios
read -r -d '' WEATHER_TOOL << 'EOF'
{
  "type": "function",
  "function": {
    "name": "get_weather_forecast",
    "description": "Get the weather for a city via wttr.in",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {"type": "string", "description": "The city name"}
      },
      "required": ["city"]
    }
  }
}
EOF

read -r -d '' CALCULATOR_TOOL << 'EOF'
{
  "type": "function",
  "function": {
    "name": "calculate",
    "description": "Perform mathematical calculations",
    "parameters": {
      "type": "object",
      "properties": {
        "expression": {"type": "string", "description": "Mathematical expression to evaluate"},
        "operation": {"type": "string", "enum": ["add", "subtract", "multiply", "divide"], "description": "Type of operation"}
      },
      "required": ["expression"]
    }
  }
}
EOF

read -r -d '' TIME_TOOL << 'EOF'
{
  "type": "function",
  "function": {
    "name": "get_current_time",
    "description": "Get the current time in a specific timezone",
    "parameters": {
      "type": "object",
      "properties": {
        "timezone": {"type": "string", "description": "Timezone identifier (e.g., 'UTC', 'America/New_York')"}
      },
      "required": ["timezone"]
    }
  }
}
EOF

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Extract provider from model name
get_provider() {
    local model="$1"
    if [[ "$model" =~ gpt|o[0-9] ]]; then
        echo "openai"
    elif [[ "$model" =~ claude ]]; then
        echo "anthropic"
    elif [[ "$model" =~ gemini ]]; then
        echo "google"
    else
        echo "unknown"
    fi
}

# Save response to file
save_response() {
    local model_key="$1"
    local step="$2"
    local response="$3"
    local filename="$OUTPUT_DIR/${model_key}_${step}_$TIMESTAMP.json"
    echo "$response" | jq . > "$filename" 2>/dev/null || echo "$response" > "$filename"
    echo "$filename"
}

# Analyze tool call structure
analyze_tool_calls() {
    local response="$1"
    local model="$2"
    local provider=$(get_provider "$model")
    
    log "Analyzing tool calls for $model ($provider):"
    
    # Check if response has choices
    local choices_count=$(echo "$response" | jq '.choices | length' 2>/dev/null || echo "0")
    log "  Choices count: $choices_count"
    
    # Analyze each choice
    for ((i=0; i<choices_count; i++)); do
        log "  Choice $i:"
        
        # Check message structure
        local message=$(echo "$response" | jq -r ".choices[$i].message" 2>/dev/null)
        local role=$(echo "$message" | jq -r '.role' 2>/dev/null)
        local content=$(echo "$message" | jq -r '.content' 2>/dev/null)
        local tool_calls=$(echo "$message" | jq '.tool_calls' 2>/dev/null)
        
        log "    Role: $role"
        log "    Content: ${content:0:100}..."
        
        if [[ "$tool_calls" != "null" && "$tool_calls" != "" ]]; then
            local tool_count=$(echo "$tool_calls" | jq 'length' 2>/dev/null || echo "0")
            log "    Tool calls count: $tool_count"
            
            for ((j=0; j<tool_count; j++)); do
                local tool_call=$(echo "$tool_calls" | jq ".[$j]" 2>/dev/null)
                local call_id=$(echo "$tool_call" | jq -r '.id' 2>/dev/null)
                local call_type=$(echo "$tool_call" | jq -r '.type' 2>/dev/null)
                local func_name=$(echo "$tool_call" | jq -r '.function.name' 2>/dev/null)
                local func_args=$(echo "$tool_call" | jq -r '.function.arguments' 2>/dev/null)
                
                log "      Tool Call $j:"
                log "        ID: $call_id"
                log "        Type: $call_type"
                log "        Function: $func_name"
                log "        Arguments: $func_args"
            done
        else
            log "    No tool calls found"
        fi
        
        # Check finish reason
        local finish_reason=$(echo "$response" | jq -r ".choices[$i].finish_reason" 2>/dev/null)
        log "    Finish reason: $finish_reason"
    done
}

# Execute tool function
execute_tool() {
    local func_name="$1"
    local args="$2"
    
    case "$func_name" in
        "get_weather_forecast")
            local city=$(echo "$args" | jq -r '.city' 2>/dev/null)
            local weather=$(curl -s "https://wttr.in/${city}?format=j1" | jq -r '{city:.nearest_area[0].areaName[0].value, country:.nearest_area[0].country[0].value, temp:.current_condition[0].temp_C, desc:.current_condition[0].weatherDesc[0].value}' 2>/dev/null)
            echo "$weather" | jq -r '"The weather in \(.city), \(.country) is \(.temp)°C and \(.desc)."' 2>/dev/null || echo "Weather data unavailable for $city"
            ;;
        "calculate")
            local expression=$(echo "$args" | jq -r '.expression' 2>/dev/null)
            local result=$(echo "$expression" | bc -l 2>/dev/null || echo "Cannot calculate: $expression")
            echo "The result of $expression is $result"
            ;;
        "get_current_time")
            local timezone=$(echo "$args" | jq -r '.timezone' 2>/dev/null)
            local current_time=$(TZ="$timezone" date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S UTC')
            echo "Current time in $timezone: $current_time"
            ;;
        *)
            echo "Unknown function: $func_name"
            ;;
    esac
}

# Test single tool call
test_single_tool() {
    local model_key="$1"
    local model="$2"
    local tool="$3"
    local user_message="$4"
    local test_name="$5"
    
    log "Testing single tool call: $test_name with $model_key"
    
    # Initial request
    local payload=$(jq -cn \
        --arg m "$model" \
        --arg msg "$user_message" \
        --argjson tool "$tool" \
        '{
            model: $m,
            messages: [
                {role:"system", content:"You are a helpful assistant. Use the provided tools when appropriate."},
                {role:"user", content:$msg}
            ],
            tools: [$tool],
            tool_choice: "auto"
        }'
    )
    
    log "Sending initial request..."
    local response=$(curl -s "${HEADERS[@]}" -d "$payload" "$ENDPOINT")
    local response_file=$(save_response "$model_key" "initial_$test_name" "$response")
    
    # Check for errors
    local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        error "API Error for $model_key: $error_msg"
        return 1
    fi
    
    analyze_tool_calls "$response" "$model"
    
    # Find tool calls in any choice
    local tool_call_choice=-1
    local choices_count=$(echo "$response" | jq '.choices | length' 2>/dev/null || echo "0")
    
    for ((i=0; i<choices_count; i++)); do
        local has_tools=$(echo "$response" | jq -r ".choices[$i].message.tool_calls // empty" 2>/dev/null)
        if [[ -n "$has_tools" && "$has_tools" != "null" ]]; then
            tool_call_choice=$i
            break
        fi
    done
    
    if [[ $tool_call_choice -eq -1 ]]; then
        warning "No tool calls found in response for $model_key"
        return 1
    fi
    
    # Extract tool call details
    local tool_call=$(echo "$response" | jq ".choices[$tool_call_choice].message.tool_calls[0]" 2>/dev/null)
    local call_id=$(echo "$tool_call" | jq -r '.id' 2>/dev/null)
    local func_name=$(echo "$tool_call" | jq -r '.function.name' 2>/dev/null)
    local func_args_str=$(echo "$tool_call" | jq -r '.function.arguments' 2>/dev/null)
    
    # Parse arguments (handle both string and object formats)
    local func_args
    if echo "$func_args_str" | jq . >/dev/null 2>&1; then
        func_args="$func_args_str"
    else
        func_args=$(echo "$func_args_str" | jq -R . | jq fromjson 2>/dev/null || echo '{}')
    fi
    
    log "Executing tool: $func_name with args: $func_args"
    local tool_result=$(execute_tool "$func_name" "$func_args")
    
    # Follow-up request with tool result
    local followup_payload=$(jq -cn \
        --arg m "$model" \
        --arg msg "$user_message" \
        --argjson tool "$tool" \
        --arg call_id "$call_id" \
        --arg func_name "$func_name" \
        --arg func_args "$func_args_str" \
        --arg result "$tool_result" \
        '{
            model: $m,
            messages: [
                {role:"system", content:"You are a helpful assistant. Use the provided tools when appropriate."},
                {role:"user", content:$msg},
                {role:"assistant", tool_calls:[{id:$call_id, type:"function", function:{name:$func_name, arguments:$func_args}}], content:""},
                {role:"tool", tool_call_id:$call_id, content:$result}
            ],
            tools: [$tool]
        }'
    )
    
    log "Sending follow-up request with tool result..."
    local final_response=$(curl -s "${HEADERS[@]}" -d "$followup_payload" "$ENDPOINT")
    local final_file=$(save_response "$model_key" "final_$test_name" "$final_response")
    
    # Check final response
    local final_error=$(echo "$final_response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$final_error" ]]; then
        error "Final API Error for $model_key: $final_error"
        return 1
    fi
    
    local final_content=$(echo "$final_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    log "Final response content: ${final_content:0:200}..."
    
    success "Completed tool call test for $model_key"
    return 0
}

# Test parallel tool calls
test_parallel_tools() {
    local model_key="$1"
    local model="$2"
    
    log "Testing parallel tool calls with $model_key"
    
    local tools="[$WEATHER_TOOL, $CALCULATOR_TOOL, $TIME_TOOL]"
    local user_message="What's the weather in Tokyo, what's 15 * 23, and what time is it in UTC?"
    
    local payload=$(jq -cn \
        --arg m "$model" \
        --arg msg "$user_message" \
        --argjson tools "$tools" \
        '{
            model: $m,
            messages: [
                {role:"system", content:"You are a helpful assistant. Use multiple tools if needed to answer the user question."},
                {role:"user", content:$msg}
            ],
            tools: $tools,
            tool_choice: "auto"
        }'
    )
    
    local response=$(curl -s "${HEADERS[@]}" -d "$payload" "$ENDPOINT")
    local response_file=$(save_response "$model_key" "parallel" "$response")
    
    local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        error "Parallel tools error for $model_key: $error_msg"
        return 1
    fi
    
    analyze_tool_calls "$response" "$model"
    
    # Count total tool calls across all choices
    local total_tools=0
    local choices_count=$(echo "$response" | jq '.choices | length' 2>/dev/null || echo "0")
    
    for ((i=0; i<choices_count; i++)); do
        local choice_tools=$(echo "$response" | jq ".choices[$i].message.tool_calls // [] | length" 2>/dev/null || echo "0")
        total_tools=$((total_tools + choice_tools))
    done
    
    log "Total tool calls found: $total_tools"
    
    if [[ $total_tools -gt 1 ]]; then
        success "Parallel tool calls supported by $model_key"
    elif [[ $total_tools -eq 1 ]]; then
        warning "Only single tool call found for $model_key (may not support parallel)"
    else
        warning "No tool calls found for $model_key"
    fi
    
    return 0
}

# Generate summary report
generate_report() {
    local report_file="$OUTPUT_DIR/tool_call_analysis_$TIMESTAMP.md"
    
    cat > "$report_file" << 'EOF'
# GitHub Copilot Tool Call Analysis Report

## Test Configuration
EOF
    
    echo "- Timestamp: $TIMESTAMP" >> "$report_file"
    echo "- Endpoint: $ENDPOINT" >> "$report_file"
    echo "- Output Directory: $OUTPUT_DIR" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "## Models Tested" >> "$report_file"
    echo "" >> "$report_file"
    
    for i in "${!MODEL_KEYS[@]}"; do
        local model_key="${MODEL_KEYS[$i]}"
        local model_value="${MODEL_VALUES[$i]}"
        local provider=$(get_provider "$model_value")
        echo "- **$model_key** ($model_value) - Provider: $provider" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    echo "## Test Results Summary" >> "$report_file"
    echo "" >> "$report_file"
    echo "| Model | Provider | Single Tool | Parallel Tools | Weather | Calculator | Time |" >> "$report_file"
    echo "|-------|----------|-------------|----------------|---------|------------|------|" >> "$report_file"
    
    for i in "${!MODEL_KEYS[@]}"; do
        local model_key="${MODEL_KEYS[$i]}"
        local model_value="${MODEL_VALUES[$i]}"
        local provider=$(get_provider "$model_value")
        
        # Check if test files exist
        local weather_test="❌"
        local calc_test="❌"
        local time_test="❌"
        local parallel_test="❌"
        
        [[ -f "$OUTPUT_DIR/${model_key}_final_weather_$TIMESTAMP.json" ]] && weather_test="✅"
        [[ -f "$OUTPUT_DIR/${model_key}_final_calculator_$TIMESTAMP.json" ]] && calc_test="✅"
        [[ -f "$OUTPUT_DIR/${model_key}_final_time_$TIMESTAMP.json" ]] && time_test="✅"
        [[ -f "$OUTPUT_DIR/${model_key}_parallel_$TIMESTAMP.json" ]] && parallel_test="✅"
        
        local single_test="❌"
        [[ "$weather_test" == "✅" || "$calc_test" == "✅" || "$time_test" == "✅" ]] && single_test="✅"
        
        echo "| $model_key | $provider | $single_test | $parallel_test | $weather_test | $calc_test | $time_test |" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    echo "## Detailed Analysis" >> "$report_file"
    echo "" >> "$report_file"
    echo "See individual JSON files in the output directory for detailed request/response analysis." >> "$report_file"
    echo "" >> "$report_file"
    echo "## Files Generated" >> "$report_file"
    echo "" >> "$report_file"
    
    ls "$OUTPUT_DIR"/*_$TIMESTAMP.* | sort | while read file; do
        echo "- $(basename "$file")" >> "$report_file"
    done
    
    success "Generated analysis report: $report_file"
}

# Main test execution
main() {
    log "Starting GitHub Copilot Tool Call Analysis"
    log "Testing ${#MODEL_KEYS[@]} models across multiple providers"
    log "Output directory: $OUTPUT_DIR"
    
    # Test each model
    for i in "${!MODEL_KEYS[@]}"; do
        local model_key="${MODEL_KEYS[$i]}"
        local model="${MODEL_VALUES[$i]}"
        local provider=$(get_provider "$model")
        
        log "=========================================="
        log "Testing model: $model_key ($model)"
        log "Provider: $provider"
        log "=========================================="
        
        # Test different tool scenarios
        test_single_tool "$model_key" "$model" "$WEATHER_TOOL" "What's the weather in Paris?" "weather"
        sleep 2
        
        test_single_tool "$model_key" "$model" "$CALCULATOR_TOOL" "What is 42 * 123?" "calculator"
        sleep 2
        
        test_single_tool "$model_key" "$model" "$TIME_TOOL" "What time is it in New York?" "time"
        sleep 2
        
        # Test parallel tools (if supported)
        test_parallel_tools "$model_key" "$model"
        sleep 3
        
        log "Completed testing $model_key"
        log ""
    done
    
    # Generate comprehensive report
    generate_report
    
    success "Tool call analysis completed!"
    log "Check $OUTPUT_DIR for detailed results and analysis"
}

# Help function
show_help() {
    cat << EOF
GitHub Copilot Tool Call Testing Script

Usage: $0 [options]

Options:
    -h, --help              Show this help message
    -e, --endpoint URL      Set API endpoint (default: $ENDPOINT)
    -k, --api-key KEY       Set API key (default: from API_KEY env var)
    -o, --output DIR        Set output directory (default: $OUTPUT_DIR)
    -m, --model MODEL       Test specific model only
    -p, --provider PROVIDER Test specific provider only (openai|anthropic|google)
    --list-models           List available models and exit

Environment Variables:
    API_KEY                 API key for authentication
    ENDPOINT                API endpoint URL
    OUTPUT_DIR              Output directory for results

Examples:
    $0                                          # Test all models
    $0 -m openai_gpt4o                        # Test specific model
    $0 -p anthropic                           # Test all Anthropic models
    $0 -e http://localhost:4000/v1/chat/completions  # Custom endpoint

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -e|--endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            mkdir -p "$OUTPUT_DIR"
            shift 2
            ;;
        -m|--model)
            local found=false
            for i in "${!MODEL_KEYS[@]}"; do
                if [[ "${MODEL_KEYS[$i]}" == "$2" ]]; then
                    MODEL_KEYS=("$2")
                    MODEL_VALUES=("${MODEL_VALUES[$i]}")
                    found=true
                    break
                fi
            done
            if [[ "$found" == false ]]; then
                error "Unknown model: $2"
                exit 1
            fi
            shift 2
            ;;
        -p|--provider)
            local filtered_keys=()
            local filtered_values=()
            for i in "${!MODEL_KEYS[@]}"; do
                local provider=$(get_provider "${MODEL_VALUES[$i]}")
                if [[ "$provider" == "$2" ]]; then
                    filtered_keys+=("${MODEL_KEYS[$i]}")
                    filtered_values+=("${MODEL_VALUES[$i]}")
                fi
            done
            if [[ ${#filtered_keys[@]} -eq 0 ]]; then
                error "No models found for provider: $2"
                exit 1
            fi
            MODEL_KEYS=("${filtered_keys[@]}")
            MODEL_VALUES=("${filtered_values[@]}")
            shift 2
            ;;
        --list-models)
            echo "Available models:"
            for i in "${!MODEL_KEYS[@]}"; do
                model_key="${MODEL_KEYS[$i]}"
                model_value="${MODEL_VALUES[$i]}"
                provider=$(get_provider "$model_value")
                echo "  $model_key: $model_value ($provider)"
            done
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check dependencies
for cmd in curl jq bc; do
    if ! command -v "$cmd" &> /dev/null; then
        error "Required command not found: $cmd"
        exit 1
    fi
done

# Run main function
main