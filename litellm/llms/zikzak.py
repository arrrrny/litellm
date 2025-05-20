# This is a proxy file to ensure proper imports
# Import the actual ZikZakCompletion from zikzak/zikzak.py
try:
    from litellm.llms.zikzak.zikzak import ZikZakCompletion
except ImportError as e:
    import os
    import sys
    
    # Add the directory to Python's path
    module_dir = os.path.join(os.path.dirname(__file__), 'zikzak')
    if os.path.exists(module_dir):
        sys.path.insert(0, os.path.dirname(__file__))
        from zikzak.zikzak import ZikZakCompletion
    else:
        # Fallback for Docker environments
        module_dir = '/app/litellm/llms/zikzak'
        if os.path.exists(module_dir):
            sys.path.insert(0, '/app/litellm/llms')
            from zikzak.zikzak import ZikZakCompletion
        else:
            raise ImportError(f"ZikZak module not found. Looked in: {os.path.dirname(__file__)}/zikzak and {module_dir}")

# Re-export the class
__all__ = ["ZikZakCompletion"]