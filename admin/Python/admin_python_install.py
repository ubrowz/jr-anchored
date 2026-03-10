#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Mar  2 20:39:14 2026

@author: joeprous
"""

# admin_python_install.py
import subprocess
import sys
import os
import hashlib
from pathlib import Path

LOCAL_REPO = os.environ.get("LOCAL_REPO")
if not LOCAL_REPO:
    sys.exit("❌ LOCAL_REPO environment variable is not set.")

BUILD_REPO = os.environ.get("BUILD_REPO", "false") == "true"
VENV_PATH  = os.environ.get("VENV_PATH")
if not VENV_PATH:
    sys.exit("❌ VENV_PATH environment variable is not set.")

REQ_FILE = os.environ.get("REQ_FILE")
if not Path(REQ_FILE).exists():
    sys.exit(f"❌ {REQ_FILE} not found.")

if BUILD_REPO:
    print(f"🌐 Downloading packages to local repo: {LOCAL_REPO}")
    subprocess.run([
        sys.executable, "-m", "pip", "download",
        "--dest", LOCAL_REPO,
        "-r", REQ_FILE
    ], check=True)

    # Write checksums for integrity verification
    checksum_file = Path(LOCAL_REPO) / "checksums.txt"
    with open(checksum_file, "w") as f:
        for pkg_file in sorted(Path(LOCAL_REPO).glob("*")):
            if pkg_file.name == "checksums.txt":
                continue
            digest = hashlib.md5(pkg_file.read_bytes()).hexdigest()
            f.write(f"{digest}  {pkg_file.name}\n")
    print(f"🔒 Checksums written to {checksum_file}")

else:
    print(f"📂 Using existing local repo: {LOCAL_REPO}")

    # Integrity check
    checksum_file = Path(LOCAL_REPO) / "checksums.txt"
    if checksum_file.exists():
        print("🔒 Verifying repo integrity...")
        failures = []
        for line in checksum_file.read_text().splitlines():
            stored_hash, filename = line.split("  ", 1)
            pkg_path = Path(LOCAL_REPO) / filename
            if not pkg_path.exists():
                failures.append(f"MISSING: {filename}")
            elif hashlib.md5(pkg_path.read_bytes()).hexdigest() != stored_hash:
                failures.append(f"MODIFIED: {filename}")
        if failures:
            sys.exit("❌ Repo integrity check FAILED:\n" +
                     "\n".join(f"   {f}" for f in failures))
        print("✅ Repo integrity verified.")
    else:
        print("⚠️  No checksums.txt found — skipping integrity check.")

# Create or recreate venv
import shutil
venv = Path(VENV_PATH)
if venv.exists():
    print(f"⚠️  Removing existing venv: {VENV_PATH}")
    shutil.rmtree(venv)

print(f"🔄 Creating venv at: {VENV_PATH}")
subprocess.run([sys.executable, "-m", "venv", VENV_PATH], check=True)

# Install from local repo only — no internet
pip = str(venv / "bin" / "pip")
print("📦 Installing packages from local repo...")
subprocess.run([
    pip, "install",
    "--no-index",                    # never use internet
    "--find-links", LOCAL_REPO,      # look only in local repo
    "-r", REQ_FILE
], check=True)

# Verify installed versions
print("\n🔍 Verifying installed versions:")
all_ok = True
python = str(venv / "bin" / "python")
for line in Path(REQ_FILE).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("--"):
        continue
    pkg, _, req_ver = line.partition("==")
    pkg = pkg.strip()
    req_ver = req_ver.split()[0].strip()   # strip any trailing hash options
    if not pkg or not req_ver:
        continue
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
print(f"   Python version: {sys.version.split()[0]}")