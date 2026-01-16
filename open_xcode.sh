#!/bin/bash

# Open Xcode to fix code signing

echo "🔧 Opening Xcode to configure code signing..."
echo ""
echo "In Xcode:"
echo "1. Click 'Runner' (blue icon) in left sidebar"
echo "2. Select 'Runner' target"
echo "3. Go to 'Signing & Capabilities' tab"
echo "4. Check 'Automatically manage signing'"
echo "5. Select your team (Personal Team works)"
echo "6. Close Xcode"
echo ""
echo "Then run: flutter run"
echo ""

cd "$(dirname "$0")/ios"
open Runner.xcworkspace
