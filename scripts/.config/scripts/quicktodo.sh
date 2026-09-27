#!/bin/bash

# Quick task adder using tuxedo (with priority support, auto-install, and TUI)

TODO_DIR="$HOME"
TODO_FILE="$TODO_DIR/todo.txt"
CARGO_BIN="$HOME/.cargo/bin"

# 1. DEPENDENCY CHECK & INSTALLATION (Runs before TUI so prompts are visible)
if ! command -v tuxedo &> /dev/null; then
    if [ -x "$CARGO_BIN/tuxedo" ]; then
        export PATH="$CARGO_BIN:$PATH"
    else
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
                TMP_DIR=$(mktemp -d)
                
                (
                    cd "$TMP_DIR" || exit 1
                    git clone https://github.com/webstonehq/tuxedo || exit 1
                    cd tuxedo || exit 1
                    cargo build --release || exit 1
                    mkdir -p "$CARGO_BIN"
                    cp target/release/tuxedo "$CARGO_BIN/" || exit 1
                ) || { 
                    echo "Error: Installation failed." >&2
                    rm -rf "$TMP_DIR"
                    exit 1
                }
                
                rm -rf "$TMP_DIR"
                export PATH="$CARGO_BIN:$PATH"
                
                echo -e "\n✅ Tuxedo installed successfully to $CARGO_BIN/tuxedo!"
                echo -e "💡 Note: You may need to add export PATH=\"\$HOME/.cargo/bin:\$PATH\" to your .bashrc or .zshrc."
                sleep 3
                ;;
        esac
    fi
fi

# 2. PARSE CLI ARGUMENTS
PRIORITY=""

while getopts "p:" opt; do
  case $opt in
    p)
      PRIORITY=$(echo "$OPTARG" | tr 'a-z' 'A-Z')
      if [[ ! "$PRIORITY" =~ ^[A-Z]$ ]]; then
          echo "Error: Priority must be a single letter (A-Z)." >&2
          exit 1
      fi
      ;;
    \?)
      echo "Usage: qtask [-p PRIORITY] [--] [task text...]" >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND -1))
TASK="$*"

# 3. INTERACTIVE TUI (Triggered only if no task was passed via CLI)
INTERACTIVE=0

if [ -z "$TASK" ]; then
    INTERACTIVE=1
    
    # TRAP: Ensure terminal restores perfectly even if you press Ctrl+C
    # Removed 'clear' from the trap to prevent screen flashing on abort
    trap "tput rmcup; exit 1" SIGINT SIGTERM

    # Enter alternate screen buffer
    tput smcup
    clear

    # Define colors for the UI
    CYAN='\033[1;36m'
    GREEN='\033[1;32m'
    DIM='\033[2m'
    NC='\033[0m' # No Color

    echo -e "${CYAN}╭──────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│              QUICK TASK              │${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────╯${NC}"
    echo ""

    # CONTEXT: Show the last 3 tasks so you know where you left off
    if [ -f "$TODO_FILE" ]; then
      echo -e "${DIM}Recent tasks:${NC}"
      tail -n 3 "$TODO_FILE" | sed 's/^/  /'
      echo ""
    fi

    # INPUT: Read the task
    read -e -p "❯ Type task: " TASK
    
    if [ -z "$TASK" ]; then
      echo ""
      echo -e "${DIM}✖ Cancelled (empty task).${NC}"
      echo ""
      read -p "Press [ENTER] to close..."
      tput rmcup
      exit 0
    fi
    
    # INPUT: Priority
    if [ -z "$PRIORITY" ]; then
        read -e -p "❯ Priority (A-Z, or leave blank): " PRI_INPUT
        if [ -n "$PRI_INPUT" ]; then
            PRI_TEMP=$(echo "$PRI_INPUT" | tr 'a-z' 'A-Z')
            if [[ "$PRI_TEMP" =~ ^[A-Z]$ ]]; then
                PRIORITY="$PRI_TEMP"
            else
                echo -e "${DIM}Warning: Invalid priority format. Adding without priority.${NC}"
            fi
        fi
    fi
fi

# 4. FORMAT & EXECUTE
if [ -n "$PRIORITY" ]; then
    FINAL_TASK="($PRIORITY) $TASK"
else
    FINAL_TASK="$TASK"
fi

# Ensure directory exists before navigating (Future-proofing for custom paths)
mkdir -p "$TODO_DIR"
cd "$TODO_DIR" || { echo "Error: Could not navigate to $TODO_DIR" >&2; exit 1; }

# Handle output differently based on whether we are in the TUI or CLI
if [ $INTERACTIVE -eq 1 ]; then
    # Hide tuxedo's standard output in TUI mode to keep it clean
    if tuxedo add "$FINAL_TASK" > /dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✔ Saved successfully!${NC}"
        echo ""
    else
        echo ""
        echo -e "${DIM}✖ Failed to save task.${NC}"
        echo ""
    fi
    
    # PAUSE: Wait for user
    read -p "Press [ENTER] to close..."
    
    # Restore terminal
    tput rmcup
else
    # Standard CLI execution output
    if tuxedo add "$FINAL_TASK"; then
        echo "Task added successfully!"
    else
        echo "Error: Failed to add task." >&2
        exit 1
    fi
fi

