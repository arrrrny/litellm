# GitHub Copilot Tool Call Testing Guide

This guide helps you test and analyze tool call behavior across different GitHub Copilot providers (OpenAI, Anthropic, Google) to improve transformation robustness.

## Quick Start

### Prerequisites

- LiteLLM proxy running on `http://localhost:4000`
- Valid GitHub Copilot authentication
- Required tools: `curl`, `jq`, `bc`, `python3`

### Run Complete Test Suite

```bash
# Run all tests and analysis
./run_tool_tests.sh

# Test specific provider only
./test_copilot.sh -p anthropic

# Test single model
./test_copilot.sh -m openai_gpt4o

# Custom endpoint
./run_tool_tests.sh -e http://your-endpoint:4000/v1/chat/completions
```

## Test Scripts Overview

### 1. `test_copilot.sh` - Main Testing Script

Comprehensive tool call testing across all GitHub Copilot models:

**Features:**
- Tests 10+ models across OpenAI, Anthropic, and Google providers
- Multiple tool scenarios (weather, calculator, time)
- Single and parallel tool call testing
- Detailed response analysis and logging
- JSON output for further analysis

**Usage:**
```bash
./test_copilot.sh [options]

Options:
  -h, --help              Show help
  -e, --endpoint URL      API endpoint
  -k, --api-key KEY       API key
  -o, --output DIR        Output directory
  -m, --model MODEL       Test specific model
  -p, --provider PROVIDER Test specific provider
  --list-models           List available models
```

**Example outputs:**
- `openai_gpt4o_initial_weather_20250524_110500.json`
- `anthropic_claude35_final_calculator_20250524_110500.json`
- `google_gemini25_parallel_20250524_110500.json`

### 2. `analyze_tool_responses.py` - Response Analysis

Python script to analyze tool call patterns and generate recommendations:

**Features:**
- Analyzes response structures by provider
- Identifies tool call placement patterns
- Detects argument format variations
- Generates transformation recommendations
- Creates improvement code suggestions

**Usage:**
```bash
python3 analyze_tool_responses.py ./tool_test_results -o analysis

# Generate JSON output too
python3 analyze_tool_responses.py ./tool_test_results -o analysis --json
```

### 3. `run_tool_tests.sh` - Complete Test Runner

Orchestrates the entire testing and analysis process:

**Features:**
- API connectivity testing
- Dependency checking
- Automated test execution
- Response analysis
- Summary report generation

**Usage:**
```bash
./run_tool_tests.sh [options]

Options:
  -t, --test-only         Run tests only
  -a, --analyze-only      Analyze existing results
  -s, --skip-connectivity Skip API test
  --clean                 Clean output directory
```

## Test Scenarios

### 1. Single Tool Call Tests

Tests individual tool usage with different providers:

**Weather Tool:**
- Function: `get_weather_forecast`
- Input: City name
- Tests: "What's the weather in Paris?"

**Calculator Tool:**
- Function: `calculate`
- Input: Mathematical expression
- Tests: "What is 42 * 123?"

**Time Tool:**
- Function: `get_current_time`
- Input: Timezone
- Tests: "What time is it in New York?"

### 2. Parallel Tool Call Tests

Tests multiple tool usage in single request:
- Query: "What's the weather in Tokyo, what's 15 * 23, and what time is it in UTC?"
- Verifies provider support for parallel tool calls

### 3. Tool Call Flow Tests

Complete request-response cycles:
1. Initial request with tools
2. Model responds with tool calls
3. Tool execution
4. Follow-up request with results
5. Final model response

## Understanding Results

### Response File Structure

Files are named: `{model}_{step}_{test}_{timestamp}.json`

**Examples:**
- `openai_gpt4o_initial_weather_20250524_110500.json` - Initial request
- `openai_gpt4o_final_weather_20250524_110500.json` - Final response
- `anthropic_claude35_parallel_20250524_110500.json` - Parallel test

### Key Analysis Points

**Tool Call Placement:**
- OpenAI: Usually in `choices[0]`
- Anthropic: May appear in `choices[1]`
- Google: Varies by model

**Argument Formats:**
- String format: `"arguments": "{\"city\":\"Paris\"}"`
- Object format: `"arguments": {"city":"Paris"}`

**Response Structures:**
```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          {
            "id": "call_123",
            "type": "function",
            "function": {
              "name": "get_weather_forecast",
              "arguments": "{\"city\":\"Paris\"}"
            }
          }
        ]
      },
      "finish_reason": "tool_calls"
    }
  ]
}
```

## Provider-Specific Patterns

### OpenAI Models
- **Models**: gpt-4o, gpt-4.1, o1, o3-mini, o4-mini
- **Tool Calls**: Usually in first choice
- **Arguments**: String format (JSON-encoded)
- **Parallel Support**: Most models support parallel calls

### Anthropic Models
- **Models**: claude-3.5-sonnet, claude-3.7-sonnet, claude-sonnet-4
- **Tool Calls**: May appear in second choice
- **Arguments**: String format
- **Parallel Support**: Varies by model

### Google Models
- **Models**: gemini-2.0-flash-001, gemini-2.5-pro
- **Tool Calls**: Placement varies
- **Arguments**: Mixed formats
- **Parallel Support**: Limited

## Improving Transformations

### Common Issues Found

1. **Tool Call Placement Inconsistency**
   - Some providers put tool calls in `choices[1]` instead of `choices[0]`
   - Solution: Check all choices for tool calls

2. **Argument Format Variations**
   - String vs object format for arguments
   - Solution: Handle both formats in parsing

3. **Multiple Choice Handling**
   - Tool calls spread across multiple choices
   - Solution: Consolidate tool calls from all choices

### Recommended Improvements

Based on test results, update `transformation.py`:

```python
def extract_tool_calls_robust(response):
    """Extract tool calls from any choice, handling provider variations."""
    all_tool_calls = []
    
    for choice in response.get("choices", []):
        message = choice.get("message", {})
        tool_calls = message.get("tool_calls", [])
        
        for tool_call in tool_calls:
            # Normalize argument format
            if "function" in tool_call:
                args = tool_call["function"].get("arguments", "{}")
                if isinstance(args, str):
                    try:
                        tool_call["function"]["arguments"] = json.loads(args)
                    except json.JSONDecodeError:
                        pass  # Keep as string if invalid JSON
            
            all_tool_calls.append(tool_call)
    
    return all_tool_calls
```

## Troubleshooting

### Common Issues

**API Connectivity:**
```bash
# Test basic connectivity
curl -H "Authorization: Bearer $API_KEY" \
     -H "Content-Type: application/json" \
     "$ENDPOINT/models"
```

**Missing Dependencies:**
```bash
# Install required tools
apt-get update && apt-get install -y curl jq bc
# or
brew install curl jq bc
```

**Permission Issues:**
```bash
chmod +x *.sh
```

### Debug Mode

Enable verbose output:
```bash
# Set debug environment
export DEBUG=1

# Run with verbose logging
./test_copilot.sh --verbose
```

### Analyzing Specific Issues

**Check specific model responses:**
```bash
# Find all files for a model
ls tool_test_results/openai_gpt4o_*

# Check for errors
jq '.error' tool_test_results/*.json | grep -v null
```

**Validate tool call structures:**
```bash
# Check tool call presence
jq '.choices[].message.tool_calls' tool_test_results/*initial*.json

# Check argument formats
jq '.choices[].message.tool_calls[]?.function.arguments' tool_test_results/*.json | head -20
```

## Validation Testing

After implementing improvements, validate with:

1. **Regression Tests**: Re-run full test suite
2. **Edge Case Testing**: Test malformed responses
3. **Performance Testing**: Measure transformation speed
4. **Integration Testing**: Test with real workloads

### Validation Script Example

```bash
#!/bin/bash
# Validate improvements

echo "Running validation tests..."

# Test all providers
for provider in openai anthropic google; do
    echo "Testing $provider models..."
    ./test_copilot.sh -p $provider -o validation_results
done

# Compare with baseline
python3 compare_results.py baseline_results validation_results
```

## Best Practices

1. **Test Regularly**: Run tests when models are updated
2. **Document Patterns**: Keep track of provider-specific behaviors
3. **Validate Changes**: Test transformations after modifications
4. **Monitor Performance**: Check for regression in response times
5. **Handle Errors**: Gracefully handle malformed responses

## Next Steps

1. Run the complete test suite
2. Analyze the generated reports
3. Implement recommended improvements
4. Validate with regression tests
5. Update documentation with findings