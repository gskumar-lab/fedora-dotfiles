#!/usr/bin/env bash

set -o pipefail

STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# --- UI Theme / Colors ---
C_KEY=$'\033[1;36m'   # Cyan for hotkeys
C_DESC=$'\033[0;39m'  # Default for descriptions
C_SEP=$'\033[1;30m'   # Dark Gray for separators
C_RST=$'\033[0m'      # Reset
C_HEAD=$'\033[1;35m'  # Magenta for headers
C_WARN=$'\033[1;33m'  # Yellow for warnings

# Construct the multiline header for fzf
FZF_HEADER="${C_KEY}ENTER${C_RST}: Copy ${C_SEP}|${C_RST} ${C_KEY}C-v${C_RST}: View ${C_SEP}|${C_RST} ${C_KEY}C-e${C_RST}: Edit ${C_SEP}|${C_RST} ${C_KEY}C-i${C_RST}: Insert ${C_SEP}|${C_RST} ${C_KEY}?${C_RST}: Preview"
FZF_HEADER+=$'\n'
FZF_HEADER+="${C_KEY}C-g${C_RST}: Generate ${C_SEP}|${C_RST} ${C_KEY}C-d${C_RST}: Delete ${C_SEP}|${C_RST} ${C_KEY}C-s${C_RST}: Git ${C_SEP}|${C_RST} ${C_KEY}C-r${C_RST}: Init ${C_SEP}|${C_RST} ${C_KEY}C-h${C_RST}: Help"

# 1. Dependency Checking
check_dependencies() {
    local missing=()
    for dep in pass fzf gpg; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        clear
        echo -e "\033[1;31mError: Missing required dependencies.\033[0m"
        echo "Please install the following tools before running this script:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
}

# 2. Init Logic (Handles GPG Generation and Git Upstream)
run_init() {
    clear
    echo -e "${C_HEAD}=== Initialize / Re-initialize Password Store ===${C_RST}"
    echo -e "\033[1;34mAvailable GPG Secret Keys:\033[0m"
    
    key_count=$(gpg --list-secret-keys --keyid-format=long | grep -c '^sec' || true)
    if [[ $key_count -gt 0 ]]; then
        gpg --list-secret-keys --keyid-format=long | grep -E '(sec|uid)'
    else
        echo "No existing GPG keys found on this system."
    fi
    echo
    
    echo "Tip: You can enter multiple GPG IDs separated by spaces to encrypt for multiple keys."
    read -r -p "Enter GPG Key ID(s), or type 'new' to generate a key: " gpg_input
    
    if [[ "${gpg_input,,}" == "new" ]]; then
        echo -e "\n\033[1;32mStarting GPG Key Generation...\033[0m"
        gpg --gen-key
        echo -e "\n\033[1;34mUpdated GPG Keys:\033[0m"
        gpg --list-secret-keys --keyid-format=long | grep -E '(sec|uid)'
        echo
        read -r -p "Enter the new GPG Key ID or email: " gpg_ids
    else
        gpg_ids="$gpg_input"
    fi
    
    if [[ -n "$gpg_ids" ]]; then
        # shellcheck disable=SC2086
        pass init $gpg_ids
        
        if [[ ! -d "$STORE_DIR/.git" ]]; then
            echo
            read -r -p "Initialize a Git repository for syncing? (y/n): " git_choice
            if [[ "$git_choice" =~ ^[Yy]$ ]]; then
                pass git init
                echo "Git repository initialized."
                
                echo
                read -r -p "Link a remote repository now? (e.g., git@github.com:user/pass.git) (y/n): " link_remote
                if [[ "$link_remote" =~ ^[Yy]$ ]]; then
                    read -r -p "Enter remote URL: " remote_url
                    if [[ -n "$remote_url" ]]; then
                        pass git remote add origin "$remote_url"
                        branch=$(git -C "$STORE_DIR" branch --show-current 2>/dev/null)
                        branch=${branch:-master}
                        
                        echo "Setting upstream and pushing to origin/$branch..."
                        pass git push --set-upstream origin "$branch"
                    fi
                fi
            fi
        fi
        echo -e "\nInitialization complete."
    else
        echo -e "\nAborted. No GPG key provided."
    fi
    
    echo
    read -n 1 -s -r -p "Press any key to return..."
}

# Helper: Show detailed Help Screen
show_help() {
    clear
    echo -e "${C_HEAD}=== Pass TUI Helper ===${C_RST}\n"
    
    echo -e "${C_HEAD}Actions:${C_RST}"
    echo -e "  ${C_KEY}ENTER${C_RST}      : Copy the selected password to your clipboard (clears automatically)."
    echo -e "  ${C_KEY}Ctrl + v${C_RST}   : View the full unencrypted contents of the selected entry."
    echo -e "  ${C_KEY}?${C_RST}          : Toggle a live preview window on the right side of the screen."
    echo -e "               ${C_WARN}(Disabled by default to avoid triggering GPG prompts while scrolling)${C_RST}\n"
    
    echo -e "${C_HEAD}Management:${C_RST}"
    echo -e "  ${C_KEY}Ctrl + g${C_RST}   : Generate a new random password and save it to a new path."
    echo -e "  ${C_KEY}Ctrl + i${C_RST}   : Insert an existing password/note manually using a text editor."
    echo -e "  ${C_KEY}Ctrl + e${C_RST}   : Edit the currently selected password file."
    echo -e "  ${C_KEY}Ctrl + d${C_RST}   : Delete the currently selected password.\n"
    
    echo -e "${C_HEAD}System:${C_RST}"
    echo -e "  ${C_KEY}Ctrl + s${C_RST}   : Open the Git synchronization menu (Pull, Push, Status)."
    echo -e "  ${C_KEY}Ctrl + r${C_RST}   : Initialize or Re-initialize the password store with GPG keys."
    echo -e "  ${C_KEY}ESC / C-c${C_RST}  : Exit the application.\n"

    read -n 1 -s -r -p "Press any key to return to the menu..."
}

# 3. Startup Checks
check_dependencies
if [[ ! -f "$STORE_DIR/.gpg-id" ]]; then
    run_init
    if [[ ! -f "$STORE_DIR/.gpg-id" ]]; then
        echo "Cannot proceed without an initialized password store."
        exit 1
    fi
fi

# Helper to list passwords
get_passwords() {
    if [[ -d "$STORE_DIR" ]]; then
        find "$STORE_DIR" -name "*.gpg" -type f -printf "%P\n" | sed 's/\.gpg$//' | sort
    fi
}

# 4. Main TUI Loop
while true; do
    out=$(get_passwords | fzf \
        --prompt="🔑 Pass> " \
        --pointer="▶" \
        --header="$FZF_HEADER" \
        --expect=ctrl-v,ctrl-e,ctrl-g,ctrl-i,ctrl-d,ctrl-s,ctrl-r,ctrl-h \
        --preview='pass show {}' \
        --preview-window='right:50%:hidden' \
        --bind='?:toggle-preview' \
        --layout=reverse \
        --height=100% \
        --border=rounded \
        --info=inline \
        --ansi) # Important: --ansi allows the color codes in the header to render

    fzf_exit=$?
    if [[ $fzf_exit -eq 130 || -z "$out" ]]; then
        clear
        exit 0
    fi

    key=$(head -n 1 <<< "$out")
    selection=$(tail -n +2 <<< "$out")

    case "$key" in
        "") # ENTER: Copy
            if [[ -n "$selection" ]]; then
                clear
                echo "Copying password for '$selection' to clipboard..."
                pass -c "$selection"
                exit 0
            fi
            ;;
        "ctrl-v") # View
            if [[ -n "$selection" ]]; then
                clear
                echo -e "\033[1;34m=== $selection ===\033[0m\n"
                pass show "$selection"
                echo
                read -n 1 -s -r -p "Press any key to return to menu..."
            fi
            ;;
        "ctrl-e") # Edit
            if [[ -n "$selection" ]]; then
                pass edit "$selection"
            fi
            ;;
        "ctrl-g") # Generate
            clear
            echo -e "\033[1;32m=== Generate New Password ===\033[0m"
            read -r -p "Path (e.g., website.com/username): " new_path
            if [[ -n "$new_path" ]]; then
                read -r -p "Length [default: 20]: " length
                length=${length:-20}
                pass generate -c "$new_path" "$length"
                echo
                read -n 1 -s -r -p "Press any key to return to menu..."
            fi
            ;;
        "ctrl-i") # Insert
            clear
            echo -e "\033[1;33m=== Insert Existing Password ===\033[0m"
            read -r -p "Path (e.g., website.com/username): " new_path
            if [[ -n "$new_path" ]]; then
                pass insert -m "$new_path"
                echo
                read -n 1 -s -r -p "Press any key to return to menu..."
            fi
            ;;
        "ctrl-d") # Delete
            if [[ -n "$selection" ]]; then
                clear
                pass rm "$selection"
                echo
                read -n 1 -s -r -p "Press any key to return to menu..."
            fi
            ;;
        "ctrl-s") # Git Handling
            clear
            echo -e "\033[1;36m=== Git Synchronization ===\033[0m"
            if [[ ! -d "$STORE_DIR/.git" ]]; then
                echo "Git is not initialized for this password store."
                read -r -p "Initialize git now? (y/n): " init_git
                if [[ "$init_git" =~ ^[Yy]$ ]]; then
                    pass git init
                fi
            else
                echo "1. Git Pull (Sync from remote)"
                echo "2. Git Push (Sync to remote)"
                echo "3. Git Status"
                echo "4. Add Remote Origin / Set Upstream"
                echo "q. Cancel"
                echo
                read -r -p "Select action [1-4]: " git_act
                
                case "$git_act" in
                    1) pass git pull ;;
                    2) pass git push ;;
                    3) pass git status ;;
                    4) 
                        read -r -p "Enter remote URL (e.g., git@github.com:user/pass.git): " remote_url
                        if [[ -n "$remote_url" ]]; then
                            pass git remote add origin "$remote_url"
                            branch=$(git -C "$STORE_DIR" branch --show-current 2>/dev/null)
                            branch=${branch:-master}
                            pass git push --set-upstream origin "$branch"
                        fi
                        ;;
                esac
            fi
            echo
            read -n 1 -s -r -p "Press any key to return to menu..."
            ;;
        "ctrl-r") # Init / Re-init
            run_init
            ;;
        "ctrl-h") # Help Screen
            show_help
            ;;
    esac
done

