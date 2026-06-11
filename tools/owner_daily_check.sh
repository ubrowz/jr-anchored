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

# ── GitHub traffic snapshot ───────────────────────────────────────────────────
# GitHub keeps clone/view stats for only 14 days; archive them daily so
# long-term trends survive. Rows are deduplicated by metric+date, so daily
# re-runs over the overlapping 14-day window are safe.
# CSV: ~/.jrscript/github_traffic.csv  (metric,date,count,uniques)

GH=""
for candidate in \
    "$(command -v gh 2>/dev/null)" \
    /opt/homebrew/bin/gh \
    /usr/local/bin/gh; do
  if [[ -x "$candidate" ]]; then
    GH="$candidate"
    break
  fi
done

TRAFFIC_CSV="${HOME:-/Users/joeprous}/.jrscript/github_traffic.csv"
if [[ -n "$GH" ]]; then
  [[ -f "$TRAFFIC_CSV" ]] || echo "metric,date,count,uniques" > "$TRAFFIC_CSV"
  for metric in clones views; do
    "$GH" api "repos/ubrowz/jr-anchored/traffic/$metric" \
      --jq ".${metric}[] | [.timestamp[0:10], .count, .uniques] | @csv" 2>/dev/null |
    while IFS= read -r row; do
      grep -qF "$metric,$row" "$TRAFFIC_CSV" || echo "$metric,$row" >> "$TRAFFIC_CSV"
    done
  done
  STARS=$("$GH" api repos/ubrowz/jr-anchored --jq .stargazers_count 2>/dev/null)
  TODAY=$(date '+%Y-%m-%d')
  if [[ -n "$STARS" ]] && ! grep -q "^stars,\"$TODAY\"" "$TRAFFIC_CSV"; then
    echo "stars,\"$TODAY\",$STARS," >> "$TRAFFIC_CSV"
  fi

  # Referrers: GitHub only exposes a rolling 14-day aggregate per referrer
  # (no per-day breakdown), so archive one snapshot row per referrer per day:
  #   referrer:<host>,"<date>",count,uniques
  "$GH" api repos/ubrowz/jr-anchored/traffic/popular/referrers \
    --jq ".[] | \"referrer:\(.referrer),\\\"$TODAY\\\",\(.count),\(.uniques)\"" 2>/dev/null |
  while IFS= read -r row; do
    key="${row%,*}"; key="${key%,*}"   # referrer:<host>,"<date>"
    grep -qF "$key" "$TRAFFIC_CSV" || echo "$row" >> "$TRAFFIC_CSV"
  done
fi
