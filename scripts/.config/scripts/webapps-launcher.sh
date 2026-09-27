#!/bin/bash

list=~/.config/scripts/webapps.list

choice=$(cut -d'|' -f1 "$list" | rofi -dmenu -i -p "WebApps" \
-theme-str '
* { font: "JetBrainsMono Nerd Font 16"; }
window { width: 350px; border-radius: 12px; }
listview { fixed-height: false; padding: 0px; margin: 0px; }
element { padding: 8px; }
element-text { margin: 0 8px; }
scrollbar { handle-width: 0px; width: 0px; }
entry { placeholder: "..."; }
')

[ -z "$choice" ] && exit

# Extract URL and optional flag safely using awk to prevent regex injection and cleanly parse fields[cite: 1]
url=$(awk -F'|' -v c="$choice" '$1 == c {print $2}' "$list")
flag=$(awk -F'|' -v c="$choice" '$1 == c {print $3}' "$list")

# Launch Brave, handling the optional flag safely
if [ -n "$flag" ]; then
    brave-origin --app="$url" "$flag" &
else
    brave-origin --app="$url" &
fi

