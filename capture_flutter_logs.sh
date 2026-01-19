#!/bin/bash
# Capture Flutter iOS logs
echo "📱 Capturing Flutter iOS logs..."
echo "Run this command in your terminal:"
echo ""
echo "flutter run -d ios 2>&1 | tee flutter_ios_logs_\$(date +%Y%m%d_%H%M%S).txt"
echo ""
echo "Or to see live logs in Xcode:"
echo "1. Open Xcode"
echo "2. Product → Run (⌘R)"
echo "3. View → Debug Area → Show Debug Area (⌘⌃Y)"
echo "4. The bottom panel shows console output"
