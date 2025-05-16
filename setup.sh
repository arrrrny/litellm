#!/bin/bash

# Exit on error and print commands as they are executed
set -e
set -x

echo "=========== SYSTEM INFORMATION ==========="
echo "Operating system: $(uname -a)"
echo "Current directory: $(pwd)"

# Navigate to your litellm directory
cd ~/Developer/litellm

# Check Python
echo "=========== PYTHON INFORMATION ==========="
PYTHON_PATH=$(which python3)
echo "Using Python at: $PYTHON_PATH"
echo "Python version: $($PYTHON_PATH --version)"

# Check pip
echo "=========== PIP INFORMATION ==========="
if command -v pip3 &> /dev/null; then
    echo "pip3 version: $(pip3 --version)"
else
    echo "pip3 not found, installing..."
    python3 -m ensurepip --upgrade || echo "ensurepip failed, trying get-pip.py"
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python3 get-pip.py
    rm get-pip.py
fi

# Remove any existing venv to start fresh
echo "=========== SETTING UP VIRTUAL ENVIRONMENT ==========="
if [ -d "venv" ]; then
    echo "Removing existing virtual environment..."
    rm -rf venv
fi

# Create virtual environment
echo "Creating new virtual environment..."
python3 -m venv venv || {
    echo "Standard venv creation failed, trying with --without-pip option..."
    python3 -m venv venv --without-pip
    source venv/bin/activate
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python get-pip.py
    rm get-pip.py
}

# Activate the virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Verify the activation worked
echo "Python in venv: $(which python)"
echo "Pip in venv: $(which pip || echo 'pip not found')"

# Install dependencies
echo "=========== INSTALLING DEPENDENCIES ==========="
python -m pip install --upgrade pip || python3 -m pip install --upgrade pip
pip install httpx || python -m pip install httpx
pip install -e . || python -m pip install -e .

# Verify installation
echo "=========== VERIFYING INSTALLATION ==========="
pip list | grep -E 'litellm|httpx'

echo "=========== SETUP COMPLETE ==========="
echo "To activate the virtual environment, run:"
echo "source venv/bin/activate"
