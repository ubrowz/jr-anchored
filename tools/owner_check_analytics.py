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

Optional morning email (all set as Render secrets, sync: false):
  GMAIL_USER           sending Gmail address (e.g. ubrowz@gmail.com)
  GMAIL_APP_PASSWORD   16-char Gmail app password (needs 2FA enabled)
  ANALYTICS_EMAIL_TO   recipient (defaults to GMAIL_USER)
When GMAIL_USER + GMAIL_APP_PASSWORD are present the table is emailed via
smtp.gmail.com (STARTTLS) as an HTML <pre> block so the columns stay aligned.
Email failures are caught and never fail the cron.

Metric note: GoatCounter's `count` is the page's hit count for the range, as
shown on its dashboard. Day boundaries here are UTC; the GoatCounter dashboard
uses the site timezone, so a single day may differ by the UTC offset.
"""

import html
import json
import os
import smtplib
import ssl
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage


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


def _ascii_safe(s: str) -> str:
    """Coerce to plain ASCII for the email: the table is ASCII data, but a
    GoatCounter path can carry a stray non-breaking space and our titles use an
    em-dash. Map the common ones nicely, then replace anything else."""
    s = s.replace("\u2014", "-").replace("\u2013", "-").replace("\u00a0", " ")
    return s.encode("ascii", "replace").decode("ascii")


def _send_email(subject: str, body: str) -> None:
    """Email the report via Gmail SMTP if configured; otherwise note and skip.
    Never raises — email must not turn the informational check into a failure."""
    user = os.environ.get("GMAIL_USER", "").strip()
    # Gmail shows app passwords as 4x4 groups; the real password is 16 chars with
    # no spaces. Strip ALL whitespace — including the non-breaking spaces (\xa0)
    # that get copied in from Google's UI, which ASCII-encoding in smtp.login()
    # would otherwise choke on.
    password = "".join(os.environ.get("GMAIL_APP_PASSWORD", "").split())
    recipient = os.environ.get("ANALYTICS_EMAIL_TO", user).strip()
    if not (user and password):
        print("  (email not sent — GMAIL_USER / GMAIL_APP_PASSWORD not set)")
        return

    subject = _ascii_safe(subject)
    body = _ascii_safe(body)
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = user
    msg["To"] = recipient
    msg.set_content(body)  # plain-text fallback
    msg.add_alternative(
        '<pre style="font-family:Menlo,Consolas,monospace;font-size:13px">'
        f"{html.escape(body)}</pre>",
        subtype="html",
    )
    try:
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as smtp:
            smtp.starttls(context=_ssl_context())
            smtp.login(user, password)
            smtp.send_message(msg)
        print(f"  Emailed report to {recipient}.")
    except Exception as exc:  # noqa: BLE001 — informational, never fail the cron
        print(f"  ⚠️  Could not send email: {exc}")


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
    header = f"{'PAGE':<{wpath}}  {'ALL-TIME':>9}  {'7-DAY':>7}  {'YESTERDAY':>9}"
    rule = "-" * len(header)

    lines = [
        "JR Anchored — Page Popularity (GoatCounter)",
        f"Windows end {end} (today's partial day excluded)",
        "",
        header,
        rule,
    ]
    t_all = t_7 = t_y = 0
    for path, a, w, y in rows:
        lines.append(f"{path:<{wpath}}  {a:>9}  {w:>7}  {y:>9}")
        t_all += a
        t_7 += w
        t_y += y
    lines.append(rule)
    lines.append(f"{'TOTAL':<{wpath}}  {t_all:>9}  {t_7:>7}  {t_y:>9}")

    report = "\n".join(lines)
    for line in lines:
        print(f"  {line}")
    _send_email(f"JR Anchored — page popularity {end[:10]}", report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
