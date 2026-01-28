#!/bin/bash
# Get Mac's Wi-Fi IP address

echo "========================================="
echo "📡 MAC'S WIFI IP ADDRESS:"
echo "========================================="
IP=$(ifconfig en0 | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')

if [ -z "$IP" ]; then
    echo "❌ ERROR: Not connected to Wi-Fi!"
    echo ""
    echo "Please connect to Wi-Fi first:"
    echo "  1. System Settings → Network → Wi-Fi"
    echo "  2. Connect to the SAME network as your iPhone"
    echo "  3. Run this script again"
else
    echo "✅ Your Mac's IP: $IP"
    echo ""
    echo "========================================="
    echo "📝 NEXT STEP:"
    echo "========================================="
    echo "Update this file:"
    echo "  lib/app/app_shell.dart"
    echo ""
    echo "Change line 147 to:"
    echo "  : 'ws://$IP:8080';"
    echo ""
    echo "Then hot restart Flutter app (press 'R')"
fi
echo "========================================="
