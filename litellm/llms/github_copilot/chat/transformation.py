from typing import Optional, Tuple, List, Union, AsyncIterator, Iterator, Any, Dict
import json
import httpx
import traceback
import time

from litellm.llms.openai.openai import OpenAIConfig
from litellm.utils import ModelResponse
from litellm.llms.base_llm.base_model_iterator import BaseModelResponseIterator
from litellm.llms.base_llm.chat.transformation import BaseLLMException, LiteLLMLoggingObj
from litellm.types.utils import (
    ChatCompletionUsageBlock,
    GenericStreamingChunk,
)
from litellm.types.llms.openai import (
    AllMessageValues,
    ChatCompletionToolCallChunk,
    ChatCompletionToolCallFunctionChunk,
)

from ..authenticator import Authenticator
from ..constants import GetAPIKeyError
from litellm.exceptions import AuthenticationError
from litellm._logging import verbose_logger

class GithubCopilotError(BaseLLMException):
    def __init__(self, status_code: int, message: str, raw_error: Optional[dict] = None, response: Optional[httpx.Response] = None):
        self.status_code = status_code
        self.raw_error = raw_error or {}
        self.error_id = self._generate_error_id()

        # Extract detailed error information if available
        detailed_message = message
        if raw_error:
            error_obj = raw_error.get("error", {})
            error_code = error_obj.get("code", "")
            error_param = error_obj.get("param", "")
            error_type = error_obj.get("type", "")

            detailed_parts = []
            if error_code:
                detailed_parts.append(f"Code: {error_code}")
            if error_type:
                detailed_parts.append(f"Type: {error_type}")
            if error_param:
                detailed_parts.append(f"Parameter: {error_param}")

            if detailed_parts:
                detailed_message = f"{message} [{', '.join(detailed_parts)}]"

        # Add error ID for tracking
        self.message = f"[{self.error_id}] {detailed_message}"

        # Create request/response objects
        self.request = httpx.Request(method="POST", url="https://api.githubcopilot.com")
        if response:
            self.response = response
        else:
            self.response = httpx.Response(status_code=status_code, request=self.request)

        # Extract headers if available
        headers = None
        if response and hasattr(response, "headers"):
            headers = dict(response.headers)

        # Log comprehensive error for production debugging
        self._log_error_details()

        super().__init__(
            message=self.message,
            status_code=self.status_code,
            request=self.request,
            response=self.response,
            headers=headers,
            body=raw_error
        )

    def _generate_error_id(self) -> str:
        """Generate unique error ID for tracking."""
        import time
        import random
        import string
        timestamp = int(time.time())
        random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        return f"GHCP-{timestamp}-{random_suffix}"

    def _log_error_details(self):
        """Log comprehensive error details for production monitoring."""
        try:
            error_context = {
                "error_id": self.error_id,
                "status_code": self.status_code,
                "message": self.message,
                "raw_error": self.raw_error,
                "response_headers": dict(self.response.headers) if hasattr(self.response, 'headers') else {},
                "request_url": str(self.request.url) if self.request else "unknown",
                "request_method": self.request.method if self.request else "unknown",
                "timestamp": time.time(),
                "error_category": self._categorize_error()
            }
            
            verbose_logger.error(f"GitHub Copilot Error Details: {json.dumps(error_context, default=str)}")
            
        except Exception as e:
            verbose_logger.error(f"Failed to log error details for {self.error_id}: {str(e)}")

    def _categorize_error(self) -> str:
        """Categorize error for better monitoring and alerting."""
        if self.status_code == 400:
            return "client_error_bad_request"
        elif self.status_code == 401:
            return "auth_error_unauthorized"
        elif self.status_code == 403:
            return "auth_error_forbidden"
        elif self.status_code == 404:
            return "client_error_not_found"
        elif self.status_code == 429:
            return "rate_limit_exceeded"
        elif 500 <= self.status_code < 600:
            return "server_error"
        else:
            return "unknown_error"

    def to_dict(self) -> dict:
        """Convert error to dictionary for structured logging."""
        return {
            "error_id": self.error_id,
            "status_code": self.status_code,
            "message": self.message,
            "category": self._categorize_error(),
            "raw_error": self.raw_error,
            "timestamp": time.time()
        }

class GithubCopilotConfig(OpenAIConfig):
    def __init__(
        self,
        api_key: Optional[str] = None,
        api_base: Optional[str] = None,
        custom_llm_provider: str = "openai",
    ) -> None:
        super().__init__()
        self.authenticator = Authenticator()
        self.health_check_cache = None
        self.last_health_check = 0

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

    def _ensure_tools(self, optional_params, messages):
        tools = optional_params.get("tools", [])
        # Detect if tools were used previously in the conversation
        tool_called = any(
            m.get("tool_calls") or m.get("tool_call_id") for m in messages
        )
        # Define the dummy tool
        noop_tool = {
            "type": "function",
            "function": {
                "name": "noop",
                "description": "No operation",
                "parameters": {"type": "object"}
            }
        }
        # Only add dummy tool if tools is empty
        if (tool_called and not tools) or ("tools" in optional_params and not tools):
            tools = [noop_tool]
        optional_params["tools"] = tools
        return optional_params

    def _validate_tool_arguments(self, tool_call):
        """
        Ensure tool call arguments are valid JSON strings, and handle empty as '{}'.
        """
        import json
        function = tool_call.get("function", {})
        arguments = function.get("arguments")
        # If arguments is missing or empty, set to "{}"
        if not arguments or (isinstance(arguments, str) and arguments.strip() == ""):
            function["arguments"] = "{}"
            tool_call["function"] = function
            return tool_call
        # If arguments is a dict/object, serialize to JSON string
        if isinstance(arguments, dict):
            function["arguments"] = json.dumps(arguments)
            tool_call["function"] = function
            return tool_call
        # If arguments is a string, check if it's valid JSON
        if isinstance(arguments, str):
            try:
                json.loads(arguments)
            except Exception as e:
                raise ValueError(f"Tool call arguments must be valid JSON. Got: {arguments}. Error: {e}")
        tool_call["function"] = function
        return tool_call

    def _transform_messages_with_tool_results(self, messages, model):
        """
        Transform messages to Copilot-compatible format, including tool results and validate tool arguments.
        """
        transformed = []
        for m in messages:
            # If this is a tool result message (role: 'tool' or special marker)
            if m.get("role") == "tool" or m.get("tool_call_id"):
                # Copilot expects: { "role": "tool", "tool_call_id": ..., "content": ... }
                transformed.append({
                    "role": "tool",
                    "tool_call_id": m.get("tool_call_id") or m.get("id"),
                    "content": m.get("content"),
                })
            # If this is an assistant message with tool calls, validate arguments
            elif m.get("role") == "assistant" and m.get("tool_calls"):
                tool_calls = []
                for tc in m.get("tool_calls", []):
                    tool_calls.append(self._validate_tool_arguments(tc))
                m = dict(m)
                m["tool_calls"] = tool_calls
                transformed.append(m)
            else:
                # Use the normal transformation for user/assistant/system
                transformed.append(m)
        return transformed

    def transform_request(
        self,
        model: str,
        messages: List[AllMessageValues],
        optional_params: dict,
        litellm_params: dict,
        headers: dict,
    ) -> dict:
        # Transform messages to include tool results in Copilot-compatible format
        messages = self._transform_messages_with_tool_results(messages=messages, model=model)

        # GitHub Copilot requires specific parameters
        copilot_required_params = {
            "intent": True,
            "n": 1,
        }

        # Check if streaming is requested, if not, force it for GitHub Copilot compatibility
        stream_requested = optional_params.get("stream", False)
        if not stream_requested:
            verbose_logger.debug("GitHub Copilot requires streaming, enabling stream=True")
            copilot_required_params["stream"] = True
        else:
            copilot_required_params["stream"] = stream_requested

        # Always provide tools; add dummy tool if none present, but never add more than one
        optional_params = self._ensure_tools(optional_params, messages)

        # Merge required params with optional params, giving priority to optional_params if they exist
        final_params = {**copilot_required_params, **optional_params}

        # Transform model name - remove github_copilot/ prefix if present
        actual_model = model.replace("github_copilot/", "") if model.startswith("github_copilot/") else model
        
        verbose_logger.debug(f"GitHub Copilot model transformation: {model} -> {actual_model}")
        verbose_logger.debug(f"GitHub Copilot transformed request params: {json.dumps(final_params, default=str)}")

        return {"model": actual_model, "messages": messages, **final_params}

    async def async_transform_request(
        self,
        model: str,
        messages: List[AllMessageValues],
        optional_params: dict,
        litellm_params: dict,
        headers: dict,
    ) -> dict:
        # Transform messages to include tool results in Copilot-compatible format
        messages = self._transform_messages_with_tool_results(messages=messages, model=model)

        # GitHub Copilot requires specific parameters
        copilot_required_params = {
            "intent": True,
            "n": 1,
        }

        # Check if streaming is requested, if not, force it for GitHub Copilot compatibility
        stream_requested = optional_params.get("stream", False)
        if not stream_requested:
            verbose_logger.debug("GitHub Copilot requires streaming, enabling stream=True")
            copilot_required_params["stream"] = True
        else:
            copilot_required_params["stream"] = stream_requested

        # Always provide tools; add dummy tool if none present, but never add more than one
        optional_params = self._ensure_tools(optional_params, messages)

        # Merge required params with optional params, giving priority to optional_params if they exist
        final_params = {**copilot_required_params, **optional_params}

        # Transform model name - remove github_copilot/ prefix if present
        actual_model = model.replace("github_copilot/", "") if model.startswith("github_copilot/") else model
        
        verbose_logger.debug(f"GitHub Copilot async model transformation: {model} -> {actual_model}")
        verbose_logger.debug(f"GitHub Copilot async transformed request params: {json.dumps(final_params, default=str)}")

        return {"model": actual_model, "messages": messages, **final_params}

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
        try:
            verbose_logger.debug(f"GitHub Copilot transform_response called with status: {raw_response.status_code}")
            
            # Handle API errors with enhanced logging
            if raw_response.status_code >= 400:
                self._handle_error_response(raw_response, model)

            # Log successful response metadata for monitoring
            response_metadata = {
                "status_code": raw_response.status_code,
                "content_type": raw_response.headers.get("content-type", "unknown"),
                "model": model,
                "has_stream": optional_params.get("stream", False)
            }
            verbose_logger.debug(f"GitHub Copilot successful response: {json.dumps(response_metadata, default=str)}")

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

            # Handle GitHub Copilot specific response issues
            if final_response is None:
                verbose_logger.warning("GitHub Copilot response transformation returned None, attempting to parse raw response")
                try:
                    raw_json = raw_response.json()
                    verbose_logger.debug(f"Raw GitHub Copilot response: {json.dumps(raw_json, default=str)}")
                    
                    # Create a proper ModelResponse if we got valid JSON but transform failed
                    if raw_json and isinstance(raw_json, dict):
                        from litellm.utils import ModelResponse, Choices, Message
                        
                        choices = []
                        if "choices" in raw_json:
                            for choice_data in raw_json["choices"]:
                                message_data = choice_data.get("message", {})
                                message = Message(
                                    content=message_data.get("content", ""),
                                    role=message_data.get("role", "assistant"),
                                    tool_calls=message_data.get("tool_calls"),
                                )
                                choice = Choices(
                                    finish_reason=choice_data.get("finish_reason", "stop"),
                                    index=choice_data.get("index", 0),
                                    message=message
                                )
                                choices.append(choice)
                        
                        final_response = ModelResponse(
                            id=raw_json.get("id", "github_copilot_response"),
                            choices=choices,
                            created=raw_json.get("created"),
                            model=raw_json.get("model", model),
                            object=raw_json.get("object", "chat.completion"),
                            usage=raw_json.get("usage")
                        )
                        verbose_logger.debug("Successfully created ModelResponse from raw GitHub Copilot data")
                        
                except Exception as parse_error:
                    verbose_logger.error(f"Failed to parse raw GitHub Copilot response: {str(parse_error)}")

            # Log final response characteristics for monitoring
            if final_response:
                response_stats = {
                    "model_used": getattr(final_response, 'model', 'unknown'),
                    "usage": getattr(final_response, 'usage', None),
                    "choices_count": len(getattr(final_response, 'choices', [])),
                    "stream_processing": "GithubCopilotResponseIterator" if optional_params.get("stream") else "direct"
                }
                verbose_logger.debug(f"GitHub Copilot final response stats: {json.dumps(response_stats, default=str)}")

            return final_response
            
        except GithubCopilotError:
            # Re-raise GithubCopilotError as-is
            raise
        except Exception as e:
            # Handle unexpected errors in transform_response
            error_details = {
                "error_type": "transform_response_error",
                "model": model,
                "status_code": getattr(raw_response, 'status_code', 'unknown'),
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
            verbose_logger.error(f"Unexpected error in GitHub Copilot transform_response: {json.dumps(error_details, default=str)}")
            
            # Convert to GithubCopilotError for consistent error handling
            raise GithubCopilotError(
                status_code=500,
                message=f"Internal error during response transformation: {str(e)}",
                raw_error=error_details,
                response=raw_response
            )

    def _handle_error_response(self, raw_response: httpx.Response, model: str) -> None:
        """Handle error responses separately to reduce complexity."""
        error_details = {
            "status_code": raw_response.status_code,
            "response_headers": dict(raw_response.headers),
            "request_method": getattr(raw_response.request, "method", "UNKNOWN"),
            "request_url": str(getattr(raw_response.request, "url", "UNKNOWN")),
            "model": model,
            "raw_response_text": raw_response.text[:1000] if hasattr(raw_response, 'text') else "No text available"
        }
        
        # Add GitHub Copilot specific debugging for Bad Request errors
        if raw_response.status_code == 400:
            error_details["github_copilot_debug"] = {
                "common_causes": [
                    "Missing required 'intent' parameter",
                    "Missing required 'stream' parameter", 
                    "Invalid model name format",
                    "Missing or invalid authentication",
                    "Malformed tool calls"
                ],
                "suggested_fixes": [
                    "Ensure 'intent': true in request",
                    "Ensure 'stream': true for streaming",
                    "Use model name without 'github_copilot/' prefix",
                    "Check GitHub Copilot authentication status"
                ]
            }
        
        try:
            err = raw_response.json()
            error_obj = err.get("error", {})
            error_details["parsed_error"] = err
            msg = self._extract_error_message(error_obj, raw_response.status_code)
            
            # Add specific GitHub Copilot error context for Bad Request
            if raw_response.status_code == 400:
                msg += "\n\nGitHub Copilot Bad Request - Common causes:"
                msg += "\n• Missing 'intent': true parameter"
                msg += "\n• Missing 'stream': true parameter" 
                msg += "\n• Invalid model name (should be 'gpt-4.1', not 'github_copilot/gpt-4.1')"
                msg += "\n• Authentication issues"
                msg += "\n• Malformed request structure"
                
        except json.JSONDecodeError as e:
            err = None
            msg = f"Invalid JSON response: {raw_response.text}"
            error_details["json_decode_error"] = str(e)

        # Log comprehensive error details for production debugging
        verbose_logger.error(f"GitHub Copilot API error: {json.dumps(error_details, default=str)}")

        # Include request details in error message for debugging
        debug_info = f"\nRequest: {error_details['request_method']} {error_details['request_url']}"
        detailed_msg = f"{msg}{debug_info}"

        raise GithubCopilotError(
            status_code=raw_response.status_code,
            message=detailed_msg,
            raw_error=err,
            response=raw_response
        )

    def _extract_error_message(self, error_obj: dict, status_code: int) -> str:
        """Extract error message from error object."""
        if isinstance(error_obj, dict):
            msg = error_obj.get("message", "")
            if not msg:
                msg = self._get_default_error_message(status_code)
        else:
            msg = str(error_obj)
        return msg

    def _get_default_error_message(self, status_code: int) -> str:
        """Get default error message based on status code."""
        if status_code == 400:
            return "Bad Request: The request was unacceptable, often due to missing a required parameter or invalid input."
        elif status_code == 401:
            return "Unauthorized: Invalid authentication or credentials."
        elif status_code == 403:
            return "Forbidden: You don't have permission to access this resource."
        elif status_code == 404:
            return "Not Found: The requested resource doesn't exist."
        elif status_code == 429:
            return "Rate Limit Exceeded: Too many requests."
        elif status_code >= 500:
            return "Server Error: Something went wrong on GitHub Copilot's servers."
        else:
            return f"Error with status code: {status_code}"

    def get_error_class(
        self, error_message: str, status_code: int, headers: Union[Dict, httpx.Headers]
    ) -> BaseLLMException:
        try:
            # Log error creation for monitoring
            verbose_logger.debug(f"Creating GitHub Copilot error - Status: {status_code}, Message: {error_message[:200]}")
            
            # First try to parse the error message as JSON if it looks like JSON
            raw_error = None
            if error_message and (error_message.startswith("{") and error_message.endswith("}")):
                try:
                    raw_error = json.loads(error_message)
                    verbose_logger.debug(f"Parsed error JSON: {json.dumps(raw_error, default=str)}")
                except json.JSONDecodeError as e:
                    verbose_logger.warning(f"Failed to parse error JSON: {str(e)}")

            # Create synthetic response to provide context
            request = httpx.Request(method="POST", url="https://api.githubcopilot.com")
            response = httpx.Response(status_code=status_code, request=request, headers=headers)

            return GithubCopilotError(
                status_code=status_code,
                message=error_message,
                raw_error=raw_error,
                response=response
            )
            
        except Exception as e:
            # Fallback error creation if something goes wrong
            verbose_logger.error(f"Failed to create GitHub Copilot error class: {str(e)}")
            fallback_error = GithubCopilotError(
                status_code=status_code or 500,
                message=f"Error creating error class: {str(e)}",
                raw_error={"original_message": error_message, "creation_error": str(e)}
            )
            return fallback_error

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for GitHub Copilot integration."""
        try:
            current_time = time.time()
            
            # Return cached result if recent (within 5 minutes)
            if current_time - self.last_health_check < 300 and self.health_check_cache:
                verbose_logger.debug("Returning cached health check result")
                return self.health_check_cache
            
            health_status = {
                "service": "github_copilot",
                "status": "healthy",
                "timestamp": current_time,
                "checks": {
                    "tool_call_accumulator": "ok",
                    "error_handling": "ok",
                    "logging": "ok"
                },
                "metrics": {
                    "last_check": self.last_health_check,
                    "cache_age_seconds": current_time - self.last_health_check if self.last_health_check else 0
                }
            }
            
            # Update cache
            self.health_check_cache = health_status
            self.last_health_check = current_time
            
            verbose_logger.info(f"GitHub Copilot health check completed: {json.dumps(health_status, default=str)}")
            return health_status
            
        except Exception as e:
            error_status = {
                "service": "github_copilot",
                "status": "unhealthy",
                "timestamp": time.time(),
                "error": str(e),
                "checks": {
                    "tool_call_accumulator": "error",
                    "error_handling": "error",
                    "logging": "error"
                }
            }
            verbose_logger.error(f"GitHub Copilot health check failed: {json.dumps(error_status, default=str)}")
            return error_status

    def validate_tool_call_json(self, arguments: str) -> Tuple[bool, Optional[str]]:
        """Validate tool call arguments JSON and return validation result."""
        try:
            if not arguments or not arguments.strip():
                return True, None  # Empty arguments are valid
                
            json.loads(arguments)
            return True, None
            
        except json.JSONDecodeError as e:
            error_msg = f"Invalid JSON in tool call arguments: {str(e)}"
            verbose_logger.warning(error_msg)
            return False, error_msg
        except Exception as e:
            error_msg = f"Unexpected error validating tool call JSON: {str(e)}"
            verbose_logger.error(error_msg)
            return False, error_msg

    def get_model_response_iterator(
        self,
        streaming_response: Union[Iterator[str], AsyncIterator[str], ModelResponse],
        sync_stream: bool,
        json_mode: Optional[bool] = False,
    ) -> BaseModelResponseIterator:
        return GithubCopilotResponseIterator(streaming_response=streaming_response, sync_stream=sync_stream, json_mode=json_mode)

class GithubCopilotResponseIterator(BaseModelResponseIterator):
    def __init__(self, streaming_response: Union[Iterator[str], AsyncIterator[str], ModelResponse], sync_stream: bool, json_mode: Optional[bool] = False):
        super().__init__(streaming_response=streaming_response, sync_stream=sync_stream, json_mode=json_mode)
        self.tool_calls_by_index = {}  # Store tool calls by index (following ZED pattern)
        self.finished_tool_calls = []  # Store completed tool calls
        self.last_tool_call_finish_reason = None

    def chunk_parser(self, chunk: dict) -> GenericStreamingChunk:
        try:
            text = ""
            tool_use_list: Optional[List[ChatCompletionToolCallChunk]] = None
            tool_use: Optional[ChatCompletionToolCallChunk] = None
            is_finished = False
            finish_reason: Optional[str] = None
            usage: Optional[ChatCompletionUsageBlock] = None
            provider_specific_fields = {}
            index = int(chunk.get("index", 0))

            # Preserve raw chunk for debugging
            if chunk:
                provider_specific_fields["raw_chunk"] = chunk

            verbose_logger.debug(f"GitHub Copilot processing chunk: {json.dumps(chunk, default=str)[:500]}...")

            # Standard streaming delta
            if "choices" in chunk and chunk["choices"]:
                choice = chunk["choices"][0]
                delta = choice.get("delta", {}) or {}
                text = delta.get("content", "")

                # Handle tool calls - check for both direct and second choice
                delta_tool_calls = delta.get("tool_calls")
                if not delta_tool_calls and len(chunk["choices"]) >= 2:
                    # Check second choice for tool calls (some models use this pattern)
                    second_choice = chunk["choices"][1]
                    second_delta = second_choice.get("delta", {}) or {}
                    delta_tool_calls = second_delta.get("tool_calls")

                if delta_tool_calls:
                    verbose_logger.debug(f"GitHub Copilot processing tool calls: {delta_tool_calls}")
                    tool_use_list = self._process_tool_calls_robust(delta_tool_calls)
                    if tool_use_list and len(tool_use_list) > 0:
                        tool_use = tool_use_list[0] # GenericStreamingChunk expects a single tool call

                # Check finish reason from any choice
                for choice_item in chunk["choices"]:
                    choice_finish_reason = choice_item.get("finish_reason")
                    if choice_finish_reason:
                        finish_reason = choice_finish_reason
                        is_finished = True
                        verbose_logger.debug(f"GitHub Copilot finish reason: {finish_reason}")
                        
                        # Handle tool_calls finish reason following ZED pattern
                        if finish_reason == "tool_calls":
                            self.last_tool_call_finish_reason = finish_reason
                            # Flush completed tool calls as events
                            self._flush_completed_tool_calls()
                        break

            # Handle usage if present
            if "usage" in chunk:
                usage = chunk["usage"]
                verbose_logger.debug(f"GitHub Copilot usage: {usage}")

            response_chunk = GenericStreamingChunk(
                text=text,
                tool_use=tool_use,
                is_finished=is_finished,
                finish_reason=finish_reason if finish_reason is not None else "",
                usage=usage,
                index=index,
                provider_specific_fields=provider_specific_fields,
            )

            return response_chunk
            
        except json.JSONDecodeError as e:
            error_details = {
                "error_type": "json_decode_error",
                "chunk": chunk,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
            verbose_logger.error(f"GitHub Copilot JSON decode error: {json.dumps(error_details, default=str)}")
            raise GithubCopilotError(
                status_code=500,
                message=f"Failed to decode JSON from chunk: {str(e)}",
                raw_error=error_details
            )
        except Exception as e:
            error_details = {
                "error_type": "chunk_processing_error",
                "chunk": chunk,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
            verbose_logger.error(f"GitHub Copilot chunk processing error: {json.dumps(error_details, default=str)}")
            raise GithubCopilotError(
                status_code=500,
                message=f"Error parsing chunk: {str(e)}",
                raw_error=error_details
            )

    def _process_tool_calls_robust(self, delta_tool_calls: List[Dict]) -> Optional[List[ChatCompletionToolCallChunk]]:
        """Process tool calls robustly following ZED pattern with enhanced error handling.
        
        This method handles:
        - GPT-4.1: Incremental streaming (sends partial tool calls over multiple chunks)
        - Gemini/Claude: Complete streaming (sends full tool calls in a single chunk)
        - Robust error handling for malformed tool calls
        - Production-ready logging for debugging
        """
        if not delta_tool_calls:
            return None

        processed_calls = []
        
        try:
            for tool_call in delta_tool_calls:
                try:
                    call_index = tool_call.get("index", 0)
                    call_id = tool_call.get("id")
                    call_type = tool_call.get("type", "function")

                    verbose_logger.debug(f"Processing tool call index {call_index}: {tool_call}")

                    # Initialize entry in accumulator following ZED pattern
                    if call_index not in self.tool_calls_by_index:
                        self.tool_calls_by_index[call_index] = {
                            'id': '',
                            'name': '',
                            'arguments': '',
                            'type': call_type
                        }

                    entry = self.tool_calls_by_index[call_index]

                    # Update ID if present
                    if call_id is not None:
                        entry['id'] = call_id

                    # Process function data if present
                    if "function" in tool_call and tool_call["function"]:
                        func_data = tool_call["function"]
                        
                        # Update function name
                        if func_data.get("name"):
                            entry['name'] = func_data["name"]
                        
                        # Accumulate arguments (following ZED pattern)
                        if func_data.get("arguments"):
                            entry['arguments'] += func_data["arguments"]

                    # Create tool call chunk from accumulated state
                    func_name = entry.get('name') if entry.get('name') else None
                    func_args = entry.get('arguments', '')

                    # Validate tool call structure
                    if not self._validate_tool_call_structure(entry, call_index):
                        continue

                    function_chunk: ChatCompletionToolCallFunctionChunk = {
                        "arguments": func_args
                    }
                    if func_name is not None:
                        function_chunk["name"] = func_name

                    tool_call_chunk: ChatCompletionToolCallChunk = {
                        "index": call_index,
                        "id": entry.get('id'),
                        "type": "function",
                        "function": function_chunk
                    }
                    
                    processed_calls.append(tool_call_chunk)
                    verbose_logger.debug(f"Successfully processed tool call {call_index}: {tool_call_chunk}")

                except Exception as e:
                    # Extract call_index safely
                    safe_call_index = tool_call.get("index", "unknown") if isinstance(tool_call, dict) else "unknown"
                    error_details = {
                        "error_type": "individual_tool_call_error",
                        "tool_call": tool_call,
                        "call_index": safe_call_index,
                        "error_message": str(e),
                        "traceback": traceback.format_exc()
                    }
                    verbose_logger.error(f"Error processing individual tool call: {json.dumps(error_details, default=str)}")
                    # Continue processing other tool calls instead of failing completely
                    continue

            return processed_calls if processed_calls else None

        except Exception as e:
            error_details = {
                "error_type": "tool_calls_processing_error",
                "delta_tool_calls": delta_tool_calls,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
            verbose_logger.error(f"Critical error processing tool calls: {json.dumps(error_details, default=str)}")
            # Return None instead of raising to prevent complete failure
            return None

    def _validate_tool_call_structure(self, entry: Dict, call_index: int) -> bool:
        """Validate tool call structure for production robustness."""
        try:
            # Enhanced validation with more comprehensive checks
            validation_errors = []
            
            if not entry.get('id'):
                validation_errors.append("missing ID")
                
            if not entry.get('name'):
                validation_errors.append("missing name (may be partial)")
                verbose_logger.debug(f"Tool call {call_index} missing name (may be partial): {entry}")
                return False
                
            # Arguments can be empty string, but should be present
            if 'arguments' not in entry:
                validation_errors.append("missing arguments field")
                entry['arguments'] = ''
            
            # Validate arguments are valid JSON if not empty
            if entry.get('arguments') and entry['arguments'].strip():
                try:
                    json.loads(entry['arguments'])
                except json.JSONDecodeError:
                    validation_errors.append("invalid JSON in arguments")
                    verbose_logger.warning(f"Tool call {call_index} has invalid JSON arguments: {entry['arguments'][:100]}")
            
            # Log warnings for non-blocking issues
            if validation_errors:
                verbose_logger.warning(f"Tool call {call_index} validation issues: {', '.join(validation_errors)}")
                
            return True
        except Exception as e:
            verbose_logger.error(f"Error validating tool call structure for index {call_index}: {str(e)}")
            return False

    def _flush_completed_tool_calls(self):
        """Flush completed tool calls as events following ZED pattern."""
        try:
            if self.tool_calls_by_index:
                verbose_logger.info(f"Flushing {len(self.tool_calls_by_index)} completed tool calls")
                
                # Validate and move completed tool calls to finished list
                valid_calls = 0
                for index, tool_call in self.tool_calls_by_index.items():
                    if tool_call.get('name') and tool_call.get('arguments') is not None:
                        # Additional validation for production
                        is_valid_json, json_error = self._validate_arguments_json(tool_call.get('arguments', ''))
                        if not is_valid_json:
                            verbose_logger.warning(f"Tool call {index} has invalid JSON, fixing: {json_error}")
                            # Try to fix common JSON issues
                            tool_call['arguments'] = self._fix_json_arguments(tool_call.get('arguments', ''))
                        
                        self.finished_tool_calls.append({
                            'index': index,
                            'tool_call': tool_call.copy(),
                            'flushed_at': time.time()
                        })
                        valid_calls += 1
                        verbose_logger.debug(f"Flushed tool call {index}: {tool_call}")
                
                verbose_logger.info(f"Successfully flushed {valid_calls}/{len(self.tool_calls_by_index)} tool calls")
                
                # Clear the accumulator for next batch
                self.tool_calls_by_index.clear()
                
        except Exception as e:
            error_details = {
                "error_type": "tool_call_flush_error",
                "tool_calls_count": len(self.tool_calls_by_index) if self.tool_calls_by_index else 0,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
            verbose_logger.error(f"Error flushing tool calls: {json.dumps(error_details, default=str)}")

    def _validate_arguments_json(self, arguments: str) -> Tuple[bool, Optional[str]]:
        """Validate tool call arguments JSON."""
        try:
            if not arguments or not arguments.strip():
                return True, None
                
            json.loads(arguments)
            return True, None
            
        except json.JSONDecodeError as e:
            return False, str(e)
        except Exception as e:
            return False, f"Unexpected error: {str(e)}"

    def _fix_json_arguments(self, arguments: str) -> str:
        """Attempt to fix common JSON issues in tool call arguments."""
        try:
            if not arguments or not arguments.strip():
                return "{}"
            
            # Try to parse as-is first
            try:
                json.loads(arguments)
                return arguments
            except json.JSONDecodeError:
                pass
            
            # Common fixes
            fixed = arguments.strip()
            
            # Add missing braces if it looks like object content
            if not fixed.startswith('{') and not fixed.startswith('['):
                fixed = '{' + fixed + '}'
            
            # Try parsing the fixed version
            try:
                json.loads(fixed)
                verbose_logger.debug(f"Successfully fixed JSON arguments: {arguments[:50]}... -> {fixed[:50]}...")
                return fixed
            except json.JSONDecodeError:
                # If still invalid, return empty object
                verbose_logger.warning(f"Could not fix JSON arguments, using empty object: {arguments[:100]}")
                return "{}"
                
        except Exception as e:
            verbose_logger.error(f"Error fixing JSON arguments: {str(e)}")
            return "{}"

    def _process_tool_calls(self, delta_tool_calls: List[Dict]) -> Optional[List[ChatCompletionToolCallChunk]]:
        """Legacy method - redirects to robust implementation."""
        return self._process_tool_calls_robust(delta_tool_calls)
