#!/usr/bin/env bash

# Path to your updated config
CONFIG_FILE="$HOME/.config/hypr/config/binds.lua"

if [[ ! -f "$CONFIG_FILE" ]]; then
    rofi -e "Config file not found at: $CONFIG_FILE"
    exit 1
fi

awk '
# Only process active lines that start with hl.bind
/^[ \t]*hl\.bind\(/ {
    
    # 1. Look specifically for our special delimiter "--|"
    comment_idx = index($0, "--|")
    
    # If the delimiter is NOT found, skip this line entirely
    if (comment_idx == 0) {
        next
    }
    
    # 2. Extract the human-readable comment
    comment = substr($0, comment_idx + 3)
    # Trim leading/trailing whitespace
    gsub(/^[ \t]+|[ \t]+$/, "", comment)
    
    # 3. Extract the Key
    start = index($0, "hl.bind(") + 8
    end = index($0, ",")
    
    if (start > 8 && end > start) {
        key = substr($0, start, end - start)
        
        # --- CLEAN UP THE KEY ---
        gsub(/mainMod \.\. "/, "SUPER", key)
        gsub(/"/, "", key)
        gsub(/[ \t]*\.\.[ \t]*key/, "1-9", key)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        gsub(/ \+ /, " + ", key)
        
        # Format the output for Rofi
        printf "<b>%-35s</b> <i>%s</i>\n", key, comment
    }
}' "$CONFIG_FILE" | rofi -dmenu -i -markup-rows -theme-str 'listview { fixed-height: false; padding: 0px; margin: 0px; }' -p  " ⌨️  Binds " 

