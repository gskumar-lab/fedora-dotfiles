#!/bin/bash

# Exit on undefined variables and pipeline failures
set -uo pipefail

TODO_DIR="$HOME"
TODO_FILE="$TODO_DIR/todo.txt"
CARGO_BIN="$HOME/.cargo/bin"

# 1. SETUP TERMINAL COLORS (Using tput for better compatibility)
if [ -t 1 ]; then
    CYAN=$(tput setaf 6 2>/dev/null || true)
    GREEN=$(tput setaf 2 2>/dev/null || true)
    DIM=$(tput dim 2>/dev/null || true)
    NC=$(tput sgr0 2>/dev/null || true)
else
    CYAN="" GREEN="" DIM="" NC=""
fi

# Helper: Clean up terminal state on exit or interrupt
cleanup() {
    tput rmcup 2>/dev/null || true
    exit 1
}

# Helper: Install tuxedo
install_tuxedo() {
    echo "Error: 'tuxedo' is not installed."
    read -p "Would you like to install it now? (Requires git and cargo) [Y/n]: " install_choice
    case "${install_choice:-Y}" in
        [nN]*) 
            echo "Installation aborted." >&2
            exit 1 
            ;;
        *)
            if ! command -v git &> /dev/null || ! command -v cargo &> /dev/null; then
                echo "Error: 'git' and 'cargo' are required to build tuxedo. Please install them first." >&2
                exit 1
            fi
            
            echo "Cloning and building tuxedo..."
            local tmp_dir
            tmp_dir=$(mktemp -d)
            
            # Subshell for building
            (
                cd "$tmp_dir" || exit 1
                # Optimization: Shallow clone to save time and bandwidth
                git clone --depth 1 https://github.com/webstonehq/tuxedo || exit 1
                cd tuxedo || exit 1
                cargo build --release || exit 1
                mkdir -p "$CARGO_BIN"
                cp target/release/tuxedo "$CARGO_BIN/" || exit 1
            ) || { 
                echo "Error: Installation failed." >&2
                rm -rf "$tmp_dir"
                exit 1
            }
            
            rm -rf "$tmp_dir"
            export PATH="$CARGO_BIN:$PATH"
            
            echo -e "\n✅ Tuxedo installed successfully to $CARGO_BIN/tuxedo!"
            echo -e "💡 Note: You may need to add 'export PATH=\"\$HOME/.cargo/bin:\$PATH\"' to your .bashrc or .zshrc."
            sleep 3
            ;;
    esac
}

# 2. DEPENDENCY CHECK
if ! command -v tuxedo &> /dev/null; then
    if [ -x "$CARGO_BIN/tuxedo" ]; then
        export PATH="$CARGO_BIN:$PATH"
    else
        install_tuxedo
    fi
fi

# 3. PARSE CLI ARGUMENTS
PRIORITY=""

while getopts "p:" opt; do
  case $opt in
    p)
      # Locale-safe uppercase conversion
      PRIORITY=$(echo "$OPTARG" | tr '[:lower:]' '[:upper:]')
      if [[ ! "$PRIORITY" =~ ^[A-Z]$ ]]; then
          echo "Error: Priority must be a single letter (A-Z)." >&2
          exit 1
      fi
      ;;
    \?)
      echo "Usage: $(basename "$0") [-p PRIORITY] [task text...] [+PROJECT] [@CONTEXT]" >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND -1))
TASK="$*"

# 4. INTERACTIVE TUI
INTERACTIVE=0

if [ -z "$TASK" ]; then
    INTERACTIVE=1
    
    # Safe cleanup trap
    trap cleanup SIGINT SIGTERM

    tput smcup 2>/dev/null || true
    clear

    echo -e "${CYAN}╭──────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│              QUICK TASK              │${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────╯${NC}"
    echo ""

    if [ -f "$TODO_FILE" ]; then
      echo -e "${DIM}Recent tasks:${NC}"
      tail -n 3 "$TODO_FILE" | sed 's/^/  /'
      echo ""
    fi

    echo -e "${DIM}Tip: You can include +PROJECT and @CONTEXT in your task${NC}"

    read -e -p "❯ Type task: " TASK
    
    if [ -z "$TASK" ]; then
      echo -e "\n${DIM}✖ Cancelled (empty task).${NC}\n"
      read -p "Press [ENTER] to close..."
      cleanup
    fi
    
    if [ -z "$PRIORITY" ]; then
        read -e -p "❯ Priority (A-Z, or leave blank): " PRI_INPUT
        if [ -n "$PRI_INPUT" ]; then
            PRI_TEMP=$(echo "$PRI_INPUT" | tr '[:lower:]' '[:upper:]')
            if [[ "$PRI_TEMP" =~ ^[A-Z]$ ]]; then
                PRIORITY="$PRI_TEMP"
            else
                echo -e "${DIM}Warning: Invalid priority format. Adding without priority.${NC}"
            fi
        fi
    fi
fi

# 5. FORMAT & EXECUTE
FINAL_TASK="${PRIORITY:+"($PRIORITY) "}$TASK"

mkdir -p "$TODO_DIR"
cd "$TODO_DIR" || { echo "Error: Could not navigate to $TODO_DIR" >&2; exit 1; }

if [ "$INTERACTIVE" -eq 1 ]; then
    if tuxedo add "$FINAL_TASK" > /dev/null 2>&1; then
        echo -e "\n${GREEN}✔ Saved successfully!${NC}\n"
    else
        echo -e "\n${DIM}✖ Failed to save task.${NC}\n"
    fi
    read -p "Press [ENTER] to close..."
    tput rmcup 2>/dev/null || true
else
    if tuxedo add "$FINAL_TASK"; then
        echo "Task added successfully!"
    else
        echo "Error: Failed to add task." >&2
        exit 1
    fi
fi

