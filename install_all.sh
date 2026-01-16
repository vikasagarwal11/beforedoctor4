#!/bin/bash

# Complete Installation Script for BeforeDoctor App
# This script installs all required components

set -e

echo "🚀 Installing all required components for BeforeDoctor App..."
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Install Homebrew
echo -e "${YELLOW}📦 Step 1: Installing Homebrew...${NC}"
if ! command_exists brew; then
    echo "   This will require your password for sudo access"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH
    if [ -f /opt/homebrew/bin/brew ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo -e "${GREEN}✅ Homebrew installed (Apple Silicon)${NC}"
    elif [ -f /usr/local/bin/brew ]; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/usr/local/bin/brew shellenv)"
        echo -e "${GREEN}✅ Homebrew installed (Intel)${NC}"
    fi
else
    echo -e "${GREEN}✅ Homebrew already installed${NC}"
fi

# 2. Install Flutter
echo ""
echo -e "${YELLOW}📱 Step 2: Installing Flutter...${NC}"
if ! command_exists flutter; then
    brew install --cask flutter
    echo -e "${GREEN}✅ Flutter installed${NC}"
    
    # Add Flutter to PATH if needed
    if ! echo "$PATH" | grep -q "flutter/bin"; then
        echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
    fi
else
    echo -e "${GREEN}✅ Flutter already installed${NC}"
fi

# Verify Flutter
if command_exists flutter; then
    flutter --version
    echo ""
    echo -e "${YELLOW}Running flutter doctor...${NC}"
    flutter doctor --android-licenses || true
else
    echo -e "${RED}❌ Flutter installation failed${NC}"
    exit 1
fi

# 3. Install CocoaPods
echo ""
echo -e "${YELLOW}🍎 Step 3: Installing CocoaPods...${NC}"
if ! command_exists pod; then
    echo "   This will require your password for sudo access"
    sudo gem install cocoapods
    echo -e "${GREEN}✅ CocoaPods installed${NC}"
else
    echo -e "${GREEN}✅ CocoaPods already installed${NC}"
fi

# 4. Setup Node.js (via nvm)
echo ""
echo -e "${YELLOW}📦 Step 4: Setting up Node.js...${NC}"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    if ! command_exists node; then
        nvm install --lts
        nvm use --lts
    fi
    
    echo -e "${GREEN}✅ Node.js: $(node --version)${NC}"
    echo -e "${GREEN}✅ npm: $(npm --version)${NC}"
else
    # Install nvm if not present
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    echo -e "${GREEN}✅ Node.js installed via nvm${NC}"
fi

# 5. Install Flutter dependencies
echo ""
echo -e "${YELLOW}📦 Step 5: Installing Flutter dependencies...${NC}"
cd "$(dirname "$0")"
flutter pub get
echo -e "${GREEN}✅ Flutter dependencies installed${NC}"

# 6. Install iOS dependencies
echo ""
echo -e "${YELLOW}🍎 Step 6: Installing iOS dependencies...${NC}"
cd ios
pod install
cd ..
echo -e "${GREEN}✅ iOS dependencies installed${NC}"

# 7. Install Gateway dependencies
echo ""
echo -e "${YELLOW}🌐 Step 7: Installing Gateway server dependencies...${NC}"
cd gateway
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use --lts
npm install
cd ..
echo -e "${GREEN}✅ Gateway dependencies installed${NC}"

# 8. Verify installations
echo ""
echo -e "${YELLOW}🔍 Step 8: Verifying installations...${NC}"
echo ""

if command_exists flutter; then
    echo -e "${GREEN}✅ Flutter: $(flutter --version | head -1)${NC}"
else
    echo -e "${RED}❌ Flutter not found${NC}"
fi

if command_exists pod; then
    echo -e "${GREEN}✅ CocoaPods: $(pod --version)${NC}"
else
    echo -e "${RED}❌ CocoaPods not found${NC}"
fi

if command_exists node; then
    echo -e "${GREEN}✅ Node.js: $(node --version)${NC}"
    echo -e "${GREEN}✅ npm: $(npm --version)${NC}"
else
    echo -e "${RED}❌ Node.js not found${NC}"
fi

# 9. Check available devices
echo ""
echo -e "${YELLOW}📱 Available devices:${NC}"
flutter devices

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Start gateway server: cd gateway && npm start"
echo "  2. Run the app: flutter run"
echo "  3. Or use: ./run_ios.sh"
