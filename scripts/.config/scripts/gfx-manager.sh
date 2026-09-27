#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run this script as root or with sudo.${NC}"
    echo "Run it as a normal user. The script will request sudo privileges automatically when needed."
    exit 1
fi

IS_ARCH=false
if [ -f "/etc/arch-release" ]; then
    IS_ARCH=true
fi

pause_menu() {
    echo ""
    # More reliable than waiting for Enter; triggers on any single keypress
    read -n 1 -s -r -p "Press any key to return to the menu..."
    echo ""
}

install_supergfxctl() {
    echo -e "\n${CYAN}Starting installation of supergfxctl from the AUR...${NC}"
    local install_success=false
    
    if command -v yay &> /dev/null; then
        echo -e "${YELLOW}Detected 'yay'. Using it to install...${NC}"
        if yay -S --needed supergfxctl; then install_success=true; fi
    elif command -v paru &> /dev/null; then
        echo -e "${YELLOW}Detected 'paru'. Using it to install...${NC}"
        if paru -S --needed supergfxctl; then install_success=true; fi
    else
        echo -e "${YELLOW}No AUR helper found. Falling back to manual makepkg build...${NC}"
        sudo pacman -S --needed base-devel git
        
        local BUILD_DIR
        BUILD_DIR=$(mktemp -d)
        local ORIGINAL_DIR=$(pwd)
        
        cd "$BUILD_DIR" || exit
        git clone https://aur.archlinux.org/supergfxctl.git
        cd supergfxctl || exit
        
        if makepkg -si; then install_success=true; fi
        
        cd "$ORIGINAL_DIR" || exit
        rm -rf "$BUILD_DIR"
    fi
    
    if [ "$install_success" = true ] && command -v supergfxctl &> /dev/null; then
        sudo systemctl enable --now supergfxd
        echo -e "${GREEN}Installation successful!${NC}"
    else
        echo -e "${RED}Installation failed. Please review the output above.${NC}"
    fi
    pause_menu
}

uninstall_supergfxctl() {
    echo -e "\n${RED}WARNING: You are about to uninstall supergfxctl.${NC}"
    read -r -p "Are you sure you want to proceed? (y/n): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo systemctl disable --now supergfxd 2>/dev/null
        if sudo pacman -Rns supergfxctl; then
            echo -e "${GREEN}Uninstalled successfully.${NC}"
        else
            echo -e "${RED}Uninstallation failed.${NC}"
            sudo systemctl enable --now supergfxd 2>/dev/null
        fi
    else
        echo -e "${YELLOW}Uninstallation aborted.${NC}"
    fi
    pause_menu
}

show_current_mode() {
    local mode
    # FIX: Wrap in a 2-second timeout to prevent 25-second DBus lockups
    mode=$(timeout 2 supergfxctl -g 2>/dev/null)
    mode=$(echo "$mode" | tr -d '[],"')
    
    if [ -z "$mode" ]; then
        echo -e "${CYAN}Current Graphics Mode:${NC} ${RED}Unknown (Daemon busy/restarting)${NC}"
    else
        echo -e "${CYAN}Current Graphics Mode:${NC} ${GREEN}${mode}${NC}"
    fi
}

configure_gpu_services() {
    local mode="$1"

    echo -e "${CYAN}Configuring GPU services for ${mode} mode...${NC}"

    case "$mode" in
        Integrated)
            echo "Disabling NVIDIA services and switcheroo-control..."

            sudo systemctl disable --now nvidia-persistenced.service 2>/dev/null || true
            sudo systemctl disable --now nvidia-powerd.service 2>/dev/null || true
            sudo systemctl disable --now switcheroo-control.service 2>/dev/null || true
            ;;

        Hybrid)
            echo "Enabling switcheroo-control for hybrid graphics..."

            sudo systemctl disable --now nvidia-persistenced.service 2>/dev/null || true
            sudo systemctl enable --now nvidia-powerd.service 2>/dev/null || true
            sudo systemctl enable --now switcheroo-control.service 2>/dev/null || true
            ;;

        Dedicated|AsusMuxDgpu)
            echo "Enabling NVIDIA services for dedicated GPU..."

            sudo systemctl enable --now switcheroo-control.service 2>/dev/null || true
            sudo systemctl enable --now nvidia-persistenced.service 2>/dev/null || true
            sudo systemctl enable --now nvidia-powerd.service 2>/dev/null || true
            ;;

        Compute)
            echo "Enabling NVIDIA services for compute mode..."

            sudo systemctl disable --now switcheroo-control.service 2>/dev/null || true
            sudo systemctl enable --now nvidia-persistenced.service 2>/dev/null || true
            sudo systemctl enable --now nvidia-powerd.service 2>/dev/null || true
            ;;

        *)
            echo -e "${YELLOW}No GPU service policy defined for: ${mode}${NC}"
            ;;
    esac

    echo -e "${GREEN}GPU services configured.${NC}"
}

switch_mode() {
    local target_mode=$1
    echo -e "\n${YELLOW}Requesting switch to ${target_mode} mode...${NC}"
    
    # Execute switch
    supergfxctl -m "$target_mode"
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}Success! Graphics mode set to $target_mode.${NC}"
	configure_gpu_services "$target_mode"
        
        if [[ "$target_mode" == *"AsusMuxDgpu"* ]] || [[ "$target_mode" == "Integrated" ]]; then
            echo -e "${YELLOW}Note: You must log out and log back in (or reboot) for your display manager to fully apply this change.${NC}"
        fi
        
        # FIX: Actively poll the daemon until it wakes back up so it doesn't freeze the next menu loop
        echo -ne "${CYAN}Waiting for daemon to stabilize... ${NC}"
        for i in {1..15}; do
            if timeout 1 supergfxctl -g &>/dev/null; then
                echo -e "${GREEN}Ready.${NC}"
                break
            fi
            echo -ne "."
            sleep 1
        done
        echo ""
    else
        echo -e "${RED}Failed to switch to $target_mode. Make sure no apps are blocking the dGPU.${NC}"
    fi
}

# Main application loop
while true; do
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}       Supergfxctl GPU Manager          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # 1. Dependency Check
    if ! command -v supergfxctl &> /dev/null; then
        echo -e "${RED}Status: 'supergfxctl' is not installed.${NC}"
        if [ "$IS_ARCH" = true ]; then
            echo -e "\nOptions:"
            echo "  1) Install supergfxctl (Arch/AUR)"
            echo "  0) Exit"
            echo -e "${BLUE}----------------------------------------${NC}"
            read -r -p "Enter your choice: " choice
            
            if [[ "$choice" == "1" ]]; then install_supergfxctl; continue; fi
            if [[ "$choice" == "0" ]]; then exit 0; fi
        else
            echo -e "\n${YELLOW}Please install supergfxd manually using your package manager.${NC}"
            exit 1
        fi
        continue
    fi
    
    # 2. Service Check
    if ! systemctl is-active --quiet supergfxd; then
        echo -e "${RED}Status: 'supergfxd' background service is NOT running.${NC}"
        echo -e "\nOptions:"
        echo "  1) Start and Enable supergfxd service"
        if [ "$IS_ARCH" = true ]; then echo "  U) Uninstall supergfxctl"; fi
        echo "  0) Exit"
        echo -e "${BLUE}----------------------------------------${NC}"
        read -r -p "Enter your choice: " choice
        
        if [[ "$choice" == "1" ]]; then
            echo -e "${CYAN}Starting service...${NC}"
            sudo systemctl enable --now supergfxd
            sleep 2
            continue
        elif [[ "${choice^^}" == "U" ]] && [ "$IS_ARCH" = true ]; then uninstall_supergfxctl; continue
        elif [[ "$choice" == "0" ]]; then exit 0; fi
        continue
    fi
    
    # 3. Normal Operation
    show_current_mode
    echo -e "${BLUE}----------------------------------------${NC}"
    
    # FIX: 2-second timeout prevents long hanging if daemon crashes
    supported_raw=$(timeout 2 supergfxctl -s 2>/dev/null)
    modes_string=$(echo "$supported_raw" | grep -oE '\b(Integrated|Hybrid|Vfio|AsusMuxDgpu|AsusEgpu|Dedicated|Compute)\b' | xargs)
    read -r -a supported_modes <<< "$modes_string"
    
    if [ ${#supported_modes[@]} -eq 0 ]; then
        echo -e "${RED}Daemon is currently unresponsive or restarting modules.${NC}"
        echo "Please wait a few moments and try again."
        pause_menu
        continue
    fi
    
    echo "Select an action:"
    i=1
    for mode in "${supported_modes[@]}"; do
        echo "  $i) Switch to $mode"
        ((i++))
    done
    
    echo ""
    if [ "$IS_ARCH" = true ]; then echo "  U) Uninstall supergfxctl"; fi
    echo "  0) Exit"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    read -r -p "Enter your choice: " choice
    
    if [[ -z "$choice" ]]; then
        continue
    elif [[ "$choice" == "0" ]]; then
        echo -e "${GREEN}Exiting...${NC}"
        exit 0
    elif [[ "${choice^^}" == "U" ]] && [ "$IS_ARCH" = true ]; then
        uninstall_supergfxctl
        continue
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -le "${#supported_modes[@]}" ]; then
        index=$((choice-1))
        selected_mode="${supported_modes[$index]}"
        
        switch_mode "$selected_mode"
        pause_menu
    else
        echo -e "${RED}Invalid selection.${NC}"
        sleep 1
    fi
done

