#!/bin/bash

# ==========================================
# CONFIGURATION & INITIALIZATION
# ==========================================
VERSION="3.0.1"
QDL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/qdl"
TEMP_DIR="$QDL_DIR/temp"
YT_TMP_BASE="$QDL_DIR/yt-dlp"
DL_DIR="$HOME/Downloads"

SESSION_FILE="$QDL_DIR/session.txt"
HISTORY_FILE="$QDL_DIR/history.log"
CANCELED_FILE="$QDL_DIR/canceled.txt"
COMPLETED_FILE="$QDL_DIR/completed.log"
HOOK_SCRIPT="$QDL_DIR/on_complete.sh"

RPC_SECRET="qdl-secret-123"
RPC_PORT="6800"

mkdir -p "$QDL_DIR" "$TEMP_DIR" "$YT_TMP_BASE" "$DL_DIR"
touch "$SESSION_FILE" "$HISTORY_FILE" "$CANCELED_FILE" "$COMPLETED_FILE"

export FZF_DEFAULT_OPTS="--height=12 --border=rounded --color=border:cyan --info=hidden --ansi"

# ==========================================
# HELPER FUNCTIONS: SETUP & DAEMON
# ==========================================
check_dependencies() {
    local missing_cmds=() missing_pkgs=()
    local deps=( "aria2c:aria2" "fzf:fzf" "curl:curl" "jq:jq" "yt-dlp:yt-dlp" "ffmpeg:ffmpeg" "notify-send:libnotify" )
    
    for dep in "${deps[@]}"; do
        local cmd="${dep%%:*}" pkg="${dep##*:}"
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        echo "⚠️ Missing dependencies detected: ${missing_cmds[*]}"
        if command -v pacman &> /dev/null; then
            echo -n "📦 Do you want to install them using pacman (Arch Linux)? [y/N]: "
            read -r install_deps
            if [[ "$install_deps" =~ ^[Yy]$ ]]; then
                sudo pacman -S --needed "${missing_pkgs[@]}"
            else
                exit 1
            fi
        else
            echo "❌ Please install missing dependencies via your package manager."
            exit 1
        fi
    fi
}

generate_hook_script() {
    cat << EOF > "$HOOK_SCRIPT"
#!/bin/bash
GID="\$1"
NUM="\$2"
FILE="\$3"

if [ "\$NUM" -gt 0 ] && [ -e "\$FILE" ]; then
    REL_PATH="\${FILE#$TEMP_DIR/}"
    RAND_HASH=\$(echo "\$REL_PATH" | cut -d'/' -f1)
    ISOLATED_DIR="$TEMP_DIR/\$RAND_HASH"
    
    ITEM_COUNT=\$(find "\$ISOLATED_DIR" -mindepth 1 -maxdepth 1 | wc -l)
    ITEM_TO_MOVE=\$(find "\$ISOLATED_DIR" -mindepth 1 -maxdepth 1 | head -n 1)
    BASENAME=\$(basename "\$ITEM_TO_MOVE")
    
    if [ "\$ITEM_COUNT" -gt 1 ]; then LOG_NAME="\$BASENAME (+ \$((\$ITEM_COUNT - 1)) more)"; else LOG_NAME="\$BASENAME"; fi
    
    mv -n "\$ISOLATED_DIR"/* "$DL_DIR/" 2>/dev/null
    rm -rf "\$ISOLATED_DIR" 
    
    echo "\$(date '+%Y-%m-%d %H:%M:%S') | \$LOG_NAME" >> "$COMPLETED_FILE"
    if command -v notify-send &> /dev/null; then notify-send "Download Complete" "\$LOG_NAME" -i downloader-arrow; fi
fi

ACTIVE=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:$RPC_SECRET"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '.result | length')
WAITING=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:$RPC_SECRET", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.status == "waiting")] | length')
ERRORS=\$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStopped", "params":["token:$RPC_SECRET", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.errorCode != "0")] | length')

if [[ "\$ACTIVE" == "0" && "\$WAITING" == "0" && "\$ERRORS" == "0" ]]; then
    curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:$RPC_SECRET"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
fi
EOF
    chmod +x "$HOOK_SCRIPT"
}

is_daemon_running() {
    curl -s --connect-timeout 1 "http://localhost:$RPC_PORT/jsonrpc" >/dev/null 2>&1
}

start_daemon() {
    setsid aria2c --dir="$TEMP_DIR" --input-file="$SESSION_FILE" --save-session="$SESSION_FILE" --save-session-interval=10 --enable-rpc=true --rpc-listen-port="$RPC_PORT" --rpc-secret="$RPC_SECRET" --on-download-complete="$HOOK_SCRIPT" --max-concurrent-downloads=3 --quiet=true < /dev/null > "$QDL_DIR/aria2.log" 2>&1 &
    for _ in {1..20}; do if is_daemon_running; then return 0; fi; sleep 0.2; done
}

check_daemon_shutdown() {
    if is_daemon_running; then
        local ACTIVE_COUNT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '.result | length')
        local WAITING_COUNT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.status == "waiting")] | length')
        local ERROR_COUNT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStopped", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq '[.result[] | select(.errorCode != "0")] | length')
        
        if [[ "$ACTIVE_COUNT" == "0" && "$WAITING_COUNT" == "0" && "$ERROR_COUNT" == "0" ]]; then
            curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.shutdown", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
        fi
    fi
}

# ==========================================
# HELPER FUNCTIONS: DOWNLOAD LOGIC
# ==========================================
add_standard_download() {
    local input="$1"
    local url_list
    
    # Strip terminal auto-quoting
    input="${input#\'}"; input="${input%\'}"; input="${input#\"}"; input="${input%\"}"
    if [[ -f "$input" && "$input" != *.torrent ]]; then url_list=$(tr -d '\r' < "$input"); else url_list="$input"; fi

    local added_count=0
    if ! is_daemon_running; then start_daemon; fi

    set -f
    for url in $url_list; do
        if [[ "$url" =~ ^(https?|ftp|magnet): || ( -f "$url" && "$url" == *.torrent ) ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | $url" >> "$HISTORY_FILE"
            local rand_hash=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
            local target_dir="$TEMP_DIR/$rand_hash"
            local payload

            if [[ -f "$url" && "$url" == *.torrent ]]; then
                local b64=$(base64 -w 0 < "$url")
                payload=$(jq -n --arg token "token:$RPC_SECRET" --arg b64 "$b64" --arg dir "$target_dir" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addTorrent", "params":[$token, $b64, [], {"dir": $dir}]}')
            else
                payload=$(jq -n --arg token "token:$RPC_SECRET" --arg u "$url" --arg dir "$target_dir" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addUri", "params":[$token, [$u], {"dir": $dir}]}')
            fi
            curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
            ((added_count++))
        fi
    done
    set +f

    if [[ "$added_count" -gt 0 ]]; then
        echo -e "\n✔ Added $added_count standard download(s) to queue."
        if command -v notify-send &> /dev/null; then notify-send "Added $added_count download(s) to queue."; fi
    else
        echo -e "\n✖ No valid URLs or .torrent files found."
    fi
    sleep 1
}

run_ytdlp_download() {
    local tmp_dir="$1"
    local url=$(cat "$tmp_dir/url.txt")
    local save_path=$(cat "$tmp_dir/save_path.txt")
    
    cd "$tmp_dir/data" || return
    # Capture the output to a log file instead of discarding it
    bash "$tmp_dir/cmd.sh" > "$tmp_dir/progress.log" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        shopt -s dotglob nullglob
        for file in "$tmp_dir/data/"*; do mv "$file" "$save_path/" 2>/dev/null; done
        shopt -u dotglob nullglob
        
        rm -rf "$tmp_dir"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | [YT-DLP] Video Processed" >> "$COMPLETED_FILE"
        if command -v notify-send &> /dev/null; then notify-send "Download Complete" "[YT-DLP] Task Finished" -i downloader-arrow; fi
    fi
}

add_ytdlp_cli_default() {
    local url="$1"
    local save_path="$DL_DIR"
    
    local job_id="job_$(date +%s)"
    local tmp_dir="$YT_TMP_BASE/$job_id"
    mkdir -p "$tmp_dir/data" "$save_path"
    
    # Add newline and no-colors flags
    local cmd=(yt-dlp -4 --newline --no-colors -P "$tmp_dir/data" "$url")
    
    echo "$url" > "$tmp_dir/url.txt"; echo "$save_path" > "$tmp_dir/save_path.txt"
    printf "%q " "${cmd[@]}" > "$tmp_dir/cmd.sh"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $url" >> "$HISTORY_FILE"
    
    run_ytdlp_download "$tmp_dir" & disown "$!"
    echo "✅ Media Download started in background: $url"
}

# ==========================================
# HELPER FUNCTIONS: LIST QUEUES
# ==========================================
show_active_tasks() {
    # Aria2 tasks
    local resp=$(curl -s --connect-timeout 1 -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellActive", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc")
    local count=$(echo "$resp" | jq '.result | length')
    
    local aria_out=""
    if [[ "$count" != "0" && -n "$count" ]]; then
        aria_out=$(echo "$resp" | jq -r '.result[] | 
        (.totalLength | tonumber) as $t | (.completedLength | tonumber) as $c | (.downloadSpeed | tonumber) as $s |
        (if $t > 0 then ($c / $t * 100) else 0 end) as $pct |
        ($pct / 5 | floor) as $filled_count |
        (20 - $filled_count) as $empty_count |
        ([range($filled_count) | "█"] | join("")) as $bar_fill |
        ([range($empty_count) | "░"] | join("")) as $bar_empty |
        "\u001b[32m\($bar_fill)\u001b[90m\($bar_empty)\u001b[0m" as $bar |
        ($s / 1024) as $spd_kb | (if $spd_kb >= 1024 then "\($spd_kb / 1024 * 10 | round / 10) MB/s" else "\($spd_kb * 10 | round / 10) KB/s" end) as $spd_raw |
        "\u001b[36m\($spd_raw)\u001b[0m" as $spd_fmt |
        (if $s > 0 and $t > 0 then ((($t - $c) / $s) | floor) else 0 end) as $eta_s |
        (if $t == 0 then "N/A" elif $eta_s == 0 then "0s" elif $eta_s > 3600 then "\($eta_s / 3600 | floor)h \(($eta_s % 3600) / 60 | floor)m" else "\($eta_s / 60 | floor)m \($eta_s % 60)s" end) as $eta_raw |
        "\u001b[33m\($eta_raw)\u001b[0m" as $eta_fmt |
        (if (.files[0].path // "") != "" then (.files[0].path | split("/") | last) elif (.bittorrent.info.name // "") != "" then .bittorrent.info.name else "Metadata Pending..." end) as $raw_name |
        (if ($raw_name | length) > 35 then ($raw_name[0:32] + "...") else $raw_name end) as $name |
        "\u001b[35m\(.gid)\u001b[0m\t│\t\($bar) \($pct | floor)%\t│\t\($spd_fmt)\t│\tETA: \($eta_fmt)\t│\t\($name)"')
    fi

    # YT-DLP Tasks
    local yt_out=""
    shopt -s nullglob
    for d in "$YT_TMP_BASE"/job_*; do
        local pid=$(pgrep -f "yt-dlp.*$d" | head -n 1)
        if [[ -n "$pid" ]]; then
            local pct="0" spd="N/A" eta="N/A" name="Metadata Pending..."
            
            if [[ -f "$d/progress.log" ]]; then
                # Get exact filename
                local dest=$(grep "^\[download\] Destination:" "$d/progress.log" | tail -n 1 | sed 's/.*Destination: //')
                if [[ -n "$dest" ]]; then name=$(basename "$dest"); else name=$(cat "$d/url.txt" 2>/dev/null | sed -E 's/.*(v=|be\/)([a-zA-Z0-9_-]+).*/\2/'); fi
                
                # Parse progress line
                local latest=$(grep "^\[download\].*%" "$d/progress.log" | tail -n 1)
                if [[ -n "$latest" ]]; then
                    pct=$(echo "$latest" | sed -n 's/.* \([0-9.]*\)%.*/\1/p')
                    spd=$(echo "$latest" | sed -n 's/.*at \([^ ]*\).*/\1/p')
                    eta=$(echo "$latest" | sed -n 's/.*ETA \([^ ]*\).*/\1/p')
                fi
            fi
            
            [[ -z "$pct" ]] && pct="0"
            [[ -z "$spd" ]] && spd="N/A"
            [[ -z "$eta" ]] && eta="N/A"
            
            # Generate 20-char visual bar
            local int_pct=${pct%.*}
            [[ -z "$int_pct" ]] && int_pct=0
            local filled=$(( int_pct / 5 ))
            local empty=$(( 20 - filled ))
            
            local bar_fill="" bar_empty=""
            for ((i=0; i<filled; i++)); do bar_fill+="█"; done
            for ((i=0; i<empty; i++)); do bar_empty+="░"; done
            
            [[ ${#name} -gt 35 ]] && name="${name:0:32}..."
            
            yt_out+="\u001b[35mYTDLP-$pid\u001b[0m\t│\t\u001b[32m${bar_fill}\u001b[90m${bar_empty}\u001b[0m ${int_pct}%\t│\t\u001b[36m${spd}\u001b[0m\t│\tETA: \u001b[33m${eta}\u001b[0m\t│\t${name}\n"
        fi
    done
    shopt -u nullglob

    # Combine and columnate
    if [[ -n "$aria_out" || -n "$yt_out" ]]; then
        { [[ -n "$aria_out" ]] && echo -e "$aria_out"; [[ -n "$yt_out" ]] && echo -e "$yt_out"; } | column -t -s $'\t'
    else
        echo "No active downloads..."
    fi
}

show_incomplete_tasks() {
    # Aria2 Incomplete
    local paused=$(curl -s --connect-timeout 1 -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellWaiting", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq -r '.result[]? | select(.status == "paused") | (if (.files[0]?.path // "") != "" then (.files[0].path | split("/") | last) else "Unknown" end) as $name | "[PAUSED] \(.gid) | \($name)"')
    local failed=$(curl -s --connect-timeout 1 -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStopped", "params":["token:'"$RPC_SECRET"'", 0, 100]}' "http://localhost:$RPC_PORT/jsonrpc" | jq -r '.result[]? | select(.errorCode != "0") | (if (.files[0]?.path // "") != "" then (.files[0].path | split("/") | last) else "Unknown" end) as $name | "[ERROR] \(.gid) | \($name)"')
    local canceled=$(awk '{print "[CANCELED] " $0}' "$CANCELED_FILE" 2>/dev/null)
    
    # YT-DLP Incomplete
    shopt -s nullglob
    for d in "$YT_TMP_BASE"/job_*; do
        if [[ -d "$d" ]] && ! pgrep -f "yt-dlp.*$d" > /dev/null; then
            local u=$(cat "$d/url.txt" 2>/dev/null)
            echo "[YTDLP-FAIL] $(basename "$d") | $u"
        fi
    done
    shopt -u nullglob

    [[ -n "$paused" ]] && echo "$paused"
    [[ -n "$failed" ]] && echo "$failed"
    [[ -n "$canceled" ]] && echo "$canceled"
}

# ==========================================
# CLI PROCESSING
# ==========================================
show_help() {
    echo "Quick Downloader Manager v$VERSION"
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message."
    echo "  -v, --version        Show version information."
    echo "  -a, --add <url>      Add a standard URL, torrent file, or txt list of URLs."
    echo "  -y, --yt <url>       Download a media URL using yt-dlp (uses default best settings)."
    echo "  --tui                Launch the interactive Terminal User Interface (Default behavior)."
    echo ""
    echo "Note: Running the script without arguments launches the TUI."
}

# Intercept and process CLI flags
if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --get-active) show_active_tasks; exit 0 ;;
            --get-incomplete) show_incomplete_tasks; exit 0 ;;
            -h|--help) show_help; exit 0 ;;
            -v|--version) echo "Quick Downloader Manager v$VERSION"; exit 0 ;;
            -a|--add) 
                if [[ -n "$2" ]]; then add_standard_download "$2"; check_daemon_shutdown; exit 0; else echo "Error: --add requires a URL"; exit 1; fi ;;
            -y|--yt) 
                if [[ -n "$2" ]]; then add_ytdlp_cli_default "$2"; exit 0; else echo "Error: --yt requires a URL"; exit 1; fi ;;
            --tui) break ;;
            *) echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done
fi

# ==========================================
# TERMINAL USER INTERFACE (TUI)
# ==========================================
check_dependencies
generate_hook_script
if grep -qE "^(http|ftp|magnet)" "$SESSION_FILE" 2>/dev/null; then
    if ! is_daemon_running; then start_daemon; fi
fi

trap "tput rmcup; clear; exit 1" SIGINT SIGTERM
tput smcup
clear

start_tui() {
    while true; do
        local MENU="1. Add Standard URL/Torrent\n2. Add Youtube Media\n3. Active Progress\n4. Recent History\n5. Completed Downloads\n6. Manage Incomplete Queue\n7. Set Speed Limit (Only for Aria2)\n8. Exit"
        local CHOICE=$(echo -e "$MENU" | fzf --reverse --prompt="Main Menu ❯ ")

        case "$CHOICE" in
            *1.*)
                clear
                echo -e "╭──────────────────────────────────────╮"
                echo -e "│       ADD STANDARD DOWNLOAD(S)       │"
                echo -e "╰──────────────────────────────────────╯"
                read -e -p "❯ " RAW_INPUT
                [[ -n "$RAW_INPUT" ]] && add_standard_download "$RAW_INPUT"
                clear
                ;;

            *2.*)
                clear
                echo -e "╭──────────────────────────────────────╮"
                echo -e "│           ADD YOUTUBE MEDIA          │"
                echo -e "╰──────────────────────────────────────╯"
                echo -n "🔗 Enter YouTube/Media link: "
                read -r url
                [[ -z "$url" ]] && continue

                echo -n "📂 Is this a (v)ideo or (p)laylist? [v/p, default: v]: "
                read -r type
                if [[ "$type" == "p" || "$type" == "P" ]]; then
                    local playlist_args="--yes-playlist"; local format_fetch_args="--yes-playlist --playlist-items 1"
                else
                    local playlist_args="--no-playlist"; local format_fetch_args="--no-playlist"
                fi

                echo "⏳ Fetching available formats..."
                local RAW_OUTPUT=$(yt-dlp -4 -F $format_fetch_args "$url" 2>/dev/null)
                if [[ -z "$RAW_OUTPUT" ]]; then echo "❌ Failed to fetch formats."; sleep 1.5; continue; fi

                local HEADER=$(echo "$RAW_OUTPUT" | grep -E "^ID\s+EXT")
                local FORMATS=$(echo "$RAW_OUTPUT" | awk '/^---/{flag=1; next} flag')
                local FORMATS_VIDEO=$(echo "$FORMATS" | grep -vi "audio only" | grep -vi "storyboard")
                local FORMATS_AUDIO=$(echo "$FORMATS" | grep -i "audio only")

                local VIDEO_ID=$(echo "$FORMATS_VIDEO" | fzf --header="$HEADER" --prompt="Select VIDEO (Enter to confirm, ESC to skip) > " --reverse | awk '{print $1}')
                local AUDIO_ID=$(echo "$FORMATS_AUDIO" | fzf --header="$HEADER" --prompt="Select AUDIO (Enter to confirm, ESC to skip) > " --reverse | awk '{print $1}')

                echo -n "📝 Download subtitles? [y/N]: "; read -r get_subs
                echo -n "🔖 Embed chapters? [y/N]: "; read -r get_chapters
                echo -n "📄 Download video description? [y/N]: "; read -r get_desc
                echo -n "📁 Save location? [Press Enter for ~/Downloads]: "; read -r save_path

                [[ -z "$save_path" ]] && save_path="$DL_DIR"
                save_path="${save_path/#\~/$HOME}"
                mkdir -p "$save_path"

                local job_id="job_$(date +%s)"
                local tmp_dir="$YT_TMP_BASE/$job_id"
                mkdir -p "$tmp_dir/data"

                local cmd=(yt-dlp -4 --newline --no-colors $playlist_args -P "$tmp_dir/data")
                if [[ -n "$VIDEO_ID" && -n "$AUDIO_ID" ]]; then cmd+=(-f "${VIDEO_ID}+${AUDIO_ID}"); elif [[ -n "$VIDEO_ID" ]]; then cmd+=(-f "${VIDEO_ID}"); elif [[ -n "$AUDIO_ID" ]]; then cmd+=(-f "${AUDIO_ID}"); fi
                [[ "$get_subs" =~ ^[Yy]$ ]] && cmd+=(--write-subs --embed-subs --sub-langs "all,en")
                [[ "$get_chapters" =~ ^[Yy]$ ]] && cmd+=(--embed-chapters)
                [[ "$get_desc" =~ ^[Yy]$ ]] && cmd+=(--write-description)
                cmd+=("$url")

                echo "$url" > "$tmp_dir/url.txt"; echo "$save_path" > "$tmp_dir/save_path.txt"
                printf "%q " "${cmd[@]}" > "$tmp_dir/cmd.sh"

                echo "$(date '+%Y-%m-%d %H:%M:%S') | $url" >> "$HISTORY_FILE"
                run_ytdlp_download "$tmp_dir" & disown "$!"
                echo "✅ Media Download started in background."; sleep 1; clear
                ;;
                
            *3.*)
                if ! is_daemon_running; then start_daemon; fi
                while true; do
                    local OUTPUT=$(bash "$0" --get-active | fzf --prompt="Active ❯ " \
                        --header="Tab: Multi-select | P: Pause | U: Unpause (yt-dlp) | C: Cancel | R: Refresh | Q/Esc: Menu" \
                        --bind="r:reload(bash \"$0\" --get-active),R:reload(bash \"$0\" --get-active)" \
                        --expect=esc,q,p,u,c,P,U,C -m)
                    
                    local KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]')
                    local SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                    
                    if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                    
                    if [[ -n "$SELECTIONS" && -n "$KEY" ]]; then
                        while IFS= read -r line; do
                            line="${line%$'\r'}"; [[ -z "$line" || "$line" == "No active downloads..." ]] && continue
                            local GID=$(echo "$line" | awk '{print $1}')

                            if [[ "$GID" == YTDLP-* ]]; then
                                local pid=${GID#YTDLP-}
                                if [[ "$KEY" == "p" ]]; then kill -STOP "$pid" 2>/dev/null; fi
                                if [[ "$KEY" == "u" ]]; then kill -CONT "$pid" 2>/dev/null; fi
                                if [[ "$KEY" == "c" ]]; then kill -TERM "$pid" 2>/dev/null; fi
                                continue
                            fi

                            if [[ "$KEY" == "p" ]]; then
                                local payload=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.forcePause", "params":[$token, $gid]}')
                                curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                            elif [[ "$KEY" == "c" ]]; then
                                local info=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStatus", "params":["token:'"$RPC_SECRET"'", "'"$GID"'"]}' "http://localhost:$RPC_PORT/jsonrpc")
                                if [[ -n "$info" ]]; then
                                    local t_url=$(echo "$info" | jq -r '.result?.files?[0]?.uris?[0]?.uri // empty')
                                    if [[ -z "$t_url" ]]; then
                                        local t_name=$(echo "$info" | jq -r 'if .result?.bittorrent?.info?.name then .result.bittorrent.info.name elif (.result?.files?[0]?.path // "") != "" then (.result.files[0].path | split("/") | last) else empty end')
                                        [[ -n "$t_name" ]] && t_url=$(grep -iF "$t_name" "$HISTORY_FILE" | tail -n 1 | awk -F" | " '{print $NF}')
                                    fi
                                fi
                                local payload=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.forceRemove", "params":[$token, $gid]}')
                                curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                sleep 0.2 
                                local dl_dir_path=$(echo "$info" | jq -r '.result.dir // empty')
                                if [[ -n "$dl_dir_path" && "$dl_dir_path" == "$TEMP_DIR"/* ]]; then rm -rf "$dl_dir_path"; fi
                                if [ -n "$t_url" ]; then echo "$t_url" >> "$CANCELED_FILE"; fi
                            fi
                        done <<< "$SELECTIONS"
                    fi
                done
                ;;
                
            *4.*)
                while true; do
                    local OUTPUT=$(cat "$HISTORY_FILE" | fzf --prompt="History ❯ " --header="Tab: Multi-select | C: Clear selected | Q/Esc: Menu" --expect=esc,q,c,C -m)
                    local KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]'); local SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                    if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                    if [[ "$KEY" == "c" && -n "$SELECTIONS" ]]; then
                        while IFS= read -r line; do
                            line="${line%$'\r'}"; [[ -z "$line" ]] && continue
                            grep -v -F "$line" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"; mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
                        done <<< "$SELECTIONS"
                    fi
                done
                ;;
                
            *5.*)
                while true; do
                    local OUTPUT=$(cat "$COMPLETED_FILE" | fzf --prompt="Completed ❯ " --header="Tab: Multi-select | C: Clear selected | Q/Esc: Menu" --expect=esc,q,c,C -m)
                    local KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]'); local SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                    if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                    if [[ "$KEY" == "c" && -n "$SELECTIONS" ]]; then
                        while IFS= read -r line; do
                            line="${line%$'\r'}"; [[ -z "$line" ]] && continue
                            grep -v -F "$line" "$COMPLETED_FILE" > "${COMPLETED_FILE}.tmp"; mv "${COMPLETED_FILE}.tmp" "$COMPLETED_FILE"
                        done <<< "$SELECTIONS"
                    fi
                done
                ;;
                
            *6.*)
                if ! is_daemon_running; then start_daemon; fi
                while true; do
                    local OUTPUT=$(bash "$0" --get-incomplete | fzf --prompt="Incomplete Queue ❯ " \
                        --header="Tab: Multi-select | R: Retry/Resume | C: Clear | Q/Esc: Menu" \
                        --expect=esc,q,r,c,R,C -m)
                    
                    local KEY=$(echo "$OUTPUT" | head -n 1 | tr '[:upper:]' '[:lower:]')
                    local SELECTIONS=$(echo "$OUTPUT" | tail -n +2)
                    
                    if [[ "$KEY" == "esc" || "$KEY" == "q" ]]; then break; fi
                    
                    if [[ -n "$SELECTIONS" && -n "$KEY" ]]; then
                        while IFS= read -r line; do
                            line="${line%$'\r'}"; [[ -z "$line" ]] && continue
                            
                            if [[ "$line" == \[YTDLP-FAIL\]* ]]; then
                                local temp="${line#*] }"; local JID="${temp%% | *}"
                                if [[ "$KEY" == "r" ]]; then run_ytdlp_download "$YT_TMP_BASE/$JID" & disown "$!"; fi
                                if [[ "$KEY" == "c" ]]; then rm -rf "$YT_TMP_BASE/$JID"; fi
                                continue
                            fi

                            if [[ "$line" == \[PAUSED\]* || "$line" == \[ERROR\]* ]]; then
                                local temp="${line#*] }"; local GID="${temp%% | *}"
                                if [[ "$KEY" == "r" ]]; then
                                    local payload=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.unpause", "params":[$token, $gid]}')
                                    curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                elif [[ "$KEY" == "c" ]]; then
                                    local dl_dir_path=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.tellStatus", "params":["token:'"$RPC_SECRET"'", "'"$GID"'"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq -r '.result.dir // empty')
                                    local payload=$(jq -n --arg token "token:$RPC_SECRET" --arg gid "$GID" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.removeDownloadResult", "params":[$token, $gid]}')
                                    curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                    if [[ -n "$dl_dir_path" && "$dl_dir_path" == "$TEMP_DIR"/* ]]; then rm -rf "$dl_dir_path"; fi
                                fi

                            elif [[ "$line" == \[CANCELED\]* ]]; then
                                local URL="${line#*] }"
                                if [[ "$KEY" == "r" ]]; then
                                    local rand_hash=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
                                    local target_dir="$TEMP_DIR/$rand_hash"
                                    local payload
                                    
                                    # Fix: Properly handle local torrent file retries instead of forcing them through addUri
                                    if [[ -f "$URL" && "$URL" == *.torrent ]]; then
                                        local b64=$(base64 -w 0 < "$URL")
                                        payload=$(jq -n --arg token "token:$RPC_SECRET" --arg b64 "$b64" --arg dir "$target_dir" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addTorrent", "params":[$token, $b64, [], {"dir": $dir}]}')
                                    else
                                        payload=$(jq -n --arg token "token:$RPC_SECRET" --arg url "$URL" --arg dir "$target_dir" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.addUri", "params":[$token, [$url], {"dir": $dir}]}')
                                    fi
                                    curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                                    
                                    grep -v -F "$URL" "$CANCELED_FILE" > "${CANCELED_FILE}.tmp"; mv "${CANCELED_FILE}.tmp" "$CANCELED_FILE"
                                elif [[ "$KEY" == "c" ]]; then
                                    grep -v -F "$URL" "$CANCELED_FILE" > "${CANCELED_FILE}.tmp"; mv "${CANCELED_FILE}.tmp" "$CANCELED_FILE"
                                    local URL_BASE=$(basename "$URL")
                                    if [[ -n "$URL_BASE" && "$URL_BASE" != "." && "$URL_BASE" != "/" ]]; then
                                        for d in "$TEMP_DIR"/*/; do if [[ -d "$d" ]] && find "$d" -name "$URL_BASE*" -print -quit | grep -q .; then rm -rf "$d"; fi; done
                                    fi
                                fi
                            fi
                        done <<< "$SELECTIONS"
                    fi
                done
                ;;
                
            *7.*)
                if ! is_daemon_running; then start_daemon; fi
                local CURRENT_LIMIT=$(curl -s -d '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.getGlobalOption", "params":["token:'"$RPC_SECRET"'"]}' "http://localhost:$RPC_PORT/jsonrpc" | jq -r '.result."max-overall-download-limit"')
                [[ "$CURRENT_LIMIT" == "0" ]] && local STATUS="Unlimited" || local STATUS="${CURRENT_LIMIT}"
                local SPEED=$(echo "" | fzf --print-query --prompt="Speed Limit (Current: $STATUS) e.g., 2M, 500K, 0 (Esc to cancel) ❯ " --bind="esc:abort" | head -n 1)
                if [[ -n "$SPEED" && "$SPEED" =~ ^[0-9]+[KMkm]?$ ]]; then
                    local payload=$(jq -n --arg token "token:$RPC_SECRET" --arg sp "$SPEED" '{"jsonrpc":"2.0", "id":"qdl", "method":"aria2.changeGlobalOption", "params":[$token, {"max-overall-download-limit": $sp}]}')
                    curl -s -d "$payload" "http://localhost:$RPC_PORT/jsonrpc" > /dev/null
                fi
                ;;
                
            *8.*|"")
                check_daemon_shutdown
                break
                ;;
        esac
    done
}

# Start main loop
start_tui
tput rmcup

