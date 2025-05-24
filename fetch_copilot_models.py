#!/usr/bin/env python3
"""
Script to fetch GitHub Copilot models dynamically and update the config.yaml file.
"""

import json
import os
import sys
import yaml
from datetime import datetime
from typing import Dict, List, Any, Optional

import httpx

# Add the litellm package to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from litellm.llms.github_copilot.authenticator import Authenticator
from litellm._logging import verbose_logger


class CopilotModelFetcher:
    def __init__(self, config_path: str = "config.yaml"):
        """Initialize the model fetcher with config path."""
        self.config_path = config_path
        self.authenticator = Authenticator()
        self.models_endpoint = "https://api.githubcopilot.com/models"
        
    def get_auth_headers(self) -> Dict[str, str]:
        """Get authentication headers for GitHub Copilot API."""
        try:
            api_key = self.authenticator.get_api_key()
            return {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Editor-Version": "vscode/1.85.1",
                "Editor-Plugin-Version": "copilot/1.155.0",
                "User-Agent": "GithubCopilot/1.155.0",
                "Copilot-Integration-Id": "vscode-chat",
            }
        except Exception as e:
            verbose_logger.error(f"Failed to get authentication headers: {e}")
            raise
    
    def fetch_models(self) -> List[Dict[str, Any]]:
        """Fetch available models from GitHub Copilot API."""
        headers = self.get_auth_headers()
        
        try:
            with httpx.Client() as client:
                response = client.get(self.models_endpoint, headers=headers)
                response.raise_for_status()
                
                data = response.json()
                if "data" in data:
                    return data["data"]
                else:
                    verbose_logger.error(f"Unexpected response format: {data}")
                    return []
                    
        except httpx.HTTPStatusError as e:
            verbose_logger.error(f"HTTP error fetching models: {e}")
            verbose_logger.error(f"Response: {e.response.text}")
            raise
        except Exception as e:
            verbose_logger.error(f"Error fetching models: {e}")
            raise
    
    def convert_model_to_litellm_config(self, model: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Convert a GitHub Copilot model to LiteLLM config format."""
        try:
            # Skip models that are not chat-enabled or not picker-enabled
            if not model.get("model_picker_enabled", False):
                return None
                
            capabilities = model.get("capabilities", {})
            if capabilities.get("type") != "chat":
                return None
            
            model_id = model.get("id")
            if not model_id:
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
            }
            
            # Add token limits if available
            if "max_context_window_tokens" in limits:
                model_info["max_tokens"] = limits["max_context_window_tokens"]
                # Estimate input/output split if not specified
                max_tokens = limits["max_context_window_tokens"]
                model_info["max_input_tokens"] = int(max_tokens * 0.75)  # 75% for input
                model_info["max_output_tokens"] = int(max_tokens * 0.25)  # 25% for output
            
            if "max_output_tokens" in limits:
                model_info["max_output_tokens"] = limits["max_output_tokens"]
            
            # Add capability flags
            if supports.get("vision", False):
                model_info["supports_vision"] = True
            
            if supports.get("tool_calls", False):
                model_info["supports_function_calling"] = True
                model_info["supports_tool_calls"] = True
            
            if supports.get("parallel_tool_calls", False):
                model_info["supports_parallel_function_calling"] = True
            
            if supports.get("structured_outputs", False):
                model_info["supports_structured_outputs"] = True
            
            if supports.get("response_schema", False):
                model_info["supports_response_schema"] = True
            
            # Most models support system messages
            model_info["supports_system_messages"] = True
            
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
            
            return model_config
            
        except Exception as e:
            verbose_logger.error(f"Error converting model {model}: {e}")
            return None
    
    def load_current_config(self) -> Dict[str, Any]:
        """Load the current config.yaml file."""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            verbose_logger.warning(f"Config file {self.config_path} not found, creating new config")
            return {"model_list": []}
        except Exception as e:
            verbose_logger.error(f"Error loading config: {e}")
            raise
    
    def update_config(self, new_models: List[Dict[str, Any]]) -> None:
        """Update the config.yaml file with new models."""
        try:
            # Load current config
            config = self.load_current_config()
            
            # Ensure model_list exists
            if "model_list" not in config:
                config["model_list"] = []
            
            # Remove existing GitHub Copilot models
            config["model_list"] = [
                model for model in config["model_list"]
                if not model.get("model_name", "").startswith("github_copilot/")
            ]
            
            # Add new models
            config["model_list"].extend(new_models)
            
            # Ensure litellm_settings exist
            if "litellm_settings" not in config:
                config["litellm_settings"] = {}
            
            # Add cache config if not present
            if "cache_config" not in config["litellm_settings"]:
                config["litellm_settings"]["cache_config"] = {
                    "type": "redis",
                    "host": "redis",
                    "port": 6379,
                    "password": "",
                    "db": 0
                }
            
            # Ensure general_settings exist
            if "general_settings" not in config:
                config["general_settings"] = {}
            
            # Add GitHub Copilot settings
            if "github_copilot" not in config["general_settings"]:
                config["general_settings"]["github_copilot"] = {
                    "token_dir": "/github_auth",
                    "cache_models": True
                }
            
            # Write updated config
            with open(self.config_path, 'w') as f:
                yaml.dump(config, f, default_flow_style=False, sort_keys=False, indent=2)
            
            verbose_logger.info(f"Updated config with {len(new_models)} GitHub Copilot models")
            
        except Exception as e:
            verbose_logger.error(f"Error updating config: {e}")
            raise
    
    def run(self) -> None:
        """Main function to fetch models and update config."""
        try:
            print("Fetching GitHub Copilot models...")
            verbose_logger.info("Starting GitHub Copilot model fetch")
            
            # Fetch models from API
            models = self.fetch_models()
            print(f"Found {len(models)} models from GitHub Copilot API")
            
            # Convert to LiteLLM format
            converted_models = []
            for model in models:
                converted = self.convert_model_to_litellm_config(model)
                if converted:
                    converted_models.append(converted)
                    print(f"Added model: {converted['model_name']}")
            
            print(f"Successfully converted {len(converted_models)} models")
            
            # Update config
            self.update_config(converted_models)
            print(f"Updated {self.config_path} with {len(converted_models)} GitHub Copilot models")
            
            # Print summary
            print("\nUpdated models:")
            for model in converted_models:
                model_name = model["model_name"]
                model_info = model["litellm_params"]["model_info"]
                capabilities = []
                
                if model_info.get("supports_vision"):
                    capabilities.append("vision")
                if model_info.get("supports_function_calling"):
                    capabilities.append("function_calling")
                if model_info.get("supports_structured_outputs"):
                    capabilities.append("structured_outputs")
                
                caps_str = ", ".join(capabilities) if capabilities else "basic_chat"
                max_tokens = model_info.get("max_tokens", "unknown")
                print(f"  {model_name}: {caps_str} (max_tokens: {max_tokens})")
            
        except Exception as e:
            verbose_logger.error(f"Failed to fetch and update models: {e}")
            print(f"Error: {e}")
            sys.exit(1)


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Fetch GitHub Copilot models and update config")
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to config.yaml file (default: config.yaml)"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        import logging
        logging.basicConfig(level=logging.DEBUG)
    
    fetcher = CopilotModelFetcher(config_path=args.config)
    fetcher.run()


if __name__ == "__main__":
    main()