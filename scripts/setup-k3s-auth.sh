#!/bin/bash
#Author: Brandon Cantrell
set -e

echo "=== K3s Cluster Authentication & ArgoCD Setup ==="
echo ""

# Prompt for K3s master details
read -p "Enter K3s master node IP address: " K3S_MASTER_IP
read -p "Enter SSH user for K3s master (default: $(whoami)): " K3S_USER
K3S_USER=${K3S_USER:-$(whoami)}
read -p "Enter K3s API port (default: 6443): " K3S_PORT
K3S_PORT=${K3S_PORT:-6443}
read -p "Enter a name for this cluster context (default: homelab-k3s): " CONTEXT_NAME
CONTEXT_NAME=${CONTEXT_NAME:-homelab-k3s}

echo ""
echo ">>> Fetching kubeconfig from K3s master..."

# Fetch kubeconfig from K3s master
ssh ${K3S_USER}@${K3S_MASTER_IP} "sudo cat /etc/rancher/k3s/k3s.yaml" > /tmp/k3s-temp.yaml

# Create .kube directory if it doesn't exist
mkdir -p ~/.kube

# Backup existing config if it exists
if [ -f ~/.kube/config ]; then
    echo ">>> Backing up existing kubeconfig..."
    cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
fi

# Update server address in the kubeconfig
echo ">>> Updating server address to https://${K3S_MASTER_IP}:${K3S_PORT}..."
sed "s|server: https://127.0.0.1:6443|server: https://${K3S_MASTER_IP}:${K3S_PORT}|g" /tmp/k3s-temp.yaml > /tmp/k3s-updated.yaml

# Merge or create config
if [ -f ~/.kube/config ]; then
    echo ">>> Merging with existing kubeconfig..."
    KUBECONFIG=~/.kube/config:/tmp/k3s-updated.yaml kubectl config view --flatten > /tmp/k3s-merged.yaml
    mv /tmp/k3s-merged.yaml ~/.kube/config
else
    echo ">>> Creating new kubeconfig..."
    mv /tmp/k3s-updated.yaml ~/.kube/config
fi

# Set proper permissions
chmod 600 ~/.kube/config

# Rename context
echo ">>> Setting context name to '${CONTEXT_NAME}'..."
kubectl config rename-context default ${CONTEXT_NAME} 2>/dev/null || true

# Set as current context
kubectl config use-context ${CONTEXT_NAME}

# Clean up temp files
rm -f /tmp/k3s-temp.yaml /tmp/k3s-updated.yaml

echo ""
echo "=== K3s Setup Complete! ==="
echo ""
echo "Testing connection..."
if kubectl get nodes &>/dev/null; then
    echo "✅ Successfully connected to K3s cluster!"
    echo ""
    kubectl get nodes
else
    echo "❌ Failed to connect. Check your K3s master IP and firewall settings."
    echo "   Make sure port ${K3S_PORT} is accessible from this machine."
    exit 1
fi

# Check if ArgoCD is installed in the cluster
echo ""
echo ">>> Checking for ArgoCD installation..."
if kubectl get namespace argocd &>/dev/null; then
    echo "✅ ArgoCD namespace found"
    
    # Setup ArgoCD CLI authentication
    read -p "Do you want to configure ArgoCD CLI authentication? (y/n): " SETUP_ARGO
    
    if [[ "$SETUP_ARGO" =~ ^[Yy]$ ]]; then
        echo ""
        echo ">>> Setting up ArgoCD CLI authentication..."
        
        # Get ArgoCD server address
        read -p "Enter ArgoCD server address (e.g., argocd.example.com or localhost:8080): " ARGO_SERVER
        
        # Prompt for credentials
        read -p "Enter ArgoCD username (default: admin): " ARGO_USER
        ARGO_USER=${ARGO_USER:-admin}
        read -sp "Enter ArgoCD password: " ARGO_PASSWORD
        echo ""
        
        # Login to ArgoCD
        echo ">>> Logging in to ArgoCD..."
        if argocd login ${ARGO_SERVER} --username ${ARGO_USER} --password ${ARGO_PASSWORD} --insecure --grpc-web; then
            echo ""
            echo "✅ ArgoCD CLI authentication complete!"
            echo ""
            echo "Test with: argocd app list"
        else
            echo "❌ ArgoCD login failed. Check your credentials and server address."
        fi
    fi
else
    echo "⚠️  ArgoCD namespace not found in cluster"
    echo "   Install ArgoCD with:"
    echo "   kubectl create namespace argocd"
    echo "   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
fi

echo ""
echo "=== All Setup Complete! ==="
echo ""
echo "Your kubeconfig: ~/.kube/config"
echo "Current context: ${CONTEXT_NAME}"
if [ -f ~/.kube/config.backup.* ]; then
    echo "Previous config backed up to: ~/.kube/config.backup.*"
fi
echo ""
echo "Useful commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl config get-contexts"
echo "  argocd app list"
