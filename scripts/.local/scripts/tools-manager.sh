#!/usr/bin/env bash

# Configuration
CONFIG_FILE="$HOME/.config/gsk/tools-manager/tools.conf"
TERMINAL="foot" # e.g., alacritty, kitty, gnome-terminal

# Rofi appearance arguments
ROFI_ARGS=(
    -i 
    -theme-str 'window {width: 800px;} listview { fixed-height: false; padding: 0px; margin: 0px; } ' 
)

if ! command -v "$TERMINAL" &> /dev/null; then
    notify-send "Tools Manager" "Terminal '$TERMINAL' not found."
    exit 1
fi

# Ensure config file exists with the new 5-column format
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "\"System\"\t\"System Monitor\"\t\"View running processes\"\t\"htop\"\t\"tui\"" > "$CONFIG_FILE"
fi

# 1. Build Main Menu (Categories + All Tools)
# Extract categories ($2)
CATEGORIES=$(awk -F'"' 'NF>=10 {print "📁 " $2}' "$CONFIG_FILE" | sort -u)
# Extract all tools: "⚙️ Name - Description [Category]"
ALL_TOOLS=$(awk -F'"' 'NF>=10 {printf "⚙️ %s - %s [%s]\n", $4, $6, $2}' "$CONFIG_FILE" | sort)

# Wrap the menu in a loop to handle the "Back" behavior
while true; do

# 2. Show Main Menu
MAIN_CHOICE=$(echo -e "$CATEGORIES\n$ALL_TOOLS" | rofi -dmenu -p "Tools" "${ROFI_ARGS[@]}")

# Exit if nothing was selected
[[ -z "$MAIN_CHOICE" ]] && exit 0

# 3. Handle Selection (Category vs Tool)
if [[ "$MAIN_CHOICE" == 📁* ]]; then
    # It's a category: Extract name and show tools inside it
    CAT_NAME="${MAIN_CHOICE#📁 }"
    
    TOOL_CHOICE=$(awk -F'"' -v cat="$CAT_NAME" 'NF>=10 && $2==cat {printf "⚙️ %s - %s\n", $4, $6}' "$CONFIG_FILE" | sort | rofi -dmenu -p "$CAT_NAME" "${ROFI_ARGS[@]}")
    # If ESC is pressed in the category menu, go back to the start of the loop (Main Menu)
    [[ -z "$TOOL_CHOICE" ]] && continue

    # Strip the gear icon to get "Name - Description"
    SELECTED="${TOOL_CHOICE#⚙️ }"
    break # A tool was selected, break the loop to run it
else
    # It's a tool selected directly from the main menu
    # Strip the gear icon and the " [Category]" suffix to get "Name - Description"
    SELECTED=$(echo "$MAIN_CHOICE" | sed 's/^⚙️ //;s/ \[.*\]$//')
    break # A tool was selected, break the loop to run it
fi
done

# 4. Lookup the exact command ($8) and type ($10) by matching "Name - Description"
CMD_INFO=$(awk -F'"' -v sel="$SELECTED" 'NF>=10 && ($4 " - " $6)==sel {print $8 "|" $10; exit}' "$CONFIG_FILE")

CMD=$(echo "$CMD_INFO" | cut -d'|' -f1)
TYPE=$(echo "$CMD_INFO" | cut -d'|' -f2)

# 5. Launch the tool
if [[ -n "$CMD" ]]; then
    if [[ "$TYPE" == "gui" ]]; then
        eval "$CMD" > /dev/null 2>&1 & disown

	elif [[ "$TYPE" == "cli" ]]; then
    		eval "$TERMINAL -e --title tools-float  bash -c '$CMD; echo \"\"; read -n 1 -s -r -p \"Press any key to close...\"' &"
	elif [[ "$TYPE" == "tui" ]]; then
    		eval "$TERMINAL -e --title tools-float $CMD &"
    fi
fi
