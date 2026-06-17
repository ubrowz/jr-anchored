#!/usr/bin/env python3
"""
tools/owner_check_streamlit.py  —  JR Anchored owner use only

Checks whether a newer Streamlit release is available than the version pinned
in admin/streamlit_version.txt — the version the JR Anchored GUI is verified to
work with. The GUI warns customers whenever their installed Streamlit differs
from this pin, so the pin should track the latest Streamlit we have tested.

Exit codes (chosen so the Render cron emails only for the actionable case):
    1  — a newer Streamlit is available (action: test the GUI, then bump the pin)
    1  — the pin file is missing (a real config problem worth surfacing)
    0  — pin matches latest, pin is ahead of PyPI, or PyPI was unreachable
          (a transient network failure should not trigger a false-alarm email)

Usage:
    python3 tools/owner_check_streamlit.py

Requires: Python 3.6+, internet access, no third-party packages.
"""

import json
import os
import shutil
import subprocess
import sys

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
PIN_FILE     = os.path.join(PROJECT_ROOT, "admin", "streamlit_version.txt")

CURL = shutil.which("curl") or "/usr/bin/curl"


def fetch_json(url):
    """Fetch JSON via curl (uses system keychain — avoids Python SSL issues on macOS)."""
    try:
        result = subprocess.run(
            [CURL, "-sfL", "--max-time", "10",
             "-A", "jr-anchored-owner-check/1.0", url],
            capture_output=True, text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except Exception:
        pass
    return None


def version_tuple(v):
    """Parse 'X.Y.Z' into a comparable tuple of ints, ignoring any suffix."""
    parts = []
    for piece in v.strip().split("."):
        digits = "".join(ch for ch in piece if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def main():
    print()
    print("JR Anchored — Streamlit Version Check")
    print("=" * 38)

    if not os.path.exists(PIN_FILE):
        print(f"\n🔴  Pin file not found: {PIN_FILE}")
        print("    The GUI reads this file to warn on Streamlit drift — it must exist.")
        sys.exit(1)

    with open(PIN_FILE) as f:
        pinned = f.read().strip()

    data   = fetch_json("https://pypi.org/pypi/streamlit/json")
    latest = data.get("info", {}).get("version") if data else None

    if not latest:
        print("\n🟡  Could not reach PyPI for streamlit — skipping (will retry tomorrow).")
        sys.exit(0)

    print(f"\n  Pinned (GUI-verified): {pinned}")
    print(f"  Latest on PyPI:        {latest}")

    if version_tuple(latest) > version_tuple(pinned):
        print(f"\n🟡  A newer Streamlit is available: {pinned} → {latest}")
        print("\n    Action required:")
        print(f"    1. Install Streamlit {latest} and test the JR Anchored GUI end to end.")
        print(f"    2. If it works: bump admin/streamlit_version.txt to {latest}, push, release.")
        print( "    3. If it breaks: leave the pin as is and note the incompatibility.")
        print()
        sys.exit(1)

    if version_tuple(latest) < version_tuple(pinned):
        print("\n🟡  Pinned version is ahead of the latest PyPI release "
              "(pre-release pinned?). Check manually — no action assumed.")
        print()
        sys.exit(0)

    print("\n✅  Pinned Streamlit matches the latest PyPI release. Nothing to do.")
    print()
    sys.exit(0)


if __name__ == "__main__":
    main()
