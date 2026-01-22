#!/bin/bash
# Wrapper script for aggressive code signing fix
# This script calls the consolidated fix_codesign.sh script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔨 AGGRESSIVE Codesigning Fix"
echo "=============================="
echo ""
echo "This will run the comprehensive fix script in aggressive mode..."
echo ""

# Kill Flutter processes first
echo "1️⃣  Killing any Flutter processes..."
killall -9 dart flutter 2>/dev/null || true
sleep 2

# Run the consolidated fix script with aggressive flag
"$SCRIPT_DIR/scripts/fix_codesign.sh" --aggressive

echo ""
echo "════════════════════════════════════════════"
echo "Opening Xcode..."
echo "════════════════════════════════════════════"
echo ""

open "$SCRIPT_DIR/ios/Runner.xcworkspace"
sleep 3

echo ""
echo "📱 In Xcode (should open now):"
echo "  1. Wait for Xcode to finish loading (check top progress bar)"
echo "  2. Select 'Vikas iPhone 15P' in top toolbar"
echo "  3. Product → Clean Build Folder (Cmd+Shift+K)"
echo "  4. Product → Run (Cmd+R)"
echo ""
echo "🎤 On your iPhone when app launches:"
echo "  1. Navigate to Voice Assistant"
echo "  2. Tap microphone button"
echo "  3. Say: 'Hello, can you hear me?'"
echo ""
echo "📋 Watch Xcode console (bottom panel) for logs"
echo ""
