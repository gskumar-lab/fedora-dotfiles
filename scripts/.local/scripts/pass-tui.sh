#!/usr/bin/env bash
# pass-tui: A feature-rich TUI wrapper for pass using fzf

set -uo pipefail
stty -ixon 2>/dev/null

# --- Configuration & Environment ---
PREFIX="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
export GPG_TTY=$(tty) # Essential for GPG pinentry in TUI

# --- Dependency Management ---
check_dependencies() {
    local deps=("pass" "fzf" "fd" "rg" "qrencode" "gpg")
    local missing=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for pass-otp extension
    if ! pass otp help &>/dev/null; then
        missing+=("pass-otp (pass extension)")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "\e[31mError: Missing dependencies.\e[0m"
        echo "Please install the following packages:"
        printf " - %s\n" "${missing[@]}"
        exit 1
    fi
}

# --- Initialization & Edge Cases ---
init_checks() {
    if [ ! -d "$PREFIX" ]; then
        echo "Password store not found at $PREFIX."
        read -p "Initialize a new password store? (y/n): " init_choice
        if [[ "$init_choice" =~ ^[Yy]$ ]]; then
            read -p "Enter GPG Key ID or Email: " gpg_key
            pass init "$gpg_key"
            read -p "Initialize Git repository? (y/n): " git_choice
            if [[ "$git_choice" =~ ^[Yy]$ ]]; then
                pass git init
            fi
        else
            echo "Exiting."
            exit 1
        fi
    fi
}

# --- Git Handling ---
handle_git() {
    if [ -d "$PREFIX/.git" ]; then
        echo "Syncing with Git repository..."
        pass git pull --rebase || echo "Git pull failed. Check remote."
        pass git push || echo "Git push failed. Check remote."
    fi
}

# --- Core Functions ---
get_passwords() {
    # Uses fd for fast filename retrieval, strips the .gpg extension
    if [ -d "$PREFIX" ]; then
        cd "$PREFIX" && fd -t f -e gpg . | sed 's/\.gpg$//' | sed 's/^\.\///'
    fi
}

show_help() {
    echo "
Pass-TUI Helpers:
  Enter     : Copy password to clipboard (Line 1)
  Ctrl-V    : View full password information
  Ctrl-E    : Edit password entry
  Ctrl-A    : Add new password
  Ctrl-G    : Generate new password
  Ctrl-D    : Delete password
  Ctrl-O    : Copy OTP code to clipboard
  Ctrl-Q    : Show QR Code (for sharing or OTP)
  Ctrl-S    : Search inside password files (Content search via rg/pass grep)
  Ctrl-/    : Toggle Preview Window
  Ctrl-H    : Show this help text
"
}

# --- Main TUI ---
main() {
    check_dependencies
    init_checks

    # Multiline header for better readability
    local header="[Enter]:Copy   [^V]:View      [^E]:Edit      [^A]:Add
[^G]:Gen       [^D]:Del       [^O]:OTP       [^Q]:QR
[^S]:Search    [^/]:Preview   [^P]:Git Sync  [^H]:Help
--------------------------------------------------------"
    
    while true; do
        local selected
        # fzf window with optional preview (hidden by default to prevent GPG pinentry freezing)
        selected=$(get_passwords | fzf \
            --prompt="🔑 Pass > " \
            --header="$header" \
            --preview='pass show {}' \
            --preview-window="right:50%:wrap:hidden" \
            --bind="ctrl-/:toggle-preview" \
            --bind="ctrl-h:execute(echo -e \"$(show_help)\" | less)+abort" \
            --bind="ctrl-s:execute(if [ -n {q} ]; then pass grep {q} | less -R; else echo 'Type a query before pressing Ctrl-S' | less; fi)" \
            --expect=ctrl-v,ctrl-e,ctrl-a,ctrl-g,ctrl-d,ctrl-o,ctrl-q,ctrl-p,enter \
            --height=100% --layout=reverse)

        local exit_code=$?
        
        # Parse fzf output
        local key=$(head -n 1 <<< "$selected")
        local entry=$(tail -n +2 <<< "$selected")

        # Handle Esc / Ctrl-C (clean exit)
        if [ $exit_code -ne 0 ] && [ -z "$key" ]; then
        #    handle_git
            clear
            exit 0
        fi

        # Handle Actions
        case "$key" in
            enter)
                if [ -n "$entry" ]; then
                    pass -c "$entry"
                    read -n 1 -s -r -p "Password copied to clipboard. Press any key..."
                fi
                ;;
            ctrl-v)
                if [ -n "$entry" ]; then
                    clear
                    pass show "$entry"
                    echo -e "\nPress any key to return..."
                    read -n 1 -s
                fi
                ;;
            ctrl-e)
                if [ -n "$entry" ]; then
                    pass edit "$entry"
                fi
                ;;
            ctrl-a)
                read -p "Enter new password path (e.g., Work/email): " new_entry
                if [ -n "$new_entry" ]; then
                    pass insert -m "$new_entry"
                fi
                ;;
            ctrl-g)
                read -p "Enter new password path (e.g., Work/email): " gen_entry
                if [ -n "$gen_entry" ]; then
                    read -p "Length [20]: " length
                    length=${length:-20}
                    pass generate -c "$gen_entry" "$length"
                    read -n 1 -s -r -p "Press any key to return..."
                fi
                ;;
            ctrl-d)
                if [ -n "$entry" ]; then
                    pass rm -i "$entry"
                fi
                ;;
	    ctrl-o)
                if [ -n "$entry" ]; then
                    if pass otp show "$entry" &>/dev/null; then
                        pass otp -c "$entry"
                        echo "OTP copied to clipboard."
                    else
                        echo "No OTP configuration found for $entry."
                        read -p "Do you want to add an OTP code? (y/n) " add_otp
                        if [[ "$add_otp" =~ ^[Yy]$ ]]; then
                            read -p "Paste OTP secret or full otpauth:// URI: " otp_input
                            
                            # Check if the user pasted a full URI or a raw secret
                            if [[ "$otp_input" == otpauth://* ]]; then
                                # It's a full URI, append it directly
                                pass otp append "$entry" <<< "$otp_input"
                            else
                                # It's a raw secret, use --secret and provide fallback issuer/account
                                pass otp append --secret --issuer "PassTUI" --account "$entry" "$entry" <<< "$otp_input"
                            fi
                        fi
                    fi
                    read -n 1 -s -r -p "Press any key to return..."
                fi
                ;;
	    ctrl-p)
                clear
                handle_git
                read -n 1 -s -r -p "Press any key to return..."
                ;;
            ctrl-q)
                if [ -n "$entry" ]; then
                    clear
                    pass show "$entry" | head -n 1 | qrencode -t UTF8
                    echo -e "\nPress any key to return..."
                    read -n 1 -s
                fi
                ;;
        esac
    done
}

# --- Entry Point ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

main
