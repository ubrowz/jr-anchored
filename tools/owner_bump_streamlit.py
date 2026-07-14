#!/usr/bin/env python3
"""
tools/owner_bump_streamlit.py  —  JR Anchored owner use only

Automated Streamlit pin maintenance. Checks PyPI for a Streamlit release newer
than the pin in admin/streamlit_version.txt; if one exists, verifies it against
the JR Anchored GUI in a throwaway venv and — when everything passes — bumps
the pin, adds a CHANGELOG entry, regenerates the local integrity manifest, and
commits + pushes the bump to origin/main.

Verification (mirrors the manual checks used for the 1.58.0 → 1.59.0 bump):
  1. Private idle-watchdog API intact — streamlit.runtime.get_instance,
     Runtime._session_mgr, and SessionManager.list_active_sessions all exist.
  2. app/jr_app.py executes without exception under streamlit.testing.v1.AppTest.
  3. Real headless boot — `streamlit run app/jr_app.py` serves
     /_stcore/health == "ok" and the root page returns HTTP 200.

Apply guardrails: the bump is only committed when the repo is on `main` with
no unpushed commits (the push must send the bump and nothing else), no staged
changes, and admin/streamlit_version.txt + CHANGELOG.md unmodified.
Only those two files are staged — never `git add -A`.

Exit codes (consumed by tools/owner_daily_check.sh for notifications):
    0 — nothing to do (pin up to date / ahead), or PyPI unreachable (transient)
    1 — new version FAILED verification: do NOT bump; investigate
    2 — new version verified OK but could not auto-apply (not on main,
        files dirty, or a git/hash step failed) — apply manually
    3 — bump verified, committed, and pushed to origin/main

Usage:
    python3 tools/owner_bump_streamlit.py [--test-only] [--dry-run] [--keep-venv]

    --test-only   check + verify, never touch the repo (exit 2 instead of apply)
    --dry-run     check + verify + edit files, but no commit/push (exit 2)
    --keep-venv   keep the throwaway venv for post-mortem inspection

Requires: Python 3.8+, internet access, git; no third-party packages outside
the throwaway venv.
"""

import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
PIN_FILE     = os.path.join(PROJECT_ROOT, "admin", "streamlit_version.txt")
CHANGELOG    = os.path.join(PROJECT_ROOT, "CHANGELOG.md")
APP_FILE     = os.path.join(PROJECT_ROOT, "app", "jr_app.py")

CURL = shutil.which("curl") or "/usr/bin/curl"

EXIT_OK, EXIT_FAILED, EXIT_NOT_APPLIED, EXIT_BUMPED = 0, 1, 2, 3


def fetch_json(url):
    """Fetch JSON via curl (uses system keychain — avoids Python SSL issues on macOS)."""
    try:
        result = subprocess.run(
            [CURL, "-sfL", "--max-time", "15",
             "-A", "jr-anchored-owner-bump/1.0", url],
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


def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    return subprocess.run(cmd, **kw)


# ---------------------------------------------------------------------------
# Verification in a throwaway venv
# ---------------------------------------------------------------------------

PRIVATE_API_CHECK = r"""
import inspect, sys
from streamlit.runtime import get_instance
assert callable(get_instance), "get_instance not callable"
from streamlit.runtime.runtime import Runtime
assert "_session_mgr" in inspect.getsource(Runtime), "_session_mgr gone from Runtime"
from streamlit.runtime.session_manager import SessionManager
assert callable(getattr(SessionManager, "list_active_sessions", None)), \
    "SessionManager.list_active_sessions missing"
print("private-api-ok")
"""

APPTEST_CHECK = r"""
import sys
from streamlit.testing.v1 import AppTest
at = AppTest.from_file(sys.argv[1], default_timeout=180)
at.run()
if at.exception:
    for e in at.exception:
        print(e.message, file=sys.stderr)
        print(e.stack_trace, file=sys.stderr)
    sys.exit(1)
print("apptest-ok")
"""


def make_venv(version):
    venv_dir = tempfile.mkdtemp(prefix="jr_st_bump_")
    print(f"  Creating throwaway venv: {venv_dir}")
    r = run([sys.executable, "-m", "venv", venv_dir])
    if r.returncode != 0:
        raise RuntimeError(f"venv creation failed:\n{r.stderr}")
    py = os.path.join(venv_dir, "bin", "python")
    print(f"  Installing streamlit=={version} (this can take a minute)...")
    r = run([py, "-m", "pip", "install", "--quiet", f"streamlit=={version}"],
            timeout=600)
    if r.returncode != 0:
        raise RuntimeError(f"pip install streamlit=={version} failed:\n{r.stderr}")
    return venv_dir, py


def check_private_api(py):
    print("  [1/3] Private idle-watchdog API...", end=" ", flush=True)
    r = run([py, "-c", PRIVATE_API_CHECK], timeout=120)
    ok = r.returncode == 0 and "private-api-ok" in r.stdout
    print("OK" if ok else f"FAILED\n{r.stdout}{r.stderr}")
    return ok


def check_apptest(py):
    print("  [2/3] jr_app.py under AppTest...", end=" ", flush=True)
    r = run([py, "-c", APPTEST_CHECK, APP_FILE], cwd=PROJECT_ROOT, timeout=600)
    ok = r.returncode == 0 and "apptest-ok" in r.stdout
    print("OK" if ok else f"FAILED\n{r.stdout}{r.stderr}")
    return ok


def free_port(start=8601, end=8620):
    for port in range(start, end + 1):
        with socket.socket() as s:
            if s.connect_ex(("localhost", port)) != 0:
                return port
    raise RuntimeError("no free port in 8601-8620")


def http_get(url):
    """Return (status_code, body) via curl, (0, '') on transport failure."""
    r = run([CURL, "-s", "--max-time", "5", "-o", "-",
             "-w", "\n%{http_code}", url])
    if r.returncode != 0:
        return 0, ""
    body, _, code = r.stdout.rpartition("\n")
    return (int(code) if code.isdigit() else 0), body


def check_headless_boot(py):
    print("  [3/3] Real headless boot...", end=" ", flush=True)
    port = free_port()
    proc = subprocess.Popen(
        [py, "-m", "streamlit", "run", APP_FILE,
         "--server.port", str(port),
         "--server.address", "localhost",
         "--server.headless", "true",
         "--server.fileWatcherType", "none",
         "--browser.gatherUsageStats", "false"],
        cwd=PROJECT_ROOT, start_new_session=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    ok, detail = False, "server never became healthy"
    try:
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                detail = f"server exited early (rc {proc.returncode})"
                break
            code, body = http_get(f"http://localhost:{port}/_stcore/health")
            if code == 200 and body.strip() == "ok":
                code2, body2 = http_get(f"http://localhost:{port}/")
                ok = code2 == 200 and "<html" in body2.lower()
                detail = "" if ok else f"root page: HTTP {code2}"
                break
            time.sleep(1)
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            proc.wait(timeout=10)
        except Exception:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except Exception:
                pass
    print("OK" if ok else f"FAILED ({detail})")
    return ok


# ---------------------------------------------------------------------------
# Apply: pin + CHANGELOG + integrity hash + commit + push
# ---------------------------------------------------------------------------

def changelog_entry(old, new):
    return (
        f"- **Streamlit pin bumped {old} → {new} (automated).**\n"
        f"  `admin/streamlit_version.txt` — verified by\n"
        f"  `tools/owner_bump_streamlit.py`: idle-watchdog private API intact,\n"
        f"  `app/jr_app.py` runs clean under AppTest, GUI boots and serves\n"
        f"  headless. No effect on analysis — the GUI sits outside the\n"
        f"  validated boundary.\n"
    )


def insert_changelog(old, new):
    """Insert the bump bullet under '### Changed' of '## [Unreleased]',
    creating either heading if absent. Anchored on the exact '## [Unreleased]'
    line — never a historical release header."""
    with open(CHANGELOG) as f:
        lines = f.readlines()

    try:
        unrel = next(i for i, l in enumerate(lines)
                     if l.rstrip("\n") == "## [Unreleased]")
    except StopIteration:
        # No Unreleased section (just after a release cut) — create one above
        # the first release header.
        first_rel = next(i for i, l in enumerate(lines) if l.startswith("## ["))
        block = ["## [Unreleased]\n", "\n", "### Changed\n", "\n",
                 changelog_entry(old, new), "\n"]
        lines[first_rel:first_rel] = block
        with open(CHANGELOG, "w") as f:
            f.writelines(lines)
        return

    # Bounds of the Unreleased section
    end = next((i for i in range(unrel + 1, len(lines))
                if lines[i].startswith("## [")), len(lines))
    changed = next((i for i in range(unrel + 1, end)
                    if lines[i].rstrip("\n") == "### Changed"), None)
    if changed is not None:
        insert_at = changed + 1
        if insert_at < len(lines) and lines[insert_at].strip() == "":
            insert_at += 1
        lines[insert_at:insert_at] = [changelog_entry(old, new), "\n"]
    else:
        lines[unrel + 1:unrel + 1] = ["\n", "### Changed\n", "\n",
                                      changelog_entry(old, new)]
    with open(CHANGELOG, "w") as f:
        f.writelines(lines)


def apply_bump(old, new, dry_run):
    g = lambda *a, **kw: run(["git", "-C", PROJECT_ROOT, *a], **kw)

    branch = g("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if branch != "main":
        print(f"\n  Repo is on '{branch}', not 'main' — not applying.")
        return False
    # Never let the auto-push publish unrelated unpushed work sitting on main:
    # the bump commit must be the ONLY thing the push sends.
    g("fetch", "origin", "main", "--quiet", timeout=60)
    ahead = g("rev-list", "--count", "origin/main..main").stdout.strip()
    if ahead != "0":
        print(f"\n  main is ahead of origin/main by {ahead} unpushed commit(s) —")
        print("  auto-pushing the bump would publish them too. Not applying.")
        return False
    if g("diff", "--cached", "--quiet").returncode != 0:
        print("\n  Staged changes present — not applying.")
        return False
    rel = ["admin/streamlit_version.txt", "CHANGELOG.md"]
    if g("status", "--porcelain", "--", *rel).stdout.strip():
        print("\n  admin/streamlit_version.txt or CHANGELOG.md already modified — not applying.")
        return False

    print(f"\n  Bumping pin {old} -> {new} ...")
    with open(PIN_FILE, "w") as f:
        f.write(new + "\n")
    insert_changelog(old, new)

    print("  Regenerating integrity manifest (admin_create_hash)...")
    r = run([os.path.join(PROJECT_ROOT, "admin", "admin_create_hash")],
            cwd=PROJECT_ROOT, timeout=600)
    if r.returncode != 0:
        print(f"  admin_create_hash FAILED:\n{r.stdout}{r.stderr}")
        print("  Repo files were edited but nothing committed — inspect and finish manually.")
        return False

    if dry_run:
        print("  --dry-run: pin + CHANGELOG edited, integrity regenerated; no commit/push.")
        return False

    msg = (f"chore(gui): bump Streamlit pin {old} → {new} (auto-verified)\n\n"
           f"Verified by tools/owner_bump_streamlit.py: idle-watchdog private API\n"
           f"intact, app runs clean under AppTest, headless boot serves. Local\n"
           f"integrity manifest regenerated.")
    if g("add", "--", *rel).returncode != 0:
        print("  git add failed — finish manually.")
        return False
    r = g("commit", "-m", msg)
    if r.returncode != 0:
        print(f"  git commit failed:\n{r.stdout}{r.stderr}")
        return False
    print("  Committed. Pushing to origin/main...")
    r = g("push", "origin", "main")
    if r.returncode != 0:
        print(f"  git push failed:\n{r.stdout}{r.stderr}")
        print("  Commit is local — push manually.")
        return False
    print("  Pushed.")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    test_only = "--test-only" in sys.argv
    dry_run   = "--dry-run" in sys.argv
    keep_venv = "--keep-venv" in sys.argv

    print()
    print("JR Anchored — Streamlit Auto-Bump")
    print("=" * 38)

    if not os.path.exists(PIN_FILE):
        print(f"\n🔴  Pin file not found: {PIN_FILE}")
        sys.exit(EXIT_FAILED)
    with open(PIN_FILE) as f:
        pinned = f.read().strip()

    data   = fetch_json("https://pypi.org/pypi/streamlit/json")
    latest = data.get("info", {}).get("version") if data else None
    if not latest:
        print("\n🟡  Could not reach PyPI — skipping (will retry tomorrow).")
        sys.exit(EXIT_OK)

    print(f"\n  Pinned (GUI-verified): {pinned}")
    print(f"  Latest on PyPI:        {latest}")

    if version_tuple(latest) <= version_tuple(pinned):
        print("\n✅  Pin is current. Nothing to do.")
        sys.exit(EXIT_OK)

    print(f"\n🟡  Newer Streamlit available: {pinned} → {latest}. Verifying...\n")

    venv_dir = None
    try:
        venv_dir, py = make_venv(latest)
        passed = (check_private_api(py)
                  and check_apptest(py)
                  and check_headless_boot(py))
    except Exception as e:
        print(f"\n🔴  Verification could not run: {e}")
        passed = False
    finally:
        if venv_dir and not keep_venv:
            shutil.rmtree(venv_dir, ignore_errors=True)
        elif venv_dir:
            print(f"  (venv kept at {venv_dir})")

    if not passed:
        print(f"\n🔴  Streamlit {latest} FAILED verification — pin stays at {pinned}.")
        print("    Re-run with --keep-venv to inspect, or test the GUI manually.")
        sys.exit(EXIT_FAILED)

    print(f"\n✅  Streamlit {latest} passed all three checks.")

    if test_only:
        print("  --test-only: not applying. Bump manually or re-run without the flag.")
        sys.exit(EXIT_NOT_APPLIED)

    if apply_bump(pinned, latest, dry_run):
        print(f"\n✅  Pin bumped to {latest}, committed and pushed to origin/main.")
        sys.exit(EXIT_BUMPED)

    print(f"\n🟡  Verified OK but not applied — bump to {latest} manually:")
    print("    1. echo '" + latest + "' > admin/streamlit_version.txt  (on main)")
    print("    2. Add a CHANGELOG entry, run ./admin/admin_create_hash")
    print("    3. Commit both files and push.")
    sys.exit(EXIT_NOT_APPLIED)


if __name__ == "__main__":
    main()
