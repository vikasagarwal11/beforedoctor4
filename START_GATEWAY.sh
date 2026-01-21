#!/bin/bash

echo "🚀 Starting Gateway Server"
echo "=========================="
echo ""

# Load NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4/gateway

# Check if already running
if pgrep -f "node server.js" > /dev/null; then
    echo "⚠️  Gateway already running!"
    echo "   PID: $(pgrep -f 'node server.js')"
    echo ""
    echo "To restart:"
    echo "  1. killall -9 node"
    echo "  2. ./START_GATEWAY.sh"
    exit 1
fi

echo "📋 Logs will be saved to: logs/gateway_xcode.log"
echo ""

# Set environment variables for local development
export NODE_ENV=development
export FIREBASE_PROJECT_ID=beforedoctor4
export VERTEX_AI_PROJECT_ID=gen-lang-client-0337309484

echo "🔧 Configuration:"
echo "   Firebase Project: $FIREBASE_PROJECT_ID"
echo "   Vertex AI Project: $VERTEX_AI_PROJECT_ID"
echo "   Environment: $NODE_ENV"
echo ""

# Start gateway
node server.js > ../logs/gateway_xcode.log 2>&1 &
GATEWAY_PID=$!

sleep 2

if ps -p $GATEWAY_PID > /dev/null; then
    echo "✅ Gateway started successfully!"
    echo "   PID: $GATEWAY_PID"
    echo "   URL: wss://beforedoctor-gateway-531178459822.us-central1.run.app"
    echo ""
    echo "📊 To view logs in real-time:"
    echo "   tail -f logs/gateway_xcode.log"
    echo ""
    echo "🛑 To stop gateway:"
    echo "   kill $GATEWAY_PID"
    echo ""
else
    echo "❌ Gateway failed to start!"
    echo "   Check logs: cat logs/gateway_xcode.log"
    exit 1
fi
