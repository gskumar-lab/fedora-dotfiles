#!/bin/bash

# ==========================================
# Dependencies & Configuration
# ==========================================
command -v fzf >/dev/null 2>&1 || { echo -e "\033[1;31mError:\033[0m 'fzf' is not installed. Please install it to use this planner."; exit 1; }

# Disable terminal flow control so Ctrl-S can be passed to FZF
stty -ixon 2>/dev/null

SCRIPT_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0")
SCRIPT_NAME=$(basename "$SCRIPT_PATH")
# Use environment TERMINAL if set, otherwise fallback to foot
TERM_CMD="${TERMINAL:-foot}"

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
    
    # Use a single awk process to handle tags, done, and skip lists efficiently in memory
    awk -v day="$DAY_SHORT" -v is_wknd="$IS_WEEKEND" '
        BEGIN {
            while ((getline < "'"$DONE"'") > 0) done_list[$0]++
            while ((getline < "'"$SKIP"'") > 0) skip_list[$0]++
        }
        {
            # 1. Tag Filtering
            if ($0 ~ /@/) {
                match_tag = 0
                if ($0 ~ "@("day"|Daily)\\b") match_tag = 1
                if (is_wknd == "true" && $0 ~ /@Weekend\b/) match_tag = 1
                if (is_wknd == "false" && $0 ~ /@Weekday\b/) match_tag = 1
                if (!match_tag) next
            }
            
            # 2. Check if already Done or Skipped (handle duplicates)
            if (done_list[$0] > 0) {
                done_list[$0]--
                next
            }
            if (skip_list[$0] > 0) {
                skip_list[$0]--
                next
            }
            
            # 3. Output to TODO
            print $0
        }
    ' "$MASTER" > "$tmp_todo"
    
    mv "$tmp_todo" "$TODO"
}

check_rollover() {
    LAST=$(cat "$LAST_RUN" 2>/dev/null)
    if [ "$LAST" != "$TODAY" ]; then
        if [ -n "$LAST" ]; then
            # Replaced sed with awk to prevent delimiter collision on dates
            [ -s "$TODO" ] && awk -v d="$LAST" '{print d " MISSED " $0}' "$TODO" >> "$HIST"
            [ -s "$DONE" ] && awk -v d="$LAST" '{print d " DONE " $0}' "$DONE" >> "$HIST"
            [ -s "$SKIP" ] && awk -v d="$LAST" '{print d " SKIPPED " $0}' "$SKIP" >> "$HIST"
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
    echo -e "${DIM}  [q] Menu  │  [c] Complete Task  │  [n] Skip Timer  │  [p] Pause${NC}"
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
            local end_time=$(( $(date +%s) + total ))
            local action=""
            clear 
            
            while [ $left -gt 0 ]; do
                # System clock check prevents execution delay time-drift
                left=$(( end_time - $(date +%s) ))
                [ $left -lt 0 ] && left=0

                draw_timer $left $total "POMODORO SESSION" "$RED" "$p_task"
                
                read -t 1 -n 1 input
                case "$input" in
                    q) action="menu"; break ;;
                    c) action="complete"; break ;;
                    n) action="next"; break ;;
		    p)
                        draw_timer $left $total "PAUSED (Press 'p' to resume)" "$YELLOW" "$p_task"
                        while true; do
                            read -n 1 -s p_input
                            # Case-insensitive check for 'p'
                            [ "${p_input,,}" = "p" ] && break
                        done
                        # Shift the target end_time forward by the remaining time so we don't lose time
                        end_time=$(( $(date +%s) + left ))
                        ;;
                esac
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
                        local b_end_time=$(( $(date +%s) + b_total ))
                        clear
                        while [ $b_left -gt 0 ]; do
                            b_left=$(( b_end_time - $(date +%s) ))
                            [ $b_left -lt 0 ] && b_left=0

                            draw_timer $b_left $b_total "SHORT BREAK" "$BLUE" "Rest your mind"
                            
                            read -t 1 -n 1 input
                            case "$input" in
                                q|n) break ;;
                                c) echo "$p_task" >> "$DONE"; sync_todo; post_action="next"; break 2 ;;
                            esac
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
# Analytics & Streaks Engine
# ==========================================
show_analytics() {
    clear
    echo -e "${CYAN}╭───────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│               ANALYTICS & STREAKS                 │${NC}"
    echo -e "${CYAN}╰───────────────────────────────────────────────────╯${NC}\n"
    
    if [ ! -s "$HIST" ]; then
        echo -e " ${DIM}No history logged yet.${NC}\n"
        read -n 1 -s -p " Press any key to return..." 
        return
    fi

    # Helper to calculate and print top 3 tasks for a specific status
    print_top() {
        grep " $1 " "$HIST" | cut -d' ' -f3- | sort | uniq -c | sort -nr | head -n 3 | \
        awk -v color="$2" -v nc="$NC" '{ count=$1; $1=""; sub(/^[ \t]+/, ""); printf "   " color "%s" nc " (%s times)\n", $0, count }'
    }

    echo -e " ${GREEN}🏆 Most Completed Tasks:${NC}"
    print_top "DONE" "$GREEN"
    
    echo -e "\n ${RED}✖ Most Missed Tasks:${NC}"
    print_top "MISSED" "$RED"
    
    echo -e "\n ${DIM}⊘ Most Skipped Tasks:${NC}"
    print_top "SKIPPED" "$DIM"

    echo -e "\n ${YELLOW}🔥 Current Streaks (Consecutive Completed Days):${NC}"
    # Read history file backwards to easily calculate current active streaks
    awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--] }' "$HIST" | awk '
        {
            status=$2; $1=""; $2=""; sub(/^[ \t]+/, ""); task=$0;
            if (!processed[task]) {
                if (status == "DONE") streak[task] = 1;
                else streak[task] = -1; # Not currently on a streak
                processed[task] = 1;
            } else if (streak[task] > 0) {
                if (status == "DONE") streak[task]++;
                else streak[task] = -1; # Streak broken
            }
        }
        END {
            found=0;
            for (t in streak) {
                if (streak[t] > 1) {
                    print "   " streak[t] " days : " t;
                    found=1;
                }
            }
            if (found==0) print "   No active multi-day streaks. Keep going!"
        }
    ' | sort -nr

    echo ""
    read -n 1 -s -p " Press any key to return..."
}

# ==========================================
# CLI Arguments parsing
# ==========================================
case "$1" in
    --pomodoro)
        run_pomodoro
        exit 0 ;;

    --notify)
        todo_count=$(grep -c "^" "$TODO" || true)
        if [ "$todo_count" -gt 0 ]; then
            if command -v notify-send &> /dev/null; then
                action=$(notify-send -u low -t 0 \
                    --action="open=Open Planner" \
                    "⏰ Routine Reminder" \
                    "You have $todo_count tasks left today!")

                if [ "$action" = "open" ]; then
                    systemd-run --user --quiet "$TERM_CMD" "$SCRIPT_PATH"
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
    printf "${CYAN}│ %-49s         │${NC}\n" "${BOLD}${title}${NC}"
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

    done_list=$(tail -n 4 "$DONE" | sed "s/^/ ${GREEN}✔${NC} /")
    hidden_done=$(( comp_count - 4 ))
    # FIXED: Replaced \n with $'\n'
    [ "$hidden_done" -gt 0 ] && done_list="${done_list}"$'\n'" ${DIM}...and $hidden_done older items${NC}"
    [ -z "$done_list" ] && done_list=" ${DIM}(No tasks completed yet)${NC}"

    skip_section=""
    if [ -s "$SKIP" ]; then
        skip_list=$(tail -n 2 "$SKIP" | sed "s/^/ ${DIM}⊘${NC} /")
        hidden_skip=$(( skip_count - 2 ))
        # FIXED: Replaced \n with $'\n'
        [ "$hidden_skip" -gt 0 ] && skip_list="${skip_list}"$'\n'" ${DIM}...and $hidden_skip older items${NC}"
        skip_section=$'\n\n'"${DIM} Skipped:${NC}"$'\n'"$skip_list"
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
 ${DIM}[^T] Stats   │ [^R] Reorder  │ [?] Help │ [Esc] Quit${NC}
${DIM} ───────────────────────────────────────────────────${NC}
EOF
)
    output=$(fzf --ansi --header="$header" \
        --expect=ctrl-p,ctrl-s,ctrl-e,ctrl-x,ctrl-a,ctrl-z,ctrl-r,ctrl-h,ctrl-t,? \
        --prompt=" ❯ " --pointer="▶" --height=100% --reverse --info=hidden \
        --color=header:italic,prompt:cyan,pointer:green < "$TODO")
    
    [ -z "$output" ] && { clear; exit 0; }

    key=$(echo "$output" | head -n1)
    task=$(echo "$output" | tail -n +2)
    is_valid_task() { [ -n "$(echo "$task" | tr -d '[:space:]')" ]; }

    case "$key" in
        "")       if is_valid_task; then echo "$task" >> "$DONE"; sync_todo; fi ;;
        ctrl-p)   
            script_path=$(realpath "$0" 2>/dev/null || readlink -f "$0")
            systemd-run --user --quiet "$TERM_CMD" -T apps-float-small "$script_path" --pomodoro 
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

	ctrl-t)
            show_analytics ;;

	ctrl-h)
            while true; do
                # 1. Fetch dates and check if history exists
                dates=$(awk '{print $1}' "$HIST" 2>/dev/null | sort -ru | head -n 30)
                if [ -z "$dates" ]; then 
                    clear
                    echo -e "\n  ${DIM}No history logged yet.${NC}\n"
                    read -n 1 -s -p " Press any key to return..." 
                    break
                fi
                
                # 2. Build the main history menu
                menu_items=""
                for d in $dates; do
                    d_done=$(grep -c "^$d DONE" "$HIST" || true)
                    d_miss=$(grep -c "^$d MISSED" "$HIST" || true)
                    d_skip=$(grep -c "^$d SKIPPED" "$HIST" || true)
                    menu_items+="$d  │  ✔ $d_done Done  │  ✖ $d_miss Missed  │  ⊘ $d_skip Skipped\n"
                done
                
                # 3. Display the date selection fzf window
                hist_header=$(cat <<EOF
${CYAN}╭───────────────────────────────────────────────────╮${NC}
${CYAN}│                  HISTORY LOG                      │${NC}
${CYAN}╰───────────────────────────────────────────────────╯${NC}
EOF
)
                selected_line=$(echo -e -n "$menu_items" | fzf --prompt=" 📅 Select Date (Esc to exit) ❯ " \
                    --pointer="▶" --height=100% --reverse \
                    --header="$hist_header")
                
                # If Esc is pressed, exit the history loop and return to planner
                [ -z "$selected_line" ] && break
                
                # 4. Extract date and build the drill-down view
                selected_date=$(echo "$selected_line" | awk '{print $1}')
                
                day_details=$(awk -v d="$selected_date" \
                                  -v c_green="$GREEN" -v c_red="$RED" -v c_dim="$DIM" -v c_nc="$NC" '
                    $1 == d {
                        status = $2
                        # Remove date and status words to isolate the task string
                        $1 = ""; $2 = ""; 
                        sub(/^[ \t]+/, "")
                        
                        # Apply corresponding colors
                        if (status == "DONE") print c_green "✔ DONE   " c_nc $0
                        else if (status == "MISSED") print c_red "✖ MISSED " c_nc $0
                        else if (status == "SKIPPED") print c_dim "⊘ SKIPPED" c_nc $0
                    }
                ' "$HIST")
                
                # 5. Display the tasks for the selected date
                echo -e "$day_details" | fzf --ansi \
                    --prompt=" ⏎ Press Enter/Esc to return to dates ❯ " \
                    --pointer=" " --height=100% --reverse \
                    --header=" 🔍 Details for $selected_date "
            done
            
            # Re-draw the main interface cleanly after exiting history
            clear
            ;;

        "?") 
            clear
            echo -e "${CYAN}╭───────────────────────────────────────────────────╮${NC}"
            echo -e "${CYAN}│                  HELP & FEATURES                  │${NC}"
            echo -e "${CYAN}╰───────────────────────────────────────────────────╯${NC}"
            echo -e "\n${GREEN}🍅 Pomodoro Timer${NC}"
            echo -e "  Press [^P] to open the Pomodoro selector in a new"
            echo -e "  terminal window. It will run independently."
	    echo -e "\n${GREEN}📊 Analytics & Streaks [^T]${NC}"
            echo -e "  View your most completed, missed, and skipped tasks,"
            echo -e "  along with your current multi-day streaks."
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

