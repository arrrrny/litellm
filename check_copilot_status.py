#!/usr/bin/env python3
"""
GitHub Copilot Model Status Checker
Quick verification of model availability and tool calling support
"""

import json
import sys
import asyncio
from datetime import datetime
from typing import Dict, List, Any, Optional

import httpx
import yaml

# Add the litellm package to the path
sys.path.insert(0, '.')
from litellm.llms.github_copilot.authenticator import Authenticator


class CopilotStatusChecker:
    def __init__(self):
        self.authenticator = Authenticator()
        self.api_base = "https://api.githubcopilot.com"
        self.test_tools = [
            {
                "type": "function",
                "function": {
                    "name": "test_tool",
                    "description": "Simple test tool",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "input": {"type": "string", "description": "Test input"}
                        },
                        "required": ["input"]
                    }
                }
            }
        ]
        
    def get_headers(self) -> Dict[str, str]:
        """Get authentication headers."""
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
            print(f"❌ Authentication failed: {e}")
            sys.exit(1)
    
    async def test_model_tool_calling(self, model: str, client: httpx.AsyncClient) -> Dict[str, Any]:
        """Test tool calling for a specific model."""
        payload = {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "You are a helpful assistant. Use the test tool with input 'hello'."
                },
                {
                    "role": "user", 
                    "content": "Use the test tool"
                }
            ],
            "tools": self.test_tools,
            "tool_choice": "auto",
            "max_tokens": 100
        }
        
        try:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                choices = data.get("choices", [])
                if choices and choices[0].get("message", {}).get("tool_calls"):
                    return {"status": "✅ Working", "code": 200, "tool_calls": True}
                else:
                    return {"status": "⚠️ No Tool Calls", "code": 200, "tool_calls": False}
            else:
                return {"status": f"❌ HTTP {response.status_code}", "code": response.status_code, "tool_calls": False}
                
        except httpx.TimeoutException:
            return {"status": "❌ Timeout", "code": 0, "tool_calls": False}
        except Exception as e:
            return {"status": f"❌ Error: {str(e)[:50]}", "code": 0, "tool_calls": False}
    
    def load_config_models(self) -> List[str]:
        """Load model names from config.yaml."""
        try:
            with open("config.yaml", "r") as f:
                config = yaml.safe_load(f)
                models = []
                for model_config in config.get("model_list", []):
                    model_name = model_config.get("model_name", "")
                    if model_name.startswith("github_copilot/"):
                        # Extract just the model name without prefix
                        models.append(model_name.replace("github_copilot/", ""))
                return sorted(models)
        except Exception as e:
            print(f"❌ Could not load config.yaml: {e}")
            return []
    
    def get_function_calling_models(self) -> List[str]:
        """Get models that claim to support function calling."""
        try:
            with open("config.yaml", "r") as f:
                config = yaml.safe_load(f)
                models = []
                for model_config in config.get("model_list", []):
                    model_name = model_config.get("model_name", "")
                    if model_name.startswith("github_copilot/"):
                        model_info = model_config.get("litellm_params", {}).get("model_info", {})
                        if model_info.get("supports_function_calling", False):
                            models.append(model_name.replace("github_copilot/", ""))
                return sorted(models)
        except Exception as e:
            print(f"❌ Could not analyze function calling support: {e}")
            return []
    
    async def check_all_models(self) -> None:
        """Check status of all configured models."""
        print("🔍 GitHub Copilot Model Status Checker")
        print("=" * 50)
        print(f"⏰ Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Load models
        all_models = self.load_config_models()
        function_models = self.get_function_calling_models()
        
        if not all_models:
            print("❌ No models found in config.yaml")
            return
        
        print(f"📊 Found {len(all_models)} total models, {len(function_models)} with function calling")
        print()
        
        headers = self.get_headers()
        
        async with httpx.AsyncClient(headers=headers) as client:
            print("🧪 Testing Tool Calling Capability:")
            print("-" * 40)
            
            working_models = []
            failed_models = []
            
            for model in function_models:
                print(f"Testing {model:<20} ... ", end="", flush=True)
                result = await self.test_model_tool_calling(model, client)
                print(result["status"])
                
                if result["tool_calls"]:
                    working_models.append(model)
                else:
                    failed_models.append((model, result["status"]))
                
                # Small delay to avoid rate limiting
                await asyncio.sleep(0.5)
        
        print()
        print("📈 Summary:")
        print("-" * 20)
        print(f"✅ Working Models: {len(working_models)}/{len(function_models)} ({len(working_models)/len(function_models)*100:.1f}%)")
        
        if working_models:
            print("\n🟢 Recommended for Tool Calling:")
            for model in working_models:
                print(f"   • {model}")
        
        if failed_models:
            print(f"\n🔴 Not Working ({len(failed_models)} models):")
            for model, status in failed_models:
                print(f"   • {model:<20} {status}")
        
        print()
        print("💡 Usage: Use working models for tool calling applications")
        print("🔄 Re-run this script periodically to check for updates")


async def main():
    """Main entry point."""
    checker = CopilotStatusChecker()
    await checker.check_all_models()


if __name__ == "__main__":
    asyncio.run(main())