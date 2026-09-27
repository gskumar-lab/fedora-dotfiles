#!/usr/bin/env bash

# ==============================================================================
# Grim + Slurp Wrapper (Refactored & Hardened)
# ==============================================================================

# Safely determine the Pictures directory
if command -v xdg-user-dir &> /dev/null; then
    BASE_DIR="$(xdg-user-dir PICTURES)"
else
    BASE_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"
fi

SAVE_DIR="$BASE_DIR/Screenshots"
FILENAME="screenshot_$(date +'%Y-%m-%d_%H-%M-%S').png"
FILEPATH="$SAVE_DIR/$FILENAME"

# Default states
MODE="region"
ACTION="save"
DELAY=0
EDIT=0
QUIET=0

# Help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

A comprehensive wrapper for grim and slurp.

Options:
  -m <mode>     Set mode: 'region', 'full', or 'output' (select screen)
  -a <action>   Set action: 'save' (default), 'copy', or 'both'
  -d <secs>     Delay in seconds before taking the screenshot
  -e            Open screenshot in swappy for editing BEFORE saving/copying
  -q            Quiet mode (no notifications)
  -I            Check and install missing dependencies (Arch Linux only)
  -h            Show this help message

Examples:
  $(basename "$0") -I                       # Install dependencies on Arch Linux
  $(basename "$0") -m region -a both -e     # Select, edit, then save & copy
  $(basename "$0") -m full -d 3             # Take full screen after 3 seconds
EOF
}

# Arch Linux dependency installer
install_deps_arch() {
    local missing_pkgs=()

    # Map commands to their Arch package names
    command -v grim &>/dev/null || missing_pkgs+=("grim")
    command -v slurp &>/dev/null || missing_pkgs+=("slurp")
    command -v wl-copy &>/dev/null || missing_pkgs+=("wl-clipboard")
    command -v notify-send &>/dev/null || missing_pkgs+=("libnotify")
    command -v swappy &>/dev/null || missing_pkgs+=("swappy")

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        echo "✅ All dependencies are already installed!"
        exit 0
    fi

    echo "⚠️ Missing dependencies detected: ${missing_pkgs[*]}"
    read -r -p "Would you like to install them now using pacman? (y/N) " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed "${missing_pkgs[@]}"
        echo "✅ Installation complete."
        exit 0
    else
        echo "❌ Installation cancelled. Please install them manually."
        exit 1
    fi
}

# If no arguments are provided, show help and exit
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# Parse arguments
while getopts "m:a:d:eqIh" opt; do
    case $opt in
        m) MODE="$OPTARG" ;;
        a) ACTION="$OPTARG" ;;
        d) DELAY="$OPTARG" ;;
        e) EDIT=1 ;;
        q) QUIET=1 ;;
        I) install_deps_arch ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Standard Dependency Check
for cmd in grim slurp wl-copy notify-send; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed." >&2
        echo "💡 Tip: Run '$(basename "$0") -I' to automatically install missing packages on Arch Linux." >&2
        exit 1
    fi
done

# Ensure directory exists
mkdir -p "$SAVE_DIR"

# Handle Delay (Executes before slurp so dropdowns can be triggered)
if [ "$DELAY" -gt 0 ]; then
    [ "$QUIET" -eq 0 ] && notify-send -a "Screenshot" -t $((DELAY * 1000)) "Screenshot" "Taking in $DELAY seconds..."
    sleep "$DELAY"
fi

# Determine capture geometry based on mode
GEOMETRY=""
case "$MODE" in
    region)
        GEOMETRY=$(slurp) || exit 1 # Exit cleanly if user hits Esc
        ;;
    output)
        GEOMETRY=$(slurp -o) || exit 1
        ;;
    full)
        GEOMETRY=""
        ;;
    *)
        echo "Error: Unknown mode '$MODE'. Use region, full, or output." >&2
        exit 1
        ;;
esac

# 1. Execute Grim (Always save temporarily first)
if [ -n "$GEOMETRY" ]; then
    grim -g "$GEOMETRY" "$FILEPATH"
else
    grim "$FILEPATH"
fi

# 2. Handle Editing (Swappy) FIRST
if [ "$EDIT" -eq 1 ]; then
    if command -v swappy &> /dev/null; then
        # Open swappy and force it to overwrite the captured file when saved
        swappy -f "$FILEPATH" -o "$FILEPATH"
        MSG_EDIT="(Edited)"
    else
        MSG_EDIT="(Warning: swappy not installed, skipped edit)"
    fi
else
    MSG_EDIT=""
fi

# 3. Handle Actions (Copy/Save) ON THE FINAL FILE
case "$ACTION" in
    copy)
        wl-copy < "$FILEPATH"
        rm "$FILEPATH" # Clean up temporary file
        MSG="Copied to clipboard $MSG_EDIT"
        ;;
    both)
        wl-copy < "$FILEPATH"
        MSG="Saved and copied $MSG_EDIT"
        ;;
    save|*)
        MSG="Saved to $SAVE_DIR $MSG_EDIT"
        ;;
esac

# 4. Send Notification
if [ "$QUIET" -eq 0 ]; then
    if [ "$ACTION" = "copy" ]; then
        # No file exists anymore, standard notification
        notify-send -a "Screenshot" "Captured!" "$MSG" -t 3000
    else
        # File exists, use it as the notification thumbnail
        notify-send -a "Screenshot" -i "$FILEPATH" "Captured!" "$MSG" -t 3000
    fi
fi
