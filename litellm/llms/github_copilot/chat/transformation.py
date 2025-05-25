from typing import Optional, Tuple, List, Union, AsyncIterator, Iterator, Any, Dict
import json
import httpx

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

class GithubCopilotError(BaseLLMException):
    def __init__(self, status_code: int, message: str, raw_error: Optional[dict] = None, response: Optional[httpx.Response] = None):
        self.status_code = status_code
        self.raw_error = raw_error or {}

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

        self.message = detailed_message

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

        super().__init__(
            message=self.message,
            status_code=self.status_code,
            request=self.request,
            response=self.response,
            headers=headers,
            body=raw_error
        )

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

    def transform_request(
        self,
        model: str,
        messages: List[AllMessageValues],
        optional_params: dict,
        litellm_params: dict,
        headers: dict,
    ) -> dict:
        # Get the base request from parent class
        messages = self._transform_messages(messages=messages, model=model)

        # Ensure required GitHub Copilot parameters are included
        copilot_required_params = {
            "intent": True,
            "n": 1,
            "stream": True,
        }

        # Always provide tools; add dummy tool if none present, but never add more than one
        optional_params = self._ensure_tools(optional_params, messages)

        # Merge required params with optional params, giving priority to optional_params if they exist
        final_params = {**copilot_required_params, **optional_params}

        return {"model": model, "messages": messages, **final_params}

    async def async_transform_request(
        self,
        model: str,
        messages: List[AllMessageValues],
        optional_params: dict,
        litellm_params: dict,
        headers: dict,
    ) -> dict:
        # Get the base request from parent class
        messages = self._transform_messages(messages=messages, model=model)

        # Ensure required GitHub Copilot parameters are included
        copilot_required_params = {
            "intent": True,
            "n": 1,
            "stream": True,
        }

        # Always provide tools; add dummy tool if none present, but never add more than one
        optional_params = self._ensure_tools(optional_params, messages)

        # Merge required params with optional params, giving priority to optional_params if they exist
        final_params = {**copilot_required_params, **optional_params}

        return {"model": model, "messages": messages, **final_params}

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
                error_obj = err.get("error", {})

                # Extract detailed error information
                if isinstance(error_obj, dict):
                    msg = error_obj.get("message", "")

                    # If no specific message found, use a more descriptive one based on status code
                    if not msg:
                        if raw_response.status_code == 400:
                            msg = "Bad Request: The request was unacceptable, often due to missing a required parameter or invalid input."
                        elif raw_response.status_code == 401:
                            msg = "Unauthorized: Invalid authentication or credentials."
                        elif raw_response.status_code == 403:
                            msg = "Forbidden: You don't have permission to access this resource."
                        elif raw_response.status_code == 404:
                            msg = "Not Found: The requested resource doesn't exist."
                        elif raw_response.status_code == 429:
                            msg = "Rate Limit Exceeded: Too many requests."
                        elif raw_response.status_code >= 500:
                            msg = "Server Error: Something went wrong on GitHub Copilot's servers."
                        else:
                            msg = f"Error with status code: {raw_response.status_code}"
                else:
                    msg = str(err)
            except json.JSONDecodeError:
                err = None
                msg = f"Invalid JSON response: {raw_response.text}"



            # Include request details in error message for debugging
            request_method = getattr(raw_response.request, "method", "UNKNOWN")
            request_url = getattr(raw_response.request, "url", "UNKNOWN")
            debug_info = f"\nRequest: {request_method} {request_url}"
            detailed_msg = f"{msg}{debug_info}"

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

        # No additional processing needed - all models (gpt-4.1, gemini, claude)
        # put their tool calls in choices[0], and the streaming logic in
        # GithubCopilotResponseIterator handles both incremental and complete
        # tool call patterns
        return final_response

    def get_error_class(
        self, error_message: str, status_code: int, headers: Union[Dict, httpx.Headers]
    ) -> BaseLLMException:
        # First try to parse the error message as JSON if it looks like JSON
        raw_error = None
        if error_message and (error_message.startswith("{") and error_message.endswith("}")):
            try:
                raw_error = json.loads(error_message)
            except json.JSONDecodeError:
                pass

        # Create synthetic response to provide context
        request = httpx.Request(method="POST", url="https://api.githubcopilot.com")
        response = httpx.Response(status_code=status_code, request=request, headers=headers)

        return GithubCopilotError(
            status_code=status_code,
            message=error_message,
            raw_error=raw_error,
            response=response
        )

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
        self.tool_call_accumulator = {}  # Store partial tool calls by index

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
                    tool_use_list = self._process_tool_calls(delta_tool_calls)
                    if tool_use_list and len(tool_use_list) > 0:
                        tool_use = tool_use_list[0] # GenericStreamingChunk expects a single tool call

                # Check finish reason from any choice
                for choice_item in chunk["choices"]:
                    if choice_item.get("finish_reason"):
                        finish_reason = choice_item["finish_reason"]
                        is_finished = True
                        break

            # Handle usage if present
            if "usage" in chunk:
                usage = chunk["usage"]

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
        except json.JSONDecodeError:
            detailed_error = f"Failed to decode JSON from chunk: {chunk}"
            # Log the error for debugging purposes
            print(f"GitHub Copilot Error: {detailed_error}")
            raise ValueError(detailed_error)
        except Exception as e:
            detailed_error = f"Error parsing chunk: {str(e)}; chunk: {chunk}"
            # Log the error for debugging purposes
            print(f"GitHub Copilot Error: {detailed_error}")
            raise ValueError(detailed_error)

    def _process_tool_calls(self, delta_tool_calls: List[Dict]) -> Optional[List[ChatCompletionToolCallChunk]]:
        """Process tool calls from all models, handling:
        - GPT-4.1: Incremental streaming (sends partial tool calls over multiple chunks)
        - Gemini/Claude: Complete streaming (sends full tool calls in a single chunk)
        """
        if not delta_tool_calls:
            return None

        processed_calls = []
        for tool_call in delta_tool_calls:
            call_index = tool_call.get("index", 0)
            call_id = tool_call.get("id")
            call_type = tool_call.get("type", "function")

            # For complete tool calls (Gemini/Claude), initialize accumulator and populate immediately
            if "function" in tool_call and tool_call["function"].get("arguments") and tool_call["function"].get("name"):
                self.tool_call_accumulator[call_index] = {
                    "id": call_id,
                    "type": call_type,
                    "function": {
                        "name": tool_call["function"]["name"],
                        "arguments": tool_call["function"]["arguments"]
                    }
                }
            # For incremental tool calls (GPT-4.1), accumulate data over multiple chunks
            else:
                # Initialize accumulator if needed
                if call_index not in self.tool_call_accumulator:
                    self.tool_call_accumulator[call_index] = {
                        "id": call_id,
                        "type": call_type,
                        "function": {
                            "name": "",
                            "arguments": ""
                        }
                    }

                accumulated = self.tool_call_accumulator[call_index]

                # Update function data if present
                if "function" in tool_call:
                    func_data = tool_call["function"]
                    if func_data.get("name"):
                        accumulated["function"]["name"] = func_data["name"]
                    if func_data.get("arguments"):
                        accumulated["function"]["arguments"] += func_data["arguments"]

            # Create tool call chunk from accumulated state
            accumulated = self.tool_call_accumulator[call_index]

            # Ensure function components exist for ChatCompletionToolCallFunctionChunk
            func_name = accumulated["function"].get("name")
            func_args = accumulated["function"].get("arguments", "") # arguments must be str

            function_chunk: ChatCompletionToolCallFunctionChunk = {
                "arguments": func_args
            }
            if func_name is not None: # name is Optional[str]
                function_chunk["name"] = func_name

            # Create a tool call chunk with the correct type
            # Type for ChatCompletionToolCallChunk is Literal["function"]
            # accumulated["type"] is derived from tool_call.get("type", "function"), so it should be "function".
            tool_call_chunk: ChatCompletionToolCallChunk = {
                "index": call_index,
                "id": accumulated.get("id"), # id is Optional[str]
                "type": "function", # Explicitly "function" as per type
                "function": function_chunk
            }
            processed_calls.append(tool_call_chunk)

        return processed_calls if processed_calls else None
