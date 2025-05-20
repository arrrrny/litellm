#!/usr/bin/env bash

# CONFIGURATION (export these in your shell or .env beforehand)
: "${API_KEY:="sk-7E1EbuNM42L0-TojVfMuzw"}"
: "${ENDPOINT:=http://localhost:4000/v1/chat/completions}"
: "${MODEL:=github_copilot/claude-3.5-sonnet}"

# Common headers
HEADERS=(
  "-H" "Authorization: Bearer ${API_KEY}"
  "-H" "Content-Type: application/json"
  "-H" "Editor-Version: vscode/1.85.1"
  "-H" "Editor-Plugin-Version: copilot/1.155.0"
  "-H" "User-Agent: GithubCopilot/1.155.0"
  "-H" "Copilot-Integration-Id: vscode-chat"
)

# The tool schema (only needs to be defined once)
read -r -d '' WEATHER_TOOL << 'EOF'
{
  "type":"function",
  "function":{
    "name":"get_weather_forecast",
    "description":"Get the weather for a city via wttr.in",
    "parameters":{
      "type":"object",
      "properties":{
        "city":{"type":"string"}
      },
      "required":["city"]
    }
  }
}
EOF

# A helper to do one full tool-call roundtrip
run_weather_test() {
  local CITY_REQUEST="$1"
  echo "→ Querying weather for: $CITY_REQUEST"

  # 1) initial ask
  local PAYLOAD
  PAYLOAD=$(jq -cn \
    --arg m "$MODEL" \
    --arg city "$CITY_REQUEST" \
    --argjson tool "$(echo "$WEATHER_TOOL")" \
    '{
      model: $m,
      messages: [
        {role:"system",content:"You are a helpful assistant."},
        {role:"user",content:"What is the weather in \($city)?"}
      ],
      tools: [$tool]
    }'
  )
  RESPONSE=$(curl -s "${HEADERS[@]}" -d "$PAYLOAD" "$ENDPOINT")
  echo "Initial response:"
  echo "$RESPONSE" | jq .

  # 2) extract the tool_call block
  #    supports either .choices[0] or .choices[1]
  TOOL_PATH=$(jq -r '
    .choices
    | to_entries
    | map(select(.value.message.tool_calls != null))
    | .[0].key
  ' <<<"$RESPONSE")

  TOOL_CALL=$(jq -r \
    --arg path "$TOOL_PATH" \
    '.choices[$path|tonumber].message.tool_calls[0]' \
    <<<"$RESPONSE"
  )
  # Parse the arguments field (which is a stringified JSON)
  CITY=$(jq -r '.function.arguments' <<<"$TOOL_CALL" | jq -r | jq -r '.city')
  CALL_ID=$(jq -r '.id' <<<"$TOOL_CALL")
  FUNC_NAME=$(jq -r '.function.name' <<<"$TOOL_CALL")

  echo "→ Extracted call: id=$CALL_ID, function=$FUNC_NAME, city=$CITY"

  # 3) execute the tool (actual weather)
  WEATHER_JSON=$(curl -s "https://wttr.in/${CITY}?format=j1" | jq '{city:.nearest_area[0].areaName[0].value, country:.nearest_area[0].country[0].value, temp:.current_condition[0].temp_C, desc:.current_condition[0].weatherDesc[0].value}')
  WEATHER_SUMMARY=$(echo "$WEATHER_JSON" | jq -r '"The weather in \(.city), \(.country) is \(.temp)°C and \(.desc)."')

  # 4) follow-up message embedding the tool result
  PAYLOAD=$(jq -cn \
    --arg m "$MODEL" \
    --argjson tool "$(echo "$WEATHER_TOOL")" \
    --arg id "$CALL_ID" \
    --arg city "$CITY" \
    --arg weather "$WEATHER_SUMMARY" \
    '{
      model: $m,
      messages: [
        {"role":"system","content":"You are a helpful assistant."},
        {"role":"user","content":"What is the weather in \($city)?"},
        {"role":"assistant","tool_calls":[{"id":$id,"type":"function","function":{"name":"get_weather_forecast","arguments":"{\"city\":\"\($city)\"}"}}],"content":""},
        {"role":"tool","tool_call_id":$id,"content":$weather}
      ],
      tools:[ $tool ]
    }'
  )
  echo "Follow-up payload:"
  echo "$PAYLOAD" | jq .
  FINAL=$(curl -s "${HEADERS[@]}" -d "$PAYLOAD" "$ENDPOINT")
  echo "Final response:"
  echo "$FINAL" | jq .
  echo
}

# Example runs
run_weather_test "Ankara"
run_weather_test "Istanbul"
