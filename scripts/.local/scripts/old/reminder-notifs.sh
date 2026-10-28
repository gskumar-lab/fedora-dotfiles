#!/bin/bash

set -e

SCRIPTS="$HOME/.local/scripts"
sleep 5

"$SCRIPTS/tuxedo-wrapper.sh" --reminders-overdue
"$SCRIPTS/tuxedo-wrapper.sh" --reminders-today
"$SCRIPTS/routine-tui.sh" --notify
"$SCRIPTS/productivity-suite.sh" --sync
