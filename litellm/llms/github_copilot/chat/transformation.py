import sys; sys.path.insert(0, '/app');

from typing import Optional, Tuple, List, Union, AsyncIterator, Iterator, Any, Dict
import json
import httpx
import os
from datetime import datetime

from litellm.llms.openai.openai import OpenAIConfig
from litellm.utils import ModelResponse, Choices, StreamingChoices, Delta # Added Delta
from litellm.llms.base_llm.base_model_iterator import BaseModelResponseIterator
from litellm.llms.base_llm.chat.transformation import BaseLLMException, LiteLLMLoggingObj
from litellm._logging import verbose_logger
from litellm.types.utils import (
    ChatCompletionToolCallChunk,
    ChatCompletionUsageBlock,
    GenericStreamingChunk,
    # Usage, # Removed Usage as it's unused
)
from litellm.types.llms.openai import AllMessageValues

from ..authenticator import Authenticator
from ..constants import GetAPIKeyError
from litellm.exceptions import AuthenticationError


class GithubCopilotError(BaseLLMException):
    def __init__(self, status_code: int, message: str, raw_error: Optional[Dict] = None, response: Optional[httpx.Response] = None):
        self.status_code = status_code
        self.message = message
        self.raw_error = raw_error
        self.request = httpx.Request(method="POST", url="https://api.githubcopilot.com") if response is None else response.request
        self.response = httpx.Response(status_code=status_code, request=self.request) if response is None else response
        super().__init__(message=self.message, status_code=self.status_code, request=self.request, response=self.response)


class GithubCopilotConfig(OpenAIConfig):
    def __init__(
        self,
        api_key: Optional[str] = None,
        api_base: Optional[str] = None,
        custom_llm_provider: str = "openai",
    ) -> None:
        super().__init__()
        self.authenticator = Authenticator()

    def _get_openai_compatible_provider_info(
        self,
        model: str,
        api_base: Optional[str],
        api_key: Optional[str],
        custom_llm_provider: str,
    ) -> Tuple[Optional[str], Optional[str], str]:
        api_base = "https://api.githubcopilot.com"
        try:
            dynamic_api_key = self.authenticator.get_api_key()
        except GetAPIKeyError as e:
            raise AuthenticationError(model=model, llm_provider=custom_llm_provider, message=str(e))
        return api_base, dynamic_api_key, custom_llm_provider

    def transform_response(
        self,
        model: str,
        raw_response: httpx.Response,
        model_response: ModelResponse,
        logging_obj: LiteLLMLoggingObj,
        request_data: dict,
        messages: List[AllMessageValues],
        optional_params: dict,
        litellm_params: dict,
        encoding: Any,
        api_key: Optional[str] = None,
        json_mode: Optional[bool] = None,
    ) -> ModelResponse:
        # Handle API errors
        if raw_response.status_code >= 400:
            try:
                err = raw_response.json()
                msg = err.get("error", {}).get("message", str(err))
                detailed_msg = msg
            except json.JSONDecodeError:
                err = {}
                msg = raw_response.text
                detailed_msg = msg

            # Create error details for logging
            error_details = {
                "request_method": raw_response.request.method if hasattr(raw_response, 'request') else "Unknown",
                "request_url": raw_response.request.url if hasattr(raw_response, 'request') else "Unknown"
            }

            # Log error to file for debugging
            try:
                log_dir = "/app/error_logs"
                os.makedirs(log_dir, exist_ok=True)

                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"error_github_copilot_{model.replace('/', '_').replace('-', '_')}_{raw_response.status_code}_{timestamp}.log"
                filepath = os.path.join(log_dir, filename)

                # Create curl command for reproduction from actual request data
                try:
                    # Extract request body as JSON if possible
                    if hasattr(raw_response.request, 'content') and raw_response.request.content:
                        try:
                            request_body = raw_response.request.content.decode('utf-8')
                            # Try to parse and re-format as pretty JSON
                            try:
                                request_body_json = json.loads(request_body)
                                request_body = json.dumps(request_body_json)
                            except:
                                # Keep as is if not valid JSON
                                pass
                        except:
                            request_body = "<binary content>"
                    else:
                        request_body = "<no content>"

                    # Build header arguments
                    header_args = []
                    for k, v in raw_response.request.headers.items():
                        # Skip content-length as curl adds it automatically
                        if k.lower() == 'content-length':
                            continue
                        # Include actual authorization token in the curl command
                        # Escape double quotes in header values
                        v_escaped = str(v).replace('"', '\\"')
                        header_args.append(f'-H "{k}: {v_escaped}"')

                    headers_str = " \\\n".join(header_args)

                    # Compose the curl command with actual request data
                    curl_command = f"""curl {headers_str} \\
-d '{request_body}' \\
"{raw_response.request.url}"
"""
                except Exception as curl_error:
                    # Fallback to a basic template if we can't build the curl command from actual data
                    auth_header = next((v for k, v in raw_response.request.headers.items() if k.lower() == 'authorization'), "")
                    curl_command = f"""curl -H "Authorization: {auth_header}" \\
-H "Content-Type: application/json" \\
-d '{{"model": "{model.replace('github_copilot/', '')}"}}' \\
"https://api.githubcopilot.com/chat/completions"
# Error building curl command: {str(curl_error)}
"""

                # Write error details to file
                with open(filepath, "w") as f:
                    f.write("="*80 + "\n")
                    f.write(f"GITHUB COPILOT ERROR LOG - {datetime.now().isoformat()}\n")
                    f.write("="*80 + "\n\n")

                    f.write(f"Provider: github_copilot\n")
                    f.write(f"Model: {model}\n")
                    f.write(f"Status Code: {raw_response.status_code}\n\n")

                    f.write("REQUEST:\n")
                    f.write("-"*40 + "\n")
                    f.write(f"Method: {error_details['request_method']}\n")
                    f.write(f"URL: {error_details['request_url']}\n")
                    f.write("Headers:\n")
                    for k, v in raw_response.request.headers.items():
                        # Mask sensitive headers
                        if k.lower() in ['authorization', 'x-api-key', 'api-key']:
                            v = v[:10] + "..." if len(v) > 10 else "***"
                        f.write(f"  {k}: {v}\n")

                    f.write("\nRESPONSE:\n")
                    f.write("-"*40 + "\n")
                    f.write(f"Status: {raw_response.status_code}\n")
                    f.write("Headers:\n")
                    for k, v in raw_response.headers.items():
                        f.write(f"  {k}: {v}\n")
                    f.write(f"Body:\n{raw_response.text[:2000] if hasattr(raw_response, 'text') else 'No text available'}\n\n")

                    f.write("REPRODUCTION CURL:\n")
                    f.write("-"*40 + "\n")
                    f.write(f"{curl_command}\n\n")

                    f.write("ERROR DETAILS:\n")
                    f.write("-"*40 + "\n")
                    f.write(f"Message: {msg}\n\n")
                    if err:
                        f.write(f"Full error: {json.dumps(err, indent=2)}\n\n")

                verbose_logger.info(f"GitHub Copilot error logged to {filepath}")
            except Exception as log_error:
                verbose_logger.error(f"Failed to log error details: {log_error}")

            # Then continue with the original code
            raise GithubCopilotError(
                status_code=raw_response.status_code,
                message=detailed_msg,
                raw_error=err,
                response=raw_response
            )

        # Base transformation using OpenAIConfig
        final_response = super().transform_response(
            model,
            raw_response,
            model_response,
            logging_obj,
            request_data,
            messages,
            optional_params,
            litellm_params,
            encoding,
            api_key,
            json_mode,
        )

        # Post-process for Claude model tool_calls
        if isinstance(final_response, ModelResponse) and final_response.model and "claude" in final_response.model.lower():
            choices_list = final_response.choices
            if choices_list and len(choices_list) >= 2:
                first_choice_obj = choices_list[0]
                second_choice_obj = choices_list[1]

                # Non-streaming
                if all(isinstance(c, Choices) for c in choices_list):
                    # Add explicit isinstance checks for the specific elements being accessed to help linter
                    if isinstance(first_choice_obj, Choices) and isinstance(second_choice_obj, Choices):
                        if hasattr(second_choice_obj.message, "tool_calls") and second_choice_obj.message.tool_calls:
                            # Assuming first_choice_obj.message is always a Message object as per Choices definition
                            setattr(first_choice_obj.message, "tool_calls", second_choice_obj.message.tool_calls)
                            final_response.choices = [first_choice_obj]
                # Streaming
                elif all(isinstance(c, StreamingChoices) for c in choices_list):
                     # Add explicit isinstance checks for the specific elements being accessed to help linter
                    if isinstance(first_choice_obj, StreamingChoices) and isinstance(second_choice_obj, StreamingChoices):
                        if hasattr(second_choice_obj.delta, "tool_calls") and second_choice_obj.delta.tool_calls:
                            # Original defensive check for first_choice_obj.delta, with Message() -> Delta() fix
                            if not hasattr(first_choice_obj, "delta") or first_choice_obj.delta is None:
                                setattr(first_choice_obj, "delta", Delta()) # Corrected to Delta()

                            # Now, first_choice_obj.delta is assumed to be a valid Delta object.
                            setattr(first_choice_obj.delta, "tool_calls", second_choice_obj.delta.tool_calls)
                            final_response.choices = [first_choice_obj]
        return final_response

    def get_error_class(
        self, error_message: str, status_code: int, headers: Union[Dict, httpx.Headers]
    ) -> BaseLLMException:
        return GithubCopilotError(status_code=status_code, message=error_message)

    def get_model_response_iterator(
        self,
        streaming_response: Union[Iterator[str], AsyncIterator[str], ModelResponse],
        sync_stream: bool,
        json_mode: Optional[bool] = False,
    ) -> BaseModelResponseIterator:
        return GithubCopilotResponseIterator(streaming_response=streaming_response, sync_stream=sync_stream, json_mode=json_mode)


class GithubCopilotResponseIterator(BaseModelResponseIterator):
    def chunk_parser(self, chunk: dict) -> GenericStreamingChunk:
        try:
            text = ""
            tool_use: Optional[ChatCompletionToolCallChunk] = None
            is_finished = False
            finish_reason: Optional[str] = None
            usage: Optional[ChatCompletionUsageBlock] = None
            provider_specific_fields = None
            index = int(chunk.get("index", 0))

            # Standard streaming delta
            if "choices" in chunk and chunk["choices"]:
                choice = chunk["choices"][0]
                delta = choice.get("delta", {}) or {}
                text = delta.get("content", "")
                tool_use = delta.get("tool_calls")
                if choice.get("finish_reason"):
                    finish_reason = choice["finish_reason"]
                    is_finished = True

            # Special Claude tool_calls in second choice
            if (
                "choices" in chunk and len(chunk["choices"]) >= 2
                and chunk["choices"][1].get("delta", {}).get("tool_calls")
            ):
                tool_use = chunk["choices"][1]["delta"]["tool_calls"]

            return GenericStreamingChunk(
                text=text,
                tool_use=tool_use,
                is_finished=is_finished,
                finish_reason=finish_reason if finish_reason is not None else "", # Ensure str is passed
                usage=usage,
                index=index,
                provider_specific_fields=provider_specific_fields,
            )
        except json.JSONDecodeError:
            raise ValueError(f"Failed to decode JSON from chunk: {chunk}")
        except Exception as e:
            raise ValueError(f"Error parsing chunk: {str(e)}; chunk: {chunk}")
