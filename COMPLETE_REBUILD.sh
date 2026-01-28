#!/bin/bash

echo "🔨 Complete Rebuild - Fix Codesigning Issue"
echo "============================================"
echo ""

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

echo "Step 1: Removing all build artifacts..."
flutter clean > /dev/null 2>&1
rm -rf ios/Pods ios/Podfile.lock
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
rm -rf build
echo "   ✅ All build artifacts removed"
echo ""

echo "Step 2: Reinstalling CocoaPods dependencies..."
cd ios
pod install
cd ..
echo ""

echo "Step 3: Checking gateway..."
if pgrep -f "node server.js" > /dev/null; then
    GATEWAY_PID=$(pgrep -f "node server.js")
    echo "   ✅ Gateway running (PID: $GATEWAY_PID)"
else
    echo "   ⚠️  Gateway not running - starting..."
    ./START_GATEWAY.sh
fi
echo ""

echo "Step 4: Running app (this may take 60-90 seconds)..."
echo "   📱 Device: Vikas iPhone 15P"
echo "   🔌 Gateway: ws://192.168.5.10:8080 (LOCAL)"
echo ""

flutter run -d 00008130-001C45D22ED0001C
