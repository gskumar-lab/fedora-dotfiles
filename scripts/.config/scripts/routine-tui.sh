#!/bin/bash

# ==========================================
# Dependencies & Configuration
# ==========================================
command -v fzf >/dev/null 2>&1 || { echo -e "\033[1;31mError:\033[0m 'fzf' is not installed. Please install it to use this planner."; exit 1; }

SCRIPT_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0")
SCRIPT_NAME=$(basename "$SCRIPT_PATH")

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

# Modern Color Palette
CYAN=$'\033[1;36m'
BLUE=$'\033[1;34m'
GREEN=$'\033[1;32m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

TODAY=$(date +%Y-%m-%d)
DAY_SHORT=$(date +%a)
[[ "$DAY_SHORT" == "Sat" || "$DAY_SHORT" == "Sun" ]] && IS_WEEKEND=true || IS_WEEKEND=false

# ==========================================
# Core Logic
# ==========================================
sync_todo() {
    local tmp_todo=$(mktemp)
    local tmp_done=$(mktemp)
    local tmp_skip=$(mktemp)
    
    cp "$DONE" "$tmp_done"
    cp "$SKIP" "$tmp_skip"
    
    while IFS= read -r t; do
        if echo "$t" | grep -q "@"; then
            match=false
            echo "$t" | grep -Eiq "@($DAY_SHORT|Daily)\b" && match=true
            if [ "$IS_WEEKEND" = true ]; then
                echo "$t" | grep -Eiq "@Weekend\b" && match=true
            else
                echo "$t" | grep -Eiq "@Weekday\b" && match=true
            fi
            if [ "$match" = false ]; then continue; fi
        fi
        
        if grep -m 1 -Fxq "$t" "$tmp_done" 2>/dev/null; then
            awk -v t="$t" 'BEGIN{removed=0} {if($0==t && removed==0){removed=1} else {print $0}}' "$tmp_done" > "${tmp_done}.new" && mv "${tmp_done}.new" "$tmp_done"
            continue
        fi
        
        if grep -m 1 -Fxq "$t" "$tmp_skip" 2>/dev/null; then
            awk -v t="$t" 'BEGIN{removed=0} {if($0==t && removed==0){removed=1} else {print $0}}' "$tmp_skip" > "${tmp_skip}.new" && mv "${tmp_skip}.new" "$tmp_skip"
            continue
        fi
        
        echo "$t" >> "$tmp_todo"
    done < "$MASTER"
    
    mv "$tmp_todo" "$TODO"
    rm -f "$tmp_done" "$tmp_skip"
}

check_rollover() {
    LAST=$(cat "$LAST_RUN" 2>/dev/null)
    if [ "$LAST" != "$TODAY" ]; then
        if [ -n "$LAST" ]; then
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
# Pomodoro UI (UX Overhauled)
# ==========================================
draw_timer() {
    local left=$1
    local total=$2
    local label=$3
    local color=$4
    local task=$5
    
    printf "\033[H"
    
    local pct=$(( ((total - left) * 100) / total ))
    local bar_len=36
    local filled=$(( (pct * bar_len) / 100 ))
    local empty=$(( bar_len - filled ))
    local bar=""; local empty_bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do empty_bar="${empty_bar}┄"; done

    mins=$((left / 60))
    secs=$((left % 60))

    echo -e "${color}╭───────────────────────────────────────────────────╮${NC}"
    echo -e "${color}│${NC}                 ${BOLD}${label}${NC}                  ${color}│${NC}"
    echo -e "${color}╰───────────────────────────────────────────────────╯${NC}"
    echo -e " 🎯 ${DIM}Focusing on:${NC} ${YELLOW}${task}${NC}\n"
    printf "      ⏳ Remaining: ${BOLD}%02d:%02d${NC}\n\n" $mins $secs
    echo -e "      ${color}${bar}${DIM}${empty_bar}${NC} ${pct}%\n"
    echo -e "${DIM} ───────────────────────────────────────────────────${NC}"
    echo -e "${DIM}  [q] Menu  │  [c] Complete Task  │  [n] Skip Timer${NC}"
    printf "\033[J"
}

run_pomodoro() {
    local work_time=1500
    local break_time=300

    while true; do
        local p_task
        p_task=$(fzf --prompt="🍅 Select Focus Task ❯ " \
                     --header="Press ESC to close Pomodoro window" \
                     --height=100% --reverse --color=prompt:red < "$TODO")
        [ -z "$p_task" ] && return
        
        while true; do
            # --- WORK SESSION ---
            local left=$work_time
            local total=$work_time
            local action=""
            clear 
            
            while [ $left -gt 0 ]; do
                draw_timer $left $total "POMODORO SESSION" "$RED" "$p_task"
                
                read -t 1 -n 1 input
                case "$input" in
                    q) action="menu"; break ;;
                    c) action="complete"; break ;;
                    n) action="next"; break ;;
                esac
                ((left--))
            done

            if [ "$action" = "complete" ]; then
                echo "$p_task" >> "$DONE"
                sync_todo
                break
            elif [ "$action" = "next" ]; then
                break
            fi

            if [ -z "$action" ]; then
                if command -v notify-send &> /dev/null; then
                    notify-send -u normal -t 5000 "🍅 Focus Session Complete!" "Great job working on: $p_task"
                else
                    echo -e "\a"
                fi
            fi

            # --- POST-TIMER MENU ---
            local post_action=""
            while true; do
                clear
                echo -e "${RED}╭───────────────────────────────────────────────────╮${NC}"
                echo -e "${RED}│                   SESSION ENDED                   │${NC}"
                echo -e "${RED}╰───────────────────────────────────────────────────╯${NC}"
                echo -e " 🎯 ${DIM}Task:${NC} ${YELLOW}$p_task${NC}\n"
                echo -e "  [1] ${GREEN}✔${NC} Complete Task  ${DIM}(Marks done & pick new)${NC}"
                echo -e "  [2] ${CYAN}☕${NC} Take 5m Break  ${DIM}(Starts break timer)${NC}"
                echo -e "  [3] ${RED}🍅${NC} Work Again     ${DIM}(Start another 25m block)${NC}"
                echo -e "  [4] ${YELLOW}⟳${NC} Next Task      ${DIM}(Pick a different task)${NC}"
                echo -e "  [5] ${DIM}↵${NC} Quit Mode      ${DIM}(Closes Pomodoro Window)${NC}\n"
                
                read -n 1 -p " ❯ Select option (1-5): " opt
                echo ""
                
                case $opt in
                    1) echo "$p_task" >> "$DONE"; sync_todo; post_action="next"; break ;;
                    2) 
                        # --- BREAK SESSION ---
                        local b_left=$break_time
                        local b_total=$break_time
                        clear
                        while [ $b_left -gt 0 ]; do
                            draw_timer $b_left $b_total "SHORT BREAK" "$BLUE" "Rest your mind"
                            
                            read -t 1 -n 1 input
                            case "$input" in
                                q|n) break ;;
                                c) echo "$p_task" >> "$DONE"; sync_todo; post_action="next"; break 2 ;;
                            esac
                            ((b_left--))
                        done

                        if [ $b_left -eq 0 ]; then
                            if command -v notify-send &> /dev/null; then
                                notify-send -u normal -t 5000 "☕ Break Over!" "Ready to focus?"
                            else
                                echo -e "\a"
                            fi
                        fi
                        continue
                        ;;
                    3) post_action="work"; break ;; 
                    4) post_action="next"; break ;;
                    5) return ;;
                    *) continue ;;
                esac
            done
            
            if [ "$post_action" = "next" ]; then
                break 
            fi
        done
    done
}

# ==========================================
# CLI Arguments parsing (Moved below functions)
# ==========================================
case "$1" in
    --pomodoro)
        # Dedicated execution state for the detached window
        run_pomodoro
        exit 0 ;;

    --notify)
        todo_count=$(grep -c "^" "$TODO" || true)
        if [ "$todo_count" -gt 0 ]; then
            if command -v notify-send &> /dev/null; then
                # Creates a clickable button. When clicked, it returns the string "open"
                action=$(notify-send -u critical -t 0 \
                    --action="open=Open Planner" \
                    "⏰ Routine Reminder" \
                    "You have $todo_count tasks left today!")

                # If the user clicks "Open Planner", launch it in foot
                if [ "$action" = "open" ]; then
                    systemd-run --user --quiet foot "$SCRIPT_PATH"
                fi
            fi
        fi
        exit 0 ;;

    --status)
        comp_count=$(grep -c "^" "$DONE" || true)
        todo_count=$(grep -c "^" "$TODO" || true)
        skip_count=$(grep -c "^" "$SKIP" || true)
        total=$((comp_count + todo_count + skip_count))
        if [ "$total" -eq 0 ]; then echo "Routine: No tasks"; else
            pct=$(( ( (comp_count + skip_count) * 100 ) / total ))
            echo "Routine: ${pct}% [${comp_count}/${total} done, ${todo_count} left]"
        fi
        exit 0 ;;
esac

# ==========================================
# Terminal & Main Loop Setup
# ==========================================
cleanup() { tput rmcup 2>/dev/null; clear; }
trap cleanup EXIT INT TERM
tput smcup
clear

dialog_box() {
    local title="$1"
    local prompt="$2"
    clear
    echo -e "${CYAN}╭───────────────────────────────────────────────────╮${NC}"
    printf "${CYAN}│ %-49s │${NC}\n" "${BOLD}${title}${NC}"
    echo -e "${CYAN}╰───────────────────────────────────────────────────╯${NC}\n"
    read -e -p " ❯ $prompt " dialog_result
}

while true; do
    comp_count=$(grep -c "^" "$DONE" || true)
    todo_count=$(grep -c "^" "$TODO" || true)
    skip_count=$(grep -c "^" "$SKIP" || true)
    
    total=$((comp_count + todo_count + skip_count))
    [ "$total" -eq 0 ] && pct=0 || pct=$(( ( (comp_count + skip_count) * 100 ) / total ))

    # High-fidelity Progress Bar
    bar_len=24
    filled=$(( (pct * bar_len) / 100 ))
    empty=$(( bar_len - filled ))
    bar=$(printf "%0.s█" $(seq 1 $filled 2>/dev/null))
    empty_bar=$(printf "%0.s┄" $(seq 1 $empty 2>/dev/null))
    progress_bar="[${GREEN}${bar}${DIM}${empty_bar}${NC}] ${BOLD}${pct}%${NC}"

    # UX FIX: Truncate lists to prevent FZF from getting pushed off-screen
    done_list=$(tail -n 4 "$DONE" | sed "s/^/ ${GREEN}✔${NC} /")
    hidden_done=$(( comp_count - 4 ))
    [ "$hidden_done" -gt 0 ] && done_list="$done_list\n ${DIM}...and $hidden_done older items${NC}"
    [ -z "$done_list" ] && done_list=" ${DIM}(No tasks completed yet)${NC}"

    skip_section=""
    if [ -s "$SKIP" ]; then
        skip_list=$(tail -n 2 "$SKIP" | sed "s/^/ ${DIM}⊘${NC} /")
        hidden_skip=$(( skip_count - 2 ))
        [ "$hidden_skip" -gt 0 ] && skip_list="$skip_list\n ${DIM}...and $hidden_skip older items${NC}"
        skip_section=$'\n\n'"${DIM} Skipped:${NC}\n$skip_list"
    fi

    header=$(cat <<EOF
${CYAN}╭───────────────────────────────────────────────────╮${NC}
${CYAN}│               DAILY ROUTINE PLANNER               │${NC}
${CYAN}╰───────────────────────────────────────────────────╯${NC}
 📅 Date: $TODAY ($DAY_SHORT)   📝 Left: $todo_count
 📊 Progress: $progress_bar

${DIM} Recently Completed:${NC}
$done_list$skip_section

${DIM} ───────────────────────────────────────────────────${NC}
 ${DIM}[Enter] Done │ [^P] Pomodoro │ [^A] Add │ [^E] Edit${NC}
 ${DIM}[^S] Skip    │ [^Z] Undo     │ [^X] Del │ [^H] Hist${NC}
 ${DIM}[?] Help     │ [^R] Reorder  │ [Esc] Quit${NC}
EOF
)
    output=$(fzf --ansi --header="$header" \
        --expect=ctrl-p,ctrl-s,ctrl-e,ctrl-x,ctrl-a,ctrl-z,ctrl-r,ctrl-h,? \
        --prompt=" ❯ " --pointer="▶" --height=100% --reverse --info=hidden \
        --color=header:italic,prompt:cyan,pointer:green < "$TODO")
    
    [ -z "$output" ] && { clear; exit 0; }

    key=$(echo "$output" | head -n1)
    task=$(echo "$output" | tail -n +2)
    is_valid_task() { [ -n "$(echo "$task" | tr -d '[:space:]')" ]; }

    case "$key" in
        "")       if is_valid_task; then echo "$task" >> "$DONE"; sync_todo; fi ;;
        ctrl-p)   
            # Spawns Pomodoro in a detached foot terminal via systemd
            script_path=$(realpath "$0" 2>/dev/null || readlink -f "$0")
            systemd-run --user --quiet foot -T apps-float-small "$script_path" --pomodoro 
            ;; 
        ctrl-s)   if is_valid_task; then echo "$task" >> "$SKIP"; sync_todo; fi ;;
        ctrl-a) 
            dialog_box "ADD NEW TASK" "Task description (use @ tags):"
            if [ -n "$(echo "$dialog_result" | tr -d '[:space:]')" ]; then
                echo "$dialog_result" >> "$MASTER"; sync_todo
            fi ;;
        ctrl-x) 
            if is_valid_task; then
                dialog_box "DELETE TASK" "Delete '$task' permanently? (y/N):"
                if [[ "$dialog_result" =~ ^[Yy]$ ]]; then
                    for f in "$MASTER" "$DONE" "$SKIP"; do
                        tmp=$(mktemp)
                        awk -v t="$task" 'BEGIN{removed=0} {if($0==t && removed==0){removed=1} else {print $0}}' "$f" > "$tmp"
                        cat "$tmp" > "$f" && rm "$tmp"
                    done
                    sync_todo
                fi
            fi ;;
        ctrl-e) 
            if is_valid_task; then
                dialog_box "EDIT TASK" "New text for '$task':"
                if [ -n "$(echo "$dialog_result" | tr -d '[:space:]')" ] && [ "$dialog_result" != "$task" ]; then
                    for f in "$MASTER" "$DONE" "$SKIP"; do
                        tmp=$(mktemp)
                        awk -v old="$task" -v new="$dialog_result" 'BEGIN{e=0} {if($0==old && e==0){print new; e=1} else {print $0}}' "$f" > "$tmp"
                        cat "$tmp" > "$f" && rm "$tmp"
                    done
                    sync_todo
                fi
            fi ;;
        ctrl-r) 
            ${EDITOR:-nano} "$MASTER"
            sync_todo ;;
        ctrl-z) 
            task=$(cat "$DONE" "$SKIP" | fzf --prompt=" ↩ Undo ❯ " --pointer="▶" --height=40% --reverse)
            if is_valid_task; then
                for f in "$DONE" "$SKIP"; do
                    tmp=$(mktemp)
                    awk -v t="$task" 'BEGIN{u=0} {if($0==t && u==0){u=1} else {print $0}}' "$f" > "$tmp"
                    cat "$tmp" > "$f" && rm "$tmp"
                done
                sync_todo
            fi ;;
        ctrl-h)
	       clear	
            echo -e "7-DAY HISTORY \n" 
            dates=$(awk '{print $1}' "$HIST" 2>/dev/null | sort -ru | head -n 7)
            if [ -z "$dates" ]; then echo -e "  ${DIM}No history logged yet.${NC}"; else
                for d in $dates; do
                    d_done=$(grep "^$d DONE" "$HIST" | wc -l)
                    d_miss=$(grep "^$d MISSED" "$HIST" | wc -l)
                    d_skip=$(grep "^$d SKIPPED" "$HIST" | wc -l)
                    echo -e "  📅 ${CYAN}$d${NC} → ${GREEN}✔ $d_done Done${NC} │ ${RED}✖ $d_miss Missed${NC} │ ${DIM}⊘ $d_skip Skipped${NC}"
                done
            fi
            echo -e "\n Press [Enter] to return."
            read -r ;;
        "?") 
            clear
            echo -e "${CYAN}╭───────────────────────────────────────────────────╮${NC}"
            echo -e "${CYAN}│                  HELP & FEATURES                  │${NC}"
            echo -e "${CYAN}╰───────────────────────────────────────────────────╯${NC}"
            echo -e "\n${GREEN}🍅 Pomodoro Timer${NC}"
            echo -e "  Press [^P] to open the Pomodoro selector in a new"
            echo -e "  terminal window. It will run independently."
            echo -e "\n${GREEN}🏷️  Smart Tags${NC}"
            echo -e "  • ${DIM}@Mon, @Tue, @Wed...${NC} (Runs on specific days)"
            echo -e "  • ${DIM}@Weekday, @Weekend${NC}  (Runs on grouped days)"
            echo -e "  • ${DIM}@Daily${NC}              (Runs every day)"
            echo -e "\n${GREEN}💻 CLI Arguments (Background Use)${NC}"
            echo -e "  • ${DIM}$SCRIPT_NAME --pomodoro${NC} (Launch Timer UI directly)"
            echo -e "  • ${DIM}$SCRIPT_NAME --notify${NC}   (Desktop alert if tasks remain)"
            echo -e "  • ${DIM}$SCRIPT_NAME --status${NC}   (Outputs text for Waybar/tmux)"
            echo -e "\nPress [ENTER] to go back..."
            read -r ;;
    esac
done

