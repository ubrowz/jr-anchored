#!/bin/zsh
set -e
#
# setup_path.zsh
# Run once to add the JR Validated Environment project folder to your PATH.
# After running this script, open a new Terminal window and you are ready.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZPROFILE="$HOME/.zprofile"

# --- Check if already added
if grep -q "# JR Validated Environment — begin" "$ZPROFILE" 2>/dev/null; then
  echo "✅ PATH already configured — nothing to do."
  echo "   If scripts are still not found, open a new Terminal window."
  exit 0
fi

# --- Add to .zprofile with begin/end markers for clean removal by uninstall scripts
{
  echo ""
  echo "# JR Validated Environment — begin"
  echo "export PATH=\"\$PATH:$SCRIPT_DIR\""
  echo "# JR Validated Environment — end"
} >> "$ZPROFILE"

echo "✅ PATH updated successfully."
echo ""
echo "👉 Please open a new Terminal window before using JR Scripts."
echo "   You only need to run this script once."
