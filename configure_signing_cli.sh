#!/bin/bash

# Try to configure code signing via command line

echo "🔧 Attempting to configure code signing via command line..."
echo ""

cd "$(dirname "$0")/ios"

# Try to set automatic signing
xcodebuild -project Runner.xcodeproj \
  -target Runner \
  -configuration Debug \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="" \
  2>&1 | grep -i "signing\|team\|error" | head -10

echo ""
echo "✅ If no errors above, try running: flutter run"
