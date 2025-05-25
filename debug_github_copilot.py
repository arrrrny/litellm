#!/usr/bin/env python3
"""
GitHub Copilot Debug Script
Analyzes and debugs GitHub Copilot integration issues with detailed request/response logging.
"""

import json
import sys
import traceback
from typing import Dict, Any

try:
    import requests
except ImportError:
    print("Error: requests library not found. Install with: pip install requests")
    sys.exit(1)

class GitHubCopilotDebugger:
    def __init__(self, base_url: str = "http://localhost:4001", api_key: str = "sk-vzsq8siOZaYVncRj1RJgYg"):
        self.base_url = base_url
        self.api_key = api_key
        self.headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }

    def debug_request(self, payload: Dict[str, Any], test_name: str = "Unknown"):
        """Debug a specific request with detailed logging."""
        print(f"\n🔍 DEBUGGING: {test_name}")
        print("=" * 60)

        # Log the request
        print("📤 REQUEST DETAILS:")
        print(f"   URL: {self.base_url}/chat/completions")
        print(f"   Headers: {json.dumps(self.headers, indent=2)}")
        print(f"   Payload: {json.dumps(payload, indent=2)}")
        print()

        try:
            # Make the request
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers,
                json=payload,
                timeout=30
            )

            # Log the response
            print("📥 RESPONSE DETAILS:")
            print(f"   Status Code: {response.status_code}")
            print(f"   Headers: {dict(response.headers)}")
            print(f"   Content-Type: {response.headers.get('content-type', 'unknown')}")
            print()

            # Try to parse response as JSON
            try:
                response_json = response.json()
                print("📄 RESPONSE BODY (JSON):")
                print(json.dumps(response_json, indent=2))
            except json.JSONDecodeError:
                print("📄 RESPONSE BODY (RAW):")
                print(response.text)

            print()

            # Analyze the response
            if response.status_code == 200:
                print("✅ REQUEST SUCCESSFUL")
                return True, response
            else:
                print("❌ REQUEST FAILED")
                self.analyze_error(response)
                return False, response

        except Exception as e:
            print(f"💥 EXCEPTION OCCURRED:")
            print(f"   Type: {type(e).__name__}")
            print(f"   Message: {str(e)}")
            print("   Traceback:")
            print(traceback.format_exc())
            return False, None

    def analyze_error(self, response):
        """Analyze error response and provide suggestions."""
        print("\n🔬 ERROR ANALYSIS:")

        status_code = response.status_code

        if status_code == 400:
            print("   • BAD REQUEST - Common causes:")
            print("     - Missing required 'intent' parameter")
            print("     - Invalid model name format")
            print("     - Malformed request structure")
            print("     - Invalid authentication")

        elif status_code == 401:
            print("   • UNAUTHORIZED - Authentication issues:")
            print("     - Invalid API key")
            print("     - Expired GitHub Copilot token")
            print("     - Missing Authorization header")

        elif status_code == 403:
            print("   • FORBIDDEN - Permission issues:")
            print("     - GitHub Copilot not activated")
            print("     - Insufficient permissions")

        elif status_code == 404:
            print("   • NOT FOUND - Endpoint issues:")
            print("     - Incorrect API endpoint")
            print("     - Model not available")

        elif status_code == 429:
            print("   • RATE LIMITED:")
            print("     - Too many requests")
            print("     - Wait before retrying")

        elif status_code >= 500:
            print("   • SERVER ERROR:")
            print("     - GitHub Copilot service issues")
            print("     - Temporary outage")

        # Try to extract specific error details
        try:
            error_data = response.json()
            if "error" in error_data:
                error_obj = error_data["error"]
                if isinstance(error_obj, dict):
                    print("\n   📋 Specific Error Details:")
                    for key, value in error_obj.items():
                        print(f"     {key}: {value}")
        except:
            pass

    def test_minimal_request(self):
        """Test with minimal required parameters."""
        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [{"role": "user", "content": "Hello"}],
            "intent": True
        }
        return self.debug_request(payload, "Minimal Request")

    def test_with_streaming(self):
        """Test with streaming enabled."""
        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [{"role": "user", "content": "Hello"}],
            "intent": True,
            "stream": True
        }
        return self.debug_request(payload, "GPT-4.1 Streaming")

    def test_claude_35_streaming(self):
        """Test Claude 3.5 streaming."""
        payload = {
            "model": "github_copilot/claude-3.5-sonnet",
            "messages": [{"role": "user", "content": "Explain recursion briefly"}],
            "intent": True,
            "stream": True
        }
        return self.debug_request(payload, "Claude 3.5 Streaming")

    def test_gemini_25_streaming(self):
        """Test Gemini 2.5 streaming."""
        payload = {
            "model": "github_copilot/gemini-2.5-pro",
            "messages": [{"role": "user", "content": "What is clean code?"}],
            "intent": True,
            "stream": True
        }
        return self.debug_request(payload, "Gemini 2.5 Streaming")



    def test_original_failing_request(self):
        """Test the original failing request from the error logs."""
        payload = {
            "model": "github_copilot/gpt-4.1",
            "messages": [{"role": "user", "content": "Hello from GitHub Copilot!"}]
        }
        return self.debug_request(payload, "Original Failing Request")

    def check_authentication(self):
        """Check if GitHub Copilot authentication is working."""
        print("\n🔐 CHECKING AUTHENTICATION:")
        print("=" * 60)

        # Try to get copilot models
        try:
            response = requests.get(f"{self.base_url}/models", timeout=10)
            print(f"Models endpoint status: {response.status_code}")

            if response.status_code == 200:
                models = response.json()
                copilot_models = [m for m in models.get("data", []) if "copilot" in m.get("id", "").lower()]
                print(f"Found {len(copilot_models)} GitHub Copilot models:")
                for model in copilot_models:
                    print(f"  • {model.get('id', 'unknown')}")
            else:
                print(f"Error getting models: {response.text}")

        except Exception as e:
            print(f"Exception checking models: {str(e)}")

    def run_full_debug(self):
        """Run comprehensive debugging."""
        print("🚀 GITHUB COPILOT COMPREHENSIVE DEBUG")
        print("=" * 80)

        # Check authentication first
        self.check_authentication()

        # Test different request variations
        tests = [
            self.test_original_failing_request,
            self.test_minimal_request,
            self.test_with_streaming,
            self.test_claude_35_streaming,
            self.test_gemini_25_streaming,
        ]

        results = []
        for test in tests:
            success, response = test()
            results.append((test.__name__, success))
            print("\n" + "-" * 60)

        # Summary
        print("\n📊 DEBUG SUMMARY:")
        print("=" * 60)
        for test_name, success in results:
            status = "✅ PASSED" if success else "❌ FAILED"
            print(f"{status} {test_name}")

        passed = sum(1 for _, success in results if success)
        total = len(results)
        print(f"\n🎯 Overall: {passed}/{total} tests passed")

        if passed == 0:
            print("\n🔥 CRITICAL ISSUES DETECTED:")
            print("  • GitHub Copilot authentication may not be working")
            print("  • LiteLLM proxy may not be configured correctly")
            print("  • Network connectivity issues")
        elif passed < total:
            print("\n⚠️  PARTIAL SUCCESS - Some configurations work:")
            print("  • Check which request format works")
            print("  • Use working configuration as reference")
        else:
            print("\n🎉 ALL TESTS PASSED - GitHub Copilot is working!")
            print("✅ GPT-4.1, Claude 3.5, and Gemini 2.5 all working!")

def main():
    """Main debug execution."""
    if len(sys.argv) > 1:
        base_url = sys.argv[1]
        print(f"Using custom base URL: {base_url}")
        debugger = GitHubCopilotDebugger(base_url=base_url)
    else:
        print("Using default base URL: http://localhost:4000")
        debugger = GitHubCopilotDebugger()

    debugger.run_full_debug()

    print("\n💡 NEXT STEPS:")
    print("  1. Check Docker container logs: docker-compose logs")
    print("  2. Verify GitHub Copilot auth: Check if access token is valid")
    print("  3. Test direct API call to GitHub Copilot endpoint")
    print("  4. Check LiteLLM configuration and model mapping")

if __name__ == "__main__":
    main()
