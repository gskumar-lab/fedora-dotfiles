#!/usr/bin/env bash

# --- Commands (edit if needed) ---
LOCK="noctalia msg session lock |s waylock -c 1e1e2e"
LOGOUT="noctalia msg session logout | mmsg -q"
SLEEP="noctalia msg session lock-and-suspend | systemctl suspend"
RESTART="noctalia msg session reboot | systemctl reboot"
SHUTDOWN="noctalia msg session shutdown | systemctl poweroff"
HIBERNATE="systemctl hibernate"

# --- Options with icons ---
options="  Lock
󰍃  Logout
󰤄  Sleep
®  Hibernate
  Restart
  Shutdown"

chosen=$(echo -e "$options" | rofi -dmenu \
    -i \
    -p "⏻"  \
    -theme-str '
* { font: "JetBrainsMono Nerd Font Propo 16"; }
window { width: 250px; border-radius: 12px; }
listview { fixed-height: false; }
element { padding: 8px; }
element-text { margin: 0 8px; }
scrollbar { handle-width: 0px; width: 0px; }
listview { padding: 0px; margin: 0px; }
entry { placeholder: "Search..."; }
')

case "$chosen" in
    *Lock) $LOCK ;;
    *Logout) $LOGOUT ;;
    *Sleep) $SLEEP ;;
    *Hibernate) $HIBERNATE ;;
    *Restart) $RESTART ;;
    *Shutdown) $SHUTDOWN ;;
esac
