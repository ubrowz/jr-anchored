# JR Validated Environment — Infrastructure Backlog

This file tracks infrastructure improvements, architectural hardening items,
and platform-level backlog that are not community scripts. Items completed
in a release are moved to the relevant section of CHANGELOG.md.

---

## Status legend

| Symbol | Meaning |
|---|---|
| 💡 | Idea — not yet started |
| 🚧 | In progress |
| ✅ | Completed and released |

---

## Validation & Integrity

| Status | Item | Description |
|---|---|---|
| 💡 | Orphaned package detection | `admin_validate` should compare packages physically present in the renv library against `R_requirements.txt` and report any that are installed but not listed as requirements. Currently the check only runs in the forward direction (listed → installed). A stale package left behind after removal from requirements goes undetected and may cause version warnings or silent dependency on unvalidated code. |

---

## Environment & Installation

| Status | Item | Description |
|---|---|---|
| 💡 | Binary type configuration | Make R package binary type (binary vs source) configurable without editing R code. Currently hardcoded. Noted in PLATFORMS.md. |
| 💡 | Dropbox repo integrity check | Verify that the local miniCRAN Dropbox repository has not been corrupted or partially synced before running `admin_install_R`. |
| 💡 | `.pkg` build script | Script to produce a macOS `.pkg` installer for end-user deployment. |

---

## Platform

| Status | Item | Description |
|---|---|---|
| 💡 | Python VENV_PATH check | Add explicit `VENV_PATH` check at the top of Python scripts with a clear error message referencing `jrrun`. Currently a missing venv produces a cryptic error (OQ finding L-02). |

---

## Notes

- Infrastructure items require admin involvement and typically trigger a new
  release with revalidation.
- Items marked 💡 have not been scoped or scheduled. Open a GitHub issue to
  begin work on any item.

---

*Last updated: 2026-03-13*
