#!/bin/bash
# backup_copilot_auth.sh - Backup and restore GitHub Copilot authentication data

set -e

BACKUP_DIR="./copilot_auth_backup"
VOLUME_NAME="litellm_github_copilot_auth"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Print section header
section() {
  echo
  echo "==============================================="
  echo "   $1"
  echo "==============================================="
  echo
}

backup_auth() {
  section "Backing up GitHub Copilot Auth Data"
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR"
  
  # Check if volume exists
  if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "❌ Volume $VOLUME_NAME does not exist. Nothing to backup."
    exit 1
  fi
  
  # Create backup using a temporary container
  echo "Creating backup of GitHub Copilot auth data..."
  docker run --rm -v "$VOLUME_NAME":/source -v "$(pwd)/$BACKUP_DIR":/backup alpine:latest \
    tar czf "/backup/copilot_auth_$TIMESTAMP.tar.gz" -C /source .
  
  echo "✅ Backup created: $BACKUP_DIR/copilot_auth_$TIMESTAMP.tar.gz"
  
  # List backups
  echo "Available backups:"
  ls -la "$BACKUP_DIR"/copilot_auth_*.tar.gz 2>/dev/null || echo "No previous backups found"
}

restore_auth() {
  section "Restoring GitHub Copilot Auth Data"
  
  # Find the latest backup
  LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/copilot_auth_*.tar.gz 2>/dev/null | head -1)
  
  if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup files found in $BACKUP_DIR"
    exit 1
  fi
  
  echo "Restoring from: $LATEST_BACKUP"
  
  # Create volume if it doesn't exist
  docker volume create "$VOLUME_NAME" >/dev/null 2>&1 || true
  
  # Restore backup using a temporary container
  docker run --rm -v "$VOLUME_NAME":/target -v "$(pwd)/$BACKUP_DIR":/backup alpine:latest \
    tar xzf "/backup/$(basename "$LATEST_BACKUP")" -C /target
  
  echo "✅ GitHub Copilot auth data restored successfully!"
}

check_auth_status() {
  section "Checking GitHub Copilot Auth Status"
  
  if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "❌ Volume $VOLUME_NAME does not exist"
    exit 1
  fi
  
  # Check if volume has data
  docker run --rm -v "$VOLUME_NAME":/data alpine:latest ls -la /data/ || echo "Volume is empty"
}

show_usage() {
  echo "Usage: $0 {backup|restore|status}"
  echo ""
  echo "Commands:"
  echo "  backup  - Create a backup of GitHub Copilot auth data"
  echo "  restore - Restore GitHub Copilot auth data from latest backup"
  echo "  status  - Check the current status of auth data"
  echo ""
  echo "Examples:"
  echo "  $0 backup"
  echo "  $0 restore"
  echo "  $0 status"
}

# Main script logic
case "${1:-}" in
  backup)
    backup_auth
    ;;
  restore)
    restore_auth
    ;;
  status)
    check_auth_status
    ;;
  *)
    show_usage
    exit 1
    ;;
esac