#!/usr/bin/env bash

# 1. Dependency Check & Auto-Install (Arch Linux)
MISSING_CMDS=()
MISSING_PKGS=()

check_dep() {
    if ! command -v "$1" &> /dev/null; then
        MISSING_CMDS+=("$1")
        MISSING_PKGS+=("$2")
    fi
}

check_dep "yt-dlp" "yt-dlp"
check_dep "fzf" "fzf"
check_dep "ffmpeg" "ffmpeg"
check_dep "notify-send" "libnotify"

if [[ ${#MISSING_CMDS[@]} -gt 0 ]]; then
    echo "⚠️ Missing dependencies detected: ${MISSING_CMDS[*]}"
    echo -n "📦 Do you want to install them using pacman (Arch Linux)? [y/N]: "
    read -r install_deps

    if [[ "$install_deps" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed "${MISSING_PKGS[@]}"
        
        for cmd in "${MISSING_CMDS[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                echo "❌ Error: $cmd failed to install. Exiting."
                exit 1
            fi
        done
        echo "✅ Dependencies installed successfully!"
        sleep 1
    else
        echo "❌ These dependencies are required. Exiting."
        exit 1
    fi
fi

# 2. Setup App Environment
TMP_BASE="$HOME/.cache/yt-dlp-manager"
mkdir -p "$TMP_BASE"

# Notification Helper
notify() {
    notify-send "yt-dlp Manager" "$1" || echo -e "\n🔔 $1"
}

# 3. Background Download Engine
run_download() {
    local tmp_dir="$1"
    local url=$(cat "$tmp_dir/url.txt")
    local save_path=$(cat "$tmp_dir/save_path.txt")
    
    # Run the command script inside the data directory
    cd "$tmp_dir/data" || return
    
    # Execute the saved command array strictly discarding output
    bash "$tmp_dir/cmd.sh" > /dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Move files to save_path, avoiding hidden glob failures
        shopt -s dotglob nullglob
        for file in "$tmp_dir/data/"*; do
            mv "$file" "$save_path/" 2>/dev/null
        done
        shopt -u dotglob nullglob
        
        # Cleanup isolated temp dir on successful completion
        rm -rf "$tmp_dir"
        notify "✅ Completed: $url"
    else
        # Leave dir intact for retry/resume capability
        notify "⚠️ Incomplete/Cancelled: $url"
    fi
}

# 4. Main Menu Loop
while true; do
    CHOICE=$(printf "1. Start new download\n2. Manage active downloads\n3. Manage incomplete downloads\n4. Exit" | \
        fzf --prompt="YT-DLP Manager > " --height=40% --border=rounded --reverse)
    
    case "$CHOICE" in
        1.*)
            # Setup New Download
            echo -n "🔗 Enter YouTube link (or leave blank to cancel): "
            read -r url
            [[ -z "$url" ]] && continue

            echo -n "📂 Is this a (v)ideo or (p)laylist? [v/p, default: v]: "
            read -r type

            if [[ "$type" == "p" || "$type" == "P" ]]; then
                playlist_args="--yes-playlist"
                format_fetch_args="--yes-playlist --playlist-items 1"
            else
                playlist_args="--no-playlist"
                format_fetch_args="--no-playlist"
            fi

            echo "⏳ Fetching available formats..."
            RAW_OUTPUT=$(yt-dlp -4 -F $format_fetch_args "$url" 2>/dev/null)
            if [[ -z "$RAW_OUTPUT" ]]; then
                echo "❌ Error: Failed to fetch formats."
                sleep 2
                continue
            fi

            HEADER=$(echo "$RAW_OUTPUT" | grep -E "^ID\s+EXT")
            FORMATS=$(echo "$RAW_OUTPUT" | awk '/^---/{flag=1; next} flag')
            FORMATS_VIDEO=$(echo "$FORMATS" | grep -vi "audio only" | grep -vi "storyboard")
            FORMATS_AUDIO=$(echo "$FORMATS" | grep -i "audio only")

            VIDEO_ID=$(echo "$FORMATS_VIDEO" | fzf --header="$HEADER" \
                --prompt="Select VIDEO (Enter to confirm, ESC to skip) > " --reverse | awk '{print $1}')

            AUDIO_ID=$(echo "$FORMATS_AUDIO" | fzf --header="$HEADER" \
                --prompt="Select AUDIO (Enter to confirm, ESC to skip) > " --reverse | awk '{print $1}')

            echo -n "📝 Download and embed subtitles? [y/N]: "
            read -r get_subs
            echo -n "🔖 Embed chapters? [y/N]: "
            read -r get_chapters
            echo -n "📄 Download video description? [y/N]: "
            read -r get_desc
            echo -n "📁 Where to save? [Press Enter for ~/Downloads]: "
            read -r save_path

            [[ -z "$save_path" ]] && save_path="$HOME/Downloads"
            save_path="${save_path/#\~/$HOME}"
            mkdir -p "$save_path"

            # Create isolated job directory
            job_id="job_$(date +%s)"
            tmp_dir="$TMP_BASE/$job_id"
            mkdir -p "$tmp_dir/data"

            # Build command array and append -P for the temp path
            cmd=(yt-dlp -4 $playlist_args -P "$tmp_dir/data")

            if [[ -n "$VIDEO_ID" && -n "$AUDIO_ID" ]]; then
                cmd+=(-f "${VIDEO_ID}+${AUDIO_ID}")
            elif [[ -n "$VIDEO_ID" ]]; then
                cmd+=(-f "${VIDEO_ID}")
            elif [[ -n "$AUDIO_ID" ]]; then
                cmd+=(-f "${AUDIO_ID}")
            fi

            [[ "$get_subs" =~ ^[Yy]$ ]] && cmd+=(--write-subs --embed-subs --sub-langs "all,en")
            [[ "$get_chapters" =~ ^[Yy]$ ]] && cmd+=(--embed-chapters)
            [[ "$get_desc" =~ ^[Yy]$ ]] && cmd+=(--write-description)
            cmd+=("$url")

            # Save state for retry capability
            echo "$url" > "$tmp_dir/url.txt"
            echo "$save_path" > "$tmp_dir/save_path.txt"
            printf "%q " "${cmd[@]}" > "$tmp_dir/cmd.sh"

            # Execute and Disown
            notify "Starting download..."
            run_download "$tmp_dir" &
            disown "$!"
            
            echo "✅ Download started in isolated temp dir. You may safely exit."
            sleep 1.5
            ;;
            
        2.*)
            # View & Manage Active Downloads
            active_processes=$(pgrep -f "yt-dlp.*$TMP_BASE" -a)
            if [ -z "$active_processes" ]; then
                echo "No active downloads currently running."
                sleep 1.5
                continue
            fi
            
            selected_proc=$(echo "$active_processes" | fzf --prompt="Select Active Download > " --height=40% --border=rounded)
            if [ -n "$selected_proc" ]; then
                pid=$(echo "$selected_proc" | awk '{print $1}')
                action=$(printf "Pause\nResume\nCancel\nGo Back" | fzf --prompt="Action > " --height=20% --border=rounded)
                
                case "$action" in
                    Pause) kill -STOP "$pid"; notify "⏸️ Paused job PID: $pid" ;;
                    Resume) kill -CONT "$pid"; notify "▶️ Resumed job PID: $pid" ;;
                    Cancel) kill -TERM "$pid"; notify "⏹️ Cancelled job PID: $pid (Moved to incomplete)" ;;
                    *) ;;
                esac
            fi
            ;;

        3.*)
            # Manage Incomplete Downloads
            shopt -s nullglob
            job_dirs=("$TMP_BASE"/job_*)
            shopt -u nullglob
            
            if [ ${#job_dirs[@]} -eq 0 ]; then
                echo "No incomplete downloads found."
                sleep 1.5
                continue
            fi
            
            # Filter out jobs that are actively running
            list_items=""
            for d in "${job_dirs[@]}"; do
                if pgrep -f "yt-dlp.*$d" > /dev/null; then
                    continue # Skip active jobs
                fi
                u=$(cat "$d/url.txt" 2>/dev/null)
                list_items+="$(basename "$d") | $u\n"
            done
            
            if [ -z "$list_items" ]; then
                echo "No inactive incomplete downloads."
                sleep 1.5
                continue
            fi
            
            selected_inc=$(echo -e "$list_items" | grep -v '^$' | fzf --prompt="Select Incomplete Download > " --height=40% --border=rounded)
            if [ -n "$selected_inc" ]; then
                jid=$(echo "$selected_inc" | awk '{print $1}')
                iact=$(printf "Retry (Resume native)\nClear (Delete temp files)\nGo Back" | fzf --prompt="Action > " --height=20% --border=rounded)
                
                case "$iact" in
                    Retry*)
                        notify "🔄 Retrying $jid"
                        run_download "$TMP_BASE/$jid" &
                        disown "$!"
                        ;;
                    Clear*)
                        rm -rf "$TMP_BASE/$jid"
                        notify "🗑️ Cleared $jid successfully."
                        ;;
                esac
            fi
            ;;
            
        4.*|"")
            echo "👋 Exiting Manager."
            exit 0
            ;;
    esac
done

