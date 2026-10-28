#!/bin/bash

# Configuration
SCRIPTS_DIR="$HOME/.productivity-old/scripts"
export TERMINAL="foot" 
AUTOSYNC_STATE_FILE="$HOME/.productivity-old/.autosync"
LOG_FILE="$HOME/.productivity-old/hub.log"

# Configuration for Sync
SYNC_DIR="$HOME/.productivity-old/data"
BRANCH="main"
GIT_USER_NAME="Productivity Hub"
GIT_USER_EMAIL="hub@local"

show_help() {
    cat << 'EOF'
Productivity Hub Helper
=======================
Usage: ./productivity-oldv6.sh [OPTION]

CLI Options:
  -n, --notes    Launch integrated notetaker
  -t, --timers   Launch quick timers
  -r, --routine  Launch routine TUI
  -k, --tasks    Launch tuxedo wrapper
  -m, --reminder Launch quick reminder
  -s, --sync     Manually force sync data
  -a, --autosync Toggle automatic syncing
  -l, --logs     View launch and sync logs
  -h, --help     Show this help message and exit

If no option is passed, the interactive GUI menu will launch.
EOF
}

sync_data() {
    export GIT_TERMINAL_PROMPT=0
    #notify-send "Productivity Hub" "Starting sync process..."
    
    mkdir -p "$SYNC_DIR"
    cd "$SYNC_DIR" || { notify-send -u critical "Sync Error" "Cannot access $SYNC_DIR"; return 1; }

    # Module 1: Initialize Repository
    if [ ! -d ".git" ]; then
        git init
        git config user.name "$GIT_USER_NAME"
        git config user.email "$GIT_USER_EMAIL"
        touch .sync_keep
        git add .sync_keep
        git commit -m "Initial automated commit"
    fi

    # Module 2: Setup Remote & Branch (User Input)
    CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null)
    
    if [ -z "$CURRENT_REMOTE" ]; then
        notify-send -t 0 -e "Productivity Hub" "Remote missing. Awaiting user input..."
        USER_REMOTE_URL=$(echo "" | fuzzel --dmenu --prompt="Git Remote URL ❯ " --lines=0)
        
        if [ -z "$USER_REMOTE_URL" ]; then
            notify-send -u critical "Sync Error" "No remote URL provided. Aborting sync."
            return 1
        fi
        
        git remote add origin "$USER_REMOTE_URL"
        REMOTE_URL="$USER_REMOTE_URL"
    else
        REMOTE_URL="$CURRENT_REMOTE"
    fi

    git checkout -B "$BRANCH" >/dev/null 2>&1

    # Module 3: Core Sync Handling
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        notify-send -e -t 3000  "Productivity Hub" "Offline Mode: Network unavailable."
        return 0
    fi

    if [ -n "$(git status --porcelain)" ]; then
        git add .
        git commit -m "Auto-commit: $(date +'%Y-%m-%d %H:%M:%S')"
    fi

    if ! git fetch origin "$BRANCH" >/dev/null 2>&1; then
        if git push -u origin "$BRANCH"; then
            notify-send -e -t 3000 "Productivity Hub" "Initial branch pushed to remote."
        else
            notify-send -u -t 0  critical "Sync Error" "Failed to push initial branch. Check sync.log."
        fi
	return 0
    fi

    COUNTS=$(git rev-list --left-right --count "$BRANCH...origin/$BRANCH" 2>/dev/null)
    AHEAD=$(echo "$COUNTS" | awk '{print $1}')
    BEHIND=$(echo "$COUNTS" | awk '{print $2}')

    # Fallback if rev-list failed
    AHEAD=${AHEAD:-0}
    BEHIND=${BEHIND:-0}

    if [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -eq 0 ]; then
        notify-send -e -t 1000 "Productivity Hub" "Data is already synchronized."
        return 0
    elif [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -gt 0 ]; then
        git pull --rebase origin "$BRANCH"
        notify-send -e -t 3000 "Productivity Hub" "Pulled latest updates from remote."
        return 0
    elif [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -eq 0 ]; then
        git push origin "$BRANCH"
        notify-send -e -t 1000 "Productivity Hub" "Pushed local updates to remote."
        return 0
    fi

    # Module 4: Rebase & Conflict Handling
    notify-send  -e -t 3000 "Productivity Hub" "Divergence detected. Attempting safe rebase..."
    
    if git rebase origin/"$BRANCH"; then
        git push origin "$BRANCH"
        notify-send -e -t 2000 "Productivity Hub" "Rebase and push successful."
    else
        notify-send -u critical -t 0  "Productivity Hub" "Conflict detected. Applying local preference..."
        git checkout --theirs .
        git add .
        
        if git rebase --continue; then
            git push origin "$BRANCH"
            notify-send -e -t 3000 "Productivity Hub" "Conflict resolved automatically. Sync complete."
        else
            git rebase --abort
            notify-send -u critical "Sync Error" "Rebase failed. Manual review required!"
            return 1
        fi
    fi
}

# ----------------------------------------
# Autosync Logic & Wrappers
# ----------------------------------------

toggle_autosync() {
    if [ -f "$AUTOSYNC_STATE_FILE" ]; then
        rm -f "$AUTOSYNC_STATE_FILE"
        notify-send -e -t 3000 "Productivity Hub" "Autosync Disabled"
    else
        touch "$AUTOSYNC_STATE_FILE"
        notify-send -e -t 3000 "Productivity Hub" "Autosync Enabled"
    fi
    # Relaunch the menu to immediately reflect the new status
    exec "$0"
}

launch_and_sync() {
    local script_path="$1"
    local script_name=$(basename "$script_path" .sh)
  
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching: $script_name" >> "$LOG_FILE" 
    # Launch the terminal with the sub-script's name as the app-id (-a)
    $TERMINAL -a "$script_name" -e bash -l -c "$script_path"

    # Check if autosync is enabled after the terminal closes
    if [ -f "$AUTOSYNC_STATE_FILE" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Autosync triggered by $script_name" >> "$LOG_FILE"
	sync_data > "$HOME/.productivity-old/sync.log" 2>&1 &
        disown
    fi
}

# ----------------------------------------
# CLI Argument Parsing
# ----------------------------------------
if [ $# -gt 0 ]; then
    case "$1" in
        -n|--notes)
            launch_and_sync "$SCRIPTS_DIR/integrated-notetaker.sh"
            exit 0
            ;;
        -t|--timers)
            launch_and_sync "$SCRIPTS_DIR/quick-timers.sh"
            exit 0
            ;;
        -r|--routine)
            launch_and_sync "$SCRIPTS_DIR/routine-tui.sh"
            exit 0
            ;;
        -k|--tasks)
            launch_and_sync "$SCRIPTS_DIR/tuxedo-wrapper.sh"
            exit 0
            ;;
	-m|--reminder)
            launch_and_sync "$SCRIPTS_DIR/quickreminder.sh"
            exit 0
            ;;
        -s|--sync)
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Force Sync triggered via CLI" >> "$LOG_FILE"
            sync_data >> "$LOG_FILE" 2>&1
            exit 0
            ;;
        -a|--autosync)
            toggle_autosync
            exit 0
            ;;
        -l|--logs)
            $TERMINAL -a "view-logs" -e less "$LOG_FILE"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Try '$0 --help' for more information."
            exit 1
            ;;
    esac
fi

# Determine dynamic menu label for Autosync
if [ -f "$AUTOSYNC_STATE_FILE" ]; then
    AUTOSYNC_LABEL="🔄 Autosync: [ON]"
else
    AUTOSYNC_LABEL="🔄 Autosync: [OFF]"
fi

# Define the menu options
OPTIONS="📝 Notes\n⏱️ Timers\n🔄 Routine\n✅ Tasks\n🔔 Reminder\n☁️ Force Sync\n$AUTOSYNC_LABEL\n📄 View Logs\n❓ Help"

# Pipe options into fuzzel (dmenu mode) and capture the selection
CHOICE=$(echo -e "$OPTIONS" | fuzzel --dmenu --prompt="Productivity Hub ❯ " --lines=9)

# Route the choice
case "$CHOICE" in
    "📝 Notes")
        launch_and_sync "$SCRIPTS_DIR/integrated-notetaker.sh" &
        ;;
    "⏱️ Timers")
        launch_and_sync "$SCRIPTS_DIR/quick-timers.sh" &
        ;;
    "🔄 Routine")
        launch_and_sync "$SCRIPTS_DIR/routine-tui.sh" &
        ;;
    "✅ Tasks")
        launch_and_sync "$SCRIPTS_DIR/tuxedo-wrapper.sh" &
        ;;
    "🔔 Reminder")
        launch_and_sync "$SCRIPTS_DIR/quickreminder.sh" &
        ;;
    "☁️ Force Sync")
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Force Sync triggered manually" >> "$LOG_FILE"
	sync_data >> "$LOG_FILE" 2>&1 &
        disown
        ;;
    "$AUTOSYNC_LABEL")
        toggle_autosync
        ;;
    "📄 View Logs")
        $TERMINAL -a "view-logs" -e less "$LOG_FILE" &
        ;;
    "❓ Help")
        $TERMINAL -a "view-help" -e sh -c "$0 --help | less" &
        ;;
    *)
        exit 0
        ;;
esac

