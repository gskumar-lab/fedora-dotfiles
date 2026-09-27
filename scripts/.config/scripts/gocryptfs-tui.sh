#!/usr/bin/env bash

# ==========================================
# gocryptfs Pure Bash Wrapper (Bulletproof)
# ==========================================

# Configuration File
CONFIG_FILE="${HOME}/.config/scripts/gocryptfs-tui.conf"

# Default Values
CIPHER_DIR="${HOME}/.vault_cipher"
MOUNT_DIR="${HOME}/Vault"

# Load saved locations if they exist
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Colors for UI
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Dependency Check
check_dependencies() {
    if ! command -v gocryptfs &> /dev/null; then
        echo -e "${RED}Missing dependency: gocryptfs${NC}"
        if [ -f /etc/arch-release ]; then
            read -p "Arch Linux detected. Install using pacman? (y/n): " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                sudo pacman -S --needed gocryptfs
            else
                exit 1
            fi
        else
            echo "Please install gocryptfs using your system's package manager."
            exit 1
        fi
        if ! command -v gocryptfs &> /dev/null; then exit 1; fi
    fi
}

check_dependencies

# 2. Auto-Lock on Exit (Handles Busy Resources)
auto_lock_on_exit() {
	# Step 1: Unmount if it is currently mounted
    if mountpoint -q "$MOUNT_DIR"; then
        echo -e "\n${YELLOW}Closing... Auto-locking vault.${NC}"
        
        umount "$MOUNT_DIR"

        if mountpoint -q "$MOUNT_DIR"; then
            echo -e "${RED}⚠️ Vault is busy. Forcing lazy unmount...${NC}"
            umount -l "$MOUNT_DIR" 
	    sleep 1
            
            if mountpoint -q "$MOUNT_DIR"; then
                echo -e "${RED}❌ Critical: Failed to lock vault!${NC}"
		command -v notify-send >/dev/null && notify-send -u critical "Vault Error ❌" "Failed to lock vault at $MOUNT_DIR!"
            else
                echo -e "${GREEN}🔒 Vault securely locked (lazy unmount).${NC}"
		rmdir "$MOUNT_DIR" 2>/dev/null # Removes the folder
		command -v notify-send >/dev/null && notify-send -u low "Vault Locked 🔒" "Your vault has been securely locked."
            fi
        else
            echo -e "${GREEN}🔒 Vault securely locked.${NC}"
	    rmdir "$MOUNT_DIR" 2>/dev/null # Removes the folder
	    command -v notify-send >/dev/null && notify-send -u low "Vault Locked 🔒" "Your vault has been securely locked."
        fi
        sleep 1.5
    fi

    # Step 2: Clean up the directory (if it is NOT mounted)
    if ! mountpoint -q "$MOUNT_DIR"; then
        rmdir "$MOUNT_DIR" 2>/dev/null
    fi

    echo -e "${NC}"
    clear
}

#trap auto_lock_on_exit EXIT
trap auto_lock_on_exit EXIT HUP INT TERM

# 3. Action Functions
do_init() {
    clear
    mkdir -p "$CIPHER_DIR" "$MOUNT_DIR"
    chmod 700 "$CIPHER_DIR" "$MOUNT_DIR" # Restrict permissions to your user only
    
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${GREEN} Initializing New Vault${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${YELLOW}WARNING: Never manually edit or move files inside $CIPHER_DIR!${NC}"
    echo "Please create a strong master password."
    echo ""
    
    gocryptfs -init "$CIPHER_DIR"
    
    echo ""
    read -p "Press [ENTER] to return to the menu..."
}

do_open() {
    clear
    mkdir -p "$MOUNT_DIR"
    
    if ! stat "$MOUNT_DIR" >/dev/null 2>&1; then
        echo -e "${YELLOW}Broken mount detected (Transport endpoint disconnected). Cleaning up...${NC}"
        umount -l "$MOUNT_DIR" 2>/dev/null
        sleep 1
    fi

    # Unencrypted file contamination check
    if [ "$(ls -A "$MOUNT_DIR" 2>/dev/null)" ] && ! mountpoint -q "$MOUNT_DIR"; then
        echo -e "${RED}Error: $MOUNT_DIR contains unencrypted files!${NC}"
        echo "Please move them out of the Vault folder before opening to prevent data loss."
        read -p "Press [ENTER] to return..."
        return
    fi

    echo -e "${BLUE}==========================================${NC}"
    echo -e "${YELLOW} Unlocking Vault${NC}"
    echo -e "${BLUE}==========================================${NC}"
    
    gocryptfs "$CIPHER_DIR" "$MOUNT_DIR"
    
    if ! mountpoint -q "$MOUNT_DIR"; then
        echo -e "\n${RED}Failed to unlock vault. Incorrect password?${NC}"
        sleep 2
    else
	# Trigger success notification
        command -v notify-send >/dev/null && notify-send -u low  "Vault Unlocked 🔓" "Your files are ready at $MOUNT_DIR"
    fi
}

do_status() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e " Vault Status"
    echo -e "${BLUE}==========================================${NC}"
    if mountpoint -q "$MOUNT_DIR"; then
        echo -e "${GREEN}🔓 Vault is currently: UNLOCKED${NC}"
        echo -e "Access your files at: $MOUNT_DIR"
    else
        echo -e "${RED}🔒 Vault is currently: LOCKED${NC}"
        echo -e "Your data is completely encrypted."
    fi
    echo ""
    read -p "Press [ENTER] to return to the menu..."
}

do_change_location() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${YELLOW} Change Vault Location / Open Existing${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "Current Cipher Dir : ${GREEN}$CIPHER_DIR${NC}"
    echo -e "Current Mount Dir  : ${GREEN}$MOUNT_DIR${NC}"
    echo ""
    echo "To open an existing vault, enter its Cipher Directory below."
    echo "(Leave blank and press ENTER to keep current paths)"
    echo ""
    
    read -p "New Cipher Directory (e.g., /home/user/hidden_vault): " new_cipher
    read -p "New Mount Directory (e.g., /home/user/MyVault): " new_mount
    
    # Expand tilde (~) to full home path if used, and update variables if not empty
    if [ -n "$new_cipher" ]; then
        CIPHER_DIR="${new_cipher/#\~/$HOME}"
    fi
    
    if [ -n "$new_mount" ]; then
        MOUNT_DIR="${new_mount/#\~/$HOME}"
    fi

    # Save the new paths to the config file so they persist
    echo "CIPHER_DIR=\"$CIPHER_DIR\"" > "$CONFIG_FILE"
    echo "MOUNT_DIR=\"$MOUNT_DIR\"" >> "$CONFIG_FILE"

    echo -e "\n${GREEN}✔ Locations updated and saved for future sessions!${NC}"
    
    sleep 1.5
}

# 4. Main Menu Loop
while true; do
    clear
    IS_MOUNTED=0
    IS_INIT=0

    mountpoint -q "$MOUNT_DIR" && IS_MOUNTED=1
    [ -f "$CIPHER_DIR/gocryptfs.conf" ] && IS_INIT=1

    echo -e "${BLUE}==========================================${NC}"
    echo -e "           gocryptfs Vault Manager        "
    echo -e "${BLUE}==========================================${NC}"
    echo -e "Cipher : ${GREEN}$CIPHER_DIR${NC}"
    echo -e "Mount  : ${GREEN}$MOUNT_DIR${NC}"
    echo -e "${BLUE}------------------------------------------${NC}"

    if [ $IS_INIT -eq 0 ]; then
        echo -e "Status: ${RED}No Vault Found at $CIPHER_DIR${NC}\n"
        echo "1) Initialize New Vault"
        echo "2) Open Existing Vault (Change Location)"
        echo "Q) Quit"
        echo ""
        read -p "Select an option: " choice
        case "$choice" in
            1) do_init ;;
            2) do_change_location ;;
            [Qq]) exit 0 ;;
            *) ;;
        esac

    elif [ $IS_MOUNTED -eq 1 ]; then
        echo -e "Status: ${GREEN}UNLOCKED 🔓${NC}\n"
        echo -e "${YELLOW}(Closing this menu will automatically lock the vault)${NC}\n"
        echo "1) Lock & Quit"
        echo "2) Check Status"
        echo ""
        read -p "Select an option: " choice
        case "$choice" in
            1) exit 0 ;;
            2) do_status ;;
            *) ;;
        esac

    else
        echo -e "Status: ${RED}LOCKED 🔒${NC}\n"
        echo "1) Unlock Vault"
        echo "2) Change Vault Location"
        echo "Q) Quit"
        echo ""
        read -p "Select an option: " choice
        case "$choice" in
            1) do_open ;;
            2) do_change_location ;;
            [Qq]) exit 0 ;;
            *) ;;
        esac
    fi
done


