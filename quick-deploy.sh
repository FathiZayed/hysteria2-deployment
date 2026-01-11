#!/bin/bash

# One-command deployment script
# Usage: curl -sSL https://raw.githubusercontent.com/FathiZayed/hysteria2-deployment/main/quick-deploy.sh | sudo bash

set -e

REPO_URL="https://github.com/FathiZayed/hysteria2-deployment.git"
DEPLOY_DIR="/opt/hysteria2"

echo "🚀 Hysteria2 Quick Deploy"
echo "=========================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

# Install git if needed
if ! command -v git &> /dev/null; then
    echo "📦 Installing git..."
    apt-get update -qq && apt-get install -y git
fi

# Clone or update repository
if [ -d "$DEPLOY_DIR" ]; then
    echo "📂 Updating existing installation..."
    cd "$DEPLOY_DIR"
    
    # **FIX: Reset local changes and clean before pulling**
    git reset --hard HEAD 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    git pull origin main 2>/dev/null || true
else
    echo "📥 Cloning repository..."
    git clone "$REPO_URL" "$DEPLOY_DIR"
    cd "$DEPLOY_DIR"
fi

# Make scripts executable
chmod +x deploy.sh

# Run deployment
echo "🔧 Running deployment script..."
./deploy.sh

echo ""
echo "✅ Deployment complete!"
echo "📍 Installation directory: $DEPLOY_DIR"
echo "📄 View credentials: cat $DEPLOY_DIR/hysteria2-credentials.txt"