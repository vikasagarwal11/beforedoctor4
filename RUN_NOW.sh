#!/bin/bash

# Complete script to run the app with all environment setup

echo "🚀 Setting up environment and running app..."
echo ""

# Setup all environment variables
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Navigate to project
cd "$(dirname "$0")"

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Setting up PATH..."
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "✅ Environment ready"
echo "📱 Running app on iOS Simulator..."
echo ""

# Run the app
flutter run
