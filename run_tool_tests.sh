#!/usr/bin/env bash

# Comprehensive GitHub Copilot Tool Call Test Runner
# This script runs tool call tests and generates analysis reports

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-./tool_test_results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
API_KEY="${API_KEY:-sk-M1kLb3qpCSq52YEx9QQlrA}"
ENDPOINT="${ENDPOINT:-http://localhost:4000/v1/chat/completions}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local missing=()

    for cmd in curl jq bc python3; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing[*]}"
        echo "Please install the missing commands and try again."
        exit 1
    fi

    # Check Python modules
    if ! python3 -c "import json, glob, pathlib" 2>/dev/null; then
        error "Required Python modules not available"
        exit 1
    fi
}

# Test API connectivity
test_api_connectivity() {
    log "Testing API connectivity..."

    local test_payload='{"model":"github_copilot/gpt-4o","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'

    local response=$(curl -s -w "%{http_code}" -o /tmp/api_test_$$.json \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -H "Editor-Version: vscode/1.85.1" \
        -H "Editor-Plugin-Version: copilot/1.155.0" \
        -H "User-Agent: GithubCopilot/1.155.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -d "$test_payload" \
        "$ENDPOINT")

    local http_code="${response: -3}"

    if [[ "$http_code" == "200" ]]; then
        success "API connectivity test passed"
        rm -f /tmp/api_test_$$.json
        return 0
    else
        error "API connectivity test failed (HTTP $http_code)"
        if [ -f /tmp/api_test_$$.json ]; then
            log "Response:"
            cat /tmp/api_test_$$.json
            rm -f /tmp/api_test_$$.json
        fi
        return 1
    fi
}

# Run tool call tests
run_tool_tests() {
    log "Starting tool call tests..."

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Run the main test script
    export API_KEY="$API_KEY"
    export ENDPOINT="$ENDPOINT"
    export OUTPUT_DIR="$OUTPUT_DIR"
    export TIMESTAMP="$TIMESTAMP"

    if [ -f "$SCRIPT_DIR/test_copilot.sh" ]; then
        log "Running comprehensive tool call tests..."
        if "$SCRIPT_DIR/test_copilot.sh"; then
            success "Tool call tests completed successfully"
            return 0
        else
            error "Tool call tests failed"
            return 1
        fi
    else
        error "Test script not found: $SCRIPT_DIR/test_copilot.sh"
        return 1
    fi
}

# Run analysis
run_analysis() {
    log "Running tool call response analysis..."

    if [ -f "$SCRIPT_DIR/analyze_tool_responses.py" ]; then
        local analysis_prefix="$OUTPUT_DIR/analysis_$TIMESTAMP"

        if python3 "$SCRIPT_DIR/analyze_tool_responses.py" "$OUTPUT_DIR" -o "$analysis_prefix"; then
            success "Analysis completed successfully"

            # Show summary
            if [ -f "${analysis_prefix}_report.md" ]; then
                log "Analysis report generated: ${analysis_prefix}_report.md"
            fi

            if [ -f "${analysis_prefix}_recommendations.py" ]; then
                log "Code recommendations generated: ${analysis_prefix}_recommendations.py"
            fi

            return 0
        else
            error "Analysis failed"
            return 1
        fi
    else
        error "Analysis script not found: $SCRIPT_DIR/analyze_tool_responses.py"
        return 1
    fi
}

# Generate summary
generate_summary() {
    local summary_file="$OUTPUT_DIR/test_summary_$TIMESTAMP.txt"

    cat > "$summary_file" << EOF
GitHub Copilot Tool Call Test Summary
=====================================

Test Run: $TIMESTAMP
Output Directory: $OUTPUT_DIR
API Endpoint: $ENDPOINT

Files Generated:
$(ls -la "$OUTPUT_DIR"/*_$TIMESTAMP.* 2>/dev/null | awk '{print "  " $9 " (" $5 " bytes)"}' || echo "  No files found")

Test Results:
EOF

    # Count successful tests
    local json_files=$(ls "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l)
    local error_files=$(grep -l "error" "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l)
    local success_files=$((json_files - error_files))

    echo "  Total response files: $json_files" >> "$summary_file"
    echo "  Successful responses: $success_files" >> "$summary_file"
    echo "  Error responses: $error_files" >> "$summary_file"

    # List models tested
    echo "" >> "$summary_file"
    echo "Models Tested:" >> "$summary_file"
    local models=$(ls "$OUTPUT_DIR"/*.json 2>/dev/null | xargs -I {} basename {} | cut -d'_' -f1 | sort -u)
    echo "$models" | while read model; do
        if [ -n "$model" ]; then
            echo "  - $model" >> "$summary_file"
        fi
    done

    echo "" >> "$summary_file"
    echo "Next Steps:" >> "$summary_file"
    echo "  1. Review analysis report for provider-specific patterns" >> "$summary_file"
    echo "  2. Check code recommendations for transformation improvements" >> "$summary_file"
    echo "  3. Update transformation.py based on findings" >> "$summary_file"
    echo "  4. Run validation tests with improved transformations" >> "$summary_file"

    log "Test summary generated: $summary_file"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f /tmp/api_test_$$.json
}

# Show help
show_help() {
    cat << EOF
GitHub Copilot Tool Call Test Runner

Usage: $0 [options]

Options:
    -h, --help              Show this help message
    -e, --endpoint URL      Set API endpoint (default: $ENDPOINT)
    -k, --api-key KEY       Set API key (default: from API_KEY env var)
    -o, --output DIR        Set output directory (default: $OUTPUT_DIR)
    -t, --test-only         Run tests only (skip analysis)
    -a, --analyze-only      Run analysis only (skip tests)
    -s, --skip-connectivity Skip API connectivity test
    --clean                 Clean output directory before running

Environment Variables:
    API_KEY                 API key for authentication
    ENDPOINT                API endpoint URL
    OUTPUT_DIR              Output directory for results

Examples:
    $0                                          # Full test run
    $0 -t                                      # Tests only
    $0 -a                                      # Analysis only
    $0 -e http://localhost:4000/v1/chat/completions  # Custom endpoint

EOF
}

# Parse command line arguments
SKIP_CONNECTIVITY=false
TEST_ONLY=false
ANALYZE_ONLY=false
CLEAN_OUTPUT=false

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
            shift 2
            ;;
        -t|--test-only)
            TEST_ONLY=true
            shift
            ;;
        -a|--analyze-only)
            ANALYZE_ONLY=true
            shift
            ;;
        -s|--skip-connectivity)
            SKIP_CONNECTIVITY=true
            shift
            ;;
        --clean)
            CLEAN_OUTPUT=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    log "GitHub Copilot Tool Call Test Runner"
    log "Output directory: $OUTPUT_DIR"
    log "API endpoint: $ENDPOINT"

    # Check dependencies
    check_dependencies

    # Clean output directory if requested
    if [ "$CLEAN_OUTPUT" = true ]; then
        log "Cleaning output directory..."
        rm -rf "$OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Test API connectivity unless skipped or analysis-only
    if [ "$SKIP_CONNECTIVITY" = false ] && [ "$ANALYZE_ONLY" = false ]; then
        if ! test_api_connectivity; then
            error "API connectivity test failed. Check your API key and endpoint."
            exit 1
        fi
    fi

    # Run tests unless analysis-only
    if [ "$ANALYZE_ONLY" = false ]; then
        if ! run_tool_tests; then
            error "Tool tests failed"
            exit 1
        fi
    fi

    # Run analysis unless test-only
    if [ "$TEST_ONLY" = false ]; then
        if ! run_analysis; then
            warning "Analysis failed, but tests completed successfully"
        fi
    fi

    # Generate summary
    generate_summary

    success "Test run completed successfully!"
    log "Check $OUTPUT_DIR for detailed results"

    # Show quick results
    if [ -f "$OUTPUT_DIR/analysis_${TIMESTAMP}_report.md" ]; then
        log ""
        log "Quick Results Preview:"
        head -20 "$OUTPUT_DIR/analysis_${TIMESTAMP}_report.md" | tail -10
        log ""
        log "Full report: $OUTPUT_DIR/analysis_${TIMESTAMP}_report.md"
    fi
}

# Run main function
main "$@"
