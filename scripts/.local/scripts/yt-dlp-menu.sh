
#!/usr/bin/env bash

# 1. Dependency Check & Auto-Install (Arch Linux)
REQUIRED_DEPS=("yt-dlp" "fzf" "ffmpeg")
MISSING_DEPS=()

for dep in "${REQUIRED_DEPS[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "⚠️ Missing dependencies detected: ${MISSING_DEPS[*]}"
    echo -n "📦 Do you want to install them using pacman (Arch Linux)? [y/N]: "
    read -r install_deps

    if [[ "$install_deps" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed "${MISSING_DEPS[@]}"
        
        # Verify installation succeeded
        for dep in "${MISSING_DEPS[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                echo "❌ Error: $dep failed to install. Exiting."
                exit 1
            fi
        done
        echo "✅ Dependencies installed successfully!"
        echo "-------------------------------------------------"
    else
        echo "❌ These dependencies are required. Exiting."
        exit 1
    fi
fi

# 2. Main Script
echo -n "🔗 Enter YouTube link: "
read -r url

if [[ -z "$url" ]]; then
    echo "❌ Error: URL cannot be empty."
    exit 1
fi

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
    echo "❌ Error: Failed to fetch formats. Check your URL or internet connection."
    exit 1
fi

HEADER=$(echo "$RAW_OUTPUT" | grep -E "^ID\s+EXT")
FORMATS=$(echo "$RAW_OUTPUT" | awk '/^---/{flag=1; next} flag')

# Filter formats for cleaner fzf menus
# Video: Remove "audio only" and useless "storyboard" thumbnail formats
FORMATS_VIDEO=$(echo "$FORMATS" | grep -vi "audio only" | grep -vi "storyboard")
# Audio: Only show "audio only" formats
FORMATS_AUDIO=$(echo "$FORMATS" | grep -i "audio only")

echo "▶️ Select VIDEO format..."
VIDEO_ID=$(echo "$FORMATS_VIDEO" | fzf --header="$HEADER" \
    --prompt="Select VIDEO (Enter to confirm, ESC to skip) > " \
    --reverse | awk '{print $1}')

echo "🎵 Select AUDIO format..."
AUDIO_ID=$(echo "$FORMATS_AUDIO" | fzf --header="$HEADER" \
    --prompt="Select AUDIO (Enter to confirm, ESC to skip) > " \
    --reverse | awk '{print $1}')

echo -n "📝 Download and embed subtitles? [y/N]: "
read -r get_subs

echo -n "🔖 Embed chapters? [y/N]: "
read -r get_chapters

echo -n "📁 Where to save? [Press Enter for ~/Downloads]: "
read -r save_path

# Handle default path and tilde expansion
if [[ -z "$save_path" ]]; then
    save_path="$HOME/Downloads"
else
    # Replace starting ~ with actual home directory path
    save_path="${save_path/#\~/$HOME}"
fi

# Create the directory if it doesn't already exist
mkdir -p "$save_path"

# 3. Build Command
cmd=(yt-dlp -4 $playlist_args -P "$save_path")

if [[ -n "$VIDEO_ID" && -n "$AUDIO_ID" ]]; then
    cmd+=(-f "${VIDEO_ID}+${AUDIO_ID}")
elif [[ -n "$VIDEO_ID" ]]; then
    cmd+=(-f "${VIDEO_ID}")
elif [[ -n "$AUDIO_ID" ]]; then
    cmd+=(-f "${AUDIO_ID}")
else
    echo "⚠️ No formats selected. Defaulting to best video+audio..."
fi

if [[ "$get_subs" =~ ^[Yy]$ ]]; then
    cmd+=(--write-subs --embed-subs --sub-langs "all,en")
fi

if [[ "$get_chapters" =~ ^[Yy]$ ]]; then
    cmd+=(--embed-chapters)
fi

cmd+=("$url")

echo ""
echo "================================================="
echo "🚀 Saving to: $save_path"
echo "🚀 Running: ${cmd[*]}"
echo "================================================="
echo ""

"${cmd[@]}"
