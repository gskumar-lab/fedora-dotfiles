#!/bin/bash
sudo -v || { echo "This script requires sudo privileges."; exit 1; }
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
    echo "0. Exit"
    echo "========================================="

    if ! command -v warp-cli &> /dev/null; then
    echo "WARP is not installed. Please run Option 1 first."
    fi
    read -p "Select an option [0-9]: " choice

    echo ""


    case $choice in
        1)
            echo "Installing Cloudflare WARP..."
            # Note: cloudflare-warp-bin is typically an AUR package. 
            # If standard pacman fails, replace 'sudo pacman' with 'yay' or 'paru'.
            #sudo pacman -S cloudflare-warp-bin --noconfirm
            sudo dnf install cloudflare-warp -y
	    ;;
        2)
            echo "Uninstalling Cloudflare WARP..."
            #sudo pacman -Rns cloudflare-warp-bin --noconfirm
            sudo dnf remove cloudflare-warp -y
	    ;;

        3)
            echo "Starting WARP service..."
            sudo systemctl start warp-svc
            #sudo systemctl enable warp-svc
            echo "Service started and enabled on boot."
            ;;
        4)
            echo "Stopping WARP service..."
            sudo systemctl stop warp-svc
            #sudo systemctl disable warp-svc
            echo "Service stopped."
            ;;

        5)
            echo "Removing existing registration (if any)..."
            # Try to delete. If it fails (e.g., missing registration), silently ignore the error.
            warp-cli registration delete 2>/dev/null || echo "No previous registration to delete."
            
            sleep 1 # Added sleep to ensure daemon registers the deletion
            
            echo "Registering new WARP client..."
            yes | warp-cli registration new
            ;;
        6)
            echo "Fetching WARP status..."
            warp-cli status
            ;;
        7)
            echo "Available modes:"
            echo "[ warp, doh, warp+doh, dot, warp+dot, proxy, tunnel_only ]"
            read -p "Enter desired mode: " mode
            warp-cli mode "$mode"
            ;;
        8)
            echo "Starting WARP service..."
            sudo systemctl start warp-svc
            sleep 2 # Crucial: wait for the WARP daemon to fully start and accept IPC
            echo "Service started."
            echo "Connecting to Cloudflare WARP..."
            warp-cli connect
            sleep 2 # Crucial: wait for the connection to be established before checking status
            warp-cli status
            ;;
        9)
            echo "Disconnecting from Cloudflare WARP..."
            warp-cli disconnect
            sleep 1 # Wait for the disconnect to process
            warp-cli status
            echo "Stopping WARP service..."
            sudo systemctl stop warp-svc
	    sudo systemctl --user stop  warp-desktop-svc.service
            echo "Service stopped."
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
    
    echo ""
    read -p "Press [Enter] to return to the menu..."
done

