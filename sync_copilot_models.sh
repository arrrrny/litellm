#!/bin/bash

# GitHub Copilot Model Sync Script
# This script fetches the latest models from GitHub Copilot API and updates the LiteLLM config

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.yaml}"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/logs/copilot_sync.log}"
LOCK_FILE="${LOCK_FILE:-/tmp/copilot_sync.lock}"

# GitHub Copilot token directory
GITHUB_COPILOT_TOKEN_DIR="${GITHUB_COPILOT_TOKEN_DIR:-/github_auth}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Check if script is already running
if [ -f "$LOCK_FILE" ]; then
    log "Script is already running (lock file exists: $LOCK_FILE)"
    exit 0
fi

# Create lock file
touch "$LOCK_FILE"

# Create necessary directories
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"

log "Starting GitHub Copilot model sync..."

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    error_exit "Config file not found: $CONFIG_FILE"
fi

# Check if we're in Docker environment
if [ -d "$GITHUB_COPILOT_TOKEN_DIR" ]; then
    log "Using Docker token directory: $GITHUB_COPILOT_TOKEN_DIR"
    export GITHUB_COPILOT_TOKEN_DIR="$GITHUB_COPILOT_TOKEN_DIR"
fi

# Create backup of current config
BACKUP_FILE="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).yaml"
cp "$CONFIG_FILE" "$BACKUP_FILE"
log "Created backup: $BACKUP_FILE"

# Set Python environment
export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"

# Run the model fetcher
log "Fetching models from GitHub Copilot API..."
if python3 "$SCRIPT_DIR/fetch_copilot_models.py" --config "$CONFIG_FILE" --verbose >> "$LOG_FILE" 2>&1; then
    log "Successfully updated config with latest GitHub Copilot models"
    
    # Validate the updated config
    if python3 -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" 2>/dev/null; then
        log "Config validation successful"
        
        # Clean up old backups (keep last 10)
        find "$BACKUP_DIR" -name "config_*.yaml" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
        log "Cleaned up old backups"
        
        # If running in Docker, send signal to reload config
        if [ -n "$LITELLM_PID" ] && kill -0 "$LITELLM_PID" 2>/dev/null; then
            log "Sending reload signal to LiteLLM process (PID: $LITELLM_PID)"
            kill -HUP "$LITELLM_PID" || log "Warning: Could not send reload signal"
        elif pgrep -f "litellm" >/dev/null; then
            log "Found LiteLLM process, attempting reload..."
            pkill -HUP -f "litellm" || log "Warning: Could not send reload signal to LiteLLM"
        fi
        
    else
        error_exit "Config validation failed, restoring backup"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
    fi
else
    error_exit "Failed to fetch models, restoring backup"
    cp "$BACKUP_FILE" "$CONFIG_FILE"
fi

# Rotate logs (keep last 100MB)
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 104857600 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
    log "Rotated log file"
fi

log "GitHub Copilot model sync completed successfully"