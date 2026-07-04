#!/usr/bin/env python3
"""
tools/owner_check_consistency.py  —  JR Anchored owner use only

Enforces the release contract: what customers clone (the `release` branch,
GitHub's default) must be the latest tagged version, and the live website
must describe exactly that version everywhere.

Checks:
  1. GitHub:  release branch HEAD == latest version tag
  1b. VERSION: the release branch VERSION file == latest version tag
  2. Website: every sitemap page returns 200 and carries the tag's version
              in its footer; homepage JSON-LD softwareVersion matches
  3. Claims:  homepage stat counters (scripts, OQ tests, modules) match the
              repo working tree and the modules page
  4. Links:   every validation-document PDF linked on downloads.html is live

Usage:
    python3 tools/owner_check_consistency.py

Exit status: 0 = consistent (warnings allowed), 1 = failures found.
Requires: Python 3.6+, internet access, no third-party packages.
"""

import base64
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

# ── Paths and constants ──────────────────────────────────────────────────────

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

REPO_API = "https://api.github.com/repos/ubrowz/jr-anchored"
SITE     = "https://www.dwylup.com"

CURL = shutil.which("curl") or "/usr/bin/curl"

failures = []
warnings = []


def fail(msg):
    failures.append(msg)
    print(f"  ❌  {msg}")


def warn(msg):
    warnings.append(msg)
    print(f"  🟡  {msg}")


def ok(msg):
    print(f"  ✅  {msg}")


# ── Low-level fetch helpers (curl: uses system keychain on macOS) ────────────

CURL_EXIT = {
    6: "could not resolve host",
    7: "connection failed",
    28: "timeout",
    35: "SSL handshake failed",
    52: "empty reply from server",
    56: "connection reset",
}


def fetch(url, head=False, attempts=3):
    """Return (http_code, body). body is empty for HEAD requests.

    An http_code of 0 means curl itself failed (no HTTP status at all).
    Those transport-level failures are retried with a short pause so a single
    network blip does not fail the daily run and email a false alarm; HTTP
    error statuses (404, 500, …) are answers, not blips — returned as-is.
    """
    if head:
        cmd = [CURL, "-sI", "-o", "/dev/null", "--max-time", "20",
               "-A", "jr-anchored-owner-check/1.0", "-w", "%{http_code}", url]
    else:
        cmd = [CURL, "-s", "--max-time", "20",
               "-A", "jr-anchored-owner-check/1.0",
               "-w", "\n%{http_code}", url]
    for attempt in range(1, attempts + 1):
        # encoding="utf-8" is required: text=True otherwise decodes curl output
        # with the locale default (cp1252 on Windows), which fails on UTF-8 pages.
        result = subprocess.run(cmd, capture_output=True, text=True,
                                encoding="utf-8", errors="replace")
        if head:
            code_s, body = (result.stdout or "").strip(), ""
        elif result.returncode == 0 and "\n" in result.stdout:
            body, _, code_s = result.stdout.rpartition("\n")
            code_s = code_s.strip()
        else:
            code_s, body = "", ""
        code = int(code_s) if code_s.isdigit() else 0
        if code:
            return code, body
        reason = CURL_EXIT.get(result.returncode, "unknown error")
        detail = f"curl exit {result.returncode}: {reason}"
        if attempt < attempts:
            print(f"  ·  {url} — {detail}; retrying in {3 * attempt}s")
            time.sleep(3 * attempt)
        else:
            print(f"  ·  {url} — {detail}; giving up after {attempts} attempts")
    return 0, ""


def fetch_json(url):
    code, body = fetch(url)
    if code == 200 and body.strip():
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            pass
    return None


def semver_key(tag):
    m = re.match(r"v(\d+)\.(\d+)\.(\d+)$", tag)
    return tuple(int(x) for x in m.groups()) if m else (-1, -1, -1)


# ── 1 · Release discipline on GitHub ─────────────────────────────────────────

def check_release_discipline():
    print("\nRelease discipline  (GitHub)")
    print("─" * 48)

    tags = fetch_json(f"{REPO_API}/tags?per_page=100")
    branch = fetch_json(f"{REPO_API}/branches/release")
    if not tags or not branch:
        fail("could not fetch tags or release branch from the GitHub API")
        return None, None

    versioned = [t for t in tags if semver_key(t["name"]) != (-1, -1, -1)]
    if not versioned:
        fail("no vX.Y.Z tags found on GitHub")
        return None, None
    latest = max(versioned, key=lambda t: semver_key(t["name"]))
    tag_name, tag_sha = latest["name"], latest["commit"]["sha"]
    release_sha = branch["commit"]["sha"]

    if release_sha == tag_sha:
        ok(f"release branch is exactly at {tag_name} ({tag_sha[:7]})")
    else:
        fail(f"release branch ({release_sha[:7]}) is NOT at the latest tag "
             f"{tag_name} ({tag_sha[:7]}) — customers clone an untagged state")
    return tag_name, tag_sha


# ── 1b · VERSION file matches the tag ────────────────────────────────────────

def check_version_file(tag_name):
    print("\nVERSION file vs tag  (release branch)")
    print("─" * 48)

    if not tag_name:
        warn("no latest tag known — skipping VERSION file check")
        return
    expected = tag_name.lstrip("v")

    data = fetch_json(f"{REPO_API}/contents/VERSION?ref=release")
    if not data or "content" not in data:
        fail("could not fetch VERSION from the release branch "
             "(file missing or API error)")
        return
    try:
        content = base64.b64decode(data["content"]).decode("utf-8").strip()
    except (ValueError, UnicodeDecodeError):
        fail("VERSION on the release branch could not be decoded")
        return

    if content == expected:
        ok(f"release branch VERSION = {content} (matches {tag_name})")
    else:
        fail(f"release branch VERSION is {content}, expected {expected} "
             f"(must match latest tag {tag_name})")


# ── 2 · Website version coherence ────────────────────────────────────────────

def sitemap_pages():
    code, body = fetch(f"{SITE}/sitemap.xml")
    if code != 200:
        fail(f"sitemap.xml returned HTTP {code}")
        return []
    return re.findall(r"<loc>\s*(\S+?)\s*</loc>", body)


def check_site_versions(tag_name):
    print("\nWebsite version coherence  (live pages)")
    print("─" * 48)

    version = tag_name.lstrip("v") if tag_name else None
    pages = sitemap_pages()
    if not pages:
        return
    ok(f"sitemap lists {len(pages)} pages")

    bad_http, bad_footer, no_footer = [], [], []
    jsonld_checked = False

    for url in pages:
        code, body = fetch(url)
        if code != 200:
            bad_http.append(f"{url} → HTTP {code}")
            continue
        m = re.search(r"<span>v(\d+\.\d+\.\d+)</span>", body)
        if not m:
            no_footer.append(url)
        elif version and m.group(1) != version:
            bad_footer.append(f"{url} → v{m.group(1)}")
        if url.rstrip("/") == SITE or url == SITE + "/":
            jsonld_checked = True
            m2 = re.search(r'"softwareVersion":\s*"([^"]+)"', body)
            if not m2:
                warn("homepage has no JSON-LD softwareVersion")
            elif version and m2.group(1) != version:
                fail(f"homepage JSON-LD softwareVersion is {m2.group(1)}, "
                     f"expected {version}")
            else:
                ok(f"homepage JSON-LD softwareVersion = {m2.group(1)}")

    for item in bad_http:
        fail(f"page not reachable: {item}")
    for item in bad_footer:
        fail(f"footer version mismatch: {item}  (expected v{version})")
    for url in no_footer:
        warn(f"no footer version span found on {url}")
    if not bad_http and not bad_footer:
        ok(f"all reachable pages carry footer v{version}")
    if not jsonld_checked:
        warn("homepage was not in the sitemap — JSON-LD not checked")


# ── 3 · Homepage claims vs repository ────────────────────────────────────────

def repo_counts():
    scripts = [p for p in
               glob.glob(os.path.join(PROJECT_ROOT, "R", "jrc_*.R"))
               + glob.glob(os.path.join(PROJECT_ROOT, "Python", "jrc_*.py"))
               + glob.glob(os.path.join(PROJECT_ROOT, "repos", "*", "R", "jrc_*.R"))
               + glob.glob(os.path.join(PROJECT_ROOT, "repos", "*", "Python", "jrc_*.py"))
               if "hello" not in os.path.basename(p)]
    tests = 0
    for path in glob.glob(os.path.join(PROJECT_ROOT, "oq", "test_*.py")) + \
            glob.glob(os.path.join(PROJECT_ROOT, "repos", "*", "oq", "test_*.py")):
        with open(path, encoding="utf-8") as fh:
            tests += len(re.findall(r"^\s*def test_", fh.read(), re.M))
    return len(scripts), tests


def check_claims(tag_sha=None):
    print("\nHomepage claims vs repository")
    print("─" * 48)

    code, body = fetch(f"{SITE}/")
    if code != 200:
        fail(f"homepage returned HTTP {code}")
        return
    stats = {}
    for m in re.finditer(
            r'hero-v2-stat-value">([^<]+)</div>\s*'
            r'<div class="hero-v2-stat-label">([^<]+)', body):
        stats[m.group(2).strip()] = m.group(1).strip()

    n_scripts, n_tests = repo_counts()

    # The checkout may be ahead of the released state (development on main,
    # or a dirty working tree) — soften count mismatches to warnings then.
    head_sha = subprocess.run(
        ["git", "-C", PROJECT_ROOT, "rev-parse", "HEAD"],
        capture_output=True, text=True,
        encoding="utf-8", errors="replace").stdout.strip()
    dirty = subprocess.run(
        ["git", "-C", PROJECT_ROOT, "status", "--porcelain"],
        capture_output=True, text=True,
        encoding="utf-8", errors="replace").stdout.strip() != ""
    ahead_of_release = dirty or (tag_sha is not None and head_sha != tag_sha)
    report = warn if ahead_of_release else fail

    claimed_scripts = stats.get("Validated scripts")
    if claimed_scripts is None:
        warn("could not parse 'Validated scripts' stat from homepage")
    elif claimed_scripts == str(n_scripts):
        ok(f"homepage claims {claimed_scripts} validated scripts — repo has {n_scripts}")
    else:
        report(f"homepage claims {claimed_scripts} validated scripts, repo has {n_scripts}")

    claimed_tests = stats.get("Automated OQ tests")
    if claimed_tests is None:
        warn("could not parse 'Automated OQ tests' stat from homepage")
    elif claimed_tests == str(n_tests):
        ok(f"homepage claims {claimed_tests} OQ tests — repo has {n_tests}")
    else:
        report(f"homepage claims {claimed_tests} OQ tests, repo has {n_tests}")

    claimed_modules = stats.get("Modules")
    code, mod_body = fetch(f"{SITE}/modules.html")
    n_modules = len(re.findall(r'class="module-title"', mod_body)) if code == 200 else None
    if claimed_modules is None or n_modules is None:
        warn("could not compare module counts (homepage stat or modules.html missing)")
    elif claimed_modules == str(n_modules):
        ok(f"homepage claims {claimed_modules} modules — modules.html lists {n_modules}")
    else:
        fail(f"homepage claims {claimed_modules} modules, modules.html lists {n_modules}")


# ── 4 · Download link health ─────────────────────────────────────────────────

def check_download_links():
    print("\nDownload links  (downloads.html)")
    print("─" * 48)

    code, body = fetch(f"{SITE}/downloads.html")
    if code != 200:
        fail(f"downloads.html returned HTTP {code}")
        return
    links = sorted(set(re.findall(r'href="(docs/[^"]+\.pdf)"', body)))
    if not links:
        warn("no docs/*.pdf links found on downloads.html")
        return
    broken = []
    for rel in links:
        code, _ = fetch(f"{SITE}/{rel}", head=True)
        if code != 200:
            broken.append(f"{rel} → HTTP {code}")
    for item in broken:
        fail(f"broken download link: {item}")
    if not broken:
        ok(f"all {len(links)} PDF download links return 200")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("JR Anchored — release/website consistency check")
    print("=" * 48)

    tag_name, tag_sha = check_release_discipline()
    check_version_file(tag_name)
    check_site_versions(tag_name)
    check_claims(tag_sha)
    check_download_links()

    print("\n" + "=" * 48)
    if failures:
        print(f"❌  OVERALL: {len(failures)} failure(s), "
              f"{len(warnings)} warning(s) — action required.")
        return 1
    if warnings:
        print(f"🟡  OVERALL: consistent — {len(warnings)} warning(s).")
        return 0
    print("✅  OVERALL: fully consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
