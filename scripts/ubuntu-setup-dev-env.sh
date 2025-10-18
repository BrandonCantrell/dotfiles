#!/bin/bash
set -e  # Exit on any error

echo "=== Ubuntu Development Environment Setup ==="
echo ""

# Update system
echo ">>> Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Python essentials
echo ">>> Installing Python development tools..."
sudo apt install -y python3-pip python3-venv python3-dev build-essential pipx

# Ensure pipx path
pipx ensurepath

# Install Python global tools
echo ">>> Installing Python global tools..."
pipx install poetry
pipx install black
pipx install ruff
pipx install ipython

# Docker (if not already installed)
if ! command -v docker &> /dev/null; then
    echo ">>> Installing Docker..."
    sudo apt install -y docker.io docker-compose-v2
    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    echo "⚠️  Log out and back in for Docker group to take effect"
else
    echo ">>> Docker already installed, skipping..."
fi

# Kubernetes tools
echo ">>> Installing Kubernetes tools..."

# kubectl
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# k9s
if ! command -v k9s &> /dev/null; then
    curl -sS https://webinstall.dev/k9s | bash
fi

# helm
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ArgoCD CLI
if ! command -v argocd &> /dev/null; then
    echo ">>> Installing ArgoCD CLI..."
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
else
    echo ">>> ArgoCD CLI already installed, skipping..."
fi

# Terraform
if ! command -v terraform &> /dev/null; then
    echo ">>> Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
else
    echo ">>> Terraform already installed, skipping..."
fi

# VSCode extensions (if code is installed)
if command -v code &> /dev/null; then
    echo ">>> Installing VSCode extensions..."
    code --install-extension ms-python.python
    code --install-extension ms-python.debugpy
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
    code --install-extension eamodio.gitlens
    code --install-extension ms-vscode-remote.remote-ssh
    code --install-extension hashicorp.terraform
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "⚠️  Important next steps:"
echo "1. Log out and back in for Docker group to take effect"
echo "2. Run 'source ~/.bashrc' or restart terminal for pipx path"
echo ""
echo "Installed tools:"
echo "  - Python 3 + venv + pip"
echo "  - pipx + poetry + black + ruff + ipython"
echo "  - Docker + docker-compose"
echo "  - kubectl + k9s + helm"
echo "  - ArgoCD CLI"
echo "  - Terraform"
if command -v code &> /dev/null; then
    echo "  - VSCode extensions (Python, Docker, K8s, GitLens, Remote-SSH, Terraform)"
fi
