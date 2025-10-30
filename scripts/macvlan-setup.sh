#!/bin/bash

################################################################################
# Docker Macvlan Network Setup Script
# Purpose: Configure VLAN interface and Docker macvlan network for homelab
################################################################################

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration Variables - CUSTOMIZE THESE
PHYSICAL_INTERFACE="enp39s0"
VLAN_ID="4"
VLAN_INTERFACE="${PHYSICAL_INTERFACE}.${VLAN_ID}"
DOCKER_NETWORK_NAME="homelab-macvlan"

# Network Configuration
SUBNET="192.168.4.0/26"
GATEWAY="192.168.4.1"
DOCKER_IP_RANGE="192.168.4.32/27"  # .32-.63 (32 IPs)

################################################################################
# Functions
################################################################################

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

check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if physical interface exists
    if ! ip link show "$PHYSICAL_INTERFACE" &>/dev/null; then
        print_error "Physical interface $PHYSICAL_INTERFACE not found"
        print_error "Available interfaces:"
        ip link show | grep "^[0-9]" | awk '{print $2}' | sed 's/:$//'
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker version
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    print_status "Docker version: $DOCKER_VERSION"
    
    print_status "Prerequisites check passed ✓"
}

install_packages() {
    print_status "Installing required packages..."
    
    apt-get update -qq
    apt-get install -y vlan &>/dev/null
    
    print_status "Packages installed ✓"
}

load_vlan_module() {
    print_status "Loading 8021q kernel module..."
    
    modprobe 8021q
    
    # Make persistent across reboots
    if ! grep -q "^8021q" /etc/modules 2>/dev/null; then
        echo "8021q" >> /etc/modules
        print_status "8021q module added to /etc/modules for persistence"
    fi
    
    print_status "8021q module loaded ✓"
}

create_vlan_interface() {
    print_status "Creating VLAN interface: $VLAN_INTERFACE..."
    
    # Check if VLAN interface already exists
    if nmcli connection show "$VLAN_INTERFACE" &>/dev/null; then
        print_warning "VLAN connection $VLAN_INTERFACE already exists"
        read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            nmcli connection delete "$VLAN_INTERFACE"
            print_status "Deleted existing connection"
        else
            print_status "Keeping existing connection"
            return 0
        fi
    fi
    
    # Create VLAN interface using NetworkManager
    nmcli connection add type vlan \
        con-name "$VLAN_INTERFACE" \
        ifname "$VLAN_INTERFACE" \
        dev "$PHYSICAL_INTERFACE" \
        id "$VLAN_ID"
    
    # Configure interface without IP (Docker macvlan doesn't need host IP)
    nmcli connection modify "$VLAN_INTERFACE" \
        ipv4.method disabled \
        ipv6.method disabled
    
    # Bring up the interface
    nmcli connection up "$VLAN_INTERFACE"
    
    # Verify interface is up
    if ip link show "$VLAN_INTERFACE" &>/dev/null; then
        print_status "VLAN interface $VLAN_INTERFACE created and UP ✓"
        ip link show "$VLAN_INTERFACE"
    else
        print_error "Failed to create VLAN interface"
        exit 1
    fi
}

create_docker_network() {
    print_status "Creating Docker macvlan network: $DOCKER_NETWORK_NAME..."
    
    # Check if network already exists
    if docker network ls | grep -q "$DOCKER_NETWORK_NAME"; then
        print_warning "Docker network $DOCKER_NETWORK_NAME already exists"
        read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker network rm "$DOCKER_NETWORK_NAME"
            print_status "Deleted existing network"
        else
            print_status "Keeping existing network"
            return 0
        fi
    fi
    
    # Create macvlan network
    docker network create -d macvlan \
        --subnet="$SUBNET" \
        --gateway="$GATEWAY" \
        --ip-range="$DOCKER_IP_RANGE" \
        -o parent="$VLAN_INTERFACE" \
        "$DOCKER_NETWORK_NAME"
    
    print_status "Docker macvlan network created ✓"
}

verify_setup() {
    print_status "Verifying setup..."
    
    echo ""
    print_status "VLAN Interface Status:"
    ip link show "$VLAN_INTERFACE"
    
    echo ""
    print_status "Docker Network Details:"
    docker network inspect "$DOCKER_NETWORK_NAME" | grep -A 10 "IPAM"
    
    echo ""
    print_status "Available Docker IP Range: $(echo "$DOCKER_IP_RANGE" | cut -d'/' -f1) - 192.168.4.63"
}

create_test_container() {
    print_status "Creating test container..."
    
    TEST_CONTAINER_NAME="test-macvlan"
    TEST_IP="192.168.4.35"
    
    # Remove existing test container if present
    if docker ps -a | grep -q "$TEST_CONTAINER_NAME"; then
        docker rm -f "$TEST_CONTAINER_NAME" &>/dev/null
    fi
    
    # Create test container
    docker run -d \
        --name "$TEST_CONTAINER_NAME" \
        --network "$DOCKER_NETWORK_NAME" \
        --ip "$TEST_IP" \
        nginx:alpine
    
    echo ""
    print_status "Test container created!"
    print_status "Access it from another device at: http://$TEST_IP"
    print_warning "Note: Ubuntu host CANNOT access containers directly (macvlan limitation)"
    echo ""
    read -p "Press enter to continue (test container will remain running)..."
}

show_summary() {
    echo ""
    echo "======================================================================"
    print_status "Setup Complete! ✓"
    echo "======================================================================"
    echo ""
    echo "Configuration Summary:"
    echo "  Physical Interface: $PHYSICAL_INTERFACE"
    echo "  VLAN ID: $VLAN_ID"
    echo "  VLAN Interface: $VLAN_INTERFACE"
    echo "  Docker Network: $DOCKER_NETWORK_NAME"
    echo "  Subnet: $SUBNET"
    echo "  Gateway: $GATEWAY"
    echo "  Docker IP Range: $DOCKER_IP_RANGE (.32-.63)"
    echo ""
    echo "Usage Example:"
    echo "  docker run -d --name myapp \\"
    echo "    --network $DOCKER_NETWORK_NAME \\"
    echo "    --ip 192.168.4.40 \\"
    echo "    nginx:alpine"
    echo ""
    echo "Important Notes:"
    echo "  - Containers get IPs from 192.168.4.32 - 192.168.4.63"
    echo "  - MetalLB uses: 192.168.4.20 - 192.168.4.30"
    echo "  - K8s nodes use: 192.168.4.10 - 192.168.4.11"
    echo "  - Ubuntu host CANNOT communicate with containers directly"
    echo "  - All other devices on network CAN access containers"
    echo "  - Add DNS entries manually in UniFi for *.opsguy.io"
    echo ""
    echo "======================================================================"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "======================================================================"
    echo "Docker Macvlan Network Setup"
    echo "======================================================================"
    echo ""
    
    check_root
    check_prerequisites
    install_packages
    load_vlan_module
    create_vlan_interface
    create_docker_network
    verify_setup
    
    echo ""
    read -p "Do you want to create a test container? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_test_container
    fi
    
    show_summary
}

# Run main function
main