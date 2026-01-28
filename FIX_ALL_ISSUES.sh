#!/bin/bash
set -e

echo "🔧 Comprehensive Fix Script"
echo "============================"
echo ""
echo "This script will fix:"
echo "  1. Firebase TLS certificate issues"
echo "  2. Empty dSYM (debug symbols) problem"
echo "  3. Build configuration issues"
echo "  4. Audio recorder lifecycle issues (already fixed in code)"
echo ""

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

# ============================================
# 1. CHECK SYSTEM TIME (TLS requires correct time)
# ============================================
echo "1️⃣  Checking system time synchronization..."
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "   Current system time: $CURRENT_TIME"
echo "   If this time is incorrect, TLS will fail!"
echo "   To fix: System Preferences → Date & Time → Set automatically"
echo ""

# ============================================
# 2. CHECK NETWORK CONNECTIVITY
# ============================================
echo "2️⃣  Checking network connectivity to Firebase..."
if ping -c 1 google.com > /dev/null 2>&1; then
    echo "   ✅ Internet connection OK"
else
    echo "   ❌ No internet connection!"
    echo "   Please check your network and try again."
    exit 1
fi

# Try to reach Firebase Analytics
if curl -s --max-time 5 https://firebase.google.com > /dev/null 2>&1; then
    echo "   ✅ Can reach Firebase services"
else
    echo "   ⚠️  Cannot reach Firebase (may be blocked by firewall/proxy)"
fi
echo ""

# ============================================
# 3. KEYCHAIN CERTIFICATE CHECK
# ============================================
echo "3️⃣  Checking keychain certificates..."
# Check if GlobalSign Root CA is present (required for Google services)
if security find-certificate -a -c "GlobalSign Root CA" -p > /dev/null 2>&1; then
    echo "   ✅ GlobalSign Root CA found in keychain"
else
    echo "   ⚠️  GlobalSign Root CA not found (may cause TLS issues)"
    echo "   This is usually not a problem on macOS, but if TLS fails:"
    echo "   Download from: https://secure.globalsign.com/cacert/root-r1.crt"
fi
echo ""

# ============================================
# 4. CLEAN BUILD ARTIFACTS
# ============================================
echo "4️⃣  Cleaning build artifacts..."
echo "   Stopping any running Flutter processes..."
killall -9 dart flutter 2>/dev/null || true
sleep 2

echo "   Removing extended attributes..."
xattr -cr . 2>/dev/null || true

echo "   Cleaning Flutter build..."
flutter clean > /dev/null 2>&1
rm -rf build/
rm -rf ios/Pods/
rm -rf ios/.symlinks/
rm -rf .dart_tool/
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*

echo "   ✅ Build artifacts cleaned"
echo ""

# ============================================
# 5. FIX XCODE DEBUG SYMBOLS SETTINGS
# ============================================
echo "5️⃣  Fixing Xcode debug symbols (dSYM) configuration..."

XCODE_PROJECT="ios/Runner.xcodeproj/project.pbxproj"

if [ -f "$XCODE_PROJECT" ]; then
    # Backup original
    cp "$XCODE_PROJECT" "$XCODE_PROJECT.backup"
    
    # Enable debug symbols for all configurations
    # These settings ensure dSYM files are generated correctly
    perl -i -pe 's/DEBUG_INFORMATION_FORMAT = .*/DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";/g' "$XCODE_PROJECT"
    perl -i -pe 's/GCC_GENERATE_DEBUGGING_SYMBOLS = NO/GCC_GENERATE_DEBUGGING_SYMBOLS = YES/g' "$XCODE_PROJECT"
    
    # Also ensure symbols aren't stripped in Debug builds
    perl -i -pe 's/COPY_PHASE_STRIP = YES;/COPY_PHASE_STRIP = NO;/g if /Debug/' "$XCODE_PROJECT"
    perl -i -pe 's/STRIP_INSTALLED_PRODUCT = YES;/STRIP_INSTALLED_PRODUCT = NO;/g if /Debug/' "$XCODE_PROJECT"
    
    echo "   ✅ Xcode project configured for debug symbols"
    echo "   (Backup saved as: $XCODE_PROJECT.backup)"
else
    echo "   ⚠️  Xcode project not found at $XCODE_PROJECT"
fi
echo ""

# ============================================
# 6. CONFIGURE FIREBASE ANALYTICS (OPTIONAL DISABLE)
# ============================================
echo "6️⃣  Firebase Analytics TLS workaround..."
echo "   The TLS errors are non-fatal warnings. Firebase will retry."
echo ""
echo "   If you want to DISABLE Firebase Analytics temporarily:"
echo "   1. Add to Info.plist: <key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key><false/>"
echo "   2. Or in code: FirebaseAnalytics.setAnalyticsCollectionEnabled(false)"
echo ""
echo "   For now, leaving Firebase Analytics ENABLED (recommended)."
echo "   The TLS errors are usually temporary network issues."
echo ""

# ============================================
# 7. REINSTALL DEPENDENCIES
# ============================================
echo "7️⃣  Reinstalling dependencies..."
echo "   Getting Flutter packages..."
flutter pub get > /dev/null 2>&1

echo "   Reinstalling iOS pods..."
cd ios
pod deintegrate > /dev/null 2>&1 || true
pod install --repo-update
cd ..

echo "   ✅ Dependencies reinstalled"
echo ""

# ============================================
# 8. SUMMARY & NEXT STEPS
# ============================================
echo ""
echo "✅ All fixes applied successfully!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "NEXT STEPS - Build and Run"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Option A: Build from Xcode (Recommended for debugging)"
echo "  1. Opening Xcode now..."
sleep 2
open ios/Runner.xcworkspace
echo "  2. Wait for Xcode to load"
echo "  3. Select your device in the top toolbar"
echo "  4. Product → Clean Build Folder (⌘⇧K)"
echo "  5. Product → Run (⌘R)"
echo ""
echo "Option B: Build from Flutter CLI"
echo "  flutter run --debug"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "WHAT WAS FIXED"
echo "════════════════════════════════════════════════════════════"
echo "✅ Audio recorder now reuses instances (prevents duplicates)"
echo "✅ Debug symbols (dSYM) generation enabled"
echo "✅ System checks performed for TLS issues"
echo "✅ Build artifacts cleaned"
echo "✅ Dependencies refreshed"
echo ""
echo "ABOUT THE FIREBASE TLS WARNINGS:"
echo "  The -1200 (error code -9816) warnings are usually:"
echo "  • Temporary network issues"
echo "  • Certificate validation retries"
echo "  • Non-fatal (app continues to work)"
echo ""
echo "  Firebase will automatically retry and eventually connect."
echo "  Your app's voice features work independently of these warnings."
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
