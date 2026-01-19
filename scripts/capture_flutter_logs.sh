#!/bin/bash
# Script to capture Flutter app logs directly to files
# Usage: ./scripts/capture_flutter_logs.sh [output_file]

OUTPUT_FILE="${1:-flutter_logs_$(date +%Y%m%d_%H%M%S).txt}"

echo "🎯 Capturing Flutter logs to: $OUTPUT_FILE"
echo "Press Ctrl+C to stop capturing"
echo ""

# Check if flutter is available
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found in PATH"
    exit 1
fi

# Filter for relevant logs (voice session, gateway, audio, errors)
echo "🔍 Filtering for voice session, gateway, audio, and error logs..."
echo ""

flutter logs 2>&1 | grep -E "(voice\.|gateway|audio\.|error|Error|Exception|⛔|✅|💡|🐛)" | tee "$OUTPUT_FILE"
