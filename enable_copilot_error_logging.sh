#!/bin/bash
# enable_copilot_error_logging.sh - Enable GitHub Copilot error logging in LiteLLM container
#
# This standalone script enables error logging for GitHub Copilot in an existing LiteLLM container.
# It doesn't require any changes to the main codebase or rebuilding the container.
#
# Usage: ./enable_copilot_error_logging.sh [container_name]
#   container_name: Optional Docker container name (default: tries to detect automatically)

set -e

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print banner
echo -e "${GREEN}"
echo "====================================="
echo " GitHub Copilot Error Logging Setup"
echo "====================================="
echo -e "${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
  exit 1
fi

# Find the container
if [ -n "$1" ]; then
  CONTAINER=$1
  echo -e "Using specified container: ${GREEN}$CONTAINER${NC}"
else
  # Try to find the container automatically
  for PATTERN in "litellm-litellm-1" "litellm_litellm_1" "litellm-1" "litellm_1"; do
    FOUND=$(docker ps | grep $PATTERN | grep -v grep | awk '{print $1}' | head -1)
    if [ -n "$FOUND" ]; then
      CONTAINER=$FOUND
      break
    fi
  done

  # If still not found, try broader search
  if [ -z "$CONTAINER" ]; then
    CONTAINER=$(docker ps | grep litellm | grep -v grep | awk '{print $1}' | head -1)
  fi
fi

if [ -z "$CONTAINER" ]; then
  echo -e "${RED}Error: No running litellm container found.${NC}"
  echo "Please specify the container name manually: ./enable_copilot_error_logging.sh CONTAINER_NAME"
  echo "Available containers:"
  docker ps
  exit 1
fi

echo -e "Using container: ${GREEN}$CONTAINER${NC}"

# Check if the error_logs volume exists
echo -e "\n${YELLOW}Checking for error_logs volume...${NC}"
if ! docker volume ls | grep -q "litellm_error_logs"; then
  echo -e "Creating error_logs volume..."
  docker volume create litellm_error_logs
  echo -e "${GREEN}Created volume: litellm_error_logs${NC}"
else
  echo -e "${GREEN}Found volume: litellm_error_logs${NC}"
fi

# Create/ensure error_logs directory with proper permissions
echo -e "\n${YELLOW}Setting up error_logs directory in container...${NC}"
docker exec $CONTAINER mkdir -p /app/error_logs
docker exec $CONTAINER chmod -R 777 /app/error_logs
echo -e "${GREEN}Created and set permissions for /app/error_logs${NC}"

# Create the error logger script inside the container
echo -e "\n${YELLOW}Creating error logger script in container...${NC}"
cat > /tmp/log_copilot_error.py << 'EOF'
#!/usr/bin/env python3
"""
Direct GitHub Copilot Error Logger

This script logs GitHub Copilot API errors to files
with detailed request/response information and reproducible curl commands.
"""

import json
import os
import sys
import traceback
from datetime import datetime
from typing import Dict, Any, Optional

class CopilotErrorLogger:
    """Utility for logging GitHub Copilot errors"""

    def __init__(self, log_dir: str = "/app/error_logs"):
        """Initialize with log directory"""
        # Try multiple locations in case of permission issues
        self.log_dirs = [
            log_dir,
            "/tmp/error_logs",
            os.path.join(os.getcwd(), "error_logs"),
            "."
        ]
        for dir_path in self.log_dirs:
            try:
                os.makedirs(dir_path, exist_ok=True)
            except:
                pass

    def log_error(self, error_text: str, model: str = "claude-sonnet-4", status_code: int = 400) -> Optional[str]:
        """Log an error to file with curl reproduction command"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # Generate a curl command for the error
        curl_command = self._generate_curl_command(model)

        # Format the log content
        log_content = f"""
==========================================================
GITHUB COPILOT ERROR LOG - {datetime.now().isoformat()}
==========================================================

PROVIDER: github_copilot
MODEL: {model}
STATUS_CODE: {status_code}

ERROR MESSAGE:
{error_text}

REPRODUCTION CURL COMMAND:
{curl_command}

INSTRUCTIONS:
1. Set your token: export COPILOT_TOKEN=your_token_here
2. Run the curl command above to reproduce the error
3. Check the response for any specific error messages
"""

        # Try to write to each directory until one works
        for log_dir in self.log_dirs:
            try:
                filename = f"error_github_copilot_{model.replace('-', '_')}_{timestamp}.log"
                filepath = os.path.join(log_dir, filename)

                with open(filepath, "w") as f:
                    f.write(log_content)

                print(f"Successfully logged error to: {filepath}")
                return filepath
            except Exception as e:
                print(f"Failed to write to {log_dir}: {e}")
                continue

        print("ERROR: Could not write to any log directory")
        return None

    def _generate_curl_command(self, model: str) -> str:
        """Generate a curl command to reproduce the error"""
        # Create appropriate request for this model
        is_claude = "claude" in model.lower()

        # Basic request structure
        request = {
            "model": model,
            "messages": [{"role": "user", "content": "What is 42 * 15?"}],
            "stream": True
        }

        # Add tools for Claude models
        if is_claude:
            request["tools"] = [{
                "type": "function",
                "function": {
                    "name": "calculate",
                    "description": "Perform mathematical calculation",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "expression": {
                                "type": "string",
                                "description": "Mathematical expression"
                            }
                        },
                        "required": ["expression"]
                    }
                }
            }]
            request["tool_choice"] = {"type": "function", "function": {"name": "calculate"}}

        # Format as JSON and escape for shell
        formatted_json = json.dumps(request, indent=2)
        escaped_json = formatted_json.replace('"', '\\"')

        # Build the curl command
        curl_parts = [
            "curl -X POST https://api.githubcopilot.com/chat/completions",
            "-H \"Authorization: Bearer $COPILOT_TOKEN\"",
            "-H \"Content-Type: application/json\"",
            "-H \"Editor-Version: vscode/1.85.1\"",
            "-H \"Editor-Plugin-Version: copilot/1.155.0\"",
            "-H \"User-Agent: GithubCopilot/1.155.0\"",
            "-H \"Copilot-Integration-Id: vscode-chat\"",
            f"-d \"{escaped_json}\""
        ]

        return " \\\n  ".join(curl_parts)

def log_error(error_text: str, model: str = "claude-sonnet-4", status_code: int = 400) -> Optional[str]:
    """Convenience function to log an error without creating the logger class"""
    logger = CopilotErrorLogger()
    return logger.log_error(error_text, model, status_code)

if __name__ == "__main__":
    # Check for help flag
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print("Usage: python log_copilot_error.py [ERROR_TEXT]")
        print("Logs a GitHub Copilot error to file with curl reproduction command")
        sys.exit(0)

    # Get error text from arguments or use default
    error_text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else """Bad Request. Received Model Group=github_copilot/claude-sonnet-4

Available Model Group Fallbacks=None LiteLLM Retried: 1 times, LiteLLM Max Retries: 2

Traceback (most recent call last):
  File "/usr/lib/python3.13/site-packages/litellm/llms/openai/openai.py", line 969, in async_streaming
    headers, response = await self.make_openai_chat_completion_request(
  File "/usr/lib/python3.13/site-packages/openai/_base_client.py", line 1549, in request
    raise self._make_status_error_from_response(err.response) from None
openai.BadRequestError: Bad Request"""

    try:
        log_path = log_error(error_text)
        if log_path:
            print(f"Error successfully logged to {log_path}")
        else:
            sys.exit(1)
    except Exception as e:
        print(f"Error occurred: {e}")
        traceback.print_exc()
        sys.exit(1)
EOF

docker cp /tmp/log_copilot_error.py $CONTAINER:/app/log_copilot_error.py
docker exec $CONTAINER chmod +x /app/log_copilot_error.py
rm /tmp/log_copilot_error.py

# Create a hook script for manual error logging
echo -e "\n${YELLOW}Creating error hook script in container...${NC}"
cat > /tmp/hook_copilot_errors.py << 'EOF'
"""
GitHub Copilot Error Hook

This module adds error logging capabilities for GitHub Copilot.
Import this at the beginning of your Python script to enable error logging.
"""

import os
import sys
import traceback

def hook_github_copilot_errors():
    """
    Set up error hooks to catch and log GitHub Copilot errors
    """
    orig_excepthook = sys.excepthook

    def copilot_error_handler(exc_type, exc_value, exc_traceback):
        """Custom exception handler for GitHub Copilot errors"""
        # Call original exception hook
        orig_excepthook(exc_type, exc_value, exc_traceback)

        # Check if this is a GitHub Copilot related error
        error_str = str(exc_value)
        traceback_str = "".join(traceback.format_tb(exc_traceback))

        if "github_copilot" in error_str.lower() or "github_copilot" in traceback_str.lower():
            try:
                # Try to import and use the error logger
                sys.path.insert(0, '/app')
                from log_copilot_error import log_error

                # Extract model name if possible
                model = "claude-sonnet-4"  # Default
                if "claude-sonnet-4" in error_str:
                    model = "claude-sonnet-4"
                elif "claude" in error_str:
                    model = "claude"
                elif "gpt-4" in error_str:
                    model = "gpt-4.1"

                # Log the error
                full_error = f"{error_str}\n\nTraceback:\n{traceback_str}"
                log_path = log_error(full_error, model)

                if log_path:
                    print(f"\nGitHub Copilot error logged to: {log_path}")
            except Exception as e:
                print(f"Failed to log GitHub Copilot error: {e}")

    # Set the custom exception handler
    sys.excepthook = copilot_error_handler
    print("GitHub Copilot error hooks enabled")

# Automatically hook errors when imported
hook_github_copilot_errors()
EOF

docker cp /tmp/hook_copilot_errors.py $CONTAINER:/app/hook_copilot_errors.py
rm /tmp/hook_copilot_errors.py

# Create a test file to verify permissions
echo -e "\n${YELLOW}Testing error logging permissions...${NC}"
docker exec $CONTAINER python -c "
import os
test_path = '/app/error_logs/test_write.txt'
try:
    with open(test_path, 'w') as f:
        f.write('Test write at ' + __import__('datetime').datetime.now().isoformat())
    print('Successfully wrote to ' + test_path)
except Exception as e:
    print('Failed to write: ' + str(e))
"

# Test the error logger
echo -e "\n${YELLOW}Testing error logger...${NC}"
docker exec $CONTAINER python /app/log_copilot_error.py "Test error from setup script"

# Create a simple guide in the error_logs directory
echo -e "\n${YELLOW}Creating usage guide...${NC}"
cat > /tmp/ERROR_LOGGING_README.txt << 'EOF'
=============================================
GITHUB COPILOT ERROR LOGGING GUIDE
=============================================

This directory contains logs of GitHub Copilot errors, including
detailed request/response information and reproducible curl commands.

HOW TO LOG ERRORS MANUALLY:

  python /app/log_copilot_error.py "Your error message here"

HOW TO ENABLE AUTO-LOGGING:

  Add this line to any Python file where GitHub Copilot is used:

  import sys; sys.path.insert(0, '/app'); import hook_copilot_errors

VIEW EXISTING ERROR LOGS:

  ls -la /app/error_logs/error_*.log

READ AN ERROR LOG:

  cat /app/error_logs/error_github_copilot_*.log

USE THE CURL COMMAND FROM A LOG:

1. Set your token:
   export COPILOT_TOKEN=your_token_here

2. Run the curl command from the log file to reproduce the error
EOF

docker cp /tmp/ERROR_LOGGING_README.txt $CONTAINER:/app/error_logs/README.txt
rm /tmp/ERROR_LOGGING_README.txt

echo -e "\n${GREEN}======== GitHub Copilot Error Logging Setup Complete ========${NC}"
echo -e "Error logs will be saved to: ${YELLOW}/app/error_logs${NC}"
echo -e "\nTo manually log an error:"
echo -e "${YELLOW}docker exec $CONTAINER python /app/log_copilot_error.py \"Your error message\"${NC}"
echo -e "\nTo view error logs:"
echo -e "${YELLOW}docker exec $CONTAINER ls -la /app/error_logs${NC}"
echo -e "\nTo read the latest error log:"
echo -e "${YELLOW}docker exec $CONTAINER bash -c \"cat \$(ls -t /app/error_logs/error_*.log | head -1)\"${NC}"
echo ""
