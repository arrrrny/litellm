#!/bin/bash

# GitHub Client ID for Copilot
CLIENT_ID="Iv1.b507a08c87ecfe98"

# Request a device code
response=$(curl -s https://github.com/login/device/code \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"scope\":\"read:user\"}")

echo "Device Code Response:"
echo "$response"

# Extract the necessary fields from the response
device_code=$(echo "$response" | grep -o '"device_code":"[^"]*"' | cut -d'"' -f4)
user_code=$(echo "$response" | grep -o '"user_code":"[^"]*"' | cut -d'"' -f4)
verification_uri=$(echo "$response" | grep -o '"verification_uri":"[^"]*"' | cut -d'"' -f4)

