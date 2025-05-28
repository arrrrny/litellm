import json
import os
from datetime import datetime
from typing import Any, Dict, Optional
import httpx


class ErrorLogger:
    """Utility for logging HTTP errors to files for debugging"""

    def __init__(self, log_dir: str = "/app/error_logs"):
        self.log_dir = log_dir
        os.makedirs(log_dir, exist_ok=True)

    def log_http_error(
        self,
        request: httpx.Request,
        response: httpx.Response,
        provider: str,
        model: str,
        error_context: Optional[Dict[str, Any]] = None
    ) -> None:
        """Log HTTP error details to file when status >= 400"""
        if response.status_code < 400:
            return

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        filename = f"error_{provider}_{model}_{response.status_code}_{timestamp}.log"
        filepath = os.path.join(self.log_dir, filename)

        # Extract request body
        request_body = ""
        if hasattr(request, 'content') and request.content:
            try:
                request_body = request.content.decode('utf-8')
            except:
                request_body = str(request.content)

        # Extract response body
        response_body = ""
        try:
            response_body = response.text
        except:
            response_body = str(response.content)

        # Generate curl command for reproduction
        curl_command = self._generate_curl_command(request, request_body)

        # Create log entry
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "provider": provider,
            "model": model,
            "status_code": response.status_code,
            "request": {
                "method": request.method,
                "url": str(request.url),
                "headers": dict(request.headers),
                "body": request_body
            },
            "response": {
                "status_code": response.status_code,
                "headers": dict(response.headers),
                "body": response_body
            },
            "curl_command": curl_command,
            "error_context": error_context or {}
        }

        # Write to file
        try:
            with open(filepath, 'w') as f:
                f.write("="*80 + "\n")
                f.write(f"HTTP ERROR LOG - {datetime.now().isoformat()}\n")
                f.write("="*80 + "\n\n")

                f.write(f"Provider: {provider}\n")
                f.write(f"Model: {model}\n")
                f.write(f"Status Code: {response.status_code}\n\n")

                f.write("REQUEST:\n")
                f.write("-" * 40 + "\n")
                f.write(f"Method: {request.method}\n")
                f.write(f"URL: {request.url}\n")
                f.write("Headers:\n")
                for k, v in request.headers.items():
                    # Mask sensitive headers
                    if k.lower() in ['authorization', 'x-api-key', 'api-key']:
                        v = v[:10] + "..." if len(v) > 10 else "***"
                    f.write(f"  {k}: {v}\n")
                f.write(f"Body:\n{request_body}\n\n")

                f.write("RESPONSE:\n")
                f.write("-" * 40 + "\n")
                f.write(f"Status: {response.status_code}\n")
                f.write("Headers:\n")
                for k, v in response.headers.items():
                    f.write(f"  {k}: {v}\n")
                f.write(f"Body:\n{response_body}\n\n")

                f.write("REPRODUCTION CURL:\n")
                f.write("-" * 40 + "\n")
                f.write(f"{curl_command}\n\n")

                if error_context:
                    f.write("ERROR CONTEXT:\n")
                    f.write("-" * 40 + "\n")
                    f.write(json.dumps(error_context, indent=2) + "\n\n")

                f.write("JSON LOG:\n")
                f.write("-" * 40 + "\n")
                f.write(json.dumps(log_entry, indent=2) + "\n")

        except Exception as e:
            # Fallback logging if file write fails
            print(f"Failed to write error log to {filepath}: {e}")

    def _generate_curl_command(self, request: httpx.Request, request_body: str) -> str:
        """Generate a curl command to reproduce the request"""
        curl_parts = ["curl"]

        # Add method
        if request.method != "GET":
            curl_parts.append(f"-X {request.method}")

        # Add headers
        for k, v in request.headers.items():
            # Skip auto-generated headers
            if k.lower() in ['content-length', 'host', 'user-agent']:
                continue
            # Mask sensitive headers but keep structure for reproduction
            if k.lower() in ['authorization', 'x-api-key', 'api-key']:
                if 'bearer' in v.lower():
                    v = "Bearer $TOKEN"
                else:
                    v = "$API_KEY"
            curl_parts.append(f'-H "{k}: {v}"')

        # Add body if present
        if request_body:
            # Escape quotes in JSON
            escaped_body = request_body.replace('"', '\\"')
            curl_parts.append(f'-d "{escaped_body}"')

        # Add URL
        curl_parts.append(f'"{request.url}"')

        return " \\\n     ".join(curl_parts)


# Global instance
error_logger = ErrorLogger()
