#!/usr/bin/env bash

# Path to your updated config
CONFIG_FILE="$HOME/.config/hypr/config/binds.lua"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found at: $CONFIG_FILE" | fuzzel --dmenu --prompt="Error: "
    exit 1
fi

# 1. Store the processed output in a variable first
OUTPUT=$(awk '
# Only process active lines that start with hl.bind
/^[ \t]*hl\.bind\(/ {
    
    # Look specifically for our special delimiter "--|"
    comment_idx = index($0, "--|")
    
    if (comment_idx == 0) {
        next
    }
    
    # Extract the human-readable comment
    comment = substr($0, comment_idx + 3)
    gsub(/^[ \t]+|[ \t]+$/, "", comment)
    
    # Extract the Key
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
        
        # Format the output (clean text for Fuzzel)
        printf "%-35s - %s\n", key, comment
    }
}' "$CONFIG_FILE")

# 2. Calculate the length of the longest line
# Adding a little extra padding (+2) to ensure it fits perfectly without touching the edges
MAX_WIDTH=$(echo "$OUTPUT" | wc -L)
CALC_WIDTH=$((MAX_WIDTH + 2))

# 3. Pass the calculated width to fuzzel
echo "$OUTPUT" | fuzzel --dmenu --width="$CALC_WIDTH" --prompt=" ⌨️ Binds: "

