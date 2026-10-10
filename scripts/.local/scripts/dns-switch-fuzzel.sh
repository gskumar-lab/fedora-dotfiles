#!/usr/bin/env bash
set -euo pipefail

# --- Dependency Checks ---
REQUIRED_DEPS=("fuzzel" "nmcli" "notify-send")
MISSING_DEPS=()

for cmd in "${REQUIRED_DEPS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    err_msg="Missing required dependencies: ${MISSING_DEPS[*]}"
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "DNS Switcher Error" "$err_msg"
    else
        echo "$err_msg" >&2
    fi
    exit 1
fi

notify() {
    local urgency="$1"
    local summary="$2"
    local body="$3"
    notify-send -u "$urgency" -a "DNS Switcher" "$summary" "$body"
}

# --- Detect Active Connection ---
ACTIVE_CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep -E ':(802-11-wireless|802-3-ethernet|wifi|ethernet)$' | head -n1 | cut -d: -f1)

if [[ -z "$ACTIVE_CONN" ]]; then
    ACTIVE_CONN=$(nmcli -t -f NAME connection show --active | head -n1)
fi

if [[ -z "$ACTIVE_CONN" ]]; then
    notify "critical" "DNS Switcher" "No active network connection found."
    exit 1
fi

# Check if IPv6 is enabled on this connection to prevent 'method=ignore' errors
IPV6_METHOD=$(nmcli -g ipv6.method connection show "$ACTIVE_CONN")
IPV6_ENABLED=1
if [[ "$IPV6_METHOD" == "ignore" ]] || [[ "$IPV6_METHOD" == "disabled" ]]; then
    IPV6_ENABLED=0
fi

# --- DNS Profiles ---
declare -A DNS_V4=(
    ["Cloudflare (1.1.1.1)"]="1.1.1.1 1.0.0.1"
    ["Cloudflare Security (Malware Blocking)"]="1.1.1.2 1.0.0.2"
    ["Cloudflare Family (Malware + Adult)"]="1.1.1.3 1.0.0.3"
    ["Google (8.8.8.8)"]="8.8.8.8 8.8.4.4"
    ["Quad9 (Filtered + DNSSEC)"]="9.9.9.9 149.112.112.112"
    ["Quad9 (Uncensored)"]="9.9.9.10 149.112.112.10"
    ["AdGuard Default"]="94.140.14.14 94.140.15.15"
    ["OpenDNS Home"]="208.67.222.222 208.67.220.220"
    ["Reset to Automatic (DHCP)"]="DHCP"
)

declare -A DNS_V6=(
    ["Cloudflare (1.1.1.1)"]="2606:4700:4700::1111 2606:4700:4700::1001"
    ["Cloudflare Security (Malware Blocking)"]="2606:4700:4700::1112 2606:4700:4700::1002"
    ["Cloudflare Family (Malware + Adult)"]="2606:4700:4700::1113 2606:4700:4700::1003"
    ["Google (8.8.8.8)"]="2001:4860:4860::8888 2001:4860:4860::8844"
    ["Quad9 (Filtered + DNSSEC)"]="2620:fe::fe 2620:fe::9"
    ["Quad9 (Uncensored)"]="2620:fe::10 2620:fe::fe:10"
    ["AdGuard Default"]="2a10:50c0::ad1:ff 2a10:50c0::ad2:ff"
    ["OpenDNS Home"]="2620:119:35::35 2620:119:53::53"
)

# --- Selection Menu via Fuzzel ---
MENU_OPTIONS=$(printf "%s\n" \
    "Cloudflare (1.1.1.1)" \
    "Cloudflare Security (Malware Blocking)" \
    "Cloudflare Family (Malware + Adult)" \
    "Google (8.8.8.8)" \
    "Quad9 (Filtered + DNSSEC)" \
    "Quad9 (Uncensored)" \
    "AdGuard Default" \
    "OpenDNS Home" \
    "Reset to Automatic (DHCP)"
)

# Get currently configured DNS servers for the active connection (Option 1 logic)
CURRENT_DNS=$(nmcli -g IP4.DNS connection show "$ACTIVE_CONN" 2>/dev/null | tr '\n' ' ' | xargs)
if [[ -z "$CURRENT_DNS" ]]; then
    CURRENT_DNS="DHCP / Auto"
fi

# Show current DNS directly inside the Fuzzel prompt title
CHOICE=$(printf "%s" "$MENU_OPTIONS" | fuzzel -d -p "DNS [$CURRENT_DNS] > " --lines 10 --width 40)

[[ -z "$CHOICE" ]] && exit 0

# --- Apply Configuration ---
apply_changes() {
    if ! nmcli device reapply "$ACTIVE_CONN" &>/dev/null; then
        nmcli connection up "$ACTIVE_CONN" &>/dev/null
    fi
}

if [[ "$CHOICE" == "Reset to Automatic (DHCP)" ]]; then
    RESET_ARGS=(connection modify "$ACTIVE_CONN" ipv4.ignore-auto-dns no ipv4.dns "")
    
    if [[ $IPV6_ENABLED -eq 1 ]]; then
        RESET_ARGS+=(ipv6.ignore-auto-dns no ipv6.dns "")
    fi

    if nmcli "${RESET_ARGS[@]}"; then
        apply_changes
        notify "low" "DNS Reset" "Restored automatic DHCP DNS on '$ACTIVE_CONN'."
    else
        notify "critical" "DNS Switcher" "Failed to restore DHCP DNS."
        exit 1
    fi
else
    SELECTED_V4="${DNS_V4[$CHOICE]}"
    SELECTED_V6="${DNS_V6[$CHOICE]:-}"

    MOD_ARGS=(
        connection modify "$ACTIVE_CONN"
        ipv4.ignore-auto-dns yes
        ipv4.dns "$SELECTED_V4"
    )

    if [[ -n "$SELECTED_V6" ]] && [[ $IPV6_ENABLED -eq 1 ]]; then
        MOD_ARGS+=(ipv6.ignore-auto-dns yes ipv6.dns "$SELECTED_V6")
    fi

    if nmcli "${MOD_ARGS[@]}"; then
        apply_changes
        notify "low" "DNS Updated" "Switched '$ACTIVE_CONN' to $CHOICE\n($SELECTED_V4)"
    else
        notify "critical" "DNS Switcher" "Failed to update DNS settings."
        exit 1
    fi
fi

