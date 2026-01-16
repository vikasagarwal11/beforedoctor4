#!/bin/bash

# Quick install script - installs what can be done without sudo
# For full installation, see INSTALLATION_STEPS.md

set -e

echo "🚀 Quick Installation (non-sudo components)..."
echo ""

cd "$(dirname "$0")"

# Check if Node.js is available (via nvm)
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    echo "📦 Setting up Node.js via nvm..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    if ! command -v node &> /dev/null; then
        echo "   Installing Node.js LTS..."
        nvm install --lts
        nvm use --lts
    fi
    
    echo "✅ Node.js: $(node --version)"
    echo "✅ npm: $(npm --version)"
fi

# Install gateway server dependencies (if Node.js is available)
if command -v npm &> /dev/null; then
    echo ""
    echo "🌐 Installing gateway server dependencies..."
    cd gateway
    if [ ! -d "node_modules" ]; then
        npm install
        echo "✅ Gateway dependencies installed"
    else
        echo "✅ Gateway dependencies already installed"
    fi
    cd ..
else
    echo "⚠️  Node.js not available - skipping gateway dependencies"
    echo "   Install Node.js: brew install node"
fi

# Check Flutter
if command -v flutter &> /dev/null; then
    echo ""
    echo "📱 Flutter found: $(flutter --version | head -1)"
    
    # Install Flutter dependencies
    echo "📦 Installing Flutter dependencies..."
    flutter pub get
    echo "✅ Flutter dependencies installed"
    
    # Check if iOS pods are needed
    if [ -d "ios" ]; then
        echo ""
        echo "🍎 iOS directory found"
        if command -v pod &> /dev/null; then
            echo "   Installing iOS dependencies..."
            cd ios
            pod install
            cd ..
            echo "✅ iOS dependencies installed"
        else
            echo "⚠️  CocoaPods not found - install with: sudo gem install cocoapods"
        fi
    fi
    
    echo ""
    echo "📱 Available devices:"
    flutter devices
else
    echo ""
    echo "⚠️  Flutter not found in PATH"
    echo "   Install Flutter: brew install --cask flutter"
    echo "   Or download from: https://flutter.dev/docs/get-started/install/macos"
fi

echo ""
echo "✅ Quick installation complete!"
echo ""
echo "For full installation, see INSTALLATION_STEPS.md"
echo "Or run: ./install_all.sh (requires sudo for some steps)"
