#!/usr/bin/env python3
"""
tools/owner_check_consistency.py  —  JR Anchored owner use only

Enforces the release contract: what customers clone (the `release` branch,
GitHub's default) must be the latest tagged version, and the live website
must describe exactly that version everywhere.

Checks:
  1. GitHub:  release branch HEAD == latest version tag
  1b. VERSION: the release branch VERSION file == latest version tag
  2. Website: every sitemap page returns 200; the homepage footer and
              JSON-LD softwareVersion carry the tag's version, and NO other
              page shows a version span (single-source since 2026-07-14)
  3. Claims:  homepage stat counters (scripts, OQ tests, modules) match the
              repo working tree and the modules page
  4. Links:   every validation-document PDF linked on downloads.html is live
  5. OQ:      the OQ evidence behind the released version actually covers it —
              every module has a clean, passing evidence file whose recorded
              git commit differs from the release commit in no OQ-covered file

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


def fetch(url, head=False, attempts=3, follow=False):
    """Return (http_code, body). body is empty for HEAD requests.

    An http_code of 0 means curl itself failed (no HTTP status at all).
    Those transport-level failures are retried with a short pause so a single
    network blip does not fail the daily run and email a false alarm; HTTP
    error statuses (404, 500, …) are answers, not blips — returned as-is.

    follow=True chases redirects and reports the FINAL status, so a link that
    301s onto a dead page fails rather than passing on the redirect's 301.
    """
    redirect = ["-L"] if follow else []
    if head:
        cmd = [CURL, "-sI", *redirect, "-o", "/dev/null", "--max-time", "20",
               "-A", "jr-anchored-owner-check/1.0", "-w", "%{http_code}", url]
    else:
        cmd = [CURL, "-s", *redirect, "--max-time", "20",
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

    # Since 2026-07-14 the site shows its version in ONE place: the homepage
    # footer (plus the homepage JSON-LD softwareVersion). Every other page
    # must carry NO version span at all — a hit there is a stale leftover
    # from the old per-page footers. The kfactor page's "v3.0.0" (the R
    # `tolerance` package version) has an id attribute on its span, so the
    # plain <span>vX.Y.Z</span> pattern deliberately does not match it.
    bad_http, stale = [], []
    home_checked = False

    for url in pages:
        code, body = fetch(url)
        if code != 200:
            bad_http.append(f"{url} → HTTP {code}")
            continue
        m = re.search(r"<span>v(\d+\.\d+\.\d+)</span>", body)
        if url.rstrip("/") == SITE or url == SITE + "/":
            home_checked = True
            if not m:
                fail("homepage footer has no version span — it is the only "
                     "page that must carry one")
            elif version and m.group(1) != version:
                fail(f"homepage footer is v{m.group(1)}, expected v{version}")
            else:
                ok(f"homepage footer = v{m.group(1)}")
            m2 = re.search(r'"softwareVersion":\s*"([^"]+)"', body)
            if not m2:
                warn("homepage has no JSON-LD softwareVersion")
            elif version and m2.group(1) != version:
                fail(f"homepage JSON-LD softwareVersion is {m2.group(1)}, "
                     f"expected {version}")
            else:
                ok(f"homepage JSON-LD softwareVersion = {m2.group(1)}")
        elif m:
            stale.append(f"{url} → v{m.group(1)}")

    for item in bad_http:
        fail(f"page not reachable: {item}")
    for item in stale:
        fail(f"stale version span on non-homepage page: {item}")
    if not bad_http and not stale:
        ok("no version spans outside the homepage")
    if not home_checked:
        warn("homepage was not in the sitemap — version + JSON-LD not checked")


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

# ── 5. OQ evidence provenance ────────────────────────────────────────────────
#
# OQ evidence headers record the commit they ran from and an integrity digest
# (added 2026-07-17). This section answers the question the header exists for:
# does the evidence behind the released version actually cover it?
#
# Ancestry is deliberately NOT the test. What matters is whether any file OQ
# EXERCISES differs between the evidence commit and the release commit — if
# none does, the R code under test is identical and the evidence covers the
# release whichever way round the two commits sit. That is what lets a
# VERSION-bump-only release reuse the previous run's evidence honestly, and
# it is why a GUI-only or docs-only change needs no re-run.

# Paths whose contents can change an OQ outcome. bin/ is here because jrrun
# and jr_platform.sh sit in the execution path of every test; app/ is NOT,
# because OQ does not exercise the GUI.
OQ_COVERED = [
    r"^R/", r"^Python/",
    r"^repos/[^/]+/R/", r"^repos/[^/]+/Python/",
    r"^oq/", r"^repos/[^/]+/oq/",
    r"^wrapper/", r"^repos/[^/]+/wrapper/",
    r"^bin/",
    r"^admin/R_requirements\.txt$",
    r"^admin/python_requirements\.txt$",
    r"^admin/renv\.lock$",
    r"^admin/project_id\.txt$",
    r"^admin/admin_oq",
    r"^repos/[^/]+/admin_[^/]*_oq$",
]

EVIDENCE_GLOBS = {
    "core":       "oq_execution_*.txt",
    "as":         "as_oq_execution_*.txt",
    "cap":        "cap_oq_execution_*.txt",
    "clinical":   "clinical_oq_execution_*.txt",
    "corr":       "corr_oq_execution_*.txt",
    "curve":      "curve_oq_execution_*.txt",
    "msa":        "msa_oq_execution_*.txt",
    "rdt":        "rdt_oq_execution_*.txt",
    "shelf_life": "shelf_life_oq_execution_*.txt",
    "spc":        "spc_oq_execution_*.txt",
}


def _git(*args):
    r = subprocess.run(["git", "-C", PROJECT_ROOT] + list(args),
                       capture_output=True, text=True)
    return r.returncode, (r.stdout or "").strip()


def _oq_covered_diff(sha_a, sha_b):
    """Files OQ exercises that differ between two commits. None => unknown."""
    code, out = _git("diff", "--name-only", sha_a, sha_b)
    if code != 0:
        return None
    changed = [l for l in out.splitlines() if l.strip()]
    return [f for f in changed if any(re.search(p, f) for p in OQ_COVERED)]


def _parse_evidence(path):
    """Pull provenance out of an evidence header. Reads only the header."""
    info = {"commit": None, "dirty": None, "digest": None, "failed": None}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh):
            if i > 40 and info["commit"] is not None:
                break
            if line.startswith("Git commit:"):
                v = line.split(":", 1)[1].strip()
                if v.startswith("["):          # graceful-degradation marker
                    info["commit"] = ""
                else:
                    info["commit"] = v.split()[0]
                    info["dirty"] = "DIRTY" in v
            elif line.startswith("Integrity hash:"):
                info["digest"] = line.split(":", 1)[1].strip()
            m = re.search(r"(\d+) failed", line)
            if m:
                info["failed"] = int(m.group(1))
    return info


def check_oq_evidence(tag_name, tag_sha):
    print("\nOQ evidence vs released version")
    print("─" * 48)

    pid_file = os.path.join(PROJECT_ROOT, "admin", "project_id.txt")
    if not os.path.isfile(pid_file):
        warn("project_id.txt not found — cannot locate OQ evidence; skipped")
        return
    with open(pid_file, encoding="utf-8") as fh:
        project_id = fh.read().strip()
    val_dir = os.path.join(os.path.expanduser("~"), ".jrscript", project_id,
                           "validation")
    if not os.path.isdir(val_dir):
        # Expected on the Render host, which has no local OQ evidence.
        warn(f"no evidence directory at {val_dir} — not an OQ host; skipped")
        return
    if not tag_sha:
        warn("release tag SHA unknown — cannot match evidence; skipped")
        return
    if _git("cat-file", "-e", tag_sha + "^{commit}")[0] != 0:
        warn(f"{tag_sha[:7]} not present locally (fetch tags?) — skipped")
        return

    legacy = 0
    for mod, pat in sorted(EVIDENCE_GLOBS.items()):
        files = sorted(glob.glob(os.path.join(val_dir, pat)))
        if not files:
            fail(f"{mod}: no OQ evidence found at all")
            continue

        # Newest first: the most recent run that covers the release wins.
        candidates = []
        for path in reversed(files):
            info = _parse_evidence(path)
            if info["commit"] is None:
                continue                    # predates provenance recording
            candidates.append((path, info))

        if not candidates:
            legacy += 1
            continue

        matched = None
        reasons = []
        for path, info in candidates:
            if not info["commit"]:
                reasons.append("commit not recorded (no git on that host)")
                continue
            if info["dirty"]:
                reasons.append(f"{os.path.basename(path)}: run from a DIRTY tree")
                continue
            if info["failed"]:
                reasons.append(f"{os.path.basename(path)}: {info['failed']} test(s) failed")
                continue
            diff = _oq_covered_diff(info["commit"], tag_sha)
            if diff is None:
                reasons.append(f"{info['commit'][:7]}: not resolvable locally")
                continue
            if diff:
                reasons.append(f"{info['commit'][:7]}: {len(diff)} OQ-covered "
                               f"file(s) differ (e.g. {diff[0]})")
                continue
            matched = (path, info)
            break

        if matched:
            path, info = matched
            same = info["commit"] == tag_sha
            how = "at the release commit" if same else \
                  f"at {info['commit'][:7]} — no OQ-covered file differs"
            ok(f"{mod}: evidence {how}")
        else:
            fail(f"{mod}: no evidence covers {tag_name} "
                 f"({reasons[0] if reasons else 'no usable evidence'})")

    if legacy:
        warn(f"{legacy} module(s) have only pre-2026-07-17 evidence with no "
             f"recorded commit — cannot verify; re-run their OQ to fix")


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


# ── URLs published in shipped scripts and docs ───────────────────────────────

# Only our own hosts: a broken CRAN or python.org link is not ours to fix, and
# third-party rate limiting would make the daily run flaky.
SOURCE_URL_RE = re.compile(
    r'https://(?:www\.)?(?:dwylup\.com|github\.com/ubrowz)[^\s"\'`<>)\]|,]*')

# Directories to scan. docs/ignore/ is deliberately excluded: it is gitignored
# private draft material (LinkedIn copy, doc generators) still referencing the
# pre-rename jr-validated-env repo, so it would fail forever without shipping.
SOURCE_URL_ROOTS = ("admin", "bin", "docs")

# Roots that legitimately serve no directory index. admin_install_R only ever
# requests paths beneath them, so the root returning 403 is correct — but the
# repository still has to be alive, so each is probed via a representative
# sub-path instead of being skipped.
MACHINE_ENDPOINTS = {
    f"{SITE}/packages": "/src/contrib/PACKAGES",
}


def collect_source_urls():
    """Map published URL -> set of files it appears in.

    Skips anything containing a shell or template variable: those are patterns
    like "$JR_PACKAGE_REPO/installers/", not addresses, and cannot be fetched.
    """
    found = {}
    for root in SOURCE_URL_ROOTS:
        base = os.path.join(PROJECT_ROOT, root)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != "ignore"]
            for name in filenames:
                if name.endswith((".pdf", ".docx", ".png", ".zip", ".tgz")):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    with open(path, encoding="utf-8") as f:
                        text = f.read()
                except (UnicodeDecodeError, OSError):
                    continue
                rel = os.path.relpath(path, PROJECT_ROOT)
                for raw in SOURCE_URL_RE.findall(text):
                    url = raw.rstrip(".,;:*")          # markdown bold / sentence punctuation
                    if "$" in url or "{" in url:
                        continue
                    found.setdefault(url, set()).add(rel)
    return found


def check_source_urls():
    """Every URL we publish in shipped scripts and docs still resolves.

    Added after three broken links shipped in a single day (2026-08-02..04):
    nine admin messages pointed at /packages/installers/, which returned 403 for
    a listing; the installer index linked /packages/, also 403; and PLATFORMS.md
    printed a bare repo root that 301s onto that same 403. All three were found
    by hand. Nothing in the review process would have caught them, because a URL
    written into a shell script is never fetched by anything until a user does.
    """
    print("\nURLs in shipped scripts and docs")
    print("─" * 48)

    urls = collect_source_urls()
    if not urls:
        warn("no URLs found to check")
        return

    broken = []
    for url in sorted(urls):
        probe, note = url, ""
        if url in MACHINE_ENDPOINTS:
            probe = url + MACHINE_ENDPOINTS[url]
            note = " (via sub-path — root serves no index by design)"
        code, _ = fetch(probe, head=True, follow=True)
        if code != 200:
            where = ", ".join(sorted(urls[url])[:3])
            broken.append(f"{url} → HTTP {code}{note}  [{where}]")

    for item in broken:
        fail(f"broken URL: {item}")
    if not broken:
        ok(f"all {len(urls)} published URLs resolve (redirects followed)")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("JR Anchored — release/website consistency check")
    print("=" * 48)

    tag_name, tag_sha = check_release_discipline()
    check_version_file(tag_name)
    check_site_versions(tag_name)
    check_claims(tag_sha)
    check_oq_evidence(tag_name, tag_sha)
    check_download_links()
    check_source_urls()

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
