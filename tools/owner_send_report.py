#!/usr/bin/env python3
"""
owner_send_report.py — email the daily-check run report. Owner use only.

Reads the report body on stdin and mails it to the owner. Called at the end of
tools/owner_daily_check.sh so the launchd job reports its result somewhere
durable — Notification Centre alerts are transient and easy to miss.

    ... | owner_send_report.py --subject "JR Anchored daily check - OK"

Credentials, in order of precedence:
  1. GMAIL_USER / GMAIL_APP_PASSWORD environment variables
  2. macOS Keychain — a generic password item named by --keychain-service
     (default "jranchored-smtp"), where the account is the Gmail address and
     the secret is a Google App Password. Create it once with:

       security add-generic-password -A \\
           -s jranchored-smtp -a you@gmail.com -w 'abcdefghijklmnop'

     -A lets the launchd job read it without an interactive prompt.

The recipient defaults to the sending address; override with REPORT_EMAIL_TO
or --to.

Always exits 0. A mail failure must never turn a healthy check run into a
failed one — the report is already on disk in ~/.jrscript/owner_check.log.

The SMTP path deliberately mirrors _send_email() in owner_check_analytics.py
(that one runs on Render off env vars); kept separate so this Mac-only addition
cannot disturb the verified Render emailer.
"""

import argparse
import html
import os
import smtplib
import ssl
import subprocess
import sys
from email.message import EmailMessage

KEYCHAIN_SERVICE = "jranchored-smtp"


def _ssl_context() -> ssl.SSLContext:
    """Default context; fall back to certifi's CA bundle when the local
    Python lacks system certificates (e.g. python.org builds on macOS)."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def _read_body() -> str:
    """Read the report from stdin as UTF-8, independent of locale.

    launchd runs with a minimal environment and no LANG, so the locale-derived
    encoding of sys.stdin cannot be relied on. Decode the raw bytes explicitly;
    errors="replace" keeps one malformed byte from costing the whole report.

    The body is NOT coerced to ASCII. It is mostly box-drawing rules and status
    markers (─ ✅ → 🟡 🔴) — 1700+ non-ASCII characters in a typical run — and
    an ASCII fold turned every one of them into "?". Nothing requires it: the
    credentials are separate from the payload, and set_content() negotiates a
    UTF-8 charset on its own.
    """
    return sys.stdin.buffer.read().decode("utf-8", errors="replace").rstrip()


def _keychain(service: str, *args: str) -> str:
    """Run security(1) against the login keychain and return its stdout.
    Returns '' if the item is missing or the keychain is locked."""
    try:
        proc = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-s", service, *args],
            capture_output=True, text=True, timeout=15,
        )
    except Exception:  # noqa: BLE001 — security(1) missing or hung
        return ""
    return proc.stdout if proc.returncode == 0 else ""


def _keychain_account(service: str) -> str:
    """The Gmail address stored on the item. Queried with no -a: that flag
    *requires* an account argument, so a bare -a makes security exit non-zero.
    Without it the item's attributes are dumped to stdout, one per line:

        "acct"<blob>="you@gmail.com"
    """
    for line in _keychain(service).splitlines():
        if '"acct"' in line and "=" in line:
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def _credentials(service: str) -> tuple[str, str]:
    """(user, password). Environment wins; Keychain is the launchd fallback."""
    user = os.environ.get("GMAIL_USER", "").strip()
    # Gmail shows app passwords as 4x4 groups; the real secret is 16 chars with
    # no spaces. Strip ALL whitespace, including non-breaking spaces pasted in
    # from Google's UI.
    password = "".join(os.environ.get("GMAIL_APP_PASSWORD", "").split())
    if user and password:
        return user, password

    kc_pw = "".join(_keychain(service, "-w").split())
    kc_user = _keychain_account(service)
    return (user or kc_user), (password or kc_pw)


def main() -> int:
    ap = argparse.ArgumentParser(description="Email the daily-check report.")
    ap.add_argument("--subject", required=True, help="Email subject line.")
    ap.add_argument("--to", default="", help="Recipient (default: sender).")
    ap.add_argument("--keychain-service", default=KEYCHAIN_SERVICE,
                    help=f"Keychain item name (default {KEYCHAIN_SERVICE}).")
    args = ap.parse_args()

    body = _read_body()
    if not body:
        body = "(the daily check produced no output)"

    user, password = _credentials(args.keychain_service)
    if not (user and password):
        print("  (report not emailed - no GMAIL_USER/GMAIL_APP_PASSWORD and "
              f"no '{args.keychain_service}' keychain item)")
        return 0

    recipient = (args.to or os.environ.get("REPORT_EMAIL_TO", "").strip()
                 or user)

    # Subject goes through as-is: EmailMessage RFC 2047-encodes a non-ASCII
    # header itself, and owner_daily_check.sh builds an ASCII subject anyway.
    subject = args.subject

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
        print(f"  Emailed daily-check report to {recipient}.")
    except Exception as exc:  # noqa: BLE001 — never fail the cron over mail
        print(f"  WARNING: could not send report email: {exc}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
