#!/bin/bash

# Install Node.js and start gateway

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

echo "📦 Checking Node.js installation..."
if ! command -v node &> /dev/null; then
    echo "Installing Node.js (latest LTS)..."
    nvm install --lts
    nvm use --lts
    echo "✅ Node.js installed!"
else
    echo "✅ Node.js already installed: $(node --version)"
fi

echo ""
cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4/gateway

echo "📦 Installing gateway dependencies..."
npm install

echo ""
echo "🚀 Starting gateway server on ws://192.168.5.10:8080..."
echo "   (Press Ctrl+C to stop)"
echo ""
npm start
