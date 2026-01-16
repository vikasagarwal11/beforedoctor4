#!/bin/bash

# Install Remaining Dependencies
# This script installs CocoaPods, iOS dependencies, and gateway dependencies

set -e

echo "🚀 Installing remaining dependencies..."
echo ""

# Add Homebrew to PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# 1. Install CocoaPods
echo "🍎 Step 1: Installing CocoaPods..."
echo "   (This will ask for your password)"
if ! command -v pod &> /dev/null; then
    sudo gem install cocoapods
    echo "✅ CocoaPods installed!"
else
    echo "✅ CocoaPods already installed!"
fi

# 2. Install iOS dependencies
echo ""
echo "📱 Step 2: Installing iOS dependencies..."
cd "$(dirname "$0")/ios"
pod install
cd ..
echo "✅ iOS dependencies installed!"

# 3. Setup Node.js and install gateway dependencies
echo ""
echo "🌐 Step 3: Installing Gateway server dependencies..."
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Use Node.js if available
if command -v node &> /dev/null; then
    nvm use --lts 2>/dev/null || nvm use node 2>/dev/null || true
    cd gateway
    npm install
    cd ..
    echo "✅ Gateway dependencies installed!"
else
    echo "⚠️  Node.js not ready yet - gateway dependencies will install when Node.js is available"
    echo "   Run this later: cd gateway && npm install"
fi

# 4. Verify installations
echo ""
echo "🔍 Verifying installations..."
echo ""

if command -v pod &> /dev/null; then
    echo "✅ CocoaPods: $(pod --version)"
else
    echo "❌ CocoaPods not found"
fi

if command -v flutter &> /dev/null; then
    echo "✅ Flutter: $(flutter --version | head -1)"
else
    echo "❌ Flutter not found"
fi

if command -v node &> /dev/null; then
    echo "✅ Node.js: $(node --version)"
    echo "✅ npm: $(npm --version)"
else
    echo "⚠️  Node.js not found (may still be installing via nvm)"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "🎉 You can now run the app with:"
echo "   flutter run"
