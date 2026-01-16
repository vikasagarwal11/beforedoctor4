#!/bin/bash

# Common functions and utilities for BeforeDoctor development scripts
# Source this file in other scripts: source "$(dirname "$0")/scripts/common.sh"

# Setup environment variables (PATH, LANG, Homebrew)
setup_environment() {
    export LANG=en_US.UTF-8
    export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
    export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
    
    # Load Homebrew if it exists
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    fi
}

# Get project root directory (works from any location)
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # If we're in scripts/, go up one level
    if [[ "$(basename "$script_dir")" == "scripts" ]]; then
        echo "$(dirname "$script_dir")"
    # If common.sh is in root, use script_dir's parent
    else
        echo "$script_dir"
    fi
}

# Check if a command exists
check_command() {
    local cmd="$1"
    local friendly_name="${2:-$cmd}"
    
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ $friendly_name is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Check command and exit if not found
require_command() {
    local cmd="$1"
    local friendly_name="${2:-$cmd}"
    local install_hint="${3:-}"
    
    if ! check_command "$cmd" "$friendly_name"; then
        if [ -n "$install_hint" ]; then
            echo "   $install_hint"
        fi
        exit 1
    fi
}

# Load NVM (Node Version Manager)
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
        return 0
    elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
        . "/opt/homebrew/opt/nvm/nvm.sh"
        return 0
    fi
    
    return 1
}

# Ensure NVM is loaded and Node.js is available
ensure_node() {
    if ! load_nvm; then
        echo "⚠️  NVM not found. Node.js may not be available."
        return 1
    fi
    
    if ! command -v node &> /dev/null; then
        echo "⚠️  Node.js not found in NVM. Install with: nvm install --lts"
        return 1
    fi
    
    # Use LTS if available
    nvm use --lts 2>/dev/null || nvm use node 2>/dev/null || true
    return 0
}

# Get Flutter device ID by name pattern
get_device_id() {
    local pattern="$1"
    local device_line
    
    device_line=$(flutter devices 2>/dev/null | grep -i "$pattern" | head -1)
    
    if [ -n "$device_line" ]; then
        # Extract device ID (format: "00008130-001C45D22ED0001C • iPhone 15 Pro")
        echo "$device_line" | awk '{print $1}' | tr -d '•' | xargs
    fi
}

# Get first available iPhone device ID
get_iphone_device_id() {
    get_device_id "iphone.*physical"
}

# Get first available iOS Simulator device ID
get_simulator_device_id() {
    get_device_id "simulator"
}

# Ensure we're in project root
ensure_project_root() {
    local project_root
    project_root="$(get_project_root)"
    
    if [ -f "$project_root/pubspec.yaml" ]; then
        cd "$project_root" || exit 1
    else
        echo "❌ Cannot find project root. pubspec.yaml not found."
        exit 1
    fi
}

# Print colored output
print_success() {
    echo -e "\033[0;32m✅ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m❌ $1\033[0m"
}

print_warning() {
    echo -e "\033[1;33m⚠️  $1\033[0m"
}

print_info() {
    echo -e "\033[0;34mℹ️  $1\033[0m"
}
