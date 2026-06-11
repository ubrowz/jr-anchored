#!/usr/bin/env python3
"""
owner_check_clones.py — report yesterday's GitHub clones in the daily cron log.

Runs after owner_check_versions.py in the Render cron (see render.yaml).
Purely informational: always exits 0 so it can never turn a healthy
version-check run into a failure email. Long-term archiving of traffic
data is handled separately by tools/owner_daily_check.sh on the owner Mac.

Requires the GITHUB_TOKEN environment variable (set in the Render
dashboard as a secret): a classic PAT with `repo` scope, or a
fine-grained token with read-only Administration permission on the
repository — the GitHub traffic endpoints require push access.
"""

import json
import os
import ssl
import sys
import urllib.request
from datetime import datetime, timedelta, timezone


def _ssl_context() -> ssl.SSLContext:
    """Default context; fall back to certifi's CA bundle when the local
    Python lacks system certificates (e.g. python.org builds on macOS)."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()

REPO = os.environ.get("GITHUB_REPO", "ubrowz/jr-anchored")


def main() -> int:
    print()
    print("JR Anchored — GitHub Clone Check")
    print("=" * 42)

    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        print("  GITHUB_TOKEN not set — skipping clone check.")
        print("  Add it in the Render dashboard (secret env var) to enable.")
        return 0

    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/traffic/clones",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "jr-anchored-owner-check",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30, context=_ssl_context()) as resp:
            data = json.load(resp)
    except Exception as exc:  # noqa: BLE001 — informational check, never fail the cron
        print(f"  ⚠️  Could not fetch clone traffic: {exc}")
        return 0

    days = {d["timestamp"][:10]: d for d in data.get("clones", [])}
    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")

    row = days.get(yesterday)
    if row:
        print(f"  Clones yesterday ({yesterday}): {row['count']} "
              f"({row['uniques']} unique)")
    else:
        print(f"  Clones yesterday ({yesterday}): none reported yet "
              f"(GitHub traffic data can lag a few hours)")

    print(f"  Last 14 days: {data.get('count', 0)} clones "
          f"({data.get('uniques', 0)} unique)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
