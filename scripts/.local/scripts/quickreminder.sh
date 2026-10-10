#!/bin/bash

REMINDER_DIR="/tmp/quick-reminders-$USER"
mkdir -p "$REMINDER_DIR"

# Universal cleanup to ensure terminal state is restored on any exit
cleanup() {
  tput rmcup 2>/dev/null
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
  
  if ! {
    read -r START_TIME
    read -r SECS
    read -r PID
    read -r MSG
  } < "$job_file" 2>/dev/null; then
    continue
  fi

  # Validate PID is a number, then verify it is alive and belongs to our script
  if ! [[ "$PID" =~ ^[0-9]+$ ]] || ! kill -0 "$PID" 2>/dev/null || ! ps -p "$PID" -o comm= 2>/dev/null | grep -qE "(bash|sleep)"; then
    rm -f "$job_file"
    continue
  fi

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
fi

# Interactive Retry Loop
while true; do
  if [ ${#ACTIVE_JOBS[@]} -gt 0 ]; then
    PROMPT_TEXT="❯ In how long? (e.g., 15m, 14:30) OR 'k<id>' to kill, 'q' to quit: "
  else
    PROMPT_TEXT="❯ In how long? (e.g., 15m, 2h, 45, 14:30) OR 'q' to quit: "
  fi

  read -e -p "$PROMPT_TEXT" TIME_IN
  TIME_IN_CLEAN="${TIME_IN// /}"
  TIME_IN_CLEAN="${TIME_IN_CLEAN,,}"

  if [[ "$TIME_IN_CLEAN" == "q" || "$TIME_IN_CLEAN" == "quit" || -z "$TIME_IN_CLEAN" ]]; then
    echo -e "\n${DIM}Exiting...${NC}\n"
    break
  fi

  # 3. KILL A RUNNING REMINDER
  if [[ "$TIME_IN_CLEAN" =~ ^k([0-9]+)$ ]]; then
    kill_idx="${BASH_REMATCH[1]}"
    job_to_kill="${ACTIVE_JOBS[$kill_idx]}"
    
    if [ -f "$job_to_kill" ]; then
      target_pid=$(sed -n '3p' "$job_to_kill")
      
      if [[ "$target_pid" =~ ^[0-9]+$ ]]; then
        pkill -P "$target_pid" 2>/dev/null
        kill -15 "$target_pid" 2>/dev/null
      fi
      rm -f "$job_to_kill"
      
      echo -e "\n${RED}✖ Reminder [${kill_idx}] cancelled.${NC}\n"
    else
      echo -e "\n${DIM}✖ Invalid reminder ID.${NC}\n"
    fi
    break
  fi

  # 4. PARSE TIME (Strict Regex + Absolute Parsing)
  SECS=0
  if [[ "$TIME_IN_CLEAN" =~ ^([0-9]+)$ ]]; then
    NUM="${BASH_REMATCH[1]}"
    UNIT="m"
    SECS=$((NUM * 60))
  elif [[ "$TIME_IN_CLEAN" =~ ^([0-9]+)([smh])$ ]]; then
    NUM="${BASH_REMATCH[1]}"
    UNIT="${BASH_REMATCH[2]}"
    case "$UNIT" in
      s) SECS=$NUM ;;
      m) SECS=$((NUM * 60)) ;;
      h) SECS=$((NUM * 3600)) ;;
    esac
  elif date -d "$TIME_IN" >/dev/null 2>&1; then
    TARGET_EPOCH=$(date -d "$TIME_IN" +%s)
    NOW=$(date +%s)
    SECS=$((TARGET_EPOCH - NOW))
    [ $SECS -lt 0 ] && SECS=$((SECS + 86400))
    NUM="$TIME_IN"
    UNIT=""
  fi

  # 5. GET MESSAGE & SET REMINDER
  if [ "$SECS" -gt 0 ]; then
    read -r -e -p "❯ Remind me to: " MSG

    MSG="${MSG//$'\n'/ - }"
    MSG="${MSG//$'\r'/}"

    if [ -n "$MSG" ]; then
      JOB_FILE=$(mktemp -p "$REMINDER_DIR" reminder_XXXXXX.job)
      
      # The Background Process
      setsid bash -c '
        SECS="$1"
        MSG="$2"
        JOB_FILE="$3"
        
        # Write the initial job state using the true background bash PID
        printf "%s\n%s\n%s\n%s\n" "$(date +%s)" "$SECS" "$BASHPID" "$MSG" > "$JOB_FILE"
        
        while true; do
            # 1. Suspend / Sleep Resilience Loop
            TARGET=$(( $(date +%s) + SECS ))
            while [ $(date +%s) -lt $TARGET ]; do
                sleep 5
            done
            
            if command -v notify-send &> /dev/null; then
                AUDIO_FILE="/usr/share/sounds/freedesktop/stereo/complete.oga"
                if [ -f "$AUDIO_FILE" ] && command -v paplay &> /dev/null; then
                    paplay "$AUDIO_FILE" 2>/dev/null &
                else
                    echo -e "\a"
                fi
                
                # Interactive "Snooze" Buttons
                RESULT=$(notify-send -u critical -t 0 --action="snooze=Snooze 10m" --action="dismiss=Dismiss" "⏰ Reminder" "$MSG")
                
                if [ "$RESULT" == "snooze" ]; then
                    # Update variables for snooze
                    SECS=600
                    # Overwrite the .job file so the main menu shows the correct 10m remaining time
                    printf "%s\n%s\n%s\n%s\n" "$(date +%s)" "$SECS" "$BASHPID" "$MSG" > "$JOB_FILE"
                    continue
                else
                    break
                fi
            else
                wall "REMINDER: $MSG" 2>/dev/null || logger "REMINDER: $MSG"
                echo -e "\a"
                break
            fi
        done
        
        # Cleanup when finally dismissed
        rm -f "$JOB_FILE"
      ' -- "$SECS" "$MSG" "$JOB_FILE" >/dev/null 2>&1 &

      echo -e "\n${GREEN}✔ Reminder set for ${NUM}${UNIT}!${NC}\n"
      break
    else
      echo -e "\n${DIM}✖ Empty message. Let's try again.${NC}\n"
      continue
    fi
  else
    echo -e "\n${DIM}✖ Invalid time format. Let's try again.${NC}\n"
    continue
  fi
done

# 6. PAUSE & CLOSE
read -p "Press [ENTER] to close..."
exit 0

