#!/usr/bin/env bash

# Lenovo Conservation Mode Controller (Fuzzel & Wayland Optimized)

#SYS_PATH="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"
# Dynamically find the conservation_mode file
SYS_PATH=$(ls /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode 2>/dev/null | head -n 1)

if [ -z "$SYS_PATH" ] || [ ! -f "$SYS_PATH" ]; then
    notify-send -u critical "Battery Mode" "Conservation mode not supported or ideapad_acpi module missing."
    exit 1
fi

# -----------------------------
# Dependency Checks
# -----------------------------
for dep in fuzzel notify-send; do
    if ! command -v "$dep" &>/dev/null; then
        notify-send -u critical "Missing dependency: $dep" 2>/dev/null || echo "Missing: $dep"
        exit 1
    fi
done

# -----------------------------
# Helpers
# -----------------------------
get_status() {
    cat "$SYS_PATH" 2>/dev/null || echo "0"
}

set_mode() {
    local value=$1
    
    # Privilege Escalation Logic for Wayland/GUI shortcuts
    if [ -w "$SYS_PATH" ]; then
        # User already has write access (e.g., via udev rule)
        echo "$value" > "$SYS_PATH"
    elif command -v pkexec &>/dev/null; then
        # Standard GUI root prompt (Polkit)
        pkexec sh -c "echo $value > $SYS_PATH"
    elif command -v foot &>/dev/null; then
        # User's suggestion: Spawn a temporary foot terminal for sudo password
        foot -T "Battery Mode - Sudo Required" -e sudo sh -c "echo $value > $SYS_PATH"
    else
        # Last resort (will likely fail if not run from a terminal)
        echo "$value" | sudo tee "$SYS_PATH" >/dev/null
    fi

    # Verify if the change was successful
    if [ "$(get_status)" -eq "$value" ]; then
        if [ "$value" -eq 1 ]; then
            notify-send -i battery-good "Battery Mode" "Conservation Mode ENABLED (~60%)"
        else
            notify-send -i battery-full "Battery Mode" "Conservation Mode DISABLED (100%)"
        fi
    else
        notify-send -u critical "Battery Mode" "Failed to change mode. Cancelled or permission denied."
    fi
}

# -----------------------------
# Fuzzel GUI
# -----------------------------
current=$(get_status)

if [ "$current" -eq 1 ]; then
    prompt="🔋 Capped (60%) > "
else
    prompt="🔋 Full (100%) > "
fi

# Use fuzzel as a dmenu replacement
choice=$(printf "%s\n" "Toggle Mode" "Enable Conservation (~60%)" "Disable Conservation (100%)" | fuzzel --dmenu --prompt="$prompt" --lines 3)

case "$choice" in
    "Toggle Mode")
        if [ "$current" -eq 1 ]; then
            set_mode 0
        else
            set_mode 1
        fi
        ;;
    "Enable Conservation (~60%)") set_mode 1 ;;
    "Disable Conservation (100%)") set_mode 0 ;;
    *) exit 0 ;;
esac

