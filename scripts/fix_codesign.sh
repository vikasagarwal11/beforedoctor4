#!/bin/bash
# Comprehensive code signing fix script
# Handles extended attributes, build cleanup, and dependency reinstallation
# Usage: ./scripts/fix_codesign.sh [--aggressive] [--run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

AGGRESSIVE=false
RUN_AFTER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --aggressive)
            AGGRESSIVE=true
            shift
            ;;
        --run)
            RUN_AFTER=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--aggressive] [--run]"
            exit 1
            ;;
    esac
done

echo "🔧 Code Signing Fix"
echo "==================="
echo ""

if [ "$AGGRESSIVE" = true ]; then
    echo "⚠️  AGGRESSIVE MODE: Will remove ALL build artifacts"
    echo ""
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Step 1: Clean extended attributes
echo "1️⃣  Removing extended attributes..."
find . -name "*.framework" -exec xattr -cr {} \; 2>/dev/null || true
xattr -cr ios 2>/dev/null || true
xattr -cr build 2>/dev/null || true
if [ "$AGGRESSIVE" = true ]; then
    echo "   Removing ALL extended attributes (may ask for sudo password)..."
    sudo xattr -cr . 2>/dev/null || xattr -cr . 2>/dev/null || true
fi
echo "   ✅ Extended attributes removed"
echo ""

# Step 2: Clean Flutter build
echo "2️⃣  Cleaning Flutter build..."
flutter clean > /dev/null 2>&1
echo "   ✅ Flutter cleaned"
echo ""

# Step 3: Clear Xcode cache
echo "3️⃣  Clearing Xcode cache..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* 2>/dev/null || true
echo "   ✅ Xcode cache cleared"
echo ""

# Step 4: Aggressive cleanup (if requested)
if [ "$AGGRESSIVE" = true ]; then
    echo "4️⃣  Removing ALL build artifacts..."
    rm -rf build/ ios/build/ ios/.symlinks/ ios/Flutter/ .dart_tool/
    rm -rf .flutter-plugins .flutter-plugins-dependencies
    echo "   ✅ Build artifacts removed"
    echo ""
fi

# Step 5: Reinstall CocoaPods
echo "5️⃣  Reinstalling CocoaPods..."
cd ios
if [ "$AGGRESSIVE" = true ]; then
    rm -rf Pods/ Podfile.lock
    pod deintegrate > /dev/null 2>&1 || true
fi
pod install > /dev/null 2>&1
cd ..
echo "   ✅ CocoaPods reinstalled"
echo ""

# Step 6: Get Flutter dependencies
if [ "$AGGRESSIVE" = true ]; then
    echo "6️⃣  Getting Flutter dependencies..."
    flutter pub get > /dev/null 2>&1
    echo "   ✅ Dependencies installed"
    echo ""
fi

# Step 7: Check gateway (if --run is specified)
if [ "$RUN_AFTER" = true ]; then
    echo "7️⃣  Checking gateway..."
    if pgrep -f "node server.js" > /dev/null; then
        GATEWAY_PID=$(pgrep -f "node server.js")
        echo "   ✅ Gateway running (PID: $GATEWAY_PID)"
    else
        echo "   ⚠️  Gateway not running - starting..."
        "$PROJECT_DIR/START_GATEWAY.sh" || true
    fi
    echo ""
fi

echo "════════════════════════════════════════"
echo "✅ Code signing fix complete!"
echo "════════════════════════════════════════"
echo ""

if [ "$RUN_AFTER" = true ]; then
    echo "🚀 Running app..."
    flutter run -d 00008130-001C45D22ED0001C || flutter run
else
    echo "Next steps:"
    echo "  • Run: flutter run"
    echo "  • Or: ./scripts/execute_script.sh"
    echo "  • Or: Open Xcode and build there"
fi
echo ""
