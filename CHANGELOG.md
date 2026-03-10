# Changelog

All notable changes to the JR Validated Environment will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- **Major** version — incompatible architectural changes
- **Minor** version — new features, backwards compatible
- **Patch** version — bug fixes, backwards compatible

---

## [1.0.0] — 2026-03-07

### Initial release

**R environment**
- Controlled local R package repository using miniCRAN stored in a shared Dropbox folder
- Pinned package versions via `R_requirements.txt` and `renv.lock`
- Automated renv library creation and rebuild on version change via zsh wrapper hash check
- SHA256 integrity verification of local package repository
- Explicit renv library path enforcement via `.libPaths()` to prevent fallback to system library
- Separation of user packages (`R_requirements.txt`) and base R packages (`R_base_requirements.txt`)

**Python environment**
- Controlled local Python package repository using `pip download` stored in a shared Dropbox folder
- Pinned package versions via `python_requirements.txt`
- Automated venv creation and rebuild on version change via zsh wrapper hash check
- SHA256 integrity verification of local package repository
- Separation of user packages (`python_requirements.txt`) and standard library modules (`python_base_requirements.txt`)

**Validation framework**
- Project integrity verification via `project_integrity.sha256` checked before every script run
- Auto-generated R validation script (`validate_R_env.R`) from `R_requirements.txt`
- Auto-generated Python validation script (`validate_Python_env.py`) from `python_requirements.txt`
- Validation report showing package versions and load paths for audit purposes
- `jrpy` wrapper for running arbitrary Python scripts in the validated environment
- `jrR` wrapper for running arbitrary R scripts in the validated environment

**Admin tooling**
- `admin_install_R` — builds local R repo and installs renv library
- `admin_install_Python` — builds local Python repo and installs venv
- `admin_create_hash` — generates project integrity file
- `admin_validate` — generates project validation report
- `generate_validate_R.zsh` — generates R validation script from requirements
- `generate_validate_Python.zsh` — generates Python validation script from requirements
- `setup_path.zsh` — one-time PATH configuration for end users
- zsh wrapper templates for R and Python scripts

---

<!-- 
When adding a new entry, copy this template to the top of the list:

## [X.Y.Z] — YYYY-MM-DD

### Added
- 

### Changed
- 

### Fixed
- 

### Removed
- 
-->
