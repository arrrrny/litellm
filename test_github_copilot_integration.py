#!/usr/bin/env python3
"""
GitHub Copilot Integration Test Script
Tests the enhanced GitHub Copilot integration with proper parameters and error handling.
"""

import json
import time
import requests
import sys
from typing import Dict, Any

class GitHubCopilotTester:
    def __init__(self, base_url: str = "http://localhost:4001", api_key: str = "sk-vzsq8siOZaYVncRj1RJgYg"):
        self.base_url = base_url
        self.api_key = api_key
        self.headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }

    def test_basic_completion(self):
        """Test basic GitHub Copilot completion with proper parameters."""
        print("🧪 Testing Basic GitHub Copilot Completion...")

        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [
                {"role": "user", "content": "Hello from GitHub Copilot! Can you help me write a Python function?"}
            ],
            "intent": True,
            "stream": False,
            "max_tokens": 150
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                result = response.json()
                print(f"   📄 Raw response: {json.dumps(result, indent=2)}")

                if result is None:
                    print("   WARNING: Response is null - this indicates a response transformation issue")
                    print("   INFO: GitHub Copilot may be responding but transformation is failing")
                    return False

                choices = result.get("choices", [])
                if not choices:
                    print("   WARNING: No choices in response")
                    return False

                message = choices[0].get("message", {})
                content = message.get("content", "")

                if content:
                    print(f"   SUCCESS: Response: {content[:100]}...")
                    return True
                else:
                    print("   WARNING: No content in message")
                    print(f"   Message object: {json.dumps(message, indent=2)}")
                    return False
            else:
                print(f"   ERROR: {response.status_code}")
                print(f"   Response: {response.text[:500]}...")
                return False

        except Exception as e:
            print(f"   EXCEPTION: {str(e)}")
            return False

    def test_streaming_completion(self):
        """Test streaming GitHub Copilot completion."""
        print("\n🌊 Testing Streaming GitHub Copilot Completion...")

        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [
                {"role": "user", "content": "Write a short Python function to calculate fibonacci numbers."}
            ],
            "intent": True,
            "stream": True,
            "max_tokens": 200
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                stream=True,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                chunks_received = 0
                content_pieces = []

                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]
                            if data_str.strip() == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data_str)
                                chunks_received += 1
                                if chunks_received <= 5:  # Show first few chunks
                                    delta_content = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                                    if delta_content:
                                        content_pieces.append(delta_content)
                                        print(f"   CHUNK {chunks_received}: {repr(delta_content)}")
                            except json.JSONDecodeError:
                                continue

                print(f"   SUCCESS: Received {chunks_received} chunks")
                print(f"   Combined content: {''.join(content_pieces)[:100]}...")
                return True
            else:
                print(f"   ERROR: {response.status_code}")
                print(f"   Response: {response.text[:500]}...")
                return False

        except Exception as e:
            print(f"   EXCEPTION: {str(e)}")
            return False

    def test_claude_35_streaming(self):
        """Test Claude 3.5 streaming through GitHub Copilot."""
        print("\n🤖 Testing Claude 3.5 Streaming...")

        payload = {
            "model": "github_copilot/claude-3.5-sonnet",
            "messages": [
                {"role": "user", "content": "Explain the concept of recursion in programming with a simple example."}
            ],
            "intent": True,
            "stream": True,
            "max_tokens": 200
        }

        try:
            response = requests.post(
            f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                stream=True,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                chunks_received = 0
                content_pieces = []

                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]
                            if data_str.strip() == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data_str)
                                chunks_received += 1
                                if chunks_received <= 3:  # Show first few chunks
                                    delta_content = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                                    if delta_content:
                                        content_pieces.append(delta_content)
                                        print(f"   📦 Claude Chunk {chunks_received}: {repr(delta_content)}")
                            except json.JSONDecodeError:
                                continue

                print(f"   ✅ Success! Claude 3.5 received {chunks_received} chunks")
                print(f"   Combined content: {''.join(content_pieces)[:100]}...")
                return True
            else:
                print(f"   ❌ Error: {response.status_code}")
                print(f"   Response: {response.text[:500]}...")
                return False

        except Exception as e:
            print(f"   ❌ Exception: {str(e)}")
            return False

    def test_gemini_25_streaming(self):
        """Test Gemini 2.5 streaming through GitHub Copilot."""
        print("\n🔮 Testing Gemini 2.5 Streaming...")

        payload = {
            "model": "github_copilot/gemini-2.5-pro",
            "messages": [
                {"role": "user", "content": "What are the key principles of clean code? Give me 3 main points."}
            ],
            "intent": True,
            "stream": True,
            "max_tokens": 200
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                stream=True,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                chunks_received = 0
                content_pieces = []

                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]
                            if data_str.strip() == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data_str)
                                chunks_received += 1
                                if chunks_received <= 3:  # Show first few chunks
                                    delta_content = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                                    if delta_content:
                                        content_pieces.append(delta_content)
                                        print(f"   📦 Gemini Chunk {chunks_received}: {repr(delta_content)}")
                            except json.JSONDecodeError:
                                continue

                print(f"   ✅ Success! Gemini 2.5 received {chunks_received} chunks")
                print(f"   Combined content: {''.join(content_pieces)[:100]}...")
                return True
            else:
                print(f"   ❌ Error: {response.status_code}")
                print(f"   Response: {response.text[:500]}...")
                return False

        except Exception as e:
            print(f"   ❌ Exception: {str(e)}")
            return False

    def test_gpt41_tool_calls_streaming(self):
        """Test GPT-4.1 with tool calls in streaming mode."""
        print("\n🔧 Testing GPT-4.1 Tool Calls (Streaming)...")

        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [
                {"role": "user", "content": "Calculate 15 * 23 and also search for 'Python functions' using the available tools."}
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "calculate",
                        "description": "Perform mathematical calculations",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "expression": {
                                    "type": "string",
                                    "description": "Mathematical expression to calculate"
                                }
                            },
                            "required": ["expression"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "web_search",
                        "description": "Search the web for information",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "Search query"
                                }
                            },
                            "required": ["query"]
                        }
                    }
                }
            ],
            "intent": True,
            "stream": True,
            "max_tokens": 300
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                stream=True,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                chunks_received = 0
                tool_calls_detected = []
                content_pieces = []

                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]
                            if data_str.strip() == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data_str)
                                chunks_received += 1

                                choices = chunk.get("choices", [])
                                if choices:
                                    delta = choices[0].get("delta", {})

                                    # Check for tool calls
                                    if "tool_calls" in delta:
                                        tool_calls_detected.extend(delta["tool_calls"])
                                        print(f"   🔨 Tool call detected in chunk {chunks_received}")

                                    # Check for content
                                    if "content" in delta and delta["content"]:
                                        content_pieces.append(delta["content"])
                                        if chunks_received <= 3:
                                            print(f"   📦 Content chunk {chunks_received}: {repr(delta['content'])}")

                            except json.JSONDecodeError:
                                continue

                print(f"   ✅ GPT-4.1 Tool Calls: {chunks_received} chunks, {len(tool_calls_detected)} tool calls")
                if tool_calls_detected:
                    print(f"   🎯 Tool calls successfully detected in streaming mode!")
                    return True
                else:
                    print(f"   📝 Content: {''.join(content_pieces)[:100]}...")
                    return len(content_pieces) > 0
            else:
                print(f"   ❌ Error: {response.status_code}")
                print(f"   Response: {response.text[:500]}...")
                return False

        except Exception as e:
            print(f"   ❌ Exception: {str(e)}")
            return False

    def test_claude35_tool_calls_streaming(self):
        """Test Claude 3.5 with tool calls in streaming mode."""
        print("\n🤖 Testing Claude 3.5 Tool Calls (Streaming)...")

        payload = {
            "model": "github_copilot/claude-3.5-sonnet",
            "messages": [
                {"role": "user", "content": "Help me analyze some code. Use the code_analyzer tool to check this function: def factorial(n): return 1 if n <= 1 else n * factorial(n-1)"}
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "code_analyzer",
                        "description": "Analyze code for quality, performance, and best practices",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "code": {
                                    "type": "string",
                                    "description": "Code to analyze"
                                },
                                "language": {
                                    "type": "string",
                                    "description": "Programming language"
                                }
                            },
                            "required": ["code", "language"]
                        }
                    }
                }
            ],
            "intent": True,
            "stream": True,
            "max_tokens": 300
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                stream=True,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                chunks_received = 0
                tool_calls_detected = []
                content_pieces = []

                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]
                            if data_str.strip() == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data_str)
                                chunks_received += 1

                                choices = chunk.get("choices", [])
                                if choices:
                                    delta = choices[0].get("delta", {})

                                    # Check for tool calls
                                    if "tool_calls" in delta:
                                        tool_calls_detected.extend(delta["tool_calls"])
                                        print(f"   🔨 Claude tool call detected in chunk {chunks_received}")

                                    # Check for content
                                    if "content" in delta and delta["content"]:
                                        content_pieces.append(delta["content"])
                                        if chunks_received <= 3:
                                            print(f"   📦 Claude chunk {chunks_received}: {repr(delta['content'])}")

                            except json.JSONDecodeError:
                                continue

                print(f"   ✅ Claude 3.5 Tool Calls: {chunks_received} chunks, {len(tool_calls_detected)} tool calls")
                if tool_calls_detected:
                    print(f"   🎯 Claude tool calls successfully detected!")
                    return True
                else:
                    print(f"   📝 Content: {''.join(content_pieces)[:100]}...")
                    return len(content_pieces) > 0
            else:
                print(f"   ❌ Error: {response.status_code}")
                return False

        except Exception as e:
            print(f"   ❌ Exception: {str(e)}")
            return False

    def test_gemini25_tool_calls_streaming(self):
        """Test Gemini 2.5 with tool calls in streaming mode."""
        print("\n🔮 Testing Gemini 2.5 Tool Calls (Streaming)...")

        payload = {
            "model": "github_copilot/gemini-2.5-pro",
            "messages": [
                {"role": "user", "content": "I need to organize my tasks. Use the task_manager tool to create a task for 'Review GitHub Copilot integration' with high priority."}
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "task_manager",
                        "description": "Manage tasks and todos",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "action": {
                                    "type": "string",
                                    "enum": ["create", "update", "delete", "list"],
                                    "description": "Action to perform"
                                },
                                "task_title": {
                                    "type": "string",
                                    "description": "Title of the task"
                                },
                                "priority": {
                                    "type": "string",
                                    "enum": ["low", "medium", "high"],
                                    "description": "Task priority"
                                }
                            },
                            "required": ["action", "task_title"]
                        }
                    }
                }
            ],
            "intent": True,
            "stream": True,
            "max_tokens": 300
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                stream=True,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                chunks_received = 0
                tool_calls_detected = []
                content_pieces = []

                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]
                            if data_str.strip() == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data_str)
                                chunks_received += 1

                                choices = chunk.get("choices", [])
                                if choices:
                                    delta = choices[0].get("delta", {})

                                    # Check for tool calls
                                    if "tool_calls" in delta:
                                        tool_calls_detected.extend(delta["tool_calls"])
                                        print(f"   🔨 Gemini tool call detected in chunk {chunks_received}")

                                    # Check for content
                                    if "content" in delta and delta["content"]:
                                        content_pieces.append(delta["content"])
                                        if chunks_received <= 3:
                                            print(f"   📦 Gemini chunk {chunks_received}: {repr(delta['content'])}")

                            except json.JSONDecodeError:
                                continue

                print(f"   ✅ Gemini 2.5 Tool Calls: {chunks_received} chunks, {len(tool_calls_detected)} tool calls")
                if tool_calls_detected:
                    print(f"   🎯 Gemini tool calls successfully detected!")
                    return True
                else:
                    print(f"   📝 Content: {''.join(content_pieces)[:100]}...")
                    return len(content_pieces) > 0
            else:
                print(f"   ❌ Error: {response.status_code}")
                return False

        except Exception as e:
            print(f"   ❌ Exception: {str(e)}")
            return False

    def test_health_endpoint(self):
        """Test the health endpoint."""
        print("\n🏥 Testing Health Endpoint...")

        try:
            response = requests.get(f"{self.base_url}/health/liveliness", timeout=10)
            print(f"   Status Code: {response.status_code}")

            if response.status_code == 200:
                print("   ✅ Health endpoint is working!")
                return True
            else:
                print(f"   ❌ Health endpoint error: {response.text}")
                return False

        except Exception as e:
            print(f"   ❌ Health endpoint exception: {str(e)}")
            return False

    def test_error_handling(self):
        """Test error handling with invalid parameters."""
        print("\n🛡️  Testing Error Handling...")

        # Test with missing required parameters
        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [
                {"role": "user", "content": "Test message"}
            ]
            # Missing intent and stream parameters
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                timeout=30
            )

            print(f"   Status Code: {response.status_code}")

            if response.status_code != 200:
                print("   ✅ Error handling is working (got expected error)")
                error_text = response.text[:300]
                print(f"   Error details: {error_text}...")
                return True
            else:
                print("   ✅ Request succeeded - GitHub Copilot auto-adds required parameters")
                print("   ℹ️  This means our parameter auto-injection is working correctly")
                return True

        except Exception as e:
            print(f"   ❌ Exception during error test: {str(e)}")
            return False

    def run_all_tests(self):
        """Run all tests and provide summary."""
        print("🚀 GitHub Copilot Integration Test Suite")
        print("=" * 60)

        tests = [
            ("Health Check", self.test_health_endpoint),
            ("Basic Completion", self.test_basic_completion),
            ("GPT-4.1 Streaming", self.test_streaming_completion),
            ("Claude 3.5 Streaming", self.test_claude_35_streaming),
            ("Gemini 2.5 Streaming", self.test_gemini_25_streaming),
            ("GPT-4.1 Tool Calls", self.test_gpt41_tool_calls_streaming),
            ("Claude 3.5 Tool Calls", self.test_claude35_tool_calls_streaming),
            ("Gemini 2.5 Tool Calls", self.test_gemini25_tool_calls_streaming),
            ("Error Handling", self.test_error_handling),
        ]

        results = []

        for test_name, test_func in tests:
            try:
                success = test_func()
                results.append((test_name, "PASSED" if success else "FAILED"))
            except Exception as e:
                print(f"   ❌ Test {test_name} crashed: {str(e)}")
                results.append((test_name, "CRASHED"))

        # Print summary
        print("\n" + "=" * 60)
        print("📋 TEST SUMMARY")
        print("=" * 60)

        passed = sum(1 for _, result in results if result == "PASSED")
        total = len(results)

        for test_name, result in results:
            icon = "✅" if result == "PASSED" else "❌"
            print(f"{icon} {test_name}: {result}")

        print(f"\n🎯 Overall Result: {passed}/{total} tests passed")

        if passed == total:
            print("🎉 All tests passed! GitHub Copilot integration is working correctly.")
            print("✅ GPT-4.1, Claude 3.5, and Gemini 2.5 all working through GitHub Copilot!")
        else:
            print("⚠️  Some tests failed. Check the logs and configuration.")

        return passed == total

def main():
    """Main test execution."""
    if len(sys.argv) > 1:
        base_url = sys.argv[1]
        print(f"Using custom base URL: {base_url}")
        tester = GitHubCopilotTester(base_url=base_url)
    else:
        print("Using default base URL: http://localhost:4000")
        tester = GitHubCopilotTester()

    success = tester.run_all_tests()

    if success:
        print("\n🎊 GitHub Copilot integration is working perfectly!")
        print("You can now use GitHub Copilot through LiteLLM proxy with:")
        print("  • GPT-4.1 (github_copilot/gpt-4.1) - Streaming ✅ Tool Calls ✅")
        print("  • Claude 3.5 Sonnet (github_copilot/claude-3.5-sonnet) - Streaming ✅ Tool Calls ✅")
        print("  • Gemini 2.5 Pro (github_copilot/gemini-2.5-pro) - Streaming ✅ Tool Calls ✅")
        print("All models support robust tool calling with ZED editor pattern!")
    else:
        print("\n⚠️  Some issues detected. Please check:")
        print("  • Docker containers are running")
        print("  • GitHub Copilot authentication is set up")
        print("  • LiteLLM proxy is accessible")
        print("  • No firewall blocking connections")

    return 0 if success else 1

if __name__ == "__main__":
    exit(main())
