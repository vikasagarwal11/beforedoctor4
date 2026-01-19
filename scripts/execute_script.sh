#!/bin/bash
# EXECUTE SCRIPT - Run app on iPhone 15 Pro (wireless/wired) with gateway and logs

PROJECT_DIR="/Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4"
GATEWAY_DIR="$PROJECT_DIR/gateway"
LOGS_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/session_logs_${TIMESTAMP}.txt"

cd "$PROJECT_DIR"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

echo "🚀 EXECUTE SCRIPT - BeforeDoctor Voice Session"
echo "================================================"
echo ""

# Detect available devices
echo "📱 Detecting available devices..."
DEVICE_LIST=$(flutter devices 2>/dev/null)

# Check for physical iPhone first (wired or wireless)
PHYSICAL_IPHONE=$(echo "$DEVICE_LIST" | grep -i "iPhone.*ios" | head -1)
DEVICE_ID=$(echo "$PHYSICAL_IPHONE" | grep -o '[0-9A-F-]*' | grep -E '^[0-9A-F]{8}-' | head -1)

if [ -n "$PHYSICAL_IPHONE" ]; then
    echo "✅ Physical iPhone detected: $PHYSICAL_IPHONE"
    USE_SIMULATOR=false
    
    # Install libimobiledevice if not present (for device logs)
    if ! command -v idevicesyslog &> /dev/null; then
        echo "⚠️  libimobiledevice not installed (needed for device logs)"
        read -p "Install now? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Installing libimobiledevice..."
            brew install libimobiledevice
        else
            echo "⚠️  Will use Flutter logs only (no system logs)"
        fi
    fi
else
    # Fall back to simulator
    if xcrun simctl list devices | grep -q "Booted"; then
        echo "✅ Simulator already booted"
        USE_SIMULATOR=true
    else
        echo "📱 No device found. Booting iPhone 15 Pro simulator..."
        IPHONE_15_PRO=$(xcrun simctl list devices | grep "iPhone 15 Pro" | grep -v "Max" | head -1 | sed 's/.*(\([^)]*\)).*/\1/')
        
        if [ -n "$IPHONE_15_PRO" ]; then
            xcrun simctl boot "$IPHONE_15_PRO"
            echo "✅ Simulator booted"
            USE_SIMULATOR=true
            sleep 3
        else
            echo "❌ No device or simulator available"
            exit 1
        fi
    fi
fi

echo ""
echo "1️⃣  Starting Gateway Server (background)..."

# Start gateway in background
cd "$GATEWAY_DIR"
./deploy.sh > "$LOGS_DIR/gateway_output.txt" 2>&1 &
GATEWAY_PID=$!
echo "   Gateway PID: $GATEWAY_PID"
echo "   Output: logs/gateway_output.txt"

cd "$PROJECT_DIR"
sleep 5

echo ""
echo "2️⃣  Starting Log Capture (background)..."

# Start Flutter log capture (works for both simulator and physical device)
# Note: flutter logs captures app output directly, more reliable than system logs
echo "   Starting Flutter log capture..."
flutter logs 2>&1 | tee "$LOG_FILE" &
LOG_PID=$!
echo "   Log capture PID: $LOG_PID"
echo "   Output: $LOG_FILE"
echo "   (Capturing Flutter app logs from iPhone)"

sleep 2

echo ""
echo "3️⃣  Launching Flutter App..."
echo ""

# Run Flutter app (foreground)
if [ -n "$DEVICE_ID" ]; then
    # Physical device
    flutter run -d "$DEVICE_ID"
elif [ "$USE_SIMULATOR" = true ]; then
    # Simulator
    flutter run -d $(xcrun simctl list devices | grep "Booted" | head -1 | sed 's/.*(\([^)]*\)).*/\1/')
else
    # Let Flutter choose
    flutter run
fi

echo ""
echo "═══════════════════════════════════════════"
echo "Session Ended"
echo "═══════════════════════════════════════════"
echo ""
echo "📁 Log files created in logs/ folder:"
echo "   • App logs (from iPhone): logs/session_logs_${TIMESTAMP}.txt"
echo "   • Gateway logs: logs/gateway_output.txt"
echo ""
echo "📋 View logs:"
echo "   cat logs/session_logs_${TIMESTAMP}.txt | grep 'voice\\.\|error'"
echo ""
echo "🛑 Cleaning up background processes..."
kill $LOG_PID 2>/dev/null || true
kill $GATEWAY_PID 2>/dev/null || true
echo "✅ Done"
echo ""
