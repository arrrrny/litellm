#!/bin/bash

# Setup cron job for GitHub Copilot model sync
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_USER="${CRON_USER:-$(whoami)}"
SYNC_INTERVAL="${COPILOT_MODEL_SYNC_INTERVAL:-60}"  # minutes
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.yaml}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/logs/cron_sync.log}"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Setting up cron job for GitHub Copilot model sync..."

# Create the cron job entry
CRON_ENTRY="*/${SYNC_INTERVAL} * * * * cd $SCRIPT_DIR && ./sync_copilot_models.sh >> $LOG_FILE 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "sync_copilot_models.sh"; then
    log "Cron job already exists, removing old entry..."
    crontab -l 2>/dev/null | grep -v "sync_copilot_models.sh" | crontab -
fi

# Add new cron job
log "Adding cron job to run every $SYNC_INTERVAL minutes..."
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

# Verify cron job was added
if crontab -l 2>/dev/null | grep -q "sync_copilot_models.sh"; then
    log "Cron job successfully added:"
    crontab -l | grep "sync_copilot_models.sh"
    log "GitHub Copilot models will sync every $SYNC_INTERVAL minutes"
    log "Logs will be written to: $LOG_FILE"
else
    log "ERROR: Failed to add cron job"
    exit 1
fi

# Test the sync script
log "Testing sync script..."
if [ -f "$SCRIPT_DIR/sync_copilot_models.sh" ]; then
    if "$SCRIPT_DIR/sync_copilot_models.sh"; then
        log "Sync script test successful"
    else
        log "WARNING: Sync script test failed, but cron job is still installed"
    fi
else
    log "ERROR: Sync script not found: $SCRIPT_DIR/sync_copilot_models.sh"
    exit 1
fi

log "Cron job setup complete!"
log ""
log "Commands:"
log "  View cron jobs:     crontab -l"
log "  Remove cron job:    crontab -l | grep -v sync_copilot_models.sh | crontab -"
log "  View sync logs:     tail -f $LOG_FILE"
log "  Manual sync:        $SCRIPT_DIR/sync_copilot_models.sh"