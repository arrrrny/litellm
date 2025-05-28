#!/usr/bin/env python
"""
GitHub Copilot Error Logger

This script provides a direct way to log GitHub Copilot API errors to files
with detailed request/response information and reproducible curl commands.

Usage:
    - Run this script directly to monitor logs in real-time
    - Import the CopilotErrorMonitor class to use in other scripts
"""

import json
import os
import logging
import time
import re
from datetime import datetime
from pathlib import Path
import traceback
import signal
import sys
from typing import Dict, List, Any, Optional, Union

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("CopilotErrorMonitor")

class CopilotErrorMonitor:
    """Monitor and log GitHub Copilot API errors"""

    def __init__(self,
                 log_dir: str = "/app/error_logs",
                 log_file_pattern: str = "*.log",
                 container_name: str = "litellm"):
        """
        Initialize the error monitor

        Args:
            log_dir: Directory where error logs are stored
            log_file_pattern: Pattern to match log files
            container_name: Docker container name for litellm
        """
        self.log_dir = log_dir
        self.fallback_log_dir = self._get_fallback_log_dir()
        self.log_file_pattern = log_file_pattern
        self.container_name = container_name
        self.last_check_time = 0

        # Create error logs directory if it doesn't exist
        self._ensure_log_directory()

        self._setup_signal_handlers()

    def _get_fallback_log_dir(self) -> str:
        """Get a fallback log directory if main directory is not writable"""
        # Try current directory
        if os.access(".", os.W_OK):
            return os.path.join(os.getcwd(), "error_logs")
        # Try home directory
        home_dir = os.path.expanduser("~")
        if os.access(home_dir, os.W_OK):
            return os.path.join(home_dir, "error_logs")
        # Try /tmp directory
        if os.access("/tmp", os.W_OK):
            return os.path.join("/tmp", "copilot_error_logs")
        return "."  # Last resort

    def _ensure_log_directory(self):
        """Create log directory with proper error handling and fallback"""
        try:
            # Try to create main log directory
            os.makedirs(self.log_dir, exist_ok=True)

            # Test write permissions by creating a test file
            test_file_path = os.path.join(self.log_dir, ".write_test")
            try:
                with open(test_file_path, "w") as f:
                    f.write("test")
                os.remove(test_file_path)
                logger.info(f"Using log directory: {self.log_dir}")
                return
            except (IOError, PermissionError) as e:
                logger.warning(f"Cannot write to {self.log_dir}: {e}")

            # Fall back to alternate directory
            logger.warning(f"Falling back to alternative log directory: {self.fallback_log_dir}")
            os.makedirs(self.fallback_log_dir, exist_ok=True)
            self.log_dir = self.fallback_log_dir

        except Exception as e:
            logger.error(f"Error creating log directories: {e}")
            logger.info(f"Will attempt to use current directory for logs")
            self.log_dir = "."

    def _setup_signal_handlers(self):
        """Setup handlers for graceful termination"""
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, self._handle_exit)

    def _handle_exit(self, signum, frame):
        """Handle exit signals"""
        logger.info(f"Received signal {signum}, shutting down")
        sys.exit(0)

    def extract_error_details(self, log_content: str) -> Dict[str, Any]:
        """
        Extract error details from log content using regex

        Args:
            log_content: Content of the log file

        Returns:
            Dictionary with extracted error details
        """
        error_details = {
            "provider": "unknown",
            "model": "unknown",
            "error_message": "",
            "status_code": 0,
            "traceback": "",
            "request_data": {},
            "response_data": {}
        }

        # Extract model information
        model_match = re.search(r"Model[=:]?\s*([^\s]+)", log_content)
        if model_match:
            error_details["model"] = model_match.group(1)

        # Extract provider information
        if "github_copilot" in log_content.lower():
            error_details["provider"] = "github_copilot"

        # Extract status code
        status_code_match = re.search(r"status[_\s]code[=:]?\s*(\d+)", log_content, re.IGNORECASE)
        if status_code_match:
            error_details["status_code"] = int(status_code_match.group(1))

        # Extract error message
        error_msg_match = re.search(r"(?:error|exception)[=:]?\s*([^\n]+)", log_content, re.IGNORECASE)
        if error_msg_match:
            error_details["error_message"] = error_msg_match.group(1).strip()

        # Extract traceback if available
        traceback_match = re.search(r"Traceback \(most recent call last\):(.*?)(?:\n\n|\Z)",
                               log_content, re.DOTALL)
        if traceback_match:
            error_details["traceback"] = traceback_match.group(1).strip()

        return error_details

    def generate_curl_command(self, error_details: Dict[str, Any]) -> str:
        """
        Generate a curl command to reproduce the error

        Args:
            error_details: Dictionary with error details

        Returns:
            Curl command string
        """
        model = error_details.get("model", "github_copilot/gpt-4.1").replace("github_copilot/", "")

        # Create a basic curl command template
        curl_cmd = [
            "curl -X POST http://localhost:4000/chat/completions",
            "-H \"Content-Type: application/json\"",
            "-H \"Authorization: Bearer $COPILOT_TOKEN\"",
            "-H \"Editor-Version: vscode/1.85.1\"",
            "-H \"Editor-Plugin-Version: copilot/1.155.0\"",
            "-H \"User-Agent: GithubCopilot/1.155.0\"",
            "-H \"Copilot-Integration-Id: vscode-chat\"",
        ]

        # Add the request body
        request_body = {
            "model": model,
            "messages": [{"role": "user", "content": "What is 2+2?"}],
            "stream": True
        }

        if "claude" in model.lower():
            # Add Claude specific tools if detected
            request_body["tools"] = [{
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
            request_body["tool_choice"] = {"type": "function", "function": {"name": "calculate"}}

        # Format the request body as JSON
        formatted_json = json.dumps(request_body, indent=2)
        # Escape quotes for shell command
        escaped_json = formatted_json.replace('"', '\\"')
        # Add the data to the curl command
        curl_cmd.append(f'-d "{escaped_json}"')

        # Add the API endpoint
        curl_cmd.append("\"https://api.githubcopilot.com/chat/completions\"")

        # Join all parts with line continuations
        return " \\\n  ".join(curl_cmd)

    def create_error_log(self, error_details: Dict[str, Any]) -> str:
        """
        Create a detailed error log file

        Args:
            error_details: Dictionary with error details

        Returns:
            Path to the created log file
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        provider = error_details.get("provider", "unknown")
        model = error_details.get("model", "unknown").split("/")[-1]  # Remove prefix
        status_code = error_details.get("status_code", 0)

        filename = f"error_{provider}_{model}_{status_code}_{timestamp}.log"
        filepath = os.path.join(self.log_dir, filename)

        with open(filepath, "w") as f:
            f.write("="*80 + "\n")
            f.write(f"GITHUB COPILOT ERROR LOG - {datetime.now().isoformat()}\n")
            f.write("="*80 + "\n\n")

            f.write(f"Provider: {provider}\n")
            f.write(f"Model: {error_details.get('model', 'unknown')}\n")
            f.write(f"Status Code: {error_details.get('status_code', 'unknown')}\n")
            f.write(f"Error Message: {error_details.get('error_message', 'unknown')}\n\n")

            if error_details.get("traceback"):
                f.write("TRACEBACK:\n")
                f.write("-"*40 + "\n")
                f.write(error_details.get("traceback", "") + "\n\n")

            f.write("REPRODUCTION CURL COMMAND:\n")
            f.write("-"*40 + "\n")
            f.write(self.generate_curl_command(error_details) + "\n\n")

            f.write("INSTRUCTIONS:\n")
            f.write("-"*40 + "\n")
            f.write("1. Set your token: export COPILOT_TOKEN=your_token_here\n")
            f.write("2. Run the curl command above to reproduce the error\n")
            f.write("3. Check the response for any specific error messages\n\n")

            f.write("JSON ERROR DETAILS:\n")
            f.write("-"*40 + "\n")
            f.write(json.dumps(error_details, indent=2) + "\n")

        logger.info(f"Created error log: {filepath}")
        return filepath

    def extract_errors_from_container_logs(self) -> List[Dict[str, Any]]:
        """
        Extract errors from container logs

        Returns:
            List of error dictionaries
        """
        try:
            # Get the container logs
            import subprocess
            cmd = f"docker logs {self.container_name} --since 2m 2>&1 | grep -A 20 -i 'github_copilot.*error'"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

            if result.returncode != 0 and not result.stdout:
                return []

            # Split logs by error occurrences
            error_logs = re.split(r'-{2,}', result.stdout)
            error_details_list = []

            for log in error_logs:
                if log.strip() and "github_copilot" in log.lower():
                    error_details = self.extract_error_details(log)
                    if error_details:
                        error_details_list.append(error_details)

            return error_details_list
        except Exception as e:
            logger.error(f"Error extracting errors from container logs: {e}")
            return []

    def monitor_errors(self, interval: int = 60) -> None:
        """
        Continuously monitor for errors

        Args:
            interval: Check interval in seconds
        """
        logger.info(f"Starting GitHub Copilot error monitor (interval: {interval}s)")
        logger.info(f"Monitoring logs in: {self.log_dir}")

        try:
            while True:
                # Check for new errors
                error_list = self.extract_errors_from_container_logs()

                for error_details in error_list:
                    self.create_error_log(error_details)

                # Sleep before next check
                time.sleep(interval)

        except KeyboardInterrupt:
            logger.info("Error monitoring stopped by user")
        except Exception as e:
            logger.error(f"Error in monitor_errors: {e}")
            logger.error(traceback.format_exc())

def manual_create_error_log(log_file_path: str, output_dir: str = "/app/error_logs") -> None:
    """
    Manually create an error log from a log file

    Args:
        log_file_path: Path to log file
        output_dir: Directory for output error log
    """
    monitor = CopilotErrorMonitor(log_dir=output_dir)

    try:
        with open(log_file_path, "r") as f:
            log_content = f.read()

        error_details = monitor.extract_error_details(log_content)
        monitor.create_error_log(error_details)
        print(f"Created error log in {output_dir}")
    except Exception as e:
        print(f"Error creating error log: {e}")

def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="GitHub Copilot Error Monitor")
    parser.add_argument("--log-dir", default="/app/error_logs",
                        help="Directory to store error logs")
    parser.add_argument("--interval", type=int, default=60,
                        help="Check interval in seconds")
    parser.add_argument("--container", default="litellm-litellm-1",
                        help="Docker container name")
    parser.add_argument("--process-log",
                        help="Process a specific log file instead of monitoring")

    args = parser.parse_args()

    if args.process_log:
        manual_create_error_log(args.process_log, args.log_dir)
    else:
        monitor = CopilotErrorMonitor(
            log_dir=args.log_dir,
            container_name=args.container
        )
        monitor.monitor_errors(interval=args.interval)

if __name__ == "__main__":
    main()
