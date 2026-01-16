#!/bin/bash

echo "🔍 Finding your Apple Developer Team ID..."
echo ""

# Try to get team ID from Xcode
cd ios
TEAM_ID=$(xcodebuild -showBuildSettings -workspace Runner.xcworkspace -scheme Runner 2>&1 | grep "DEVELOPMENT_TEAM" | head -1 | awk '{print $3}' | tr -d ' ')

if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != '""' ] && [ "$TEAM_ID" != "" ]; then
    echo "✅ Found Team ID: $TEAM_ID"
    echo ""
    echo "Setting it in the project..."
    # This would need to be set in Xcode project file
    echo "Please set this in Xcode:"
    echo "  1. Open Runner.xcworkspace"
    echo "  2. Select Runner target"
    echo "  3. Signing & Capabilities tab"
    echo "  4. Team should show your Apple ID"
else
    echo "⚠️  Team ID not found in build settings"
    echo ""
    echo "Please:"
    echo "  1. Open Runner.xcworkspace in Xcode"
    echo "  2. Select Runner target"
    echo "  3. Go to Signing & Capabilities"
    echo "  4. Make sure 'Team' is selected (not empty)"
    echo "  5. If empty, click 'Add an Account...' and sign in"
fi
