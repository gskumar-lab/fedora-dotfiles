#!/usr/bin/env bash

set -eo pipefail

# -----------------------------------------------------------------------------
# 0. Background Handlers (Self-calling execution blocks for FZF)
# -----------------------------------------------------------------------------

# Safely executes ripgrep only when there is an actual query, preventing 
# massive CPU spikes and freezing when searching large directories like ~
if [[ "$1" == "--rg" ]]; then
    query="$2"
    target_dir="$3"
    if [[ -z "$query" ]]; then
        echo "Type a query to search file contents..."
        exit 0
    fi
    rg --column --line-number --no-heading --color=always --smart-case -e "$query" "$target_dir" 2>/dev/null
    exit 0
fi

if [[ "$1" == "--preview" ]]; then
    item="$2"
    bat_cmd="$3"
    
    # Extract filename (everything before the first colon, if colons exist)
    file="${item%%:*}"
    
    if [[ ! -f "$file" ]]; then
        echo "File not found: $file"
        exit 0
    fi

    echo -e "\e[1;34mPath:\e[0m $file\n---"

    if [[ "$item" =~ ^[^:]+:[0-9]+: ]]; then
        # Text Mode (rg output: file:line:col:text)
        rest="${item#*:}"      # Strip file path
        line="${rest%%:*}"     # Extract line number
        
        if [[ "$bat_cmd" != "cat" ]]; then
            start_line=$(( line - 15 > 0 ? line - 15 : 1 ))
            "$bat_cmd" --style=numbers --color=always --highlight-line "$line" --line-range "${start_line}:$((line + 15))" "$file"
        else
            start_line=$(( line - 15 > 0 ? line - 15 : 1 ))
            cat -n "$file" | sed -n "${start_line},$((line + 15))p"
        fi
    else
        # File Mode
        if [[ "$bat_cmd" != "cat" ]]; then
            "$bat_cmd" --style=numbers,changes --color=always "$file"
        else
            cat -n "$file" | head -n 100
        fi
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# 1. Dependency Check & Installer
# -----------------------------------------------------------------------------

detect_package_manager() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v zypper &>/dev/null; then echo "zypper"
    elif command -v brew &>/dev/null; then echo "brew"
    else echo "unknown"; fi
}

install_packages() {
    local pm="$1"
    shift
    local pkgs=("$@")

    echo -e "\nAttempting installation with: $pm"
    case "$pm" in
        apt) sudo apt-get update && sudo apt-get install -y "${pkgs[@]}" ;;
        dnf) sudo dnf install -y "${pkgs[@]}" ;;
        pacman) sudo pacman -S --noconfirm "${pkgs[@]}" ;;
        zypper) sudo zypper install -y "${pkgs[@]}" ;;
        brew) brew install "${pkgs[@]}" ;;
        *) echo "Error: Install missing dependencies manually: ${pkgs[*]}"; exit 1 ;;
    esac
}

check_dependencies() {
    local missing=()
    local pm
    pm="$(detect_package_manager)"

    [[ ! -x "$(command -v fzf)" ]] && missing+=("fzf")
    [[ ! -x "$(command -v rg)" ]] && missing+=("ripgrep")
    
    if ! command -v bat &>/dev/null && ! command -v batcat &>/dev/null; then
        [[ "$pm" == "apt" ]] && missing+=("bat") || missing+=("bat")
    fi

    if [[ "$(uname)" == "Linux" ]] && ! command -v xdg-open &>/dev/null; then
        missing+=("xdg-utils")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        clear
        echo "Missing recommended dependencies: ${missing[*]}"
        read -r -p "Would you like to install them now using '$pm'? [y/N] " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            install_packages "$pm" "${missing[@]}"
        else
            echo "Proceeding with missing dependencies..."
            sleep 2
        fi
    fi
}

get_bat_cmd() {
    if command -v bat &>/dev/null; then echo "bat"
    elif command -v batcat &>/dev/null; then echo "batcat"
    else echo "cat"; fi
}

# -----------------------------------------------------------------------------
# 2. File Manager Launcher
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 2. File Manager Launcher
# -----------------------------------------------------------------------------

open_in_file_manager() {
    local target_path="$1"
    local dir_path
    dir_path="$(dirname "$target_path")"

    # Helper function to completely detach a GUI process from the script
    detach_cmd() {
        if command -v setsid &>/dev/null; then
            # setsid creates a new session, escaping the script's scope entirely
            setsid "$@" >/dev/null 2>&1 &
        else
            # Fallback if setsid isn't available
            nohup "$@" >/dev/null 2>&1 &
        fi
    }

    # Linux native environments
    if command -v nautilus &>/dev/null; then
        detach_cmd nautilus --select "$target_path"
    elif command -v dolphin &>/dev/null; then
        detach_cmd dolphin --select "$target_path"
    else
        detach_cmd xdg-open "$dir_path"
    fi
}

# -----------------------------------------------------------------------------
# 3. Search Modules
# -----------------------------------------------------------------------------

process_selection() {
    local selected_item="$1"
    [[ -z "$selected_item" ]] && return 1

    local raw_file="${selected_item%%:*}"
    
    # Ensure the file actually exists before trying to open it
    if [[ ! -f "$raw_file" ]]; then
        return 1
    fi

    local full_path
    full_path="$(cd "$(dirname "$raw_file")" && pwd)/$(basename "$raw_file")"

    clear
    echo "Opening directory for: $full_path"
    open_in_file_manager "$full_path"
    
    # Exit the entire script after successfully launching the file manager
    exit 0
}

search_files() {
    local search_root="$1"
    local bat_cmd="$2"
    local find_cmd

    if command -v fd &>/dev/null; then
        find_cmd="fd --type f --hidden --exclude .git . \"$search_root\""
    elif command -v fdfind &>/dev/null; then
        find_cmd="fdfind --type f --hidden --exclude .git . \"$search_root\""
    else
        find_cmd="find \"$search_root\" -type f -not -path '*/\.git/*' 2>/dev/null"
    fi

    # || true prevents `set -e` from killing the script if Esc is pressed (exit 130)
    local selected_item
    selected_item=$(eval "$find_cmd" | fzf \
        --prompt="🔍 File Name > " \
        --header="Enter: Open in File Manager | Esc: Back to Menu" \
        --preview "\"$0\" --preview {} \"$bat_cmd\"" \
        --preview-window=right,60%,border-left \
        --height=95% --reverse || true)

    # Return to main menu if ESC was pressed (selected_item is empty)
    [[ -z "$selected_item" ]] && return 0
    
    process_selection "$selected_item"
}

search_text() {
    local search_root="$1"
    local bat_cmd="$2"
    
    if ! command -v rg &>/dev/null; then
        echo "Ripgrep (rg) is required for text search."
        sleep 2
        return
    fi

    # || true prevents `set -e` from killing the script if Esc is pressed
    local selected_item
    selected_item=$(: | fzf \
        --prompt="📝 File Content > " \
        --header="Type to search content | Enter: Open in File Manager | Esc: Back to Menu" \
        --ansi \
        --phony \
        --bind "change:reload:\"$0\" --rg {q} \"$search_root\"" \
        --preview "\"$0\" --preview {} \"$bat_cmd\"" \
        --preview-window=up,60%,border-bottom \
        --height=95% --reverse || true)

    # Return to main menu if ESC was pressed
    [[ -z "$selected_item" ]] && return 0

    process_selection "$selected_item"
}

# -----------------------------------------------------------------------------
# 4. TUI Main Loop
# -----------------------------------------------------------------------------

main() {
    check_dependencies
    
    # Default path is Home (~), but can be overridden by passing an argument
    local search_root="${1:-$HOME}"
    
    # Ensure the path is absolute
    # Fallback to the current search_root if cd fails due to permissions
search_root="$(cd "$new_dir" 2>/dev/null && pwd || echo "$search_root")"
    
    local bat_cmd
    bat_cmd=$(get_bat_cmd)

    while true; do
        # Render the interactive main menu (|| true handles ESC press safely)
        local choice
        choice=$(echo -e "1. 🔍 Search Files (by Name)\n2. 📝 Search Text (by Content)\n3. 📁 Change Directory (Current: $search_root)\n4. ❌ Exit" | \
            fzf --prompt="Main Menu > " \
                --header="FZF File & Text Search Explorer" \
                --layout=reverse \
                --border=rounded \
                --margin=10%,20% \
                --height=40% || true)

        # Exit the script entirely if ESC is pressed at the main menu
        [[ -z "$choice" ]] && exit 0

        # Handle menu selection
        case "$choice" in
            1*)
                search_files "$search_root" "$bat_cmd"
                ;;
            2*)
                search_text "$search_root" "$bat_cmd"
                ;;
            3*)
                echo -n "Enter new directory path: "
                read -r -e new_dir
                # Expand tilde and check if valid directory
                new_dir="${new_dir/#\~/$HOME}"
                if [[ -d "$new_dir" ]]; then
                    search_root="$(cd "$new_dir" && pwd)"
                else
                    echo "Invalid directory!"
                    sleep 1
                fi
                ;;
            4*)
                clear
                exit 0
                ;;
        esac
    done
}

main "$@"
