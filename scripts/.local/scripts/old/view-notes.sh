#!/bin/bash

# ==========================================
# DEPENDENCY CHECKS
# ==========================================

check_dep() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "\033[1;31m✖ Error: Required dependency '$1' is not installed.\033[0m"
    echo "Please install '$1' to use this script."
    exit 1
  fi
}

# 1. Check for fzf
check_dep fzf

# 2. Check for file reversing tool
if command -v tac >/dev/null 2>&1; then
  REVERSE_CMD="tac"
elif tail -r /dev/null >/dev/null 2>&1; then
  REVERSE_CMD="tail -r"
else
  echo -e "\033[1;31m✖ Error: Neither 'tac' nor 'tail -r' found. Cannot reverse file order.\033[0m"
  exit 1
fi

# 3. Check for wl-copy specifically
if ! command -v wl-copy >/dev/null 2>&1; then
  echo -e "\033[1;33m⚠ Warning: 'wl-copy' not found.\033[0m"
  echo "Notes will be printed to the terminal instead of copied."
  sleep 2
fi

# ==========================================
# MAIN SCRIPT
# ==========================================

NOTES_FILE="$HOME/notes.txt"
EDITOR=${EDITOR:-nano}

if [ ! -f "$NOTES_FILE" ]; then
  echo "No notes file found at $NOTES_FILE"
  exit 1
fi

# Define the multi-line header properly as a standard variable
HEADER="╭────────────────────────────────────────────────────────╮
│ [ENTER] Copy | [CTRL-E] Edit | [CTRL-D] Delete | [ESC] │
╰────────────────────────────────────────────────────────╯"

# Pass options directly to fzf to avoid environment variable quoting issues
SELECTED=$(eval "$REVERSE_CMD \"$NOTES_FILE\"" | fzf \
  --layout=reverse \
  --border=rounded \
  --info=inline \
  --prompt="🔍 Search Notes ❯ " \
  --header="$HEADER" \
  --color=prompt:#5fff87,pointer:#ff5f87,header:#5fafd7 \
  --bind "ctrl-e:execute($EDITOR \"$NOTES_FILE\" >/dev/tty </dev/tty)" \
  --bind "ctrl-d:execute(bash -c 'read -p \"⚠ Delete this note? (y/N): \" ans </dev/tty; if [[ \$ans =~ ^[Yy]$ ]]; then grep -Fxv \"\$1\" \"$NOTES_FILE\" > \"$NOTES_FILE.tmp\"; mv \"$NOTES_FILE.tmp\" \"$NOTES_FILE\"; fi' _ {})+reload($REVERSE_CMD \"$NOTES_FILE\")")

if [ -n "$SELECTED" ]; then
  CLEAN_NOTE=$(echo "$SELECTED" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} - //')

  if command -v wl-copy >/dev/null 2>&1; then
    echo -n "$CLEAN_NOTE" | wl-copy
    echo -e "\033[1;32m✔ Copied to clipboard:\033[0m $CLEAN_NOTE"
  else
    echo -e "\033[1;36m❯ Selected:\033[0m $CLEAN_NOTE"
  fi
  read -p "Press [ENTER] to close..."
fi

