#!/bin/zsh
#
# tools/owner_daily_check.sh  —  JR Anchored owner use only
#
# Runs the version compatibility check and notifies via macOS Notification
# Centre if any packages need updating. Intended to be run as a daily cron job.
#
# Crontab entry (run once via: crontab -e):
#   17 8 * * * /path/to/jrscripts/tools/owner_daily_check.sh
#
# Log: ~/.jrscript/owner_check.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$(command -v python3)"
CHECK_SCRIPT="$SCRIPT_DIR/owner_check_versions.py"
LOG_FILE="$HOME/.jrscript/owner_check.log"
TS="$(date '+%Y-%m-%dT%H:%M:%S')"

mkdir -p "$(dirname "$LOG_FILE")"

if [[ ! -x "$PYTHON" ]]; then
  echo "$TS  ERROR  python3 not found" >> "$LOG_FILE"
  exit 1
fi

# Run the check and capture output + exit code
OUTPUT="$("$PYTHON" "$CHECK_SCRIPT" 2>&1)"
STATUS=$?

if [[ $STATUS -eq 0 ]]; then
  echo "$TS  OK  all pinned versions match CRAN/PyPI" >> "$LOG_FILE"
else
  # Write full output to log
  echo "$TS  ISSUES FOUND" >> "$LOG_FILE"
  echo "$OUTPUT" | sed 's/^/    /' >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  # Send macOS Notification Centre alert
  osascript -e 'display notification "One or more pinned R or Python package versions no longer match CRAN/PyPI. Run tools/owner_check_versions.py for details." with title "JR Anchored — Version Check" subtitle "Action required before next release"'
fi
