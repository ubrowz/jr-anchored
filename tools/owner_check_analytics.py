#!/usr/bin/env python3
"""
owner_check_analytics.py — daily GoatCounter page-popularity table.

Runs in the Render cron (see render.yaml), grouped with the other informational
checks. Purely informational: always exits 0 so it can never turn a healthy
version-check run into a failure email.

For each tracked page it prints three windows. All windows END at 00:00 UTC
today, so today's partial (and still-changing) day is excluded and the numbers
are stable whenever the report is read:

  ALL-TIME   cumulative hits up to the start of today
  7-DAY      hits over the 7 complete days ending yesterday
  YESTERDAY  hits during yesterday (the last day of the 7-day window)

Rows are sorted by the 7-DAY column — most popular page of the last week on top.

Requires GOATCOUNTER_API_TOKEN (set as a Render dashboard secret, sync: false):
create it at dwylup.goatcounter.com -> Settings -> Password, MFA, API, with the
"Read statistics" permission.

Metric note: GoatCounter's `count` is the page's hit count for the range, as
shown on its dashboard. Day boundaries here are UTC; the GoatCounter dashboard
uses the site timezone, so a single day may differ by the UTC offset.
"""

import json
import os
import ssl
import sys
import urllib.parse
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


SITE = os.environ.get("GOATCOUNTER_SITE", "dwylup")
BASE = f"https://{SITE}.goatcounter.com/api/v0"
EPOCH = "2020-01-01T00:00:00Z"  # safely before the site existed → "all time"


def _iso(d: datetime) -> str:
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def _fetch_hits(token: str, start: str, end: str) -> dict:
    """Return {path: count} for the half-open window [start, end), following
    GoatCounter's exclude_paths pagination until `more` is false."""
    ctx = _ssl_context()
    totals: dict = {}
    seen_ids: list = []
    while True:
        qs = urllib.parse.urlencode({"start": start, "end": end, "limit": "100"})
        for pid in seen_ids:
            qs += f"&exclude_paths={pid}"
        req = urllib.request.Request(
            f"{BASE}/stats/hits?{qs}",
            headers={
                "Authorization": f"Bearer {token}",
                "User-Agent": "jr-anchored-owner-check",
            },
        )
        with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
            data = json.load(resp)
        for h in data.get("hits", []):
            totals[h["path"]] = h.get("count", 0)
            seen_ids.append(h["path_id"])
        if not data.get("more"):
            return totals


def main() -> int:
    print()
    print("JR Anchored — Page Popularity (GoatCounter)")
    print("=" * 60)

    token = os.environ.get("GOATCOUNTER_API_TOKEN", "").strip()
    if not token:
        print("  GOATCOUNTER_API_TOKEN not set — skipping analytics table.")
        print("  Create a token at dwylup.goatcounter.com -> Settings -> API")
        print("  and add it in the Render dashboard (secret env var).")
        return 0

    now = datetime.now(timezone.utc)
    today0 = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = _iso(today0)
    start_7 = _iso(today0 - timedelta(days=7))
    start_y = _iso(today0 - timedelta(days=1))

    try:
        all_time = _fetch_hits(token, EPOCH, end)
        last7 = _fetch_hits(token, start_7, end)
        yest = _fetch_hits(token, start_y, end)
    except Exception as exc:  # noqa: BLE001 — informational check, never fail the cron
        print(f"  ⚠️  Could not fetch GoatCounter stats: {exc}")
        return 0

    paths = set(all_time) | set(last7) | set(yest)
    rows = [
        (p, all_time.get(p, 0), last7.get(p, 0), yest.get(p, 0))
        for p in paths
    ]
    # Most popular page of the last week on top; ties broken by all-time, then path.
    rows.sort(key=lambda r: (-r[2], -r[1], r[0]))

    if not rows:
        print("  No tracked pages returned yet.")
        return 0

    wpath = max(len("PAGE"), max(len(r[0]) for r in rows))
    header = f"  {'PAGE':<{wpath}}  {'ALL-TIME':>9}  {'7-DAY':>7}  {'YESTERDAY':>9}"
    rule = "  " + "-" * (len(header) - 2)

    print(f"  Windows end {end} (today's partial day excluded)")
    print()
    print(header)
    print(rule)
    t_all = t_7 = t_y = 0
    for path, a, w, y in rows:
        print(f"  {path:<{wpath}}  {a:>9}  {w:>7}  {y:>9}")
        t_all += a
        t_7 += w
        t_y += y
    print(rule)
    print(f"  {'TOTAL':<{wpath}}  {t_all:>9}  {t_7:>7}  {t_y:>9}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
