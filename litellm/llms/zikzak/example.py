import litellm

def main():
    """
    Example demonstrating the ZikZak Z1 model's task orchestration capabilities
    """
    print("ZikZak Z1 Model Example")
    print("----------------------")
    
    # Set verbose mode to see the routing decisions
    litellm.set_verbose = True
    
    # Example 1: Scaffolding Task (will route to GPT-4.1)
    print("\n\nExample 1: Scaffolding Task (routes to GPT-4.1)")
    print("--------------------------------------------------")
    
    scaffolding_response = litellm.completion(
        model="zikzak/z1",
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Create a basic project structure for a Flask web application with templates and static folders"}
        ]
    )
    
    # Handle response content safely
    content = ""
    if hasattr(scaffolding_response, 'choices') and scaffolding_response.choices:
        if hasattr(scaffolding_response.choices[0], 'message'):
            content = scaffolding_response.choices[0].message.content[:200]
    print(f"Response for scaffolding task: {content}...\n")
    
    # Example 2: Complex Code Task (will route to Claude 3.7)
    print("\n\nExample 2: Complex Code Task (routes to Claude 3.7)")
    print("-----------------------------------------------")
    
    code_response = litellm.completion(
        model="zikzak/z1",
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Implement an efficient algorithm for finding the longest palindromic substring in a given string"}
        ]
    )
    
    # Handle response content safely
    content = ""
    if hasattr(code_response, 'choices') and code_response.choices:
        if hasattr(code_response.choices[0], 'message'):
            content = code_response.choices[0].message.content[:200]
    print(f"Response for complex code task: {content}...\n")
    
    # Example 3: Task without clear indicators (will use default model)
    print("\n\nExample 3: General Task (uses default model)")
    print("------------------------------------------")
    
    general_response = litellm.completion(
        model="zikzak/z1",
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Explain how virtual memory works in operating systems"}
        ]
    )
    
    # Handle response content safely
    content = ""
    if hasattr(general_response, 'choices') and general_response.choices:
        if hasattr(general_response.choices[0], 'message'):
            content = general_response.choices[0].message.content[:200]
    print(f"Response for general task: {content}...\n")
    
    # Access metadata about which model was actually used
    if hasattr(general_response, "_hidden_params"):
        print(f"This response was orchestrated by: {general_response._hidden_params.get('orchestrated_by', 'unknown')}")
        print(f"Using model: {general_response._hidden_params.get('original_model_used', 'unknown')}")

if __name__ == "__main__":
    main()