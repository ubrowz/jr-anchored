#!/usr/bin/env python3
"""
tools/owner_check_versions.py  —  JR Anchored owner use only

Checks whether the versions pinned in admin/ still match what CRAN and PyPI
currently serve.  Run this before each GitHub release to confirm that a fresh
admin_install_R --rebuild will succeed for a new organisation.

Usage:
    python3 tools/owner_check_versions.py

Requires: Python 3.6+, internet access, no third-party packages.
"""

import json
import os
import re
import subprocess
import sys

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ADMIN_DIR    = os.path.join(PROJECT_ROOT, "admin")

R_REQUIREMENTS  = os.path.join(ADMIN_DIR, "R_requirements.txt")
R_VERSION_FILE  = os.path.join(ADMIN_DIR, "r_version.txt")
PY_REQUIREMENTS = os.path.join(ADMIN_DIR, "python_requirements.txt")

# ── Low-level helpers ─────────────────────────────────────────────────────────

import shutil

CURL = shutil.which("curl") or "/usr/bin/curl"


def fetch_json(url):
    """Fetch JSON via curl (uses system keychain — avoids Python SSL issues on macOS)."""
    try:
        result = subprocess.run(
            [CURL, "-sfL", "--max-time", "10",
             "-A", "jr-anchored-owner-check/1.0", url],
            capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except Exception:
        pass
    return None


def normalise_ver(v):
    """Treat hyphens as dots so '1.7-17' == '1.7.17'."""
    return v.replace("-", ".") if v else v


def read_requirements(path):
    """Return OrderedDict of {package: version} from a pinned requirements file."""
    pkgs = {}
    if not os.path.exists(path):
        return pkgs
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "==" in line:
                pkg, ver = line.split("==", 1)
                pkgs[pkg.strip()] = ver.strip()
    return pkgs

# ── CRAN helpers ──────────────────────────────────────────────────────────────

def cran_current_version(package):
    """Return the version CRAN currently serves, or None if not found."""
    data = fetch_json(f"https://cran.r-project.org/web/packages/{package}/json")
    if data and "Version" in data:
        return data["Version"]
    return None


def cran_current_r_minor():
    """Return the current R minor version (X.Y) from CRAN's r-release file."""
    try:
        result = subprocess.run(
            [CURL, "-sfL", "--max-time", "10",
             "https://cran.r-project.org/bin/windows/base/release.htm"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            match = re.search(r"R-(\d+)\.(\d+)\.\d+", result.stdout)
            if match:
                return f"{match.group(1)}.{match.group(2)}"
    except Exception:
        pass
    return None

# ── PyPI helpers ──────────────────────────────────────────────────────────────

def pypi_current_version(package):
    """Return the latest version on PyPI, or None if not found."""
    data = fetch_json(f"https://pypi.org/pypi/{package}/json")
    if data and "info" in data and "version" in data["info"]:
        return data["info"]["version"]
    return None


def pypi_version_exists(package, version):
    """Return True if a specific version exists on PyPI (PyPI keeps all versions)."""
    data = fetch_json(f"https://pypi.org/pypi/{package}/{version}/json")
    return data is not None

# ── Formatting ─────────────────────────────────────────────────────────────────

def header(title):
    print(f"\n{title}")
    print("─" * len(title))


def ok(msg=""):
    return f"✅  OK{('  ' + msg) if msg else ''}"


def warn(msg=""):
    return f"🟡  {msg}"


def fail(msg=""):
    return f"🔴  {msg}"

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    issues   = 0   # critical: fresh install will fail
    warnings = 0   # non-critical: newer version available

    print()
    print("JR Anchored — Version Compatibility Check")
    print("=" * 42)

    # ── Connectivity check ────────────────────────────────────────────────────
    if not shutil.which(CURL) and not os.path.isfile(CURL):
        print(f"\n❌  curl not found at '{CURL}' — cannot reach CRAN or PyPI.")
        sys.exit(2)

    test = fetch_json("https://cran.r-project.org/web/packages/ggplot2/json")
    if test is None:
        print("\n❌  Cannot reach cran.r-project.org — check internet connection.")
        sys.exit(2)

    # ── R packages ────────────────────────────────────────────────────────────

    header("R packages  (admin/R_requirements.txt)")

    r_pkgs = read_requirements(R_REQUIREMENTS)
    if not r_pkgs:
        print("  (no packages pinned)")
    else:
        w_pkg  = max(len(p) for p in r_pkgs) + 2
        w_ver  = max(len(v) for v in r_pkgs.values()) + 2

        for pkg, pinned in r_pkgs.items():
            cran_ver = cran_current_version(pkg)

            if cran_ver is None:
                issues += 1
                status = fail("REMOVED FROM CRAN")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} CRAN: {'—':<{w_ver}} {status}")
                print(f"       → Remove from R_requirements.txt: {pkg}=={pinned}")
            elif normalise_ver(cran_ver) == normalise_ver(pinned):
                status = ok()
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} CRAN: {cran_ver:<{w_ver}} {status}")
            else:
                issues += 1
                status = fail("UPDATE REQUIRED — binary no longer on CRAN")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} CRAN: {cran_ver:<{w_ver}} {status}")
                print(f"       → R_requirements.txt:  {pkg}=={pinned}  →  {pkg}=={cran_ver}")

    # ── R version ─────────────────────────────────────────────────────────────

    header("R version  (admin/r_version.txt)")

    if not os.path.exists(R_VERSION_FILE):
        print("  r_version.txt not found — skipping")
    else:
        with open(R_VERSION_FILE) as f:
            pinned_r = f.read().strip()

        current_r = cran_current_r_minor()

        if current_r is None:
            warnings += 1
            print(f"  Pinned: {pinned_r}   Current: (could not determine)   {warn('CHECK MANUALLY')}")
        elif current_r == pinned_r:
            print(f"  Pinned: {pinned_r}   Current: {current_r}   {ok()}")
        else:
            issues += 1
            print(f"  Pinned: {pinned_r}   Current: {current_r}   {fail('UPDATE REQUIRED')}")
            print(f"       → r_version.txt:  {pinned_r}  →  {current_r}")
            print(f"       → Then update all package pins above to match new CRAN binaries,")
            print(f"         run admin_install_R --rebuild, re-run OQ, and cut a new release.")

    # ── Python packages ───────────────────────────────────────────────────────

    header("Python packages  (admin/python_requirements.txt)")

    py_pkgs = read_requirements(PY_REQUIREMENTS)
    if not py_pkgs:
        print("  (empty — nothing to check)")
    else:
        w_pkg = max(len(p) for p in py_pkgs) + 2
        w_ver = max(len(v) for v in py_pkgs.values()) + 2

        for pkg, pinned in py_pkgs.items():
            pypi_ver = pypi_current_version(pkg)
            exists   = pypi_version_exists(pkg, pinned)

            if pypi_ver is None:
                warnings += 1
                status = warn("COULD NOT CHECK")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} PyPI: {'—':<{w_ver}} {status}")
            elif not exists:
                # Extremely unlikely — PyPI keeps all versions — but handle it
                issues += 1
                status = fail("PINNED VERSION GONE FROM PyPI")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} PyPI: {pypi_ver:<{w_ver}} {status}")
                print(f"       → python_requirements.txt:  {pkg}=={pinned}  →  {pkg}=={pypi_ver}")
            elif pypi_ver == pinned:
                status = ok()
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} PyPI: {pypi_ver:<{w_ver}} {status}")
            else:
                # Newer version available but pinned version still exists — informational only
                warnings += 1
                status = warn("newer version available (optional update)")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} PyPI: {pypi_ver:<{w_ver}} {status}")
                print(f"       → python_requirements.txt:  {pkg}=={pinned}  →  {pkg}=={pypi_ver}  (optional)")

    # ── Verdict ───────────────────────────────────────────────────────────────

    print()
    print("=" * 42)
    if issues == 0 and warnings == 0:
        print("✅  OVERALL: OK — all pinned versions match. Safe to release.")
    elif issues == 0:
        print(f"🟡  OVERALL: OK to release — {warnings} optional update(s) available.")
    else:
        print(f"🔴  OVERALL: {issues} critical issue(s) — update required before release.")
        print()
        print("    Steps to resolve:")
        print("    1. Apply the R_requirements.txt and/or r_version.txt changes shown above.")
        print("    2. Run:  admin_install_R --rebuild")
        print("    3. Re-run the full OQ test suite.")
        print("    4. Update CHANGELOG.md and cut a new GitHub release.")
    print()
    sys.exit(1 if issues > 0 else 0)


if __name__ == "__main__":
    main()
