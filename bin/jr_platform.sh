#!/bin/bash
#
# jr_platform.sh
# Sourced by jrrun, jr_versions, and admin scripts to provide
# cross-platform (macOS / Windows Git Bash) helper functions.
#
# Usage:
#   source "$(dirname "$0")/jr_platform.sh"   # from bin/
#   source "$SCRIPT_DIR/../bin/jr_platform.sh" # from admin/
#

# --- Detect OS
# Returns: "macos" | "windows" | "linux"
# Checks $OSTYPE first; falls back to uname -s for Git Bash environments
# where $OSTYPE may be empty or not set.
jr_os() {
  case "$OSTYPE" in
    darwin*)              echo "macos"   ; return ;;
    msys*|cygwin*|win32*) echo "windows" ; return ;;
  esac
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    Darwin*)              echo "macos"   ;;
    *)                    echo "linux"   ;;
  esac
}

# --- Python virtualenv binary path
# Usage: jr_venv_python "/path/to/venv"
jr_venv_python() {
  local venv="$1"
  if [[ "$(jr_os)" == "windows" ]]; then
    echo "$venv/Scripts/python.exe"
  else
    echo "$venv/bin/python"
  fi
}

# --- Python virtualenv pip path
# Usage: jr_venv_pip "/path/to/venv"
jr_venv_pip() {
  local venv="$1"
  if [[ "$(jr_os)" == "windows" ]]; then
    echo "$venv/Scripts/pip.exe"
  else
    echo "$venv/bin/pip"
  fi
}

# --- Python virtualenv pytest path
# Usage: jr_venv_pytest "/path/to/venv"
jr_venv_pytest() {
  local venv="$1"
  if [[ "$(jr_os)" == "windows" ]]; then
    echo "$venv/Scripts/pytest.exe"
  else
    echo "$venv/bin/pytest"
  fi
}

# --- R platform string for renv library paths
# Returns the platform component used by renv, e.g. "macos" or "windows"
jr_r_platform_dir() {
  if [[ "$(jr_os)" == "windows" ]]; then
    echo "windows"
  else
    echo "macos"
  fi
}

# --- Cross-platform sed in-place edit
# Usage: jr_sed_inplace 's/foo/bar/g' "/path/to/file"
# Handles the macOS 'sed -i ""' vs GNU 'sed -i' difference.
jr_sed_inplace() {
  local expr="$1"
  local file="$2"
  if [[ "$(jr_os)" == "macos" ]]; then
    sed -i '' "$expr" "$file"
  else
    sed -i "$expr" "$file"
  fi
}

# --- Shell RC file for PATH setup
# Returns the file that setup_jr_path.sh should append to.
jr_shell_rc() {
  if [[ "$(jr_os)" == "windows" ]]; then
    echo "$HOME/.bash_profile"
  else
    echo "$HOME/.zprofile"
  fi
}

# --- macOS version (stub gracefully on non-macOS)
jr_os_version() {
  if command -v sw_vers >/dev/null 2>&1; then
    sw_vers -productVersion
  else
    local ver
    ver=$(uname -r 2>/dev/null || echo "unknown")
    echo "$ver"
  fi
}

# --- Source-tree provenance for OQ evidence
# Usage: jr_git_commit "/path/to/project_root"
# Returns the commit the evidence was produced from, with a clean/dirty
# marker. Degrades gracefully: an end-user install may have no git binary
# and no .git directory. Never fabricates a commit — says so instead.
jr_git_commit() {
  local root="$1" sha dirty
  if ! command -v git >/dev/null 2>&1; then
    echo "[git not available on this host]"
    return
  fi
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "[not a git checkout]"
    return
  fi
  sha=$(git -C "$root" rev-parse HEAD 2>/dev/null) || {
    echo "[no commit — empty repository]"
    return
  }
  if [[ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]]; then
    dirty=" (DIRTY — uncommitted changes present at run time)"
  else
    dirty=" (clean)"
  fi
  echo "${sha}${dirty}"
}

# --- Environment fingerprint for OQ evidence
# Usage: jr_integrity_digest "/path/to/project_root"
# SHA256 of admin/project_integrity.sha256 — a single value standing for the
# whole set of files that manifest covers. Note this is MACHINE-SPECIFIC: the
# manifest includes r_package_hashes.sha256 / python_package_hashes.sha256,
# which hash this host's installed package binaries. So it fingerprints the
# environment the suite actually ran against, not the source tree alone —
# use the git commit to compare trees across machines.
jr_integrity_digest() {
  local root="$1" f
  f="$root/admin/project_integrity.sha256"
  if [[ ! -f "$f" ]]; then
    echo "[integrity manifest not found]"
    return
  fi
  shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || echo "[digest failed]"
}

# --- Report the OQ output folder and prune old runs
# Usage: jr_oq_output_summary "$PROJECT_ID" "$JR_OUT_DIR" [keep]
#
# Prints the folder this run's artifacts went to and its size, then removes
# all but the newest `keep` run folders (default 5). Run folders are named
# with a sortable timestamp, so "newest" is a lexical sort.
#
# This deletes data, so it is deliberately narrow:
#   - it only ever looks inside $HOME/.jrscript/<project_id>/oq_output
#   - it only removes entries whose name matches a run-id timestamp exactly
#   - it never removes the folder just written to
# Anything else in that directory is left alone.
jr_oq_output_summary() {
  local project_id="$1" out_dir="$2" keep="${3:-5}"
  local root="$HOME/.jrscript/$project_id/oq_output"

  if [[ -d "$out_dir" ]]; then
    echo "📁 OQ artifacts for this run:"
    echo "   $out_dir"
    echo "   $(find "$out_dir" -type f | wc -l | tr -d '[:space:]') file(s), $(du -sh "$out_dir" 2>/dev/null | cut -f1 | tr -d '[:space:]')"
  fi

  [[ -d "$root" ]] || return 0

  local -a runs=()
  local d name
  for d in "$root"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ "$name" =~ ^[0-9]{8}T[0-9]{6}$ ]] || continue    # never touch anything else
    runs+=("$name")
  done

  local total=${#runs[@]}
  (( total > keep )) || return 0

  # Sort ascending; everything before the last `keep` is surplus.
  local -a sorted=()
  while IFS= read -r name; do sorted+=("$name"); done < <(printf '%s\n' "${runs[@]}" | sort)

  local removed=0 i
  for (( i = 0; i < total - keep; i++ )); do
    name="${sorted[$i]}"
    [[ "$root/$name" == "${out_dir%/}" ]] && continue   # never the current run
    rm -rf -- "${root:?}/${name:?}" && removed=$(( removed + 1 ))
  done

  if (( removed > 0 )); then
    echo "🧹 Pruned $removed old OQ output folder(s); kept the newest $keep."
    echo "   $root  ($(du -sh "$root" 2>/dev/null | cut -f1 | tr -d '[:space:]') total)"
  fi
}
