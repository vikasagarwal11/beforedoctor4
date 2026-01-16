#!/bin/bash

# Fix Keychain access for Xcode

echo "🔐 Fixing Keychain Access for Xcode..."
echo ""
echo "If Keychain is locked, run this:"
echo ""
echo "1. Open Keychain Access:"
echo "   open -a 'Keychain Access'"
echo ""
echo "2. Right-click 'login' keychain → Unlock"
echo "   Enter your Mac login password"
echo ""
echo "3. Or run this command:"
echo "   security unlock-keychain ~/Library/Keychains/login.keychain-db"
echo ""
echo "4. Then try building in Xcode again"
echo ""

# Try to unlock keychain (will prompt for password)
security unlock-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "✅ Keychain unlocked" || echo "⚠️  Keychain unlock failed - enter password manually"
