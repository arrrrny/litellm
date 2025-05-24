#!/bin/bash
# production_status.sh - Show LiteLLM Production Status

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 LiteLLM Production Status${NC}"
echo "==============================="
echo

# Check service status
echo -e "${BLUE}Service Status:${NC}"
docker-compose -f docker-compose.prod.yml ps

echo
echo -e "${BLUE}Health Check:${NC}"
if curl -s http://localhost:4000/ >/dev/null 2>&1; then
    echo -e "${GREEN}✅ API is accessible${NC}"
else
    echo -e "${YELLOW}❌ API is not accessible${NC}"
fi

echo
echo -e "${BLUE}Configuration:${NC}"
echo "  • Debug logging: DISABLED (ERROR level only)"
echo "  • GitHub Copilot auth: PRESERVED"
echo "  • Database: PostgreSQL (persistent)"
echo "  • Master key: sk-1234"
echo "  • Workers: 4"
echo "  • Restart policy: unless-stopped"

echo
echo -e "${BLUE}Available Models:${NC}"
curl -s -H "Authorization: Bearer sk-1234" http://localhost:4000/v2/model/info 2>/dev/null | \
  jq -r '.data[].model_name' 2>/dev/null || echo "  Could not fetch models (jq not installed or API not ready)"

echo
echo -e "${BLUE}Quick Test:${NC}"
echo "curl -X POST http://localhost:4000/chat/completions \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -H \"Authorization: Bearer sk-1234\" \\"
echo "     -d '{\"model\": \"github_copilot/gpt-4.1\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"

echo
echo -e "${BLUE}Management Commands:${NC}"
echo "  View logs:  docker-compose -f docker-compose.prod.yml logs -f"
echo "  Stop:       docker-compose -f docker-compose.prod.yml down"
echo "  Restart:    docker-compose -f docker-compose.prod.yml restart"
echo "  Backup:     ./backup_copilot_auth.sh backup"

echo
echo -e "${GREEN}Production mode is active! 🎉${NC}"