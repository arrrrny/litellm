#!/bin/bash
# start_prod.sh - Start LiteLLM in production mode

set -e

echo "Starting LiteLLM in Production Mode..."
echo "- Logging: ERROR level only"
echo "- Debug: DISABLED"
echo "- Performance: OPTIMIZED"

# Stop any existing containers
docker-compose down 2>/dev/null || true
docker-compose -f docker-compose.prod.yml down 2>/dev/null || true

# Start production containers
docker-compose -f docker-compose.prod.yml up -d

echo ""
echo "✅ LiteLLM Production started successfully!"
echo ""
echo "Access: http://localhost:4001"
echo "Logs:   docker-compose -f docker-compose.prod.yml logs -f"
echo "Stop:   docker-compose -f docker-compose.prod.yml down"
