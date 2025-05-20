from typing import Optional, Tuple, List, Union, AsyncIterator, Iterator, Any, Dict
import json
import httpx

from litellm.llms.openai.openai import OpenAIConfig
from litellm.utils import ModelResponse, Choices, StreamingChoices, Delta # Added Delta
from litellm.llms.base_llm.base_model_iterator import BaseModelResponseIterator
from litellm.llms.base_llm.chat.transformation import BaseLLMException, LiteLLMLoggingObj
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
