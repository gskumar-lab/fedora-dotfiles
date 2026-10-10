#!/usr/bin/env bash

# ==============================================================================
# QTimer - A Comprehensive Terminal Timer using fzf
# ==============================================================================

# --- Configuration & Storage ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config/gsk}/qtimer"
PRESETS_FILE="$CONFIG_DIR/presets.txt"
STATUS_FILE="/tmp/qtimer.status"

# Terminal emulator command. 
# For foot: "foot" 
# For alacritty: "alacritty -e"
TERMINAL_CMD="foot --title apps-float-tiny " 

# --- Colors & Styling ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
RESET='\033[0m'
BOLD='\033[1m'

# Initialize config directory
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$PRESETS_FILE" ]]; then
    echo -e "Tea (5m)|300\nSoft-Boiled Egg (6m)|360\nPower Nap (20m)|1200" > "$PRESETS_FILE"
fi

# --- Trap for Graceful Exit ---
cleanup() {
    tput cnorm
    rm -f "$STATUS_FILE"
    echo -e "\n\033[K${RED}Timer stopped.${RESET}"
    exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP

# --- Helper: Audio & Desktop Notifications ---
play_audio() {
    if command -v paplay &> /dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/complete.oga &> /dev/null &
    elif command -v afplay &> /dev/null; then
        afplay /System/Library/Sounds/Glass.aiff &> /dev/null &
    elif command -v mpv &> /dev/null; then
        mpv --no-video /usr/share/sounds/freedesktop/stereo/complete.oga &> /dev/null &
    else
        echo -e "\a" 
    fi
}

send_notification() {
    local title="$1"
    local msg="$2"
    play_audio
    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$msg" -i "timer" -u critical
    fi
}

# --- Format & Parsing ---
format_time() {
    local T=$1
    printf "%02d:%02d:%02d" $((T/3600)) $(( (T%3600)/60 )) $((T%60))
}

parse_time() {
    local input="$1"
    local h=$(echo "$input" | grep -ioE '[0-9]+h' | tr -d 'hH' || echo 0)
    local m=$(echo "$input" | grep -ioE '[0-9]+m' | tr -d 'mM' || echo 0)
    local s=$(echo "$input" | grep -ioE '[0-9]+s' | tr -d 'sS' || echo 0)
    
    if [[ $h == 0 && $m == 0 && $s == 0 && "$input" =~ ^[0-9]+$ ]]; then m=$input; fi
    echo $(( h * 3600 + m * 60 + s ))
}

draw_progress_bar() {
    local current=$1
    local total=$2
    [[ $total -eq 0 ]] && total=1 
    local width=30 
    
    local pct=$(( current * 100 / total ))
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    
    # Format the raw seconds into MM:SS
    local cur_fmt tot_fmt
    printf -v cur_fmt "%02d:%02d" $((current / 60)) $((current % 60))
    printf -v tot_fmt "%02d:%02d" $((total / 60)) $((total % 60))
    
    # Pure Bash string replication
    local filled_bar empty_bar
    [[ $filled -gt 0 ]] && printf -v filled_bar "%${filled}s" || filled_bar=""
    [[ $empty -gt 0 ]] && printf -v empty_bar "%${empty}s" || empty_bar=""
    
    # Modern Unicode block characters
    filled_bar=${filled_bar// /█}
    empty_bar=${empty_bar// /░}
    
    # ANSI Color Codes
    local color="\e[32m" # Green 
    local reset="\e[0m"
    
    # Print with time format (MM:SS / MM:SS)
    printf "\r[${color}%s%s${reset}] %3d%%\n (%s / %s)\n" \
        "$filled_bar" "$empty_bar" "$pct" "$cur_fmt" "$tot_fmt"
}

# ==============================================================================
# TIMER ENGINES
# ==============================================================================

run_countdown() {
    local total_secs=$1
    local label="${2:-Timer}"
    local current_secs=$total_secs
    local paused=0

    clear
    tput civis
    
    while [ $current_secs -gt 0 ]; do
        echo "$label: $(format_time $current_secs)" > "$STATUS_FILE"

        local color=$GREEN
        [[ $current_secs -le 10 ]] && color=$RED
        
        tput cup 0 0
        printf "${CYAN}${BOLD}=== %s ===${RESET}\033[K\n\n" "$label"
        
        if [[ $paused -eq 1 ]]; then
            echo -e "${YELLOW}⏸  $(format_time $current_secs) [PAUSED]${RESET} $(draw_progress_bar $current_secs $total_secs)\033[K"
        else
            echo -e "${color}⏳ $(format_time $current_secs)${RESET} $(draw_progress_bar $current_secs $total_secs)\033[K"
        fi
        
        echo -e "\n${BLUE}[p]ause  [s]kip  [r]eset  [q]uit${RESET}\033[J"
        
        if IFS= read -r -t 1 -n 1 -s key; then
            case "$key" in
                p) paused=$((1 - paused)) ;;
                s) current_secs=0; break ;;       
                r) current_secs=$total_secs ;;    
                q) 
                   echo -en "\n${RED}Are you sure you want to quit? [y/N]${RESET} "
                   IFS= read -r -n 1 -s confirm
                   if [[ "${confirm,,}" == "y" ]]; then cleanup; fi
                   ;;
            esac
        else
            if [[ $paused -eq 0 ]]; then ((current_secs--)); fi
        fi
    done

    echo -e "\n\033[K${MAGENTA}⏰ 00:00:00 - DONE!${RESET}\033[K"
    send_notification "Timer Complete" "$label has finished!"
    rm -f "$STATUS_FILE"
}

run_stopwatch() {
    local elapsed=0
    local paused=0
    clear; tput civis

    while true; do
        echo "Stopwatch: $(format_time $elapsed)" > "$STATUS_FILE"
        
        tput cup 0 0
        echo -e "${BLUE}${BOLD}=== ⏱️ Stopwatch ===${RESET}\033[K\n"
        
        if [[ $paused -eq 1 ]]; then
            echo -e "${YELLOW}⏸  $(format_time $elapsed) [PAUSED]${RESET}\033[K"
        else
            echo -e "${CYAN}⏱️  $(format_time $elapsed)${RESET}\033[K"
        fi
        
        echo -e "\n${BLUE}[p]ause  [s]top  [q]uit${RESET}\033[K\n"
        echo -en "\033[J"

        if IFS= read -r -t 1 -n 1 -s key; then
            case "$key" in
                p) paused=$((1 - paused)) ;;
                s) break ;; 
                q) 
                   echo -en "\n${RED}Are you sure you want to quit? [y/N]${RESET} "
                   IFS= read -r -n 1 -s confirm
                   if [[ "${confirm,,}" == "y" ]]; then cleanup; fi
                   ;;
            esac
        else
            if [[ $paused -eq 0 ]]; then ((elapsed++)); fi
        fi
    done

    echo -e "\n\033[K${MAGENTA}⏹ Stopwatch Stopped at $(format_time $elapsed)${RESET}"
    read -n 1 -s -p "Press any key to close..."
    cleanup
}

run_pomodoro() {
    local w_secs=$1
    local b_secs=$2
    local cycle=1
    
    while true; do
        run_countdown $w_secs "🍅 Pomodoro (Cycle $cycle)"
        
        clear
        echo -e "${RED}${BOLD}🍅 Pomodoro - Cycle $cycle complete!${RESET}"
        echo -e "\nPress ${GREEN}[Enter]${RESET} to start break, or ${YELLOW}[q]${RESET} to quit..."
        IFS= read -r -n 1 -s key
        [[ "$key" == "q" ]] && cleanup

        run_countdown $b_secs "☕ Short Break (Cycle $cycle)"
        
        clear
        echo -e "${BLUE}${BOLD}☕ Break complete!${RESET}"
        echo -e "\nPress ${GREEN}[Enter]${RESET} for next cycle, or ${YELLOW}[q]${RESET} to quit..."
        IFS= read -r -n 1 -s key
        [[ "$key" == "q" ]] && cleanup
        ((cycle++))
    done
}

# ==============================================================================
# HELPERS & ROUTERS
# ==============================================================================

SCRIPT_PATH="$(command -v "$0" 2>/dev/null || echo "$0")"
SCRIPT_PATH="$(realpath "$SCRIPT_PATH" 2>/dev/null || readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"

spawn() {
    # systemd-run launches the terminal completely outside the current process tree
    systemd-run --user --quiet $TERMINAL_CMD bash "$SCRIPT_PATH" "$@"
    exit 0
}

# HELPER: Show CLI Usage
show_help() {
    echo -e "${CYAN}${BOLD}QTimer - Terminal Timer & Stopwatch${RESET}\n"
    echo -e "Usage: $(basename "$0") [COMMAND] [ARGS...]\n"
    echo -e "${BOLD}Commands:${RESET}"
    echo -e "  ${GREEN}c, countdown <time>${RESET}   Start a countdown (e.g., 10m, 1h30m)"
    echo -e "  ${GREEN}s, stopwatch${RESET}          Start a stopwatch"
    echo -e "  ${GREEN}p, pomodoro <w> <b>${RESET}   Start a pomodoro (e.g., 25m 5m)"
    echo -e "  ${GREEN}preset <name>${RESET}         Run a saved preset by exact name"
    echo -e "  ${GREEN}-h, --help${RESET}            Show this help message\n"
    echo -e "Run without arguments to launch the interactive FZF menu."
}

# HELPER: CLI Args Router
execute_cli() {
    case "$1" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        c|countdown)
            local secs=$(parse_time "$2")
            if [[ $secs -gt 0 ]]; then 
                run_countdown $secs "Custom Timer ($2)"
                read -n 1 -s -p "Press any key to close..."
            else 
                echo -e "${RED}Invalid time format.${RESET}"
            fi
            ;;
        s|stopwatch)
            run_stopwatch
            ;;
        p|pomodoro)
            local w=$(parse_time "${2:-25m}")
            local b=$(parse_time "${3:-5m}")
            run_pomodoro $w $b
            ;;
        preset)
            local p_secs=$(grep -F "$2|" "$PRESETS_FILE" | cut -d'|' -f2 | head -n 1)
            if [[ -n "$p_secs" ]]; then 
                run_countdown $p_secs "$2"
                read -n 1 -s -p "Press any key to close..."
            else 
                echo -e "${RED}Preset not found.${RESET}"
            fi
            ;;
        --run-countdown) run_countdown "$2" "$3"; read -n 1 -s -p "Press any key to close..."; cleanup ;;
        --run-stopwatch) run_stopwatch ;;
        --run-pomodoro) run_pomodoro "$2" "$3" ;;
        *)
            echo -e "${RED}Unknown command.${RESET} Use -h or --help for usage."
            exit 1
            ;;
    esac
}

# HELPER: FZF Tool Options Router
execute_tool() {
    local choice="$1"

    case "$choice" in
        *"Pomodoro"*)
            local p_choice=$(show_menu "Pomodoro > " "🍅 Pomodoro" "1. ⏱️ Classic (25m / 5m)\n2. ⚙️  Custom Intervals\n3. 🔙 Back")
            if [[ -z "$p_choice" || "$p_choice" == *"Back"* ]]; then return; fi
            
            if [[ "$p_choice" == *"Classic"* ]]; then
                spawn --run-pomodoro $((25*60)) $((5*60))
            else
                clear; read -p "Work duration (e.g. 45m): " w_input
                read -p "Break duration (e.g. 10m): " b_input
                local ws=$(parse_time "$w_input")
                local bs=$(parse_time "$b_input")
                if [[ $ws -gt 0 && $bs -gt 0 ]]; then spawn --run-pomodoro $ws $bs; fi
            fi
            ;;
        *"Custom Countdown"*)
            clear; read -p "Enter time (e.g., 10m, 1h30m): " t_input
            local secs=$(parse_time "$t_input")
            if [[ $secs -gt 0 ]]; then spawn --run-countdown $secs "Timer ($t_input)"; fi
            ;;
        *"Stopwatch"*)
            spawn --run-stopwatch
            ;;
        *"Presets Manager"*)
            local pm_choice=$(show_menu "Presets > " "📁 Presets" "1. 🚀 Run\n2. ➕ Create\n3. 🗑  Delete\n4. 🔙 Back")
            if [[ -z "$pm_choice" || "$pm_choice" == *"Back"* ]]; then return; fi
            
            if [[ "$pm_choice" == *"Run"* ]]; then
                local preset=$(cat "$PRESETS_FILE" | fzf --prompt="Run > " --border=rounded --delimiter="|" --with-nth=1 --bind "esc:abort")
                if [[ -n "$preset" ]]; then
                    local p_name=$(echo "$preset" | cut -d'|' -f1)
                    local p_secs=$(echo "$preset" | cut -d'|' -f2)
                    spawn --run-countdown $p_secs "$p_name"
                fi
            elif [[ "$pm_choice" == *"Create"* ]]; then
                clear; read -p "Name: " p_name; read -p "Duration (e.g. 10m): " p_dur
                local p_secs=$(parse_time "$p_dur")
                if [[ $p_secs -gt 0 && -n "$p_name" ]]; then echo "$p_name|$p_secs" >> "$PRESETS_FILE"; fi
            elif [[ "$pm_choice" == *"Delete"* ]]; then
                local del_preset=$(cat "$PRESETS_FILE" | fzf --prompt="Delete > " --border=rounded --delimiter="|" --with-nth=1 --bind "esc:abort")
                if [[ -n "$del_preset" ]]; then grep -vF "$del_preset" "$PRESETS_FILE" > "${PRESETS_FILE}.tmp" && mv "${PRESETS_FILE}.tmp" "$PRESETS_FILE"; fi
            fi
            ;;
        *"Help"*)
            clear
            show_help
            echo -e "\nPress any key to return..."
            read -n 1 -s
            ;;
    esac
}

show_menu() {
    echo -e "$3" | fzf --prompt="$1" --header=" $2 " \
        --border=rounded --margin=5% --padding=1 --info=hidden \
        --bind "esc:abort" \
        --color="border:#5eacd3,header:#89b4fa,prompt:#a6e3a1"
}

main_menu() {
    while true; do
        clear
        local choice=$(show_menu "Select Mode > " "⚡ QTimer Menu" "1. 🍅 Pomodoro\n2. ⏳ Custom Countdown\n3. ⏱️ Stopwatch\n4. 📁 Presets Manager\n5. ℹ️  Help / Usage")
        
        if [[ -z "$choice" ]]; then clear; exit 0; fi

        execute_tool "$choice"
    done
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

if [[ -n "$1" ]]; then
    execute_cli "$@"
else
    main_menu
fi

