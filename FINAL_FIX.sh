#!/bin/bash
# FINAL FIX for codesign error
# Removes extended attributes from entire Desktop/Vikas directory

set -e

echo "🔧 FINAL FIX - Removing Extended Attributes"
echo "============================================"
echo ""
echo "This will remove extended attributes from:"
echo "  /Users/ainarai/Desktop/Vikas/"
echo ""
echo "This requires your password (sudo access)."
echo ""

read -p "Continue? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled."
    exit 0
fi

echo ""
echo "1️⃣  Removing extended attributes (may take 30-60 seconds)..."
echo "   (You may be asked for your password)"
echo ""

# Remove from entire Vikas directory
sudo xattr -cr /Users/ainarai/Desktop/Vikas/ 2>&1 | grep -v "Operation not permitted" | head -20 || true

echo ""
echo "2️⃣  Cleaning Flutter project..."
cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4
flutter clean > /dev/null 2>&1

echo ""
echo "3️⃣  Removing build directory..."
rm -rf build/

echo ""
echo "4️⃣  Getting Flutter dependencies..."
flutter pub get > /dev/null 2>&1

echo ""
echo "════════════════════════════════════════"
echo "✅ Cleanup complete!"
echo "════════════════════════════════════════"
echo ""
echo "Now try running the app:"
echo "  ./scripts/execute_script.sh"
echo ""
echo "OR open in Xcode:"
echo "  open ios/Runner.xcworkspace"
echo ""
