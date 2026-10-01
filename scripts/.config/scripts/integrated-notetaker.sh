#!/usr/bin/env bash
# TUI Note App: New, Read, Search, Tags, Delete, Quick Notes, Help

# ==========================================
# CONFIGURATION
# ==========================================
NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"
QUICK_NOTES_FILE="$HOME/notes.txt"
EDITOR="${EDITOR:-vim}"
EXT=".md"

# ==========================================
# QUICK NOTES INTEGRATION
# ==========================================
cmd_quicknote() {
  # TRAP: Ensure terminal restores perfectly and returns to menu (or exits if standalone)
  trap "tput rmcup; clear; return 1 2>/dev/null || exit 1" SIGINT SIGTERM

  tput smcup
  clear

  local CYAN='\033[1;36m'
  local GREEN='\033[1;32m'
  local DIM='\033[2m'
  local NC='\033[0m'

  echo -e "${CYAN}╭────────────────────────────────────────────╮${NC}"
  echo -e "${CYAN}│                 QUICK NOTE                 │${NC}"
  echo -e "${CYAN}│       [ENTER] Save | [CTRL-C] Cancel       │${NC}"
  echo -e "${CYAN}╰────────────────────────────────────────────╯${NC}"
  echo ""

  if [ -f "$QUICK_NOTES_FILE" ]; then
    echo -e "${DIM}Recent entries:${NC}"
    tail -n 3 "$QUICK_NOTES_FILE" | sed 's/^/  /'
    echo ""
  fi

  # Using standard read to better handle trap interrupts
  read -e -p "❯ Type note: " NOTE

  # Check if NOTE has content. (If Ctrl-C is pressed during read, the trap fires first).
  if [ -n "$NOTE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $NOTE" >>"$QUICK_NOTES_FILE"
    echo -e "\n${GREEN}✔ Saved successfully!${NC}\n"
  else
    echo -e "\n${DIM}✖ Cancelled (empty note).${NC}\n"
  fi

  read -p "Press [ENTER] to continue..."
  tput rmcup
  trap - SIGINT SIGTERM
}

cmd_view_quicknotes() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo -e "\033[1;31m✖ Error: fzf is required.\033[0m"
    exit 1
  fi

  if [ ! -f "$QUICK_NOTES_FILE" ]; then
    echo "No notes file found at $QUICK_NOTES_FILE"
    sleep 2
    return
  fi

  local REVERSE_CMD
  if command -v tac >/dev/null 2>&1; then
    REVERSE_CMD="tac"
  elif tail -r /dev/null >/dev/null 2>&1; then
    REVERSE_CMD="tail -r"
  else
    echo -e "\033[1;31m✖ Error: Neither 'tac' nor 'tail -r' found. Cannot reverse file order.\033[0m"
    sleep 2
    return
  fi

  local HEADER="╭────────────────────────────────────────────────────────╮
│ [ENTER] Copy | [CTRL-E] Edit | [CTRL-D] Delete | [ESC] │
╰────────────────────────────────────────────────────────╯"

  local SELECTED
  SELECTED=$(eval "$REVERSE_CMD \"$QUICK_NOTES_FILE\"" | fzf \
    --layout=reverse \
    --border=rounded \
    --info=inline \
    --prompt="🔍 Search Quick Notes ❯ " \
    --header="$HEADER" \
    --color=prompt:#5fff87,pointer:#ff5f87,header:#5fafd7 \
    --bind "ctrl-e:execute($EDITOR \"$QUICK_NOTES_FILE\" >/dev/tty </dev/tty)" \
    --bind "ctrl-d:execute(bash -c 'read -p \"⚠ Delete this note? (y/N): \" ans </dev/tty; if [[ \$ans =~ ^[Yy]$ ]]; then grep -Fxv \"\$1\" \"$QUICK_NOTES_FILE\" > \"$QUICK_NOTES_FILE.tmp\"; mv \"$QUICK_NOTES_FILE.tmp\" \"$QUICK_NOTES_FILE\"; fi' _ {})+reload($REVERSE_CMD \"$QUICK_NOTES_FILE\")")

  if [ -n "$SELECTED" ]; then
    local CLEAN_NOTE
    CLEAN_NOTE=$(echo "$SELECTED" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} - //')

    clear
    if command -v wl-copy >/dev/null 2>&1; then
      echo -n "$CLEAN_NOTE" | wl-copy
      echo -e "\033[1;32m✔ Copied (Wayland):\033[0m $CLEAN_NOTE"
    elif command -v xclip >/dev/null 2>&1; then
      echo -n "$CLEAN_NOTE" | xclip -selection clipboard
      echo -e "\033[1;32m✔ Copied (X11):\033[0m $CLEAN_NOTE"
    else
      echo -e "\033[1;33m⚠ 'wl-copy' or 'xclip' not found. Printed to terminal instead.\033[0m"
      echo -e "\033[1;36m❯ Selected:\033[0m $CLEAN_NOTE"
    fi

    read -p "Press [ENTER] to continue..."
  fi
}

# ==========================================
# HELP & REFERENCE SYSTEM
# ==========================================
cmd_help() {
  clear
  local CYAN='\033[1;36m'
  local GREEN='\033[1;32m'
  local YELLOW='\033[1;33m'
  local BOLD='\033[1m'
  local NC='\033[0m'

  echo -e "${CYAN}======================================================${NC}"
  echo -e "${BOLD}              TUI NOTE APP - REFERENCE                ${NC}"
  echo -e "${CYAN}======================================================${NC}"

  echo -e "\n${YELLOW}📁 DIRECTORIES & FILES:${NC}"
  echo -e "  • ${BOLD}Main Vault:${NC}   $NOTES_DIR"
  echo -e "  • ${BOLD}Quick Notes:${NC}  $QUICK_NOTES_FILE"
  echo -e "  • ${BOLD}Extension:${NC}    $EXT files"

  echo -e "\n${YELLOW}🛠️  COMMAND LINE FLAGS (BINDS):${NC}"
  echo -e "  • ${BOLD}-q, --quicknote${NC}        Launch directly into Quick Note input."
  echo -e "  • ${BOLD}-v, --view-quicknotes${NC}  Launch directly into Quick Note search/copy."
  echo -e "  • ${BOLD}-h, --help${NC}             Show this help screen."

  echo -e "\n${YELLOW}✨ MENU FUNCTIONALITIES:${NC}"
  echo -e "  • ${BOLD}New Note:${NC}      Creates a markdown file and auto-populates date/tags header."
  echo -e "  • ${BOLD}Read Note:${NC}     Lists all vault files. Previews with Glow/Bat. [CTRL-E] to edit."
  echo -e "  • ${BOLD}Search Notes:${NC}  Full-text search across vault via ripgrep. Jumps to exact line."
  echo -e "  • ${BOLD}Browse by Tag:${NC} Extracts all #tags, lists them by frequency, then filters files."
  echo -e "  • ${BOLD}Quick Note:${NC}    Appends single-line timestamped notes to $QUICK_NOTES_FILE."
  echo -e "  • ${BOLD}View Quick:${NC}    Search quick notes. [ENTER] copies to clipboard (wl-copy)."
  echo -e "                   [CTRL-E] edits file. [CTRL-D] deletes selected quick note."
  echo -e "  • ${BOLD}Delete Note:${NC}   Multi-select markdown files via [TAB] to delete."

  echo -e "\n${CYAN}======================================================${NC}\n"
  read -p "Press [ENTER] to return..."
}

# ==========================================
# PRE-FLIGHT & COMMAND LINE FLAGS
# ==========================================
case "$1" in
-q | --quicknote)
  cmd_quicknote
  exit 0
  ;;
-v | --view-quicknotes)
  cmd_view_quicknotes
  exit 0
  ;;
-h | --help)
  cmd_help
  exit 0
  ;;
esac

# ==========================================
# MAIN VAULT PREVIEW LOGIC
# ==========================================
export FZF_PREVIEW_OPTS='
    file={1}
    line={2}
    
    if [ ! -f "$file" ]; then
        echo "Error: Cannot read file -> $file"
        exit 1
    fi
    
    if [ -n "$line" ]; then
        cmd="cat"
        if command -v bat >/dev/null 2>&1; then 
            cmd="bat --color=always --style=plain"
        elif command -v batcat >/dev/null 2>&1; then 
            cmd="batcat --color=always --style=plain"
        fi
        eval "$cmd \"\$file\"" 2>/dev/null | tail -n +"$line" | head -n 30
    else
        if command -v glow >/dev/null 2>&1; then
            glow -s dark "$file" 2>/dev/null
        else
            cmd="cat"
            if command -v bat >/dev/null 2>&1; then 
                cmd="bat --color=always --style=plain"
            elif command -v batcat >/dev/null 2>&1; then 
                cmd="batcat --color=always --style=plain"
            fi
            eval "$cmd \"\$file\"" 2>/dev/null | head -n 30
        fi
    fi
'

# ==========================================
# MAIN VAULT HELPER FUNCTIONS
# ==========================================
slugify() {
  echo "$1" | iconv -t ascii//TRANSLIT | sed -E -e 's/[^[:alnum:]]+/-/g' -e 's/^-+|-+$//g' | tr '[:upper:]' '[:lower:]'
}

cmd_new() {
  clear
  read -r -e -p "Note Title: " title
  [[ -z "$title" ]] && return

  local file="$(slugify "$title")$EXT"

  if [[ ! -f "$file" ]]; then
    echo "# $title" >"$file"
    echo -e "\nTags: \nDate: $(date +%Y-%m-%d)\n" >>"$file"
  fi
  $EDITOR "$file"
}

cmd_read() {
  local result key file
  result=$(find . -type f -name "*$EXT" 2>/dev/null | sed 's|^\./||' | sort -r |
    fzf --prompt="📖 Read (Enter: Read, Ctrl-E: Edit)> " \
      --expect=ctrl-e \
      --border=rounded \
      --preview "$FZF_PREVIEW_OPTS" \
      --preview-window="right:60%:wrap")

  [[ -z "$result" ]] && return

  key=$(echo "$result" | head -n 1)
  file=$(echo "$result" | tail -n +2)

  [[ -z "$file" ]] && return

  if [[ "$key" == "ctrl-e" ]]; then
    $EDITOR "$file"
  else
    if command -v glow >/dev/null 2>&1; then
      glow -p "$file"
    elif command -v bat >/dev/null 2>&1; then
      bat --paging=always "$file"
    elif command -v batcat >/dev/null 2>&1; then
      batcat --paging=always "$file"
    else
      less "$file"
    fi
  fi
}

cmd_search() {
  local selected
  selected=$(rg --color=never -n "^" . 2>/dev/null |
    fzf --prompt="🔍 Search> " \
      --border=rounded \
      --delimiter : \
      --preview "$FZF_PREVIEW_OPTS" \
      --preview-window "right:60%:wrap")

  if [[ -n "$selected" ]]; then
    local file line
    file=$(echo "$selected" | awk -F: '{print $1}')
    line=$(echo "$selected" | awk -F: '{print $2}')
    $EDITOR "+$line" "$file"
  fi
}

cmd_tags() {
  local tag
  tag=$(rg -o '#[a-zA-Z0-9_-]+' . 2>/dev/null |
    awk -F: '{print $2}' | sort | uniq -c | sort -nr |
    fzf --prompt="🏷️  Select Tag> " --border=rounded | awk '{print $2}')

  if [[ -n "$tag" ]]; then
    local file
    file=$(rg -l "$tag" . 2>/dev/null | sed 's|^\./||' |
      fzf --prompt="Notes with $tag> " \
        --border=rounded \
        --preview "$FZF_PREVIEW_OPTS")

    [[ -n "$file" ]] && $EDITOR "$file"
  fi
}

cmd_delete() {
  local files
  files=$(find . -type f -name "*$EXT" 2>/dev/null | sed 's|^\./||' | sort -r |
    fzf -m \
      --prompt="🗑️  Delete (Tab to multi-select)> " \
      --border=rounded \
      --preview "$FZF_PREVIEW_OPTS" \
      --preview-window="right:60%:wrap")

  if [[ -n "$files" ]]; then
    clear
    echo "You are about to delete:"
    echo "$files" | sed 's/^/ - /'
    echo ""
    read -r -p "Are you sure? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "$files" | while read -r file; do
        rm "$file"
      done
      echo "Deleted."
      sleep 1
    fi
  fi
}

# ==========================================
# TUI MAIN INITIALIZATION & LOOP
# ==========================================
_editor_cmd=$(echo "$EDITOR" | awk '{print $1}')

for cmd in rg fzf "$_editor_cmd"; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "Error: $cmd is required." && exit 1
  fi
done

mkdir -p "$NOTES_DIR"
cd "$NOTES_DIR" || exit 1

while true; do
  choice=$(printf "📝 New Note\n📖 Read Note\n🔍 Search Notes\n🏷️ Browse by Tag\n⚡ Add Quick Note\n📜 View Quick Notes\n🗑️ Delete Note(s)\n❓ Help / Info\n❌ Quit" |
    fzf --prompt="Menu> " \
      --layout=reverse \
      --border=rounded \
      --margin=5%,10% \
      --padding=1,2 \
      --info=hidden \
      --header=" Vault: $NOTES_DIR " \
      --header-first)

  case "$choice" in
  "📝 New Note") cmd_new ;;
  "📖 Read Note") cmd_read ;;
  "🔍 Search Notes") cmd_search ;;
  "🏷️ Browse by Tag") cmd_tags ;;
  "⚡ Add Quick Note") cmd_quicknote ;;
  "📜 View Quick Notes") cmd_view_quicknotes ;;
  "🗑️ Delete Note(s)") cmd_delete ;;
  "❓ Help / Info") cmd_help ;;
  "❌ Quit" | "")
    clear
    exit 0
    ;;
  esac
done
