#!/bin/bash

# Easy Flutter Installation Script
# This will guide you through installation

echo "🚀 Starting Flutter Installation..."
echo ""
echo "This script will install:"
echo "  1. Homebrew (if needed)"
echo "  2. Flutter"
echo "  3. CocoaPods"
echo "  4. All project dependencies"
echo ""
echo "You'll be asked for your password 2 times - that's normal!"
echo ""
read -p "Press Enter to continue..."

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo ""
    echo "📦 Step 1: Installing Homebrew..."
    echo "   (This will ask for your password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add to PATH
    if [ -f /opt/homebrew/bin/brew ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f /usr/local/bin/brew ]; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    echo "✅ Homebrew installed!"
else
    echo "✅ Homebrew already installed!"
fi

# Install Flutter
if ! command -v flutter &> /dev/null; then
    echo ""
    echo "📱 Step 2: Installing Flutter..."
    echo "   (This will take 5-10 minutes)"
    brew install --cask flutter
    echo "✅ Flutter installed!"
else
    echo "✅ Flutter already installed!"
fi

# Install CocoaPods
if ! command -v pod &> /dev/null; then
    echo ""
    echo "🍎 Step 3: Installing CocoaPods..."
    echo "   (This will ask for your password again)"
    sudo gem install cocoapods
    echo "✅ CocoaPods installed!"
else
    echo "✅ CocoaPods already installed!"
fi

# Install Flutter dependencies
echo ""
echo "📦 Step 4: Installing Flutter dependencies..."
cd "$(dirname "$0")"
flutter pub get
echo "✅ Flutter dependencies installed!"

# Install iOS dependencies
echo ""
echo "🍎 Step 5: Installing iOS dependencies..."
cd ios
pod install
cd ..
echo "✅ iOS dependencies installed!"

# Verify
echo ""
echo "🔍 Verifying installation..."
flutter --version
echo ""

echo "✅ Installation Complete!"
echo ""
echo "🎉 Now you can run the app with:"
echo "   flutter run"
echo ""

