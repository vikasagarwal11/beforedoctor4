#!/bin/bash
# EXECUTE SCRIPT (3 Terminals) - Run gateway, app, and logs in separate windows
# Automatically opens 3 terminal windows for iPhone 15 Pro

PROJECT_DIR="/Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4"
GATEWAY_DIR="$PROJECT_DIR/gateway"
LOGS_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/session_logs_${TIMESTAMP}.txt"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

echo "🚀 EXECUTE SCRIPT - 3 Terminals Mode"
echo "====================================="
echo ""
echo "Project: $PROJECT_DIR"
echo "Gateway: $GATEWAY_DIR"
echo "Logs: $LOG_FILE"
echo ""

# Function to open new Terminal window with command
open_terminal_window() {
    local title="$1"
    local command="$2"
    
    osascript <<EOF
tell application "Terminal"
    do script "cd '$PROJECT_DIR' && clear && echo '═══════════════════════════════════════════' && echo '  $title' && echo '═══════════════════════════════════════════' && echo '' && $command"
    set custom title of front window to "$title"
end tell
EOF
}

# Step 1: Check prerequisites
echo "1️⃣  Checking prerequisites..."

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js first:"
    echo "   brew install node"
    exit 1
fi
echo "   ✅ Node.js found"

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first."
    exit 1
fi
echo "   ✅ Flutter found"

# Check for physical iPhone first
PHYSICAL_IPHONE=$(flutter devices 2>/dev/null | grep -i "iPhone.*ios" | head -1)

if [ -n "$PHYSICAL_IPHONE" ]; then
    echo "   ✅ Physical iPhone detected: $PHYSICAL_IPHONE"
    
    # Check if libimobiledevice is needed (for device logs)
    if ! command -v idevicesyslog &> /dev/null; then
        echo "   ⚠️  libimobiledevice not installed (needed for iPhone logs)"
        read -p "   Install now? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "   Installing libimobiledevice..."
            brew install libimobiledevice
        else
            echo "   ⚠️  Will use Flutter logs only (no system logs)"
        fi
    fi
else
    # Check for simulator as fallback
    DEVICE_CHECK=$(flutter devices 2>/dev/null | grep -E "(ios|iPhone|iPad)" | head -1)
    if [ -z "$DEVICE_CHECK" ]; then
        echo "   ⚠️  No iPhone or simulator detected"
        echo "   Options:"
        echo "   1. Connect your iPhone via USB or WiFi"
        echo "   2. Open Simulator.app and boot a simulator"
        echo ""
        read -p "Press Enter once you have a device ready, or Ctrl+C to cancel..."
    else
        echo "   ✅ Simulator available"
    fi
fi

echo ""
echo "2️⃣  Starting Gateway Server (Terminal 1)..."
sleep 1

# Terminal 1: Gateway Server
open_terminal_window "Gateway Server" "cd '$GATEWAY_DIR' && echo 'Starting gateway server...' && echo '' && ./deploy.sh; exec bash"

echo "   ✅ Gateway terminal opened"
echo ""
echo "⏳ Waiting 5 seconds for gateway to deploy..."
sleep 5

echo "3️⃣  Launching Flutter App (Terminal 2)..."
sleep 1

# Terminal 2: Flutter App
open_terminal_window "Flutter App" "echo 'Launching Flutter app...' && echo '' && flutter run; exec bash"

echo "   ✅ Flutter app terminal opened"
echo ""
echo "⏳ Waiting 3 seconds before starting log capture..."
sleep 3

echo "4️⃣  Starting Log Capture (Terminal 3)..."
sleep 1

# Terminal 3: Log Capture
# Detect device type and use appropriate logging
if [ -n "$PHYSICAL_IPHONE" ] && command -v idevicesyslog &> /dev/null; then
    # Physical iPhone with idevicesyslog
    open_terminal_window "Log Capture (iPhone Device)" "echo 'Capturing iPhone logs...' && echo 'Device: $PHYSICAL_IPHONE' && echo 'Output: $LOG_FILE' && echo '' && idevicesyslog 2>&1 | grep -E '(flutter|Runner|voice\\.|gateway|audio\\.|error|Error|Exception)' | tee '$LOG_FILE'; exec bash"
elif xcrun simctl list devices | grep -q "Booted"; then
    # Simulator detected
    open_terminal_window "Log Capture (iOS Simulator)" "echo 'Capturing iOS Simulator logs...' && echo 'Output: $LOG_FILE' && echo '' && xcrun simctl spawn booted log stream --level=debug --predicate 'processImagePath contains \"Runner\"' --style=compact 2>&1 | tee '$LOG_FILE'; exec bash"
else
    # Flutter logs only (fallback)
    open_terminal_window "Log Capture (Flutter Logs)" "echo 'Capturing Flutter logs...' && echo 'Output: $LOG_FILE' && echo '' && flutter logs 2>&1 | grep -E '(voice\\.|gateway|audio\\.|error|Error|Exception)' | tee '$LOG_FILE'; exec bash"
fi

echo "   ✅ Log capture terminal opened"
echo ""
echo "═══════════════════════════════════════════"
echo "✅ All systems launched!"
echo "═══════════════════════════════════════════"
echo ""
echo "📋 Terminal Windows:"
echo "   1. Gateway Server (deploying to Cloud Run)"
echo "   2. Flutter App (building and launching)"
echo "   3. Log Capture (saving to: $LOG_FILE)"
echo ""
echo "📝 Instructions:"
echo "   • Wait for gateway to deploy (Terminal 1)"
echo "   • Wait for Flutter app to launch (Terminal 2)"
echo "   • Logs are being captured automatically (Terminal 3)"
echo "   • Press Ctrl+C in Terminal 3 to stop logging"
echo "   • View logs later with: cat $LOG_FILE"
echo ""
echo "🛑 To stop everything:"
echo "   • Press Ctrl+C in each terminal window"
echo "   • Or close the terminal windows"
echo ""
