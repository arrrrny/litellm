#!/bin/bash
# rebuild_docker.sh - Complete rebuild script for LiteLLM Docker environment

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
section "GitHub Copilot LiteLLM Docker Rebuild"
echo "This script will completely rebuild the LiteLLM Docker environment."
echo "It will destroy all existing containers, volumes, and images related to LiteLLM."
echo "Press Ctrl+C now to cancel, or wait 5 seconds to continue..."

sleep 5

# Stop and remove existing containers
section "Stopping and removing existing containers"
docker-compose down -v || echo "No containers running or error stopping them."

# Cleanup unused volumes & images
section "Cleaning up Docker environment"
echo "Pruning unused volumes..."
docker volume prune -f

echo "Removing litellm_github_copilot_auth volume if it exists..."
docker volume rm litellm_github_copilot_auth 2>/dev/null || true

# Verify source code
section "Verifying source code structure"
./verify_modules.sh || {
  echo "Source code verification failed. Please fix the issues and try again."
  exit 1
}

# Rebuilding the container
section "Rebuilding Docker container"
echo "Building fresh Docker image..."
docker-compose build --no-cache

# Start containers
section "Starting containers"
echo "Starting LiteLLM in Docker..."
docker-compose up -d

# Wait for service to become available
section "Waiting for service to start"
echo "Checking if LiteLLM is responding (this may take a minute)..."

MAX_RETRIES=10
RETRY_COUNT=0
ENDPOINT="http://localhost:4000/health/liveliness"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -s $ENDPOINT > /dev/null; then
    echo "✓ LiteLLM is running successfully!"
    break
  else
    echo "Waiting for LiteLLM to start (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ LiteLLM did not start successfully within the expected time."
  echo "Check the logs with: docker-compose logs"
  exit 1
fi

# Show logs
section "Service Logs"
echo "Here are the most recent logs:"
docker-compose logs --tail=20

section "Success!"
echo "LiteLLM is now running in Docker."
echo ""
echo "Access the proxy at: http://localhost:4000"
echo "View logs with:      docker-compose logs -f"
echo "Stop with:           docker-compose down"
echo ""
echo "To test GitHub Copilot, try:"
echo "curl -X POST http://localhost:4000/chat/completions \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"model\": \"github_copilot/gpt-4.1\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello from GitHub Copilot!\"}]}'"
