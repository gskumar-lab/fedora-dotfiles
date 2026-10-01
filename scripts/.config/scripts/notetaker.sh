#!/usr/bin/env bash
# TUI Note App: New, Read, Search, Tags, Delete

# ==========================================
# CONFIGURATION
# ==========================================
NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"
EDITOR="${EDITOR:-vim}"
EXT=".md"

mkdir -p "$NOTES_DIR"
cd "$NOTES_DIR" || exit 1

# ==========================================
# PREVIEW LOGIC (with Glow Integration)
# ==========================================
export FZF_PREVIEW_OPTS='
    file={1}
    line={2}
    
    if [ ! -f "$file" ]; then
        echo "Error: Cannot read file -> $file"
        exit 1
    fi
    
    if [ -n "$line" ]; then
        # SEARCH MODE: Needs raw text to jump to line number
        cmd="cat"
        if command -v bat >/dev/null 2>&1; then 
            cmd="bat --color=always --style=plain"
        elif command -v batcat >/dev/null 2>&1; then 
            cmd="batcat --color=always --style=plain"
        fi
        
        eval "$cmd \"\$file\"" 2>/dev/null | tail -n +"$line" | head -n 30
    else
        # FULL FILE MODE: Use Glow for rich markdown rendering
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
# HELPER FUNCTIONS
# ==========================================
slugify() {
    echo "$1" | iconv -t ascii//TRANSLIT | sed -E -e 's/[^[:alnum:]]+/-/g' -e 's/^-+|-+$//g' | tr '[:upper:]' '[:lower:]'
}

# ==========================================
# CORE FEATURES
# ==========================================
cmd_new() {
    clear
    read -r -e -p "Note Title: " title
    [[ -z "$title" ]] && return
    
    local file="$(slugify "$title")$EXT"
    
    if [[ ! -f "$file" ]]; then
        echo "# $title" > "$file"
        echo -e "\nTags: \nDate: $(date +%Y-%m-%d)\n" >> "$file"
    fi
    
    $EDITOR "$file"
}

cmd_read() {
    local result key file
    # --expect captures the key pressed before exiting fzf
    result=$(find . -type f -name "*$EXT" 2>/dev/null | sed 's|^\./||' | sort -r | \
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
    tag=$(rg -o '#[a-zA-Z0-9_-]+' . 2>/dev/null | \
        awk -F: '{print $2}' | sort | uniq -c | sort -nr | \
        fzf --prompt="🏷️  Select Tag> " --border=rounded | awk '{print $2}')
    
    if [[ -n "$tag" ]]; then
        local file
        file=$(rg -l "$tag" . 2>/dev/null | sed 's|^\./||' | \
            fzf --prompt="Notes with $tag> " \
                --border=rounded \
                --preview "$FZF_PREVIEW_OPTS")
                
        [[ -n "$file" ]] && $EDITOR "$file"
    fi
}

cmd_delete() {
    local files
    files=$(find . -type f -name "*$EXT" 2>/dev/null | sed 's|^\./||' | sort -r | \
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
# TUI MAIN LOOP
# ==========================================
for cmd in rg fzf $EDITOR; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "Error: $cmd is required." && exit 1
    fi
done

while true; do
    choice=$(printf "📝 New Note\n📖 Read Note\n🔍 Search Notes\n🏷️ Browse by Tag\n🗑️ Delete Note(s)\n❌ Quit" | \
        fzf --prompt="Menu> " \
            --layout=reverse \
            --border=rounded \
            --margin=5%,10% \
            --padding=1,2 \
            --info=hidden \
            --header=" Vault: $NOTES_DIR " \
            --header-first)
    
    case "$choice" in
        "📝 New Note")        cmd_new ;;
        "📖 Read Note")       cmd_read ;;
        "🔍 Search Notes")    cmd_search ;;
        "🏷️ Browse by Tag")   cmd_tags ;;
        "🗑️ Delete Note(s)")  cmd_delete ;;
        "❌ Quit" | "")       clear; exit 0 ;;
    esac
done

