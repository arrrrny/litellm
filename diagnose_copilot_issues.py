#!/usr/bin/env python3
"""
GitHub Copilot Tool Calling Diagnostic Script
Tests different request formats to understand model failures
"""

import json
import os
import sys
import asyncio
from datetime import datetime
from typing import Dict, List, Any, Optional

import httpx
import yaml

# Add the litellm package to the path
sys.path.insert(0, '.')
from litellm.llms.github_copilot.authenticator import Authenticator


class CopilotDiagnostic:
    def __init__(self):
        self.authenticator = Authenticator()
        self.api_base = "https://api.githubcopilot.com"
        
    def get_headers_variants(self, token: str) -> List[Dict[str, Any]]:
        """Get different header variants to test."""
        return [
            # Original test headers
            {
                "name": "vscode_original",
                "headers": {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                    "Editor-Version": "vscode/1.85.1",
                    "Editor-Plugin-Version": "copilot/1.155.0",
                    "User-Agent": "GithubCopilot/1.155.0",
                    "Copilot-Integration-Id": "vscode-chat",
                }
            },
            # CodeCompanion style headers
            {
                "name": "neovim_style",
                "headers": {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                    "Copilot-Integration-Id": "vscode-chat",
                    "Editor-Version": "Neovim/0.9.0",
                }
            },
            # Minimal headers
            {
                "name": "minimal",
                "headers": {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                }
            },
            # With vision header
            {
                "name": "with_vision",
                "headers": {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                    "Copilot-Integration-Id": "vscode-chat",
                    "Editor-Version": "vscode/1.85.1",
                    "Copilot-Vision-Request": "true",
                }
            }
        ]
    
    def get_request_variants(self) -> List[Dict[str, Any]]:
        """Get different request payload variants."""
        base_tool = {
            "type": "function",
            "function": {
                "name": "test_calculation",
                "description": "Perform a simple calculation",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "expression": {
                            "type": "string",
                            "description": "Mathematical expression"
                        }
                    },
                    "required": ["expression"]
                }
            }
        }
        
        return [
            # Original format
            {
                "name": "standard",
                "payload": {
                    "model": "MODEL_PLACEHOLDER",
                    "messages": [
                        {"role": "system", "content": "You are a helpful assistant. Use tools when appropriate."},
                        {"role": "user", "content": "Calculate 5 * 3"}
                    ],
                    "tools": [base_tool],
                    "tool_choice": "auto"
                }
            },
            # Without system message
            {
                "name": "no_system",
                "payload": {
                    "model": "MODEL_PLACEHOLDER",
                    "messages": [
                        {"role": "user", "content": "Calculate 5 * 3 using the test_calculation tool"}
                    ],
                    "tools": [base_tool],
                    "tool_choice": "auto"
                }
            },
            # With max_tokens
            {
                "name": "with_max_tokens",
                "payload": {
                    "model": "MODEL_PLACEHOLDER",
                    "messages": [
                        {"role": "user", "content": "Calculate 5 * 3"}
                    ],
                    "tools": [base_tool],
                    "tool_choice": "auto",
                    "max_tokens": 1000
                }
            },
            # Force tool choice
            {
                "name": "force_tool",
                "payload": {
                    "model": "MODEL_PLACEHOLDER",
                    "messages": [
                        {"role": "user", "content": "Calculate 5 * 3"}
                    ],
                    "tools": [base_tool],
                    "tool_choice": {"type": "function", "function": {"name": "test_calculation"}}
                }
            },
            # With temperature
            {
                "name": "with_temp",
                "payload": {
                    "model": "MODEL_PLACEHOLDER",
                    "messages": [
                        {"role": "user", "content": "Calculate 5 * 3"}
                    ],
                    "tools": [base_tool],
                    "tool_choice": "auto",
                    "temperature": 0.1
                }
            },
            # No tools (baseline)
            {
                "name": "no_tools",
                "payload": {
                    "model": "MODEL_PLACEHOLDER",
                    "messages": [
                        {"role": "user", "content": "What is 5 * 3? Just answer with the number."}
                    ]
                }
            }
        ]
    
    async def get_model_capabilities(self, token: str) -> Dict[str, Any]:
        """Fetch model capabilities from GitHub Copilot API."""
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Editor-Version": "vscode/1.85.1",
            "Editor-Plugin-Version": "copilot/1.155.0",
            "User-Agent": "GithubCopilot/1.155.0",
            "Copilot-Integration-Id": "vscode-chat",
        }
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{self.api_base}/models", headers=headers)
                response.raise_for_status()
                
                data = response.json()
                models = {}
                
                for model in data.get("data", []):
                    if model.get("model_picker_enabled", False):
                        model_id = model.get("id")
                        capabilities = model.get("capabilities", {})
                        supports = capabilities.get("supports", {})
                        
                        models[model_id] = {
                            "supports_tool_calls": supports.get("tool_calls", False),
                            "supports_streaming": supports.get("streaming", False),
                            "supports_vision": supports.get("vision", False),
                            "supports_parallel_tool_calls": supports.get("parallel_tool_calls", False),
                            "type": capabilities.get("type"),
                            "limits": capabilities.get("limits", {})
                        }
                
                return models
        except Exception as e:
            print(f"Error fetching model capabilities: {e}")
            return {}
    
    async def test_model_variant(self, model: str, header_variant: Dict, request_variant: Dict, client: httpx.AsyncClient) -> Dict[str, Any]:
        """Test a specific model with header and request variants."""
        payload = request_variant["payload"].copy()
        payload["model"] = model
        
        try:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                json=payload,
                headers=header_variant["headers"],
                timeout=30.0
            )
            
            result = {
                "status_code": response.status_code,
                "success": response.status_code == 200,
                "has_tool_calls": False,
                "response_size": len(response.content),
                "error": None
            }
            
            if response.status_code == 200:
                try:
                    data = response.json()
                    choices = data.get("choices", [])
                    if choices:
                        message = choices[0].get("message", {})
                        tool_calls = message.get("tool_calls", [])
                        result["has_tool_calls"] = len(tool_calls) > 0
                        result["choice_count"] = len(choices)
                        result["finish_reason"] = choices[0].get("finish_reason")
                        if tool_calls:
                            result["tool_call_count"] = len(tool_calls)
                except Exception as parse_error:
                    result["error"] = f"JSON parse error: {parse_error}"
            else:
                try:
                    error_text = response.text[:200]
                    result["error"] = error_text
                except:
                    result["error"] = f"HTTP {response.status_code}"
                    
            return result
            
        except httpx.TimeoutException:
            return {"status_code": 0, "success": False, "error": "Timeout", "has_tool_calls": False}
        except Exception as e:
            return {"status_code": 0, "success": False, "error": str(e)[:100], "has_tool_calls": False}
    
    async def run_comprehensive_diagnosis(self):
        """Run comprehensive diagnosis across models, headers, and request formats."""
        print("🔬 GitHub Copilot Comprehensive Diagnostic")
        print("=" * 60)
        print(f"⏰ Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Get authentication token
        try:
            token = self.authenticator.get_api_key()
            print("✅ Authentication successful")
        except Exception as e:
            print(f"❌ Authentication failed: {e}")
            return
        
        # Get model capabilities
        print("📋 Fetching model capabilities...")
        capabilities = await self.get_model_capabilities(token)
        
        if not capabilities:
            print("❌ Could not fetch model capabilities")
            return
        
        print(f"📊 Found {len(capabilities)} models")
        
        # Filter to tool-calling models
        tool_models = {k: v for k, v in capabilities.items() if v.get("supports_tool_calls", False)}
        print(f"🔧 {len(tool_models)} models claim tool calling support")
        print()
        
        # Get test variants
        header_variants = self.get_headers_variants(token)
        request_variants = self.get_request_variants()
        
        print(f"🧪 Testing {len(header_variants)} header variants × {len(request_variants)} request variants")
        print()
        
        # Test models
        results = {}
        
        async with httpx.AsyncClient() as client:
            for model_name in sorted(tool_models.keys()):
                print(f"🎯 Testing model: {model_name}")
                print("-" * 40)
                
                model_results = {}
                
                for header_variant in header_variants:
                    for request_variant in request_variants:
                        test_name = f"{header_variant['name']}_{request_variant['name']}"
                        
                        print(f"   {test_name:<25} ... ", end="", flush=True)
                        
                        result = await self.test_model_variant(
                            model_name, header_variant, request_variant, client
                        )
                        
                        model_results[test_name] = result
                        
                        # Display result
                        if result["success"]:
                            if result["has_tool_calls"]:
                                print("✅ TOOL CALLS")
                            else:
                                print("⚠️ NO TOOLS") 
                        else:
                            print(f"❌ {result['status_code']} {result.get('error', '')[:20]}")
                        
                        # Small delay to avoid rate limiting
                        await asyncio.sleep(0.2)
                
                results[model_name] = model_results
                print()
        
        # Analyze results
        print("📈 ANALYSIS")
        print("=" * 30)
        
        # Find working combinations
        working_combinations = {}
        for model_name, model_results in results.items():
            working = []
            for test_name, result in model_results.items():
                if result["success"] and result["has_tool_calls"]:
                    working.append(test_name)
            
            if working:
                working_combinations[model_name] = working
        
        print(f"✅ Models with working tool calls: {len(working_combinations)}")
        for model, combinations in working_combinations.items():
            print(f"   {model}: {len(combinations)} working combinations")
            for combo in combinations[:3]:  # Show first 3
                print(f"     • {combo}")
            if len(combinations) > 3:
                print(f"     ... and {len(combinations) - 3} more")
        
        print()
        
        # Find models that work with any combination
        broken_models = []
        for model_name, model_results in results.items():
            has_any_success = any(r["success"] and r["has_tool_calls"] for r in model_results.values())
            if not has_any_success:
                broken_models.append(model_name)
        
        print(f"❌ Models that don't work with any combination: {len(broken_models)}")
        for model in broken_models:
            print(f"   {model}")
        
        # Error pattern analysis
        print()
        print("🔍 ERROR PATTERNS")
        print("-" * 20)
        
        error_patterns = {}
        for model_name, model_results in results.items():
            for test_name, result in model_results.items():
                if not result["success"]:
                    error_key = f"HTTP_{result['status_code']}"
                    if error_key not in error_patterns:
                        error_patterns[error_key] = {"models": set(), "count": 0}
                    error_patterns[error_key]["models"].add(model_name)
                    error_patterns[error_key]["count"] += 1
        
        for error, info in sorted(error_patterns.items()):
            print(f"{error}: {info['count']} failures across {len(info['models'])} models")
            for model in sorted(info["models"]):
                print(f"   • {model}")
        
        # Save detailed results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        results_file = f"copilot_diagnosis_{timestamp}.json"
        
        with open(results_file, "w") as f:
            json.dump({
                "timestamp": timestamp,
                "capabilities": capabilities,
                "test_results": results,
                "working_combinations": working_combinations,
                "broken_models": broken_models,
                "error_patterns": {k: {"models": list(v["models"]), "count": v["count"]} for k, v in error_patterns.items()}
            }, f, indent=2)
        
        print()
        print(f"💾 Detailed results saved to: {results_file}")
        print()
        print("🎯 RECOMMENDATIONS")
        print("-" * 20)
        
        if working_combinations:
            print("Use these model + format combinations for reliable tool calling:")
            for model, combinations in list(working_combinations.items())[:3]:
                best_combo = combinations[0] if combinations else "none"
                print(f"  • {model} with {best_combo}")
        else:
            print("❌ No working tool calling combinations found!")
            print("   This suggests a fundamental API or authentication issue.")


async def main():
    """Main entry point."""
    diagnostic = CopilotDiagnostic()
    await diagnostic.run_comprehensive_diagnosis()


if __name__ == "__main__":
    asyncio.run(main())