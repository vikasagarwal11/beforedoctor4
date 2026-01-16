#!/bin/bash

# Installation script for Flutter app dependencies
# This script will install: Homebrew, Flutter, CocoaPods, and Node.js

set -e

echo "🚀 Installing dependencies for Flutter app testing..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Install Homebrew
if ! command_exists brew; then
    echo -e "${YELLOW}📦 Installing Homebrew...${NC}"
    echo "   This will require your password for sudo access"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH (for Apple Silicon Macs)
    if [ -f /opt/homebrew/bin/brew ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
    # For Intel Macs
    elif [ -f /usr/local/bin/brew ]; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    echo -e "${GREEN}✅ Homebrew installed${NC}"
else
    echo -e "${GREEN}✅ Homebrew already installed${NC}"
fi

# 2. Install Flutter
if ! command_exists flutter; then
    echo -e "${YELLOW}📱 Installing Flutter...${NC}"
    brew install --cask flutter
    echo -e "${GREEN}✅ Flutter installed${NC}"
    
    # Add Flutter to PATH if not already there
    if ! echo "$PATH" | grep -q "flutter/bin"; then
        echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
    fi
else
    echo -e "${GREEN}✅ Flutter already installed${NC}"
fi

# 3. Install CocoaPods
if ! command_exists pod; then
    echo -e "${YELLOW}🍎 Installing CocoaPods...${NC}"
    sudo gem install cocoapods
    echo -e "${GREEN}✅ CocoaPods installed${NC}"
else
    echo -e "${GREEN}✅ CocoaPods already installed${NC}"
fi

# 4. Install Node.js
if ! command_exists node; then
    echo -e "${YELLOW}📦 Installing Node.js...${NC}"
    brew install node
    echo -e "${GREEN}✅ Node.js installed${NC}"
else
    echo -e "${GREEN}✅ Node.js already installed${NC}"
fi

# 5. Verify installations
echo ""
echo -e "${YELLOW}🔍 Verifying installations...${NC}"
echo ""

if command_exists flutter; then
    flutter --version
    echo ""
else
    echo -e "${RED}❌ Flutter not found in PATH${NC}"
    echo "   Try running: source ~/.zshrc"
fi

if command_exists pod; then
    pod --version
    echo ""
else
    echo -e "${RED}❌ CocoaPods not found${NC}"
fi

if command_exists node; then
    echo "Node.js: $(node --version)"
    echo "npm: $(npm --version)"
    echo ""
else
    echo -e "${RED}❌ Node.js not found${NC}"
fi

# 6. Install Flutter dependencies
echo -e "${YELLOW}📦 Installing Flutter dependencies...${NC}"
cd "$(dirname "$0")"
flutter pub get
echo -e "${GREEN}✅ Flutter dependencies installed${NC}"

# 7. Install iOS CocoaPods dependencies
echo -e "${YELLOW}🍎 Installing iOS dependencies...${NC}"
cd ios
pod install
cd ..
echo -e "${GREEN}✅ iOS dependencies installed${NC}"

# 8. Install gateway server dependencies
echo -e "${YELLOW}🌐 Installing gateway server dependencies...${NC}"
cd gateway
npm install
cd ..
echo -e "${GREEN}✅ Gateway server dependencies installed${NC}"

# 9. Check available devices
echo ""
echo -e "${YELLOW}📱 Checking available devices...${NC}"
flutter devices

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Run the app: ./run_ios.sh"
echo "  2. Or manually: flutter run"
echo "  3. Start gateway server (if needed): cd gateway && npm start"
