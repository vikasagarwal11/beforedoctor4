#!/bin/bash

echo "🧪 Voice Recording Test with Local Gateway"
echo "==========================================="
echo ""

# Check gateway is running
if ! pgrep -f "node server.js" > /dev/null; then
    echo "❌ Gateway not running!"
    echo "   Starting gateway..."
    ./START_GATEWAY.sh
    sleep 3
else
    GATEWAY_PID=$(pgrep -f "node server.js")
    echo "✅ Gateway running (PID: $GATEWAY_PID)"
fi

echo ""
echo "📱 Configuration:"
echo "   Gateway: ws://192.168.5.10:8080 (local)"
echo "   Device: Vikas iPhone 15P"
echo ""
echo "📊 Monitoring gateway logs in background..."
echo "   (Check logs/gateway_xcode.log for details)"
echo ""

# Start monitoring gateway logs in background
tail -f logs/gateway_xcode.log &
TAIL_PID=$!

echo "🚀 Launching app..."
echo ""

# Run Flutter app
flutter run -d 00008130-001C45D22ED0001C

# Cleanup
kill $TAIL_PID 2>/dev/null
