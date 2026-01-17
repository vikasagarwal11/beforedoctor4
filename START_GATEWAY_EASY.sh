#!/bin/bash

# Easy script to start the gateway server

echo "🚀 Starting Gateway Server..."
echo ""

# Navigate to project
cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4/gateway

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# Use Node.js LTS
nvm use --lts

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies first..."
    npm install
fi

# Start server
echo "✅ Starting gateway server on ws://192.168.5.10:8080"
echo "   Keep this terminal open!"
echo ""
npm start
