# GitHub Copilot Tool Call Analysis Report

## Test Configuration
- Timestamp: 20250524_114327
- Endpoint: http://localhost:4000/v1/chat/completions
- Output Directory: tool_test_demo

## Models Tested

- **anthropic_claude35** (github_copilot/claude-3.5-sonnet) - Provider: anthropic

## Test Results Summary

| Model | Provider | Single Tool | Parallel Tools | Weather | Calculator | Time |
|-------|----------|-------------|----------------|---------|------------|------|
| anthropic_claude35 | anthropic | ❌ | ✅ | ❌ | ❌ | ❌ |

## Detailed Analysis

See individual JSON files in the output directory for detailed request/response analysis.

## Files Generated

- anthropic_claude35_initial_calculator_20250524_114327.json
- anthropic_claude35_initial_time_20250524_114327.json
- anthropic_claude35_initial_weather_20250524_114327.json
- anthropic_claude35_parallel_20250524_114327.json
- test_log_20250524_114327.txt
- tool_call_analysis_20250524_114327.md
