# GitHub Copilot Model Sync for LiteLLM

This document describes the dynamic model synchronization feature for GitHub Copilot in LiteLLM, which automatically fetches the latest available models from the GitHub Copilot API and updates your configuration.

## Overview

The GitHub Copilot model sync feature provides:

- **Dynamic Model Discovery**: Automatically fetches all available models from GitHub Copilot API
- **Capability Detection**: Automatically detects and configures model capabilities (vision, function calling, structured outputs, etc.)
- **Token Limit Configuration**: Automatically sets appropriate token limits based on model specifications
- **Automated Updates**: Supports scheduled updates via cron jobs or Docker integration
- **Backup & Recovery**: Creates backups before updates and validates configurations

## Quick Start

### Manual Sync

```bash
# Fetch and update models immediately
python fetch_copilot_models.py

# With custom config file
python fetch_copilot_models.py --config /path/to/config.yaml

# With verbose logging
python fetch_copilot_models.py --verbose
```

### Docker Integration

```bash
# Set environment variables in your docker-compose.yml
environment:
  SYNC_COPILOT_MODELS_ON_STARTUP: "true"
  COPILOT_MODEL_SYNC_INTERVAL: "3600"  # 1 hour
  GITHUB_COPILOT_TOKEN_DIR: "/github_auth"

# Use the startup script
./docker_startup.sh
```

### Cron Job Setup

```bash
# Setup automatic sync every hour
COPILOT_MODEL_SYNC_INTERVAL=60 ./setup_cron.sh

# Manual sync using the wrapper script
./sync_copilot_models.sh
```

## Features

### Automatic Model Configuration

The sync automatically configures models with:

- **Model Name**: `github_copilot/{model_id}`
- **Provider**: `github_copilot`
- **Headers**: Appropriate editor headers for Copilot integration
- **Capabilities**: Vision, function calling, structured outputs based on API response
- **Token Limits**: Max tokens, input/output token limits
- **Caching**: Automatic cache configuration for supported models

### Example Generated Config

```yaml
model_list:
  - model_name: github_copilot/gpt-4o
    litellm_params:
      model: github_copilot/gpt-4o
      extra_headers:
        Editor-Version: vscode/1.85.1
        Editor-Plugin-Version: copilot/1.155.0
        User-Agent: GithubCopilot/1.155.0
        Copilot-Integration-Id: vscode-chat
      model_info:
        litellm_provider: github_copilot
        mode: chat
        input_cost_per_token: 0.0
        output_cost_per_token: 0.0
        max_tokens: 128000
        max_input_tokens: 96000
        max_output_tokens: 4096
        supports_vision: true
        supports_function_calling: true
        supports_tool_calls: true
        supports_parallel_function_calling: true
        supports_system_messages: true
      cache_models_for: 7200
```

## Configuration

### Environment Variables

- `GITHUB_COPILOT_TOKEN_DIR`: Directory containing GitHub Copilot tokens (default: `/github_auth`)
- `SYNC_COPILOT_MODELS_ON_STARTUP`: Enable model sync on container startup (default: `true`)
- `COPILOT_MODEL_SYNC_INTERVAL`: Sync interval in seconds for background sync (default: `3600`)
- `CONFIG_FILE`: Path to LiteLLM config file (default: `config.yaml`)

### Authentication

Ensure GitHub Copilot authentication is set up:

1. **Local Development**: Tokens stored in `~/.config/litellm/github_copilot/`
2. **Docker**: Mount tokens to `/github_auth` volume
3. **Environment**: Set `GITHUB_TOKEN` for Codespaces

### Docker Volume Mount

```yaml
# docker-compose.yml
services:
  litellm:
    volumes:
      - ./github_auth:/github_auth:ro
```

## Scripts

### `fetch_copilot_models.py`

Main script for fetching and updating models.

```bash
python fetch_copilot_models.py [OPTIONS]

Options:
  --config CONFIG   Path to config.yaml file
  --verbose        Enable verbose logging
  --help           Show help message
```

### `sync_copilot_models.sh`

Wrapper script with backup, validation, and logging.

Features:
- Creates config backups before updates
- Validates updated configuration
- Handles errors gracefully with automatic restore
- Logs all operations
- Sends reload signals to running LiteLLM processes

### `docker_startup.sh`

Docker container startup script with integrated model sync.

Features:
- Syncs models on container startup
- Starts background sync process
- Handles container shutdown gracefully
- Health checks and authentication validation

### `setup_cron.sh`

Sets up automated model sync via cron jobs.

```bash
# Setup cron job every 60 minutes
COPILOT_MODEL_SYNC_INTERVAL=60 ./setup_cron.sh
```

## Model Filtering

Only models that meet these criteria are included:

- `model_picker_enabled: true`
- `capabilities.type: "chat"`
- Valid model ID

Models are automatically configured based on their reported capabilities:

- **Vision Support**: `supports.vision`
- **Function Calling**: `supports.tool_calls`
- **Parallel Calls**: `supports.parallel_tool_calls`
- **Structured Outputs**: `supports.structured_outputs`
- **Response Schema**: `supports.response_schema`

## Logging

Logs are written to:
- **Manual sync**: Console output
- **Cron jobs**: `logs/cron_sync.log`
- **Docker**: `logs/startup.log` and `logs/copilot_sync.log`

Log rotation is automatic when files exceed 100MB.

## Troubleshooting

### Authentication Issues

```bash
# Check token files
ls -la ~/.config/litellm/github_copilot/
# or
ls -la /github_auth/

# Test authentication
python -c "
from litellm.llms.github_copilot.authenticator import Authenticator
auth = Authenticator()
print(auth.get_api_key())
"
```

### Configuration Validation

```bash
# Validate YAML syntax
python -c "import yaml; yaml.safe_load(open('config.yaml'))"

# Check model availability
curl -H "Authorization: Bearer $TOKEN" https://api.githubcopilot.com/models
```

### Debug Mode

```bash
# Enable verbose logging
export PYTHONPATH=.
python fetch_copilot_models.py --verbose

# Check sync script logs
tail -f logs/copilot_sync.log
```

## API Endpoints

- **Models**: `https://api.githubcopilot.com/models`
- **Token**: `https://api.github.com/copilot_internal/v2/token`
- **Chat**: `https://api.githubcopilot.com/chat/completions`

## Integration Examples

### Docker Compose

```yaml
version: '3.8'
services:
  litellm:
    build: .
    ports:
      - "4000:4000"
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./github_auth:/github_auth:ro
      - ./logs:/app/logs
    environment:
      SYNC_COPILOT_MODELS_ON_STARTUP: "true"
      COPILOT_MODEL_SYNC_INTERVAL: "3600"
      GITHUB_COPILOT_TOKEN_DIR: "/github_auth"
    command: ./docker_startup.sh
```

### Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: copilot-model-sync
spec:
  schedule: "0 * * * *"  # Every hour
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: model-sync
            image: litellm:latest
            command: ["./sync_copilot_models.sh"]
            volumeMounts:
            - name: config
              mountPath: /app/config.yaml
            - name: github-auth
              mountPath: /github_auth
          restartPolicy: OnFailure
```

### GitHub Actions

```yaml
name: Update Copilot Models
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  update-models:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'
    - name: Install dependencies
      run: pip install -r requirements.txt
    - name: Update models
      run: python fetch_copilot_models.py --config config.yaml
    - name: Commit changes
      run: |
        git config --local user.email "action@github.com"
        git config --local user.name "GitHub Action"
        git add config.yaml
        git diff --staged --quiet || git commit -m "Update Copilot models"
        git push
```

## Security Considerations

- Store tokens securely with appropriate file permissions (600)
- Use read-only mounts for token directories in Docker
- Regularly rotate GitHub tokens
- Monitor logs for authentication failures
- Validate configurations before applying updates

## Limitations

- Requires valid GitHub Copilot subscription and authentication
- Model availability depends on your GitHub Copilot plan
- API rate limits may apply (usually 15,000 requests/hour)
- Some models may not be available in all regions

## Support

For issues related to:
- **Authentication**: Check GitHub Copilot subscription and token validity
- **Model Sync**: Review logs and verify API connectivity
- **Configuration**: Validate YAML syntax and model parameters
- **Docker**: Check volume mounts and environment variables