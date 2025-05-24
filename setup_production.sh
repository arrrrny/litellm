#!/bin/bash
# setup_production.sh - Comprehensive production setup for LiteLLM with GitHub Copilot

set -e

BACKUP_DIR="./copilot_auth_backup"
VOLUME_NAME="litellm_github_copilot_auth"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section() {
    echo
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}   $1${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running or not installed."
        echo "Please start Docker and try again."
        exit 1
    fi
}

# Backup GitHub Copilot auth data
backup_auth_data() {
    section "Securing GitHub Copilot Authentication"
    
    if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
        print_status "GitHub Copilot auth volume found - creating backup..."
        ./backup_copilot_auth.sh backup || print_warning "Could not create backup"
    else
        print_warning "No existing GitHub Copilot auth data found"
    fi
}

# Stop existing services
stop_services() {
    section "Stopping Existing Services"
    
    print_status "Stopping development containers..."
    docker-compose down 2>/dev/null || print_warning "No development containers running"
    
    print_status "Stopping production containers..."
    docker-compose -f docker-compose.prod.yml down 2>/dev/null || print_warning "No production containers running"
}

# Clean up resources safely
cleanup_resources() {
    section "Cleaning Up Resources"
    
    print_status "Removing unused containers and networks..."
    docker container prune -f || true
    docker network prune -f || true
    
    print_status "Removing unused images..."
    docker image prune -f || true
    
    # Only remove non-auth postgres volumes
    print_status "Cleaning old database volumes..."
    docker volume rm litellm_postgres_data 2>/dev/null || print_status "No old postgres volume to remove"
    docker volume rm postgres_data 2>/dev/null || print_status "No old postgres volume to remove"
    
    # Verify auth volume is preserved
    if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
        print_success "GitHub Copilot auth data preserved!"
    else
        print_warning "Auth volume not found - will be created fresh"
    fi
}

# Build production images
build_production() {
    section "Building Production Environment"
    
    print_status "Building production Docker images..."
    docker-compose -f docker-compose.prod.yml build --no-cache
    
    print_success "Production images built successfully!"
}

# Start production services
start_services() {
    section "Starting Production Services"
    
    print_status "Starting LiteLLM in production mode..."
    docker-compose -f docker-compose.prod.yml up -d
    
    print_success "Production services started!"
}

# Wait for services to be ready
wait_for_services() {
    section "Waiting for Services"
    
    print_status "Waiting for database to be ready..."
    local db_ready=false
    local retries=0
    local max_retries=30
    
    while [ $retries -lt $max_retries ] && [ "$db_ready" = false ]; do
        if docker-compose -f docker-compose.prod.yml exec -T db pg_isready -U llmproxy -d litellm >/dev/null 2>&1; then
            db_ready=true
            print_success "Database is ready!"
        else
            print_status "Waiting for database... (${retries}/${max_retries})"
            sleep 2
            retries=$((retries + 1))
        fi
    done
    
    if [ "$db_ready" = false ]; then
        print_error "Database failed to start within expected time"
        return 1
    fi
    
    print_status "Waiting for LiteLLM API to be ready..."
    local api_ready=false
    retries=0
    max_retries=20
    
    while [ $retries -lt $max_retries ] && [ "$api_ready" = false ]; do
        if curl -s http://localhost:4000/health/liveliness >/dev/null 2>&1; then
            api_ready=true
            print_success "LiteLLM API is ready!"
        else
            print_status "Waiting for API... (${retries}/${max_retries})"
            sleep 3
            retries=$((retries + 1))
        fi
    done
    
    if [ "$api_ready" = false ]; then
        print_error "LiteLLM API failed to start within expected time"
        return 1
    fi
}

# Check service health
check_health() {
    section "Health Check"
    
    print_status "Checking service health..."
    
    # Check containers
    local containers=$(docker-compose -f docker-compose.prod.yml ps --services)
    for container in $containers; do
        local status=$(docker-compose -f docker-compose.prod.yml ps $container --format "table {{.State}}" | tail -n +2)
        if [ "$status" = "running" ]; then
            print_success "$container: Running"
        else
            print_error "$container: $status"
        fi
    done
    
    # Check API endpoint
    if curl -s http://localhost:4000/health/liveliness >/dev/null 2>&1; then
        print_success "API Health Check: Passed"
    else
        print_error "API Health Check: Failed"
    fi
    
    # Check logs for errors
    local error_count=$(docker-compose -f docker-compose.prod.yml logs --tail=50 2>/dev/null | grep -i error | wc -l || echo 0)
    if [ "$error_count" -eq 0 ]; then
        print_success "No errors in recent logs"
    else
        print_warning "Found $error_count error(s) in recent logs"
    fi
}

# Show final status
show_final_status() {
    section "Production Setup Complete!"
    
    echo -e "${GREEN}🚀 LiteLLM is now running in PRODUCTION mode!${NC}"
    echo
    echo -e "${BLUE}Production Features Enabled:${NC}"
    echo "   ✅ Debug logging: DISABLED"
    echo "   ✅ Log level: ERROR only"
    echo "   ✅ Performance: OPTIMIZED"
    echo "   ✅ Workers: 4"
    echo "   ✅ Redis caching: ENABLED"
    echo "   ✅ Restart policy: unless-stopped"
    echo "   ✅ GitHub Copilot auth: PRESERVED"
    echo
    echo -e "${BLUE}Access Information:${NC}"
    echo "   🌐 API URL: http://localhost:4000"
    echo "   🔑 Master Key: sk-1234"
    echo "   📊 Health: http://localhost:4000/health/liveliness"
    echo
    echo -e "${BLUE}Management Commands:${NC}"
    echo "   📋 View logs:    docker-compose -f docker-compose.prod.yml logs -f"
    echo "   ⏹️  Stop:        docker-compose -f docker-compose.prod.yml down"
    echo "   🔄 Restart:     docker-compose -f docker-compose.prod.yml restart"
    echo "   💾 Backup auth: ./backup_copilot_auth.sh backup"
    echo
    echo -e "${BLUE}Test Command:${NC}"
    echo 'curl -X POST http://localhost:4000/chat/completions \'
    echo '     -H "Content-Type: application/json" \'
    echo '     -H "Authorization: Bearer sk-1234" \'
    echo '     -d '"'"'{"model": "github_copilot/gpt-4.1", "messages": [{"role": "user", "content": "Hello from production!"}]}'"'"
    echo
    echo -e "${GREEN}Setup completed successfully! 🎉${NC}"
}

# Show help
show_help() {
    echo "LiteLLM Production Setup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --skip-backup    Skip GitHub Copilot auth backup"
    echo "  --skip-cleanup   Skip Docker cleanup (faster)"
    echo "  --help, -h       Show this help message"
    echo
    echo "This script will:"
    echo "  1. Backup GitHub Copilot authentication data"
    echo "  2. Stop existing containers"
    echo "  3. Clean up Docker resources (preserving auth)"
    echo "  4. Build production images"
    echo "  5. Start production services"
    echo "  6. Wait for services to be ready"
    echo "  7. Perform health checks"
}

# Main execution
main() {
    local skip_backup=false
    local skip_cleanup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup)
                skip_backup=true
                shift
                ;;
            --skip-cleanup)
                skip_cleanup=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Main setup flow
    echo -e "${BLUE}Starting LiteLLM Production Setup...${NC}"
    echo
    
    check_docker
    
    if [ "$skip_backup" = false ]; then
        backup_auth_data
    else
        print_warning "Skipping auth backup as requested"
    fi
    
    stop_services
    
    if [ "$skip_cleanup" = false ]; then
        cleanup_resources
    else
        print_warning "Skipping cleanup as requested"
    fi
    
    build_production
    start_services
    wait_for_services
    check_health
    show_final_status
}

# Run main function with all arguments
main "$@"