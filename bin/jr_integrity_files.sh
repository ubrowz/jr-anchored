#!/bin/bash
#
# jr_integrity_files.sh
# Shared canonical file lists for the project integrity manifest.
#
# Sourced by:
#   admin/admin_create_hash  — to know which files to hash into the manifest
#   bin/jrrun                — to detect untracked code files added since hashing
#
# All paths are emitted relative to PROJECT_ROOT with a leading "./", matching
# the manifest format produced by `shasum -a 256`. Callers MUST cd to
# PROJECT_ROOT before calling these functions.
#

# ---------------------------------------------------------------------------
# jr_integrity_hash_list
# Full set of files covered by the integrity manifest. Run by admin_create_hash
# (on the admin machine, where executable bits are reliable).
# ---------------------------------------------------------------------------
jr_integrity_hash_list() {
  # bin: executables ...
  find ./bin -maxdepth 1 -type f -perm -111
  # ... plus the helpers that jrrun/scripts SOURCE (not executable, so the
  # -perm filter above misses them — they must be covered explicitly).
  local f
  for f in ./bin/jr_platform.sh ./bin/jr_helpers.R ./bin/jr_helpers.py \
           ./bin/jr_integrity_files.sh; do
    [[ -f "$f" ]] && echo "$f"
  done

  # wrapper scripts on PATH (core + every module). Wrappers have no extension,
  # so take all regular non-dot files — and match jr_integrity_addition_list
  # exactly to avoid false positives.
  find ./wrapper -maxdepth 1 -type f ! -name ".*"
  find ./repos/*/wrapper -maxdepth 1 -type f ! -name ".*" 2>/dev/null

  # admin executables
  find ./admin -maxdepth 1 -type f -perm -111
  # admin helper scripts — exclude the locally generated, gitignored validation
  # scripts (admin_validate rewrites validate_R_env.R / validate_Python_env.py on
  # every run; their generators above are tracked and hashed instead).
  find ./admin/R -type f -name "*.R" ! -name "validate_R_env.R"
  find ./admin/Python -type f -name "*.py" ! -name "validate_Python_env.py"

  # analysis scripts — core ...
  find ./R -type f -name "*.R"
  find ./Python -type f -name "*.py"
  # ... and every module under repos/
  find ./repos/*/R -type f -name "*.R" 2>/dev/null
  find ./repos/*/Python -type f -name "*.py" 2>/dev/null

  # the Streamlit GUI + its modules (orchestrate jrrun and the admin scripts)
  find ./app -maxdepth 1 -type f -name "*.py" 2>/dev/null

  # platform launchers (first code that runs on each OS)
  for f in "./JR Anchored.bat" \
           "./Create JR Anchored Shortcut.ps1" \
           "./JR Anchored.app/Contents/MacOS/launcher"; do
    [[ -f "$f" ]] && echo "$f"
  done

  # environment definition files + the release-signing trust root
  for f in ./VERSION \
           ./admin/R_requirements.txt ./admin/python_requirements.txt \
           ./admin/renv.lock ./admin/r_version.txt \
           ./admin/python_version.txt ./admin/streamlit_version.txt \
           ./admin/allowed_signers \
           ./admin/python_package_hashes.sha256 ./admin/r_package_hashes.sha256; do
    [[ -f "$f" ]] && echo "$f"
  done
}

# ---------------------------------------------------------------------------
# jr_integrity_addition_list
# Cross-platform-safe subset used at verify time (in jrrun) to catch files that
# were ADDED after the manifest was generated. Enumerated by location and
# extension ONLY — never by executable bit — so Windows Git Bash permission
# quirks cannot cause false positives. Covers the code-execution vectors
# reachable through jrrun and the PATH wrappers.
# ---------------------------------------------------------------------------
jr_integrity_addition_list() {
  find ./R -type f -name "*.R" 2>/dev/null
  find ./Python -type f -name "*.py" 2>/dev/null
  find ./repos/*/R -type f -name "*.R" 2>/dev/null
  find ./repos/*/Python -type f -name "*.py" 2>/dev/null
  find ./admin/R -type f -name "*.R" ! -name "validate_R_env.R" 2>/dev/null
  find ./admin/Python -type f -name "*.py" ! -name "validate_Python_env.py" 2>/dev/null
  find ./wrapper -maxdepth 1 -type f ! -name ".*" 2>/dev/null
  find ./repos/*/wrapper -maxdepth 1 -type f ! -name ".*" 2>/dev/null
  find ./app -maxdepth 1 -type f -name "*.py" 2>/dev/null
}
