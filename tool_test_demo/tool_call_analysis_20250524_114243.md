# GitHub Copilot Tool Call Analysis Report

## Test Configuration
- Timestamp: 20250524_114243
- Endpoint: http://localhost:4000/v1/chat/completions
- Output Directory: tool_test_demo

## Models Tested

- **openai_gpt4o** (github_copilot/gpt-4o) - Provider: openai

## Test Results Summary

| Model | Provider | Single Tool | Parallel Tools | Weather | Calculator | Time |
|-------|----------|-------------|----------------|---------|------------|------|
| openai_gpt4o | openai | ✅ | ✅ | ✅ | ✅ | ✅ |

## Detailed Analysis

See individual JSON files in the output directory for detailed request/response analysis.

## Files Generated

- openai_gpt4o_final_calculator_20250524_114243.json
- openai_gpt4o_final_time_20250524_114243.json
- openai_gpt4o_final_weather_20250524_114243.json
- openai_gpt4o_initial_calculator_20250524_114243.json
- openai_gpt4o_initial_time_20250524_114243.json
- openai_gpt4o_initial_weather_20250524_114243.json
- openai_gpt4o_parallel_20250524_114243.json
- test_log_20250524_114243.txt
- tool_call_analysis_20250524_114243.md
