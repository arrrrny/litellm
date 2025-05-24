#!/usr/bin/env python3
"""
Test script for GitHub Copilot model sync functionality.
"""

import json
import os
import sys
import tempfile
import yaml
from typing import Dict, List, Any

# Add the litellm package to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from litellm.llms.github_copilot.authenticator import Authenticator
from fetch_copilot_models import CopilotModelFetcher


def test_authentication():
    """Test GitHub Copilot authentication."""
    print("Testing GitHub Copilot authentication...")
    
    try:
        auth = Authenticator()
        api_key = auth.get_api_key()
        
        if api_key and len(api_key) > 10:
            print("✅ Authentication successful")
            print(f"   Token length: {len(api_key)}")
            return True
        else:
            print("❌ Authentication failed: Invalid token")
            return False
            
    except Exception as e:
        print(f"❌ Authentication failed: {e}")
        return False


def test_model_fetching():
    """Test fetching models from GitHub Copilot API."""
    print("\nTesting model fetching...")
    
    try:
        auth = Authenticator()
        models = auth.fetch_available_models()
        
        if models:
            print(f"✅ Successfully fetched {len(models)} models")
            
            # Display some model info
            chat_models = [m for m in models if m.get('capabilities', {}).get('type') == 'chat']
            picker_enabled = [m for m in models if m.get('model_picker_enabled', False)]
            
            print(f"   Chat models: {len(chat_models)}")
            print(f"   Picker enabled: {len(picker_enabled)}")
            
            # Show first few models
            print("   Sample models:")
            for model in models[:5]:
                model_id = model.get('id', 'unknown')
                capabilities = model.get('capabilities', {})
                supports = capabilities.get('supports', {})
                features = []
                
                if supports.get('vision'):
                    features.append('vision')
                if supports.get('tool_calls'):
                    features.append('tools')
                if supports.get('streaming'):
                    features.append('streaming')
                
                features_str = ', '.join(features) if features else 'basic'
                print(f"     {model_id}: {features_str}")
            
            return True
        else:
            print("❌ No models fetched")
            return False
            
    except Exception as e:
        print(f"❌ Model fetching failed: {e}")
        return False


def test_model_conversion():
    """Test converting models to LiteLLM format."""
    print("\nTesting model conversion...")
    
    try:
        auth = Authenticator()
        models = auth.fetch_available_models()
        converted_models = auth.get_litellm_model_configs()
        
        if converted_models:
            print(f"✅ Successfully converted {len(converted_models)} models")
            
            # Validate conversion
            for model_config in converted_models[:3]:
                model_name = model_config.get('model_name', '')
                litellm_params = model_config.get('litellm_params', {})
                model_info = litellm_params.get('model_info', {})
                
                print(f"   Model: {model_name}")
                print(f"     Provider: {model_info.get('litellm_provider')}")
                print(f"     Max tokens: {model_info.get('max_tokens', 'unknown')}")
                
                # Check required fields
                required_fields = ['model_name', 'litellm_params']
                for field in required_fields:
                    if field not in model_config:
                        print(f"     ❌ Missing field: {field}")
                        return False
            
            return True
        else:
            print("❌ No models converted")
            return False
            
    except Exception as e:
        print(f"❌ Model conversion failed: {e}")
        return False


def test_config_update():
    """Test updating configuration file."""
    print("\nTesting config update...")
    
    try:
        # Create a temporary config file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            test_config = {
                'model_list': [
                    {
                        'model_name': 'test_model',
                        'litellm_params': {'model': 'test_model'}
                    }
                ],
                'litellm_settings': {},
                'general_settings': {}
            }
            yaml.dump(test_config, f)
            temp_config_path = f.name
        
        try:
            # Test with the fetcher
            fetcher = CopilotModelFetcher(config_path=temp_config_path)
            auth = Authenticator()
            converted_models = auth.get_litellm_model_configs()
            
            if converted_models:
                fetcher.update_config(converted_models)
                
                # Verify the update
                with open(temp_config_path, 'r') as f:
                    updated_config = yaml.safe_load(f)
                
                copilot_models = [
                    m for m in updated_config.get('model_list', [])
                    if m.get('model_name', '').startswith('github_copilot/')
                ]
                
                if copilot_models:
                    print(f"✅ Successfully updated config with {len(copilot_models)} models")
                    print(f"   Config file: {temp_config_path}")
                    
                    # Verify structure
                    sample_model = copilot_models[0]
                    required_keys = ['model_name', 'litellm_params']
                    
                    for key in required_keys:
                        if key not in sample_model:
                            print(f"     ❌ Missing key in model config: {key}")
                            return False
                    
                    print("     ✅ Config structure validated")
                    return True
                else:
                    print("❌ No GitHub Copilot models found in updated config")
                    return False
            else:
                print("❌ No models to update config with")
                return False
                
        finally:
            # Clean up temp file
            os.unlink(temp_config_path)
            
    except Exception as e:
        print(f"❌ Config update failed: {e}")
        return False


def test_headers():
    """Test authentication headers generation."""
    print("\nTesting headers generation...")
    
    try:
        auth = Authenticator()
        headers = auth._get_github_headers()
        
        required_headers = ['accept', 'editor-version', 'user-agent']
        
        for header in required_headers:
            if header not in headers:
                print(f"❌ Missing header: {header}")
                return False
        
        print("✅ Headers generated successfully")
        print(f"   Headers: {list(headers.keys())}")
        return True
        
    except Exception as e:
        print(f"❌ Header generation failed: {e}")
        return False


def run_all_tests():
    """Run all tests and return overall result."""
    print("GitHub Copilot Model Sync Test Suite")
    print("=" * 50)
    
    tests = [
        ("Authentication", test_authentication),
        ("Headers", test_headers),
        ("Model Fetching", test_model_fetching),
        ("Model Conversion", test_model_conversion),
        ("Config Update", test_config_update),
    ]
    
    results = []
    
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"❌ {test_name} test crashed: {e}")
            results.append((test_name, False))
    
    print("\n" + "=" * 50)
    print("Test Results Summary")
    print("=" * 50)
    
    passed = 0
    total = len(results)
    
    for test_name, result in results:
        status = "PASS" if result else "FAIL"
        emoji = "✅" if result else "❌"
        print(f"{emoji} {test_name}: {status}")
        if result:
            passed += 1
    
    print("-" * 50)
    print(f"Total: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! GitHub Copilot model sync is working correctly.")
        return True
    else:
        print("⚠️  Some tests failed. Please check the output above for details.")
        return False


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Test GitHub Copilot model sync functionality")
    parser.add_argument(
        "--test",
        choices=["auth", "headers", "fetch", "convert", "config", "all"],
        default="all",
        help="Specific test to run (default: all)"
    )
    
    args = parser.parse_args()
    
    if args.test == "auth":
        return test_authentication()
    elif args.test == "headers":
        return test_headers()
    elif args.test == "fetch":
        return test_model_fetching()
    elif args.test == "convert":
        return test_model_conversion()
    elif args.test == "config":
        return test_config_update()
    else:
        return run_all_tests()


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)