#!/bin/bash

# Your API key
API_KEY="sk-7E1EbuNM42L0-TojVfMuzw"

# Define the endpoint
ENDPOINT="http://localhost:4000/v1/chat/completions"

# Set the model - change this to test different models
MODEL="github_copilot/gpt-4o"
# MODEL="github_copilot/claude-3.7-sonnet"

# Define the tool
WEATHER_TOOL='{
  "type": "function",
  "function": {
    "name": "get_weather_forecast",
    "description": "Get the weather forecast for a given city using wttr.in",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {
          "type": "string",
          "description": "The city to get the weather forecast for"
        }
      },
      "required": ["city"]
    }
  }
}'

# Define headers
HEADERS=(
  "Authorization: Bearer $API_KEY"
  "Content-Type: application/json"
  "Editor-Version: vscode/1.85.1"
  "Editor-Plugin-Version: copilot/1.155.0"
  "User-Agent: GithubCopilot/1.155.0"
  "Copilot-Integration-Id: vscode-chat"
)

# Step 1: Send initial query with the weather tool
echo "Step 1: Sending initial query to $MODEL with weather tool..."
INITIAL_QUERY=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What's the weather forecast for Ankara?"}
  ],
  "tools": [$WEATHER_TOOL]
}
EOF
)

# Make the first API call
RESPONSE=$(curl -s "$ENDPOINT" \
  -H "${HEADERS[0]}" \
  -H "${HEADERS[1]}" \
  -H "${HEADERS[2]}" \
  -H "${HEADERS[3]}" \
  -H "${HEADERS[4]}" \
  -H "${HEADERS[5]}" \
  -d "$INITIAL_QUERY")

echo "Initial Response:"
echo $RESPONSE | jq .

# Step 2: Extract tool call information - handle different model formats
if [[ "$MODEL" == *"claude"* ]]; then
  # Claude format - tool calls are in the second choice
  echo "Detected Claude model, looking for tool calls in second choice..."
  TOOL_CALL_ID=$(echo $RESPONSE | jq -r '.choices[1].message.tool_calls[0].id')
  TOOL_NAME=$(echo $RESPONSE | jq -r '.choices[1].message.tool_calls[0].function.name')
  ARGUMENTS=$(echo $RESPONSE | jq -r '.choices[1].message.tool_calls[0].function.arguments')
  CONTENT_MESSAGE=$(echo $RESPONSE | jq -r '.choices[0].message.content')
else
  # OpenAI-compatible format - tool calls are in the first choice
  echo "Using standard format for tool calls..."
  TOOL_CALL_ID=$(echo $RESPONSE | jq -r '.choices[0].message.tool_calls[0].id')
  TOOL_NAME=$(echo $RESPONSE | jq -r '.choices[0].message.tool_calls[0].function.name')
  ARGUMENTS=$(echo $RESPONSE | jq -r '.choices[0].message.tool_calls[0].function.arguments')
  CONTENT_MESSAGE=""
fi

# Extract city from arguments
CITY=$(echo $ARGUMENTS | jq -r '.city')

echo "Tool Call ID: $TOOL_CALL_ID"
echo "Tool Name: $TOOL_NAME"
echo "City: $CITY"
[[ ! -z "$CONTENT_MESSAGE" ]] && echo "Content Message: $CONTENT_MESSAGE"

# Step 3: Execute the tool call (get actual weather)
echo -e "\nStep 3: Fetching actual weather data for $CITY..."
WEATHER_DATA=$(curl -s "https://wttr.in/$CITY?format=j1")
WEATHER_SUMMARY=$(echo $WEATHER_DATA | jq '{
  city: .nearest_area[0].areaName[0].value,
  country: .nearest_area[0].country[0].value,
  temperature: .current_condition[0].temp_C,
  humidity: .current_condition[0].humidity,
  description: .current_condition[0].weatherDesc[0].value
}')

echo "Weather data fetched:"
echo $WEATHER_SUMMARY | jq .

# Step 4: Send the follow-up response with tool results
echo -e "\nStep 4: Sending tool results back to the model..."

# Create the tool results as a proper escaped JSON string
WEATHER_JSON=$(echo $WEATHER_SUMMARY | jq -c | sed 's/"/\\"/g')

# For Claude models, create a special message format
if [[ "$MODEL" == *"claude"* ]]; then
  # Adapted format for Claude models
  FOLLOWUP_QUERY=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What's the weather forecast for Kayseri?"},
    {"role": "assistant", "content": "$CONTENT_MESSAGE"},
    {"role": "tool", "content": "$WEATHER_JSON", "name": "$TOOL_NAME", "tool_call_id": "$TOOL_CALL_ID"}
  ],
  "tools": [$WEATHER_TOOL]
}
EOF
)
else
  # Standard format for OpenAI-compatible models
  FOLLOWUP_QUERY=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What's the weather forecast for Kayseri?"},
    {"role": "assistant", "tool_calls": [{"id": "$TOOL_CALL_ID", "type": "function", "function": {"name": "$TOOL_NAME", "arguments": $ARGUMENTS}}]},
    {"role": "tool", "tool_call_id": "$TOOL_CALL_ID", "content": $(echo $WEATHER_SUMMARY | jq -c .)}
  ],
  "tools": [$WEATHER_TOOL]
}
EOF
)
fi

echo "Sending follow-up query:"
echo "$FOLLOWUP_QUERY" | jq .

# Make the second API call
FINAL_RESPONSE=$(curl -s "$ENDPOINT" \
  -H "${HEADERS[0]}" \
  -H "${HEADERS[1]}" \
  -H "${HEADERS[2]}" \
  -H "${HEADERS[3]}" \
  -H "${HEADERS[4]}" \
  -H "${HEADERS[5]}" \
  -d "$FOLLOWUP_QUERY")

echo -e "\nFinal response from model:"
echo $FINAL_RESPONSE | jq .
echo -e "\nFormatted response:"
echo $FINAL_RESPONSE | jq -r '.choices[0].message.content'
