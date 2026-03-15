# Changelog

All notable changes to the JR Validated Environment will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- **Major** version — incompatible architectural changes
- **Minor** version — new features, backwards compatible
- **Patch** version — bug fixes, backwards compatible

---

## [1.1.0] — 2026-03-15

### Added

**R scripts**
- `jrc_descriptive` — descriptive statistics summary (mean, SD, CV, percentiles, skewness, kurtosis, 95% CI on mean). Intended as a quick characterisation step before normality testing or tolerance interval analysis.
- `jrc_bland_altman` — Bland-Altman method comparison analysis. Reports bias, SD of differences, limits of agreement (LoA) with 95% CIs, and proportional bias test. Saves Bland-Altman plot as PNG.
- `jrc_weibull` — Weibull reliability analysis. Fits a 2-parameter Weibull distribution via MLE using `survreg()`, handles right-censored observations, reports shape (β) and scale (η) with 95% CIs, B1/B10/B50 life estimates, and saves a Weibull probability plot as PNG.
- `jrc_verify_attr` — statistical tolerance interval verification for continuous data. Computes 1-sided or 2-sided tolerance intervals (normal or Box-Cox), compares against spec limits, and saves a histogram PNG showing the TI and spec limits with pass/fail shading.

**Python scripts**
- `jrc_convert_csv` — converts a multi-column delimited file to the standard jrc CSV format. Supports column selection by name or number, configurable skip lines for metadata headers, and auto-delimiter detection (tab/space/comma).
- `jrc_convert_txt` — converts a single-column text file (one value per line) to jrc CSV format. Supports optional line range selection to exclude stabilisation periods or post-test noise.

### Changed
- `admin_scaffold` split into `admin_scaffold_R` (creates R script + wrapper + help file) and `admin_scaffold_Python` (creates wrapper + help file for Python scripts). The unified `admin_scaffold` is removed.

---

## [1.0.0] — 2026-03-12

### Initial release

**Architecture**
- Unified `jrrun` wrapper in `bin/` replaces all per-script wrappers (`jrr`, `jrpy`, `jrR_hello`, `jrPy_hello`) — extension-based routing dispatches `.R` scripts to the R environment and `.py` scripts to the Python environment
- `bin/` folder for JR infrastructure scripts (`jrrun`, `jr_versions`, `jr_uninstall`)
- `wrapper/` folder for user entry point scripts (`jr_animate`, `jr_static`)
- `help/` folder for per-script help text files — `jrrun myscript.R --help` displays `help/myscript.txt`
- `setup_jr_path.zsh` adds both `bin/` and `wrapper/` to PATH via `~/.zprofile` with begin/end markers for clean removal
- All scripts in `bin/` use `PROJECT_ROOT=$(dirname SCRIPT_DIR)` pattern for correct path resolution

**R environment**
- Controlled local R package repository using miniCRAN stored in a shared Dropbox folder
- Pinned package versions via `R_requirements.txt` and `renv.lock`
- R packages installed into isolated per-project library at `~/.renv/[PROJECT_ID]/library/` using explicit `install.packages(lib=lib_path)` — never the system library
- Automated R library rebuild on version change via hash check in `jrrun`
- SHA256 integrity verification of local package repository on every install
- `--add packagename==version` argument to add a single package without rebuilding the entire repo
- Separation of user packages (`R_requirements.txt`) and base R packages (`R_base_requirements.txt`)

**Python environment**
- Controlled local Python package repository using `pip download` stored in a shared Dropbox folder
- Pinned package versions via `python_requirements.txt` — pip honours exact version pins end-to-end
- Automated venv rebuild on version change via hash check in `jrrun`
- SHA256 integrity verification of local package repository on every install
- `--add packagename==version` argument to add a single package without rebuilding the entire repo
- Separation of user packages (`python_requirements.txt`) and standard library modules (`python_base_requirements.txt`)

**Validation framework**
- Project integrity verification via `project_integrity.sha256` checked by `jrrun` before every script execution
- Auto-generated R validation script (`validate_R_env.R`) from `R_requirements.txt`
- Auto-generated Python validation script (`validate_Python_env.py`) from `python_requirements.txt`
- `admin_validate` produces a timestamped combined IQ evidence file at `~/.jrscript/[PROJECT_ID]/validation/`
- Bypass protection: R scripts explicitly check for `RENV_PATHS_ROOT` at startup and halt if called outside `jrrun`; Python scripts fail at import time without the validated venv
- Run log at `~/.jrscript/[PROJECT_ID]/run.log` — every `jrrun` execution logged with timestamp, script name, arguments, and exit code
- Admin log at `~/.jrscript/[PROJECT_ID]/admin.log` — all admin actions logged with outcome
- Validation Plan template (`docs/templates/validation_plan_template.docx`) covering IQ, OQ, PQ
- Validation Report template (`docs/templates/jr_validation_report_template.docx`) covering IQ, OQ, PQ

**Admin tooling**
- `admin_install_R` — builds local R repo and installs isolated R library; supports `--rebuild` and `--add`
- `admin_install_Python` — builds local Python repo and installs venv; supports `--rebuild` and `--add`
- `admin_create_hash` — generates project integrity file
- `admin_validate` — generates validation scripts and produces timestamped IQ evidence file
- `admin_uninstall` — removes the entire JR environment from the machine
- `bin/jr_uninstall` — removes the current user's local environment components (R library, venv, run log, PATH entry)
- `bin/jr_versions` — displays current R, Python, and all package versions

**Known limitations (documented)**
- miniCRAN `--rebuild` and `--add` fetch current CRAN versions, not pinned versions. The local repository is the version control artefact for R. Rebuilding requires re-validation.
- Python scripts invoked directly outside `jrrun` fail at import time rather than displaying an explicit error referencing the wrapper. Improvement planned for v1.1.

**Removed**
- `jrr`, `jrpy` — replaced by `jrrun`
- `jrR_hello`, `jrPy_hello` — replaced by `jr_static` and `jr_animate`
- `templates/jrr_template`, `templates/jrpython_template` — replaced by `jrrun` dispatch model

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
