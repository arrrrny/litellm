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
  File "/usr/lib/python3.13/site-packages/litellm/llms/openai/openai.py", line 436, in make_openai_chat_completion_request
    raise e
  File "/usr/lib/python3.13/site-packages/openai/_base_client.py", line 1742, in post
    return await self.request(cast_to, opts, stream=stream, stream_cls=stream_cls)
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
