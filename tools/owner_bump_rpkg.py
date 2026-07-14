#!/usr/bin/env python3
"""
tools/owner_bump_rpkg.py  —  JR Anchored owner use only

Automated CRAN binary-drift fix (the "TROUBLESHOOTING entry 13" workflow that
was run manually for FrF2, igraph ×2, rlang, and colorspace). Detects R
packages whose pinned version is no longer served by CRAN, applies the fix,
proves it with the targeted OQ suites, and pushes the result to origin/main.

Pipeline (per drifted package, mirroring the manual sessions):
  1. Detect  — runs tools/owner_check_versions.py and parses its
               "→ R_requirements.txt:  pkg==old  →  pkg==new" lines.
  2. Fix     — ./admin/admin_install_R --add pkg==new  (updates the pin,
               downloads the binary into the local miniCRAN, rebuilds renv).
  3. Hash    — ./admin/admin_create_hash twice; the two manifests must be
               identical (stability check from Session 45).
  4. Prove   — ./admin/admin_oq_all_smart pkg...  (targeted OQ suites from
               admin/package_oq_matrix.md; unknown packages fall back to a
               full run inside the runner).
  5. Ship    — CHANGELOG entry under [Unreleased]/### Changed, commit staging
               exactly admin/R_requirements.txt + CHANGELOG.md, push
               origin/main. A RELEASE is still needed afterwards: new
               customer installs keep failing until the release branch
               carries the new pin.

NOT auto-fixed (always manual): R version drift (needs full rebuild +
revalidation) and Python package drift (different repo mechanics).

Guardrails, checked BEFORE anything is mutated: repo on `main`, no unpushed
commits (the push must send this fix and nothing else), no staged changes,
R_requirements.txt + CHANGELOG.md unmodified. If OQ fails, nothing is
committed and the working tree is deliberately left as-is for post-mortem
(the renv environment and local miniCRAN have already changed on disk;
reverting only the pin would desync them).

Exit codes (consumed by tools/owner_daily_check.sh):
    0 — no R-package drift (nothing to do)
    1 — fix attempted but FAILED (install, hash instability, OQ red, or git
        error) — working tree may be dirty; investigate before anything else
    2 — drift found but not auto-fixable (guards failed, or R-version /
        Python drift needing manual handling)
    3 — drift fixed, OQ green, committed and pushed to origin/main

Usage:
    python3 tools/owner_bump_rpkg.py [--check-only] [--no-push]

    --check-only  detect and report only; never mutate anything
    --no-push     full pipeline through the local commit, but no push
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
CHECKER      = os.path.join(SCRIPT_DIR, "owner_check_versions.py")
CHANGELOG    = os.path.join(PROJECT_ROOT, "CHANGELOG.md")
INTEGRITY    = os.path.join(PROJECT_ROOT, "admin", "project_integrity.sha256")

EXIT_OK, EXIT_FAILED, EXIT_MANUAL, EXIT_FIXED = 0, 1, 2, 3

R_DRIFT_RE  = re.compile(
    r"→ R_requirements\.txt:\s+(\S+)==(\S+)\s+→\s+\1==(\S+)")
R_VER_RE    = re.compile(r"→ r_version\.txt:")
# Only REQUIRED Python updates count; "(optional)" lines are advisory —
# pip keeps serving old wheels, so an optional newer version is not drift.
PY_DRIFT_RE = re.compile(r"→ python_requirements\.txt:(?!.*\(optional\)).*$",
                         re.MULTILINE)


def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    kw.setdefault("cwd", PROJECT_ROOT)
    return subprocess.run(cmd, **kw)


def git(*args, **kw):
    return run(["git", "-C", PROJECT_ROOT, *args], **kw)


# ---------------------------------------------------------------------------
# Detect
# ---------------------------------------------------------------------------

def detect():
    """Run the version checker; return (r_bumps, r_version_drift, py_drift).

    r_bumps is a list of (pkg, old, new). A checker exit of 2 (config error)
    or an unreachable network shows up as no parsable drift lines — treated
    as nothing to do; the plain daily version check still reports it.
    """
    r = run([sys.executable, CHECKER], timeout=300)
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode == 0:
        # Checker says releasable — optional updates only; nothing actionable.
        return [], False, False
    bumps = [(m.group(1), m.group(2), m.group(3))
             for m in R_DRIFT_RE.finditer(out)]
    return bumps, bool(R_VER_RE.search(out)), bool(PY_DRIFT_RE.search(out))


# ---------------------------------------------------------------------------
# Guards (checked before anything is mutated)
# ---------------------------------------------------------------------------

def guards_ok():
    branch = git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if branch != "main":
        print(f"  Repo is on '{branch}', not 'main' — not auto-fixing.")
        return False
    git("fetch", "origin", "main", "--quiet", timeout=60)
    ahead = git("rev-list", "--count", "origin/main..main").stdout.strip()
    if ahead != "0":
        print(f"  main is ahead of origin/main by {ahead} unpushed commit(s) —")
        print("  the fix push must not publish them. Not auto-fixing.")
        return False
    if git("diff", "--cached", "--quiet").returncode != 0:
        print("  Staged changes present — not auto-fixing.")
        return False
    rel = ["admin/R_requirements.txt", "CHANGELOG.md"]
    if git("status", "--porcelain", "--", *rel).stdout.strip():
        print("  R_requirements.txt or CHANGELOG.md already modified — not auto-fixing.")
        return False
    return True


# ---------------------------------------------------------------------------
# Fix steps
# ---------------------------------------------------------------------------

def install(pkg, new):
    print(f"  admin_install_R --add {pkg}=={new} ...", flush=True)
    r = run([os.path.join(PROJECT_ROOT, "admin", "admin_install_R"),
             "--add", f"{pkg}=={new}"], timeout=3600)
    if r.returncode != 0:
        print(f"  admin_install_R FAILED:\n{r.stdout[-3000:]}{r.stderr[-2000:]}")
        return False
    return True


def create_hash_stable():
    print("  admin_create_hash (twice, stability check) ...", flush=True)
    script = os.path.join(PROJECT_ROOT, "admin", "admin_create_hash")
    r = run([script], timeout=600)
    if r.returncode != 0:
        print(f"  admin_create_hash FAILED:\n{r.stdout[-2000:]}{r.stderr[-2000:]}")
        return False
    with tempfile.NamedTemporaryFile(delete=False) as tf:
        first = tf.name
    shutil.copyfile(INTEGRITY, first)
    try:
        r = run([script], timeout=600)
        if r.returncode != 0:
            print(f"  admin_create_hash (2nd run) FAILED:\n{r.stdout[-2000:]}{r.stderr[-2000:]}")
            return False
        with open(first, "rb") as a, open(INTEGRITY, "rb") as b:
            if a.read() != b.read():
                print("  Integrity manifest NOT stable across two runs — investigate.")
                return False
    finally:
        os.unlink(first)
    return True


def run_oq(pkgs):
    print(f"  admin_oq_all_smart {' '.join(pkgs)} (this can take an hour) ...",
          flush=True)
    r = run([os.path.join(PROJECT_ROOT, "admin", "admin_oq_all_smart"), *pkgs],
            timeout=14400)
    tail = "\n".join((r.stdout or "").splitlines()[-25:])
    print("  --- OQ summary ---")
    print("  " + tail.replace("\n", "\n  "))
    if r.returncode != 0:
        print("  OQ FAILED — nothing will be committed.")
        return False
    return True


# ---------------------------------------------------------------------------
# CHANGELOG + commit + push
# ---------------------------------------------------------------------------

def changelog_entry(bumps):
    lines = ["- **CRAN binary drift fixed (automated).** CRAN stopped serving"]
    lines.append("  the pinned binary for:")
    for pkg, old, new in bumps:
        lines.append(f"  `{pkg}` {old} → {new};")
    lines.append("  bumped via `admin_install_R --add` by")
    lines.append("  `tools/owner_bump_rpkg.py`. Integrity manifest stable across")
    lines.append("  two regenerations; targeted OQ suites (per")
    lines.append("  `admin/package_oq_matrix.md`) all green. Ships to customers")
    lines.append("  with the next release.")
    return "\n".join(lines) + "\n"


def insert_changelog(entry):
    """Insert the bullet under '### Changed' of '## [Unreleased]', creating
    either heading if absent. Anchored on the exact '## [Unreleased]' line —
    never a historical release header."""
    with open(CHANGELOG) as f:
        lines = f.readlines()
    try:
        unrel = next(i for i, l in enumerate(lines)
                     if l.rstrip("\n") == "## [Unreleased]")
    except StopIteration:
        first_rel = next(i for i, l in enumerate(lines) if l.startswith("## ["))
        lines[first_rel:first_rel] = ["## [Unreleased]\n", "\n", "### Changed\n",
                                      "\n", entry, "\n"]
        with open(CHANGELOG, "w") as f:
            f.writelines(lines)
        return
    end = next((i for i in range(unrel + 1, len(lines))
                if lines[i].startswith("## [")), len(lines))
    changed = next((i for i in range(unrel + 1, end)
                    if lines[i].rstrip("\n") == "### Changed"), None)
    if changed is not None:
        at = changed + 1
        if at < len(lines) and lines[at].strip() == "":
            at += 1
        lines[at:at] = [entry, "\n"]
    else:
        lines[unrel + 1:unrel + 1] = ["\n", "### Changed\n", "\n", entry]
    with open(CHANGELOG, "w") as f:
        f.writelines(lines)


def commit_and_push(bumps, no_push):
    insert_changelog(changelog_entry(bumps))
    summary = ", ".join(f"{p} {o}→{n}" for p, o, n in bumps)
    subject = f"fix(deps): CRAN drift — {summary} (auto, OQ green)"
    if len(subject) > 72:
        subject = f"fix(deps): CRAN binary drift — {len(bumps)} pkg(s) bumped (auto)"
    body = ("Detected by owner_check_versions; fixed by tools/owner_bump_rpkg.py:\n"
            + "".join(f"  {p} {o} -> {n}\n" for p, o, n in bumps)
            + "admin_install_R --add, integrity manifest stable across two runs,\n"
              "targeted OQ suites green. Needs a release to reach new installs.")
    rel = ["admin/R_requirements.txt", "CHANGELOG.md"]
    if git("add", "--", *rel).returncode != 0:
        print("  git add failed.")
        return False
    r = git("commit", "-m", f"{subject}\n\n{body}")
    if r.returncode != 0:
        print(f"  git commit failed:\n{r.stdout}{r.stderr}")
        return False
    if no_push:
        print("  --no-push: committed locally, not pushed.")
        return True
    print("  Committed. Pushing to origin/main ...")
    r = git("push", "origin", "main")
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
    check_only = "--check-only" in sys.argv
    no_push    = "--no-push" in sys.argv

    print()
    print("JR Anchored — CRAN Drift Auto-Fix")
    print("=" * 38)

    bumps, r_ver_drift, py_drift = detect()

    if r_ver_drift:
        print("\n🔴  R VERSION drift detected — full rebuild + revalidation is")
        print("    required; this is never auto-fixed. Handle manually first.")
        sys.exit(EXIT_MANUAL)

    if not bumps:
        if py_drift:
            print("\n🟡  Python package drift reported — not handled by this tool")
            print("    (update python_requirements.txt + Python_repo manually).")
            sys.exit(EXIT_MANUAL)
        print("\n✅  No R package drift. Nothing to do.")
        sys.exit(EXIT_OK)

    print("\n🟡  CRAN binary drift detected:")
    for pkg, old, new in bumps:
        print(f"      {pkg}: {old} → {new}")

    if check_only:
        print("\n  --check-only: not fixing.")
        sys.exit(EXIT_MANUAL)

    if not guards_ok():
        print("\n🟡  Drift confirmed but guards prevent auto-fix — run the")
        print("    workflow manually (TROUBLESHOOTING entry 13) or clear the")
        print("    guard condition and re-run.")
        sys.exit(EXIT_MANUAL)

    print()
    for pkg, old, new in bumps:
        if not install(pkg, new):
            sys.exit(EXIT_FAILED)
    if not create_hash_stable():
        sys.exit(EXIT_FAILED)
    if not run_oq([p for p, _, _ in bumps]):
        sys.exit(EXIT_FAILED)

    if not commit_and_push(bumps, no_push):
        sys.exit(EXIT_FAILED)

    print("\n✅  CRAN drift fixed, OQ green, "
          + ("committed (not pushed)." if no_push else "pushed to origin/main."))
    print("    ⚠️  Cut a release when convenient — new customer installs keep")
    print("        failing until the release branch carries the new pin.")
    if py_drift:
        print("    🟡  Python package drift also reported — handle manually.")
    sys.exit(EXIT_FIXED)


if __name__ == "__main__":
    main()
