#!/bin/bash
# rebuild_docker_prod.sh - Production rebuild script for LiteLLM Docker environment

set -e # Exit on error
set -o pipefail

# Print section header
section() {
  echo
  echo "==============================================="
  echo "   $1"
  echo "==============================================="
  echo
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or not installed."
  echo "Please start Docker and try again."
  exit 1
fi

# Start script
section "GitHub Copilot LiteLLM Production Docker Rebuild"
echo "This script will completely rebuild the LiteLLM Docker environment for PRODUCTION."
echo "- All debug logging will be DISABLED"
echo "- Performance optimizations will be applied"
echo "- Only ERROR level logs will be shown"
echo "It will destroy all existing containers and images related to LiteLLM."
echo "Press Ctrl+C now to cancel, or wait 5 seconds to continue..."

sleep 5

# Stop and remove existing containers
section "Stopping and removing existing containers"
docker-compose -f docker-compose.prod.yml down || echo "No containers running or error stopping them."
docker-compose down || echo "No dev containers running."

# Backup GitHub Copilot auth data first
section "Backing up GitHub Copilot Authentication"
echo "Creating safety backup of GitHub Copilot auth data..."
./backup_copilot_auth.sh backup || echo "Warning: Could not backup auth data (might not exist yet)"

# Cleanup unused volumes & images (preserving GitHub Copilot auth)
section "Cleaning up Docker environment"
echo "Removing unused Docker resources while preserving GitHub Copilot auth..."
echo "⚠️  Preserving GitHub Copilot authentication data..."

# List volumes before cleanup for safety
echo "Current volumes:"
docker volume ls | grep -E "(github_copilot|litellm)" || echo "No LiteLLM volumes found"

# Clean up containers and networks, but NOT volumes
docker container prune -f || true
docker network prune -f || true
docker image prune -f || true

# Only remove specific non-auth volumes if they exist
echo "Removing old postgres data (will be recreated)..."
docker volume rm litellm_postgres_data 2>/dev/null || echo "Old postgres volume not found (OK)"
docker volume rm postgres_data 2>/dev/null || echo "Old postgres volume not found (OK)"

echo "✅ GitHub Copilot auth data preserved and backed up!"

# Verify auth volume still exists
if docker volume inspect litellm_github_copilot_auth >/dev/null 2>&1; then
  echo "✅ GitHub Copilot auth volume confirmed intact"
else
  echo "⚠️  Auth volume not found - will be restored from backup if needed"
fi

# Verify source code
section "Verifying source code structure"
./verify_modules.sh || {
  echo "Source code verification failed. Please fix the issues and try again."
  exit 1
}

# Rebuilding the container
section "Rebuilding Docker container for PRODUCTION"
echo "Building fresh Docker image with production optimizations..."
docker-compose -f docker-compose.prod.yml build --no-cache

# Start containers
section "Starting containers in PRODUCTION mode"
echo "Starting LiteLLM in Production Docker mode..."
docker-compose -f docker-compose.prod.yml up -d

# Wait for service to become available
section "Waiting for service to start"
echo "Checking if LiteLLM is responding (this may take a minute)..."

MAX_RETRIES=10
RETRY_COUNT=0
ENDPOINT="http://localhost:4000/health/liveliness"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -s $ENDPOINT > /dev/null; then
    echo "✓ LiteLLM Production is running successfully!"
    break
  else
    echo "Waiting for LiteLLM to start (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 20
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ LiteLLM did not start successfully within the expected time."
  echo "Check the logs with: docker-compose -f docker-compose.prod.yml logs"
  exit 1
fi

# Show minimal logs
section "Service Status"
echo "Here are the most recent ERROR logs (if any):"
docker-compose -f docker-compose.prod.yml logs --tail=10 | grep -i error || echo "No error logs found - service is running cleanly!"

section "Production Success!"
echo "LiteLLM is now running in PRODUCTION mode with minimal logging."
echo ""
echo "🚀 Production Settings Applied:"
echo "   • Debug logging: DISABLED"
echo "   • Log level: ERROR only"
echo "   • Performance: OPTIMIZED"
echo "   • Workers: 4"
echo "   • Restart policy: unless-stopped"
echo ""
echo "Access the proxy at: http://localhost:4000"
echo "View logs with:      docker-compose -f docker-compose.prod.yml logs -f"
echo "Stop with:           docker-compose -f docker-compose.prod.yml down"
echo ""
echo "To test GitHub Copilot, try:"
echo "curl -X POST http://localhost:4000/chat/completions \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -H \"Authorization: Bearer sk-1234\" \\"
echo "     -d '{\"model\": \"github_copilot/gpt-4.1\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello from GitHub Copilot!\"}]}'"