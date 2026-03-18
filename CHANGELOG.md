# Changelog

All notable changes to the JR Validated Environment will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- **Major** version — incompatible architectural changes
- **Minor** version — new features, backwards compatible
- **Patch** version — bug fixes, backwards compatible

---

## [1.6.0] — 2026-03-18

### Added
- `web/downloads.html` — new Downloads page listing all 8 PDFs in two sections (Manuals and Validation Documents) with download buttons linking to `docs/<filename>.pdf` on the web server.
- `CONTRIBUTING.md`: three-level contribution overview (personal use via `jrrun`, team contribution via `admin_scaffold`, public GitHub PR) and the previously referenced but missing Contributing Community Scripts section.

### Changed
- `web/get-started.html`: added utility commands section (jrrun, jr_versions, jr_uninstall) to the end-user tab; added contributing a script subsection to the For your project tab; Downloads link added to site nav.
- `web/style.css`: added download card and button styles.
- `web/index.html`, `web/script_guide.html`, `web/faq.html`: Downloads link added to site nav.
- `docs/ignore/generate_user_manual.py`: added Section 6 (Utility Commands: jrrun, jr_versions, jr_uninstall) and Section 7 (Contributing a Script: personal, team, public); First-Time Setup renumbered 6→8, Glossary 7→9.
- `docs/user_manual.pdf`: regenerated with new Sections 6 and 7.

---

## [1.5.0] — 2026-03-17

### Added
- `web/faq.html` — new FAQ page with 18 Q&As across three sections: using the scripts, setup and administration, and validation and compliance. Covers data format, first-run build time, RStudio restriction, cross-machine consistency, offline use, adding packages, integrity check behaviour, `admin_validate` vs `admin_oq`, Dropbox alternatives (SMB + Git, Syncthing, Resilio Sync, Nextcloud, iCloud Drive), revalidation triggers, and audit evidence.
- `web/favicon.svg` — browser tab icon (navy rounded square, blue "JR" text, white background). Added to all four pages.

### Changed
- `web/style.css`: added FAQ accordion styles using native `<details>`/`<summary>` — no JavaScript required.
- `web/index.html`, `web/get-started.html`, `web/script_guide.html`: FAQ link added to site nav; footer version updated to v1.5.0.

---

## [1.4.0] — 2026-03-17

### Added
- `oq/test_core.py` — automated OQ/IQ test suite for core infrastructure (JR-VP-001). Covers TC-CORE-IQ-001, TC-CORE-OQ-001..005: admin_validate evidence, R and Python hello-world runs, integrity tamper detection, R and Python bypass protection. Brings total automated OQ tests to 142.
- `admin/python_requirements.txt`: added `matplotlib==3.10.8`, `numpy==2.4.3`, and transitive dependencies (`contourpy`, `cycler`, `fonttools`, `kiwisolver`, `packaging`, `pillow`, `pyparsing`, `python-dateutil`, `six`). Previously the Python environment contained no third-party packages.

### Changed
- `R/jrc_R_hello.R` (renamed from `R/jrhello.R`), `Python/jrc_py_hello.py` (from `Python/jrhello.py`) — hello-world scripts aligned to `jrc_*` naming convention.
- `wrapper/jrc_R_hello` (from `jr_static`), `wrapper/jrc_py_hello` (from `jr_animate`), `wrapper/jrc_helloworld` (from `jr_helloworld`) — wrapper names now match script names.
- `help/jrc_R_hello.txt`, `help/jrc_py_hello.txt` — help files renamed and updated to match new wrapper names.
- `web/`: expanded to a three-page static site (`index.html`, `get-started.html`, `script_guide.html`) with shared `style.css`.

### Fixed
- `docs/ignore/oq_validation_plan.md`: corrected script names from `jrhello.R/jrhello.py` to `jrc_R_hello.R/jrc_py_hello.py`; clarified that hello-world scripts are covered by the core IQ/OQ plan.
- `docs/TROUBLESHOOTING.md`: corrected wrapper name from `jrR_hello` to `jrc_R_hello`.

---

## [1.3.0] — 2026-03-17

### Added

**R scripts — Design of Experiments**
- `jrc_doe_design` — generates a DoE run matrix from a CSV factors file. Supports full factorial 2-level (`full2`), full factorial 2-level with centre points (`full2c`), full factorial 3-level (`full3`), fractional factorial 2-level (`fractional`), and Plackett-Burman (`pb`) designs. Outputs a run sheet CSV, summary CSV, and PNG plot. Requires `FrF2` and `DoE.base`.
- `jrc_doe_analyse` — analyses a completed DoE run sheet. Computes main effects and two-way interactions, identifies significant effects (p < 0.05), performs a curvature test, reports results to terminal and HTML, and saves a main-effects PNG plot. Requires `base64enc`.

**Web**
- `web/script_guide.html`: new "DoE Planner" tab — an interactive decision tree that guides users to the correct DoE script and design type based on study stage, goal, and number of factors. Includes syntax and example for each design variant.

### Fixed
- `admin/R/admin_R_install.R`: renv library path was incorrect — `renv.lock` was written to `~/.renv/<PROJECT_ID>/renv.lock` (unread by `jrrun`) instead of `admin/renv.lock`; R packages were installed to `~/.renv/<PROJECT_ID>/library/` instead of the correct three-component path `~/.renv/<PROJECT_ID>/renv/library/macos/<R-ver>/<platform>`. Both corrected.
- `admin/admin_generate_validate_R`: `lib_path` formula was `file.path(renv_root, "library")` — did not match the three-component path used everywhere else. Updated to match; `admin/R/validate_R_env.R` regenerated.
- `jrc_doe_design.R` (fractional): `resolution = "minimum"` is not a valid `FrF2::FrF2()` argument — corrected to `resolution = 3`.
- `jrc_doe_design.R` (Plackett-Burman): `FrF2::pb()` returns factor columns; matrix coercion failed with "non-numeric argument to binary operator". Fixed by converting via `as.integer(sapply(..., function(x) as.numeric(as.character(x))))`.
- `jrc_doe_analyse.R`: curvature p-value was written to HTML output only — not printed to terminal. Added `message()` call so terminal output includes the curvature result (required for TC-DOE-ANA-003).

---

## [1.2.0] — 2026-03-16

### Added

**OQ test suite**
- `oq/` folder containing 116 pytest-based tests covering all 24 community scripts
- `admin_oq` — runs the OQ suite in an isolated Python venv and produces a timestamped evidence file at `~/.jrscript/<PROJECT_ID>/validation/oq_execution_<timestamp>.txt`
- `admin_oq_validate` — pre-flight checker for the OQ environment; verifies Python version pin, venv existence, and pinned package versions before running `admin_oq`
- `oq/python_version.txt` — pins the Python version (3.11.9) for the OQ venv
- `oq/requirements.txt` — pins pytest==8.3.4 for the OQ venv (isolated from the user analysis venv)

**Validation documents**
- `docs/statistics_validation_plan.pdf` (JR-VP-002 v1.0) — OQ validation plan for all 24 community scripts
- `docs/statistics_validation_report.pdf` (JR-OQ-001 v1.0) — OQ validation report; 116/116 tests passed
- `docs/core_IQ_validation_plan.pdf` (JR-VP-001 v1.0) — IQ validation plan
- `docs/core_validation_report.pdf` (JR-VR-001 v1.0) — combined IQ/OQ/PQ validation report

**Documentation**
- `docs/admin_statistics_manual.pdf` (JR-AM-002 v1.0) — administrator manual for the OQ/statistics test suite; covers `admin_oq`, `admin_oq_validate`, `oq/python_version.txt`, `oq/requirements.txt`, OQ venv management, and troubleshooting
- `docs/user_manual.pdf` — engineer-facing user guide for design verification; covers all 16 analysis scripts with plain-English guidance, a quick reference table, three worked examples, first-time setup, and a glossary

### Fixed
- `admin_oq`: zsh pipestatus compatibility — `PIPESTATUS[0]` (bash) corrected to `pipestatus[1]` (zsh); script was exiting with code 1 after every run even when all tests passed
- `jrc_bland_altman.R`: minor bug fix
- `jrc_ss_fatigue.R`: minor bug fix

### Changed
- Help files completed for `jrc_ss_gauge_rr`, `jrc_ss_fatigue`, `jrc_ss_equivalence`, `jrc_ss_paired`, `jrc_gen_uniform` — replaced scaffolding placeholder text with full content

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
