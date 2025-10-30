#!/bin/bash

################################################################################
# NVIDIA Container Toolkit Installation Script
# Purpose: Install NVIDIA Container Toolkit to enable GPU access in Docker
################################################################################

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_nvidia_drivers() {
    print_status "Checking for NVIDIA drivers..."
    
    if ! command -v nvidia-smi &>/dev/null; then
        print_error "nvidia-smi not found. Please install NVIDIA drivers first."
        print_error "Visit: https://www.nvidia.com/Download/index.aspx"
        exit 1
    fi
    
    print_status "NVIDIA drivers found:"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
}

check_docker() {
    print_status "Checking for Docker..."
    
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    print_status "Docker version: $DOCKER_VERSION"
}

remove_old_repo() {
    print_status "Removing any existing repository configuration..."
    
    if [ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]; then
        rm /etc/apt/sources.list.d/nvidia-container-toolkit.list
        print_status "Removed old repository file"
    fi
}

install_toolkit() {
    print_status "Installing NVIDIA Container Toolkit..."
    
    # Add GPG key
    print_status "Adding NVIDIA GPG key..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    # Add repository
    print_status "Adding NVIDIA Container Toolkit repository..."
    echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH=; [ \"\$(uname -m)\" = \"aarch64\" ] && ARCH=arm64 || ARCH=amd64; echo \$ARCH) /" | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Update package list
    print_status "Updating package lists..."
    apt-get update -qq
    
    # Install toolkit
    print_status "Installing nvidia-container-toolkit package..."
    apt-get install -y nvidia-container-toolkit
    
    print_status "NVIDIA Container Toolkit installed ✓"
}

configure_docker() {
    print_status "Configuring Docker to use NVIDIA runtime..."
    
    nvidia-ctk runtime configure --runtime=docker
    
    print_status "Restarting Docker service..."
    systemctl restart docker
    
    # Wait for Docker to restart
    sleep 3
    
    print_status "Docker configured ✓"
}

test_installation() {
    print_status "Testing NVIDIA GPU access in Docker..."
    
    echo ""
    if docker run --rm --runtime=nvidia --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi; then
        echo ""
        print_status "Test successful! GPU is accessible from Docker ✓"
    else
        echo ""
        print_error "Test failed. GPU may not be accessible from Docker"
        exit 1
    fi
}

show_summary() {
    echo ""
    echo "======================================================================"
    print_status "Installation Complete! ✓"
    echo "======================================================================"
    echo ""
    echo "Your Docker containers can now access NVIDIA GPU(s)"
    echo ""
    echo "To use GPU in a container, add to your docker-compose.yml:"
    echo ""
    echo "  services:"
    echo "    myapp:"
    echo "      runtime: nvidia"
    echo "      environment:"
    echo "        - NVIDIA_VISIBLE_DEVICES=all"
    echo "        - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility"
    echo ""
    echo "Or for 'docker run' command:"
    echo "  docker run --runtime=nvidia --gpus all [image]"
    echo ""
    echo "======================================================================"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "======================================================================"
    echo "NVIDIA Container Toolkit Installation"
    echo "======================================================================"
    echo ""
    
    check_root
    check_nvidia_drivers
    check_docker
    remove_old_repo
    install_toolkit
    configure_docker
    test_installation
    show_summary
}

# Run main function
main