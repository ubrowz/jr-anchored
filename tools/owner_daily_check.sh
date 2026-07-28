#!/bin/zsh
#
# tools/owner_daily_check.sh  —  JR Anchored owner use only
#
# Runs the version compatibility check and notifies via macOS Notification
# Centre if any packages need updating. Intended to be run as a daily cron job.
#
# Scheduled via launchd: ~/Library/LaunchAgents/com.jranchored.dailycheck.plist
#   (runs daily ~08:18; a crontab entry previously did this).
#
# Log: ~/.jrscript/owner_check.log

# ── Login-like PATH ───────────────────────────────────────────────────────────
# launchd runs with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin) that EXCLUDES
# /usr/local/bin (R / Rscript), Homebrew, and the R framework. Without this,
# admin_install_R failed "Rscript not found" during the CRAN-drift auto-fix.
# Prepend the standard tool locations so R, python3, gh and curl all resolve.
export PATH="/usr/local/bin:/opt/homebrew/bin:/Library/Frameworks/R.framework/Resources/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/owner_check_versions.py"
LOG_FILE="${HOME:-/Users/joeprous}/.jrscript/owner_check.log"
TS="$(date '+%Y-%m-%dT%H:%M:%S')"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Byte offset into the log before this run. Every section below tees into
# LOG_FILE, so slicing from here at the end yields exactly this run's output —
# which becomes the body of the report email, with no restructuring needed.
if [[ -f "$LOG_FILE" ]]; then
  LOG_OFFSET=$(wc -c < "$LOG_FILE" | tr -d ' ')
else
  LOG_OFFSET=0
fi

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

  # ── CRAN drift auto-fix ─────────────────────────────────────────────────────
  # Version drift detected: try the automated entry-13 workflow
  # (admin_install_R --add → admin_create_hash ×2 stable → targeted OQ →
  # commit + push). Exit codes: 0 no R drift, 1 fix FAILED, 2 manual needed,
  # 3 fixed + pushed. R-version and Python drift are never auto-fixed.
  RPKG_SCRIPT="$SCRIPT_DIR/owner_bump_rpkg.py"
  if [[ -f "$RPKG_SCRIPT" ]]; then
    R_OUTPUT="$("$PYTHON" "$RPKG_SCRIPT" 2>&1)"
    R_STATUS=$?
    {
      echo "$TS  CRAN DRIFT AUTO-FIX (exit $R_STATUS)"
      echo "$R_OUTPUT" | sed 's/^/    /'
      echo ""
    } | tee -a "$LOG_FILE"
    case $R_STATUS in
      3)
        osascript -e 'display notification "CRAN binary drift was fixed automatically: pin bumped, OQ green, pushed to origin/main. Cut a release so new customer installs work again." with title "JR Anchored — CRAN Drift Auto-Fix" subtitle "Fixed and pushed — release needed"' 2>/dev/null || true
        ;;
      1)
        osascript -e 'display notification "CRAN drift auto-fix FAILED mid-workflow — the working tree may be dirty. Inspect ~/.jrscript/owner_check.log before doing anything else in the repo." with title "JR Anchored — CRAN Drift Auto-Fix" subtitle "FAILED — repo needs attention"' 2>/dev/null || true
        ;;
      *)
        osascript -e 'display notification "Version drift detected but not auto-fixed (R version, Python package, or repo guards). Run tools/owner_check_versions.py for details." with title "JR Anchored — Version Check" subtitle "Manual action required"' 2>/dev/null || true
        ;;
    esac
  else
    osascript -e 'display notification "One or more pinned R or Python package versions no longer match CRAN/PyPI. Run tools/owner_check_versions.py for details." with title "JR Anchored — Version Check" subtitle "Action required before next release"' 2>/dev/null || true
  fi
fi

# ── Release/website consistency check ─────────────────────────────────────────
# Asserts: release branch == latest tag == live footer versions == JSON-LD ==
# homepage stat claims; all downloads.html PDFs reachable.

CONSISTENCY_SCRIPT="$SCRIPT_DIR/owner_check_consistency.py"
if [[ -f "$CONSISTENCY_SCRIPT" ]]; then
  C_OUTPUT="$("$PYTHON" "$CONSISTENCY_SCRIPT" 2>&1)"
  C_STATUS=$?
  if [[ $C_STATUS -eq 0 ]]; then
    echo "$TS  OK  release/website consistency check passed" | tee -a "$LOG_FILE"
  else
    {
      echo "$TS  CONSISTENCY ISSUES FOUND (exit $C_STATUS)"
      echo "$C_OUTPUT" | sed 's/^/    /'
      echo ""
    } | tee -a "$LOG_FILE"
    osascript -e 'display notification "Release branch, website versions, stat claims, or download links are inconsistent. Run tools/owner_check_consistency.py for details." with title "JR Anchored — Consistency Check" subtitle "Customer-visible drift detected"' 2>/dev/null || true
  fi
fi

# ── Streamlit auto-bump ───────────────────────────────────────────────────────
# Checks PyPI for a newer Streamlit than the GUI pin; if found, verifies it in
# a throwaway venv (private watchdog API, AppTest, headless boot) and — when
# all checks pass and the repo is on clean main — bumps the pin, updates the
# CHANGELOG, regenerates the integrity manifest, commits and pushes.
# Exit codes: 0 nothing to do, 1 verification failed, 2 verified but not
# applied, 3 bumped + pushed.

BUMP_SCRIPT="$SCRIPT_DIR/owner_bump_streamlit.py"
if [[ -f "$BUMP_SCRIPT" ]]; then
  B_OUTPUT="$("$PYTHON" "$BUMP_SCRIPT" 2>&1)"
  B_STATUS=$?
  case $B_STATUS in
    0)
      echo "$TS  OK  streamlit auto-bump: pin current (or PyPI unreachable)" | tee -a "$LOG_FILE"
      ;;
    3)
      {
        echo "$TS  STREAMLIT PIN AUTO-BUMPED AND PUSHED"
        echo "$B_OUTPUT" | sed 's/^/    /'
        echo ""
      } | tee -a "$LOG_FILE"
      osascript -e 'display notification "A new Streamlit release passed all GUI checks. The pin was bumped, committed, and pushed to origin/main." with title "JR Anchored — Streamlit Auto-Bump" subtitle "Pin updated automatically"' 2>/dev/null || true
      ;;
    *)
      {
        echo "$TS  STREAMLIT BUMP NEEDS ATTENTION (exit $B_STATUS)"
        echo "$B_OUTPUT" | sed 's/^/    /'
        echo ""
      } | tee -a "$LOG_FILE"
      if [[ $B_STATUS -eq 1 ]]; then
        osascript -e 'display notification "A new Streamlit release FAILED GUI verification. The pin was NOT bumped. Run tools/owner_bump_streamlit.py --keep-venv to investigate." with title "JR Anchored — Streamlit Auto-Bump" subtitle "Verification failed"' 2>/dev/null || true
      else
        osascript -e 'display notification "A new Streamlit release passed verification but could not be auto-applied (repo not on clean main). Run tools/owner_bump_streamlit.py from main." with title "JR Anchored — Streamlit Auto-Bump" subtitle "Manual apply needed"' 2>/dev/null || true
      fi
      ;;
  esac
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

# ── Email the run report ──────────────────────────────────────────────────────
# Notification Centre alerts are transient and only land if you're at the Mac.
# Mail the same result so every run is accounted for, including quiet ones.
# Set REPORT_EMAIL=failures to suppress the all-green mail.

REPORT_SCRIPT="$SCRIPT_DIR/owner_send_report.py"
if [[ -f "$REPORT_SCRIPT" ]]; then
  # Exactly the lines this run appended to the log.
  RUN_LOG="$(tail -c "+$((LOG_OFFSET + 1))" "$LOG_FILE" 2>/dev/null)"
  [[ -n "$RUN_LOG" ]] || RUN_LOG="(no output — every check passed silently)"

  # Overall verdict. Order matters: a problem outranks an automated fix, and
  # the drift auto-fix section only runs when something was already wrong.
  if echo "$RUN_LOG" | grep -qE "FAILED|ISSUES FOUND|NEEDS ATTENTION|ERROR"; then
    VERDICT="NEEDS ATTENTION"
  elif echo "$RUN_LOG" | grep -qE "AUTO-BUMPED|AUTO-FIX|PUSHED"; then
    VERDICT="ACTION TAKEN"
  else
    VERDICT="OK"
  fi

  # The traffic snapshot logs nothing, so surface its headline here instead —
  # otherwise the email would under-report what the job actually did.
  TRAFFIC_SUMMARY=""
  if [[ -f "$TRAFFIC_CSV" ]]; then
    TRAFFIC_SUMMARY="$(grep '^clones,' "$TRAFFIC_CSV" | tail -1 | tr -d '"' |
      awk -F, 'NF>=4 {printf "GitHub clones %s: %s (%s unique)", $2, $3, $4}')"
  fi

  if [[ "$REPORT_EMAIL" != "failures" || "$VERDICT" != "OK" ]]; then
    {
      echo "JR Anchored - daily check"
      echo "Run:      $TS on $(scutil --get ComputerName 2>/dev/null || hostname)"
      echo "Verdict:  $VERDICT"
      [[ -n "$TRAFFIC_SUMMARY" ]] && echo "Traffic:  $TRAFFIC_SUMMARY"
      echo "Log:      $LOG_FILE"
      echo ""
      echo "----------------------------------------------------------------"
      echo "$RUN_LOG"
    } | "$PYTHON" "$REPORT_SCRIPT" \
          --subject "JR Anchored daily check - $VERDICT ($(date '+%Y-%m-%d'))" \
      2>&1 | tee -a "$LOG_FILE"
  fi
fi
