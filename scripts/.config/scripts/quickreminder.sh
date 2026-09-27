#!/bin/bash

REMINDER_DIR="/tmp/quick-reminders-$USER"
mkdir -p "$REMINDER_DIR"

# Universal cleanup to ensure terminal state is restored on any exit
cleanup() {
  tput rmcup 2>/dev/null
  clear
}
trap cleanup EXIT INT TERM

tput smcup
clear

# Colors
CYAN='\033[1;36m'
GREEN='\033[1;32m'
DIM='\033[2m'
RED='\033[1;31m'
NC='\033[0m'

echo -e "${CYAN}╭──────────────────────────────────────╮${NC}"
echo -e "${CYAN}│              REMINDER                │${NC}"
echo -e "${CYAN}╰──────────────────────────────────────╯${NC}"
echo ""

ACTIVE_JOBS=()
idx=1

# 1. CLEANUP & LOAD
for job_file in "$REMINDER_DIR"/*.job; do
  [ -e "$job_file" ] || continue
  
  # Fail gracefully if file disappears during read
  if ! {
    read -r START_TIME
    read -r SECS
    read -r PID
    read -r MSG
  } < "$job_file" 2>/dev/null; then
    continue
  fi

  # Clean up dead processes
  if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$job_file"
    continue
  fi

  # Calculate time remaining
  NOW=$(date +%s)
  REMAINING=$((SECS - (NOW - START_TIME)))
  [ $REMAINING -lt 0 ] && REMAINING=0
  
  H=$((REMAINING / 3600))
  M=$(((REMAINING % 3600) / 60))
  S=$((REMAINING % 60))
  
  TIME_STR=""
  [ $H -gt 0 ] && TIME_STR="${H}h "
  [ $M -gt 0 ] && TIME_STR="${TIME_STR}${M}m "
  TIME_STR="${TIME_STR}${S}s"
  
  ACTIVE_JOBS[$idx]="$job_file"
  
  echo -e "  [${CYAN}${idx}${NC}] ${TIME_STR} left - ${MSG}"
  ((idx++))
done

if [ ${#ACTIVE_JOBS[@]} -gt 0 ]; then
  echo ""
  PROMPT_TEXT="❯ In how long? (e.g., 15m) OR 'k<id>' to kill: "
else
  PROMPT_TEXT="❯ In how long? (e.g., 15m, 2h, 45): "
fi

# 2. INPUT
read -e -p "$PROMPT_TEXT" TIME_IN
TIME_IN="${TIME_IN// /}"
TIME_IN="${TIME_IN,,}"

# 3. KILL A RUNNING REMINDER
if [[ "$TIME_IN" =~ ^k([0-9]+)$ ]]; then
  kill_idx="${BASH_REMATCH[1]}"
  job_to_kill="${ACTIVE_JOBS[$kill_idx]}"
  
  if [ -f "$job_to_kill" ]; then
    target_pid=$(sed -n '3p' "$job_to_kill")
    
    if [ -n "$target_pid" ]; then
      # Use SIGTERM for safe termination instead of SIGKILL
      pkill -P "$target_pid" 2>/dev/null
      kill -15 "$target_pid" 2>/dev/null
    fi
    rm -f "$job_to_kill"
    
    echo -e "\n${RED}✖ Reminder [${kill_idx}] cancelled.${NC}\n"
  else
    echo -e "\n${DIM}✖ Invalid reminder ID.${NC}\n"
  fi
  
  read -p "Press [ENTER] to close..."
  exit 0
fi

# 4. PARSE TIME (Strict Regex)
SECS=0
if [[ "$TIME_IN" =~ ^([0-9]+)$ ]]; then
  NUM="${BASH_REMATCH[1]}"
  UNIT="m"
  SECS=$((NUM * 60))
elif [[ "$TIME_IN" =~ ^([0-9]+)([smh])$ ]]; then
  NUM="${BASH_REMATCH[1]}"
  UNIT="${BASH_REMATCH[2]}"
  case "$UNIT" in
    s) SECS=$NUM ;;
    m) SECS=$((NUM * 60)) ;;
    h) SECS=$((NUM * 3600)) ;;
  esac
fi

# 5. GET MESSAGE & SET REMINDER
if [ "$SECS" -gt 0 ]; then
  read -e -p "❯ Remind me to: " MSG

  if [ -n "$MSG" ]; then
    # Secure filename generation to prevent collisions
    JOB_FILE=$(mktemp -p "$REMINDER_DIR" reminder_XXXXXX.job)
    START_TIME=$(date +%s)
    
    # The Background Process
    setsid bash -c '
  	sleep "$1"
  	if command -v notify-send &> /dev/null; then
    		notify-send -u critical -t 0  "⏰ Reminder" "$2"
  	else
    	wall "REMINDER: $2" 2>/dev/null || logger "REMINDER: $2"
  	fi
  	rm -f "$3"
' -- "$SECS" "$MSG" "$JOB_FILE" >/dev/null 2>&1 &

BG_PID=$!

    # Write to file AFTER acquiring PID, using printf strictly
    printf "%s\n%s\n%s\n%s\n" "$START_TIME" "$SECS" "$BG_PID" "$MSG" > "$JOB_FILE"
    
    echo -e "\n${GREEN}✔ Reminder set for ${NUM}${UNIT} from now!${NC}\n"
  else
    echo -e "\n${DIM}✖ Cancelled (empty message).${NC}\n"
  fi
else
  echo -e "\n${DIM}✖ Cancelled (invalid time format).${NC}\n"
fi

# 6. PAUSE & CLOSE
read -p "Press [ENTER] to close..."
exit 0

