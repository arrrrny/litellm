#!/bin/bash
# fix_encryption_issues.sh - Clean database and fix encryption issues

set -e

echo "🔧 Fixing LiteLLM Encryption Issues"
echo "=================================="
echo ""

# Stop services
echo "1. Stopping services..."
docker-compose -f docker-compose.prod.yml down

# Backup GitHub Copilot auth
echo "2. Backing up GitHub Copilot auth..."
./backup_copilot_auth.sh backup || echo "Could not backup (may not exist)"

# Remove database volume to start fresh
echo "3. Removing old database volume..."
docker volume rm litellm_postgres_data_prod 2>/dev/null || echo "No old database volume found"

# Clean up any corrupted volumes
echo "4. Cleaning up potentially corrupted data..."
docker volume prune -f

# Generate a proper salt key
echo "5. Generating new salt key..."
NEW_SALT=$(echo -n "$(openssl rand -hex 32)" | base64)
sed -i.bak "s/LITELLM_SALT_KEY=.*/LITELLM_SALT_KEY=\"$NEW_SALT\"/" .env.prod
echo "   New salt key generated and saved to .env.prod"

# Start services with fresh database
echo "6. Starting services with fresh database..."
docker-compose -f docker-compose.prod.yml up -d

# Wait for services
echo "7. Waiting for services to start..."
sleep 30

# Check if services are healthy
echo "8. Checking service health..."
if curl -s http://localhost:4000/ >/dev/null 2>&1; then
    echo "✅ Services are running successfully!"
else
    echo "⚠️  Services may still be starting..."
fi

echo ""
echo "🎉 Encryption issues should now be resolved!"
echo ""
echo "Services starting up - check logs with:"
echo "docker-compose -f docker-compose.prod.yml logs -f"
echo ""
echo "Check status with:"
echo "./production_status.sh"