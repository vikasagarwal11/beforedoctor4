#!/bin/bash

# Check if app is running

echo "🔍 Checking app status..."
echo ""

# Setup environment
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Check if app is built
if [ -d "build/ios/Debug-iphonesimulator/Runner.app" ]; then
    echo "✅ App built successfully!"
else
    echo "⏳ App not built yet"
fi

# Check Flutter processes
if ps aux | grep -E "flutter run|dart" | grep -v grep > /dev/null; then
    echo "✅ Flutter is running"
else
    echo "⏳ Flutter not running"
fi

# Check simulator
if ps aux | grep -i simulator | grep -v grep > /dev/null; then
    echo "✅ Simulator is running"
else
    echo "⚠️  Simulator not running (run: open -a Simulator)"
fi

# Check devices
echo ""
echo "📱 Available devices:"
flutter devices 2>&1 | grep -E "iPhone|iPad|Found" | head -5

echo ""
echo "🎯 To run the app:"
echo "   ./RUN_NOW.sh"
echo "   or"
echo "   flutter run"
