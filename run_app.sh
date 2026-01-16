#!/bin/bash

# Run the Flutter app with all environment variables set

# Setup environment
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Navigate to project
cd "$(dirname "$0")"

# Run the app
echo "🚀 Running Flutter app..."
echo ""
flutter run
