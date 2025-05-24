#!/bin/bash

# Docker startup script for LiteLLM with GitHub Copilot model sync
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/app/config.yaml}"
GITHUB_COPILOT_TOKEN_DIR="${GITHUB_COPILOT_TOKEN_DIR:-/github_auth}"
LOG_FILE="/app/logs/startup.log"
SYNC_ON_STARTUP="${SYNC_COPILOT_MODELS_ON_STARTUP:-true}"
SYNC_INTERVAL="${COPILOT_MODEL_SYNC_INTERVAL:-3600}"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting LiteLLM container with GitHub Copilot integration..."

# Check if GitHub Copilot token directory exists
if [ -d "$GITHUB_COPILOT_TOKEN_DIR" ]; then
    log "GitHub Copilot token directory found: $GITHUB_COPILOT_TOKEN_DIR"
    export GITHUB_COPILOT_TOKEN_DIR="$GITHUB_COPILOT_TOKEN_DIR"
    
    # Set proper permissions
    chmod -R 600 "$GITHUB_COPILOT_TOKEN_DIR"/* 2>/dev/null || true
else
    log "WARNING: GitHub Copilot token directory not found: $GITHUB_COPILOT_TOKEN_DIR"
    log "Copilot authentication may not work properly"
fi

# Sync models on startup if enabled
if [ "$SYNC_ON_STARTUP" = "true" ]; then
    log "Syncing GitHub Copilot models on startup..."
    
    if [ -f "$SCRIPT_DIR/fetch_copilot_models.py" ]; then
        if python3 "$SCRIPT_DIR/fetch_copilot_models.py" --config "$CONFIG_FILE" 2>&1 | tee -a "$LOG_FILE"; then
            log "Successfully synced GitHub Copilot models on startup"
        else
            log "WARNING: Failed to sync GitHub Copilot models on startup, continuing with existing config"
        fi
    else
        log "WARNING: Model sync script not found, continuing with existing config"
    fi
fi

# Start background model sync if interval is set
if [ "$SYNC_INTERVAL" -gt 0 ]; then
    log "Starting background model sync with interval: ${SYNC_INTERVAL}s"
    
    (
        while true; do
            sleep "$SYNC_INTERVAL"
            log "Running scheduled GitHub Copilot model sync..."
            
            if [ -f "$SCRIPT_DIR/sync_copilot_models.sh" ]; then
                "$SCRIPT_DIR/sync_copilot_models.sh" 2>&1 | tee -a "$LOG_FILE" || true
            else
                log "WARNING: Sync script not found, skipping scheduled sync"
            fi
        done
    ) &
    
    SYNC_PID=$!
    log "Background sync started with PID: $SYNC_PID"
fi

# Function to handle shutdown
cleanup() {
    log "Shutting down LiteLLM container..."
    
    if [ -n "$SYNC_PID" ]; then
        log "Stopping background sync process..."
        kill "$SYNC_PID" 2>/dev/null || true
    fi
    
    if [ -n "$LITELLM_PID" ]; then
        log "Stopping LiteLLM process..."
        kill "$LITELLM_PID" 2>/dev/null || true
        wait "$LITELLM_PID" 2>/dev/null || true
    fi
    
    log "Container shutdown complete"
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Set environment variables for LiteLLM
export LITELLM_CONFIG_PATH="$CONFIG_FILE"

# Start LiteLLM
log "Starting LiteLLM proxy server..."
log "Config file: $CONFIG_FILE"
log "Database URL: ${DATABASE_URL:-postgresql://llmproxy:dbpassword9090@db:5432/litellm}"

# Start LiteLLM in the background
python3 -m litellm --config "$CONFIG_FILE" --host 0.0.0.0 --port 4000 &
LITELLM_PID=$!

log "LiteLLM started with PID: $LITELLM_PID"

# Wait for LiteLLM to start
sleep 5

# Health check
if kill -0 "$LITELLM_PID" 2>/dev/null; then
    log "LiteLLM is running successfully"
    
    # Optional: Test GitHub Copilot authentication
    if [ -d "$GITHUB_COPILOT_TOKEN_DIR" ]; then
        log "Testing GitHub Copilot authentication..."
        python3 -c "
from litellm.llms.github_copilot.authenticator import Authenticator
try:
    auth = Authenticator()
    token = auth.get_api_key()
    print('GitHub Copilot authentication successful')
except Exception as e:
    print(f'GitHub Copilot authentication failed: {e}')
" 2>&1 | tee -a "$LOG_FILE"
    fi
else
    log "ERROR: LiteLLM failed to start"
    exit 1
fi

# Keep the container running and wait for signals
log "Container initialization complete. LiteLLM is ready to serve requests."
log "GitHub Copilot models will sync every ${SYNC_INTERVAL}s"

wait "$LITELLM_PID"