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
    def __init__(self, status_code: int, message: str):
        self.status_code = status_code
        self.message = message
        self.request = httpx.Request(method="POST", url="https://api.githubcopilot.com")
        self.response = httpx.Response(status_code=status_code, request=self.request)
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
                msg = err.get("error", {}).get("message", str(err))
            except json.JSONDecodeError:
                msg = raw_response.text
            raise GithubCopilotError(status_code=raw_response.status_code, message=msg)

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
        return GithubCopilotError(status_code=status_code, message=error_message)

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
            provider_specific_fields = None
            index = int(chunk.get("index", 0))

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

            return GenericStreamingChunk(
                text=text,
                tool_use=tool_use,
                is_finished=is_finished,
                finish_reason=finish_reason if finish_reason is not None else "",
                usage=usage,
                index=index,
                provider_specific_fields=provider_specific_fields,
            )
        except json.JSONDecodeError:
            raise ValueError(f"Failed to decode JSON from chunk: {chunk}")
        except Exception as e:
            raise ValueError(f"Error parsing chunk: {str(e)}; chunk: {chunk}")

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
