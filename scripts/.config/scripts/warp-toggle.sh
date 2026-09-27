#!/bin/bash

SERVICE="warp-svc.service"

if systemctl is-active --quiet "$SERVICE"; then
    # WARP is ON → disconnect and stop service
    warp-cli disconnect
    systemctl stop "$SERVICE"

    notify-send "Cloudflare WARP" "Disconnected 🔴"
else
    # WARP is OFF → start service and connect
    systemctl start "$SERVICE"

    # Give warp-svc time to initialize
    sleep 1

    warp-cli connect

    notify-send "Cloudflare WARP" "Connected 🟢"
fi
