#!/usr/bin/env python3
"""
owner_prepare_release.py — do the slow, unattendable part of a release. Owner use only.

Runs after tools/owner_bump_rpkg.py has pushed a dependency fix to main. It
takes the repo from "fix is on main" to "everything a release needs is proven",
and then STOPS. Publishing stays a human act:

    1. Bump VERSION (patch by default)
    2. Rename the CHANGELOG's [Unreleased] heading to the new version + date
    3. Commit exactly VERSION + CHANGELOG.md            <- the release commit
    4. admin_create_hash twice, asserting the digest is stable
    5. FULL ./admin/admin_oq_all from a clean tree
    6. Verify every module's newest evidence records the release commit,
       clean, with no failures
    7. Print the publish command and stop

Why this order, and why the full suite: a dependency bump changes
admin/R_requirements.txt, which is in owner_check_consistency.OQ_COVERED, so
EVERY module's existing evidence goes stale — not just the bumped package's.
And owner_bump_rpkg runs its targeted OQ mid-workflow with the tree mutated, so
that evidence is stamped DIRTY (bin/jr_platform.sh writes the marker off a bare
`git status --porcelain`) and owner_check_consistency rejects dirty evidence
outright. Evidence therefore has to be produced AFTER the release commit, from a
clean tree. Nothing may touch the working tree during the run.

What this deliberately does NOT do: create the signed tag, push, advance the
release branch, or publish the GitHub release. A human sees the OQ result and
decides to ship. That gate is the point, not an omission.

Exit codes:
    0 — nothing to prepare (no [Unreleased] content)
    1 — prepared but FAILED (OQ red, or evidence does not verify) — do not publish
    2 — guards blocked it before anything was mutated
    3 — prepared and verified, ready to publish

Usage:
    python3 tools/owner_prepare_release.py [--minor|--major] [--dry-run]
"""

import datetime
import glob
import importlib.util
import os
import re
import subprocess
import sys

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
CHANGELOG    = os.path.join(PROJECT_ROOT, "CHANGELOG.md")
VERSION_FILE = os.path.join(PROJECT_ROOT, "VERSION")

EXIT_OK, EXIT_FAILED, EXIT_MANUAL, EXIT_PREPARED = 0, 1, 2, 3


# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------

def run(cmd, timeout=7200, cwd=PROJECT_ROOT, stdin_text=None):
    """Run a command, capturing output as UTF-8 (never the ambient locale)."""
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout,
                          input=stdin_text)


def git(*args, **kw):
    return run(["git", *args], **kw)


# ---------------------------------------------------------------------------
# Reuse the consistency checker's rules rather than restating them
# ---------------------------------------------------------------------------

def _consistency():
    """Import owner_check_consistency for EVIDENCE_GLOBS and _parse_evidence.

    Importing keeps the module list and the header parser in exactly one place;
    a second copy here could only drift out of sync with the check that
    actually gates the release.
    """
    path = os.path.join(SCRIPT_DIR, "owner_check_consistency.py")
    spec = importlib.util.spec_from_file_location("_occ", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Guards — all checked before anything is mutated
# ---------------------------------------------------------------------------

def guards_ok():
    branch = git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if branch != "main":
        print(f"  Repo is on '{branch}', not 'main' — not preparing.")
        return False
    if git("status", "--porcelain").stdout.strip():
        print("  Working tree is dirty — not preparing (OQ evidence would be "
              "stamped DIRTY and rejected).")
        return False
    git("fetch", "origin", "main", "--quiet", timeout=120)
    ahead = git("rev-list", "--count", "origin/main..main").stdout.strip()
    if ahead != "0":
        print(f"  main is ahead of origin/main by {ahead} commit(s) — push or "
              "drop them first, so the release contains only reviewed work.")
        return False
    if not os.path.isfile(VERSION_FILE) or not os.path.isfile(CHANGELOG):
        print("  VERSION or CHANGELOG.md missing — not preparing.")
        return False
    return True


# ---------------------------------------------------------------------------
# Version + CHANGELOG
# ---------------------------------------------------------------------------

def next_version(bump):
    with open(VERSION_FILE, encoding="utf-8") as fh:
        cur = fh.read().strip()
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", cur)
    if not m:
        return None, None
    major, minor, patch = (int(g) for g in m.groups())
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return cur, f"{major}.{minor}.{patch}"


def unreleased_body(text):
    """The content under '## [Unreleased]', or '' when the section is empty."""
    m = re.search(r"^## \[Unreleased\][^\n]*\n(.*?)(?=^## \[|\Z)",
                  text, re.MULTILINE | re.DOTALL)
    return m.group(1).strip() if m else ""


def rename_unreleased(new_ver, today):
    """Rename the [Unreleased] heading in place.

    Anchored on that exact line: a looser pattern has previously renamed the
    next historical release header instead.
    """
    with open(CHANGELOG, encoding="utf-8") as fh:
        text = fh.read()
    if not re.search(r"^## \[Unreleased\]", text, re.MULTILINE):
        return False
    text = re.sub(r"^## \[Unreleased\][^\n]*$",
                  f"## [{new_ver}] — {today}", text,
                  count=1, flags=re.MULTILINE)
    with open(CHANGELOG, "w", encoding="utf-8") as fh:
        fh.write(text)
    return True


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

def rehash_stable():
    """admin_create_hash twice; return the digest only if it is stable."""
    script = os.path.join(PROJECT_ROOT, "admin", "admin_create_hash")
    integrity = os.path.join(PROJECT_ROOT, "admin", "project_integrity.sha256")
    digests = []
    for attempt in (1, 2):
        r = run([script], timeout=1800)
        if r.returncode != 0:
            print(f"  admin_create_hash failed on attempt {attempt}:")
            print((r.stdout + r.stderr)[-1500:])
            return None
        h = run(["shasum", "-a", "256", integrity])
        digests.append(h.stdout.split()[0] if h.stdout else "")
    if digests[0] != digests[1] or not digests[0]:
        print(f"  Integrity manifest UNSTABLE across regenerations "
              f"({digests[0][:12]} then {digests[1][:12]}) — renv may still be "
              "writing. Not proceeding.")
        return None
    print(f"  Integrity digest stable: {digests[0][:12]}")
    return digests[0]


def full_oq():
    """Run the whole OQ suite. Returns (ok, tail_of_output)."""
    script = os.path.join(PROJECT_ROOT, "admin", "admin_oq_all")
    r = run([script], timeout=7200)
    out = r.stdout + r.stderr
    return r.returncode == 0, out


def oq_test_total(out):
    """Sum pytest's per-suite 'N passed' summary lines.

    Counting the runner's per-test PASSED echo instead undercounts (it gave 785
    against a true 817), so anchor on pytest's own summary lines.
    """
    return sum(int(n) for n in re.findall(r"^=+ (\d+) passed", out, re.MULTILINE))


def verify_evidence(release_sha):
    """Every module must have newest evidence at release_sha, clean, 0 failures."""
    occ = _consistency()
    pid_file = os.path.join(PROJECT_ROOT, "admin", "project_id.txt")
    with open(pid_file, encoding="utf-8") as fh:
        project_id = fh.read().strip()
    val_dir = os.path.join(os.path.expanduser("~"), ".jrscript", project_id,
                           "validation")

    problems = []
    for mod, pat in sorted(occ.EVIDENCE_GLOBS.items()):
        files = sorted(glob.glob(os.path.join(val_dir, pat)))
        if not files:
            problems.append(f"{mod}: no evidence found")
            continue
        info = occ._parse_evidence(files[-1])
        name = os.path.basename(files[-1])
        if info["commit"] != release_sha:
            problems.append(f"{mod}: newest evidence at "
                            f"{(info['commit'] or '?')[:7]}, not the release commit")
        elif info["dirty"]:
            problems.append(f"{mod}: {name} run from a DIRTY tree")
        elif info["failed"]:
            problems.append(f"{mod}: {info['failed']} test(s) failed")
        else:
            print(f"  ✅  {mod}: evidence at the release commit, clean")
    return problems


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    bump = "major" if "--major" in sys.argv else \
           "minor" if "--minor" in sys.argv else "patch"
    dry = "--dry-run" in sys.argv

    print()
    print("JR Anchored — Release Preparation")
    print("=" * 42)

    with open(CHANGELOG, encoding="utf-8") as fh:
        body = unreleased_body(fh.read())
    if not body:
        print("\n✅  CHANGELOG [Unreleased] is empty — nothing to prepare.")
        return EXIT_OK

    if not guards_ok():
        return EXIT_MANUAL

    cur, new = next_version(bump)
    if not new:
        print(f"  VERSION does not parse as X.Y.Z — not preparing.")
        return EXIT_MANUAL
    today = datetime.date.today().isoformat()
    print(f"\n  Unreleased changes present. {cur} → {new} ({bump}), dated {today}.")

    if dry:
        print("\n  --dry-run: stopping before any change.")
        print("  Would: bump VERSION, rename the CHANGELOG heading, commit,")
        print("         rehash twice, run the FULL OQ suite, verify evidence.")
        return EXIT_OK

    # ── 1/2. VERSION + CHANGELOG ────────────────────────────────────────────
    with open(VERSION_FILE, "w", encoding="utf-8") as fh:
        fh.write(new + "\n")
    if not rename_unreleased(new, today):
        print("  Could not find the '## [Unreleased]' heading — reverting.")
        git("checkout", "--", "VERSION")
        return EXIT_MANUAL

    # ── 3. Release commit ───────────────────────────────────────────────────
    git("add", "--", "VERSION", "CHANGELOG.md")
    msg = (f"chore(release): v{new}\n\n"
           "Prepared by tools/owner_prepare_release.py: VERSION bumped and the\n"
           "CHANGELOG [Unreleased] section closed. Full OQ evidence is recorded\n"
           "against this commit. Not yet tagged or published.\n")
    r = git("commit", "-F", "-", stdin_text=msg)
    if r.returncode != 0:
        print("  Release commit failed:")
        print((r.stdout + r.stderr)[-800:])
        return EXIT_FAILED
    release_sha = git("rev-parse", "HEAD").stdout.strip()
    print(f"  Release commit {release_sha[:7]} created (local only).")

    # ── 4. Rehash, twice, stable ────────────────────────────────────────────
    print("\n  admin_create_hash (twice, stability check) ...")
    if rehash_stable() is None:
        print("\n🔴  Integrity manifest unstable — release commit is local; "
              "investigate before publishing.")
        return EXIT_FAILED

    if git("status", "--porcelain").stdout.strip():
        print("\n🔴  Tree went dirty after rehashing — OQ evidence would be "
              "rejected. Not running OQ.")
        return EXIT_FAILED

    # ── 5. Full OQ ──────────────────────────────────────────────────────────
    print("\n  admin_oq_all — FULL suite, all modules (this takes about an hour).")
    print("  Do not touch the working tree until it finishes.")
    ok, out = full_oq()
    total = oq_test_total(out)
    if not ok:
        tail = "\n".join(out.splitlines()[-25:])
        print(f"\n🔴  FULL OQ FAILED ({total} tests counted). Nothing published.")
        print("    The release commit is local and unpushed — inspect, fix, and")
        print("    either amend it or reset it away.")
        print("    --- tail of OQ output ---")
        print(tail)
        return EXIT_FAILED
    print(f"  ✅  Full OQ PASSED — {total} tests, 0 failures.")

    # ── 6. Evidence provenance ──────────────────────────────────────────────
    print("\n  Verifying OQ evidence provenance ...")
    problems = verify_evidence(release_sha)
    if problems:
        print("\n🔴  Evidence does not cover the release commit:")
        for p in problems:
            print(f"      {p}")
        print("    Not publishable as-is. Release commit is local and unpushed.")
        return EXIT_FAILED

    # ── 7. Stop. Hand over. ─────────────────────────────────────────────────
    print()
    print("=" * 42)
    print(f"✅  v{new} PREPARED — full OQ green ({total} tests), evidence "
          f"verified at {release_sha[:7]}.")
    print()
    print("    Nothing has been pushed, tagged, or published. To ship it:")
    print()
    print(f"      git push origin main")
    print(f"      git tag -s v{new} -m 'v{new}'")
    print(f"      git push origin v{new}")
    print(f"      git push origin 'v{new}^{{commit}}:release'")
    print(f"      gh release create v{new} --verify-tag --notes-file <notes>")
    print()
    print("    Then bump the homepage version (footer + JSON-LD) in the")
    print("    jrscripts-web worktree, deploy, and re-run")
    print("    tools/owner_check_consistency.py to confirm all green.")
    print()
    return EXIT_PREPARED


if __name__ == "__main__":
    sys.exit(main())
