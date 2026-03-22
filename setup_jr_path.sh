#!/bin/bash
set -e
#
# setup_jr_path.sh
# Run once to add the JR Validated Environment project folder to your PATH.
# After running this script, open a new Terminal window and you are ready.
#
# Works on macOS (zsh, writes to ~/.zprofile) and
# Windows Git Bash (bash, writes to ~/.bashrc).
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Platform helpers
# shellcheck source=bin/jr_platform.sh
source "$SCRIPT_DIR/bin/jr_platform.sh"

RC_FILE="$(jr_shell_rc)"

# --- Check if already added
if grep -q "$SCRIPT_DIR/bin" "$RC_FILE" 2>/dev/null; then
  echo "✅ PATH already configured — nothing to do."
  echo "   If scripts are still not found, open a new Terminal window."
  exit 0
fi

# --- Add to RC file with begin/end markers for clean removal by uninstall scripts
{
  echo ""
  echo "# JR Validated Environment — begin"
  echo "export PATH=\"\$PATH:$SCRIPT_DIR/bin:$SCRIPT_DIR/wrapper\""
  echo "for _jr_repo in \"$SCRIPT_DIR/repos\"/*/wrapper; do"
  echo "  [[ -d \"\$_jr_repo\" ]] && export PATH=\"\$PATH:\$_jr_repo\""
  echo "done"
  echo "unset _jr_repo"
  echo "# JR Validated Environment — end"
} >> "$RC_FILE"

echo "✅ PATH updated successfully (added to $RC_FILE)."
echo ""
echo "👉 Please open a new Terminal window before using JR Scripts."
echo "   You only need to run this script once."
