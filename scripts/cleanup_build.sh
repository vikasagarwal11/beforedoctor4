#!/bin/bash
# Script to fix iOS build issues (codesign errors, stale files)
# This removes filesystem metadata that causes codesign failures

echo "🧹 Cleaning iOS build artifacts and metadata..."
echo ""

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

# Step 1: Remove ALL build directories
echo "1️⃣  Removing all build directories..."
rm -rf build/
rm -rf ios/build/
rm -rf ios/.symlinks/
rm -rf ios/Flutter/Flutter.framework
rm -rf ios/Flutter/Flutter.podspec
rm -rf ~/.pub-cache/hosted/pub.dev/flutter_*/
echo "   ✅ Build directories removed"

# Step 2: Clean Flutter completely
echo ""
echo "2️⃣  Running flutter clean..."
flutter clean
echo "   ✅ Flutter cleaned"

# Step 3: Remove extended attributes from ENTIRE project
echo ""
echo "3️⃣  Removing extended attributes from entire project..."
find . -type f -name "*.DS_Store" -delete 2>/dev/null || true
# Remove xattr from project root (this will recursively clean everything)
sudo xattr -cr . 2>/dev/null || xattr -cr . 2>/dev/null || true
echo "   ✅ Extended attributes removed"

# Step 4: Run flutter pub get
echo ""
echo "4️⃣  Running flutter pub get..."
flutter pub get
echo "   ✅ Dependencies fetched"

# Step 5: Clean and reinstall CocoaPods
echo ""
echo "5️⃣  Cleaning CocoaPods..."
cd ios
rm -rf Pods/
rm -rf Podfile.lock
rm -rf .symlinks/

echo "   Reinstalling pods..."
pod install --repo-update
cd ..
echo "   ✅ CocoaPods reinstalled"

# Step 6: One final clean of build directory
echo ""
echo "6️⃣  Final cleanup..."
rm -rf build/
rm -rf ios/build/
echo "   ✅ Final cleanup done"

echo ""
echo "════════════════════════════════════════"
echo "✅ Complete cleanup finished!"
echo "════════════════════════════════════════"
echo ""
echo "Next step: Run the app"
echo "  ./scripts/execute_script.sh"
echo ""
