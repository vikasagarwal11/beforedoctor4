#!/bin/bash
set -e

echo "🧪 Voice Session Diagnostic Test"
echo "=================================="
echo ""

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

# Check if iPhone is connected
echo "📱 Checking for iPhone connection..."
DEVICE_ID="00008130-001C45D22ED0001C"
if ! flutter devices | grep -q "$DEVICE_ID"; then
    echo "❌ iPhone not found!"
    echo ""
    echo "Please:"
    echo "  1. Connect iPhone via USB cable"
    echo "  2. Unlock iPhone"
    echo "  3. Trust this Mac (if prompted)"
    echo "  4. Run this script again"
    exit 1
fi
echo "✅ iPhone detected"
echo ""

# Clean build
echo "1️⃣  Cleaning build..."
flutter clean > /dev/null 2>&1
flutter pub get > /dev/null 2>&1
echo "✅ Clean complete"
echo ""

# Start gateway
echo "2️⃣  Starting gateway server..."
cd gateway
node server.js > ../logs/gateway_$(date +%H%M%S).log 2>&1 &
GATEWAY_PID=$!
cd ..
echo "✅ Gateway started (PID: $GATEWAY_PID)"
echo ""

# Run app
echo "3️⃣  Building and launching app on iPhone..."
echo "   (First build takes ~60 seconds)"
echo ""
echo "📋 Logs will be saved to: logs/test_$(date +%H%M%S).log"
echo ""
echo "───────────────────────────────────────────────────────"
echo "WHEN APP LAUNCHES ON YOUR PHONE:"
echo "  1. Navigate to Voice Assistant screen"
echo "  2. Tap the microphone button"
echo "  3. Grant microphone permission if asked"
echo "  4. Say: 'Hello, can you hear me?'"
echo "  5. Wait 5-10 seconds for response"
echo ""
echo "TO STOP TEST: Press 'q' or Ctrl+C"
echo "───────────────────────────────────────────────────────"
echo ""

# Capture logs
LOG_FILE="logs/test_$(date +%H%M%S).log"
flutter run -d $DEVICE_ID 2>&1 | tee "$LOG_FILE"

# Cleanup on exit
echo ""
echo "🛑 Stopping gateway..."
kill $GATEWAY_PID 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════════"
echo "📊 TEST COMPLETE - Analyzing Results..."
echo "═══════════════════════════════════════════════════════"
echo ""

# Quick analysis
echo "🔍 Quick Log Analysis:"
echo ""

if grep -q "voice.gateway_connected" "$LOG_FILE" 2>/dev/null; then
    echo "✅ Gateway connection: SUCCESS"
else
    echo "❌ Gateway connection: FAILED (client never connected)"
fi

if grep -q "voice.server_listening_state_received" "$LOG_FILE" 2>/dev/null; then
    echo "✅ Server ready event: RECEIVED"
else
    echo "❌ Server ready event: NOT RECEIVED"
fi

if grep -q "voice.server_ready_SET_TO_TRUE_DEBUG" "$LOG_FILE" 2>/dev/null; then
    echo "✅ Server ready flag: SET TO TRUE"
else
    echo "❌ Server ready flag: NEVER SET"
fi

if grep -q "voice.audio_chunk_sent" "$LOG_FILE" 2>/dev/null; then
    echo "✅ Audio chunks: SENT TO GATEWAY"
else
    echo "❌ Audio chunks: NOT SENT (likely rejected)"
fi

REJECTED_COUNT=$(grep -c "voice.audio_chunk_rejected" "$LOG_FILE" 2>/dev/null || echo "0")
if [ "$REJECTED_COUNT" -gt 0 ]; then
    echo "⚠️  Audio chunks rejected: $REJECTED_COUNT times"
fi

echo ""
echo "───────────────────────────────────────────────────────"
echo "📁 Full logs saved to:"
echo "   Flutter: $LOG_FILE"
echo "   Gateway: logs/gateway_*.log"
echo ""
echo "🔎 To view detailed logs:"
echo "   grep -E 'voice\\.(gateway_connected|audio_chunk_rejected|gateway_error)' $LOG_FILE | head -50"
echo ""
echo "💬 What happened on your iPhone?"
echo "   [ ] I heard the AI speak"
echo "   [ ] The AI heard me and responded"
echo "   [ ] Nothing happened when I tapped mic"
echo "   [ ] Got error message: _______________"
echo "═══════════════════════════════════════════════════════"
