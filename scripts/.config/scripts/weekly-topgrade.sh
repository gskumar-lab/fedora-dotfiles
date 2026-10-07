#!/bin/sh

action=$(
    notify-send \
        -a "System Updates" \
        -u normal \
        -t 60000 \
        -i system-software-update \
        -A "update=Update System" \
        -A "dismiss=Dismiss" \
        "System Update Available" \
        "Click an action below."
)

case "$action" in
    update)
        foot -e topgrade
        ;;
esac

