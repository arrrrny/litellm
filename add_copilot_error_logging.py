#!/usr/bin/env python3
"""
GitHub Copilot Error Logging Patch

This script adds error logging capabilities to the GitHub Copilot transformation module
in LiteLLM. It modifies the transformation.py file to log errors to the error_logs directory.

Usage:
  python add_copilot_error_logging.py

The script will:
1. Find the GitHub Copilot transformation.py file
2. Add error logging code to the _handle_error_response method
3. Create the log_copilot_error function if needed
"""

import os
import re
import sys
import shutil
import datetime
import json
from pathlib import Path

# Configuration
TRANSFORMATION_FILE_PATTERN = "**/github_copilot/chat/transformation.py"
BACKUP_DIR = "backups"
ERROR_LOGS_DIR = "/app/error_logs"  # Docker container path

def find_transformation_file():
    """Find the GitHub Copilot transformation.py file"""
    # Try common locations
    locations = [
        "litellm/llms/github_copilot/chat/transformation.py",
        "llms/github_copilot/chat/transformation.py",
        "**/github_copilot/chat/transformation.py",
    ]

    for location in locations:
        # Try direct match first
        if os.path.exists(location):
            return location

        # Try glob pattern
        if "*" in location:
            import glob
            matches = glob.glob(location, recursive=True)
            if matches:
                return matches[0]

    # Last resort - search recursively
    for root, _, files in os.walk("."):
        for file in files:
            if file == "transformation.py" and "github_copilot" in root and "chat" in root:
                return os.path.join(root, file)

    return None

def create_backup(file_path):
    """Create a backup of the file"""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = os.path.join(BACKUP_DIR, f"transformation_{timestamp}.py.bak")
    shutil.copy2(file_path, backup_path)
    print(f"Created backup: {backup_path}")
    return backup_path

def add_error_logger_function(content):
    """Add the error logger function if it doesn't exist"""
    if "def log_copilot_error" in content:
        return content  # Already exists

    # Create the log_copilot_error function
    logger_code = """
def log_copilot_error(error_info, model=None, status_code=None):
    """Log GitHub Copilot error to file"""
    try:
        # Ensure error logs directory exists
        log_dir = '/app/error_logs'
        os.makedirs(log_dir, exist_ok=True)

        # Get current timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

        # Extract model name if available
        if model is None and isinstance(error_info, dict):
            model = error_info.get('model', 'unknown')
        elif model is None:
            model = 'unknown'

        # Create filename
        filename = f"error_copilot_{model.replace('/', '_').replace('-', '_')}_{timestamp}.log"
        filepath = os.path.join(log_dir, filename)

        # Format the log content
        log_content = {
            "timestamp": datetime.now().isoformat(),
            "model": model,
            "status_code": status_code,
            "error_info": error_info,
        }

        # Generate curl command for reproduction
        curl_cmd = _generate_copilot_curl_command(model)
        log_content["curl_command"] = curl_cmd

        # Write to file with pretty formatting
        with open(filepath, 'w') as f:
            f.write("="*80 + "\\n")
            f.write(f"GITHUB COPILOT ERROR LOG - {datetime.now().isoformat()}\\n")
            f.write("="*80 + "\\n\\n")

            f.write(f"Provider: github_copilot\\n")
            f.write(f"Model: {model}\\n")
            f.write(f"Status Code: {status_code}\\n\\n")

            f.write("ERROR DETAILS:\\n")
            f.write("-"*40 + "\\n")
            if isinstance(error_info, dict):
                f.write(json.dumps(error_info, indent=2) + "\\n\\n")
            else:
                f.write(str(error_info) + "\\n\\n")

            f.write("REPRODUCTION CURL COMMAND:\\n")
            f.write("-"*40 + "\\n")
            f.write(curl_cmd + "\\n\\n")

            f.write("INSTRUCTIONS:\\n")
            f.write("-"*40 + "\\n")
            f.write("1. Set your token: export COPILOT_TOKEN=your_token_here\\n")
            f.write("2. Run the curl command above to reproduce the error\\n")
            f.write("3. Check the response for any specific error messages\\n\\n")

            f.write("JSON LOG:\\n")
            f.write("-"*40 + "\\n")
            f.write(json.dumps(log_content, indent=2) + "\\n")

        verbose_logger.info(f"GitHub Copilot error logged to: {filepath}")
        return filepath
    except Exception as e:
        verbose_logger.error(f"Failed to log GitHub Copilot error: {e}")
        return None

def _generate_copilot_curl_command(model):
    """Generate a curl command to reproduce GitHub Copilot API call"""
    # Default to a math calculation with tool choice for testing
    is_claude = "claude" in str(model).lower()

    # Basic curl command
    curl_parts = [
        "curl -X POST https://api.githubcopilot.com/chat/completions",
        "-H \\"Authorization: Bearer $COPILOT_TOKEN\\"",
        "-H \\"Content-Type: application/json\\"",
        "-H \\"Editor-Version: vscode/1.85.1\\"",
        "-H \\"Editor-Plugin-Version: copilot/1.155.0\\"",
        "-H \\"User-Agent: GithubCopilot/1.155.0\\"",
        "-H \\"Copilot-Integration-Id: vscode-chat\\""
    ]

    # Create request data
    if is_claude:
        request_data = {
            "model": str(model).replace("github_copilot/", ""),
            "messages": [{"role": "user", "content": "What is 42 * 15?"}],
            "tools": [{
                "type": "function",
                "function": {
                    "name": "calculate",
                    "description": "Perform mathematical calculation",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "expression": {
                                "type": "string",
                                "description": "Mathematical expression (e.g., 42 * 15)"
                            }
                        },
                        "required": ["expression"]
                    }
                }
            }],
            "tool_choice": {"type": "function", "function": {"name": "calculate"}},
            "max_tokens": 50,
            "stream": True
        }
    else:
        request_data = {
            "model": str(model).replace("github_copilot/", ""),
            "messages": [{"role": "user", "content": "What is 42 * 15?"}],
            "max_tokens": 50,
            "stream": True
        }

    # Format request data as JSON
    json_data = json.dumps(request_data, indent=2).replace('\\"', '\\\\"')
    curl_parts.append(f'-d "{json_data}"')

    return " \\\\\n  ".join(curl_parts)
"""

    # Add imports if needed
    imports_to_add = """
import os
from datetime import datetime
"""

    # Find the end of the imports section
    import_end = re.search(r'import.*\n\n', content, re.DOTALL)
    if import_end:
        pos = import_end.end()
        new_content = content[:pos] + imports_to_add + content[pos:] + logger_code
    else:
        # Fallback - add at the beginning of the file
        new_content = imports_to_add + content + logger_code

    return new_content

def patch_handle_error_response(content):
    """Add error logging to the _handle_error_response method"""
    # Find the _handle_error_response method
    handle_error_pattern = r'def _handle_error_response\(self, raw_response:.*?\):.*?raise GithubCopilotError\('
    match = re.search(handle_error_pattern, content, re.DOTALL)

    if not match:
        print("Could not find _handle_error_response method. Please manually add error logging.")
        return content

    # Find the end position where GithubCopilotError is raised
    raise_pos = content.find("raise GithubCopilotError(", match.start())
    if raise_pos == -1:
        print("Could not find where GithubCopilotError is raised. Please manually add error logging.")
        return content

    # Find the end of the line before raise
    line_end = content.rfind("\n", 0, raise_pos)

    # Add error logging code
    error_log_code = """
        # Log error to file
        try:
            error_log = {
                "status_code": raw_response.status_code,
                "response_headers": dict(raw_response.headers),
                "request_method": getattr(raw_response.request, "method", "UNKNOWN"),
                "request_url": str(getattr(raw_response.request, "url", "UNKNOWN")),
                "model": model,
                "raw_response_text": raw_response.text[:1000] if hasattr(raw_response, 'text') else "No text available",
                "parsed_error": err if err else None
            }
            log_copilot_error(error_log, model=model, status_code=raw_response.status_code)
        except Exception as log_error:
            verbose_logger.error(f"Failed to log GitHub Copilot error: {log_error}")

"""

    patched_content = content[:line_end+1] + error_log_code + content[line_end+1:]
    return patched_content

def main():
    """Main entry point"""
    print("GitHub Copilot Error Logging Patch")
    print("=================================\n")

    # Find the transformation file
    transformation_file = find_transformation_file()
    if not transformation_file:
        print("ERROR: Could not find GitHub Copilot transformation.py file.")
        print("Please specify the path manually by editing this script.")
        sys.exit(1)

    print(f"Found transformation file: {transformation_file}")

    # Create backup
    backup_path = create_backup(transformation_file)

    # Read the file
    with open(transformation_file, 'r') as f:
        content = f.read()

    # Add the error logger function
    content = add_error_logger_function(content)

    # Patch the _handle_error_response method
    content = patch_handle_error_response(content)

    # Write the updated file
    with open(transformation_file, 'w') as f:
        f.write(content)

    print("\nSuccess! Added error logging to GitHub Copilot transformation.py")
    print(f"Original file backed up to: {backup_path}")
    print("\nErrors will now be logged to: {ERROR_LOGS_DIR}")
    print("Make sure this directory exists and is writable in the Docker container.")

    # Create directory in current location as a fallback
    os.makedirs("error_logs", exist_ok=True)
    print("\nCreated local error_logs directory as fallback.")

    # Instructions for Docker setup
    print("\nTo ensure error logs volume is properly set up, run:")
    print("  docker volume create litellm_error_logs")
    print("  docker exec YOUR_CONTAINER_NAME mkdir -p /app/error_logs")
    print("  docker exec YOUR_CONTAINER_NAME chmod -R 777 /app/error_logs")

if __name__ == "__main__":
    main()
