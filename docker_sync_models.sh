#!/bin/bash

# Docker-friendly GitHub Copilot model sync script
# This script is designed to work seamlessly in Docker environments

set -e

# Configuration with Docker-friendly defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/app/config.yaml}"
GITHUB_COPILOT_TOKEN_DIR="${GITHUB_COPILOT_TOKEN_DIR:-/github_auth}"
LOG_DIR="${LOG_DIR:-/app/logs}"
BACKUP_DIR="${BACKUP_DIR:-/app/backups}"
PYTHON_CMD="${PYTHON_CMD:-python3}"

# Create directories
mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# Logging
LOG_FILE="$LOG_DIR/docker_model_sync.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting Docker GitHub Copilot model sync..."
log "Config file: $CONFIG_FILE"
log "Token directory: $GITHUB_COPILOT_TOKEN_DIR"
log "Working directory: $SCRIPT_DIR"

# Check if running in Docker
if [ -f /.dockerenv ]; then
    log "Running in Docker container"
    IN_DOCKER=true
else
    log "Running outside Docker"
    IN_DOCKER=false
fi

# Check token directory
if [ ! -d "$GITHUB_COPILOT_TOKEN_DIR" ]; then
    log "ERROR: GitHub Copilot token directory not found: $GITHUB_COPILOT_TOKEN_DIR"
    log "Please ensure the token directory is mounted properly"
    exit 1
fi

# Check for token files
if [ ! -f "$GITHUB_COPILOT_TOKEN_DIR/access-token" ] && [ ! -f "$GITHUB_COPILOT_TOKEN_DIR/api-key.json" ]; then
    log "WARNING: No token files found in $GITHUB_COPILOT_TOKEN_DIR"
    log "Available files: $(ls -la "$GITHUB_COPILOT_TOKEN_DIR" 2>/dev/null || echo 'none')"
fi

# Set environment for Python script
export GITHUB_COPILOT_TOKEN_DIR="$GITHUB_COPILOT_TOKEN_DIR"
export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log "Creating initial config file: $CONFIG_FILE"
    cat > "$CONFIG_FILE" << 'EOF'
model_list: []
litellm_settings:
  cache_config:
    type: redis
    host: redis
    port: 6379
    password: ""
    db: 0
general_settings:
  database_url: "postgresql://llmproxy:dbpassword9090@db:5432/litellm"
  store_model_in_db: true
  github_copilot:
    token_dir: "/github_auth"
    cache_models: true
EOF
fi

# Create backup
BACKUP_FILE="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).yaml"
cp "$CONFIG_FILE" "$BACKUP_FILE"
log "Created backup: $BACKUP_FILE"

# Test authentication first
log "Testing GitHub Copilot authentication..."
if ! $PYTHON_CMD -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from litellm.llms.github_copilot.authenticator import Authenticator
try:
    auth = Authenticator()
    token = auth.get_api_key()
    print('Authentication successful')
    exit(0)
except Exception as e:
    print(f'Authentication failed: {e}')
    exit(1)
" 2>&1; then
    log "ERROR: GitHub Copilot authentication failed"
    log "Please check your token files in $GITHUB_COPILOT_TOKEN_DIR"
    exit 1
fi

# Run model sync
log "Fetching models from GitHub Copilot API..."
if $PYTHON_CMD "$SCRIPT_DIR/fetch_copilot_models.py" --config "$CONFIG_FILE" 2>&1; then
    log "Successfully updated models"
    
    # Validate config
    if $PYTHON_CMD -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" 2>/dev/null; then
        log "Config validation successful"
        
        # Count models
        MODEL_COUNT=$($PYTHON_CMD -c "
import yaml
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
copilot_models = [m for m in config.get('model_list', []) if m.get('model_name', '').startswith('github_copilot/')]
print(len(copilot_models))
" 2>/dev/null || echo "0")
        
        log "Updated config with $MODEL_COUNT GitHub Copilot models"
        
        # Send reload signal if LiteLLM is running
        if $IN_DOCKER && pgrep -f "litellm" >/dev/null 2>&1; then
            log "Sending reload signal to LiteLLM..."
            pkill -HUP -f "litellm" 2>/dev/null || log "Could not send reload signal"
        fi
        
        # Clean up old backups (keep last 5)
        find "$BACKUP_DIR" -name "config_*.yaml" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
        
    else
        log "ERROR: Config validation failed, restoring backup"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        exit 1
    fi
else
    log "ERROR: Model sync failed, restoring backup"
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    exit 1
fi

# Health check - verify models are accessible
log "Running health check..."
HEALTH_CHECK_RESULT=$($PYTHON_CMD -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
import yaml
try:
    with open('$CONFIG_FILE') as f:
        config = yaml.safe_load(f)
    models = config.get('model_list', [])
    copilot_models = [m for m in models if m.get('model_name', '').startswith('github_copilot/')]
    if copilot_models:
        print(f'Health check passed: {len(copilot_models)} models configured')
        for model in copilot_models[:3]:
            name = model.get('model_name', 'unknown')
            info = model.get('litellm_params', {}).get('model_info', {})
            max_tokens = info.get('max_tokens', 'unknown')
            capabilities = []
            if info.get('supports_vision'): capabilities.append('vision')
            if info.get('supports_function_calling'): capabilities.append('functions')
            caps = ', '.join(capabilities) if capabilities else 'basic'
            print(f'  {name}: {caps} (max: {max_tokens})')
        exit(0)
    else:
        print('Health check failed: No GitHub Copilot models found')
        exit(1)
except Exception as e:
    print(f'Health check failed: {e}')
    exit(1)
" 2>&1)

if [ $? -eq 0 ]; then
    log "$HEALTH_CHECK_RESULT"
    log "Docker model sync completed successfully!"
else
    log "Health check failed: $HEALTH_CHECK_RESULT"
    exit 1
fi

# Log summary
log "Summary:"
log "  Config file: $CONFIG_FILE"
log "  Backup file: $BACKUP_FILE"
log "  Log file: $LOG_FILE"
log "  Token directory: $GITHUB_COPILOT_TOKEN_DIR"

# If this is the first run, show usage
if [ ! -f "$LOG_DIR/.first_run_done" ]; then
    log ""
    log "Usage in Docker:"
    log "  Manual sync:    ./docker_sync_models.sh"
    log "  View logs:      tail -f $LOG_FILE"
    log "  List models:    grep 'model_name:' $CONFIG_FILE"
    log "  Health check:   docker exec <container> ./docker_sync_models.sh"
    log ""
    touch "$LOG_DIR/.first_run_done"
fi