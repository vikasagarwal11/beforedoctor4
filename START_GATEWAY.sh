#!/bin/bash

# Start Gateway Server with proper Node.js setup

cd "$(dirname "$0")/gateway"

# Try to load nvm
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    echo "✅ nvm loaded"
elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
    . "/opt/homebrew/opt/nvm/nvm.sh"
    echo "✅ nvm loaded from Homebrew"
fi

# Check if npm is available
if ! command -v npm &> /dev/null; then
    echo "❌ npm not found. Please install Node.js:"
    echo ""
    echo "Option 1: Install via nvm:"
    echo "  nvm install --lts"
    echo "  nvm use --lts"
    echo ""
    echo "Option 2: Install via Homebrew:"
    echo "  brew install node"
    echo ""
    exit 1
fi

echo "📦 Installing gateway dependencies..."
npm install

echo ""
echo "🚀 Starting gateway server on ws://192.168.5.10:8080..."
echo "   (Gateway will run until you press Ctrl+C)"
echo ""
npm start
