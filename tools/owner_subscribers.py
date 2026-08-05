#!/usr/bin/env python3
"""Encrypted store for release-notification subscribers.

People who ask to be told about validated releases and script defects give us an
email address and nothing else. That is still personal data, so it is never kept
in the repository, never kept on the shared web host, and never kept in plain
text on disk.

Storage model
-------------
    ~/.jrscript/subscribers.json.enc      AES-256-CBC, PBKDF2, 600k iterations
    Keychain item "jranchored-subscribers" holds the passphrase

The web form does not write anywhere: contact.php emails the submission, and the
address is added here by hand with `add`. That keeps the shared host free of any
subscriber list at all, which is the property worth having if it is ever
compromised.

Threat model, stated honestly: this protects the list if the laptop or a backup
is stolen or copied. It is not protection against someone who already has your
unlocked session, because the Keychain will hand them the passphrase exactly as
it does for this tool. `openssl enc` offers no authenticated mode, so tampering
is detected only indirectly: altered ciphertext fails PKCS#7 padding or yields
text that is not valid JSON, and both are reported rather than ignored.

Usage
-----
    owner_subscribers.py init
    owner_subscribers.py add someone@example.com [--name "..."] [--source get-started]
    owner_subscribers.py list [--plain]
    owner_subscribers.py count
    owner_subscribers.py remove someone@example.com        # unsubscribe / erasure
    owner_subscribers.py export                            # addresses, one per line

Exit codes: 0 ok, 1 error, 2 store missing or passphrase unavailable.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

STORE = os.path.expanduser("~/.jrscript/subscribers.json.enc")
KEYCHAIN_SERVICE = "jranchored-subscribers"
PBKDF2_ITER = 600_000

# The consent wording shown on the form. Recorded per subscriber so that if the
# wording changes we can still tell what each person actually agreed to.
CONSENT_VERSION = "2026-08-05"

# Deliberately narrower than RFC 5321. The permissive form [^@\s]+ accepts shell
# metacharacters and ANSI escapes, and although this tool never invokes a shell,
# the address is printed into emails and terminals where a human may act on it.
# An address like a$(id)b@example.com is RFC-valid and becomes remote code
# execution the moment someone pastes a suggested command. The cost is rejecting
# exotic-but-legal addresses (quoted local parts, !#$%&'*/=?^`{|}~); no real
# subscriber has been turned away by that trade in practice.
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,63}$")


def _safe(text: str) -> str:
    """Strip control characters before printing.

    Terminal escape sequences in a stored value can rewrite the screen, so
    anything read back from the store is sanitised on the way out even though
    the validator should have prevented it going in.
    """
    return "".join(c for c in text if c.isprintable())


# ── openssl ──────────────────────────────────────────────────────────────────

def _openssl() -> str:
    """Prefer Homebrew OpenSSL over the system LibreSSL when both are present.

    Both support -pbkdf2, so this is about keeping up with upstream fixes rather
    than capability.
    """
    for path in ("/opt/homebrew/bin/openssl", "/usr/local/bin/openssl"):
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    found = shutil.which("openssl")
    if not found:
        sys.exit("❌ openssl not found; cannot read or write the encrypted store.")
    return found


# ── passphrase ───────────────────────────────────────────────────────────────

def _keychain_passphrase() -> str:
    """Passphrase from the login Keychain, or '' when absent or locked."""
    env = os.environ.get("JR_SUBSCRIBERS_PASSPHRASE", "")
    if env:
        return env
    try:
        out = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=15,
        )
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:  # noqa: BLE001 — security(1) missing or hung
        return ""


def _require_passphrase() -> str:
    pw = _keychain_passphrase()
    if not pw:
        sys.exit(
            "❌ No passphrase available.\n"
            f"   Expected Keychain item '{KEYCHAIN_SERVICE}', or "
            "JR_SUBSCRIBERS_PASSPHRASE in the environment.\n"
            "   Run:  owner_subscribers.py init"
        )
    return pw


# ── encrypted read / write ───────────────────────────────────────────────────

def _decrypt(passphrase: str) -> list[dict]:
    if not os.path.exists(STORE):
        sys.exit(f"❌ No store at {STORE}. Run:  owner_subscribers.py init")
    # NOT text=True. Altered ciphertext decrypts to arbitrary bytes, and letting
    # subprocess decode them raises UnicodeDecodeError with a stack trace instead
    # of reporting the real problem. Decode deliberately, below.
    res = subprocess.run(
        [_openssl(), "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", str(PBKDF2_ITER),
         "-in", STORE, "-pass", "env:JR_PW"],
        capture_output=True, env={**os.environ, "JR_PW": passphrase},
    )
    if res.returncode != 0:
        detail = res.stderr.decode("utf-8", errors="replace").strip().splitlines()
        sys.exit("❌ Could not decrypt the store. Wrong passphrase, or the file has "
                 "been altered.\n   " + (detail[-1] if detail else "(no detail)"))
    try:
        data = json.loads(res.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        sys.exit("❌ The store decrypted to something that is not valid JSON.\n"
                 "   The padding happened to check out but the contents are wrong, "
                 "which means the file has been altered or corrupted.\n"
                 "   Restore from backup rather than trusting this list.")
    if not isinstance(data, list):
        sys.exit("❌ Store has an unexpected shape (expected a list).")
    return data


def _encrypt(records: list[dict], passphrase: str) -> None:
    """Write atomically: a half-written encrypted file is unrecoverable."""
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    payload = json.dumps(records, indent=2, ensure_ascii=False)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(STORE), prefix=".subs-")
    os.close(fd)
    try:
        res = subprocess.run(
            [_openssl(), "enc", "-aes-256-cbc", "-pbkdf2", "-iter", str(PBKDF2_ITER),
             "-out", tmp, "-pass", "env:JR_PW"],
            input=payload, capture_output=True, text=True,
            env={**os.environ, "JR_PW": passphrase},
        )
        if res.returncode != 0:
            sys.exit(f"❌ Encryption failed: {res.stderr.strip()}")
        os.chmod(tmp, 0o600)
        os.replace(tmp, STORE)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


# ── commands ─────────────────────────────────────────────────────────────────

def cmd_init(_args) -> int:
    if os.path.exists(STORE):
        print(f"✅ Store already exists: {STORE}")
        print(f"   {len(_decrypt(_require_passphrase()))} subscriber(s).")
        return 0
    pw = _keychain_passphrase()
    if not pw:
        print("No passphrase found. Create one and store it in the Keychain:\n")
        print("  PW=$(openssl rand -base64 32)")
        print(f'  security add-generic-password -A -s {KEYCHAIN_SERVICE} \\')
        print('      -a "$USER" -w "$PW"\n')
        print("Then re-run:  owner_subscribers.py init")
        return 2
    _encrypt([], pw)
    print(f"✅ Created empty encrypted store: {STORE}")
    print(f"   AES-256-CBC, PBKDF2 with {PBKDF2_ITER:,} iterations, mode 600.")
    return 0


def cmd_add(args) -> int:
    email = args.email.strip().lower()
    if not EMAIL_RE.match(email):
        sys.exit(f"❌ Not a valid email address: {args.email}")
    pw = _require_passphrase()
    recs = _decrypt(pw)
    if any(r.get("email") == email for r in recs):
        print(f"·  {email} is already subscribed; nothing changed.")
        return 0
    recs.append({
        "email": email,
        "name": (args.name or "").strip(),
        "source": args.source,
        "subscribed": _dt.date.today().isoformat(),
        "consent_version": CONSENT_VERSION,
    })
    _encrypt(recs, pw)
    print(f"✅ Added {email}  ({len(recs)} subscriber(s) total).")
    return 0


def cmd_remove(args) -> int:
    email = args.email.strip().lower()
    pw = _require_passphrase()
    recs = _decrypt(pw)
    kept = [r for r in recs if r.get("email") != email]
    if len(kept) == len(recs):
        print(f"·  {email} is not in the store; nothing changed.")
        return 0
    _encrypt(kept, pw)
    print(f"✅ Removed {email}  ({len(kept)} subscriber(s) remaining).")
    return 0


def cmd_list(args) -> int:
    recs = _decrypt(_require_passphrase())
    if not recs:
        print("(no subscribers yet)")
        return 0
    if args.plain:
        for r in recs:
            print(_safe(r["email"]))
        return 0
    width = max(len(r["email"]) for r in recs)
    print(f"{len(recs)} subscriber(s):\n")
    for r in sorted(recs, key=lambda r: r.get("subscribed", "")):
        print(f"  {_safe(r['email']):<{width}}  {_safe(r.get('subscribed','?'))}  "
              f"{_safe(r.get('source','?'))}"
              + (f"  ({_safe(r['name'])})" if r.get("name") else ""))
    return 0


def cmd_count(_args) -> int:
    print(len(_decrypt(_require_passphrase())))
    return 0


def cmd_export(_args) -> int:
    """Addresses only, one per line, for a send step to consume.

    Deliberately separate from sending: an export is easy to inspect before
    anything leaves the machine.
    """
    for r in _decrypt(_require_passphrase()):
        print(_safe(r["email"]))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="create the encrypted store").set_defaults(fn=cmd_init)

    a = sub.add_parser("add", help="add a subscriber")
    a.add_argument("email")
    a.add_argument("--name", default="")
    a.add_argument("--source", default="get-started",
                   help="where they signed up (default: get-started)")
    a.set_defaults(fn=cmd_add)

    r = sub.add_parser("remove", help="remove a subscriber (unsubscribe / erasure)")
    r.add_argument("email")
    r.set_defaults(fn=cmd_remove)

    l = sub.add_parser("list", help="list subscribers")
    l.add_argument("--plain", action="store_true", help="addresses only")
    l.set_defaults(fn=cmd_list)

    sub.add_parser("count", help="number of subscribers").set_defaults(fn=cmd_count)
    sub.add_parser("export", help="addresses, one per line").set_defaults(fn=cmd_export)

    args = p.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
