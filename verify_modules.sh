#!/bin/bash

# Docker-focused verification script for LiteLLM
# This checks everything needed for proper Docker deployment

set -e
set -o pipefail

echo "=== DOCKER DEPLOYMENT VERIFICATION ==="
echo

MODULE_DIR="litellm/llms"
ZIKZAK_MODULE_DIR="$MODULE_DIR/zikzak"
GITHUB_COPILOT_MODULE_DIR="$MODULE_DIR/github_copilot"

# Function to check for file existence
check_file() {
    if [ -f "$1" ]; then
        echo "✓ File exists: $1"
    else
        echo "✗ ERROR: File missing: $1"
        ERRORS=1
    fi
}

# Function to check for directory existence
check_dir() {
    if [ -d "$1" ]; then
        echo "✓ Directory exists: $1"
    else
        echo "✗ ERROR: Directory missing: $1"
        ERRORS=1
    fi
}

echo "=== 1. Verifying Files Needed for Docker ==="

# Check Docker files
check_file "Dockerfile"
check_file "docker-compose.yml"
check_file "config.yaml"

# Check module bridge file (critical for Docker)
check_file "$MODULE_DIR/zikzak.py"

# Check critical implementation files
check_dir "$ZIKZAK_MODULE_DIR"
check_file "$ZIKZAK_MODULE_DIR/zikzak.py"
check_file "$ZIKZAK_MODULE_DIR/__init__.py"
check_file "$ZIKZAK_MODULE_DIR/rules.json"

check_dir "$GITHUB_COPILOT_MODULE_DIR"
check_file "$GITHUB_COPILOT_MODULE_DIR/authenticator.py"
check_file "$GITHUB_COPILOT_MODULE_DIR/__init__.py"

echo
echo "=== 2. Verifying Configuration ==="

# Check custom provider configuration
if grep -q "custom_provider_map:" config.yaml && grep -q "provider: \"zikzak\"" config.yaml; then
    echo "✓ Config contains ZikZak provider configuration"
else
    echo "✗ ERROR: Config missing proper ZikZak provider config"
    ERRORS=1
fi

# Check handler path
if grep -q "custom_handler: \"litellm.llms.zikzak\"" config.yaml; then
    echo "✓ Config contains correct ZikZak handler path"
else
    echo "✗ ERROR: Config has incorrect ZikZak handler path"
    ERRORS=1
fi

# Check model configurations
if grep -q "model_name: zikzak/z1" config.yaml; then
    echo "✓ Config contains ZikZak model definition"
else
    echo "✗ ERROR: Config missing ZikZak model definition"
    ERRORS=1
fi

if grep -q "model_name: github_copilot/" config.yaml; then
    echo "✓ Config contains GitHub Copilot model definitions"
else
    echo "✗ ERROR: Config missing GitHub Copilot model definitions"
    ERRORS=1
fi

echo
echo "=== 3. Verifying Docker Setup ==="

# Check volume for persistent GitHub Copilot auth
if grep -q "github_copilot_auth:/root/.config/litellm/github_copilot" docker-compose.yml; then
    echo "✓ Docker Compose contains GitHub Copilot volume"
else
    echo "✗ ERROR: Docker Compose missing GitHub Copilot volume"
    ERRORS=1
fi

# Check for config mount
if grep -q "./config.yaml:/app/config.yaml" docker-compose.yml; then
    echo "✓ Docker Compose mounts config.yaml correctly"
else
    echo "✗ ERROR: Docker Compose missing config.yaml mount"
    ERRORS=1
fi

# Check Docker entrypoint and command
if grep -q "\- \"--config=/app/config.yaml\"" docker-compose.yml; then
    echo "✓ Docker Compose command includes config.yaml"
else
    echo "✗ ERROR: Docker Compose command not properly configured"
    ERRORS=1
fi

# Check for symbolic link or directory creation in Dockerfile
if grep -q "mkdir -p /app/litellm/llms" Dockerfile && grep -q "litellm/llms/zikzak" Dockerfile; then
    echo "✓ Dockerfile creates necessary directories for ZikZak module"
else
    echo "✗ WARNING: Dockerfile might be missing directory setup for ZikZak module"
    # Not critical, just a warning
fi

# Check for httpx installation (needed by GitHub Copilot)
if grep -q "httpx" Dockerfile; then
    echo "✓ Dockerfile installs httpx (required for GitHub Copilot)"
else 
    echo "✗ WARNING: Dockerfile might be missing httpx installation"
fi

echo
echo "=== 4. Checking Bridge Module ==="
# View the content of the bridge module
echo "Bridge module content:"
echo "---------------------"
head -n 10 "$MODULE_DIR/zikzak.py"
echo "---------------------"

# Final report
echo
if [ "$ERRORS" == "1" ]; then
    echo "=== Docker Verification FAILED: Please fix the issues above ==="
    echo "You may need to rebuild the Docker image after changes."
    exit 1
else
    echo "=== Docker Verification PASSED ==="
    echo "Your setup should work with Docker! Run the following to test:"
    echo "  docker-compose down -v && docker-compose build && docker-compose up"
fi