#!/usr/bin/env bash
# pass-tui: A feature-rich TUI wrapper for pass using fzf

set -uo pipefail
stty -ixon 2>/dev/null

# --- Configuration & Environment ---
PREFIX="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
SYNC_STATE_FILE="$PREFIX/.tui-autosync"
export GPG_TTY=$(tty) # Essential for GPG pinentry in TUI

# --- Dependency Management ---
check_dependencies() {
    local deps=("pass" "fzf" "fd" "rg" "qrencode" "gpg" "python3")
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

# --- Notifications ---
send_notification() {
    local title="$1"
    local message="$2"
    shift 2 # Remove title and message so only flags remain
    
    if command -v notify-send &> /dev/null; then
        notify-send -a "Pass-TUI" "$@" "$title" "$message"
    fi
}

# --- State Management ---
get_autosync_state() {
    if [ -f "$SYNC_STATE_FILE" ]; then
        cat "$SYNC_STATE_FILE"
    else
        echo "false"
    fi
}

set_autosync_state() {
    echo "$1" > "$SYNC_STATE_FILE"
}

# --- Git Handling (Backgrounded) ---
handle_git_bg() {
    local LOCK_FILE="$PREFIX/.sync.lock"

    if [ ! -d "$PREFIX/.git" ]; then
        return 0
    fi

    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$LOCK_FILE"
    fi

    (
        trap '' HUP
        trap 'rm -f "$LOCK_FILE"' EXIT
        echo "${BASHPID:-$$}" > "$LOCK_FILE"
        cd "$PREFIX" || exit

        if git remote | grep -q '.'; then
            local current_branch
            current_branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)
            [[ -z "$current_branch" || "$current_branch" == "HEAD" ]] && current_branch="main"

            if git pull --rebase origin "$current_branch" >/dev/null 2>&1 && \
               git push -u origin "$current_branch" >/dev/null 2>&1; then
                send_notification "Pass-TUI Git" "Sync completed successfully." -e -t 1000 -i freefilesync
            else
                send_notification "Pass-TUI Git Error" "Sync failed! Check network or conflicts." -t 0 -i realtimesync
            fi
        else
            send_notification "Pass-TUI Git Error" "No Git remote configured." -u critical -i gtk-dialog-error
        fi
    ) </dev/null >/dev/null 2>&1 &

    disown -h $! 2>/dev/null || disown
}

# --- Core Functions ---
get_passwords() {
    if [ -d "$PREFIX" ]; then
        cd "$PREFIX" && fd -t f -e gpg . | sed 's/\.gpg$//' | sed 's/^\.\///'
    fi
}

# --- Bitwarden Importer Engine ---
import_bitwarden() {
    local json_file="${1:-}"

    if [ -z "$json_file" ]; then
        clear
        echo -e "\e[1;34m=== Bitwarden JSON Importer ===\e[0m\n"
        read -e -p "Enter path to Bitwarden JSON file: " json_file
    fi

    # Expand tilde if present
    json_file="${json_file/#\~/$HOME}"

    if [ ! -f "$json_file" ]; then
        echo -e "\e[31mError: File '$json_file' does not exist.\e[0m"
        read -n 1 -s -r -p "Press any key to return..."
        return 1
    fi

    python3 - "$json_file" "$PREFIX" << 'EOF'
import sys, json, os, subprocess

export_path = sys.argv[1]
prefix = sys.argv[2]

try:
    with open(export_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f"\033[31mFailed to read JSON: {e}\033[0m")
    sys.exit(1)

def sanitize(name):
    return str(name).replace('/', '-').strip() if name else "unnamed"

folders = {f['id']: sanitize(f.get('name')) for f in data.get('folders', []) if 'id' in f}
items = data.get('items', [])
imported, skipped = 0, 0

env = os.environ.copy()
env["PASSWORD_STORE_GIT"] = "0"  # Batch mode: suppress per-item Git commits

print(f"\033[1;32mStarting import of {len(items)} items...\033[0m\n")

for item in items:
    if item.get('type') != 1:  # Only process login credentials
        skipped += 1
        continue

    name = sanitize(item.get('name'))
    f_id = item.get('folderId')
    pass_path = f"{folders[f_id]}/{name}" if (f_id and f_id in folders) else name

    login = item.get('login') or {}
    lines = [login.get('password') or ""]

    if login.get('username'):
        lines.append(f"Username: {login['username']}")
    for uri in login.get('uris', []):
        if uri.get('uri'):
            lines.append(f"URL: {uri['uri']}")
    if login.get('totp'):
        lines.append(f"totp: {login['totp']}")
    for fld in item.get('fields', []):
        if fld.get('name') and fld.get('value') is not None:
            lines.append(f"{fld['name']}: {fld['value']}")
    if item.get('notes'):
        lines.append(f"Notes:\n{item['notes']}")

    payload = "\n".join(lines) + "\n"
    res = subprocess.run(["pass", "insert", "-m", "-f", pass_path], input=payload, text=True, capture_output=True, env=env)
    if res.returncode == 0:
        imported += 1
        print(f"  ✓ {pass_path}")
    else:
        print(f"  ✗ {pass_path}: {res.stderr.strip()}")

# Batch Git commit
if os.path.isdir(os.path.join(prefix, ".git")) and imported > 0:
    print("\n\033[1;34mCreating single Git commit for imported items...\033[0m")
    subprocess.run(["git", "-C", prefix, "add", "-A"], check=False)
    subprocess.run(["git", "-C", prefix, "commit", "-m", f"Import {imported} items from Bitwarden"], check=False)

print(f"\n\033[1;32mImport completed: {imported} imported, {skipped} skipped.\033[0m")
EOF

    read -n 1 -s -r -p "Press any key to return..."
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
  Ctrl-I    : Import credentials from Bitwarden JSON export
  Ctrl-S    : Search inside password files (Content search via rg/pass grep)
  Ctrl-/    : Toggle Preview Window
  Ctrl-P    : Manual Git Sync (Background Pull/Push)
  Ctrl-T    : Toggle Auto Git Sync (Triggers push/pull in background on exit)
  Ctrl-H    : Show this help text

CLI Usage:
  $(basename "$0")                      Launch TUI
  $(basename "$0") import-bw <file>     Import Bitwarden JSON directly
"
}

# --- Main TUI ---
main() {
    check_dependencies
    init_checks

    local AUTO_SYNC
    AUTO_SYNC=$(get_autosync_state)
    
    while true; do
        local sync_status
        if [ "$AUTO_SYNC" = "true" ]; then
            sync_status="ON"
        else
            sync_status="OFF"
        fi

        local header="  [Enter] Copy      [^V] View         [^E] Edit         [^A] Add
  [^G] Gen          [^D] Del          [^O] OTP          [^Q] QR
  [^S] Search       [^I] Import BW    [^/] Preview      [^P] Git Sync
  
  [^T] Auto Sync on Exit: [$sync_status]                [^H] Help"
        
        local selected
        selected=$(get_passwords | fzf \
            --prompt="🔑 Pass > " \
            --header="$header" \
            --preview='pass show {}' \
            --preview-window="right:50%:wrap:hidden" \
            --bind="ctrl-/:toggle-preview" \
            --bind="ctrl-h:execute(echo -e \"$(show_help)\" | less)" \
            --bind="ctrl-s:execute(if [ -n {q} ]; then pass grep {q} | less -R; else echo 'Type a query before pressing Ctrl-S' | less; fi)" \
            --expect=ctrl-v,ctrl-e,ctrl-a,ctrl-g,ctrl-d,ctrl-o,ctrl-q,ctrl-p,ctrl-t,ctrl-i,enter \
            --height=100% --layout=reverse)

        local exit_code=$?
        local key=$(head -n 1 <<< "$selected")
        local entry=$(tail -n +2 <<< "$selected")

        # Handle Esc / Ctrl-C (clean exit)
        if [ $exit_code -ne 0 ] && [ -z "$key" ]; then
            if [ "$AUTO_SYNC" = "true" ]; then
                handle_git_bg
            fi
            clear
            exit 0
        fi

        # Handle Actions
        case "$key" in
            enter)
                if [ -n "$entry" ]; then
                    pass -c "$entry"
                    send_notification "Pass-TUI" "Password copied to clipboard." -t 3000
                fi
                ;;
            ctrl-v)
                clear
                if [ -n "$entry" ]; then
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
                clear
                read -p "Enter new password path (e.g., Work/email): " new_entry
                if [ -n "$new_entry" ]; then
                    pass insert -m "$new_entry"
                fi
                ;;
            ctrl-g)
                clear
                read -p "Enter new password path (e.g., Work/email): " gen_entry
                if [ -n "$gen_entry" ]; then
                    read -p "Length [20]: " length
                    length=${length:-20}
                    pass generate -c "$gen_entry" "$length"
                    read -n 1 -s -r -p "Press any key to return..."
                fi
                ;;
            ctrl-d)
                clear
                if [ -n "$entry" ]; then
                    pass rm "$entry"
                fi
                ;;
            ctrl-o)
                clear
                if [ -n "$entry" ]; then
                    if pass otp show "$entry" &>/dev/null; then
                        pass otp -c "$entry"
                        send_notification "Pass-TUI" "OTP copied to clipboard." -t 3000
                    else
                        echo "No OTP configuration found for $entry."
                        read -p "Do you want to add an OTP code? (y/n) " add_otp
                        if [[ "$add_otp" =~ ^[Yy]$ ]]; then
                            read -p "Paste OTP secret or full otpauth:// URI: " otp_input
                            if [[ "$otp_input" == otpauth://* ]]; then
                                pass otp append "$entry" <<< "$otp_input"
                            else
                                pass otp append --secret --issuer "PassTUI" --account "$entry" "$entry" <<< "$otp_input"
                            fi
                        fi
                        read -n 1 -s -r -p "Press any key to return..."
                    fi
                fi
                ;;
            ctrl-i)
                import_bitwarden
                ;;
            ctrl-p)
                handle_git_bg
                ;;
            ctrl-t)
                if [ "$AUTO_SYNC" = "true" ]; then
                    AUTO_SYNC="false"
                else
                    AUTO_SYNC="true"
                fi
                set_autosync_state "$AUTO_SYNC"
                send_notification "Pass-TUI" "Auto-Sync toggled $([ "$AUTO_SYNC" = "true" ] && echo "ON" || echo "OFF")" -t 2000
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

if [[ "${1:-}" == "import-bw" ]]; then
    check_dependencies
    init_checks
    import_bitwarden "${2:-}"
    exit 0
fi

main

