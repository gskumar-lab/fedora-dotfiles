#!/bin/bash

# ==========================================
# CONFIGURATION & INITIALIZATION
# ==========================================
QDL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/qdl"
TEMP_DIR="$QDL_DIR/temp"
DL_DIR="$HOME/Downloads"

SESSION_FILE="$QDL_DIR/session.txt"
HISTORY_FILE="$QDL_DIR/history.log"
CANCELED_FILE="$QDL_DIR/canceled.txt"
COMPLETED_FILE="$QDL_DIR/completed.log"
HOOK_SCRIPT="$QDL_DIR/on_complete.sh"

RPC_SECRET="qdl-secret-123"
RPC_PORT="6800"

mkdir -p "$QDL_DIR" "$TEMP_DIR" "$DL_DIR"
touch "$SESSION_FILE" "$HISTORY_FILE" "$CANCELED_FILE" "$COMPLETED_FILE"

# ==========================================
# GENERATE ARIA2 COMPLETION HOOK
# ==========================================
cat << EOF > "$HOOK_SCRIPT"
#!/bin/bash
GID="\$1"
NUM="\$2"
FILE="\$3"

if [ "\$NUM" -gt 0 ] && [ -e "\$FILE" ]; then
    # Move the completed file to the final Downloads directory
    mv "\$FILE" "$DL_DIR/"
    
    BASENAME=\$(basename "\$FILE")
    echo "\$(date '+%Y-%m-%d %H:%M:%S') | \$BASENAME" >> "$COMPLETED_FILE"
    
    # Trigger desktop notification if supported
    if command -v notify-send &> /dev/null; then
        notify-send "Download Complete" "\$BASENAME" --icon=folder-download
    fi
fi

# Auto-shutdown daemon if no active or pending downloads remain
ACTIVE=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:$RPC_SECRET"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '.result | length')
WAITING=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:$RPC_SECRET", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.status == "waiting")] | length')

if [[ "\$ACTIVE" == "0" && "\$WAITING" == "0" ]]; then
    curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:$RPC_SECRET"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
fi
EOF
chmod +x "$HOOK_SCRIPT"

# ==========================================
# DEPENDENCY VALIDATION
# ==========================================
for cmd in aria2c fzf curl jq awk; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "\nError: Required command '$cmd' is not installed."
        exit 1
    fi
done

# ==========================================
# UI & TERMINAL MANAGEMENT
# ==========================================
trap "tput rmcup; clear; exit 1" SIGINT SIGTERM #[cite: 1]

tput smcup #[cite: 1]
clear

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
DIM='\033[2m'
NC='\033[0m' #[cite: 1]

draw_header() {
    clear
    echo -e "${CYAN}╭──────────────────────────────────────╮${NC}" #[cite: 1]
    echo -e "${CYAN}│           QUICK DOWNLOADER           │${NC}" #[cite: 1]
    echo -e "${CYAN}╰──────────────────────────────────────╯${NC}\n" #[cite: 1]
    
    if [ -s "$HISTORY_FILE" ]; then
        echo -e "${DIM}Recent additions:${NC}" #[cite: 1]
        tail -n 3 "$HISTORY_FILE" | awk -F" | " '{print "  " $NF}'
        echo ""
    fi
}

# ==========================================
# DAEMON LIFECYCLE
# ==========================================
is_daemon_running() {
    curl -s --connect-timeout 1 "http://localhost:$RPC_PORT/jsonrpc" >/dev/null 2>&1
}

# Added process-level check to prevent file writing race conditions
is_daemon_process_running() {
    pgrep -f "aria2c.*$RPC_SECRET" > /dev/null 2>&1
}

start_daemon() {
    nohup aria2c --dir="$TEMP_DIR" \
        --input-file="$SESSION_FILE" \
        --save-session="$SESSION_FILE" \
        --save-session-interval=10 \
        --enable-rpc=true \
        --rpc-listen-port="$RPC_PORT" \
        --rpc-secret="$RPC_SECRET" \
        --on-download-complete="$HOOK_SCRIPT" \
        --max-concurrent-downloads=3 \
        --quiet=true < /dev/null > "$QDL_DIR/aria2.log" 2>&1 &
    
    for _ in {1..20}; do
        if is_daemon_running; then return 0; fi
        sleep 0.1
    done
}

if grep -qE "^(http|ftp|magnet)" "$SESSION_FILE" 2>/dev/null; then
    if ! is_daemon_running; then start_daemon; fi
fi

# ==========================================
# MAIN LOOP
# ==========================================
while true; do
    draw_header
    
    MENU="1. Add URL (Quick Download)\n2. Active Progress\n3. Recent History\n4. Completed Downloads\n5. Manage Incomplete Queue\n6. Set Download Speed Limit\n7. Exit"
    CHOICE=$(echo -e "$MENU" | fzf --reverse  --prompt="❯ " --height=12 --border=rounded --info=hidden --color=border:cyan)

    case "$CHOICE" in
        *1.*)
            read -r -p "❯ Paste URL: " URL < /dev/tty
            if [[ ! "$URL" =~ ^(https?|ftp|magnet): ]]; then
                echo -e "\n${RED}✖ Invalid URL format.${NC}\n"
                sleep 1.5; continue
            fi

            echo "$(date '+%Y-%m-%d %H:%M:%S') | $URL" >> "$HISTORY_FILE"
            
            if is_daemon_running; then
                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addUri", "params":["token:'"$RPC_SECRET"'", ["'"$URL"'"]]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
            else
                echo "$URL" >> "$SESSION_FILE"
                start_daemon
            fi
            echo -e "\n${GREEN}✔ Queued successfully!${NC}\n" #[cite: 1]
            sleep 1
            ;;
            
        *2.*)
            if ! is_daemon_running; then
                echo -e "\n${DIM}No active downloads (Daemon is sleeping).${NC}\n"
                read -r -p "Press [ENTER] to return..." < /dev/tty
                continue
            fi
            
            while is_daemon_running; do
                clear
                echo -e "${CYAN}Active Progress (Keys: [q]uit view, [p]ause, [c]ancel):${NC}\n"
                
                PAYLOAD='{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:'"$RPC_SECRET"'"]}'
                RESP=$(curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc")
                
                COUNT=$(echo "$RESP" | jq '.result | length')
                if [[ "$COUNT" == "0" || -z "$COUNT" ]]; then
                    echo "  Queue is emptying (or waiting for peers)..."
                else
                    echo "$RESP" | jq -r '.result[] | 
                    .totalLength as $t | .completedLength as $c | .downloadSpeed as $s |
                    (if ($t|tonumber) > 0 then (($c|tonumber) / ($t|tonumber) * 100) else 0 end) as $pct |
                    (($s|tonumber) / 1024) as $spd |
                    (if .files[0].path != "" then (.files[0].path | split("/") | last) elif .bittorrent.info.name then .bittorrent.info.name else "Metadata Pending..." end) as $name |
                    "  ➜ \($name) | \($pct * 100 | round / 100)% | \($spd * 10 | round / 10) KB/s"'
                fi
                
                read -t 1 -n 1 -s key < /dev/tty
                if [[ $key == "q" ]]; then break; fi
                
                if [[ $key == "p" || $key == "c" ]]; then
                    ACTIVE_LIST=$(echo "$RESP" | jq -r '.result[] | (if .files[0].path != "" then (.files[0].path | split("/") | last) else "Unknown" end) as $name | "\(.gid) | \($name)"')
                    
                    if [ -n "$ACTIVE_LIST" ]; then
                        ACTION_MSG=$([[ $key == "p" ]] && echo "PAUSE" || echo "CANCEL")
                        TARGET=$(echo "$ACTIVE_LIST" | fzf --prompt="Select download to $ACTION_MSG ❯ " --height=10 --border=rounded)
                        
                        if [ -n "$TARGET" ]; then
                            GID=$(echo "$TARGET" | awk -F" | " '{print $1}')
                            
                            if [[ $key == "p" ]]; then
                                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.pause", "params":["token:'"$RPC_SECRET"'", "'"$GID"'"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                            else
                                INFO=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStatus", "params":["token:'"$RPC_SECRET"'", "'"$GID"'"]}' "http://localhost:$RPC_PORT/jsonrpc")
                                T_URL=$(echo "$INFO" | jq -r '.result.files[0].uris[0].uri // empty')
                                
                                if [ -z "$T_URL" ]; then
                                    T_NAME=$(echo "$INFO" | jq -r '(if .bittorrent.info.name then .bittorrent.info.name else (.files[0].path | split("/") | last) end)')
                                    if [ -n "$T_NAME" ]; then
                                        T_URL=$(awk -F" | " '{print $NF}' "$HISTORY_FILE" | grep -iF "$T_NAME" | tail -n 1)
                                    fi
                                fi
                                
                                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.remove", "params":["token:'"$RPC_SECRET"'", "'"$GID"'"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                
                                if [ -n "$T_URL" ]; then
                                    echo "$T_URL" >> "$CANCELED_FILE"
                                fi
                            fi
                            
                            # Auto-shutdown daemon if pausing/canceling leaves the queue empty
                            ACTIVE_C=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '.result | length')
                            WAITING_C=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.status == "waiting")] | length')
                            if [[ "$ACTIVE_C" == "0" && "$WAITING_C" == "0" ]]; then
                                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                            fi
                        fi
                    fi
                fi
            done
            ;;
            
        *3.*)
            echo -e "${DIM}Recent Additions:${NC}\n"
            tail -n 15 "$HISTORY_FILE" | awk -F" | " '{print "  " $1 " - " $NF}'
            echo ""
            read -r -n 1 -p "Press [ENTER] to return, or [c] to clear history... " key < /dev/tty
            if [[ $key == "c" || $key == "C" ]]; then
                > "$HISTORY_FILE"
                echo -e "\n\n${GREEN}✔ History cleared.${NC}"
                sleep 1
            fi
            ;;
            
        *4.*)
            echo -e "${DIM}Completed Downloads (Verified via completion hook):${NC}\n"
            if [ -s "$COMPLETED_FILE" ]; then
                tail -n 15 "$COMPLETED_FILE" | sed 's/^/  ✔ /'
            else
                echo -e "  ${DIM}No completed downloads yet.${NC}"
            fi
            echo ""
            read -r -n 1 -p "Press [ENTER] to return, or [c] to clear completed list... " key < /dev/tty
            if [[ $key == "c" || $key == "C" ]]; then
                > "$COMPLETED_FILE"
                echo -e "\n\n${GREEN}✔ Completed queue cleared.${NC}"
                sleep 1
            fi
            ;;
            
        *5.*)
            while true; do
                clear
                echo -e "${CYAN}╭──────────────────────────────────────╮${NC}"
                echo -e "${CYAN}│          INCOMPLETE QUEUE            │${NC}"
                echo -e "${CYAN}╰──────────────────────────────────────╯${NC}\n"
                
                SUB_MENU="1. View Incomplete (Paused & Canceled)\n2. Retry a Download\n3. Clear Queue & Delete Temp Files\n4. Back to Main Menu"
                SUB_CHOICE=$(echo -e "$SUB_MENU" | fzf --prompt="Manage Queue ❯ " --height=8 --border=rounded --color=border:cyan)
                
                case "$SUB_CHOICE" in
                    *1.*)
                        echo -e "${DIM}Incomplete Queue:${NC}\n"
                        { grep -E "^(http|ftp|magnet)" "$SESSION_FILE"; cat "$CANCELED_FILE" 2>/dev/null; } | sort -u | sed 's/^/  ⏳ /'
                        echo ""; read -r -p "Press [ENTER] to return..." < /dev/tty
                        ;;
                    *2.*)
                        FAILED=$( { grep -E "^(http|ftp|magnet)" "$SESSION_FILE"; cat "$CANCELED_FILE" 2>/dev/null; } | sort -u | fzf --prompt="Select URL to retry ❯ " --height=10 --border=rounded )
                        if [ -n "$FAILED" ]; then
                            if [ -s "$CANCELED_FILE" ]; then
                                grep -v -F "$FAILED" "$CANCELED_FILE" > "${CANCELED_FILE}.tmp" && mv "${CANCELED_FILE}.tmp" "$CANCELED_FILE"
                            fi
                            
                            if is_daemon_running; then
                                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addUri", "params":["token:'"$RPC_SECRET"'", ["'"$FAILED"'"]]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                            else
                                echo "$FAILED" >> "$SESSION_FILE"
                                start_daemon
                            fi
                            echo -e "\n${GREEN}✔ Retrying URL...${NC}\n"
                            sleep 1
                        fi
                        ;;
                    *3.*)
                        echo -e "\n${RED}Clear incomplete queue and permanently delete partial temp files? [y/N]${NC} "
                        read -r -n 1 -s confirm < /dev/tty
                        if [[ $confirm == "y" || $confirm == "Y" ]]; then
                            if is_daemon_running; then
                                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                
                                # FIX: Wait for the physical process to die so it doesn't overwrite the wipe
                                while is_daemon_process_running; do sleep 0.2; done
                            fi
                            
                            rm -rf "${TEMP_DIR:?}/"*
                            
                            > "$SESSION_FILE"
                            > "$CANCELED_FILE"
                            echo -e "\n\n${GREEN}✔ Incomplete queue cleared and temp directory emptied.${NC}"
                            sleep 1.5
                        fi
                        ;;
                    *4.*|"")
                        break
                        ;;
                esac
            done
            ;;
            
        *6.*)
            read -r -p "❯ Enter Speed Limit (e.g., 2M, 500K, or 0 for unlimited): " SPEED < /dev/tty
            if [[ "$SPEED" =~ ^[0-9]+[KMkm]?$ ]]; then
                if ! is_daemon_running; then start_daemon; fi
                
                curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.changeGlobalOption", "params":["token:'"$RPC_SECRET"'", {"max-overall-download-limit": "'"$SPEED"'"}]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                echo -e "\n${GREEN}✔ Global speed limit updated to $SPEED.${NC}\n"
            else
                echo -e "\n${RED}✖ Invalid format. Use numbers followed by K or M (e.g., 2M).${NC}\n"
            fi
            sleep 1.5
            ;;
            
        *7.*|"")
            break
            ;;
    esac
done

tput rmcup #[cite: 1]

