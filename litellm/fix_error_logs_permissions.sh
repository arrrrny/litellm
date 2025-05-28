#!/bin/bash
# fix_error_logs_permissions.sh - Ensure error logs volume has correct permissions

set -eo pipefail # Exit on error, pipe failure

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}===== GitHub Copilot Error Logs Permission Fix =====${NC}"
echo "This script ensures that the error_logs volume is properly mounted and writable"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
  exit 1
fi

# Verify the error_logs volume exists
if ! docker volume inspect litellm_error_logs > /dev/null 2>&1; then
  echo -e "${YELLOW}Creating error logs volume...${NC}"
  docker volume create litellm_error_logs
  echo -e "${GREEN}Created volume: litellm_error_logs${NC}"
else
  echo -e "${GREEN}Found volume: litellm_error_logs${NC}"

  # Remove any potential problematic permissions
  echo -e "${YELLOW}Cleaning up any permission issues...${NC}"
  TEMP_CONTAINER="permission-fixer"
  docker run --rm --name $TEMP_CONTAINER -v litellm_error_logs:/data alpine:latest sh -c "chmod -R 777 /data || true"
fi

# Find the running litellm container
CONTAINER=$(docker ps | grep -E 'litellm(-litellm-1|_litellm_1)' | grep -v grep | awk '{print $1}' | head -1)

# If not found, try broader search
if [ -z "$CONTAINER" ]; then
  CONTAINER=$(docker ps | grep litellm | grep -v grep | awk '{print $1}' | head -1)
fi

if [ -z "$CONTAINER" ]; then
  echo -e "${RED}Error: No running litellm container found.${NC}"
  echo "Please make sure your litellm container is running."
  exit 1
fi

echo -e "${YELLOW}Using container: $CONTAINER${NC}"

# Create the error_logs directory in the container and set permissions
echo "Creating /app/error_logs directory in the container..."
docker exec $CONTAINER sh -c "mkdir -p /app/error_logs && chmod -R 777 /app/error_logs && chown -R $(docker exec $CONTAINER id -u):$(docker exec $CONTAINER id -g) /app/error_logs"

# Double-check permissions
echo "Verifying permissions..."
docker exec $CONTAINER ls -la /app/error_logs

# Create a test file to verify write permissions - try multiple methods
TEST_CONTENT="Test file created at $(date)"
echo "Creating test file to verify write permissions..."

# Try with bash first
docker exec $CONTAINER sh -c "echo '$TEST_CONTENT' > /app/error_logs/test_write.txt || touch /app/error_logs/test_write.txt"

# Make sure the file exists and is writable
docker exec $CONTAINER sh -c "touch /app/error_logs/test_write.txt && chmod 666 /app/error_logs/test_write.txt && echo '$TEST_CONTENT' > /app/error_logs/test_write.txt"

# Verify the test file was created
if docker exec $CONTAINER sh -c "cat /app/error_logs/test_write.txt | grep -q \"$TEST_CONTENT\" || echo '$TEST_CONTENT' > /app/error_logs/test_write.txt && cat /app/error_logs/test_write.txt | grep -q \"$TEST_CONTENT\""; then
  echo -e "${GREEN}Success! The error_logs volume is writable.${NC}"
else
  echo -e "${RED}Error: Failed to write to error_logs volume.${NC}"
  echo "This might indicate a problem with the volume mounting or permissions."
  echo "Attempting to fix with direct volume mount..."

  # Final attempt with a temporary container
  docker run --rm -v litellm_error_logs:/mnt alpine:latest sh -c "echo '$TEST_CONTENT' > /mnt/outside_test.txt && chmod -R 777 /mnt"
  echo -e "${YELLOW}Volume permissions reset with temporary container. Please restart your litellm container.${NC}"
fi

echo -e "${YELLOW}Creating error logger script in container...${NC}"
# Copy the error logger script to the container if it exists
if [ -f "copilot_error_logger.py" ]; then
  docker cp copilot_error_logger.py $CONTAINER:/app/copilot_error_logger.py
  docker exec $CONTAINER chmod +x /app/copilot_error_logger.py
  echo -e "${GREEN}Copied and made executable: copilot_error_logger.py${NC}"
else
  echo -e "${YELLOW}Writing basic error logger script to container...${NC}"
  ERROR_LOGGER_CONTENT=$(cat <<'EOF'
import os, datetime, json

def log_error(error_dict):
    """Log an error to the error_logs directory"""
    log_dir = "/app/error_logs"
    os.makedirs(log_dir, exist_ok=True)

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"error_{timestamp}.log"
    filepath = os.path.join(log_dir, filename)

    with open(filepath, "w") as f:
        f.write(json.dumps(error_dict, indent=2))

    print(f"Error logged to {filepath}")

# Create a test error log
test_error = {
    "test": True,
    "timestamp": str(datetime.datetime.now()),
    "message": "This is a test error log"
}
log_error(test_error)
EOF
)
  docker exec -i $CONTAINER sh -c "cat > /app/simple_error_logger.py" <<< "$ERROR_LOGGER_CONTENT"
  docker exec $CONTAINER python /app/simple_error_logger.py
  echo -e "${GREEN}Created and tested a simple error logger${NC}"
fi

echo ""
echo -e "${GREEN}====== Setup Complete ======${NC}"
echo "The error_logs volume should now be properly configured and writable."
echo ""
echo "To start the error logger (inside the container):"
echo "  docker exec -it $CONTAINER python /app/copilot_error_logger.py"
echo ""
echo "To monitor logs outside the container:"
echo "  docker exec $CONTAINER tail -f /app/error_logs/error_*.log"
echo ""
echo "To quickly test error logging in your application, add this code:"
echo -e "${YELLOW}
import os, json, datetime
def log_copilot_error(error_info):
    try:
        log_dir = '/app/error_logs'
        os.makedirs(log_dir, exist_ok=True)
        timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        error_path = f'{log_dir}/copilot_error_{timestamp}.log'
        with open(error_path, 'w') as f:
            f.write(json.dumps(error_info, indent=2))
        print(f'Error logged to {error_path}')
    except Exception as e:
        print(f'Failed to log error: {e}')
${NC}"
echo ""
