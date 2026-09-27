#!/usr/bin/env bash

# Lenovo Conservation Mode TUI Controller
# Works with ideapad_acpi

SYS_PATH="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"

# -----------------------------
# Dependency Checks
# -----------------------------
deps=("dialog" "notify-send")

missing=()

for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        missing+=("$dep")
    fi
done

if [ ${#missing[@]} -ne 0 ]; then
    echo "Missing dependencies: ${missing[*]}"
    echo "Install packages: dialog & libnotify"
    exit 1
fi

# -----------------------------
# Permission Check
# -----------------------------
if [ ! -w "$SYS_PATH" ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# -----------------------------
# Helpers
# -----------------------------
get_status() {
    cat "$SYS_PATH"
}

notify() {
    notify-send "Battery Mode" "$1"
}

set_mode() {
    local value=$1
    echo "$value" | $SUDO tee "$SYS_PATH" >/dev/null

    if [ "$value" -eq 1 ]; then
        notify "Conservation Mode ENABLED (Charge limit ~60%)"
    else
        notify "Conservation Mode DISABLED (Full charge)"
    fi
}

toggle_mode() {
    current=$(get_status)
    if [ "$current" -eq 1 ]; then
        set_mode 0
    else
        set_mode 1
    fi
}

# -----------------------------
# TUI Menu
# -----------------------------
while true; do
    current=$(get_status)

    if [ "$current" -eq 1 ]; then
        status="ENABLED (Capped ~60%)"
    else
        status="DISABLED (Full charge)"
    fi

    choice=$(dialog --clear \
        --title "Lenovo Battery Mode" \
        --menu "Current: $status" 15 50 6 \
        1 "Enable Conservation Mode" \
        2 "Disable Conservation Mode" \
        3 "Toggle Mode" \
        4 "Show Status" \
        5 "Exit" \
        3>&1 1>&2 2>&3)

    clear

    case $choice in
        1) set_mode 1 ;;
        2) set_mode 0 ;;
        3) toggle_mode ;;
        4)
            notify "$status"
            ;;
        5) break ;;
        *) break ;;
    esac
done
