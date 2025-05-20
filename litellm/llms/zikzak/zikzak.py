import os
import json
import logging
from typing import Dict, List, Union, Callable, AsyncGenerator

import litellm
from litellm.utils import CustomLLM
from litellm.types.utils import ModelResponse
from litellm.types.completion import Completion
from litellm.types.chat_completion import ChatCompletion

# Set up logging
logger = logging.getLogger(__name__)

class ZikZakCompletion(CustomLLM):
    """
    ZikZak Provider - Orchestration layer for using different models based on task type
    
    Uses: 
    - Claude 3.7 for scaffolding tasks (folder/file creation)
    - GPT 4.1 for complex code tasks
    """
    
    def __init__(self) -> None:
        super().__init__()
        self.rules = {}
        self._load_rules()
    
    def _load_rules(self) -> None:
        """Load the orchestration rules from the rules file if it exists"""
        rules_path = os.path.join(os.path.dirname(__file__), "rules.json")
        try:
            if os.path.exists(rules_path):
                with open(rules_path, "r") as f:
                    self.rules = json.load(f)
            else:
                # Default rules when file doesn't exist
                self.rules = {
                    "scaffolding_model": "github_copilot/gpt-4.1",
                    "code_model": "github_copilot/claude-3.7-sonnet",
                    "task_routing": {
                        "scaffolding": ["create_directory", "edit_file", "generate_files"],
                        "code": ["implement", "debug", "optimize"]
                    }
                }
                # Create rules file with default rules
                with open(rules_path, "w") as f:
                    json.dump(self.rules, f, indent=2)
        except Exception as e:
            logger.error(f"Error loading ZikZak rules: {e}")
            # Fallback to default rules
            self.rules = {
                "scaffolding_model": "github_copilot/gpt-4.1",
                "code_model": "github_copilot/claude-3.7-sonnet",
                "task_routing": {
                    "scaffolding": ["create_directory", "edit_file", "generate_files"],
                    "code": ["implement", "debug", "optimize"]
                }
            }
    
    def _determine_model(self, messages: List[Dict]) -> str:
        """Determine which model to use based on task type detected in messages"""
        
        # Default to scaffolding model
        model_to_use = self.rules.get("scaffolding_model", "github_copilot/claude-3.7-sonnet")
        
        if len(messages) == 0:
            return model_to_use
            
        # Check the last user message to determine task type
        last_user_msg = None
        for msg in reversed(messages):
            if msg.get("role") == "user":
                last_user_msg = msg.get("content", "")
                break
        
        if not last_user_msg:
            return model_to_use
            
        # Check for scaffolding keywords
        scaffolding_indicators = [
            "create directory", "make folder", "new file", "create file",
            "scaffold", "project structure", "file structure"
        ]
        
        # Check for code complexity indicators
        code_indicators = [
            "implement", "algorithm", "optimize", "debug", "complex",
            "performance", "refactor"
        ]
        
        # Simple routing logic - can be enhanced
        if any(indicator in last_user_msg.lower() for indicator in scaffolding_indicators):
            return self.rules.get("scaffolding_model", "github_copilot/gpt-4.1")
        elif any(indicator in last_user_msg.lower() for indicator in code_indicators):
            return self.rules.get("code_model", "github_copilot/claude-3.7-sonnet")
        
        return model_to_use
    
    def completion(self, 
                  model: str, 
                  messages: List[Dict], 
                  model_response: ModelResponse,
                  print_verbose: Callable,
                  encoding,
                  logging_obj,
                  optional_params=None,
                  litellm_params=None,
                  logger_fn=None) -> Union[Completion, ChatCompletion, AsyncGenerator[Completion, None]]:
        """
        Orchestrates requests to the appropriate provider based on the task type
        """
        # Determine which model to use based on the task
        selected_model = self._determine_model(messages)
        
        print_verbose(f"ZikZak routing to model: {selected_model}")
        
        # Use the selected model
        response = litellm.completion(
            model=selected_model,
            messages=messages,
            stream=optional_params.get("stream", False) if optional_params else False,
            api_base=optional_params.get("api_base", None) if optional_params else None,
            api_key=optional_params.get("api_key", None) if optional_params else None,
            **(optional_params or {})
        )
        
        # Add metadata about the orchestration
        if hasattr(response, "_hidden_params"):
            response._hidden_params["orchestrated_by"] = "zikzak"
            response._hidden_params["original_model_used"] = selected_model
        
        return response
    
    async def acompletion(self,
                         model: str, 
                         messages: List[Dict], 
                         model_response: ModelResponse,
                         print_verbose: Callable,
                         encoding,
                         logging_obj,
                         optional_params=None,
                         litellm_params=None,
                         logger_fn=None) -> Union[Completion, ChatCompletion, AsyncGenerator[Completion, None]]:
        """
        Async version of the completion method
        """
        # Determine which model to use based on the task
        selected_model = self._determine_model(messages)
        
        print_verbose(f"ZikZak routing to model: {selected_model}")
        
        # Use the selected model
        response = await litellm.acompletion(
            model=selected_model,
            messages=messages,
            stream=optional_params.get("stream", False) if optional_params else False,
            api_base=optional_params.get("api_base", None) if optional_params else None,
            api_key=optional_params.get("api_key", None) if optional_params else None,
            **(optional_params or {})
        )
        
        # Add metadata about the orchestration
        if hasattr(response, "_hidden_params"):
            response._hidden_params["orchestrated_by"] = "zikzak" 
            response._hidden_params["original_model_used"] = selected_model
        
        return response