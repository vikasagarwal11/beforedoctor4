#!/bin/bash

# Master Development Script for BeforeDoctor App
# Provides a menu-driven interface for common development tasks

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Setup environment
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true

cd "$(dirname "$0")"

# Print header
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  BeforeDoctor - Development Tools     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Show menu
show_menu() {
    echo -e "${YELLOW}📱 RUN APP${NC}"
    echo "  1) Run on iOS Simulator"
    echo "  2) Run on Physical iPhone"
    echo "  3) Run (simple)"
    echo "  4) Fix issues and run"
    echo "  5) Run without code signing"
    echo ""
    echo -e "${YELLOW}🔧 SETUP & INSTALL${NC}"
    echo "  6) Complete installation (all dependencies)"
    echo "  7) Quick install (no sudo required)"
    echo "  8) Install Node.js & Gateway"
    echo "  9) Fix Ruby & install CocoaPods"
    echo ""
    echo -e "${YELLOW}🔐 CODE SIGNING${NC}"
    echo "  10) Fix code signing for simulator"
    echo "  11) Open Xcode (configure signing manually)"
    echo "  12) Fix keychain access"
    echo ""
    echo -e "${YELLOW}🌐 GATEWAY SERVER${NC}"
    echo "  13) Start Gateway Server"
    echo "  14) Deploy Gateway to Cloud Run"
    echo ""
    echo -e "${YELLOW}🔍 UTILITIES${NC}"
    echo "  15) Check status (all systems)"
    echo "  16) Check developer mode (iPhone)"
    echo "  17) Get Team ID"
    echo "  18) Check available devices"
    echo "  19) Show Xcode guide"
    echo ""
    echo -e "${RED}  0) Exit${NC}"
    echo ""
}

# Execute choice
execute_choice() {
    case $1 in
        1)
            echo -e "${GREEN}🚀 Running on iOS Simulator...${NC}"
            ./run_ios.sh
            ;;
        2)
            echo -e "${GREEN}📱 Running on Physical iPhone...${NC}"
            ./RUN_ON_PHONE.sh
            ;;
        3)
            echo -e "${GREEN}🚀 Running app...${NC}"
            ./run_app.sh
            ;;
        4)
            echo -e "${GREEN}🔧 Fixing issues and running...${NC}"
            ./fix_and_run.sh
            ;;
        5)
            echo -e "${GREEN}🚀 Running without code signing...${NC}"
            ./run_without_signing.sh
            ;;
        6)
            echo -e "${GREEN}📦 Complete installation...${NC}"
            ./install_all.sh
            ;;
        7)
            echo -e "${GREEN}⚡ Quick installation...${NC}"
            ./quick_install.sh
            ;;
        8)
            echo -e "${GREEN}📦 Installing Node.js & Gateway...${NC}"
            ./INSTALL_NODE_AND_GATEWAY.sh
            ;;
        9)
            echo -e "${GREEN}💎 Fixing Ruby & installing CocoaPods...${NC}"
            ./FIX_RUBY_AND_INSTALL.sh
            ;;
        10)
            echo -e "${GREEN}🔧 Fixing code signing...${NC}"
            ./fix_signing.sh
            ;;
        11)
            echo -e "${GREEN}🔧 Opening Xcode...${NC}"
            ./open_xcode.sh
            ;;
        12)
            echo -e "${GREEN}🔐 Fixing keychain access...${NC}"
            ./FIX_KEYCHAIN_ACCESS.sh
            ;;
        13)
            echo -e "${GREEN}🌐 Starting Gateway Server...${NC}"
            ./START_GATEWAY.sh
            ;;
        14)
            echo -e "${GREEN}☁️  Deploying Gateway to Cloud Run...${NC}"
            cd gateway && ./deploy.sh
            ;;
        15)
            echo -e "${GREEN}🔍 Checking status...${NC}"
            ./check_status.sh
            ;;
        16)
            echo -e "${GREEN}🔍 Checking developer mode...${NC}"
            ./check_developer_mode.sh
            ;;
        17)
            echo -e "${GREEN}🔍 Getting Team ID...${NC}"
            ./get_team_id.sh
            ;;
        18)
            echo -e "${GREEN}📱 Checking available devices...${NC}"
            ./try_physical_device.sh
            ;;
        19)
            echo -e "${GREEN}📚 Showing Xcode guide...${NC}"
            ./show_xcode_guide.sh
            ;;
        0)
            echo -e "${GREEN}👋 Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Invalid choice. Please try again.${NC}"
            ;;
    esac
}

# Main loop
while true; do
    show_menu
    read -p "Select an option [0-19]: " choice
    echo ""
    execute_choice "$choice"
    echo ""
    if [ "$choice" != "0" ]; then
        read -p "Press Enter to continue..."
        clear
    fi
done
