#!/bin/bash
# init_error_logging.sh - Initialize error logging for GitHub Copilot
# This script runs inside the container at startup to ensure error logging is properly configured

set -e

# Define paths
ERROR_LOG_DIR="/app/error_logs"
LOG_COPILOT_ERROR_PATH="/app/log_copilot_error.py"
ERROR_LOG_INIT_FLAG="/app/error_logs/.initialized"

# Create error_logs directory with proper permissions
mkdir -p "$ERROR_LOG_DIR"
chmod -R 777 "$ERROR_LOG_DIR"

# Check if copilot error logger exists, if not create it
if [ ! -f "$LOG_COPILOT_ERROR_PATH" ]; then
  cat > "$LOG_COPILOT_ERROR_PATH" << 'EOF'
#!/usr/bin/env python3
"""
Direct GitHub Copilot Error Logger

This script logs a specific error for GitHub Copilot with Claude Sonnet 4
and writes it to a file in a way that will work regardless of permissions issues.
"""

import os
import json
import datetime
import sys
import traceback

def log_copilot_error(error_text=None, model="claude-sonnet-4", status_code=400):
    """
    Log the GitHub Copilot error to multiple possible locations
    to ensure at least one works regardless of permission issues.
    """
    # Use provided error text or the default one
    if error_text is None:
        error_text = """Bad Request. Received Model Group=github_copilot/claude-sonnet-4

Available Model Group Fallbacks=None LiteLLM Retried: 1 times, LiteLLM Max Retries: 2

Traceback (most recent call last):
  File "/usr/lib/python3.13/site-packages/litellm/llms/openai/openai.py", line 969, in async_streaming
    headers, response = await self.make_openai_chat_completion_request(
    )
  File "/usr/lib/python3.13/site-packages/openai/_base_client.py", line 1549, in request
    raise self._make_status_error_from_response(err.response) from None
openai.BadRequestError: Bad Request"""

    # Generate a curl command to reproduce the issue
    curl_command = f"""curl -H "Authorization: Bearer $COPILOT_TOKEN" \\
-H "Content-Type: application/json" \\
-H "Editor-Version: vscode/1.85.1" \\
-H "Editor-Plugin-Version: copilot/1.155.0" \\
-H "User-Agent: GithubCopilot/1.155.0" \\
-H "Copilot-Integration-Id: vscode-chat" \\
-d '{{"model": "{model}","messages":[{{"role":"user","content":"What is 42 * 15?"}}],"tools":[{{
  "type": "function",
  "function": {{
    "name": "calculate",
    "description": "Perform mathematical calculation",
    "parameters": {{
      "type": "object",
      "properties": {{
        "expression": {{
          "type": "string",
          "description": "Mathematical expression (e.g., 42 * 15)"
        }}
      }},
      "required": ["expression"]
    }}
  }}
}}],"tool_choice":{{"type":"function","function":{{"name":"calculate"}}}},"max_tokens":50,"stream":true}}' \\
"https://api.githubcopilot.com/chat/completions"
"""

    # Create error log content
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    error_log = {
        "timestamp": datetime.datetime.now().isoformat(),
        "model": f"github_copilot/{model}",
        "status_code": status_code,
        "error_text": error_text,
        "curl_command": curl_command
    }

    # Format log content
    log_content = f"""
==========================================================
GITHUB COPILOT ERROR LOG - {datetime.datetime.now().isoformat()}
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

JSON ERROR DETAILS:
{json.dumps(error_log, indent=2)}
"""

    # Try multiple locations to ensure at least one works
    log_locations = [
        "/app/error_logs",
        os.path.join(os.getcwd(), "error_logs"),
        "/tmp/copilot_error_logs",
        os.path.expanduser("~/error_logs"),
        ".",
    ]

    success = False
    for log_dir in log_locations:
        try:
            # Create directory if it doesn't exist
            os.makedirs(log_dir, exist_ok=True)

            # Create unique filename
            filename = f"error_github_copilot_{model.replace('-', '_')}_{timestamp}.log"
            filepath = os.path.join(log_dir, filename)

            # Write the log file
            with open(filepath, "w") as f:
                f.write(log_content)

            print(f"Successfully logged error to: {filepath}")
            success = True
            break
        except Exception as e:
            print(f"Failed to write to {log_dir}: {e}")
            continue

    if not success:
        print("ERROR: Failed to write error log to any location.")
        print("\nLog content that couldn't be written:")
        print(log_content)
        return None

    return filepath

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print("Usage: python log_copilot_error.py [ERROR_TEXT]")
        print("Logs a GitHub Copilot Claude Sonnet 4 error to multiple possible locations")
        sys.exit(0)

    # Get error text from command line if provided
    error_text = None
    if len(sys.argv) > 1:
        error_text = sys.argv[1]

    try:
        filepath = log_copilot_error(error_text)
        if filepath:
            print(f"Error logged successfully to {filepath}")
        else:
            sys.exit(1)
    except Exception as e:
        print(f"Error occurred: {e}")
        traceback.print_exc()
        sys.exit(1)
EOF

  chmod +x "$LOG_COPILOT_ERROR_PATH"
  echo "Created Copilot error logger script"
fi

# Create a simple test file to verify permissions
echo "Error logging initialized at $(date)" > "$ERROR_LOG_DIR/init_success.txt"

# Create an initialization flag file
touch "$ERROR_LOG_INIT_FLAG"

echo "GitHub Copilot error logging initialized successfully"
echo "Log directory: $ERROR_LOG_DIR"
echo "Error logger script: $LOG_COPILOT_ERROR_PATH"

# Create a simple hook for the LiteLLM code to use
cat > "/app/github_copilot_error_hook.py" << 'EOF'
"""
GitHub Copilot Error Hook

This module provides a simple function to log GitHub Copilot errors
that can be imported and used in the LiteLLM codebase.
"""

import os
import sys
import json
from datetime import datetime

def log_copilot_error(error_info):
    """Log GitHub Copilot error to file"""
    try:
        # Try to import and use the full logger if available
        sys.path.append('/app')
        try:
            from log_copilot_error import log_copilot_error as full_logger
            return full_logger(error_text=str(error_info))
        except ImportError:
            pass  # Fall back to simple logging

        # Simple fallback logging
        log_dir = '/app/error_logs'
        os.makedirs(log_dir, exist_ok=True)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        error_path = f'{log_dir}/copilot_error_{timestamp}.log'

        with open(error_path, 'w') as f:
            if isinstance(error_info, dict):
                f.write(json.dumps(error_info, indent=2))
            else:
                f.write(str(error_info))

        print(f'GitHub Copilot error logged to {error_path}')
        return error_path
    except Exception as e:
        print(f'Failed to log GitHub Copilot error: {e}')
        return None
EOF

# Note the successful initialization
echo "Error logging initialization completed at $(date)"
exit 0
