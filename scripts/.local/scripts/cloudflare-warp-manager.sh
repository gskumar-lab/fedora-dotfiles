#!/bin/bash

# Cache sudo privileges at the start
sudo -v || { echo "This script requires sudo privileges."; exit 1; }

# ==========================================
# Core Functions
# ==========================================

check_installed() {
    if ! command -v warp-cli &> /dev/null; then
        echo "WARP is not installed. Please install it first."
        exit 1
    fi
}

install_warp() {
    echo "Installing Cloudflare WARP..."
    sudo dnf install cloudflare-warp -y
}

uninstall_warp() {
    echo "Uninstalling Cloudflare WARP..."
    sudo dnf remove cloudflare-warp -y
}

start_svc() {
    echo "Starting WARP service..."
    sudo systemctl start warp-svc
}

stop_svc() {
    echo "Stopping WARP service..."
    sudo systemctl stop warp-svc
}

register_warp() {
    check_installed
    echo "Removing existing registration (if any)..."
    warp-cli registration delete 2>/dev/null || echo "No previous registration to delete."
    
    sleep 1 
    
    echo "Registering new WARP client..."
    yes | warp-cli registration new
}

status_warp() {
    check_installed
    echo "Fetching WARP status..."
    warp-cli status
}

change_mode() {
    check_installed
    local mode=$1
    if [ -z "$mode" ]; then
        echo "Available modes: [ warp, doh, warp+doh, dot, warp+dot, proxy, tunnel_only ]"
        read -p "Enter desired mode: " mode
    fi
    warp-cli mode "$mode"
}

connect_warp() {
    check_installed
    start_svc
    sleep 2
    echo "Connecting to Cloudflare WARP..."
    warp-cli connect
    sleep 2
    status_warp
}

disconnect_warp() {
    check_installed
    echo "Disconnecting from Cloudflare WARP..."
    warp-cli disconnect
    sleep 1
    status_warp
    
    stop_svc
    
    systemctl --user stop warp-desktop-svc.service 2>/dev/null
    echo "Service stopped."
}

toggle_warp() {
    check_installed
    local SERVICE="warp-svc.service"

    # Get the actual user to ensure notify-send works even when run with sudo
    local USER_NAME=${SUDO_USER:-$USER}

    if systemctl is-active --quiet "$SERVICE"; then
        # WARP is ON → disconnect and stop service
        warp-cli disconnect
        sudo systemctl stop "$SERVICE"

        sudo -u "$USER_NAME" notify-send "Cloudflare WARP" "Disconnected 🔴" 2>/dev/null
        echo "WARP Disconnected."
    else
        # WARP is OFF → start service and connect
        sudo systemctl start "$SERVICE"

        # Give warp-svc time to initialize
        sleep 1

        warp-cli connect

        sudo -u "$USER_NAME" notify-send "Cloudflare WARP" "Connected 🟢" 2>/dev/null
        echo "WARP Connected."
    fi
}

# ==========================================
# Interactive Menu
# ==========================================

interactive_menu() {
    while true; do
        clear
        echo "========================================="
        echo "     Cloudflare WARP Management Tool     "
        echo "========================================="
        echo "1. Install Cloudflare WARP"
        echo "2. Uninstall Cloudflare WARP"
        echo "3. Start WARP Service"
        echo "4. Stop WARP Service"
        echo "5. New Registration"
        echo "6. Check Status"
        echo "7. Change Mode"
        echo "8. Connect"
        echo "9. Disconnect"
        echo "10. Toggle WARP (ON/OFF)"
        echo "0. Exit"
        echo "========================================="

        if ! command -v warp-cli &> /dev/null; then
            echo "WARP is not installed. Please run Option 1 first."
        fi
        
        read -p "Select an option [0-10]: " choice
        echo ""

        case $choice in
            1) install_warp ;;
            2) uninstall_warp ;;
            3) start_svc ;;
            4) stop_svc ;;
            5) register_warp ;;
            6) status_warp ;;
            7) change_mode ;;
            8) connect_warp ;;
            9) disconnect_warp ;;
            10) toggle_warp ;;
            0) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        
        echo ""
        read -p "Press [Enter] to return to the menu..."
    done
}

# ==========================================
# CLI Flag Parsing
# ==========================================

if [ $# -eq 0 ]; then
    interactive_menu
else
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -i|--install) install_warp; exit 0 ;;
            -u|--uninstall) uninstall_warp; exit 0 ;;
            -s|--start) start_svc; exit 0 ;;
            -x|--stop) stop_svc; exit 0 ;;
            -r|--register) register_warp; exit 0 ;;
            -t|--status) status_warp; exit 0 ;;
            -m|--mode) 
                if [ -n "$2" ]; then
                    change_mode "$2"
                    shift
                else
                    change_mode
                fi
                exit 0 ;;
            -c|--connect) connect_warp; exit 0 ;;
            -d|--disconnect) disconnect_warp; exit 0 ;;
            -g|--toggle) toggle_warp; exit 0 ;;
            -h|--help)
                echo "Usage: $0 [OPTION]"
                echo "Options:"
                echo "  -i, --install      Install Cloudflare WARP"
                echo "  -u, --uninstall    Uninstall Cloudflare WARP"
                echo "  -s, --start        Start WARP background service"
                echo "  -x, --stop         Stop WARP background service"
                echo "  -r, --register     Register a new WARP client"
                echo "  -t, --status       Check WARP status"
                echo "  -m, --mode [MODE]  Change WARP mode"
                echo "  -c, --connect      Start service and connect"
                echo "  -d, --disconnect   Disconnect and stop service"
                echo "  -g, --toggle       Toggle WARP connection ON/OFF"
                echo "  -h, --help         Display this help message"
                exit 0
                ;;
            *)
                echo "Invalid flag: $1"
                echo "Use -h or --help for usage information."
                exit 1
                ;;
        esac
        shift
    done
fi
