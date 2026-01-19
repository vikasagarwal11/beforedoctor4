#!/bin/bash
# Aggressive fix for codesign errors
# Removes ALL extended attributes that block codesigning

echo "🔧 Aggressive Codesign Fix"
echo "=========================="
echo ""

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

echo "This will:"
echo "  1. Remove ALL build artifacts"
echo "  2. Remove extended attributes (may need sudo password)"
echo "  3. Clean Flutter cache"
echo "  4. Reinstall dependencies"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "1️⃣  Removing build directories..."
rm -rf build/
rm -rf ios/build/
rm -rf ios/.symlinks/
rm -rf ios/Flutter/
rm -rf .dart_tool/
rm -rf .flutter-plugins
rm -rf .flutter-plugins-dependencies
echo "   ✅ Done"

echo ""
echo "2️⃣  Removing extended attributes (may ask for sudo password)..."
echo "   Cleaning project root..."
sudo xattr -cr . 2>/dev/null || xattr -cr . 2>/dev/null || true
echo "   ✅ Done"

echo ""
echo "3️⃣  Running flutter clean..."
flutter clean
echo "   ✅ Done"

echo ""
echo "4️⃣  Removing Pods..."
cd ios
rm -rf Pods/
rm -rf Podfile.lock
cd ..
echo "   ✅ Done"

echo ""
echo "5️⃣  Running flutter pub get..."
flutter pub get
echo "   ✅ Done"

echo ""
echo "6️⃣  Reinstalling CocoaPods..."
cd ios
pod install --repo-update
cd ..
echo "   ✅ Done"

echo ""
echo "════════════════════════════════════════"
echo "✅ Aggressive cleanup complete!"
echo "════════════════════════════════════════"
echo ""
echo "Now run: flutter run"
echo "Or run: ./scripts/execute_script.sh"
echo ""
