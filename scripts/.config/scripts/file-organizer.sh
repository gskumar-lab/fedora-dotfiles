#!/bin/bash

# ==========================================
# Configuration
# ==========================================
SOURCE_DIR="$HOME/Downloads"
LOG_FILE="$SOURCE_DIR/organizer.log"

DIR_IMG="$SOURCE_DIR/Images"
DIR_DOC="$SOURCE_DIR/Documents"
DIR_ARCHIVE="$SOURCE_DIR/Archives"
DIR_MEDIA="$SOURCE_DIR/Media"
DIR_OTHER="$SOURCE_DIR/Others"

# ==========================================
# Helper Function
# ==========================================
show_help() {
    # Get the absolute path of this script to make copy-pasting cron easier
    SCRIPT_PATH=$(readlink -f "$0")
    
    echo "Downloads Organizer Script"
    echo "=========================="
    echo "Sorts files in $SOURCE_DIR into categorized folders."
    echo "Ignores files modified within the last 5 minutes (grace period)."
    echo ""
    echo "Usage:"
    echo "  $0            Run the organizer"
    echo "  $0 -h, --help Show this help menu"
    echo ""
    echo "Crontab Automation (Run every 1 hour):"
    echo "--------------------------------------"
    echo "To run this script automatically at the top of every hour:"
    echo "  1. Open your terminal."
    echo "  2. Type: crontab -e"
    echo "  3. Paste the following line at the very bottom:"
    echo ""
    echo "     0 * * * * $SCRIPT_PATH"
    echo ""
    echo "  4. Save and exit. The script will now run in the background."
    echo "     (Logs are saved to: $LOG_FILE)"
    echo ""
}

# Check for help flags
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# ==========================================
# Main Processing Loop
# ==========================================
mkdir -p "$DIR_IMG" "$DIR_DOC" "$DIR_ARCHIVE" "$DIR_MEDIA" "$DIR_OTHER"

echo "--- Organization started at $(date) ---" >> "$LOG_FILE"

find "$SOURCE_DIR" -maxdepth 1 -type f -mmin +5 -print0 | while IFS= read -r -d '' file; do
    
    filename=$(basename "$file")

    if [[ "$filename" == .* ]] || [[ "$filename" == "organizer.log" ]]; then
        continue
    fi

    if [[ "$filename" == *.crdownload ]] || [[ "$filename" == *.part ]]; then
        continue
    fi

    if [[ "$filename" == *.* ]]; then
        ext="${filename##*.}"
        ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    else
        ext="" 
    fi

    case "$ext" in
        jpg|jpeg|png|gif|svg|webp|bmp) TARGET_DIR="$DIR_IMG" ;;
        pdf|doc|docx|xls|xlsx|ppt|pptx|txt|odt|csv|rtf) TARGET_DIR="$DIR_DOC" ;;
        zip|tar|gz|bz2|7z|rar|xz) TARGET_DIR="$DIR_ARCHIVE" ;;
        mp3|mp4|mkv|avi|mov|wav|flac|m4a|webm) TARGET_DIR="$DIR_MEDIA" ;;
        *) TARGET_DIR="$DIR_OTHER" ;;
    esac

    dest_path="$TARGET_DIR/$filename"
    
    if [ -e "$dest_path" ]; then
        timestamp=$(date +%s)
        if [[ -z "$ext" ]]; then
            dest_path="$TARGET_DIR/${filename}_${timestamp}"
        else
            base="${filename%.*}"
            dest_path="$TARGET_DIR/${base}_${timestamp}.${ext}"
        fi
    fi

    mv "$file" "$dest_path"
    echo "Moved: $filename -> $(basename "$TARGET_DIR")" >> "$LOG_FILE"

done

echo "--- Organization complete ---" >> "$LOG_FILE"

