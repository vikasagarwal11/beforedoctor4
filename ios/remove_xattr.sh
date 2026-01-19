#!/bin/bash
# Remove extended attributes from Flutter.framework before codesigning
# This runs as an Xcode build phase

set -e

if [ -f "${BUILT_PRODUCTS_DIR}/Flutter.framework/Flutter" ]; then
    echo "Removing extended attributes from Flutter.framework..."
    xattr -cr "${BUILT_PRODUCTS_DIR}/Flutter.framework" 2>/dev/null || true
    echo "Done"
fi
