#!/bin/bash

# Fix Ruby Version and Install CocoaPods
# This script installs a newer Ruby and then CocoaPods

set -e

echo "🔧 Fixing Ruby version and installing CocoaPods..."
echo ""

# Add Homebrew to PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# 1. Install newer Ruby via Homebrew
echo "💎 Step 1: Installing newer Ruby..."
if ! brew list ruby &> /dev/null; then
    brew install ruby
    echo "✅ Ruby installed!"
else
    echo "✅ Ruby already installed!"
fi

# 2. Add Homebrew Ruby to PATH
echo ""
echo "📝 Step 2: Setting up Ruby PATH..."
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="$(brew --prefix)/lib/ruby/gems/$(brew --prefix ruby)/bin:$PATH"

# 3. Install CocoaPods using Homebrew Ruby
echo ""
echo "🍎 Step 3: Installing CocoaPods..."
/opt/homebrew/opt/ruby/bin/gem install cocoapods
echo "✅ CocoaPods installed!"

# 4. Add to PATH permanently
echo ""
echo "📝 Step 4: Adding Ruby to PATH permanently..."
cat >> ~/.zshrc << 'EOF'

# Homebrew Ruby
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="$(brew --prefix)/lib/ruby/gems/$(brew --prefix ruby)/bin:$PATH"
EOF

# 5. Install iOS dependencies
echo ""
echo "📱 Step 5: Installing iOS dependencies..."
cd "$(dirname "$0")/ios"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
pod install
cd ..
echo "✅ iOS dependencies installed!"

# 6. Verify
echo ""
echo "🔍 Verifying installation..."
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
pod --version
echo ""

echo "✅ All done!"
echo ""
echo "🎉 You can now run the app with:"
echo "   flutter run"
