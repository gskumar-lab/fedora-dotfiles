#!/bin/bash

# ==========================================
# Configuration & Styling
# ==========================================
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/routine_planner"
mkdir -p "$DIR"

MASTER="$DIR/master.txt"
TODO="$DIR/todo.txt"
DONE="$DIR/done.txt"
SKIP="$DIR/skip.txt"
HIST="$DIR/history.log"
LAST_RUN="$DIR/last_run.txt"

for file in "$MASTER" "$TODO" "$DONE" "$SKIP" "$HIST" "$LAST_RUN"; do
    [ ! -f "$file" ] && touch "$file"
done

# Colors
CYAN=$'\033[1;36m'
GREEN=$'\033[1;32m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
NC=$'\033[0m'

TODAY=$(date +%Y-%m-%d)
DAY_SHORT=$(date +%a) # e.g., Mon, Tue, Wed

# Determine if it's the weekend for tag logic
if [[ "$DAY_SHORT" == "Sat" || "$DAY_SHORT" == "Sun" ]]; then
    IS_WEEKEND=true
else
    IS_WEEKEND=false
fi

# ==========================================
# Universal Sync Function (with Tag Logic)
# ==========================================
sync_todo() {
    local tmp_todo
    tmp_todo=$(mktemp)
    
    while IFS= read -r t; do
        # Day-Specific Tasks Logic
        if echo "$t" | grep -q "@"; then
            match=false
            
            # Use -Ewi to ensure we match whole words (e.g., @Mon, not @Monday.com)
            echo "$t" | grep -Ewiq "@($DAY_SHORT|Daily)" && match=true
            
            if [ "$IS_WEEKEND" = true ]; then
                echo "$t" | grep -Ewiq "@Weekend" && match=true
            else
                echo "$t" | grep -Ewiq "@Weekday" && match=true
            fi
            
            # If a tag exists but doesn't apply to today, skip adding it
            if [ "$match" = false ]; then
                continue
            fi
        fi
        
        # Add if not already done or skipped
        if ! grep -Fxq "$t" "$DONE" && ! grep -Fxq "$t" "$SKIP"; then
            echo "$t" >> "$tmp_todo"
        fi
    done < "$MASTER"
    
    mv "$tmp_todo" "$TODO"
}

# ==========================================
# Daily Rollover Logic
# ==========================================
check_rollover() {
    LAST=$(cat "$LAST_RUN" 2>/dev/null)
    if [ "$LAST" != "$TODAY" ]; then
        if [ -n "$LAST" ]; then
            # Batch process the history logging instead of looping
            [ -s "$TODO" ] && sed "s/^/$LAST MISSED /" "$TODO" >> "$HIST"
            [ -s "$DONE" ] && sed "s/^/$LAST DONE /" "$DONE" >> "$HIST"
            [ -s "$SKIP" ] && sed "s/^/$LAST SKIPPED /" "$SKIP" >> "$HIST"
        fi
        > "$DONE"
        > "$SKIP"
        echo "$TODAY" > "$LAST_RUN"
        sync_todo
    fi
}

check_rollover

# ==========================================
# CLI Arguments parsing (--notify, --status)
# ==========================================
case "$1" in
    --notify)
        todo_count=$(grep -c "^" "$TODO" || true)
        if [ "$todo_count" -gt 0 ]; then
            if command -v notify-send &> /dev/null; then
                notify-send -u critical -t 0 "⏰ Routine Reminder" "You have $todo_count tasks remaining today!"
            else
                wall "REMINDER: You have $todo_count tasks remaining today!" 2>/dev/null || logger "REMINDER: You have $todo_count tasks remaining today!"
            fi
        fi
        exit 0
        ;;
    --status)
        comp_count=$(grep -c "^" "$DONE" || true)
        todo_count=$(grep -c "^" "$TODO" || true)
        skip_count=$(grep -c "^" "$SKIP" || true)
        
        total=$((comp_count + todo_count + skip_count))
        if [ "$total" -eq 0 ]; then
            echo "Routine: No tasks for today"
        else
            pct=$(( ( (comp_count + skip_count) * 100 ) / total ))
            echo "Routine: ${pct}% [${comp_count}/${total} done, ${todo_count} left]"
        fi
        exit 0
        ;;
esac

# ==========================================
# Terminal Setup (Interactive Mode Only)
# ==========================================
cleanup() {
  tput rmcup 2>/dev/null
  clear
}
trap cleanup EXIT INT TERM

tput smcup
clear

# ==========================================
# Main TUI Loop
# ==========================================
while true; do
    comp_count=$(grep -c "^" "$DONE" || true)
    todo_count=$(grep -c "^" "$TODO" || true)
    skip_count=$(grep -c "^" "$SKIP" || true)
    
    total=$((comp_count + todo_count + skip_count))
    if [ "$total" -eq 0 ]; then pct=0; else pct=$(( ( (comp_count + skip_count) * 100 ) / total )); fi

    # Visual Progress Bar
    bar_len=20
    filled=$(( (pct * bar_len) / 100 ))
    empty=$(( bar_len - filled ))

    bar=""
    empty_bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do empty_bar="${empty_bar}░"; done

    progress_bar="[${GREEN}${bar}${DIM}${empty_bar}${NC}] ${pct}%"

    done_list=$(sed "s/^/${GREEN}☑${NC} /" "$DONE")
    [ -z "$done_list" ] && done_list="${DIM}(None)${NC}"

    skip_section=""
    if [ -s "$SKIP" ]; then
        skip_list=$(sed "s/^/${DIM}⊘${NC} /" "$SKIP")
        skip_section=$'\n'"Skipped:"$'\n'"$skip_list"
    fi

    # Boxed Header
    header=$(cat <<EOF
${CYAN}╭───────────────────────────────────────────────────╮${NC}
${CYAN}│               DAILY ROUTINE PLANNER               │${NC}
${CYAN}╰───────────────────────────────────────────────────╯${NC}
Date: $TODAY ($DAY_SHORT)  |  Remaining: $todo_count
Progress: $progress_bar

Completed:
$done_list$skip_section

-- Hotkeys --
[Enter] Complete  │  [^S] Skip  │  [^E] Edit      │  [^X] Remove
[^A] Add Task     │  [^Z] Undo  │  [^R] Reorder   │  [^H] History
[?] Help          │  [Esc] Quit
─────────────────────────────────────────────────────────────────────
EOF
)
    output=$(fzf --ansi --header="$header" \
        --expect=ctrl-s,ctrl-e,ctrl-x,ctrl-a,ctrl-z,ctrl-r,ctrl-h,? \
        --prompt="❯ " --height=100% --reverse --info=hidden --color=header:italic < "$TODO")
    
    [ -z "$output" ] && { clear; exit 0; }

    key=$(echo "$output" | head -n1)
    task=$(echo "$output" | tail -n +2)

    case "$key" in
        "") # Complete
            if [ -n "$task" ]; then echo "$task" >> "$DONE"; sync_todo; fi ;;
        ctrl-s) # Skip
            if [ -n "$task" ]; then echo "$task" >> "$SKIP"; sync_todo; fi ;;
        ctrl-a) # Add
            clear
            echo -e "${CYAN}╭──────────────────────────────────────╮${NC}"
            echo -e "${CYAN}│              ADD TASK                │${NC}"
            echo -e "${CYAN}╰──────────────────────────────────────╯${NC}"
            echo -e "${DIM}Tip: Use tags like @Mon, @Tue, @Weekday, or @Weekend${NC}\n"
            read -e -p "❯ New routine task: " new_task 
            if [ -n "$new_task" ]; then
                echo "$new_task" >> "$MASTER"
                sync_todo
            fi 
            ;;
        ctrl-x) # Remove
            if [ -n "$task" ]; then
                clear; echo -e "\nTask: ${DIM}$task${NC}\n"
                read -p "❯ Permanently delete? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    for f in "$MASTER" "$DONE" "$SKIP"; do
                        tmp=$(mktemp)
                        awk -v t="$task" '$0!=t' "$f" > "$tmp" && mv "$tmp" "$f"
                    done
                    sync_todo
                fi
            fi 
            ;;
        ctrl-e) # Edit
            if [ -n "$task" ]; then
                clear; echo -e "Editing task: ${DIM}$task${NC}\n"
                read -e -p "❯ New text: " new_task
                if [ -n "$new_task" ] && [ "$new_task" != "$task" ]; then
                    for f in "$MASTER" "$DONE" "$SKIP"; do
                        tmp=$(mktemp)
                        awk -v old="$task" -v new="$new_task" '{if ($0 == old) print new; else print $0}' "$f" > "$tmp" && mv "$tmp" "$f"
                    done
                    sync_todo
                fi
            fi 
            ;;
        ctrl-r) # Reorder
            ${EDITOR:-nano} "$MASTER"
            sync_todo
            ;;
        ctrl-z) # Undo
            task=$(cat "$DONE" "$SKIP" | fzf --prompt="❯ Undo " --height=40% --reverse)
            if [ -n "$task" ]; then
                for f in "$DONE" "$SKIP"; do
                    tmp=$(mktemp)
                    awk -v t="$task" '$0!=t' "$f" > "$tmp" && mv "$tmp" "$f"
                done
                sync_todo
            fi 
            ;;
        ctrl-h) # Streak / History Calendar
            clear
            echo -e "${CYAN}╭───────────────────────────────────────────────────╮${NC}"
            echo -e "${CYAN}│               LAST 7 DAYS ACTIVITY                │${NC}"
            echo -e "${CYAN}╰───────────────────────────────────────────────────╯${NC}\n"
            
            dates=$(awk '{print $1}' "$HIST" 2>/dev/null | sort -ru | head -n 7)
            if [ -z "$dates" ]; then
                echo -e "${DIM}No history logged yet. Complete tasks today and check back tomorrow!${NC}"
            else
                for d in $dates; do
                    d_done=$(grep "^$d DONE" "$HIST" | wc -l)
                    d_miss=$(grep "^$d MISSED" "$HIST" | wc -l)
                    d_skip=$(grep "^$d SKIPPED" "$HIST" | wc -l)
                    echo -e "📅 ${CYAN}$d${NC} → ${GREEN}✔ $d_done Done${NC}  |  ${RED}✖ $d_miss Missed${NC}  |  ${DIM}⊘ $d_skip Skipped${NC}"
                done
            fi
            
            echo -e "\nPress [ENTER] to go back..."
            read -r
            ;;
        "?") # Help / Features Menu
            clear
            echo -e "${CYAN}╭───────────────────────────────────────────────────╮${NC}"
            echo -e "${CYAN}│                  HELP & FEATURES                  │${NC}"
            echo -e "${CYAN}╰───────────────────────────────────────────────────╯${NC}"
            echo -e "\n${GREEN}🏷️  Smart Tags (Scheduling)${NC}"
            echo -e "  Append tags to your tasks to schedule them. Tasks"
            echo -e "  without tags will appear every day by default."
            echo -e "  • ${DIM}@Mon, @Tue, @Wed...${NC} (Runs on specific days)"
            echo -e "  • ${DIM}@Weekday, @Weekend${NC}  (Runs on grouped days)"
            echo -e "  • ${DIM}@Daily${NC}              (Runs every day)"
            echo -e "\n${GREEN}🔄 Daily Rollover${NC}"
            echo -e "  The first time you run the script on a new day,"
            echo -e "  any leftover tasks from yesterday are logged as"
            echo -e "  MISSED in your history, and a fresh list is made."
            echo -e "\n${GREEN}⚙️  CLI Arguments${NC}"
            echo -e "  • ${DIM}./script.sh --notify${NC} (Send desktop alert if tasks remain)"
            echo -e "  • ${DIM}./script.sh --status${NC} (Print inline text summary and exit)"
            echo -e "\n${GREEN}📁 Data Storage${NC}"
            echo -e "  All files (master list, history, state) live in:"
            echo -e "  ${DIM}$DIR${NC}"
            echo -e "\nPress [ENTER] to go back..."
            read -r
            ;;
    esac
done

