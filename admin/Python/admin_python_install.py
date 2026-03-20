#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
admin_python_install.py

Modes:
  BUILD_REPO=true   → downloads pinned packages from PyPI into LOCAL_REPO,
                       then installs into venv
  BUILD_REPO=false  → installs directly from LOCAL_REPO (no internet needed)
  ADD_PACKAGE=name==version
                    → downloads ONE new package + dependencies into existing
                       LOCAL_REPO, checks for version conflicts, updates
                       python_requirements.txt, checksums.txt, then installs

Called via zsh wrapper admin_install_Python.
"""

import subprocess
import sys
import os
import hashlib
import re
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOCAL_REPO = os.environ.get("LOCAL_REPO")
if not LOCAL_REPO:
    sys.exit("❌ LOCAL_REPO environment variable is not set.\n"
             "   Call this script only via zsh wrapper admin_install_Python.")

BUILD_REPO  = os.environ.get("BUILD_REPO",  "false") == "true"
ADD_PACKAGE = os.environ.get("ADD_PACKAGE", "").strip()
VENV_PATH   = os.environ.get("VENV_PATH")
if not VENV_PATH:
    sys.exit("❌ VENV_PATH environment variable is not set.")

REQ_FILE = os.environ.get("REQ_FILE")
if not REQ_FILE or not Path(REQ_FILE).exists():
    sys.exit(f"❌ REQ_FILE not set or not found: {REQ_FILE}")

# ---------------------------------------------------------------------------
# Determine mode
# ---------------------------------------------------------------------------

if ADD_PACKAGE:
    MODE = "ADD"
elif BUILD_REPO:
    MODE = "BUILD"
else:
    MODE = "INSTALL"

print(f"Mode: {MODE}\n")

# ---------------------------------------------------------------------------
# Helper — parse requirements file into {name: version} dict
# ---------------------------------------------------------------------------

def read_requirements(path):
    pkgs = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("--"):
            continue
        if "==" not in line:
            sys.exit(f"❌ Requirements entries must use 'package==version' format.\n"
                     f"   Offending line: {line}")
        pkg, _, ver = line.partition("==")
        pkgs[pkg.strip()] = ver.split()[0].strip()
    return pkgs

# ---------------------------------------------------------------------------
# Helper — write checksums.txt for entire LOCAL_REPO
# ---------------------------------------------------------------------------

def write_checksums():
    checksum_file = Path(LOCAL_REPO) / "checksums.txt"
    entries = []
    for pkg_file in sorted(Path(LOCAL_REPO).glob("*")):
        if pkg_file.name == "checksums.txt":
            continue
        digest = hashlib.md5(pkg_file.read_bytes()).hexdigest()
        entries.append(f"{digest}  {pkg_file.name}")
    checksum_file.write_text("\n".join(entries) + "\n")
    return checksum_file

# ---------------------------------------------------------------------------
# Helper — resolve dependencies of a package using pip's dry-run
# Returns dict of {package_name: version_string}
# ---------------------------------------------------------------------------

def resolve_deps(package_spec):
    """
    Uses pip install --dry-run --report to resolve full dependency tree
    without installing anything. Requires pip >= 22.2.
    """
    import json, tempfile
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tf:
        report_path = tf.name

    result = subprocess.run(
        [sys.executable, "-m", "pip", "install",
         "--dry-run", "--ignore-installed",
         "--report", report_path,
         "--index-url", "https://pypi.org/simple/",
         package_spec],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        sys.exit(f"❌ Failed to resolve dependencies for {package_spec}:\n"
                 f"{result.stderr}")

    with open(report_path) as f:
        report = json.load(f)
    Path(report_path).unlink()

    deps = {}
    for item in report.get("install", []):
        name    = item["metadata"]["name"]
        version = item["metadata"]["version"]
        deps[name.lower()] = version
    return deps

# ---------------------------------------------------------------------------
# Read current requirements
# ---------------------------------------------------------------------------

pkg_versions = read_requirements(REQ_FILE)

print("📋 Current packages in python_requirements.txt:")
for pkg, ver in pkg_versions.items():
    print(f"   {pkg:<20} {ver}")
print()

# ---------------------------------------------------------------------------
# ADD mode
# ---------------------------------------------------------------------------

if MODE == "ADD":

    # Validate format
    if "==" not in ADD_PACKAGE:
        sys.exit(f"❌ --add requires format: packagename==version\n"
                 f"   Received: {ADD_PACKAGE}")

    add_name, _, add_ver = ADD_PACKAGE.partition("==")
    add_name = add_name.strip()
    add_ver  = add_ver.strip()

    print(f"➕ Adding package: {add_name} version {add_ver}\n")

    # Check if already in requirements
    if add_name.lower() in {k.lower() for k in pkg_versions}:
        existing_key = next(k for k in pkg_versions if k.lower() == add_name.lower())
        existing_ver = pkg_versions[existing_key]
        if existing_ver == add_ver:
            print(f"✅ {add_name}=={add_ver} is already in requirements — nothing to do.")
            sys.exit(0)
        else:
            print(f"⚠️  {add_name} already in requirements at version "
                  f"{existing_ver} — updating to {add_ver}")

    # Verify local repo exists
    if not Path(LOCAL_REPO).exists():
        sys.exit(f"❌ Local repo not found at: {LOCAL_REPO}\n"
                 f"   Run admin_install_Python --rebuild first to create the repo,\n"
                 f"   then use --add to extend it.")

    # Resolve full dependency tree from PyPI
    print(f"🔍 Resolving dependencies for {ADD_PACKAGE}...")
    resolved_deps = resolve_deps(ADD_PACKAGE)

    print("📦 Resolved dependencies:")
    for dep, ver in resolved_deps.items():
        print(f"   {dep:<20} {ver} (PyPI)")
    print()

    # -------------------------------------------------------------------------
    # Conflict check — compare resolved versions against pinned requirements
    # Same philosophy as R: fail clearly if any dependency version conflicts
    # with an existing pin. New dependencies not yet in requirements are allowed.
    # -------------------------------------------------------------------------

    conflicts = []
    new_implicit_deps = {}

    for dep, resolved_ver in resolved_deps.items():
        if dep.lower() == add_name.lower():
            continue    # skip the target package itself

        # Check against existing pins (case-insensitive name comparison)
        pinned_key = next((k for k in pkg_versions if k.lower() == dep.lower()), None)

        if pinned_key:
            pinned_ver = pkg_versions[pinned_key]
            if resolved_ver != pinned_ver:
                conflicts.append(
                    f"   {dep:<20} pinned: {pinned_ver:<12}  "
                    f"PyPI would download: {resolved_ver}"
                )
        else:
            # Not yet in requirements — will be added automatically
            new_implicit_deps[dep] = resolved_ver

    if conflicts:
        print("❌ DEPENDENCY VERSION CONFLICT DETECTED\n")
        print(f"   {add_name}=={add_ver} requires dependencies whose PyPI versions")
        print("   differ from the versions pinned in python_requirements.txt:\n")
        for c in conflicts:
            print(c)
        print()
        print("   Resolution options:")
        print(f"   1. Update the pinned version(s) in python_requirements.txt")
        print(f"      to match PyPI, then run --add again.")
        print(f"   2. Choose a different version of {add_name} whose dependencies")
        print(f"      are compatible with your current pins.")
        print(f"   3. Run --rebuild to update the entire environment at once")
        print(f"      (note: this requires full re-validation).")
        sys.exit("\n❌ Aborting --add due to dependency conflict. No files were changed.")

    print("✅ No dependency conflicts detected.\n")

    if new_implicit_deps:
        print("ℹ️  New implicit dependencies will be added to python_requirements.txt:")
        for dep, ver in new_implicit_deps.items():
            print(f"   {dep}=={ver}")
        print()

    # Download new package + dependencies into existing repo
    print(f"🌐 Downloading {ADD_PACKAGE} + dependencies from PyPI...")
    subprocess.run([
        sys.executable, "-m", "pip", "download",
        "--dest", LOCAL_REPO,
        ADD_PACKAGE
    ], check=True)
    print()

    # Update python_requirements.txt — target package first, then implicit deps
    req_lines = Path(REQ_FILE).read_text().splitlines()

    # Update or append target package
    existing_idx = next(
        (i for i, l in enumerate(req_lines)
         if l.strip().lower().startswith(add_name.lower() + "==")),
        None
    )
    new_entry = f"{add_name}=={add_ver}"
    if existing_idx is not None:
        req_lines[existing_idx] = new_entry
    else:
        req_lines.append(new_entry)

    # Append new implicit dependencies
    for dep, ver in new_implicit_deps.items():
        dep_entry = f"{dep}=={ver}"
        already = any(l.strip().lower().startswith(dep.lower() + "==")
                      for l in req_lines)
        if not already:
            req_lines.append(dep_entry)

    Path(REQ_FILE).write_text("\n".join(req_lines) + "\n")
    print(f"📝 python_requirements.txt updated: {add_name}=={add_ver}")
    for dep, ver in new_implicit_deps.items():
        print(f"📝 python_requirements.txt added implicit dep: {dep}=={ver}")
    print()

    # Recompute checksums for entire repo
    print("🔒 Recomputing repo checksums...")
    checksum_file = write_checksums()
    print(f"✅ checksums.txt updated.\n")

    # Reload requirements so install step picks up new entries
    pkg_versions = read_requirements(REQ_FILE)

# ---------------------------------------------------------------------------
# BUILD mode
# ---------------------------------------------------------------------------

elif MODE == "BUILD":

    print(f"🌐 Downloading packages to local repo: {LOCAL_REPO}")
    subprocess.run([
        sys.executable, "-m", "pip", "download",
        "--dest", LOCAL_REPO,
        "-r", REQ_FILE
    ], check=True)

    print("🔒 Writing checksums...")
    checksum_file = write_checksums()
    print(f"🔒 Checksums written to {checksum_file}\n")

# ---------------------------------------------------------------------------
# INSTALL mode
# ---------------------------------------------------------------------------

elif MODE == "INSTALL":

    print(f"📂 Using existing local repo: {LOCAL_REPO}")

    checksum_file = Path(LOCAL_REPO) / "checksums.txt"
    if checksum_file.exists():
        print("🔒 Verifying repo integrity...")
        failures = []
        for line in checksum_file.read_text().splitlines():
            if not line.strip():
                continue
            stored_hash, filename = line.split("  ", 1)
            pkg_path = Path(LOCAL_REPO) / filename
            if not pkg_path.exists():
                failures.append(f"MISSING: {filename}")
            elif hashlib.md5(pkg_path.read_bytes()).hexdigest() != stored_hash:
                failures.append(f"MODIFIED: {filename}")
        if failures:
            sys.exit("❌ Repo integrity check FAILED:\n" +
                     "\n".join(f"   {f}" for f in failures))
        print("✅ Repo integrity verified.\n")
    else:
        print("⚠️  No checksums.txt found — skipping integrity check.")

# ---------------------------------------------------------------------------
# Create or recreate venv  (all modes)
# ---------------------------------------------------------------------------

import shutil
venv = Path(VENV_PATH)
if venv.exists():
    print(f"⚠️  Removing existing venv: {VENV_PATH}")
    shutil.rmtree(venv)

print(f"🔄 Creating venv at: {VENV_PATH}")
subprocess.run([sys.executable, "-m", "venv", VENV_PATH], check=True)

# ---------------------------------------------------------------------------
# Install from local repo only — no internet  (all modes)
# ---------------------------------------------------------------------------

venv_bin = "Scripts" if sys.platform == "win32" else "bin"
pip      = str(venv / venv_bin / "pip")
python   = str(venv / venv_bin / "python")

print("📦 Installing packages from local repo...")
subprocess.run([
    pip, "install",
    "--no-index",
    "--find-links", LOCAL_REPO,
    "-r", REQ_FILE
], check=True)

# ---------------------------------------------------------------------------
# Verify installed versions  (all modes)
# ---------------------------------------------------------------------------

print("\n🔍 Verifying installed versions:")
all_ok = True
for pkg, req_ver in pkg_versions.items():
    result = subprocess.run(
        [python, "-c",
         f"import importlib.metadata; print(importlib.metadata.version('{pkg}'))"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"   ❌ {pkg:<20} NOT INSTALLED")
        all_ok = False
    else:
        inst_ver = result.stdout.strip()
        if inst_ver != req_ver:
            print(f"   ❌ {pkg:<20} installed: {inst_ver}  required: {req_ver}")
            all_ok = False
        else:
            print(f"   ✅ {pkg:<20} {inst_ver}")

if not all_ok:
    sys.exit("❌ Version mismatch detected.")

print(f"\n✅ Python environment ready at: {VENV_PATH}")
print(f"   Python version : {sys.version.split()[0]}")
print(f"   Repo           : {LOCAL_REPO}")
print(f"   Packages       : {', '.join(pkg_versions.keys())}")
if MODE == "ADD":
    print(f"   Added          : {add_name}=={add_ver}")

