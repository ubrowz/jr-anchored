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

_cran_index       = None  # source index — loaded once, shared across lookups
_cran_bin_index   = None  # macOS binary index; False once probed + unavailable
_cran_bin_flavour = None  # which macOS build flavour answered

# CRAN renames the macOS arm64 build flavour every few R releases (R 4.5 was
# big-sur-arm64, R 4.6 is sonoma-arm64). Probe newest first and use whichever
# actually serves an index for the pinned R minor; add new names at the front.
R_BINARY_FLAVOURS = ("sonoma-arm64", "big-sur-arm64")


def _parse_packages(text):
    """Parse a CRAN PACKAGES file into {package: version}."""
    pkgs = {}
    current_pkg = None
    for line in text.splitlines():
        if line.startswith("Package:"):
            current_pkg = line.split(":", 1)[1].strip()
        elif line.startswith("Version:") and current_pkg:
            pkgs[current_pkg] = line.split(":", 1)[1].strip()
            current_pkg = None
    return pkgs


def _fetch_packages(url):
    """Fetch and parse a PACKAGES index; None if unreachable or empty."""
    try:
        result = subprocess.run(
            [CURL, "-sfL", "--max-time", "30", url],
            capture_output=True, text=True
        )
        if result.returncode != 0 or not result.stdout:
            return None
        return _parse_packages(result.stdout) or None
    except Exception:
        return None


def _load_cran_index():
    """CRAN's *source* PACKAGES index as {package: version}."""
    global _cran_index
    if _cran_index is None:
        _cran_index = _fetch_packages(
            "https://cran.r-project.org/src/contrib/PACKAGES")
    return _cran_index


def _load_cran_binary_index(r_minor):
    """CRAN's *macOS arm64 binary* index for the pinned R minor.

    This is the index admin_R_install.R downloads from, so it — not the source
    index — decides whether a pinned version is still installable here. CRAN
    publishes source ahead of binaries, and during that window the source index
    reports a version no binary exists for; comparing against source made the
    checker demand an upgrade admin_install_R could not then satisfy.

    Returns None when no flavour serves an index (running on Linux CI, or CRAN
    unreachable), in which case callers fall back to the source index.
    """
    global _cran_bin_index, _cran_bin_flavour
    if _cran_bin_index is not None:
        return _cran_bin_index or None
    if not r_minor:
        return None
    for flavour in R_BINARY_FLAVOURS:
        idx = _fetch_packages(
            "https://cran.r-project.org/bin/macosx/"
            f"{flavour}/contrib/{r_minor}/PACKAGES")
        if idx:
            _cran_bin_index, _cran_bin_flavour = idx, flavour
            return idx
    _cran_bin_index = False      # probed and unavailable — don't retry
    return None


JR_PACKAGE_REPO = os.environ.get(
    "JR_PACKAGE_REPO", "https://www.dwylup.com/packages")

_jr_bin_index = None


def _load_jr_binary_index(r_minor):
    """The JR-hosted macOS binary index for the pinned R minor.

    Since v4.10.0 admin_install_R installs from the JR repository first and
    falls back to CRAN, so *this* index decides whether a pin is still
    installable. CRAN moving on is no longer breakage — the JR repository holds
    the validated versions frozen — so it must be consulted before CRAN or the
    checker reports failures that do not exist.
    """
    global _jr_bin_index
    if _jr_bin_index is not None:
        return _jr_bin_index or None
    if not r_minor or not JR_PACKAGE_REPO:
        return None
    for flavour in R_BINARY_FLAVOURS:
        idx = _fetch_packages(
            f"{JR_PACKAGE_REPO}/bin/macosx/{flavour}/contrib/{r_minor}/PACKAGES")
        if idx:
            _jr_bin_index = idx
            return idx
    _jr_bin_index = False        # probed and unavailable — don't retry
    return None


def jr_binary_version(package, r_minor):
    """Return the version the JR repository serves as a macOS binary, or None."""
    idx = _load_jr_binary_index(r_minor)
    return idx.get(package) if idx else None


def cran_current_version(package):
    """Return the version CRAN currently serves as source, or None."""
    idx = _load_cran_index()
    return idx.get(package) if idx else None


def cran_binary_version(package, r_minor):
    """Return the version CRAN serves as a macOS binary, or None."""
    idx = _load_cran_binary_index(r_minor)
    return idx.get(package) if idx else None


def pinned_r_minor():
    """The R minor version (X.Y) pinned in admin/r_version.txt, or None."""
    try:
        with open(R_VERSION_FILE) as f:
            m = re.match(r"(\d+\.\d+)", f.read().strip())
            return m.group(1) if m else None
    except Exception:
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

    if _load_cran_index() is None:
        print("\n❌  Cannot reach cran.r-project.org — check internet connection.")
        sys.exit(2)

    # ── R packages ────────────────────────────────────────────────────────────

    header("R packages  (admin/R_requirements.txt)")

    r_minor = pinned_r_minor()
    bin_idx = _load_cran_binary_index(r_minor)
    jr_idx  = _load_jr_binary_index(r_minor)

    if jr_idx:
        print(f"  Installable-from check: {JR_PACKAGE_REPO} first, then CRAN —")
        print("  the same order admin_install_R uses. A pin CRAN has dropped is")
        print("  fine as long as the JR repository still serves it.")
    elif bin_idx:
        print(f"  JR repository unreachable — comparing against macOS "
              f"{_cran_bin_flavour} binaries for R {r_minor} only.")
    else:
        print("  No macOS binary index reachable — comparing against the CRAN")
        print("  source index (a source-only version may have no binary yet).")

    r_pkgs = read_requirements(R_REQUIREMENTS)
    if not r_pkgs:
        print("  (no packages pinned)")
    else:
        w_pkg  = max(len(p) for p in r_pkgs) + 2
        w_ver  = max(len(v) for v in r_pkgs.values()) + 2

        for pkg, pinned in r_pkgs.items():
            src_ver  = cran_current_version(pkg)
            cran_ver = cran_binary_version(pkg, r_minor) if bin_idx else src_ver
            jr_ver   = jr_binary_version(pkg, r_minor)

            # The question is "can a fresh install still get this pin?", not
            # "does CRAN still serve it?". Either repository satisfying the pin
            # is a pass; only losing it from both is an outage.
            served_by = None
            if jr_ver and normalise_ver(jr_ver) == normalise_ver(pinned):
                served_by = "JR"
            elif cran_ver and normalise_ver(cran_ver) == normalise_ver(pinned):
                served_by = "CRAN"

            newest = cran_ver or src_ver

            if served_by:
                if newest and normalise_ver(newest) != normalise_ver(pinned):
                    # Upstream has moved on. The pin is still installable, so
                    # this is a monthly "worth adopting?" question, not a fault.
                    status = ok(f"— {served_by}; CRAN now at {newest}")
                else:
                    status = ok(f"— {served_by}")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} {status}")
            elif jr_idx is None and cran_ver is None and src_ver is None:
                issues += 1
                status = fail("REMOVED FROM CRAN")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} {status}")
                print(f"       → Remove from R_requirements.txt: {pkg}=={pinned}")
            elif jr_idx is None and cran_ver is None:
                # No JR index to consult and CRAN has not built a binary for
                # this R minor yet. Not actionable.
                warnings += 1
                status = warn(f"no macOS binary for R {r_minor} yet (source {src_ver})")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} {status}")
            else:
                # Neither repository serves the pinned version. This is the
                # genuine failure: a fresh install cannot be satisfied.
                issues += 1
                status = fail("NOT INSTALLABLE — absent from JR repo and CRAN")
                print(f"  {pkg:<{w_pkg}} pinned: {pinned:<{w_ver}} {status}")
                print(f"       → JR repo: {jr_ver or '—'}   CRAN: {cran_ver or '—'}")
                print(f"       → Re-publish {pkg}=={pinned} to the JR repository,")
                print(f"         or bump the pin and revalidate.")

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
            # Since v4.11.0 the validated R installer is hosted alongside the
            # packages, so CRAN releasing a newer R does not break a fresh
            # install — the pinned installer is still served. This is a
            # deliberate upgrade decision, not a fault.
            warnings += 1
            print(f"  Pinned: {pinned_r}   Current: {current_r}   "
                  f"{warn('newer R available — upgrade is a decision, not a break')}")
            print(f"       → Fresh installs are unaffected: {JR_PACKAGE_REPO}/installers/")
            print(f"         still serves the validated R {pinned_r} installer.")
            print(f"       → To adopt {current_r}: bump r_version.txt, host the new")
            print(f"         installer, refresh package pins to the new binaries,")
            print(f"         run admin_install_R --rebuild, re-run OQ, cut a release.")

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
        print("    5. Redeploy the checker service so it picks up the updated repo.")
    print()
    sys.exit(1 if issues > 0 else 0)


if __name__ == "__main__":
    main()
