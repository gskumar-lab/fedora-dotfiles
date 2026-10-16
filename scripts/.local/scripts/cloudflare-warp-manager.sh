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

send_notification() {
    local title="$1"
    local message="$2"
    local target_user="${SUDO_USER:-$USER}"

    # If running as regular user without sudo, run notify-send directly
    if [ -z "$SUDO_USER" ]; then
        notify-send -i network-vpn "$title" "$message" 2>/dev/null
        return
    fi

    # Detect user's DBUS address and run notify-send inside their user session
    local user_id
    user_id=$(id -u "$target_user")

    sudo -u "$target_user" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
        DISPLAY="${DISPLAY:-:0}" \
        notify-send -i network-vpn "$title" "$message" 2>/dev/null
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
        if ! command -v fzf &> /dev/null; then
            echo "fzf is not installed. Available modes: warp, doh, warp+doh, dot, warp+dot, proxy, tunnel_only"
            read -p "Enter desired mode: " mode
        else
            local modes="warp\ndoh\nwarp+doh\ndot\nwarp+dot\nproxy\ntunnel_only"
            mode=$(echo -e "$modes" | fzf --prompt="Select Mode > " --height=30% --layout=reverse --border=rounded)
        fi
    fi
    
    if [ -n "$mode" ]; then
        warp-cli mode "$mode"
        echo "Mode changed to: $mode"
    else
        echo "Operation cancelled."
    fi
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

    if systemctl is-active --quiet "$SERVICE"; then
        # WARP is ON → disconnect and stop service
        warp-cli disconnect
        sudo systemctl stop "$SERVICE"
        send_notification "Cloudflare WARP" "Disconnected 🔴"
        echo "WARP Disconnected."
    else
        # WARP is OFF → start service and connect
        sudo systemctl start "$SERVICE"
        sleep 1
        warp-cli connect
        send_notification "Cloudflare WARP" "Connected 🟢"
        echo "WARP Connected."
    fi
}

# ==========================================
# Interactive fzf Menu
# ==========================================

interactive_menu() {
    if ! command -v fzf &> /dev/null; then
        echo "Error: 'fzf' is required for the interactive menu."
        echo "Please install it using: sudo dnf install fzf"
        exit 1
    fi

    # Define menu options (Most used at the top)
    local options="1. Toggle WARP (ON/OFF)
2. Connect
3. Disconnect
4. Check Status
5. Change Mode
6. Start WARP Service
7. Stop WARP Service
8. New Registration
9. Install Cloudflare WARP
10. Uninstall Cloudflare WARP
0. Exit"

    while true; do
        clear
        echo "========================================="
        echo "     Cloudflare WARP Manager (fzf)       "
        echo "========================================="
        
        if ! command -v warp-cli &> /dev/null; then
            echo -e "\n⚠️  WARP is not installed. Please select 'Install Cloudflare WARP'."
        fi

        # Pass options to fzf
        local choice
        choice=$(echo "$options" | fzf --prompt="Select an option > " --height=50% --layout=reverse --border=rounded)

        # Handle cancellation (ESC/Ctrl+C)
        if [ -z "$choice" ]; then
            echo "Exiting..."
            exit 0
        fi

        echo ""
        # Execute based on selection prefix
        case "$choice" in
            1.*) toggle_warp ;;
            2.*) connect_warp ;;
            3.*) disconnect_warp ;;
            4.*) status_warp ;;
            5.*) change_mode ;;
            6.*) start_svc ;;
            7.*) stop_svc ;;
            8.*) register_warp ;;
            9.*) install_warp ;;
            10.*) uninstall_warp ;;
            0.*) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid option." ;;
        esac
        
        echo ""
        read -n 1 -s -r -p "Press any key to return to the menu..."
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
                if [ -n "$2" ] && [[ "$2" != -* ]]; then
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
                echo "  -m, --mode [MODE]  Change WARP mode (uses fzf if no mode provided)"
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

