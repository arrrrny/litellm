# GitHub Copilot Tool Call Analysis Report

## Test Configuration
- Timestamp: 20250524_114414
- Endpoint: http://localhost:4000/v1/chat/completions
- Output Directory: tool_test_demo

## Models Tested

- **google_gemini25** (github_copilot/gemini-2.5-pro) - Provider: google

## Test Results Summary

| Model | Provider | Single Tool | Parallel Tools | Weather | Calculator | Time |
|-------|----------|-------------|----------------|---------|------------|------|
| google_gemini25 | google | ✅ | ✅ | ✅ | ✅ | ✅ |

## Detailed Analysis

See individual JSON files in the output directory for detailed request/response analysis.

## Files Generated

- google_gemini25_final_calculator_20250524_114414.json
- google_gemini25_final_time_20250524_114414.json
- google_gemini25_final_weather_20250524_114414.json
- google_gemini25_initial_calculator_20250524_114414.json
- google_gemini25_initial_time_20250524_114414.json
- google_gemini25_initial_weather_20250524_114414.json
- google_gemini25_parallel_20250524_114414.json
- test_log_20250524_114414.txt
- tool_call_analysis_20250524_114414.md
