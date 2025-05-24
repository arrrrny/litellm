import json
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

import httpx

from litellm._logging import verbose_logger
from litellm.llms.custom_httpx.http_handler import _get_httpx_client

from .constants import (
    APIKeyExpiredError,
    GetAccessTokenError,
    GetAPIKeyError,
    GetDeviceCodeError,
    RefreshAPIKeyError,
)

# Constants
GITHUB_CLIENT_ID = "Iv1.b507a08c87ecfe98"
GITHUB_DEVICE_CODE_URL = "https://github.com/login/device/code"
GITHUB_ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token"
GITHUB_API_KEY_URL = "https://api.github.com/copilot_internal/v2/token"
GITHUB_COPILOT_MODELS_URL = "https://api.githubcopilot.com/models"


class Authenticator:
    def __init__(self) -> None:
        """Initialize the GitHub Copilot authenticator with configurable token paths."""
        # Token storage paths
        self.token_dir = os.getenv(
            "GITHUB_COPILOT_TOKEN_DIR",
            os.path.expanduser("~/.config/litellm/github_copilot"),
        )
        self.access_token_file = os.path.join(
            self.token_dir,
            os.getenv("GITHUB_COPILOT_ACCESS_TOKEN_FILE", "access-token"),
        )
        self.api_key_file = os.path.join(
            self.token_dir, os.getenv("GITHUB_COPILOT_API_KEY_FILE", "api-key.json")
        )
        self._ensure_token_dir()

    def get_access_token(self) -> str:
        """
        Login to Copilot with retry 3 times.

        Returns:
            str: The GitHub access token.

        Raises:
            GetAccessTokenError: If unable to obtain an access token after retries.
        """
        try:
            with open(self.access_token_file, "r") as f:
                access_token = f.read().strip()
                if access_token:
                    return access_token
        except IOError:
            verbose_logger.warning(
                "No existing access token found or error reading file"
            )

        for attempt in range(3):
            verbose_logger.debug(f"Access token acquisition attempt {attempt + 1}/3")
            try:
                access_token = self._login()
                try:
                    with open(self.access_token_file, "w") as f:
                        f.write(access_token)
                except IOError:
                    verbose_logger.error("Error saving access token to file")
                return access_token
            except (GetDeviceCodeError, GetAccessTokenError, RefreshAPIKeyError) as e:
                verbose_logger.warning(f"Failed attempt {attempt + 1}: {str(e)}")
                continue

        raise GetAccessTokenError("Failed to get access token after 3 attempts")

    def get_api_key(self) -> str:
        """
        Get the API key, refreshing if necessary.

        Returns:
            str: The GitHub Copilot API key.

        Raises:
            GetAPIKeyError: If unable to obtain an API key.
        """
        try:
            with open(self.api_key_file, "r") as f:
                api_key_info = json.load(f)
                if api_key_info.get("expires_at", 0) > datetime.now().timestamp():
                    return api_key_info.get("token")
                else:
                    verbose_logger.warning("API key expired, refreshing")
                    raise APIKeyExpiredError("API key expired")
        except IOError:
            verbose_logger.warning("No API key file found or error opening file")
        except (json.JSONDecodeError, KeyError) as e:
            verbose_logger.warning(f"Error reading API key from file: {str(e)}")
        except APIKeyExpiredError:
            pass  # Already logged in the try block

        try:
            api_key_info = self._refresh_api_key()
            with open(self.api_key_file, "w") as f:
                json.dump(api_key_info, f)
            token = api_key_info.get("token")
            if token:
                return token
            else:
                raise GetAPIKeyError("API key response missing token")
        except IOError as e:
            verbose_logger.error(f"Error saving API key to file: {str(e)}")
            raise GetAPIKeyError(f"Failed to save API key: {str(e)}")
        except RefreshAPIKeyError as e:
            raise GetAPIKeyError(f"Failed to refresh API key: {str(e)}")

    def _refresh_api_key(self) -> Dict[str, Any]:
        """
        Refresh the API key using the access token.

        Returns:
            Dict[str, Any]: The API key information including token and expiration.

        Raises:
            RefreshAPIKeyError: If unable to refresh the API key.
        """
        access_token = self.get_access_token()
        headers = self._get_github_headers(access_token)

        max_retries = 3
        for attempt in range(max_retries):
            try:
                sync_client = _get_httpx_client()
                response = sync_client.get(GITHUB_API_KEY_URL, headers=headers)
                response.raise_for_status()

                response_json = response.json()

                if "token" in response_json:
                    return response_json
                else:
                    verbose_logger.warning(
                        f"API key response missing token: {response_json}"
                    )
            except httpx.HTTPStatusError as e:
                verbose_logger.error(
                    f"HTTP error refreshing API key (attempt {attempt+1}/{max_retries}): {str(e)}"
                )
            except Exception as e:
                verbose_logger.error(f"Unexpected error refreshing API key: {str(e)}")

        raise RefreshAPIKeyError("Failed to refresh API key after maximum retries")

    def _ensure_token_dir(self) -> None:
        """Ensure the token directory exists."""
        if not os.path.exists(self.token_dir):
            os.makedirs(self.token_dir, exist_ok=True)

    def _get_github_headers(self, access_token: Optional[str] = None) -> Dict[str, str]:
        """
        Generate standard GitHub headers for API requests.

        Args:
            access_token: Optional access token to include in the headers.

        Returns:
            Dict[str, str]: Headers for GitHub API requests.
        """
        headers = {
            "accept": "application/json",
            "editor-version": "vscode/1.85.1",
            "editor-plugin-version": "copilot/1.155.0",
            "user-agent": "GithubCopilot/1.155.0",
            "accept-encoding": "gzip,deflate,br",
        }

        if access_token:
            headers["authorization"] = f"token {access_token}"

        if "content-type" not in headers:
            headers["content-type"] = "application/json"

        return headers

    def _get_device_code(self) -> Dict[str, str]:
        """
        Get a device code for GitHub authentication.

        Returns:
            Dict[str, str]: Device code information.

        Raises:
            GetDeviceCodeError: If unable to get a device code.
        """
        try:
            sync_client = _get_httpx_client()
            resp = sync_client.post(
                GITHUB_DEVICE_CODE_URL,
                headers=self._get_github_headers(),
                json={"client_id": GITHUB_CLIENT_ID, "scope": "read:user"},
            )
            resp.raise_for_status()
            resp_json = resp.json()

            required_fields = ["device_code", "user_code", "verification_uri"]
            if not all(field in resp_json for field in required_fields):
                verbose_logger.error(f"Response missing required fields: {resp_json}")
                raise GetDeviceCodeError("Response missing required fields")

            return resp_json
        except httpx.HTTPStatusError as e:
            verbose_logger.error(f"HTTP error getting device code: {str(e)}")
            raise GetDeviceCodeError(f"Failed to get device code: {str(e)}")
        except json.JSONDecodeError as e:
            verbose_logger.error(f"Error decoding JSON response: {str(e)}")
            raise GetDeviceCodeError(f"Failed to decode device code response: {str(e)}")
        except Exception as e:
            verbose_logger.error(f"Unexpected error getting device code: {str(e)}")
            raise GetDeviceCodeError(f"Failed to get device code: {str(e)}")

    def _poll_for_access_token(self, device_code: str) -> str:
        """
        Poll for an access token after user authentication.

        Args:
            device_code: The device code to use for polling.

        Returns:
            str: The access token.

        Raises:
            GetAccessTokenError: If unable to get an access token.
        """
        sync_client = _get_httpx_client()
        max_attempts = 12  # 1 minute (12 * 5 seconds)

        for attempt in range(max_attempts):
            try:
                resp = sync_client.post(
                    GITHUB_ACCESS_TOKEN_URL,
                    headers=self._get_github_headers(),
                    json={
                        "client_id": GITHUB_CLIENT_ID,
                        "device_code": device_code,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    },
                )
                resp.raise_for_status()
                resp_json = resp.json()

                if "access_token" in resp_json:
                    verbose_logger.info("Authentication successful!")
                    return resp_json["access_token"]
                elif (
                    "error" in resp_json
                    and resp_json.get("error") == "authorization_pending"
                ):
                    # Print more informative waiting message
                    if attempt % 2 == 0:  # Only print every other attempt to reduce noise
                        waiting_msg = f"Waiting for GitHub Copilot authorization (attempt {attempt+1}/{max_attempts})... Please visit the URL and enter the code."
                        print(waiting_msg)
                        verbose_logger.info(waiting_msg)
                    else:
                        verbose_logger.debug(
                            f"Authorization pending (attempt {attempt+1}/{max_attempts})"
                        )
                else:
                    verbose_logger.warning(f"Unexpected response: {resp_json}")
            except httpx.HTTPStatusError as e:
                error_msg = f"HTTP error polling for access token: {str(e)}"
                verbose_logger.error(error_msg)
                print(f"ERROR: {error_msg}")
                raise GetAccessTokenError(f"Failed to get access token: {str(e)}")
            except json.JSONDecodeError as e:
                verbose_logger.error(f"Error decoding JSON response: {str(e)}")
                raise GetAccessTokenError(
                    f"Failed to decode access token response: {str(e)}"
                )
            except Exception as e:
                verbose_logger.error(
                    f"Unexpected error polling for access token: {str(e)}"
                )
                raise GetAccessTokenError(f"Failed to get access token: {str(e)}")

            time.sleep(5)

        raise GetAccessTokenError("Timed out waiting for user to authorize the device")

    def _login(self) -> str:
        """
        Login to GitHub Copilot using device code flow.

        Returns:
            str: The GitHub access token.

        Raises:
            GetDeviceCodeError: If unable to get a device code.
            GetAccessTokenError: If unable to get an access token.
        """
        print("\n\nStarting GitHub Copilot authentication process...\n\n")
        device_code_info = self._get_device_code()

        device_code = device_code_info["device_code"]
        user_code = device_code_info["user_code"]
        verification_uri = device_code_info["verification_uri"]

        if "verification_uri_complete" in device_code_info:
            print(f"\nAlternative direct URL: {device_code_info['verification_uri_complete']}\n")

        # Print the authentication URL and code multiple times to ensure visibility in logs
        auth_message = f"""

        =====================================================
        GITHUB COPILOT AUTHENTICATION REQUIRED
        =====================================================

        Please visit: {verification_uri}

        And enter code: {user_code}

        =====================================================
        """

        print(auth_message)
        verbose_logger.critical(auth_message)  # Log at critical level to ensure visibility

        # Also log to stderr for maximum visibility
        import sys
        sys.stderr.write(auth_message + "\n")
        sys.stderr.flush()

        return self._poll_for_access_token(device_code)

    def fetch_available_models(self) -> List[Dict[str, Any]]:
        """
        Fetch available models from GitHub Copilot API.

        Returns:
            List[Dict[str, Any]]: List of available models with their capabilities.

        Raises:
            GetAPIKeyError: If unable to authenticate or fetch models.
        """
        try:
            api_key = self.get_api_key()
            headers = self._get_github_headers()
            headers["Authorization"] = f"Bearer {api_key}"

            sync_client = _get_httpx_client()
            response = sync_client.get(GITHUB_COPILOT_MODELS_URL, headers=headers)
            response.raise_for_status()

            data = response.json()
            if "data" in data:
                verbose_logger.info(f"Successfully fetched {len(data['data'])} models from GitHub Copilot")
                return data["data"]
            else:
                verbose_logger.warning(f"Unexpected response format from models API: {data}")
                return []

        except httpx.HTTPStatusError as e:
            verbose_logger.error(f"HTTP error fetching models: {e}")
            verbose_logger.error(f"Response: {e.response.text}")
            raise GetAPIKeyError(f"Failed to fetch models: {e}")
        except Exception as e:
            verbose_logger.error(f"Error fetching models: {e}")
            raise GetAPIKeyError(f"Failed to fetch models: {e}")

    def convert_model_to_litellm_config(self, model: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Convert a GitHub Copilot model to LiteLLM config format.

        Args:
            model: Model information from GitHub Copilot API.

        Returns:
            Optional[Dict[str, Any]]: LiteLLM model configuration or None if model is not suitable.
        """
        try:
            # Skip models that are not chat-enabled or not picker-enabled
            if not model.get("model_picker_enabled", False):
                verbose_logger.debug(f"Skipping model {model.get('id')} - not picker enabled")
                return None

            capabilities = model.get("capabilities", {})
            if capabilities.get("type") != "chat":
                verbose_logger.debug(f"Skipping model {model.get('id')} - not chat type")
                return None

            model_id = model.get("id")
            if not model_id:
                verbose_logger.warning("Model missing id field")
                return None

            # Extract model info from capabilities
            supports = capabilities.get("supports", {})
            limits = capabilities.get("limits", {})

            # Build model_info with available information
            model_info = {
                "litellm_provider": "github_copilot",
                "mode": "chat",
                "input_cost_per_token": 0.0,
                "output_cost_per_token": 0.0,
                "supports_system_messages": True,  # All Copilot chat models support system messages
            }

            # Add token limits if available
            if "max_context_window_tokens" in limits:
                max_tokens = limits["max_context_window_tokens"]
                model_info["max_tokens"] = max_tokens

                # Handle input/output token limits based on model patterns
                if model_id in ["gpt-4.1", "gpt-4o", "o4-mini"]:
                    model_info["max_input_tokens"] = int(max_tokens * 0.75)
                    model_info["max_output_tokens"] = 16384
                elif model_id in ["claude-3.7-sonnet", "claude-3.7-sonnet-thought"]:
                    model_info["max_input_tokens"] = int(max_tokens * 0.75)
                    model_info["max_output_tokens"] = 16384
                elif model_id == "gemini-2.0-flash-001":
                    model_info["max_input_tokens"] = int(max_tokens * 0.75)
                    model_info["max_output_tokens"] = 8192
                else:
                    # Default split for other models
                    model_info["max_input_tokens"] = int(max_tokens * 0.75)
                    model_info["max_output_tokens"] = int(max_tokens * 0.25)

            # Override with explicit max_output_tokens if provided
            if "max_output_tokens" in limits:
                model_info["max_output_tokens"] = limits["max_output_tokens"]

            # Add capability flags
            if supports.get("vision", False):
                model_info["supports_vision"] = True

            # Handle tool calls and function calling capabilities
            if supports.get("tool_calls", False) or model_id in ["gpt-4.1", "gpt-4o", "o4-mini", "claude-3.5-sonnet", "claude-3.7-sonnet", "claude-sonnet-4", "gemini-2.5-pro", "gemini-2.0-flash-001"]:
                model_info["supports_function_calling"] = True
                model_info["supports_tool_calls"] = True

            # Parallel function calling (supported by newer models)
            if supports.get("parallel_tool_calls", False) or model_id in ["gpt-4.1", "gpt-4o", "o4-mini", "claude-3.5-sonnet", "claude-3.7-sonnet", "claude-sonnet-4", "gemini-2.5-pro"]:
                model_info["supports_parallel_function_calling"] = True

            # Structured outputs
            if supports.get("structured_outputs", False) or model_id in ["o1", "o3-mini", "o4-mini", "gpt-4.1"]:
                model_info["supports_structured_outputs"] = True

            if supports.get("response_schema", False):
                model_info["supports_response_schema"] = True

            # Build the complete model config
            model_config = {
                "model_name": f"github_copilot/{model_id}",
                "litellm_params": {
                    "model": f"github_copilot/{model_id}",
                    "extra_headers": {
                        "Editor-Version": "vscode/1.85.1",
                        "Editor-Plugin-Version": "copilot/1.155.0",
                        "User-Agent": "GithubCopilot/1.155.0",
                        "Copilot-Integration-Id": "vscode-chat"
                    },
                    "model_info": model_info
                }
            }

            # Add cache_models_for for models that support caching
            if supports.get("streaming", False):
                model_config["litellm_params"]["cache_models_for"] = 7200

            verbose_logger.debug(f"Converted model {model_id} to LiteLLM config")
            return model_config

        except Exception as e:
            verbose_logger.error(f"Error converting model {model}: {e}")
            return None

    def get_litellm_model_configs(self) -> List[Dict[str, Any]]:
        """
        Get all available GitHub Copilot models in LiteLLM config format.

        Returns:
            List[Dict[str, Any]]: List of model configurations ready for LiteLLM.
        """
        try:
            models = self.fetch_available_models()
            converted_models = []

            for model in models:
                converted = self.convert_model_to_litellm_config(model)
                if converted:
                    converted_models.append(converted)

            verbose_logger.info(f"Successfully converted {len(converted_models)} GitHub Copilot models")
            return converted_models

        except Exception as e:
            verbose_logger.error(f"Failed to get LiteLLM model configs: {e}")
            return []
