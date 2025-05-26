import litellm
import os
import json
import traceback
from typing import Dict, Any

def test_thinking_parameter_with_copilot():
    """Test using the thinking parameter directly with GitHub Copilot"""
    
    model = "github_copilot/gpt-4o"
    
    messages = [
        {
            "role": "user",
            "content": "Solve this math problem: What is 2+2?"
        }
    ]
    
    print("Testing GitHub Copilot with thinking parameter...")
    print(f"Model: {model}")
    print(f"Messages: {json.dumps(messages, indent=2)}")
    print("\n" + "="*50 + "\n")
    
    try:
        response = litellm.completion(
            model=model,
            messages=messages,
            thinking={"enabled": True},  # Using thinking parameter
            stream=False
        )
        
        print("SUCCESS: Response received with thinking parameter")
        print(f"Response: {json.dumps(response.dict(), indent=2, default=str)}")
        
    except Exception as e:
        print("ERROR: Exception occurred with thinking parameter")
        print(f"Error type: {type(e).__name__}")
        print(f"Error message: {str(e)}")
        print(f"Traceback:\n{traceback.format_exc()}")

def test_reasoning_effort_with_copilot():
    """Test using the reasoning_effort parameter with GitHub Copilot"""
    
    model = "github_copilot/gpt-4o"
    
    messages = [
        {
            "role": "user",
            "content": "Solve this logic puzzle step by step."
        }
    ]
    
    print("Testing GitHub Copilot with reasoning_effort parameter...")
    print(f"Model: {model}")
    print(f"Messages: {json.dumps(messages, indent=2)}")
    print("\n" + "="*50 + "\n")
    
    try:
        response = litellm.completion(
            model=model,
            messages=messages,
            reasoning_effort="high",  # Using reasoning_effort parameter
            stream=False
        )
        
        print("SUCCESS: Response received with reasoning_effort parameter")
        print(f"Response: {json.dumps(response.dict(), indent=2, default=str)}")
        
    except Exception as e:
        print("ERROR: Exception occurred with reasoning_effort parameter")
        print(f"Error type: {type(e).__name__}")
        print(f"Error message: {str(e)}")
        print(f"Traceback:\n{traceback.format_exc()}")

def test_multiple_unsupported_params_with_copilot():
    """Test using multiple unsupported parameters with GitHub Copilot"""
    
    model = "github_copilot/gpt-4o"
    
    messages = [
        {
            "role": "user",
            "content": "Help me with research."
        }
    ]
    
    print("Testing GitHub Copilot with multiple unsupported parameters...")
    print(f"Model: {model}")
    print(f"Messages: {json.dumps(messages, indent=2)}")
    print("\n" + "="*50 + "\n")
    
    try:
        response = litellm.completion(
            model=model,
            messages=messages,
            thinking={"enabled": True},
            reasoning_effort="medium",
            web_search_options={"enabled": True},
            stream=False
        )
        
        print("SUCCESS: Response received with multiple unsupported parameters")
        print(f"Response: {json.dumps(response.dict(), indent=2, default=str)}")
        
    except Exception as e:
        print("ERROR: Exception occurred with multiple unsupported parameters")
        print(f"Error type: {type(e).__name__}")
        print(f"Error message: {str(e)}")
        print(f"Traceback:\n{traceback.format_exc()}")

def test_copilot_without_thinking():
    """Test GitHub Copilot without thinking to ensure baseline works"""
    
    model = "github_copilot/gpt-4o"
    
    messages = [
        {
            "role": "user",
            "content": "What is 2+2?"
        }
    ]
    
    print("Testing GitHub Copilot without thinking (baseline)...")
    print(f"Model: {model}")
    print(f"Messages: {json.dumps(messages, indent=2)}")
    print("\n" + "="*50 + "\n")
    
    try:
        response = litellm.completion(
            model=model,
            messages=messages,
            stream=False
        )
        
        print("SUCCESS: Baseline response received")
        print(f"Response: {json.dumps(response.dict(), indent=2, default=str)}")
        
    except Exception as e:
        print("ERROR: Even baseline failed")
        print(f"Error type: {type(e).__name__}")
        print(f"Error message: {str(e)}")
        print(f"Traceback:\n{traceback.format_exc()}")

if __name__ == "__main__":
    print("GitHub Copilot Thinking Tool Debug Script")
    print("="*60)
    
    # Check environment
    print(f"LiteLLM version: {litellm.__version__}")
    print(f"Python version: {os.sys.version}")
    print(f"GitHub token set: {'GITHUB_TOKEN' in os.environ}")
    print("\n")
    
    # Test 1: Baseline without thinking
    test_copilot_without_thinking()
    print("\n" + "="*60 + "\n")
    
    # Test 2: With thinking parameter
    test_thinking_parameter_with_copilot()
    print("\n" + "="*60 + "\n")
    
    # Test 3: With reasoning_effort parameter
    test_reasoning_effort_with_copilot()
    print("\n" + "="*60 + "\n")
    
    # Test 4: With multiple unsupported parameters
    test_multiple_unsupported_params_with_copilot()
    print("\n" + "="*60 + "\n")
    
    print("Debug script completed.")