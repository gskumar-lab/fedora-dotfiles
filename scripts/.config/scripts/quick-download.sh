#!/bin/bash

# ==========================================
# SCRIPT SELF-EXECUTION / SUB-PROCESS FLAGS
# ==========================================
if [[ "$1" == "--get-active" ]]; then
    RESP=$(curl -s --connect-timeout 1 -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:qdl-secret-123"]}' "http://localhost:6800/jsonrpc")
    COUNT=$(echo "$RESP" | jq '.result | length')
    if [[ "$COUNT" == "0" || -z "$COUNT" ]]; then
        echo "No active downloads..."
    else
        echo "$RESP" | jq -r '.result[] | 
        (.totalLength | tonumber) as $t | 
        (.completedLength | tonumber) as $c | 
        (.downloadSpeed | tonumber) as $s |
        
        # Calculate Percentage
        (if $t > 0 then ($c / $t * 100) else 0 end) as $pct |
        
        # Visual Progress Bar (10 characters)
        ([range(10) | if . < ($pct / 10) then "█" else "░" end] | join("")) as $bar |
        
        # Dynamic Speed (KB/s or MB/s)
        ($s / 1024) as $spd_kb |
        (if $spd_kb >= 1024 then "\($spd_kb / 1024 * 10 | round / 10) MB/s" else "\($spd_kb * 10 | round / 10) KB/s" end) as $spd_fmt |
        
        # ETA Calculation (Forced to integer with floor to prevent modulo crash)
        (if $s > 0 and $t > 0 then ((($t - $c) / $s) | floor) else 0 end) as $eta_s |
        (if $t == 0 then "N/A" 
         elif $eta_s == 0 then "0s" 
         elif $eta_s > 3600 then "\($eta_s / 3600 | floor)h \(($eta_s % 3600) / 60 | floor)m" 
         else "\($eta_s / 60 | floor)m \($eta_s % 60)s" end) as $eta_fmt |
        
        # Name Formatting (Safely fallback if files array is weird)
        (if (.files[0].path // "") != "" then (.files[0].path | split("/") | last) 
         elif (.bittorrent.info.name // "") != "" then .bittorrent.info.name 
         else "Metadata Pending..." end) as $raw_name |
        (if ($raw_name | length) > 35 then ($raw_name[0:32] + "...") else $raw_name end) as $name |
        
        # Final UI String Construction
        "\(.gid) │ \($bar) \($pct | floor)% │ \($spd_fmt) │ ETA: \($eta_fmt) │ \($name)"'
    fi
    exit 0
fi

if [[ "$1" == "--get-incomplete" ]]; then
    PAUSED=$(curl -s --connect-timeout 1 -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:qdl-secret-123", 0, 100]}' "http://localhost:6800/jsonrpc" | jq -r '.result[] | select(.status == "paused") | (if .files[0].path != "" then (.files[0].path | split("/") | last) else "Unknown" end) as $name | "[PAUSED] \(.gid) | \($name)"')
    
    FAILED=$(curl -s --connect-timeout 1 -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStopped", "params":["token:qdl-secret-123", 0, 100]}' "http://localhost:6800/jsonrpc" | jq -r '.result[] | select(.errorCode != "0") | (if .files[0].path != "" then (.files[0].path | split("/") | last) else "Unknown" end) as $name | "[ERROR] \(.gid) | \($name)"')
    
    CANCELED=$(awk '{print "[CANCELED] " $0}' "${XDG_DATA_HOME:-$HOME/.local/share}/qdl/canceled.txt" 2>/dev/null)
    
    [[ -n "$PAUSED" ]] && echo "$PAUSED"
    [[ -n "$FAILED" ]] && echo "$FAILED"
    [[ -n "$CANCELED" ]] && echo "$CANCELED"
    exit 0
fi

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
    # Isolate the random directory hash from the filepath
    REL_PATH="\${FILE#$TEMP_DIR/}"
    RAND_HASH=\$(echo "\$REL_PATH" | cut -d'/' -f1)
    ISOLATED_DIR="$TEMP_DIR/\$RAND_HASH"
    
    # Identify the actual downloaded file/folder inside the isolated directory
    ITEM_TO_MOVE=\$(find "\$ISOLATED_DIR" -mindepth 1 -maxdepth 1 | head -n 1)
    BASENAME=\$(basename "\$ITEM_TO_MOVE")
    
    # Move the contents to the final download directory
    mv -n "\$ISOLATED_DIR"/* "$DL_DIR/"
    
    # Clean up the empty isolated directory
    rmdir "\$ISOLATED_DIR" 2>/dev/null
    
    echo "\$(date '+%Y-%m-%d %H:%M:%S') | \$BASENAME" >> "$COMPLETED_FILE"

    if command -v notify-send &> /dev/null; then
        notify-send "Download Complete" "\$BASENAME" --icon=folder-download
    fi
fi

# Shut down if no active, waiting, OR failed tasks remain in memory
ACTIVE=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:$RPC_SECRET"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '.result | length')
WAITING=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:$RPC_SECRET", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.status == "waiting")] | length')
ERRORS=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStopped", "params":["token:$RPC_SECRET", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.errorCode != "0")] | length')

if [[ "\$ACTIVE" == "0" && "\$WAITING" == "0" && "\$ERRORS" == "0" ]]; then
    curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:$RPC_SECRET"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
fi
EOF
chmod +x "$HOOK_SCRIPT"

# ==========================================
# DEPENDENCIES & UI SETUP
# ==========================================
for cmd in aria2c fzf curl jq awk base64; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "Error: Required command '$cmd' is not installed."
        exit 1
    fi
done

trap "tput rmcup; clear; exit 1" SIGINT SIGTERM
tput smcup
clear

export FZF_DEFAULT_OPTS="--height=12 --border=rounded --color=border:cyan --info=hidden"

# ==========================================
# DAEMON LIFECYCLE
# ==========================================
is_daemon_running() {
    curl -s --connect-timeout 1 "http://localhost:$RPC_PORT/jsonrpc" >/dev/null 2>&1
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
        sleep 0.2
    done
}

if grep -qE "^(http|ftp|magnet)" "$SESSION_FILE" 2>/dev/null; then
    if ! is_daemon_running; then start_daemon; fi
fi

# ==========================================
# MAIN LOOP
# ==========================================
while true; do
    MENU="1. Add URL (Single, Bulk, File, or Torrent)\n2. Active Progress\n3. Recent History\n4. Completed Downloads\n5. Manage Incomplete Queue\n6. Set Download Speed Limit\n7. Exit"
    CHOICE=$(echo -e "$MENU" | fzf --reverse --prompt="Main Menu ❯ ")

    case "$CHOICE" in
        *1.*)
            clear
            echo -e "╭──────────────────────────────────────╮"
            echo -e "│           ADD DOWNLOAD(S)            │"
            echo -e "╰──────────────────────────────────────╯"
            echo -e "Options:"
            echo -e "  - Paste a single URL or path to .torrent file"
            echo -e "  - Paste multiple URLs separated by a space"
            echo -e "  - Provide the path to a .txt file containing URLs"
            echo -e "\nPress ENTER without typing to return to the menu.\n"
            
            read -e -p "❯ " RAW_INPUT
            if [[ -z "$RAW_INPUT" ]]; then continue; fi

            # Strip terminal auto-quoting for dragged files
            INPUT="${RAW_INPUT#\'}"
            INPUT="${INPUT%\'}"
            INPUT="${INPUT#\"}"
            INPUT="${INPUT%\"}"

            if [[ -f "$INPUT" && "$INPUT" != *.torrent ]]; then
                URL_LIST=$(tr -d '\r' < "$INPUT")
            else
                URL_LIST="$INPUT"
            fi

            ADDED_COUNT=0
            if ! is_daemon_running; then start_daemon; fi

	    set -f
            for URL in $URL_LIST; do
                if [[ "$URL" =~ ^(https?|ftp|magnet): || ( -f "$URL" && "$URL" == *.torrent ) ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | $URL" >> "$HISTORY_FILE"

                    # Generate a unique isolated directory for this specific download
                    RAND_HASH=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
                    TARGET_DIR="$TEMP_DIR/$RAND_HASH"

                    if [[ -f "$URL" && "$URL" == *.torrent ]]; then
                        B64=$(base64 -w 0 < "$URL")
                        # addTorrent requires an empty array [] for URIs when passing options
                        PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg b64 "$B64" --arg dir "$TARGET_DIR" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addTorrent", "params":[$token, $b64, [], {"dir": $dir}]}')
                    else
                        PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg url "$URL" --arg dir "$TARGET_DIR" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addUri", "params":[$token, [$url], {"dir": $dir}]}')
                    fi

                    curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                    ((ADDED_COUNT++))
                fi
            done
            set +f

            if [[ "$ADDED_COUNT" -gt 0 ]]; then
                echo -e "\n✔ Successfully added $ADDED_COUNT download(s) to the queue."
                if command -v notify-send &> /dev/null; then
                    notify-send "Quick Downloader" "Added $ADDED_COUNT download(s) to the queue." --icon=document-save
                fi
                sleep 1.5
            else
                echo -e "\n✖ No valid URLs or .torrent files found."
                sleep 1.5
            fi

	    clear
            ;;
            
        *2.*)
            if ! is_daemon_running; then start_daemon; fi
            while true; do
                OUTPUT=$(bash "$0" --get-active | fzf --prompt="Active ❯ " \
                    --header="Tab: Multi-select | P: Pause | C: Cancel | R: Refresh | Q/Esc: Menu" \
		    --bind="r:reload(bash \"$0\" --get-active),R:reload(bash \"$0\" --get-active)" \
                    --expect=esc,q,p,c,P,C -m)
                
                KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]')
                SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                
                if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                
                if [[ -n "$SELECTIONS" && -n "$KEY" ]]; then
                    while IFS= read -r line; do
                        line="${line%$'\r'}"
                        if [[ -z "$line" || "$line" == "No active downloads..." ]]; then continue; fi
                        
                        GID=$(echo "$line" | awk '{print $1}')

                        if [[ "$KEY" == "p" ]]; then
                            PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.pause", "params":[$token, $gid]}')
                            curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                        elif [[ "$KEY" == "c" ]]; then
                            INFO=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStatus", "params":["token:'"$RPC_SECRET"'", "'"$GID"'"]}' "http://localhost:$RPC_PORT/jsonrpc")
                            T_URL=$(echo "$INFO" | jq -r '.result.files[0].uris[0].uri // empty')
                            
                            if [ -z "$T_URL" ]; then
                                T_NAME=$(echo "$INFO" | jq -r '(if .bittorrent.info.name then .bittorrent.info.name else (.files[0].path | split("/") | last) end)')
                                T_URL=$(grep -iF "$T_NAME" "$HISTORY_FILE" | tail -n 1 | awk -F" | " '{print $NF}')
                            fi
                            
                            PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.remove", "params":[$token, $gid]}')
                            curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                            
                            if [ -n "$T_URL" ]; then
                                echo "$T_URL" >> "$CANCELED_FILE"
                            fi
                        fi
                    done <<< "$SELECTIONS"
                fi
            done
            ;;
            
        *3.*)
            while true; do
                OUTPUT=$(cat "$HISTORY_FILE" | fzf --prompt="History ❯ " \
                    --header="Tab: Multi-select | C: Clear selected | Q/Esc: Menu" \
                    --expect=esc,q,c,C -m)
                
                KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]')
                SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                
                if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                if [[ "$KEY" == "c" && -n "$SELECTIONS" ]]; then
                    while IFS= read -r line; do
                        line="${line%$'\r'}"
                        if [[ -z "$line" ]]; then continue; fi
                        
                        grep -v -F "$line" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
                        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
                    done <<< "$SELECTIONS"
                fi
            done
            ;;
            
        *4.*)
            while true; do
                OUTPUT=$(cat "$COMPLETED_FILE" | fzf --prompt="Completed ❯ " \
                    --header="Tab: Multi-select | C: Clear selected | Q/Esc: Menu" \
                    --expect=esc,q,c,C -m)
                
                KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]')
                SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                
                if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                if [[ "$KEY" == "c" && -n "$SELECTIONS" ]]; then
                    while IFS= read -r line; do
                        line="${line%$'\r'}"
                        if [[ -z "$line" ]]; then continue; fi
                        
                        grep -v -F "$line" "$COMPLETED_FILE" > "${COMPLETED_FILE}.tmp"
                        mv "${COMPLETED_FILE}.tmp" "$COMPLETED_FILE"
                    done <<< "$SELECTIONS"
                fi
            done
            ;;
            
        *5.*)
            if ! is_daemon_running; then start_daemon; fi
            while true; do
                OUTPUT=$(bash "$0" --get-incomplete | fzf --prompt="Incomplete Queue ❯ " \
                    --header="Tab: Multi-select | R: Retry | C: Clear (Removes Temp Files) | Q/Esc: Menu" \
                    --expect=esc,q,r,c,R,C -m)
                
                KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]')
                SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                
                if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                
                if [[ -n "$SELECTIONS" && -n "$KEY" ]]; then
                    while IFS= read -r line; do
                        line="${line%$'\r'}"
                        if [[ -z "$line" ]]; then continue; fi
                        
                        if [[ "$line" == \[PAUSED\]* || "$line" == \[ERROR\]* ]]; then
                            temp="${line#*] }"
                            GID="${temp%% | *}"
                            FILENAME="${temp#* | }"
                            
                            if [[ "$KEY" == "r" ]]; then
                                PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.unpause", "params":[$token, $gid]}')
                                curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                            elif [[ "$KEY" == "c" ]]; then
                                PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.removeDownloadResult", "params":[$token, $gid]}')
                                curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                
                                if [[ -n "$FILENAME" && "$FILENAME" != "." && "$FILENAME" != "/" ]]; then
                                    rm -rf "${TEMP_DIR:?}/$FILENAME"*
                                fi
                            fi
                        elif [[ "$line" == \[CANCELED\]* ]]; then
                            URL="${line#*] }"
                            
                            if [[ "$KEY" == "r" ]]; then
                                PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg url "$URL" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addUri", "params":[$token, [$url]]}')
                                curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                
                                grep -v -F "$URL" "$CANCELED_FILE" > "${CANCELED_FILE}.tmp"
                                mv "${CANCELED_FILE}.tmp" "$CANCELED_FILE"
                            elif [[ "$KEY" == "c" ]]; then
                                grep -v -F "$URL" "$CANCELED_FILE" > "${CANCELED_FILE}.tmp"
                                mv "${CANCELED_FILE}.tmp" "$CANCELED_FILE"
                                
                                URL_BASE=$(basename "$URL")
                                if [[ -n "$URL_BASE" && "$URL_BASE" != "." && "$URL_BASE" != "/" ]]; then
                                    rm -rf "${TEMP_DIR:?}/$URL_BASE"*
                                fi
                            fi
                        fi
                    done <<< "$SELECTIONS"
                fi
            done
            ;;
            
        *6.*)
            if ! is_daemon_running; then start_daemon; fi
            CURRENT_LIMIT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.getGlobalOption", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq -r '.result."max-overall-download-limit"')
            [[ "$CURRENT_LIMIT" == "0" ]] && STATUS="Unlimited" || STATUS="${CURRENT_LIMIT}"
            
            SPEED=$(echo "" | fzf --print-query --prompt="Speed Limit (Current: $STATUS) e.g., 2M, 500K, 0 (Esc to cancel) ❯ " --bind="esc:abort" | head -n 1)
            
            if [[ -n "$SPEED" && "$SPEED" =~ ^[0-9]+[KMkm]?$ ]]; then
                PAYLOAD=$(jq -n --arg token "token:$RPC_SECRET" --arg sp "$SPEED" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.changeGlobalOption", "params":[$token, {"max-overall-download-limit": $sp}]}')
                curl -s -d "$PAYLOAD" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
            fi
            ;;
            
        *7.*|"")
            if is_daemon_running; then
                ACTIVE_COUNT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '.result | length')
                WAITING_COUNT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.status == "waiting")] | length')
                ERROR_COUNT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStopped", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.errorCode != "0")] | length')
                
                if [[ "$ACTIVE_COUNT" == "0" && "$WAITING_COUNT" == "0" && "$ERROR_COUNT" == "0" ]]; then
                    curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                fi
            fi
            break
            ;;
    esac
done

tput rmcup

