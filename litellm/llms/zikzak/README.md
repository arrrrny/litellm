# ZikZak Provider for LiteLLM

ZikZak is a model orchestration provider that routes tasks to the most appropriate model based on the nature of the task.

## Overview

The ZikZak provider with its Z1 model acts as an intelligent orchestration layer, analyzing incoming requests and routing them to the most suitable underlying model. This approach allows for:

- Using GPT-4.1 for scaffolding tasks (creating project structures, directories, files)
- Using Claude 3.7 for complex code implementation, debugging, and optimization
- Optimizing cost and performance by using the most appropriate model for each task type

## How It Works

The ZikZak provider uses keyword detection and task categorization to automatically determine which model to send requests to. The rules for this routing are stored in a `rules.json` file that can be updated over time to improve performance or to adjust which models handle specific tasks.

## Configuration

To use the ZikZak provider, add it to your LiteLLM configuration:

```yaml
model_list:
  - model_name: zikzak/z1
    litellm_params:
      model: zikzak/z1
      model_info:
        max_tokens: 128000
        max_input_tokens: 64000
        max_output_tokens: 4096
        litellm_provider: "zikzak"
        mode: "chat"
        supports_vision: true
        supports_function_calling: true
        supports_parallel_function_calling: true
        supports_system_messages: true

litellm_settings:
  custom_provider_map:
    - provider: "zikzak"
      custom_handler: "litellm.llms.zikzak.ZikZakCompletion"
```

## Usage

You can use the ZikZak Z1 model just like any other LiteLLM model:

```python
import litellm

response = litellm.completion(
    model="zikzak/z1",
    messages=[{"role": "user", "content": "Create a project structure for a React application"}]
)
```

The ZikZak provider will automatically determine that this is a scaffolding task and route it to GPT-4.1. For more complex coding tasks, it will route to Claude 3.7.

## Rules Configuration

The rules for task routing are stored in `rules.json` within the ZikZak provider directory. This file contains:

- Model mappings for different task types
- Keywords for identifying task types
- Default and fallback model configurations

The rules file can be updated over time to improve routing logic and performance.

## Benefits

- Separation of concerns - use GPT-4.1 for what it's best at, and Claude for what it excels in
- Automatic task routing without manual model selection
- Extensible architecture that can incorporate additional models and task types
- Cost optimization by using the most appropriate model for each task

## Limitations

- The current keyword-based routing is relatively simple and may misclassify some tasks
- Only supports Claude 3.7 and GPT-4.1 initially, but can be expanded

## Future Enhancements

- Machine learning for task classification
- Support for additional models
- Analytics for routing performance
- User-specific routing preferences