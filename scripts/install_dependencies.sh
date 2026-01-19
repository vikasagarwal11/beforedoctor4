#!/bin/bash
# Install required dependencies for physical device logging

echo "📦 Installing dependencies for physical device logging..."
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "✅ Homebrew is already installed"
fi

# Install libimobiledevice for physical device logging
if ! command -v idevicesyslog &> /dev/null; then
    echo "📱 Installing libimobiledevice for iOS device logging..."
    brew install libimobiledevice
    echo "✅ libimobiledevice installed"
else
    echo "✅ libimobiledevice is already installed"
fi

echo ""
echo "✅ All dependencies installed!"
echo ""
