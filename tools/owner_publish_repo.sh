#!/bin/bash
#
# owner_publish_repo.sh — assemble the publishable package repository. Owner use only.
#
# Produces a clean upload tree containing ONLY what the current pin set needs:
# every file listed in each PACKAGES index, plus the index sidecars. Superseded
# package versions left on disk by past drift bumps are excluded — they are not
# in any index, so R can never resolve them, and shipping them would waste
# ~110 MB.
#
# SCOPE, worth being explicit about: tools::write_PACKAGES indexes only the
# NEWEST version of each package, so the published repository serves the CURRENT
# pin set. It does not make historical JR Anchored releases installable forever;
# that would need a CRAN-style Archive/ layout. The failure this fixes is "a new
# customer clones the current release and the install fails because CRAN dropped
# a pinned binary".
#
# Usage:
#   tools/owner_publish_repo.sh                 # report only
#   tools/owner_publish_repo.sh <staging_dir>   # also copy the tree there
#
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/R_repo/my-cran-repo"
STAGE="${1:-}"

# Trees to publish. The 4.5 tree is deliberately omitted: it sits below the R
# version pinned in admin/r_version.txt, so no supported install reaches for it.
TREES=(
  "src/contrib"
  "bin/macosx/sonoma-arm64/contrib/4.6"
)

[[ -d "$REPO" ]] || { echo "❌ repo not found: $REPO"; exit 1; }

total_files=0; total_skip=0
echo "JR Anchored — publishable repository"
echo "===================================="
for tree in "${TREES[@]}"; do
  d="$REPO/$tree"
  [[ -d "$d" ]] || { echo "  ⚠️  missing tree: $tree"; continue; }
  ext=".tgz"; [[ "$tree" == src/* ]] && ext=".tar.gz"

  wanted="$(awk -v E="$ext" '/^Package:/{p=$2} /^Version:/{print p"_"$2 E}' "$d/PACKAGES" | sort -u)"
  present="$(cd "$d" && ls *"$ext" 2>/dev/null | sort)"
  missing="$(comm -23 <(echo "$wanted") <(echo "$present"))"
  skipped="$(comm -13 <(echo "$wanted") <(echo "$present"))"

  n_want=$(echo "$wanted" | grep -c . || true)
  n_skip=$(echo "$skipped" | grep -c . || true)
  echo ""
  echo "  $tree"
  echo "    publish : $n_want files"
  echo "    skip    : $n_skip superseded (not in any index)"
  if [[ -n "$missing" ]]; then
    echo "    ❌ INDEXED BUT ABSENT:"; echo "$missing" | sed 's/^/       /'
    exit 1
  fi
  total_files=$((total_files + n_want)); total_skip=$((total_skip + n_skip))

  if [[ -n "$STAGE" ]]; then
    mkdir -p "$STAGE/$tree"
    while IFS= read -r f; do [[ -n "$f" ]] && cp "$d/$f" "$STAGE/$tree/"; done <<< "$wanted"
    for s in PACKAGES PACKAGES.gz PACKAGES.rds; do
      [[ -f "$d/$s" ]] && cp "$d/$s" "$STAGE/$tree/"
    done
  fi
done

echo ""
echo "  TOTAL to publish: $total_files files   (excluding $total_skip superseded)"
if [[ -n "$STAGE" ]]; then
  echo "  Staged at: $STAGE  ($(du -sh "$STAGE" 2>/dev/null | awk '{print $1}'))"
  echo ""
  echo "  Upload the CONTENTS of that directory to the web root of the"
  echo "  package host, preserving the directory structure, then set:"
  echo "      export JR_PACKAGE_REPO=https://<host>"
fi
