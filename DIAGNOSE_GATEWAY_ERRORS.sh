#!/bin/bash
echo "🔍 Checking for gateway errors in your logs..."
echo ""

# Check if user provided log file
if [ -z "$1" ]; then
  echo "Usage: ./DIAGNOSE_GATEWAY_ERRORS.sh <log_file.txt>"
  echo ""
  echo "Or paste your logs and search for:"
  echo "  - 'gateway_error_received'"
  echo "  - 'gateway.error'"
  echo "  - 'GatewayEventType.error'"
  echo ""
  exit 1
fi

LOG_FILE="$1"

echo "Searching for gateway errors..."
grep -i "error" "$LOG_FILE" | grep -i "gateway\|voice" | head -20

echo ""
echo "Searching for state transitions..."
grep "server_ready" "$LOG_FILE" | tail -30
