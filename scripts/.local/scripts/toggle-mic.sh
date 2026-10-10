#!/bin/bash

# ==============================================================================
# toggle-mic.sh
# Toggle script for Microphone, EasyEffects, and Handy
# ==============================================================================

show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS]

Options:
  -m,  --mic          Toggle Microphone only
  -e,  --ee           Toggle EasyEffects only
  -n,  --handy        Toggle Handy only
  -me, --mic-ee       Toggle Microphone + EasyEffects
  -mh, --mic-handy    Toggle Microphone + Handy
  -a,  --all          Toggle Microphone + EasyEffects + Handy
  -h,  --help         Display this help message and exit
EOF
}

DO_MIC=false
DO_EE=false
DO_HANDY=false

if [[ $# -eq 0 ]]; then
    DO_MIC=true
    DO_EE=true
    DO_HANDY=true
else
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -m|--mic)       DO_MIC=true ;;
            -e|--ee)        DO_EE=true ;;
            -n|--handy)     DO_HANDY=true ;;
            -me|--mic-ee)   DO_MIC=true; DO_EE=true ;;
            -mh|--mic-handy)DO_MIC=true; DO_HANDY=true ;;
            -a|--all)       DO_MIC=true; DO_EE=true; DO_HANDY=true ;;
            -h|--help)      show_help; exit 0 ;;
            *)              echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done
fi

# ==============================================================================
# Notification Helper Functions
# ==============================================================================
NOTIF_BODY=""

append_notif() {
    # If the body is empty, set it. Otherwise, append with a newline.
    if [[ -z "$NOTIF_BODY" ]]; then
        NOTIF_BODY="$1"
    else
        NOTIF_BODY="${NOTIF_BODY}\n$1"
    fi
}

send_notification() {
    # Send a single notification if the body has content
    if [[ -n "$NOTIF_BODY" ]]; then
        notify-send -u low -a "Audio Toggle" "Audio Status" "$NOTIF_BODY"
    fi
}

# ==============================================================================
# Global Target State
# ==============================================================================
STATE=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)
if [[ "$STATE" == *"[MUTED]"* ]]; then
    MIC_TARGET="ON"
else
    MIC_TARGET="OFF"
fi

# ==============================================================================
# 1. Microphone Actions
# ==============================================================================
if [[ "$DO_MIC" == true ]]; then
    if [[ "$MIC_TARGET" == "ON" ]]; then
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
        append_notif "🎙️ Mic: ON"
    else
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1
        append_notif "🔇 Mic: MUTED"
    fi
fi

# ==============================================================================
# 2. EasyEffects Actions
# ==============================================================================
if [[ "$DO_EE" == true ]]; then
    if [[ "$DO_MIC" == true ]]; then
        EE_TARGET=$MIC_TARGET
    else
        if pgrep -x "easyeffects" > /dev/null; then EE_TARGET="OFF"; else EE_TARGET="ON"; fi
    fi

    if [[ "$EE_TARGET" == "ON" ]]; then
        if ! pgrep -x "easyeffects" > /dev/null; then
            nohup easyeffects --gapplication-service > /dev/null 2>&1 &
            append_notif "🎛️ EasyEffects: Started"
        fi
    else
        if pgrep -x "easyeffects" > /dev/null; then
            easyeffects --quit
            append_notif "🎛️ EasyEffects: Stopped"
        fi
    fi
fi

# ==============================================================================
# 3. Handy Actions
# ==============================================================================
if [[ "$DO_HANDY" == true ]]; then
    if [[ "$DO_MIC" == true ]]; then
        HANDY_TARGET=$MIC_TARGET
    else
        if pgrep -f "handy" > /dev/null; then HANDY_TARGET="OFF"; else HANDY_TARGET="ON"; fi
    fi

    if [[ "$HANDY_TARGET" == "ON" ]]; then
        if ! pgrep -f "handy" > /dev/null; then
            nohup handy --start-hidden > /dev/null 2>&1 &
            append_notif "📝 Handy: Started"
        fi
    else
        if pgrep -f "handy" > /dev/null; then
            pkill -f "handy"
            append_notif "📝 Handy: Stopped"
        fi
    fi
fi

# ==============================================================================
# Dispatch Notification
# ==============================================================================
send_notification

