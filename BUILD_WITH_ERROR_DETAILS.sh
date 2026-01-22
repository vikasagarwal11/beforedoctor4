#!/bin/bash

echo "🔍 Comprehensive Build with Full Error Details"
echo "==============================================="
echo ""

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

LOG_FILE="logs/detailed_build_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p logs

echo "📝 Logging to: $LOG_FILE"
echo ""

{
  echo "========================================"
  echo "BUILD STARTED: $(date)"
  echo "========================================"
  echo ""
  
  echo "1️⃣  Checking Flutter..."
  flutter --version
  echo ""
  
  echo "2️⃣  Checking connected devices..."
  flutter devices
  echo ""
  
  echo "3️⃣  Running Flutter pub get..."
  flutter pub get
  echo ""
  
  echo "4️⃣  Building Flutter framework..."
  flutter build ios-framework --no-profile --no-release --output=build/ios_framework
  echo ""
  
  echo "5️⃣  Checking code for issues..."
  flutter analyze 2>&1 || true
  echo ""
  
  echo "6️⃣  Attempting Flutter build for iOS..."
  flutter build ios --debug --no-codesign 2>&1
  BUILD_EXIT_CODE=$?
  echo ""
  echo "Flutter build exit code: $BUILD_EXIT_CODE"
  
  if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ FLUTTER BUILD FAILED"
    echo ""
    echo "7️⃣  Trying direct xcodebuild for detailed error..."
    cd ios
    xcodebuild -workspace Runner.xcworkspace \
               -scheme Runner \
               -configuration Debug \
               -destination 'generic/platform=iOS' \
               -showBuildSettings 2>&1 | head -50
    echo ""
    
    xcodebuild -workspace Runner.xcworkspace \
               -scheme Runner \
               -configuration Debug \
               -destination 'generic/platform=iOS' \
               clean build \
               CODE_SIGNING_ALLOWED=NO \
               CODE_SIGNING_REQUIRED=NO \
               2>&1
    XCODE_EXIT_CODE=$?
    echo ""
    echo "Xcodebuild exit code: $XCODE_EXIT_CODE"
  else
    echo "✅ FLUTTER BUILD SUCCEEDED"
  fi
  
  echo ""
  echo "========================================"
  echo "BUILD ENDED: $(date)"
  echo "========================================"
  
} 2>&1 | tee "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Full build log saved to:"
echo "   $LOG_FILE"
echo ""
echo "🔍 Searching for errors in log..."
echo ""

grep -i "error:" "$LOG_FILE" | grep -v "0 errors" | tail -20 || echo "No explicit 'error:' lines found"

echo ""
echo "🔍 Searching for 'failed' in log..."
echo ""

grep -i "failed" "$LOG_FILE" | tail -20 || echo "No 'failed' lines found"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 Open the full log file to see complete details:"
echo "   open $LOG_FILE"
echo ""
