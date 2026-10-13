#!/bin/bash

NOTES_FILE="$HOME/notes.txt"

# 1. TRAP: Ensure terminal restores perfectly even if you press Ctrl+C
trap "tput rmcup; clear; exit 1" SIGINT SIGTERM

# Enter alternate screen buffer
tput smcup
clear

# Define colors for the UI
CYAN='\033[1;36m'
GREEN='\033[1;32m'
DIM='\033[2m'
NC='\033[0m' # No Color

echo -e "${CYAN}╭──────────────────────────────────────╮${NC}"
echo -e "${CYAN}│              QUICK NOTE              │${NC}"
echo -e "${CYAN}╰──────────────────────────────────────╯${NC}"
echo ""

# 2. CONTEXT: Show the last 3 notes so you know where you left off
if [ -f "$NOTES_FILE" ]; then
  echo -e "${DIM}Recent entries:${NC}"
  tail -n 3 "$NOTES_FILE" | sed 's/^/  /'
  echo ""
fi

# 3. INPUT: Read the note
read -e -p "❯ Type note: " NOTE

if [ -n "$NOTE" ]; then
  # Save to file
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $NOTE" >> "$NOTES_FILE"
  
  echo ""
  echo -e "${GREEN}✔ Saved successfully!${NC}"
  echo ""
else
  echo ""
  echo -e "${DIM}✖ Cancelled (empty note).${NC}"
  echo ""
fi

# 4. PAUSE: Wait for user
read -p "Press [ENTER] to close..."

# Restore terminal
tput rmcup
