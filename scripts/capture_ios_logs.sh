#!/bin/bash
# Script to capture iOS/Flutter logs directly to files
# Usage: ./scripts/capture_ios_logs.sh [output_file]

OUTPUT_FILE="${1:-ios_logs_$(date +%Y%m%d_%H%M%S).txt}"

echo "📱 Capturing iOS logs to: $OUTPUT_FILE"
echo "Press Ctrl+C to stop capturing"
echo ""

# Check if running on simulator or device
if xcrun simctl list devices | grep -q "Booted"; then
    echo "✅ Detected iOS Simulator"
    
    # Get the booted device UDID
    BOOTED_DEVICE=$(xcrun simctl list devices | grep "Booted" | head -1 | sed 's/.*(\([^)]*\)).*/\1/')
    
    if [ -z "$BOOTED_DEVICE" ]; then
        echo "❌ No booted simulator found"
        exit 1
    fi
    
    echo "📋 Device UDID: $BOOTED_DEVICE"
    echo "🔍 Filtering for Runner/Flutter process..."
    echo ""
    
    # Capture logs from simulator, filter for Runner/Flutter
    xcrun simctl spawn "$BOOTED_DEVICE" log stream \
        --level=debug \
        --predicate 'processImagePath contains "Runner" OR processImagePath contains "flutter"' \
        --style=compact \
        2>&1 | tee "$OUTPUT_FILE"
    
else
    echo "📱 Physical device detected (or no simulator running)"
    echo "⚠️  For physical devices, you need libimobiledevice installed"
    echo ""
    echo "To install libimobiledevice:"
    echo "  brew install libimobiledevice"
    echo ""
    echo "Then run:"
    echo "  idevicesyslog > $OUTPUT_FILE"
    echo ""
    
    # Try to use idevicesyslog if available
    if command -v idevicesyslog &> /dev/null; then
        echo "✅ Found idevicesyslog, capturing device logs..."
        idevicesyslog 2>&1 | tee "$OUTPUT_FILE"
    else
        echo "❌ idevicesyslog not found. Install it with: brew install libimobiledevice"
        exit 1
    fi
fi
