#!/bin/bash

# Exit on pipeline failures
set -uo pipefail

TODO_DIR="${TUXEDO_DIR:-$HOME/Todo}"
TODO_FILE="$TODO_DIR/todo.txt"
CHECKLIST_DIR="$TODO_DIR/checklists"
ACTIVE_CHECKLIST_DIR="$CHECKLIST_DIR/active"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tuxedo-wrapper"
CONFIG_FILE="$CONFIG_DIR/config"
mkdir -p "$TODO_DIR" "$CHECKLIST_DIR" "$ACTIVE_CHECKLIST_DIR"
SYNC_TRIGGERED=false

# ==========================================
# 1. SETUP & CONFIGURATION
# ==========================================
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "AUTO_SYNC=false" > "$CONFIG_FILE"
fi
source "$CONFIG_FILE"

# ==========================================
# 2. DEPENDENCY CHECKS
# ==========================================
check_dependencies() {
    local deps=("tuxedo" "fzf" "git")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required dependency '$cmd' is not installed." >&2
            exit 1
        fi
    done
}

# ==========================================
# 3. CORE FUNCTIONS
# ==========================================
send_notification() {
    local message="$1"
    local status="${2:-success}"

    if ! command -v notify-send >/dev/null 2>&1; then
        return 0
    fi

    if [[ "$status" == "error" ]]; then
        notify-send "Tuxedo" "$message" -u critical --icon=realtimesync
    else
        notify-send "Tuxedo" "$message" -t 1000 -u low --icon=freefilesync
    fi
}

run_background_sync() {
    local LOCK_DIR="$CONFIG_DIR/sync.lock.d"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        return 0
    fi
    (
        trap '' HUP
        if git_sync quiet; then
            send_notification "Auto-sync complete!" "success"
        else
            send_notification "Auto-sync failed!" "error"
        fi
        rmdir "$LOCK_DIR"
    ) </dev/null >/dev/null 2>&1 &
    disown -h $! 2>/dev/null || disown
}

trigger_sync() {
    local mode=${1:-"background"}
    if [[ "$AUTO_SYNC" == "true" && "$SYNC_TRIGGERED" == "false" ]]; then
        SYNC_TRIGGERED=true
        if [[ "$mode" == "foreground" ]]; then
            if git_sync quiet; then
                send_notification "Sync complete!" "success"
            else
                send_notification "Sync failed!" "error"
            fi
        else
            run_background_sync
        fi
    fi
}

launch_tuxedo() {
    tuxedo
    trigger_sync background
}

add_quick_todo() {
    clear
    echo -e "╭──────────────────────────────────────╮"
    echo -e "│              QUICK TASK              │"
    echo -e "╰──────────────────────────────────────╯"
    echo ""
    echo "--- Recent Tasks ---"
    if [[ -f "$TODO_FILE" ]]; then
         tail -n 3 "$TODO_FILE" | awk '{
            if ($0 ~ /^[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+)?\(A\)/) print "\033[1;31m" $0 "\033[0m"
            else if ($0 ~ /^[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+)?\(B\)/) print "\033[1;33m" $0 "\033[0m"
            else if ($0 ~ /^[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+)?\(C\)/) print "\033[1;32m" $0 "\033[0m"
            else if ($0 ~ /^[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+)?\([D-Z]\)/) print "\033[1;36m" $0 "\033[0m"   
	    else print $0
        }'
    else
        echo "No tasks found."
    fi
    echo "--------------------"
    
    echo -e "Tip: You can include +PROJECT and @CONTEXT in your task"
    read -e -p "❯ Enter task: " TASK
    if [[ -n "$TASK" ]]; then
        read -e -p "❯ Priority (A-Z, leave blank for none): " PRIO
        PRIO=$(echo "$PRIO" | tr 'a-z' 'A-Z' | grep -o '^[A-Z]$' || true)
        if [[ -n "$PRIO" ]]; then
            TASK="($PRIO) $TASK"
        fi
        tuxedo add "$TASK"
        echo -e "\033[1;32mTask added successfully!\033[0m"
        trigger_sync background
    fi
}

git_sync() {
    local quiet=${1:-""}
    [[ "$quiet" != "quiet" ]] && echo "Syncing with git..."
    
    cd "$TODO_DIR" || exit 1
    
    if [[ -f ".git/index.lock" ]]; then
        [[ "$quiet" != "quiet" ]] && echo "Git is currently syncing in the background."
        return 1
    fi

    if [[ ! -d ".git" ]]; then
        git init > /dev/null 2>&1
        git branch -M main > /dev/null 2>&1
        [[ "$quiet" != "quiet" ]] && echo "Initialized new git repository."
    fi

    if ! git remote | grep -q "^origin$"; then
        if [[ "$quiet" == "quiet" ]] || [ ! -t 0 ]; then
            git add todo.txt checklists/ > /dev/null 2>&1
            if ! git diff --cached --quiet; then
                git commit -m "Auto-sync: $(date +'%Y-%m-%d %H:%M:%S')" > /dev/null 2>&1
            fi
            return 0
        fi

        clear
        echo -e "\nGit remote 'origin' is not configured."
        read -e -p "❯ Enter remote repository URL (or leave blank for local-only): " REMOTE_URL
        if [[ -n "$REMOTE_URL" ]]; then
            git remote add origin "$REMOTE_URL"
            [[ "$quiet" != "quiet" ]] && echo "Remote 'origin' added successfully."
        else
            [[ "$quiet" != "quiet" ]] && { echo "Skipping remote sync. Storing locally."; sleep 1; }
            git add todo.txt checklists/ > /dev/null 2>&1
            ! git diff --cached --quiet && git commit -m "Auto-sync: $(date +'%Y-%m-%d %H:%M:%S')" > /dev/null 2>&1
            return 0
        fi
    fi

    git add todo.txt checklists/ > /dev/null 2>&1
    if ! git diff --cached --quiet; then
        git commit -m "Auto-sync: $(date +'%Y-%m-%d %H:%M:%S')" > /dev/null 2>&1
    fi
    
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then
        [[ "$quiet" != "quiet" ]] && echo "Setting upstream branch and pushing..."
        git push -u origin main > /dev/null 2>&1 || return 1
    else
        git fetch origin main > /dev/null 2>&1
        git pull --rebase origin main > /dev/null 2>&1 || { 
		git rebase --abort > /dev/null 2>&1
		send_notification "Git merge conflict! Manual intervention required." "error"       
		return 1
       	}
        
        LOCAL_COMMIT=$(git rev-parse HEAD)
        REMOTE_COMMIT=$(git rev-parse origin/main)
        if [[ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]]; then
            git push origin main > /dev/null 2>&1 || return 1
        fi
    fi
    
    [[ "$quiet" != "quiet" ]] && { echo "Git sync complete!"; sleep 1; }
    return 0
}

run_checklist() {
    local target_file="$1"
    while true; do
	local tmp_file
        tmp_file=$(mktemp)
        grep "^\[ \]" "$target_file" > "$tmp_file" 2>/dev/null || true
        grep "^\[x\]" "$target_file" >> "$tmp_file" 2>/dev/null || true
        grep -v "^\[ \]" "$target_file" | grep -v "^\[x\]" >> "$tmp_file" 2>/dev/null || true
        mv "$tmp_file" "$target_file"

        # Extract items, preserving exact line numbers for precise sed replacements
        local items
        items=$(cat -n "$target_file")
        
        # Select items using fzf multi-select (-m)
        local selections
        selections=$(echo "$items" | fzf -m \
            --prompt="❯ Checklist (ESC to save): " \
            --header="TAB: multi-select | ENTER: toggle selected | ESC: save & exit" \
            --layout=reverse --height=60%)
        
        # If nothing is selected (ESC pressed), break the loop and save
        [[ -z "$selections" ]] && break
        
        # Process each selected line
        while IFS= read -r selection; do
            local line_num
            line_num=$(echo "$selection" | awk '{print $1}')
            
            # Toggle the checkbox state in-place
            if sed -n "${line_num}p" "$target_file" | grep -q "\[ \]"; then
                sed -i "${line_num}s/\[ \]/\[x\]/" "$target_file"
            elif sed -n "${line_num}p" "$target_file" | grep -q "\[x\]"; then
                sed -i "${line_num}s/\[x\]/\[ \]/" "$target_file"
            fi
        done <<< "$selections"
    done
    
    trigger_sync background
}

checklists_menu() {
    while true; do
        options=(
            "1. Start New Checklist from Template"
            "2. Create New Blank Checklist"
            "3. Resume Active Checklist"
            "4. Send Unchecked Items to Tuxedo"
            "5. Delete Active Checklist"
            "6. Back to Main Menu"
        )
        
        choice=$(printf "%s\n" "${options[@]}" | fzf \
            --prompt="❯ Checklists Menu: " \
            --header="Manage your checklists" \
            --height=50% --layout=reverse --border)

        [[ -z "$choice" ]] && return 0

        case "$choice" in
            1*) 
                # Pick template and create active instance
                local template
                template=$(ls "$CHECKLIST_DIR"/*.txt 2>/dev/null | fzf --prompt="❯ Select Template: " -1)
                [[ -n "$template" ]] && {
                    local base_name
                    base_name=$(basename "$template" .txt)
                    local new_active="$ACTIVE_CHECKLIST_DIR/${base_name}_$(date +%Y%m%d_%H%M).txt"
                    cp "$template" "$new_active"
                    run_checklist "$new_active"
                }
                ;;
            2*)
                # Create New Blank Checklist
                read -e -p "❯ Enter new checklist name: " cl_name
                if [[ -n "$cl_name" ]]; then
                    local safe_name
                    safe_name=$(echo "$cl_name" | tr ' ' '_')
                    local new_active="$ACTIVE_CHECKLIST_DIR/${safe_name}_$(date +%Y%m%d_%H%M).txt"
                    
                    # Open editor for user to add tasks
                    ${EDITOR:-nano} "$new_active"
                    
                    # Auto-format: remove blank lines and prefix tasks with "[ ] " if missing
                    if [[ -f "$new_active" ]]; then
                        sed -i -e '/^$/d' -e '/^\[[ x]\]/! s/^/[ ] /' "$new_active"
                        run_checklist "$new_active"
                    fi
                fi
                ;;
            3*) 
                # Resume existing active checklist
                local active_file
                active_file=$(ls "$ACTIVE_CHECKLIST_DIR"/*.txt 2>/dev/null | fzf --prompt="❯ Select Active: " -1)
                [[ -n "$active_file" ]] && run_checklist "$active_file"
                ;;
	    4*) 
                # Export selected unchecked items to tuxedo format
                local active_file
                active_file=$(ls "$ACTIVE_CHECKLIST_DIR"/*.txt 2>/dev/null | fzf --prompt="❯ Export from: " -1)
                
                if [[ -n "$active_file" ]]; then
                    local base_name
                    base_name=$(basename "$active_file" | cut -d'_' -f1)
                    
                    # Grab only unchecked items and strip the brackets
                    local unchecked
		    unchecked=$(grep "^\[ \]" "$active_file" | sed -e 's/^\[ \] //' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r//')
                    
                    if [[ -z "$unchecked" ]]; then
                        echo "No unchecked items found."
                        sleep 1
                        continue
                    fi
                    
                    # fzf multi-select for the user to pick which items to export
                    local selected_tasks
                    selected_tasks=$(echo "$unchecked" | fzf -m \
                        --prompt="❯ Select tasks to export: " \
                        --header="TAB: multi-select | ENTER: export | ESC: cancel" \
                        --layout=reverse --height=60%)
                    
                    if [[ -n "$selected_tasks" ]]; then
                        while IFS= read -r task; do
                            tuxedo add "$task +checklist @$base_name"
                        done <<< "$selected_tasks"
                        
                        echo "Exported selected tasks to Tuxedo!"
                        sleep 1
                        trigger_sync background
                    fi
                fi
                ;;
            5*)
                # Delete Active Checklist
                local active_file
                active_file=$(ls "$ACTIVE_CHECKLIST_DIR"/*.txt 2>/dev/null | fzf --prompt="❯ Delete Checklist: " -1)
                if [[ -n "$active_file" ]]; then
                    read -e -p "Are you sure you want to delete $(basename "$active_file")? (y/N): " confirm
                    if [[ "${confirm,,}" == "y" ]]; then
                        rm -f "$active_file"
                        echo "Checklist deleted."
                        sleep 1
                        trigger_sync background
                    fi
                fi
                ;;
            6*) return 0 ;;
        esac
    done
}

toggle_auto_sync() {
    if [[ "$AUTO_SYNC" == "true" ]]; then
        sed -i -E 's/^AUTO_SYNC=.*/AUTO_SYNC=false/' "$CONFIG_FILE"
        echo "Auto-sync disabled."
    else
        sed -i -E 's/^AUTO_SYNC=.*/AUTO_SYNC=true/' "$CONFIG_FILE"
	echo "Auto-sync enabled."
    fi
    source "$CONFIG_FILE"
    sleep 1
}

# ==========================================
# 4. REMINDERS & CRON
# ==========================================
check_reminders() {
    local mode=$1
    local task_count=0
    local title=""
    local message=""
    
    [[ ! -f "$TODO_FILE" ]] && return 0
    
    local pending_tasks
    pending_tasks=$(grep -v '^x ' "$TODO_FILE" || true)
    [[ -z "$pending_tasks" ]] && return 0

    if [[ "$mode" == "today" ]]; then
        local today_date
        today_date=$(date +%Y-%m-%d)
        task_count=$(echo "$pending_tasks" | grep -c "due:$today_date" || true)
        title="Tasks Due Today"
        message="You have $task_count task(s) due today."
        
    elif [[ "$mode" == "overdue" ]]; then
        local today_epoch
        today_epoch=$(date -d "$(date +%Y-%m-%d)" +%s)
        
        while read -r line; do
            local due_date
            due_date=$(echo "$line" | grep -o 'due:[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | cut -d':' -f2 || true)
            if [[ -n "$due_date" ]]; then
                local due_epoch
                due_epoch=$(date -d "$due_date" +%s 2>/dev/null || echo "")
                if [[ -n "$due_epoch" && "$due_epoch" -lt "$today_epoch" ]]; then
                    ((task_count++))
                fi
            fi
        done <<< "$(echo "$pending_tasks" | grep 'due:' || true)"
        
        title="Overdue Tasks"
        message="You have $task_count overdue task(s)."
    fi

    # Only fire notification if there is at least 1 task
    if [[ "$task_count" -gt 0 ]]; then
        if command -v notify-send >/dev/null 2>&1; then
            local action
            action=$(notify-send -t 0 "$title" "$message" \
                --action="open=Open Tuxedo" \
                --action="dismiss=Dismiss" \
                --icon=appointment-soon -u normal)

            if [[ "$action" == "open" ]]; then
                launch_tuxedo
            fi
        else
            echo -e "=== $title ===\n$message"
        fi
    fi
}

manage_cron_toggle() {
    
	# Define the backup path and create the backup safely
    local backup_file="/tmp/crontab_backup_$(date +%s).bak"
    crontab -l > "$backup_file" 2>/dev/null || true
    echo "Crontab backed up to: $backup_file"
    
    local mode=$1
    local script_path
    script_path=$(readlink -f "$0")
    
    local tag_today="# TUXEDO_WRAPPER_CRON_TODAY"
    local tag_overdue="# TUXEDO_WRAPPER_CRON_OVERDUE"
    
    if [[ "$mode" == "today" ]]; then
        if crontab -l 2>/dev/null | grep -q "$tag_today"; then
            # Currently ON -> Turn OFF
            (crontab -l 2>/dev/null | grep -v "$tag_today") | crontab -
            echo "Today's reminders disabled."
        else
            # Currently OFF -> Turn ON (daily - every 4 hrs)
            (crontab -l 2>/dev/null | grep -v "$tag_today"; echo "0 */4 * * * $script_path --reminders-today $tag_today") | crontab -
            echo "Today's reminders enabled (daily - every 4 hrs)."
        fi
    elif [[ "$mode" == "overdue" ]]; then
        if crontab -l 2>/dev/null | grep -q "$tag_overdue"; then
            # Currently ON -> Turn OFF
            (crontab -l 2>/dev/null | grep -v "$tag_overdue") | crontab -
            echo "Overdue reminders disabled."
        else
            # Currently OFF -> Turn ON (every 4 hrs)
            (crontab -l 2>/dev/null | grep -v "$tag_overdue"; echo "0 */4 * * * $script_path --reminders-overdue $tag_overdue") | crontab -
            echo "Overdue reminders enabled (every 4 hrs)."
        fi
    fi
    sleep 1.5
}

reminders_menu() {
    while true; do
        # 1. Check current status of crontabs
        local today_status="OFF"
        local overdue_status="OFF"
        
        if crontab -l 2>/dev/null | grep -q "# TUXEDO_WRAPPER_CRON_TODAY"; then
            today_status="ON"
        fi
        
        if crontab -l 2>/dev/null | grep -q "# TUXEDO_WRAPPER_CRON_OVERDUE"; then
            overdue_status="ON"
        fi

        # 2. Build the menu options
        options=(
            "1. Current Day Reminders (Run Now)"
            "2. Overdue Reminders (Run Now)"
            "3. Toggle Auto-Reminders: Today (Currently: $today_status)"
            "4. Toggle Auto-Reminders: Overdue (Currently: $overdue_status)"
            "5. Back to Main Menu"
        )
        
        choice=$(printf "%s\n" "${options[@]}" | fzf \
            --prompt="❯ Reminders Menu: " \
            --header="Select an action (ESC to exit)" \
            --height=50% --layout=reverse --border)

        [[ -z "$choice" ]] && return 0

        # 3. Handle selections
        case "$choice" in
            1*) check_reminders "today" ;;
            2*) check_reminders "overdue" ;;
            3*) manage_cron_toggle "today" ;;
            4*) manage_cron_toggle "overdue" ;;
            5*) return 0 ;;
        esac
    done
}

show_helper() {
    clear
    echo "Tuxedo Wrapper Help"
    echo "-------------------"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -l, --launch            Launch Tuxedo UI"
    echo "  -a, --add               Add a quick todo"
    echo "  -c, --checklists        Open Checklists Menu"
    echo "  -s, --sync              Manually trigger git sync"
    echo "  -t, --toggle-sync       Toggle auto-sync feature"
    echo "  -rt, --reminders-today  Check today's tasks and notify"
    echo "  -ro, --reminders-overdue Check overdue tasks and notify"
    echo "  -h, --help              Show this help message"
    echo ""
    read -p "Press [ENTER] to return..."
}

wrapper_exit() {
    trigger_sync background
    exit 0
}

# ==========================================
# 5. TUI MENU (FZF)
# ==========================================
show_tui() {
    while true; do
        SYNC_TRIGGERED=false
        sync_status="OFF"
        [[ "$AUTO_SYNC" == "true" ]] && sync_status="ON"

        options=(
            "1. Launch Tuxedo"
            "2. Add Quick Todo"
	    "3. Checklists"
            "4. Git Sync (Manual)"
            "5. Toggle Auto-Sync (Currently: $sync_status)"
            "6. Toggle Reminders (Menu)"
            "7. Helper"
            "8. Exit"
        )

        choice=$(printf "%s\n" "${options[@]}" | fzf \
            --prompt="❯ Tuxedo Menu: " \
            --header="Select an action (ESC to exit)" \
            --height=40% --layout=reverse --border)

        [[ -z "$choice" ]] && wrapper_exit

        case "$choice" in
            1*) launch_tuxedo ;;
            2*) add_quick_todo ;;
	    3*) checklists_menu ;;
	    4*) git_sync ;;
            5*) toggle_auto_sync ;;
            6*) reminders_menu ;;
            7*) show_helper ;;
            8*) wrapper_exit ;;
        esac
    done
}

# ==========================================
# 6. CLI ARGUMENT PARSING
# ==========================================
check_dependencies

if [[ $# -gt 0 ]]; then
    case "$1" in
        -l|--launch)              launch_tuxedo ;;
        -a|--add)                 add_quick_todo ;;
	-c|--checklists)          checklists_menu ;;
        -s|--sync)                git_sync quiet ;;
        -t|--toggle-sync)         toggle_auto_sync ;;
        -rt|--reminders-today)    check_reminders "today" ;;
        -ro|--reminders-overdue)  check_reminders "overdue" ;;
        -h|--help)                show_helper ;;
        *)                        echo "Invalid option. Use -h for help."; exit 1 ;;
    esac
else
    show_tui
fi

