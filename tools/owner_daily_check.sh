#!/bin/zsh
#
# tools/owner_daily_check.sh  —  JR Anchored owner use only
#
# Runs the version compatibility check and notifies via macOS Notification
# Centre if any packages need updating. Intended to be run as a daily cron job.
#
# Crontab entry (run once via: crontab -e):
#   17 8 * * * /Users/joeprous/Software/JR/jrscripts/tools/owner_daily_check.sh
#
# Log: ~/.jrscript/owner_check.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/owner_check_versions.py"
LOG_FILE="${HOME:-/Users/joeprous}/.jrscript/owner_check.log"
TS="$(date '+%Y-%m-%dT%H:%M:%S')"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# ── Find python3 (PATH is minimal in cron) ────────────────────────────────────
PYTHON=""
for candidate in \
    "$(command -v python3 2>/dev/null)" \
    /usr/bin/python3 \
    /usr/local/bin/python3 \
    /opt/homebrew/bin/python3; do
  if [[ -x "$candidate" ]]; then
    PYTHON="$candidate"
    break
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "$TS  ERROR  python3 not found in any known location" | tee -a "$LOG_FILE"
  exit 1
fi

# ── Run the check ─────────────────────────────────────────────────────────────
OUTPUT="$("$PYTHON" "$CHECK_SCRIPT" 2>&1)"
STATUS=$?

# ── Write to log (always — so a missing entry means the script never ran) ─────
if [[ $STATUS -eq 0 ]]; then
  echo "$TS  OK  all pinned versions match CRAN/PyPI" | tee -a "$LOG_FILE"
else
  {
    echo "$TS  ISSUES FOUND (exit $STATUS)"
    echo "$OUTPUT" | sed 's/^/    /'
    echo ""
  } | tee -a "$LOG_FILE"

  # macOS Notification Centre alert
  osascript -e 'display notification "One or more pinned R or Python package versions no longer match CRAN/PyPI. Run tools/owner_check_versions.py for details." with title "JR Anchored — Version Check" subtitle "Action required before next release"' 2>/dev/null || true
fi
