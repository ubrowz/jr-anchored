# Changelog

All notable changes to the JR Validated Environment will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- **Major** version — a significant product milestone or incompatible architectural change
- **Minor** version — new features, backwards compatible
- **Patch** version — bug fixes, backwards compatible

---

## [Unreleased]

### Security
- **Honest security-model documentation (gaps #5, #6).** `SECURITY.md` now states
  the model explicitly: the project and package hash manifests are
  tamper-*evidence* (not tamper-resistance), authenticity comes from signed
  releases, the `RENV_PATHS_ROOT` check is a validation-discipline guardrail (not
  a security boundary), and the GUI admin password is a convenience gate (not
  access control). Scope updated to add release-signature and package-hash
  verification bypass. README/COMPARISON/CLAUDE wording brought in line with the
  now-stronger controls. (Website copy is tracked separately for the web pass.)
- **Admin password hardening (gap #4).** The GUI admin password is now stored as
  a salted, iterated **PBKDF2-HMAC-SHA256** hash (200k iterations) instead of an
  unsalted single-round SHA-256, and verified in constant time
  (`hmac.compare_digest`). Existing passwords keep working and are transparently
  upgraded to the new format on next login. The config file is written
  owner-only (`chmod 600`), and unreadable/corrupt config now fails closed. A
  caption makes explicit that this password gates the GUI Admin tab as a
  convenience control — not the validated security boundary (terminal/file
  access to the machine can run the admin scripts directly).
- **Package content hash-pinning (gap #3).** The local R and Python package
  repositories (delivered via Dropbox/SMB) are now verified file-by-file against
  a **git-anchored SHA256 manifest** before every environment build — including
  `jrrun`'s own rebuild path, which previously installed without any content
  check. New `bin/jr_hash_packages` (generate) and `bin/jr_verify_packages`
  (verify); manifests `admin/{python,r}_package_hashes.sha256` are git-tracked
  and covered by the project integrity file, so a swapped same-version package
  is caught instead of installed silently. Replaces the old MD5 `checksums.txt`
  that lived inside the (untrusted) repo. Generation runs on `--rebuild`/`--add`;
  verification runs in `admin_install_R/Python` (INSTALL mode) and `jrrun`.
  Note: manifests reflect the platform(s) the admin built on — regenerate when
  adding a new platform's binaries.
- **Integrity manifest coverage extended (gap #2).** `admin_create_hash` now
  hashes the full executable surface: all `repos/*/{R,Python,wrapper}` module
  scripts (previously **uncovered** — they ran without verification), the helpers
  sourced by `jrrun` (`bin/jr_platform.sh`, `bin/jr_helpers.{R,py}`), the
  Streamlit GUI (`app/jr_app.py`), and the platform launchers. Coverage went
  from 93 to 163 files. New shared list `bin/jr_integrity_files.sh` keeps
  `admin_create_hash` and `jrrun` in sync.
- **Addition detection.** `jrrun` now fails closed if a script or wrapper is
  present on disk but absent from the manifest (cross-platform-safe, enumerated
  by location+extension so Windows Git Bash permission quirks cannot
  false-positive). Previously only listed files were checked, so a newly dropped
  script ran unverified.
- **Signed-release verification (gap #1).** Releases are SSH-signed tags.
  `admin_update` refuses to apply an update whose tag signature is invalid;
  `admin_setup` blocks on an invalid signature; the GUI sidebar shows a
  *Verified release* / *Signature INVALID* status. New helper
  `bin/jr_verify_release`, pinned key `admin/allowed_signers`, and
  `docs/VERIFYING.md`. Runs in advisory mode until the signing key is configured.

> **Upgrade note (backward compatibility):** an install that pulls this change
> must regenerate the integrity manifest (`admin/admin_create_hash`) before the
> next run — `admin_update` does this automatically. A manual `git pull` without
> regenerating will report an "untracked file(s)" integrity failure because the
> newly covered `repos/` scripts are not in the old manifest.

## [4.0.3] — 2026-06-19

### Fixed

- **Windows: GUI Streamlit-drift banner suggested a command that fails** — when
  the installed Streamlit differs from `admin/streamlit_version.txt`, the in-app
  banner recommended `python3 -m pip install …`, but a python.org Windows
  install has no `python3` (only `python`/`py`). The banner now says
  `python -m pip install streamlit==<pin>`. The terminal launcher already used
  the resolved interpreter and was unaffected.

### Added

- **Owner-only daily analytics** (`tools/owner_check_analytics.py`) — pulls
  GoatCounter per-page hits (all-time / last-7-day / yesterday, sorted by the
  week), prints the table in the Render cron logs and emails it each morning.
  Internal tooling; no effect on the validated environment.

## [4.0.2] — 2026-06-19

### Fixed

- **Windows: emoji status output no longer crashes Python scripts** — on
  Windows the Git Bash console uses the cp1252 codepage, which cannot encode
  the emoji used in status messages, raising `UnicodeEncodeError` (first hit
  during `admin_setup --rebuild`). Affected scripts now reconfigure
  stdout/stderr to UTF-8 (`errors="replace"`) before any output. The fix is
  in-code rather than via `PYTHONUTF8`/`PYTHONIOENCODING`, because the
  launchers run Python with `-I` (isolated mode), which ignores those env
  vars. Coverage: `admin_python_install.py` and the `validate_Python_env.py`
  generator template (`admin_generate_validate_Python`), the `jrc_*` analysis
  scripts run via `jrrun`, and all OQ test suites. Backward-compatible — no
  behaviour change on macOS/Linux. All 9 OQ suites pass.

## [4.0.1] — 2026-06-18

### Changed

- **README refreshed for the GUI-first (v4.0.0) model** — end-user quick start
  is now double-click-the-app (Terminal optional); admin quick start is
  `git clone` → GUI Admin tab → `admin_setup --rebuild`, upgrades via
  `admin_update`. Corrected counts (56 validated scripts, 10 modules, 621 OQ
  tests), added Dropbox alongside SMB, listed `admin_setup`/`admin_update`/
  `admin_oq_all`, and updated the How-It-Works diagram.

### Removed

- **Owner-only sales tooling removed from the repository** — `tools/delivery_email_template.html`
  and `tools/generate_invoice_template.py` are internal business artefacts, now
  untracked and gitignored so they no longer ship on the public `release` branch.

## [4.0.0] — 2026-06-17

> **Milestone release — JR Anchored is now fully operable from the GUI.** Every
> admin task, including first-time setup, runs from the Admin tab, so the only
> terminal step on a new machine is `git clone`. **No breaking changes** —
> existing command-line workflows are unaffected.

### Added

- **`tools/owner_check_streamlit.py` — daily new-Streamlit alert** — compares the
  latest Streamlit on PyPI against the GUI-verified pin in
  `admin/streamlit_version.txt` and exits non-zero when a newer release exists.
  Wired into the Render daily cron (`render.yaml`), so a new Streamlit triggers
  Render's failure email — the prompt to test the GUI against the new version and,
  if it works, bump `streamlit_version.txt`, push, and release. Transient PyPI
  failures exit 0 (no false-alarm email).

- **GUI: run every admin command from the Admin tab** — the Admin tab now covers
  the full admin lifecycle so the only terminal step is `git clone`. New
  **Setup & Environments** section: `admin_setup` and `admin_setup --rebuild`
  (first-time setup), `admin_install_R --rebuild` / `admin_install_Python
  --rebuild`, and "add a package" inputs (`--add name==version`). **OQ Testing**
  expanded with `admin_oq_validate` (pre-flight) and `admin_oq` (core) alongside
  `admin_oq_all`. New guarded **Danger zone** runs `admin_uninstall` (type
  UNINSTALL to confirm; the GUI feeds the script's confirmation). Long-running
  builds stream a live tail to keep the connection alive. Existing buttons
  (`admin_create_hash`, `admin_validate`, `admin_update`, Validation Pack,
  Export Configured App) are unchanged. Script-authoring commands
  (`admin_scaffold_*`, `admin_create_repo`) remain terminal-only by design.

- **GUI: install the Validation Pack from the Admin tab** — a new
  **Validation Pack** section detects a `jr-anchored-pack-*.zip` placed in the
  project root and installs it with one click (runs `install_pack.sh`: verify
  SHA-256 → unpack → install templates), with live output. After install the
  **📄 Generate Word report** option is detected automatically on the Scripts
  page — no Terminal needed. Removes the `bash install_pack.sh` step from the
  customer flow for GUI users (PATH setup, which only matters for terminal
  `jr_pack` use, is unnecessary in the GUI path).

- **`tools/owner_check_consistency.py` — automated release/website
  consistency check** — asserts the release contract daily: the `release`
  branch (GitHub's default, what customers clone) sits exactly on the latest
  version tag; every sitemap page is reachable and carries that version in
  its footer; the homepage JSON-LD `softwareVersion` matches; the homepage
  stat counters (validated scripts, OQ tests, modules) match the repository
  and the modules page; and every validation-document PDF linked on
  downloads.html returns 200. Wired into `owner_daily_check.sh` with its own
  log line and macOS notification on failure. Stat-count mismatches soften
  to warnings while the working tree is dirty (development ahead of release
  is expected).

### Changed

- **GUI warns on Streamlit version drift** — the launchers `bin/jr_app` and
  `JR Anchored.bat` now compare the installed Streamlit against the pin in
  `admin/streamlit_version.txt` when Streamlit is already present (previously
  the pin was applied only when Streamlit was missing, so an existing
  different version ran silently). On a mismatch they print a clear,
  non-blocking warning naming both versions and the optional command to
  install the tested version, then launch normally. Because Dock launches
  redirect launcher stdout to `~/.jrscript/jr_app.log` (no visible terminal),
  `app/jr_app.py` also renders the same mismatch as an in-app `st.warning`
  banner at the top of every page — visible on all launch paths. Analysis
  results are unaffected: the GUI sits outside the validated boundary and all
  computation runs through `jrrun`; the warning only guards the GUI's use of
  a private Streamlit API (the idle watchdog).

- **`admin_update` now rebuilds the package repo and validates** — when the
  R or Python environment spec changed in the pull, `admin_update` runs
  `admin_install_R --rebuild` / `admin_install_Python --rebuild` instead of a
  plain install. A plain install draws only from the existing local repo,
  which does not contain newly pinned packages or binaries for a new R
  version, so `renv::restore` warned-and-skipped them and left the library
  incomplete — surfacing later as "MASS/lattice/Matrix not found in the
  validated library" (e.g. upgrading to 3.12.0, which added those pins).
  `admin_update` now also runs `admin_validate` at the end and exits non-zero
  if it fails, so an incomplete update can no longer report success.

- **Streamlit pin bumped 1.55.0 → 1.58.0** — `admin/streamlit_version.txt`, the
  GUI-verified Streamlit version. 1.58.0 is now the tested baseline: customers on
  1.58.0 no longer see the version-drift warning, and the daily owner Streamlit
  check passes. No effect on analysis — the GUI sits outside the validated
  boundary.

---

## [3.12.0] — 2026-06-12

### Added

- **Website — R & Python languages guide and course visibility** (web-local
  branch; live on www.dwylup.com):
  - `guide_languages.html` — *R and Python in JR Anchored*: why the
    statistics run in R and the tooling runs in Python, a side-by-side
    pandas/R code comparison for Python-native teams, script anatomy,
    and a role/language summary table. Card on the Guides index under
    Installation & customization, footer "R & Python" link on all pages,
    sitemap entry.
  - FAQ: new entry *"Why is JR Anchored built on R? Our team only knows
    Python."* cross-linking the languages guide.
  - "Free Course" item in the Learn dropdown on all pages, and a course
    callout banner on the home page — both pointing at
    `learning_path.html`.

- **Website — free course, calculators and reference pages** (web-local
  branch; live or upload-pending on www.dwylup.com):
  - `learning_path.html` — *Statistics for Design Verification*: free
    ~10-hour course, 7 modules + electives + capstone, GUI-first
    exercises with collapsed Terminal equivalents, Course + FAQPage
    structured data; new "Courses" section atop the Guides index.
  - `kfactor_calculator.html` + `kfactor_data.js` — exact tolerance
    interval K-factors (P 90–99.9%, C 90–99%, n 2–500, 1-/2-sided);
    11,976 values computed via `tolerance::K.factor` (EXACT) from the
    validated renv library, spot-verified against `jrc_ss_attr_check`
    (2.2198 / 2.5549) and externally against NIST and the EMA/RMTC
    table. Generator: `web/make_kfactor_data.R`.
  - `western_electric_rules.html` — the 8 rules reference with zone
    system and annotated `jrc_spc_imr` example charts.
  - `guide_msa.html` — interactive %GRR/ndc verdict widget, 5-question
    FAQ with FAQPage schema, CTR-focused title/meta rewrite (page had
    1,735 impressions at position 9 with zero clicks).
  - `guide_gui.html` — updated for the GUI lifecycle fixes (auto-stop,
    self-healing ports, Streamlit pin).

- **Website — `guide_curve.html`: curve module guide with full configuration
  reference** — new guide page (replaces user-manual updates for the curve
  module going forward): data model, phases, queries, smoothing/resampling,
  and a worked force-compression example, followed by a configuration
  reference covering every config key — each parameter with explanation,
  config example, and an annotated figure (22 PNGs in `web/examples/`,
  generated by `web/make_curve_guide_pngs.py`). Guides index card, sitemap
  entry, footer link on all pages; home-page OQ counter 616 → 621;
  downloads page references the v1.1 validation documents. (web-local
  commits 5cd456d, 1d5576e.)

- **`jrc_curve_properties`: five functionality extensions** —
  (1) `x_at_y_N.show = yes` draws a + marker on the plot at each reported
  crossing. (2) `[transform]` gains `x_scale` and `x_offset` for X-axis unit
  conversion and zeroing; transforms apply in the order x_scale, x_offset,
  y_scale, y_offset_x, and all X values elsewhere in the config refer to the
  transformed axis. (3) New `width_at_y_N` query reports the X distance
  between the first and last crossing at a given Y (peak width / FWHM), with
  `.phase` and `.show` modifiers. (4) `x_at_y` crossings are now classified:
  tangency points (the curve touches the query Y without crossing, e.g. a
  peak apex) and exact series endpoints are annotated in the results.
  (5) `[smoothing] resample = yes` interpolates scoped data onto a uniform
  X grid before derivative-based calculations, making inflection/yield/d2y
  results reliable on non-uniformly sampled data (verified: inflection of a
  non-uniformly sampled sine found at x = 3.1414 vs true π). Five new OQ
  test cases (TC-CURVE-Q-004..006, T-003, R-001) with analytical numeric
  assertions; suite now 36 tests, all passing. Help file and sample config
  updated.

### Changed

- **GUI: sample-data dropdown shows the file count** — the data section's
  selectbox label now reads "Or use sample data (4 files available)"
  instead of a bare label over a "(none)" default, which user testing
  showed reads as "no sample data exists". Applies to the standard and
  convert-script data sections.

- **GitHub repository discoverability** — README gains release/license/
  platform badges and the GUI screenshot; repo topics replaced with
  searched-for terms (r, medical-devices, fda, iso-13485, gauge-rr, spc,
  …); GitHub Discussions enabled.

- **Render cron: daily clone report** — new `tools/owner_check_clones.py`
  runs after the version check in the `jr-version-check` cron and prints
  yesterday's GitHub clone count (plus the 14-day total) to the run log.
  Informational only — always exits 0, so failure emails remain reserved
  for version drift. Requires a `GITHUB_TOKEN` secret env var in the
  Render dashboard (classic PAT with `repo` scope, or fine-grained token
  with read-only Administration permission).

- **`owner_daily_check.sh`: daily GitHub traffic archive** — appends the
  14-day clone/view windows and the star count to
  `~/.jrscript/github_traffic.csv` (deduplicated by metric+date), since
  GitHub discards traffic data after 14 days. Skips silently if `gh` is
  unavailable. Also archives referrers (`referrer:<host>` rows, one
  snapshot per referrer per day) — the cleanest human-traffic signal,
  since clone counts are dominated by bots that mirror push activity.

- **GUI: Streamlit version pinned for first-time installs** — new
  `admin/streamlit_version.txt` (1.55.0, integrity-hashed alongside the
  R/Python version pins) is read by both launchers; `bin/jr_app` and
  `JR Anchored.bat` now `pip install streamlit==<pin>` instead of the
  latest release. The GUI idle watchdog relies on a private Streamlit
  API verified against this version, so fresh installs (notably Windows,
  where Streamlit is installed on first launch) must not float. Already-
  installed versions are left untouched. Falls back to unpinned install
  if the version file is missing.

- **Curve module bumped to v1.1; validation documents revised** —
  script version 1.0 → 1.1 (bug fixes + functionality extensions above).
  JR-VP-CURVE-001 and JR-VR-CURVE-001 regenerated as v1.1: new URs
  (UR-CURVE-019 resampling, UR-CURVE-020 numeric correctness), test cases
  TC-CURVE-Q-004..006 / T-003 / R-001 added, numeric cases N-001..003
  (in the suite since v1.0) now documented, RTM and acceptance criteria
  updated to 36 test cases. Report generator's evidence parser fixed for
  the multi-line pytest format (pending-TC tracking — previously every TC
  would have shown NOT RUN); regenerated report spot-checked: 36 PASS,
  0 NOT RUN. The curve user manual is superseded by the new website guide
  (guide_curve.html on www.dwylup.com) and will no longer be updated.

- **`jrc_curve_properties`: config syntax consistency and review cleanups** —
  `.show` is now the one canonical "draw on plot" modifier across all sections
  (`overall.show`, `at_x_N.show`, `inflections.show`, ...); the old `.plot`
  ([slope]) and `.plot_slope` ([transitions]) names remain accepted as
  synonyms. The `[smoothing]` section accepts `smooth_method`/`smooth_span`
  as synonyms of `method`/`span`, and its default method is now savgol as
  documented (previously a bare `[smoothing]` section silently did nothing).
  Inline comments now work with both `#` and `;`. The duplicate-key pre-scan
  also recognises `:` as a key delimiter. The validator flags orphan modifiers
  (e.g. `secant.x1` without `secant = yes`) as warnings, treats an unknown
  smoothing method as an error instead of a warning, and config warnings are
  now counted in the end-of-run warning tally. `smooth_d2y` falls back to a
  numerical gradient on non-uniformly spaced X (the analytical Savitzky-Golay
  second derivative assumes uniform spacing) and warns once per phase when
  spacing is non-uniform. `--help` now lists the `[transform]` and `[debug]`
  sections. Help file and sample config updated; smoothing-resolution logic
  consolidated into one `resolve_smoothing()` helper. All 31 curve OQ tests
  pass.

- **igraph upgraded 2.3.1 → 2.3.2** — CRAN binary for 2.3.1 no longer available.
  Pin updated in `admin/R_requirements.txt`. All 191 OQ tests pass.

- **FrF2 upgraded 2.3-4 → 2.3-5** — CRAN binary for 2.3-4 no longer available.
  Pin updated in `admin/R_requirements.txt`; 27 transitive dependencies explicitly
  pinned. All 191 OQ tests pass.

### Fixed

- **Scaffold scripts: module wrappers now placed in the module's own
  `wrapper/` folder** — `admin_scaffold_R --repo` and
  `admin_scaffold_Python --repo` wrote the wrapper to the root `wrapper/`
  folder, inconsistent with every existing module (which keep wrappers in
  `repos/<module>/wrapper/`, the layout `setup_jr_path.sh` puts on the
  PATH). Both scaffolds (v1.3) now write module wrappers to
  `repos/<module>/wrapper/` with the correct `../../../bin/jrrun` relative
  path, create the folder on first use, and document the behaviour; the
  Customization Guide on the website was corrected to match.

- **Validation report documents: local-path hyperlinks and missing per-TC
  results** — the report generators embedded the OQ evidence file reference
  as a clickable `file:///Users/...` hyperlink; the link survived docx→PDF
  conversion, and Google crawled the published PDFs' links as site-relative
  URLs, producing 404s in Search Console. All nine generators now render the
  evidence reference as plain text (`add_file_ref()`). While regenerating,
  five module generators (as, cap, corr, msa, spc) were found still using
  the single-line evidence regex, showing "NOT RUN" for most test cases —
  the multi-line `pending_tc` parser was ported from the curve generator.
  All nine reports regenerated and verified: no `file://` links, no
  "NOT RUN" rows, PASS counts match the evidence files; republished PDFs
  committed (rdt and all validation plans were unaffected).

- **GUI: orphaned Streamlit servers after closing the browser tab** — the
  server never exits on browser disconnect, so closing the tab (instead of
  using the Close GUI button) left an invisible server holding a port until
  reboot. Three fixes: (1) `app/jr_app.py` gains an idle watchdog thread that
  shuts the server down ~3 minutes after the last browser session
  disconnects (2-minute startup grace period). (2) The stale-server reaper in
  `bin/jr_app` matched `ps -o comm=` case-sensitively against `*python*`,
  which never matches macOS framework Python (`.../MacOS/Python`) — it now
  matches the lower-cased full command line against `*streamlit*jr_app.py*`,
  which also stops it from killing unrelated Python processes that happen to
  hold a port. (3) Both launchers (`bin/jr_app`, `JR Anchored.bat`) now pass
  `--server.address localhost` — previously the GUI listened on all network
  interfaces, exposing script execution to the LAN.

- **`jrc_curve_properties`: six bug fixes plus stricter config validation** —
  (1) interpolation queries on non-monotonic X (multi-pass series) are now
  rejected with a warning instead of silently mixing loading/unloading arms;
  `y_offset_x` uses the first pass through the reference X in time order.
  (2) `x_at_y` no longer reports a duplicate crossing when a data point lands
  exactly on the query Y. (3) `at_x_N` slope queries outside the data range
  are skipped with a warning instead of silently extrapolating the edge slope.
  (4) `search = ascending/descending` now handles valley-shaped zones, not
  only peaks. (5) `x_end` is matched only at or after `x_start`, as documented.
  (6) Repeated X values no longer produce inf/NaN in inflection/yield
  derivatives — skipped with a warning. The inflection-search boundary trim
  now uses half the smoothing window (minimum 3 rows) as documented, via the
  previously dead `smooth_half_window()`. All yes/no flag keys are validated:
  any value other than yes/no is a config error (a typo previously skipped
  that analysis silently). Help file updated. All 31 curve OQ tests pass.

- **`owner_check_versions.py`: resolution instructions now include a redeploy step** —
  the "Steps to resolve" block printed on failure now lists step 5:
  redeploy the checker service so it picks up the updated repo.

---

## [3.11.8] — 2026-05-17

### Added

- **Release branch introduced as GitHub default** — the `release` branch now
  serves as the stable, validated entry point for all clones and pulls.
  `main` remains the development branch and is never the recommended
  installation target. New users cloning the repo land on `release`
  automatically; existing users on `main` are warned by `admin_setup`.

  **Release workflow** — when a commit on `main` is ready to be promoted
  to a validated release:

  ```bash
  git tag vX.Y.Z              # tag the commit on main
  git push origin vX.Y.Z      # publish the tag
  git push origin vX.Y.Z:release   # advance the release branch
  ```

  This keeps `release` pinned to an explicit validated state regardless of
  how frequently `main` is updated.

### Fixed

- **Windows: `admin_oq`, all module `admin_*_oq`, `admin_oq_all`, and
  `admin_validate_Python_env` now set `PYTHONUTF8=1` before invoking pytest or
  Python** — on Windows, Python defaults stdout to `cp1252`, causing a
  `UnicodeEncodeError` whenever pytest printed R script output containing emoji
  (e.g. `✅`). All 191 OQ tests failed immediately. `PYTHONUTF8=1` forces UTF-8
  I/O for the pytest process; it is a no-op on macOS where UTF-8 is the default.
  `admin_validate` already had this fix; it is now applied consistently everywhere.

- **Windows GUI: Admin and Settings pages no longer raise UnicodeDecodeError** —
  the Admin page buttons (`admin_validate`, `admin_create_hash`, `admin_oq`, etc.)
  and the Settings page R version check and PowerShell shortcut creator all used
  `text=True` without an explicit encoding. On Windows this defaulted to `cp1252`,
  raising `UnicodeDecodeError` on any UTF-8 output. All four `subprocess` calls
  now specify `encoding="utf-8"`, matching the convention already in use on the
  Scripts page.

- **Windows: correct R version now detected when multiple versions are installed** —
  `admin_setup` previously selected R alphabetically from `Program Files/R/`, picking
  e.g. R-4.5.3 over a newly installed R-4.6.0. Detection now matches the folder
  version against the pinned `REQ_R` value.

- **Windows: Python version no longer blank when Windows Store stub is on PATH** —
  `admin_setup` now looks up the real CPython installer directly via
  `%USERPROFILE%\AppData\Local\Programs\Python\`, bypassing the Store stub. Falls
  back to a version-verified AppData scan, then `python` in PATH.

- **Windows: R bootstrap installs no longer require Administrator rights** —
  `admin_R_install.R` now prepends a writable personal library
  (`%USERPROFILE%\AppData\Local\R\win-library\<ver>\`) to `.libPaths()` when the
  system R library is not writable, so miniCRAN and renv bootstrap without elevation.

- **Windows: `JR Anchored.bat` now runs correctly in CMD without Git for Windows** —
  replaced all Unicode box-drawing characters with plain ASCII (avoided CMD codepage
  failures), and escaped all parentheses inside `echo` statements within `if`/`else`
  blocks (avoided "and was unexpected at this time" parse error).

- **Windows: `.gitattributes` added to enforce CRLF line endings for `*.bat`** —
  CMD cannot parse LF-only batch files; the new `.gitattributes` rule ensures correct
  endings on all Windows checkouts.

- **Windows GUI: R now found on Windows when checking environment** —
  the Streamlit environment check previously searched only macOS paths for `Rscript`.
  It now also globs `C:\Program Files\R\R-*\bin\Rscript.exe` on Windows.

- **Windows GUI: configured-app zip correctly placed on OneDrive-redirected Desktop** —
  `os.path.expanduser("~/Desktop")` returns the default Desktop path, missing
  OneDrive redirection. A new `_win_desktop()` helper reads the real path from the
  Windows registry (`Shell Folders\Desktop`), falling back to the OneDrive path if
  the registry key is unavailable.

- **Windows OQ: bypass protection tests no longer fail with FileNotFoundError** —
  all 6 module conftest files now resolve the Rscript binary at import time via
  `RSCRIPT_BIN` (globbing `C:\Program Files\R\R-*\bin\Rscript.exe` on Windows,
  plain `"Rscript"` elsewhere). All 23 module test files that called
  `subprocess.run(["Rscript", ...])` in bypass protection tests now use
  `RSCRIPT_BIN`, which is exported from conftest.

- **GUI: `admin_oq_all` now streams live output during the run** — the
  `_run_oq_cmd` helper previously blocked silently for 20+ minutes. It now
  streams stdout line-by-line into a live code block, updating every 10 lines.
  This prevents the Streamlit WebSocket from dropping and eliminates the
  symptom of the button resetting to unclicked with no result shown.

- **OQ diagnostics: all Downloads assertion failures now show context** —
  every `_recent_png` / `_recent_file` assertion in all 24 module test files
  was updated to include: resolved `DOWNLOADS` path, whether it exists, all
  matching files of any age, and the R script's own output. This makes
  environment-specific failures (wrong HOME, TCC denial) immediately
  identifiable from the pytest output alone.

- **OQ: report tests now accept `.docx` in addition to HTML/JSON** —
  on machines with jr_pack (Validation Pack) fully installed, the R script
  writes HTML + JSON intermediates, calls jr_pack to generate a `.docx` Word
  report, then deletes the intermediates. All 30 report test methods across
  10 module OQ suites (cap, msa, rdt, shelf_life, spc) now check for
  `.docx` OR HTML/JSON so both install configurations pass. JSON content
  checks are skipped when only `.docx` is present (jr_pack proved correctness
  by producing the Word document).

- **OQ: file detection mtime buffer increased to 1 second** —
  `_recent_png` / `_recent_file` / html/json loops previously used
  `>= t_start` with no tolerance. On Intel Macs with HFS+ timestamps this
  caused spurious failures when the file mtime matched `t_start` exactly.
  All 41 detection expressions across 10 files now use `>= t_start - 1.0`.

- **Windows: `admin_oq_all` now discovers module suites with bash glob
  instead of `find`** — when `admin_oq_all` is invoked via `bash --login`
  from the GUI on Windows, the login profile may prepend
  `C:\Windows\System32` to `PATH`, causing `find` to resolve to Windows
  `find.exe` (a string-in-file tool, not a filesystem searcher). This
  produced no output, leaving `SUITES` with only the hardcoded core suite
  (`admin_oq`). Module suites were silently skipped and no module evidence
  files were written. Discovery now uses bash's native glob expansion
  (`for _script in "$_module_dir"admin_*oq`) which bypasses PATH lookup
  entirely and works identically on Windows, macOS, and Linux.

- **macOS: `jr_app` escapes the Dock bundle context at startup** — when the
  GUI is started from the Dock (`.app` bundle), macOS associates all child
  processes with the bundle's TCC responsible-process chain. This blocks R
  scripts from writing to `~/Downloads`, so every OQ test that saves a PNG
  there fails from the GUI even though it passes from Terminal.

  Two separate strategies are used depending on hardware:

  - **Apple Silicon under Rosetta**: re-execs as arm64 via `arch -arm64`.
    `arch` creates a new subprocess that transitions from Rosetta to native,
    resetting the TCC chain. Symptom without this: numpy/matplotlib `.so`
    files (arm64) fail to load in the x86_64 emulated process, and all OQ
    suites that save files to `~/Downloads` fail from the GUI.
  - **Intel Mac launched without a TTY** (from Dock, not Terminal): relaunches
    through Terminal.app via `osascript`. On Intel, `arch -x86_64` does
    NOT reset the TCC chain because the architecture is unchanged — macOS
    still attributes the subprocess to the bundle. Relaunching through
    Terminal.app transfers the responsible process to Terminal, which already
    holds the necessary `~/Downloads` (and other folder) TCC grants. Falls
    back to `arch -x86_64` if `osascript` is unavailable.

  Both conditions are detected at startup via `hw.optional.arm64` /
  `uname -m` / `[[ ! -t 0 ]]`; they are no-ops when not applicable.

- **Windows: Validation Pack `--report` now works end-to-end** — four
  separate issues prevented `--report` Word document generation on Windows:

  - **`python3` not found (status 9009)**: all 16 R scripts that invoke
    `jr_pack.py` called `system2("python3", ...)`. On Windows, `python3`
    resolves to the Microsoft Store stub (exit 9009). A new `jr_python_bin()`
    helper in `jr_helpers.R` locates the real `python.exe` via
    `admin/python_version.txt` → `%USERPROFILE%\AppData\Local\Programs\
    Python\PythonXYY\python.exe`, and falls back to `"python"` in PATH. All
    16 scripts now call `system2(jr_python_bin(), ...)`.

  - **`UnicodeEncodeError` for emoji in `jr_pack.py` output**: `jr_pack.py`
    prints `✅` to stdout; on Windows the default console encoding is
    `cp1252`, which cannot encode that character. `jr_python_bin()` now
    sets `PYTHONUTF8=1` as a side effect before every Python subprocess
    call, forcing UTF-8 I/O without touching any of the 16 call sites.

  - **SHA-256 missing from Word document**: the inline SHA-256 computation
    in all 13 report-generating R scripts called `system2("shasum", ...)`,
    which is not on the Windows PATH when R invokes `system2`. A new
    `jr_sha256_file()` helper in `jr_helpers.R` tries `shasum` first
    (macOS/Linux/Git Bash), then falls back to `certutil -hashfile`
    (built in to all Windows installations). All 13 scripts now call
    `jr_sha256_file()` instead of the inline 5-line block.

  - **Data filename in report shows temp name instead of uploaded name**:
    the GUI saved uploaded CSV files as random-named temp files
    (e.g. `tmp3a8f1b.csv`); `basename()` in the R script returned that
    temp name rather than the user's original filename. The GUI now saves
    each upload into a dedicated `mkdtemp()` directory under the original
    filename, so `basename()` returns the correct name.

- **Windows: JSON sidecar invalid for MSA, RDT, and shelf-life poolability
  `--report` runs** — `jvs(png_path)` wrote the raw Windows path (e.g.
  `C:\Users\...\file.png`) into the JSON sidecar without escaping backslashes.
  `json.load()` in the OQ test and in the Word generator then raised
  `JSONDecodeError: Invalid \escape`. Fixed in `jrc_msa_gauge_rr`,
  `jrc_rdt_verify`, `jrc_shelf_life_poolability`, and `jrc_verify_attr` to
  match the `gsub("\\\\", "/", png_path)` normalisation already present in
  the cap and spc scripts.

---

## [3.11.6] — 2026-05-15

### Fixed

- **Windows launcher: no longer requires Git for Windows** — `JR Anchored.bat`
  rewritten in native cmd.exe. Reads `admin/python_version.txt` to locate the
  correct Python executable; falls back to `python` in PATH. Checks and
  auto-installs Streamlit with clear error messages. Opens the browser via
  PowerShell after a short delay. Git for Windows is no longer a requirement
  for Windows end users.

- **Configured-app export: Dropbox paths now work for all users** — the macOS
  launcher now expands a leading `~` or the literal string `$HOME` after reading
  the baked-in project root, so an admin can export `~/Dropbox/JR Anchored` and
  each user's home folder is substituted at launch time. On Windows, `%USERPROFILE%`
  in the `JRROOT` value is expanded by cmd.exe at parse time — no bat change
  required. The Export Configured App UI now shows platform-specific tips.

---

## [3.11.5] — 2026-05-13

### Fixed

- **jrrun: set `PYTHONUNBUFFERED=1` for Python scripts** — without this,
  Python block-buffers stdout when writing to a pipe (e.g. the OQ test
  subprocess). Output printed before a blocking call such as `plt.show()`
  was never flushed to the pipe before a timeout fired, causing
  TC-CORE-OQ-002 to report a false failure even when the script ran
  correctly. Setting `PYTHONUNBUFFERED=1` ensures all print output is
  flushed immediately, regardless of whether stdout is a TTY or a pipe.

---

## [3.11.4] — 2026-05-13

### Fixed

- **OQ: report tests no longer fail on machines with macOS TCC restrictions** —
  the six `--report` test cases (TC-VER-012–014, TC-VER-DISC-009–011) previously
  used `glob.glob(~/Downloads/)` to verify report creation. On macOS the test
  process is blocked from listing `~/Downloads/`, returning an empty list even
  when the `.docx` was successfully written. Tests now parse the output path
  directly from the script's printed `"DV Report saved to: …"` /
  `"Verification report saved to: …"` messages using `re.search()`, eliminating
  the directory-listing dependency entirely.

---

## [3.11.3] — 2026-05-13

### Fixed

- **GUI: logo upload uses file picker instead of path input** — the previous
  text-input + file-copy approach still triggered a macOS TCC `PermissionError`
  because the Streamlit process itself cannot read from `~/Downloads/`. Replaced
  with `st.file_uploader`: the user picks the file through a system dialog, which
  grants the process permission. Bytes are received in-memory and written directly
  to `pack/shared/`, so no path outside the pack is ever accessed by the process.

---

## [3.11.2] — 2026-05-13

### Fixed

- **GUI: logo copied into `pack/shared/` on save** — the Settings form previously
  stored the raw absolute path the user typed (often `~/Downloads/`). macOS TCC
  blocks subprocess access to `~/Downloads/`, causing `jr_pack` to crash with
  `PermissionError` when generating Word reports via `system2()` in R. The form
  now copies the logo file into `pack/shared/` and writes a relative path to
  `jr_pack_config.json`, which is always accessible to subprocesses. Existing
  installs can re-save in Settings to migrate.

- **`--report`: exit non-zero when `jr_pack` fails** — previously the script
  printed "Retry manually" and continued with exit 0, masking `jr_pack` failures.
  OQ tests then failed with a confusing "no .docx found" message. Now
  `quit(status=1)` is called so the failure and `jr_pack` error output are
  visible in the test report. Applies to `jrc_verify_attr.R` and
  `jrc_verify_discrete.R`.

- **OQ: `--report` failure shows `~/Downloads/` contents** — when the expected
  report file is not found, the assertion now lists every file written to
  `~/Downloads/` during the run, making filename mismatches immediately visible.

---

## [3.11.1] — 2026-05-13

### Fixed

- **OQ: `--report` tests pass on machines with Validation Pack installed** — when
  `jr_pack.py` is present it converts the JSON sidecar to a Word report in
  `~/Downloads/` and removes the intermediate HTML/JSON files. Tests
  TC-VER-012..014 and TC-VER-DISC-009..011 previously always checked for
  HTML/JSON and failed on Pack-installed machines. Tests now detect
  `PACK_INSTALLED` at import time and assert `.docx` (Pack present, validated
  with `zipfile.is_zipfile`) or HTML/JSON + JSON content (Pack absent).

- **GUI: "Connection error" popup suppressed on close** — clicking "Close GUI"
  now injects a `display:none` CSS rule for Streamlit's BaseWeb modal before the
  server shuts down, so the browser-side "Connection error" dialog is hidden when
  the WebSocket drops. Button renamed from "Stop JR App" to "Close GUI" and the
  caption simplified.

### Changed

- **Consolidated Python version pin to `admin/python_version.txt`** — the
  duplicate `oq/python_version.txt` (and three dead module-level copies in
  `repos/msa/oq/`, `repos/spc/oq/`, `repos/shelf_life/oq/`) have been removed.
  `admin_oq_validate` and all 8 module `admin_*_oq` runners now read the pin
  from `admin/python_version.txt` directly. `admin_create_repo` updated to
  source the pin from `admin/` and no longer copies a version file into new
  module `oq/` directories. No behaviour change — both venvs have always used
  the same Python version (3.11.9).

---

## [3.11.0] — 2026-05-09

### Added

- **GUI: Admin tab** — third sidebar tab gated behind a SHA256-hashed password.
  Admin can set a password on first use, log in/out per browser session, and run
  all admin commands (`admin_install_R`, `admin_install_Python`, `admin_create_hash`,
  `admin_validate`, `admin_setup`, `jr_versions`) with live streaming output.
  Admin config stored in `app/.admin_config.json` (gitignored).
- **GUI: Export Configured App** — admin button in the Admin tab that bundles a
  configured copy of `JR Anchored.app` (macOS) or a configured `.bat` + launcher
  zip (Windows) with the project root path baked in, ready to share with end users.
- **GUI: Environment pre-flight checks** — sidebar shows `✅`/`❌` R and Python
  version status on every page, compared against `admin/r_version.txt` and
  `admin/python_version.txt`. Scripts page shows an error banner if versions mismatch.
- **GUI: Settings UX improvements** — Validation Pack section shows a friendly
  `st.info` for non-admin users; Terminal Access and Install App sections clearly
  labelled as optional; Install App explains the Launchpad benefit.

### Fixed

- **`JR Anchored.app` launcher: no Terminal window** — launcher rewritten to use
  `nohup /bin/zsh -l -c "exec jr_app" & disown`. The app now detaches silently;
  a macOS notification confirms the browser is opening. No Terminal window left open.
- **`JR Anchored.app` launcher: full PATH on double-click** — changed to a zsh
  login shell (`-l`) so `~/.zprofile` is sourced, giving the app the same R, Python,
  and Homebrew PATH as an interactive Terminal session.
- **GUI: Python 3.9 type-hint error** — added `from __future__ import annotations`
  to fix `str | None` syntax failing on macOS system Python (< 3.10).
- **`_get_env_status()`: Rscript not found via bare name** — now tries four candidate
  paths (`Rscript`, `/usr/local/bin/Rscript`, `/opt/homebrew/bin/Rscript`,
  `/Library/Frameworks/R.framework/Resources/bin/Rscript`) before reporting R as
  not found, ensuring detection works even when PATH is minimal.
- **`setup_jr_path.sh`: project root written unconditionally** — `jr_project_root.txt`
  is now always written to `~/.jrscript/`, even when PATH was already configured,
  so the GUI launcher always knows the project location.
- **`JR Anchored.app` launcher: 3-level project root fallback** — checks
  `Contents/Resources/jr_project_root.txt` (admin-exported), then
  `~/.jrscript/jr_project_root.txt` (written by `setup_jr_path.sh`), then
  relative path (app still in project folder).
- **`JR Anchored.bat`: configurable project root** — added `JRROOT` variable
  (blank = auto-detect) for admin-distributed Windows launchers.

---

## [3.10.0] — 2026-05-08

### Fixed

- **All 12 `--report` scripts: input file SHA-256 added to JSON sidecar** — generated Word
  reports now include the input filename and its SHA-256 hash, providing a complete data
  traceability chain for auditors. Scripts with numeric-only inputs (`jrc_verify_discrete`,
  `jrc_shelf_life_arrhenius`, `jrc_shelf_life_q10`) are unaffected. Pack generators
  (`generate_dv_report.py`, `generate_pv_report.py`) updated to render the new fields.
- **`jrc_shelf_life_linear`: JSON sidecar format mismatch with DV report generator** —
  `method_rows`/`results_rows` were written as `{"label","value"}` pairs under keys
  `"method_rows"`/`"results_rows"`, while `generate_dv_report.py` reads `"method"`/`"results"`
  with `{"k","v"}` pairs. Sections 2 and 3 of the generated Word report rendered empty.
  Converted to the standard format and renamed the keys.
- **4 DV scripts: top-level `input_file` and `input_sha256` missing from JSON sidecar** —
  `jrc_shelf_life_extrapolate`, `jrc_shelf_life_poolability`, `jrc_msa_gauge_rr`, and
  `jrc_rdt_verify` were embedding SHA-256 only inside the `method`/`results` arrays.
  Added top-level fields to align with `jrc_verify_attr` and `jrc_shelf_life_linear`,
  enabling the dedicated Input Data Traceability block in the generated Word report.

### Added

- **`admin/admin_setup`**: new script that runs all first-time (or subsequent) admin setup
  steps in one command — pre-flight checks R and Python versions, verifies the shared
  repository is accessible, then runs `admin_install_R [--rebuild]` →
  `admin_install_Python [--rebuild]` → `admin_create_hash` → `admin_validate` →
  `setup_jr_path.sh`. Pass `--rebuild` for a first-time internet-based build.
- **`admin/admin_update`**: new script for safe over-the-air updates — fetches from GitHub,
  runs pre-flight conflict checks (uncommitted changes, local commits, R version mismatch),
  shows what the pull will change (R packages diff, Python env), and when clear automatically
  runs `git pull` → `admin_create_hash` → `admin_install_R` / `admin_install_Python` as needed.
- **Validation Pack — Input file folder field**: DV and PV Word reports now include a
  yellow user-fill "Input file folder" row in the traceability section, allowing the user
  to record where the input file is stored so an auditor can locate it independently.
- **Website — `get-started.html`**: admin first-time setup steps condensed to
  `admin_setup --rebuild`; subsequent setups condensed to `admin_setup`.
- **Website — `guide_install.html`**: sections 5.3–5.6 replaced with single
  `admin_setup --rebuild` step; section 8.1 (Upgrading) updated to use `admin_update`.
- **Website — `guide_customization.html`, `regulatory.html`, `guide_validation.html`**:
  stale `renv.lock` references replaced with `R_requirements.txt`.

### Changed

- **`bin/jrrun`: R rebuild trigger switches from `renv.lock` to `R_requirements.txt` + `r_version.txt`** —
  `renv.lock` is a derived file generated deterministically by `admin_install_R`
  from `R_requirements.txt` and the installed R version. Distributing it via git
  caused merge conflicts whenever admins upgraded R or added packages locally.
  The rebuild trigger is now the combined SHA-256 of `R_requirements.txt` and
  `r_version.txt`. During a rebuild, `jrrun` regenerates `renv.lock` inline from
  `R_requirements.txt` before calling `renv::restore`, so a stale lockfile can
  never silently install the wrong package versions.
- **`admin/admin_install_R`: writes matching combined hash to `.renv_lock_hash`** —
  prevents a spurious jrrun rebuild immediately after `admin_install_R` has run.
- **`admin/renv.lock` gitignored and removed from git index** — new admins
  generate it locally on first `admin_install_R`; existing admins are unaffected
  (file remains on disk after pull).

---

## [3.9.1] — 2026-05-07

### Fixed

- **`bin/jrrun`: locale warnings on every script run** — `LANG` was used as an
  internal variable to flag R vs Python scripts. Because `LANG` is a standard POSIX
  locale environment variable already exported by the shell, overwriting it with `"R"`
  leaked into all child processes (Rscript, Perl), causing locale warnings on every run.
  Renamed to `_JR_LANG` throughout. No behaviour change; no OQ re-run required.

---

## [3.9.0] — 2026-05-07

### Added

- **GUI: `--help` expander on every script page** — a collapsible "📖 Script help"
  expander appears below the script description, showing the full help text for the
  selected script. Content is read from the `help/` files at render time.
- **GUI: Curve Properties — config file upload** — users can now upload their own
  `.cfg` and data CSV directly in the GUI alongside the existing sample-config
  selector. The GUI patches the `file =` path in the uploaded config to point to
  the temp CSV, and writes the cfg to `~/Downloads` so all output files land there
  with meaningful names derived from the uploaded filename.
- **GUI: Curve Properties — sample config viewer** — a collapsible "📋 Sample config"
  expander shows the full annotated `sample.cfg` so users can read the config syntax
  without leaving the GUI.
- **GUI: Curve Properties — inline PDF plot** — after a successful run, the PDF plot
  is rendered inline in the GUI via a base64 `<iframe>`, with a download button below.
  No new dependencies required.
- **GUI: Word report checkbox gated on pack installation** — the "Generate Word report"
  checkbox is shown enabled only when `pack/jr_pack.py` is present (i.e. the Validation
  Pack has been installed). On machines without the pack the checkbox is greyed out with
  a caption linking to dwylup.com. Previously the checkbox was always enabled, leading to
  a silent HTML-only fallback with no user feedback.

---

## [3.8.2] — 2026-05-04

### Changed

- **R version bumped to 4.6** — `admin/r_version.txt` updated from `4.5` to `4.6`.
  Run `admin_install_R --rebuild` to update the local package repository.
- **ggplot2 updated to 4.0.3** — previous pin `4.0.2` is no longer available on CRAN.
- **OQ suite re-qualified** — all 425 tests pass under R 4.6.0.

### Fixed

- **`admin_install_R --rebuild` failed on R 4.6** — macOS ARM binary path was hardcoded
  to `big-sur-arm64`, which CRAN replaced with `sonoma-arm64` for R 4.4+. The installer
  now queries `contrib.url()` from the installed R binary to determine the correct
  platform string, with an architecture-based fallback.

### Added

- **`tools/owner_check_versions.py`** — owner-only maintenance script that checks whether
  R packages in `admin/R_requirements.txt`, the R version in `admin/r_version.txt`, and
  Python packages in `admin/python_requirements.txt` still match what CRAN and PyPI
  currently serve. Reports critical issues (missing/changed versions) and optional updates.
  Run before each release: `python3 tools/owner_check_versions.py`.
- **`tools/owner_daily_check.sh`** — cron wrapper for the above. Writes a timestamped
  entry to `~/.jrscript/owner_check.log` on every run; fires a macOS Notification Centre
  alert when action is required. Crontab entry: `17 8 * * * /path/to/jrscripts/tools/owner_daily_check.sh`.

---

## [3.8.1] — 2026-04-29

### Fixed

- **GUI: Settings page `PACK_DIR` path** — the Settings page was looking for
  `jr_pack_config.json` in `../jr-anchored-pack/` (the developer's sibling-repo
  layout) instead of `./pack/` (the customer deployment path). Settings now
  resolves correctly after unzipping the pack archive.
- **GUI: Settings warning message** — "Pack not found" replaced with
  "Configuration file not found" and the exact expected path, to distinguish a
  missing config from a missing pack installation.
- **Validation Pack installer: `jr_pack_config.json` not created** — `install.sh`
  now creates a default (empty) `jr_pack_config.json` as Step 3 of the
  installation. Previously the file was absent after install, causing the GUI
  Settings page and `jr_pack configure` to fail. `jr_pack configure` is also
  hardened to initialise from defaults if the file does not yet exist.

---

## [3.8.0] — 2026-04-25

### Fixed

- **`jrc_verify_attr --report`** — converted from legacy HTML-only output to the standard
  JSON + Word pattern used by all other `--report` scripts. Output now writes to
  `~/Downloads/` (was written to the same temp folder as the input CSV). JSON sidecar
  includes method rows (method, reference, proportion, confidence, interval type,
  transformation, column) and results rows (n, mean, SD, K-factor, TI limits, spec limits,
  verdict). `jr_log_output_hashes` now logs only the PNG (HTML is removed after Word
  generation). `report_type` is `"dv"`.
- **`jrc_verify_discrete --report`** — same conversion applied; JSON sidecar includes
  method rows (method, reference, N, f, proportion, confidence) and results rows (observed
  failure rate, upper CI, allowable failure rate, margin, verdict). No PNG for this script.

### Added

- **`generate_dv_report.py` subtitles** — cover-page subtitle entries added for
  `jrc_verify_attr` ("Statistical Tolerance Interval Verification") and
  `jrc_verify_discrete` ("Attribute (Pass/Fail) Verification — Clopper-Pearson").
- **OQ: 4 new test cases**
  - `TC-VER-012` updated to check HTML + JSON in `~/Downloads/` (was checking old path)
  - `TC-VER-013`: JSON sidecar created for `jrc_verify_attr --report`
  - `TC-VER-014`: JSON content — `report_type=="dv"` and `verdict_pass is True`
  - `TC-VER-DISC-010`: JSON sidecar created for `jrc_verify_discrete --report`
  - `TC-VER-DISC-011`: JSON content — `report_type=="dv"` and `verdict_pass is True`

---

## [3.7.0] — 2026-04-25

### Added

- **GUI: Settings page** — new top-level sidebar navigation item opens a form that reads
  and writes `jr_pack_config.json` (company name, logo path, document number prefix).
  Replaces the need to edit the JSON file or run `jr_pack configure` from the terminal.
- **GUI: `--report` checkbox** — all 16 scripts that support `--report` now show a
  checkbox below their parameter panel. When ticked, `--report` is appended to the
  command, triggering Word report generation via the JR Anchored Validation Pack.
- **GUI: 6 new scripts** — added to the script catalogue with correct parameter panels
  and sample data:
  - `jrc_verify_discrete` (Sample Size module) — N, f, proportion, confidence inputs
  - `jrc_shelf_life_q10`, `jrc_shelf_life_arrhenius` (new Shelf Life module) —
    temperature and duration inputs; no file required
  - `jrc_shelf_life_linear` (Shelf Life) — file + spec limit + confidence + direction +
    optional transform selector
  - `jrc_shelf_life_poolability` (Shelf Life) — fileonly with shelf_life sample data
  - `jrc_shelf_life_extrapolate` (Shelf Life) — model CSV + target time

---

## [3.6.0] — 2026-04-25

### Added

- **OQ tests for `jrc_verify_attr` and `jrc_verify_discrete` `--report`** — two new test
  classes added to `oq/test_statistical_suite.py`:
  - `TC-VER-012`: `--report` exits 0 and HTML report is written next to the input CSV
  - `TC-VER-DISC-009`: `--report` exits 0 and HTML report is written to `~/Downloads/`
- **`guide_reports.html` cmd-block completed** — Step 1 example block now shows all 16
  supported scripts (was 13). Added: `jrc_verify_attr`, `jrc_rdt_verify`,
  `jrc_cap_nonnormal`. Fixed `jrc_verify_discrete` comment from "attribute pass/fail"
  → "pass/fail binomial".

---

## [3.5.0] — 2026-04-25

### Added

- **OQ test cases for `--report` sidecar feature** — 42 new pytest TCs added across 10 OQ
  test files, bringing the total to 425 implemented test cases. Each of the 14 scripts
  that produce `--report` output now has three dedicated assertions:
  - `_html_created`: `--report` exits 0 and the HTML report file appears in `~/Downloads/`
  - `_json_sidecar_created`: the `_data.json` sidecar is written alongside the HTML
  - `_json_content`: the JSON parses cleanly; `report_type` matches the expected string
    (`"pv"`, `"dv"`, `"msa"`, or `"rdt"`); `verdict_pass` is a boolean, and `True` for
    all passing reference datasets
  - Covers all 14 scripts: cap_normal, cap_nonnormal, cap_sixpack, spc_imr, spc_xbar_r,
    spc_xbar_s, spc_p (PV); shelf_life_linear, arrhenius, q10, poolability, extrapolate
    (DV); msa_gauge_rr (MSA); rdt_verify (RDT)

---

## [3.4.0] — 2026-04-24

### Added

- **JSON sidecar for `jrc_msa_gauge_rr` and `jrc_rdt_verify`** — both scripts now write a
  `_data.json` alongside the HTML when `--report` is passed. The sidecar is consumed by
  `jr_pack deliverables msa-report` / `rdt-report` to generate a Word (.docx) report.
  - MSA JSON includes `anova[]` (4-row ANOVA table) and `variance_components[]` (7 rows
    with Gauge R&R sub-rows) for multi-column table rendering in the generator.
  - RDT JSON includes `use_weibayes` boolean flag; all Weibayes numeric fields default to
    `null` when Weibayes mode is not active, enabling conditional section rendering.

---

## [3.3.0] — 2026-04-24

### Added

- **JSON sidecar for all 5 DV shelf life scripts** — each `save_*_report()` function now
  writes a `_data.json` alongside the HTML, compatible with `jr_pack deliverables dv-report`.
  - `jrc_shelf_life_arrhenius`, `jrc_shelf_life_q10`: `verdict_pass` hardcoded `true`
    (pure calculation scripts with no spec-limit comparison).
  - `jrc_shelf_life_linear`, `jrc_shelf_life_extrapolate`: `verdict_pass` derived from
    CI bound vs spec limit check.
  - `jrc_shelf_life_poolability`: `verdict_pass` is `true` when decision is `"FULL POOL"`;
    includes a `batch_fits[]` array with per-batch regression data for table rendering.

---

## [3.2.0] — 2026-04-24

### Added

- **JSON sidecar for all 7 PV scripts** — all seven PV/SPC scripts now write a `_data.json`
  alongside the HTML when `--report` is passed. The sidecar is consumed by
  `jr_pack deliverables pv-report` to generate a Word (.docx) Process Validation Report.
  - Scripts updated: `jrc_cap_normal`, `jrc_cap_nonnormal`, `jrc_cap_sixpack`,
    `jrc_spc_imr`, `jrc_spc_xbar_r`, `jrc_spc_xbar_s`, `jrc_spc_p`.
  - `verdict_pass` is `true` when the overall PV/SPC verdict is CAPABLE/EXCELLENT or
    IN CONTROL; `false` for MARGINAL, NOT CAPABLE, or OUT OF CONTROL.

---

## [3.1.0] — 2026-04-24

### Added

- **Python bypass protection** — `jrc_convert_csv` and `jrc_convert_txt` now exit with a
  clear error message if run outside `jrrun` (i.e., when `VENV_PATH` is not set), matching
  the bypass-protection behaviour of all R scripts.

### Fixed

- **`admin_generate_validate_R`**: added transitive dependency inventory section — all
  `renv`-resolved packages are listed as informational (ℹ️) in the evidence file without
  affecting PASS/FAIL. Semantics of `R_requirements.txt` clarified: it declares only
  packages explicitly required by scripts; transitive dependencies are resolved and
  managed by `renv`.
- **`admin_generate_validate_R`**: fixed silent drop of last line in `R_base_requirements.txt`
  (missing trailing newline); `MASS` is now correctly included in base package validation.
- **`admin_install_R`**: added pre-flight checks before invoking `renv install` — verifies
  the local repo directory exists, no Dropbox sync-conflict files are present, the `PACKAGES`
  index is found, and every pinned package file is present.

---

## [3.0.0] — 2026-04-23

### Added

- **`--report` flag on all remaining SPC and cap scripts** — completes the full `--report`
  coverage across the framework. Each produces a self-contained PV HTML report read from
  `pv_report_template.html` (JR Anchored Validation Pack) with chart embedded as base64.
  - `jrc_spc_xbar_r` v1.0 → v1.1 — X-bar / R chart: constants table, per-subgroup OOC violation table with rules
  - `jrc_spc_xbar_s` v1.0 → v1.1 — X-bar / S chart: analytical constants (c4, A3, B3, B4), OOC subgroups
  - `jrc_spc_p` v1.0 → v1.1 — P-chart: p-bar, variable/constant limits, WE violations
  - `jrc_cap_sixpack` v1.0 → v1.1 — full sixpack: I-MR limits, all capability indices (Cp, Cpk, Pp, Ppk, Cpm), Shapiro-Wilk note, PPM

---

## [2.9.0] — 2026-04-23

### Added

- **`--report` flag on all 5 shelf life scripts** — each produces a self-contained HTML Design
  Verification report with SHA-256 logging. Gated by `docs/templates/dv_report_template.html`
  (JR Anchored Validation Pack).
  - `jrc_shelf_life_q10` v1.0 → v1.1 — Q10 calculation sheet, sensitivity table (Q10 ±0.5)
  - `jrc_shelf_life_arrhenius` v1.0 → v1.1 — Arrhenius calculation sheet, Ea sensitivity (±2 kcal/mol)
  - `jrc_shelf_life_linear` v1.1 → v1.2 — linear stability model: regression stats, shelf life estimate, chart embedded
  - `jrc_shelf_life_poolability` v1.0 → v1.1 — ICH Q1E ANCOVA decision (FULL/PARTIAL/DO NOT POOL), per-batch table, chart embedded
  - `jrc_shelf_life_extrapolate` v1.1 → v1.2 — projection at target time, ICH Q1E extrapolation warnings, pass/fail verdict

---

## [2.8.0] — 2026-04-23

### Added

- **`--report` flag** — Design Verification and Process Validation report generation,
  available on seven scripts. Each run with `--report` produces a self-contained HTML
  file (chart embedded as base64, no external dependencies) with a six-section structure:
  Purpose & Scope, Test Setup, Statistical Method, Results (with verdict), Conclusion, and
  Approvals table. SHA-256 of the HTML is logged to the run log alongside the PNG hash.
  Requires the JR Anchored Validation Pack (sentinel gate: `docs/templates/pv_report_template.html`
  or `dv_report_template.html`).

  **Design Verification scripts** (report type DV, files to DHF):
  - `jrc_verify_discrete` v1.0 → v1.1 — binomial pass/fail, Clopper-Pearson CI
  - `jrc_rdt_verify` v1.0 → v1.1 — binomial + Weibayes RDT verification, unit timeline chart
  - `jrc_msa_gauge_rr` — gauge R&R ANOVA, %Study Var, colour-coded ACCEPTABLE/MARGINAL/UNACCEPTABLE verdict

  **Process Validation scripts** (report type PV, files to process validation file):
  - `jrc_cap_normal` v1.0 → v1.1 — Cp/Cpk/Pp/Ppk/Cpm, sigma level, PPM estimate, capability histogram
  - `jrc_cap_nonnormal` v1.0 → v1.1 — percentile-based Ppk (ISO 22514-2 / AIAG), Shapiro-Wilk note
  - `jrc_spc_imr` v1.0 → v1.1 — I-MR control limits, Western Electric violations table, STABLE/SIGNALS verdict

  **Note:** `jrc_verify_attr` --report (v1.1) was added in v2.6.x and is unchanged.

---

## [2.7.0] — 2026-04-22

### Added

- **`jrc_rdt_plan`** v1.0 — Reliability Demonstration Test planner. Given a reliability
  claim (R, C, target_life), outputs required sample sizes for k = 0 to 5 allowed
  failures. Supports Bogey/binomial mode (no Weibull shape assumption) and Weibayes
  mode (beta provided). When accel_factor > 1, shows a beta sensitivity table. Saves
  a two-panel PNG (n-vs-k bar chart + beta sensitivity line plot) to ~/Downloads/.
  Uses exact `-log(R)` formula throughout (not the `1-R` approximation).

- **`jrc_rdt_verify`** v1.0 — Post-test RDT evaluator. Reads a CSV of unit test times
  and pass/fail statuses. Reports both Binomial (Clopper-Pearson exact) and Weibayes
  verdicts against the pre-specified claim. PASS if either method passes; disagreement
  is flagged. Saves a two-panel PNG (unit timeline + demonstrated reliability bars).
  Supports `--accel_factor`, `--beta`, `--time_col`, `--status_col`. Script exits 0
  for both PASS and FAIL; non-zero = input/runtime error.

- **`repos/rdt/`** — new module folder with `R/`, `wrapper/`, `help/`, `sample_data/`,
  `oq/`, `oq/data/` sub-directories. Wrappers in `repos/rdt/wrapper/` (path
  `../../../bin/jrrun` — aligned with all other module-local wrappers).

- **Help files**: `repos/rdt/help/jrc_rdt_plan.txt` and `jrc_rdt_verify.txt` — full
  documentation including methods, formulas, FDA/regulatory context (21 CFR 820.30(f),
  ISO 13485:2016 §7.3.6), and worked examples.

- **Sample data**: `repos/rdt/sample_data/rdt_verify_example.csv` (45 units, all
  survived, status=0) and `repos/rdt/sample_data/rdt_plan_notes.txt` (4 worked
  examples: Bogey n=45, Weibayes AF=1 n=45, Weibayes AF=2 beta=2 n=12, k_allowed=1).

- **OQ suite — JR-VP-RDT-001**: 25 test cases across `test_rdt_plan.py` (13 TCs)
  and `test_rdt_verify.py` (12 TCs) in `repos/rdt/oq/`. All numeric TCs include
  independently-derived Python references (closed-form Beta(1,n) ppf, exact
  qchisq(0.90, 2) = −2·ln(0.10), Erlang-2 bisection for qchisq(0.90, 4)). 25/25 pass.

- **OQ fixtures**: 5 CSVs in `repos/rdt/oq/data/` — `rdt_verify_pass.csv` (45 units),
  `rdt_verify_fail.csv` (20 units), `rdt_verify_zero_failures.csv` (50 units),
  `rdt_verify_all_failed_early.csv` (edge-case: all failed before target life),
  `rdt_verify_missing_col.csv` (column-validation fixture).

- **`repos/rdt/admin_rdt_oq`** — OQ runner script (shares the common OQ venv).

- **Validation artefacts**: `repos/rdt/docs/rdt_validation_plan.pdf` (JR-VP-RDT-001,
  13 URs, 25 TCs, RTM) and `repos/rdt/docs/rdt_validation_report.pdf` (JR-VR-RDT-001,
  25/25 PASS, 0 deviations).

- **GUI**: "Reliability Demo Testing" group added to `app/jr_app.py` — Plan Test
  (`rdt_plan` param type, no file upload) and Evaluate Results (`rdt_verify` param
  type, file upload with sample data). PNG displayed inline after run.

- **`rdt_module_plan.md`** — full 9-section implementation plan for the RDT module.

- **`new_module_plan_template.md`** — generic module plan template for future modules.

---

## [2.6.0] — 2026-04-19

### Added

- **`jrc_verify_discrete`** v1.0 — discrete (pass/fail) verification assessment using
  the exact Clopper-Pearson one-sided binomial confidence interval. Takes N (units
  tested), f (failures observed), required proportion P, and confidence C. Reports the
  upper CI bound on the true failure rate, allowable failure rate (= 1 − P), margin in
  percentage points, and a PASS/FAIL verdict. If f = 0, a note directs the user to
  `jrc_ss_discrete_ci` as the canonical zero-failure tool. Complements `jrc_verify_attr`
  in the Verification suite.

- **OQ: TC-VER-DISC-001..008** — 8 new tests in `oq/test_statistical_suite.py`.
  TC-VER-DISC-004 independently verifies the Clopper-Pearson upper bound using
  pure-Python bisection on the Binomial CDF; TC-VER-DISC-005 uses the exact formula
  1 − (1−C)^(1/N) for f = 0 — both computed without R.

### Validation

- **JR-VP-002 v3.0** — Statistics Validation Plan updated: UR-025 added, Section 10.9
  (TC-VER-DISC-001..008), total 185 test cases.
- **JR-OQ-001 v4.0** — Statistics Validation Report updated: references v3.0 plan,
  185/185 PASS. Fixed TC parsing bug in generator (multi-line evidence format now
  correctly parsed — all TCs show PASS instead of NOT RUN).

### Web (web-local only)

- **`script_guide.html`** — `jrc_verify_discrete` entry added: SCRIPTS array,
  CATEGORIES (Data Analysis), TREE (analyse + plan_attribute nodes), GUI_NAMES,
  and EXAMPLES with 5 explanatory sections.
- **`modules.html`** — Core module updated: 24 → 25 scripts; Data Analysis group
  updated to 8 scripts with discrete verification mentioned.
- **`index.html`** — stat counters: 51 → 52 validated scripts, 535 → 543 OQ tests;
  meta description and hero paragraph updated to match.
- **All 22 pages** — footer version bumped v2.5.0 → v2.6.0.
- **Nav dropdown** — fixed hover: CSS `transition-delay: 0.15s` on hide gives the
  cursor time to cross the gap between button and menu before the menu fades out.
  Showing remains instant (no delay). JS click-toggle retained for touch devices.
- **`web/examples/jrc_verify_discrete.png`** — terminal screenshot generated via
  `make_terminal_pngs.py`.

### GitHub

- **Release v2.6.0** published at `github.com/ubrowz/jr-anchored/releases/tag/v2.6.0`
  — tagged at commit 3423747, marked Latest, release notes cover all additions
  since v2.0.0 (the previous GitHub release).

---

## [2.5.0] — Shelf Life Phase 5: extrapolate log transform, wrapper alignment, validation documents (2026-04-19)

### Added

- **`jrc_shelf_life_extrapolate` v1.0 → v1.1** — reads the `transform` field written
  by `jrc_shelf_life_linear` into the model CSV. When `transform = log`, the fitted
  value and both CI bounds are back-transformed via `exp()` before comparison to the
  spec limit and display — all results are on the original measurement scale.
  Backward-compatible: model CSVs produced without `--transform log` omit the field;
  extrapolate defaults to `none`. Transform line added to output header.

- **`repos/shelf_life/wrapper/`** — dedicated wrapper subfolder created to align
  shelf_life with all other modules (as, cap, corr, curve, msa, spc). Five wrappers
  moved from root `wrapper/` to `repos/shelf_life/wrapper/`. `setup_jr_path.sh`
  loops over `repos/*/wrapper/` dynamically — no PATH changes required.

- **Phase 5 validation documents** (`repos/shelf_life/docs/ignore/`, gitignored):
  - `generate_shelf_life_validation_plan.py` — python-docx generator for
    JR-VP-SHELF-001 v1.0 (27 URs, 57 TCs, full RTM, regulatory references:
    ASTM F1980, ISO 11607, ICH Q1E, ICH Q1A(R2), Brown-Forsythe 1974).
  - `generate_shelf_life_validation_report.py` — python-docx generator for
    JR-VR-SHELF-001 v1.0; reads latest `shelf_life_oq_execution_*.txt` evidence
    file automatically; 57/57 PASS confirmed from
    `shelf_life_oq_execution_20260419T080311.txt`.

### Changed

- **`.gitignore`** — `repos/shelf_life/docs/ignore/` added alongside the other
  six module doc-generator entries.

---

## [2.5.0] — jrc_shelf_life_linear: --transform log flag (2026-04-19)

### Added

- **`jrc_shelf_life_linear --transform log`** — new optional flag that fits
  `lm(log(value) ~ time)` instead of `lm(value ~ time)`. The confidence interval
  is back-transformed via `exp()` before comparing to `spec_limit`, so all results
  (shelf life, plot, model CSV) remain on the original measurement scale. Use for
  right-skewed data or when variance grows with the mean — typical of log-normal
  distributions (bioburden, moisture uptake, degradation byproducts). All values
  must be strictly positive. The plot title is annotated `[log-linear model]` and
  the terminal output reports the slope as both the log-scale coefficient and the
  equivalent percentage change per unit time.

- **TC-SHELF-LIN-013..016** — 4 new OQ tests for `--transform log`:
  - TC-SHELF-LIN-013: happy path → exit 0, "log" noted in output
  - TC-SHELF-LIN-014: numerical correctness — shelf life independently computed via
    pure-Python log-OLS + bisection (`_bisect_shelf_life_log()`), tolerance ±0.05
  - TC-SHELF-LIN-015: value ≤ 0 with `--transform log` → non-zero exit
  - TC-SHELF-LIN-016: model CSV contains `transform = log` field

  Shelf life OQ total: **53 → 57 tests**. All 57 pass.

### Changed

- **`jrc_shelf_life_linear`** version bumped to 1.1. Model CSV now includes a
  `transform` row (`none` or `log`).
- **`help/jrc_shelf_life_linear.txt`** — `--transform` argument documented with
  usage guidance and a log-transform example.

---

## [2.5.0] — Shelf Life module Phase 1–4: scripts, OQ suite, independent validation (2026-04-18)

### Added

- **`repos/shelf_life/`** — new Shelf Life & Degradation Analysis module with 5 R scripts:
  - **`jrc_shelf_life_q10`** — accelerated ageing via Q10 method (ASTM F1980). Computes
    acceleration factor and real-time equivalent; reports Q10 ± 0.5 sensitivity bracket.
  - **`jrc_shelf_life_arrhenius`** — accelerated ageing via Arrhenius kinetics (ISO 11607 /
    ICH Q1E). Computes AF from activation energy and temperature pair; reports Ea ± 2
    kcal/mol sensitivity bracket. Supports `--unit C|K`.
  - **`jrc_shelf_life_linear`** — linear degradation model with shelf life estimation.
    Fits `lm(value ~ time)` on individual pull-and-test measurements; performs
    Brown-Forsythe homogeneity-of-variance test (robust to non-normal data — see note
    below); solves for shelf life as the time where the lower (or upper) confidence
    bound of the predicted mean crosses the specification limit. Saves PNG plot and
    model coefficient CSV for downstream use.
  - **`jrc_shelf_life_poolability`** — ICH Q1E batch poolability analysis. Two-step
    ANCOVA (α = 0.25): tests batch × time interaction then batch main effect. Reports
    FULL POOL / PARTIAL POOL / DO NOT POOL with F-statistics and p-values.
  - **`jrc_shelf_life_extrapolate`** — projects value and confidence interval to a target
    time point from a `jrc_shelf_life_linear` model CSV. Enforces ICH Q1E extrapolation
    limits: ⚠️ warning at > 50% beyond last observation; ❌ hard stop at > 100%.

- **`repos/shelf_life/oq/test_shelf_life_suite.py`** — 53 OQ tests across 5 classes
  (TC-SHELF-Q10-001..010, TC-SHELF-ARR-001..010, TC-SHELF-LIN-001..012,
  TC-SHELF-POOL-001..010, TC-SHELF-EXT-001..011). All 53 pass (subsequently
  extended to 57 — see entry above).

- **`repos/shelf_life/oq/data/`** — 13 CSV test fixtures covering happy paths,
  known-data numerical cases, edge conditions (heterogeneous variance, below-spec at
  t=0, direction=high), and error paths (missing column, too few time points, single
  batch, wrong-script model file).

- **`repos/shelf_life/admin_shelf_life_oq`** — OQ runner producing timestamped evidence
  file at `~/.jrscript/<PROJECT_ID>/validation/shelf_life_oq_execution_<ts>.txt`.

- **`wrapper/jrc_shelf_life_*`** — five wrappers (executable); `help/jrc_shelf_life_*` —
  five help files.

### Design decisions

- **Brown-Forsythe homogeneity test (base R, no `car` package):** `car::leveneTest` was
  considered but requires a new package and would trigger full environment re-validation.
  Brown-Forsythe is implemented directly as a one-way ANOVA on absolute deviations from
  group medians — equivalent to `car::leveneTest(..., center=median)` — using only base R
  `lm()` and `anova()`. Robust to non-normal data (unlike Bartlett's test), which matters
  for real-world shelf life data (bioburden, particulate counts, degradation byproducts).
  `nlme` (used by `jrc_shelf_life_poolability`) is a recommended package bundled with R;
  no new packages added to `R_requirements.txt`.

- **OQ numerical independence:** All numerical correctness tests compute reference values
  independently of the R scripts:
  - Q10: exact arithmetic (2^3 = 8.0)
  - Arrhenius: `math.exp()` in Python test code, tolerance ±0.001
  - Linear shelf life: pure-Python OLS + bisection in test body, tolerance ±0.05
  - Extrapolate CI bounds: closed-form from known coefficients + NIST t-table, ±0.05
  - Poolability: ANCOVA p-values extracted and verified against expected direction

### Pending (Phase 6–7)

- ~~Phase 5: Validation Plan document (JR-VP-SHELF-001) + Validation Report~~ ✅ complete
- Phase 6: `admin_create_hash`, CHANGELOG version tag, push as v2.1.0
- Phase 7: website updates (new module page, script guide entries, shelf life guide,
  homepage counters)
- Phase 8: N/A (JR Anchored for Java parked)

---

## [2.5.0] — DoE guide expansion, jrc_verify_attr report improvements, Validation Pack CLI (2026-04-10)

### Fixed

- **`R/jrc_verify_attr.R`** — HTML verification report improvements for Word compatibility:
  - Body background changed from `#ebebeb` to `#fff` (was rendering grey in Word).
  - Embedded chart now uses `width="100%"` HTML attribute in addition to CSS, preventing
    Word from rendering the image at its native pixel width.
  - `ggsave` dimensions reduced from 9 × 6 inches to 6.5 × 4.5 inches at 150 DPI so
    the chart fits within standard Letter page margins when opened in Word.

### Added

- **`R/jrc_verify_attr.R`** — two new fields in the HTML verification report:
  - **Company logo placeholder** — dashed box at the top of the report; replace with
    your logo in Word before use.
  - **Customer Doc ID** — editable field in the report header for the customer's own
    document numbering system.

### Changed

- **`.gitignore`** — `pack/` and `docs/templates/verify_attr_report_template.html`
  added to prevent paid Validation Pack assets from being committed to the public repo.

### Web (web-local only)

- **`web/guide_doe.html`** — new section "Going further: 3-level designs and replicates":
  - `full3` design type — when to use it, 2-level vs 3-level run count comparison table,
    warning on exponential growth, command example.
  - Replicates — two reasons to add them (small effects, no error estimate), command
    example with run count comment, replicates-vs-repeats callout.
  - Section inserted between "Choosing the right design" and the PB screening example.

### Validation Pack (jr-anchored-pack)

- **`jr_pack.py`** — unified CLI entry point with subcommands: `iq-report`, `run-record`,
  `audit-trail`, `vqs`. Each delegates to the corresponding generator.
- **`jr_pack`** — bash wrapper: resolves Python, checks python-docx, works on macOS and
  Windows Git Bash. Executable; supports drag-to-terminal on macOS.
- **`install.sh`** — one-command installer: installs python-docx, copies sentinel file,
  adds `jr_pack` to PATH. Expects pack to be unzipped as `pack/` inside JR Anchored root.
  Idempotent — safe to re-run after updates.
- **`INSTALL.md`** — full installation guide: unzip-and-run instructions, drag-to-terminal
  approach, all `jr_pack` commands documented, Gatekeeper note for macOS.
- **`dist/jr-anchored-pack-20260410.zip`** — customer-ready zip: `pack/` root structure,
  generators + template + wrapper + installer only; no repo clutter.
- All four generators updated to expose a `main()` entry point callable from `jr_pack`.

---

## [2.5.0] — DoE OQ expansion and web updates (2026-04-08)

### Added

- **`oq/test_doe_suite.py`** — 13 new OQ tests expanding DoE coverage to 177 total:
  - `TestDoeDesignExtended` (TC-DOE-DES-013..018): run-count limit enforcement for
    `full2` (>256 runs) and `full3` (>243 runs), invalid centre-point and replicate
    arguments, centre-points + replicates combined (18-run total), fractional with
    centre points.
  - `TestDoeAnalyseExtended` (TC-DOE-ANA-009..015): analytically verified R² ≥ 0.99
    against known-effects data (2³ factorial, Temperature only significant), significant
    factor identification, R² range check, curvature significant / not-significant
    scenarios, constant-response degenerate case, HTML report completeness (ANOVA,
    Residuals, embedded PNG, no NaN/Inf outside base64).
- **`oq/data/`** — five new test data files: `doe_factors_9f_2level.csv`,
  `doe_factors_6f_3level.csv`, `doe_results_known_effects.csv`,
  `doe_results_no_curvature.csv`, `doe_results_constant_response.csv`.
- **`web/guide_doe.html`** — new "Example: screening six candidate factors with a
  Plackett–Burman design" section: 6-factor table, PB command, Pareto result table,
  aliasing-warning callout, two-stage strategy, tip on PB vs fractional (web-local only).

### Changed

- **`web/index.html`** — automated OQ test counter updated 465 → 478 (web-local only).
- **`docs/ignore/generate_statistics_validation_plan.py`** — UR-023 TC range updated
  to TC-DOE-DES-001..018 / TC-DOE-ANA-001..015; totals updated to 177.
- **`docs/ignore/generate_statistics_validation_report.py`** — UR-023 TC range updated
  to match; 177/177 PASS confirmed from `oq_execution_20260408T131658.txt`.

### OQ

- Full 177-test suite executed via `admin_oq` — all PASS (99.94 s).
  Evidence: `~/.jrscript/MyProject/validation/oq_execution_20260408T131658.txt`.
- `docs/ignore/statistics_validation_plan.docx` and
  `docs/ignore/statistics_validation_report.docx` regenerated with updated counts.

---

## [2.5.0] — version enforcement, scaffold --repo flag (2026-04-07)

### Fixed

- **`admin/admin_install_R`** — version mismatch error now shows
  `Required: R X.X (admin/r_version.txt)` / `Installed: R X.X`, points to
  `https://cran.r-project.org` (was incorrectly referencing `R_repo/`), adds a
  Windows uninstall hint, and notes that a deliberate version change requires
  re-running the full OQ qualification suite.
- **`admin/admin_install_Python`** — same improvements: clear Required/Installed
  lines, correct URL (`python.org/downloads/`), Windows uninstall hint, OQ re-run
  note. Removed the "multiple versions detected" assumption that was wrong when
  only a single wrong-version Python was installed.

### Added

- **`admin/admin_scaffold_R`** — new optional `--repo <module>` flag. Places the
  script in `repos/<module>/R/` and help in `repos/<module>/help/`; the wrapper
  always goes in root `wrapper/`. Creates the module folder structure
  (`repos/<module>/R/`, `help/`, `oq/`, `oq/data/`) on first use if absent.
  Without the flag, behaviour is unchanged (core `R/`, `help/`, `wrapper/`).
- **`admin/admin_scaffold_Python`** — same `--repo <module>` flag, placing help in
  `repos/<module>/help/` and creating `repos/<module>/Python/`, `oq/`, `oq/data/`.

---

## [2.5.0] — Windows multi-Python path resolution fixes (2026-04-06)

### Fixed

- **`bin/jrrun`** — Python version check and venv rebuild on Windows now derive
  the AppData path directly from the required version (e.g.
  `AppData/Local/Programs/Python/Python311/python.exe`) instead of using bare
  `python`, which resolved to whichever version appeared first in PATH. Fixes
  false "wrong version" errors when multiple Python versions are installed.
- **`admin/admin_install_Python`** — same AppData path fix for binary selection,
  auto-detect fallback (now matches required version rather than last alphabetical
  result), and error messages corrected: `.pkg` → `.exe` on Windows, Dropbox sync
  hint added, multi-version PATH issue explained.
- **`repos/msa/admin_msa_oq`, `repos/spc/admin_spc_oq`, `repos/corr/admin_corr_oq`,
  `repos/curve/admin_curve_oq`, `repos/cap/admin_cap_oq`, `repos/as/admin_as_oq`**
  — same AppData path fix for OQ venv creation.
- **`admin/admin_create_repo`** — same fix applied to the heredoc template so
  newly scaffolded `admin_*_oq` scripts are correct from the start.
- **`bin/jr_app`** — reads `admin/python_version.txt` on Windows to derive the
  AppData path rather than using bare `python`.
- **`bin/jr_helpers.R`** — `jr_log_output_hashes()` now normalises path separators
  with `normalizePath(winslash="/")` before calling `shasum`. Fixes a warning on
  Windows where `path.expand("~")` returns backslash paths that combine with
  `file.path()` forward slashes, producing mixed separators that `shasum` cannot
  resolve. Covers all 24+ R scripts that route through this helper.
- **`Python/jrc_py_hello.py`** — probes `tkinter` before committing to the TkAgg
  backend so a missing Tkinter install raises a clear `ImportError` rather than
  silently failing. `set_window_title` moved inside a try/except. `plt.show(block=True)`
  enforced. On Windows, the PNG fallback is opened automatically with `os.startfile()`.

---

## [2.5.0] — rename jrc_ss_gauge_rr → jrc_msa_grr_design (2026-04-06)

### Changed

- **`R/jrc_ss_gauge_rr.R` renamed to `R/jrc_msa_grr_design.R`** — the script
  provides Gauge R&R study design guidance (AIAG MSA), not a sample size
  calculation. The `jrc_ss_` prefix was misleading; `jrc_msa_` correctly
  reflects that this is an MSA planning tool.
- **`wrapper/jrc_ss_gauge_rr` → `wrapper/jrc_msa_grr_design`**
- **`help/jrc_ss_gauge_rr.txt` → `help/jrc_msa_grr_design.txt`**
- All internal references updated: `oq/test_ss_suite.py` (OQ class renamed to
  `TestMsaGrrDesign`), `app/jr_app.py`, web pages, and documentation generators.
- `admin/project_integrity.sha256` regenerated.

---

## [2.5.0] — jrc_verify_attr --report gated behind Validation Pack (2026-04-05)

### Changed

- **`R/jrc_verify_attr.R` — `--report` requires Validation Pack** — before
  generating the HTML verification report, the script now checks for the
  presence of `docs/templates/verify_attr_report_template.html`. If the file is
  absent, execution stops with a clear message directing the user to
  `dwylup.com` to purchase the JR Anchored Validation Pack. This replaces
  unrestricted access to the report feature.
- **`docs/templates/verify_attr_report_template.html` — removed from public
  repo** — the template has been moved to the private `jr-anchored-pack`
  repository (`r-python/templates/`). Paying customers copy it into
  `docs/templates/` in their installation to unlock `--report`.
- **`help/jrc_verify_attr.txt`** — `--report` entry updated to note that the
  feature requires the JR Anchored Validation Pack.

---

## [2.5.0] — run traceability: output hashing, per-run evidence files (2026-04-05)

### Added

- **`bin/jr_helpers.R` and `bin/jr_helpers.py`** — new helper modules providing
  `jr_log_output_hashes()`. Called at the end of every file-producing script to
  SHA-256 hash each output file and append `jrrun_output` entries to `run.log`.
  Reads `PROJECT_ID` from the environment (exported by `jrrun`).
- **Output file hashing — all 43 file-producing scripts** — every R and Python
  script that writes output files now calls `jr_log_output_hashes()` after
  writing. Covers all scripts in `R/`, `Python/`, and all `repos/*/R/` and
  `repos/*/Python/` directories. The `jrc_curve_properties.py` output functions
  were refactored to return their output paths for collection in `main()`.
- **Per-run evidence files in `jrrun`** — every `jrrun` invocation now captures
  complete terminal output (stdout + stderr) to a timestamped evidence file at
  `~/.jrscript/<PROJECT_ID>/runs/run_<YYYYMMDDTHHMMSS>_<script>.txt`. The file
  includes a header (script, arguments, timestamp, host, OS, project ID) and the
  full script output. After the run, the evidence file is SHA-256 hashed and a
  `jrrun_evidence` entry is appended to `run.log`.
- **`JR_PROJECT_ROOT` and `PROJECT_ID` exported by `jrrun`** — both variables
  are now exported as environment variables so helper scripts called from within
  R/Python scripts can locate the run log without hard-coded paths.
- **Input file hashing in `jrrun`** — `jrrun` cycles through all script
  arguments, detects which are files, and appends `jrrun_input` entries
  (filename + SHA-256) to `run.log` before the script runs.

### Changed

- **`run.log` entry chain** — each `jrrun` execution now produces up to four
  entry types in sequence: `jrrun_input` (per input file), `jrrun` (exit code),
  `jrrun_output` (per output file, written by the script), `jrrun_evidence`
  (evidence file hash, written by `jrrun`).
- **`admin/admin_scaffold_R`** — template now includes
  `source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))`
  after `.libPaths()` and a `jr_log_output_hashes(c(out_file))` placeholder.
- **`admin/admin_scaffold_Python`** — Next steps output now includes the
  `sys.path.insert` + `from jr_helpers import jr_log_output_hashes` pattern
  and guidance on where to call it.

---

## [2.5.0] — jrrun version checks (2026-04-02)

### Added

- **`bin/jrrun` — R and Python version checks** — `jrrun` now verifies the
  installed R and Python versions against `admin/r_version.txt` and
  `admin/python_version.txt` before any script runs. On a version mismatch,
  execution stops immediately with a clear message showing the required and
  installed versions and a download link (cran.r-project.org for R,
  python.org for Python). Replaces silent cryptic failure during environment
  rebuild with an actionable error message.

---

## [2.5.0] — jrc_verify_attr report flag; Ask JR; SEO (2026-04-01)

### Added

- **`jrc_verify_attr --report`** — new optional flag that generates an HTML
  verification report alongside the histogram PNG. The report auto-fills all
  analysis results (N, mean, SD, K-factor, TI limits, spec limits, PASS/FAIL
  verdict) and embeds the chart as a base64 PNG. Sections for Purpose and
  Scope, Test Conditions, Conclusion, and Approvals are provided as
  fill-in placeholders. Open in Word (File → Open, Save As .docx) or print
  to PDF from a browser. Requires the JR Anchored Validation Pack (see
  `docs/templates/verify_attr_report_template.html` note below).
- **`docs/templates/verify_attr_report_template.html`** — blank example of the
  verification report. *Moved to jr-anchored-pack in Session 17; no longer in
  the public repo.*
- **Ask JR** (`web/ask.html` + `web/ask.php`) — Claude-powered natural language
  assistant embedded in the website. Multi-turn chat, plain-text responses with
  clickable relevant links. PHP server-side proxy keeps the API key off the
  browser. Auto-routes to proxy on live site; falls back to user-provided key
  on localhost.

### Changed

- **`help/jrc_verify_attr.txt`** — documented `--report` flag; updated Usage
  line to show `[--report]`; added `--report` example.
- **Website SEO** — all six main pages updated: titles lead with keywords;
  H1 tags keyword-rich; meta descriptions expanded with FDA 21 CFR 820 and
  ISO 13485 terms; FAQ section headings converted from `<div>` to `<h2>`.
- **`web/script_guide.html`** — `jrc_verify_attr` card and result panel updated
  to document the `--report` flag.
- **`web/downloads.html`** — new Templates section with verification report
  template download card.

---

## [2.5.0] — Validation report generators for all 8 modules (2026-03-31)

### Added

- **Validation report generators for SPC and AS modules** —
  `repos/spc/docs/ignore/generate_spc_validation_report.py` (71 TCs, 27 URs)
  and `repos/as/docs/ignore/generate_as_validation_report.py` (46 TCs, 16 URs).
  Both generators read actual pytest evidence files and derive per-TC PASS/FAIL
  from them, producing a Word .docx with TC table, RTM, and summary section.
- **Statistics validation report generator extended to cover DoE** —
  `docs/ignore/generate_statistics_validation_report.py` updated to version 3.0;
  now covers Core + DoE (combined, 164 TCs, 24 URs) in addition to the 24
  community scripts. DoE prefix groups `TC-DOE-DES-` and `TC-DOE-ANA-` added.
- **`admin/admin_oq`** — OS version line added to evidence header for
  traceability.

### Changed

- All 6 module generators (`corr`, `cap`, `msa`, `curve`, `spc`, `as`) — fixed
  `_PROJECT_ROOT` path resolution (was 3 `dirname` levels, needed 4) so evidence
  file discovery works correctly from `repos/<module>/docs/ignore/`.

### Infrastructure

- **`web/` branch strategy** — `web/` content moved from `main` to a dedicated
  local-only branch `web-local`. `main` is now clean of web commits and pushes
  without triggering the pre-push hook. `web/` remains on disk and gitignored.

---

## [2.5.0] — OQ evidence quality improvement (2026-03-31)

### Changed

- **All 7 `oq/conftest.py` files** — `run()` helper now prints `CMD`, `OUT`
  (every line of script stdout+stderr), and `EXIT` after every test invocation.
  With pytest `-s`, this flows into the timestamped evidence file, making it
  possible to reconstruct exactly what the script produced for each test case.
- **All 7 `admin_*_oq` runner scripts** — default pytest args updated from
  `"-v" "--tb=short"` to `"-v" "-s" "--tb=short"` so print output is captured.
- **14 numeric test classes across all 8 modules** — added explicit
  `print(f"label: expected X ± tol, got Y")` statements before every
  tolerance-based assertion, making expected vs actual values visible in
  the evidence file for all numeric correctness checks.

---

## [2.5.0] — Web guides, home page, Windows GUI fixes (2026-03-30)

### Added

- **`web/guide_cap.html`** — Process Capability guide: Cp/Cpk/Pp/Ppk, non-normal
  percentile method, sixpack, worked example, acceptance criteria table, references.
- **`web/guide_install.html`** — Installation Guide (10 chapters): macOS/Windows
  prerequisites, SMB and Dropbox sharing, admin and user setup, upgrade workflow
  (Chapter 8), troubleshooting, uninstalling. Converted from docs/ignore/installation_guide.docx.
- **`web/doe_guide.html`** — SPC, Capability, and Installation Guide cards added
  to the Guides index page.
- **`web/sitemap.xml`** — guide_spc.html, guide_cap.html, guide_install.html added
  (priority 0.8).
- **`web/get-started.html`** — links to Installation Guide in quick-start callouts
  and team onboarding section.

### Changed

- **`web/index.html`** — home page revised to lead with module value rather than
  infrastructure. New tagline, hero heading, "What you can do with it" section with
  four module cards (DoE, MSA, SPC, Capability), "Why validated?" compliance badges,
  stats bar expanded to 5 items (added "8 Modules").
- **`web/style.css`** — stats bar grid widened from 4 to 5 columns.

### Fixed

- **`JR Anchored.bat`** — hardcoded `C:\Program Files\Git\bin\bash.exe` instead
  of bare `bash` (not on Windows system PATH); added existence check with
  user-friendly error message if Git for Windows is not installed.
- **`app/jr_app.py`** — Windows integrity check always failed because:
  (1) `BASH_PREFIX = ["bash"]` — bare bash not in PATH for Python subprocess;
  (2) `JRRUN` was a Windows backslash path — `bash dirname "$0"` returned `.`,
  making `SCRIPT_DIR` and `PROJECT_ROOT` resolve to the working directory.
  Fixed by adding `_to_posix()` (converts `C:\...\jrrun` → `/c/.../jrrun`) and
  using `--login` flag so bash sources `.bash_profile` for the correct PATH.
  Both fixes pushed to `origin/main` via cherry-pick (commits 03a0e45, 50c8693).

---

## [2.5.0] — Phase 9 OQ: Community Script Numeric Assertions (v2.6.0 target)

### Added — High-risk community script numeric OQ coverage

- **25 new numeric OQ test cases** for the 9 community scripts that directly
  affect design-verification conclusions under 21 CFR 820.70(i) / ISO 13485.
  Each asserts a computed value against an independently derived result (closed-
  form formula or published K-factor table), covering the calculation paths that
  produce binding ✅/❌ verdicts or required sample sizes.
- **New analytical dataset** `oq/data/verify_attr_known.csv` — 30-row dataset
  with exact mean = 10.0000 and sd = 1.0000 by construction (28 × 10.0000 plus
  symmetric outliers ±3.8079), symmetric so skewness = 0 and the normal path is
  exercised without Box-Cox.
- `extract_float()` and `extract_table_n()` helpers added to `oq/conftest.py`
  for regex-based extraction of labelled values and table rows.
- Total OQ test count: **440 → 465** (25 new numeric assertions).
- `docs/validation_improvement_plan.md` — Phase 9 OQ plan documenting tier
  assignments, risk rationale, and deferred non-normal tests for a later phase.

### Test breakdown

| Script | New TCs | Key metrics validated |
|--------|---------|----------------------|
| jrc_ss_discrete | TC-DISC-006..009 (4) | n via chi-squared exact formula |
| jrc_ss_discrete_ci | TC-DISCICI-005..006 (2) | Clopper-Pearson exact proportion |
| jrc_ss_attr | TC-ATTR-008 (1) | required n range for known K-factor |
| jrc_ss_attr_check | TC-ATTRCK-004..005 (2) | pass/fail boundary around K1(30,0.95,0.95) |
| jrc_ss_attr_ci | TC-ATTRCI-004 (1) | achieved proportion for k_sample=3.0 |
| jrc_ss_sigma | TC-SIGMA-005..007 (3) | n via normal sample size formula |
| jrc_ss_fatigue | TC-FAT-006..007 (2) | cross-script consistency + p_eff reduction |
| jrc_ss_paired | TC-PAIRED-006..007 (2) | 1-sided vs 2-sided n difference |
| jrc_ss_equivalence | TC-EQUIV-005..006 (2) | TOST n = 1-sided paired n |
| jrc_verify_attr | TC-VER-009..011 (3) | K-factor numeric + ✅/❌ verdict boundary |

---

## [2.5.0] — Numerical OQ Enhancement (v2.5.0 target)

### Added — Numeric correctness assertions across all modules

- **33 new tolerance-based OQ test cases** across 6 modules: Cap, MSA, SPC,
  Corr, AS, and Curve. Each asserts a computed numeric value against an
  independently derived expected result (hand calculation or Python reference
  implementation), closing the gap between behavioural testing and calculation
  correctness under 21 CFR 820.70(i) / ISO 13485 §7.5.6.
- Total OQ test count: **407 → 440** (33 new numeric assertions).
- New `extract_float()` helper added to all module `conftest.py` files for
  consistent regex-based value extraction from script output.
- Two new analytical datasets:
  - `repos/cap/oq/data/cap_cpk_1p000.csv` — centred, Cpk = Cp = 1.000 (exact)
  - `repos/cap/oq/data/cap_cpk_0p667.csv` — offset, Cpk = 0.667, Cp = 1.000 (exact)
  - `repos/corr/oq/data/corr_exact_linear.csv` — y = 2x+1, r = slope = 1.000 (exact)
- `docs/validation_improvement_plan.md` — execution guide for this enhancement,
  documenting all TCs, expected values, tolerances, and derivations.
- Fixed pre-existing syntax error in `repos/msa/oq/test_msa_linearity_bias.py`
  (f-string with nested double quotes, line 178).

### Module breakdown

| Module | New TCs | Key metrics validated |
|--------|---------|----------------------|
| Cap    | TC-CAP-N-014..018 (5) | Cpk, Cp, Ppk |
| MSA    | TC-MSA-GRR-011..013, T1-012..013 (5) | %GRR, ndc, Cg, Cgk |
| SPC    | TC-SPC-IMR-012..015, XBR-013..016, XBS-012..015, P-012..013, C-011..012 (16) | UCL, LCL, centrelines |
| Corr   | TC-CORR-P-012..013, R-012..014 (5) | r, slope, intercept, R² |
| AS     | TC-AS-ATTR-012..013 (2) | Pa(AQL), Pa(RQL) |
| Curve  | TC-CURVE-N-001..003 (3) | AUC, slope, y_at_x |

---

## [2.4.0] — 2026-03-26

### Added — `jrc_curve_properties` further enhancements

- **Per-phase `max_y`, `min_y`, `max_x`, `min_x`, `auc`** — these properties
  can now be specified directly in `[phase.NAME]` sections to compute them for
  multiple phases in a single run. Results appear in a `Phase` section in the
  output. Supersedes the `max_y_phase` / `min_y_phase` pattern in `[global]`.
- **`max_x` / `min_x` in `[global]`** — maximum and minimum X over the full
  dataset (or a named phase via `auc.phase`) reported alongside the Y position.
- **Transform section in results output** — when `[transform]` is active,
  `y_scale` and `y_offset_x` values are recorded in a `Transform` section in
  the results table and results file, making the output self-contained.
- **Dot notation for modifier keys** — config modifier keys now use dot
  separators instead of underscores: `secant.x1`, `overall.phase`,
  `inflections_1.phase`, `yield_1.slope`, `d2y.phase`, etc. This unambiguously
  distinguishes feature names from their modifiers. All sample configs updated.
- **Config pre-validation** — `validate_config()` runs before any data loading
  and reports all errors in one pass (no need to fix-and-rerun):
  - Duplicate keys and duplicate sections (previously caused Python tracebacks)
  - Unknown section names
  - Unknown keys inside known sections (catches typos and old-style underscore keys)
  - Non-numeric values where numbers are required
  - Invalid enum values (`search`, `delimiter`, `method`, `mode`)
  - Missing required keys (`x_start`/`x_end` in phases, `file`/`x_col`/`y_col` in `[data]`)
  - `[debug] d2y = yes` without `d2y.phase`
  - Phase name references to undefined phases (warning, not error)
- **Circle test dataset** — `sample_data/circle.csv` (150-point parametric
  circle) and `sample_data/circle.cfg` added for testing ascending/descending
  phase separation.
- **OQ test suite** — `repos/curve/oq/` with 28 automated pytest tests across
  8 test classes (validation, global, phase, slope, query, transform,
  transitions, output files). All 28/28 PASS. Test data: `linear.csv`,
  `sine.csv`, `triangle.csv` plus 14 config fixtures.
- **`admin_curve_oq`** — evidence runner producing timestamped
  `curve_oq_execution_<timestamp>.txt` in `~/.jrscript/<PROJECT_ID>/validation/`.
- **Validation documents** — `repos/curve/docs/ignore/` generators for
  `curve_validation_plan.docx` (JR-VP-CURVE-001, 18 URs, 28 TCs),
  `curve_validation_report.docx` (JR-VR-CURVE-001, 28/28 PASS),
  and `curve_user_manual.docx`.
- **GUI** — "Curve Analysis" module added to `app/jr_app.py` with `curve_cfg`
  param type; user selects a sample `.cfg` from `repos/curve/sample_data/`.
- **Web** — `modules.html` (Curve section), `script_guide.html`
  (`jrc_curve_properties` card + category + tree leaf + `EXAMPLES` entry
  with four text sections explaining output structure, raw vs. smoothed
  tagging, and the PDF plot; `GUI_NAMES` entry; modal updated to hide
  image area for text-only examples), `downloads.html` (Curve Module
  section with 3 download cards), `references.html` (Curve section with
  Savitzky-Golay 1964, Numerical Recipes, and ISO 7500-1 references),
  `index.html` (46 scripts / 407 OQ tests). All page footers updated to
  v2.4.0.

---

## [2.3.0] — 2026-03-25

### Added — `jrc_curve_properties` enhancements

- **Per-phase smoothing** — `[phase.NAME]` sections now accept `smooth_method`
  and `smooth_span` keys that override the global `[smoothing]` settings for
  derivative calculations (slope, inflections, yield) within that phase only.
- **Direct second-derivative** — inflection detection now uses
  `savgol_filter(deriv=2, delta=mean_dx)` directly instead of double-gradient,
  eliminating boundary amplification artefacts.
- **Inflection boundary trim** — 2 % of phase length trimmed from each end
  before inflection search, suppressing ghost zero-crossings at phase edges
  without cutting real inflections.
- **`[debug]` section** — `d2y = yes` writes a diagnostic CSV (`<cfg>_debug_d2y_<phase>.csv`)
  containing `x, y_raw, y_smooth, d2y, trimmed` for the named phase; use to
  tune `smooth_span` for inflection detection.
- **Smooth-span guidance** in help file — explains the noise/shift trade-off,
  recommends starting at 0.30, and describes a stability check (±0.10 test).
- **Multiple inflection/yield blocks** via numbered suffixes (`inflections_1`,
  `inflections_2`, ...; `yield_1_slope`, `yield_2_slope`, ...) — avoids
  duplicate-key errors in configparser; bare form and numbered form may coexist.
- **`[transform]` section** — `y_scale` multiplies every Y value (applied first);
  `y_offset_x` subtracts the Y at a reference X from every value (applied after
  scale). Both update the plot Y-axis automatically.
- **Relative X queries** — `y_at_rel_x_N` queries Y at `x_ref × (1 + frac)`;
  `_frac` is signed (positive or negative offset).
- **`_show` flag** — all plot markers (query points, yield points) are hidden by
  default; add `_show = yes` to opt in. Applies to `y_at_x_N`, `y_at_rel_x_N`,
  `yield_slope`, `yield_N_slope`.
- **Phase arm disambiguation** — `[phase.NAME]` supports `search = ascending |
  descending` to restrict the boundary search to one arm of a peak/valley curve,
  and `after_phase` to restrict the search zone to rows after a prior phase ends.
- **Tangent line length normalisation** — tangent lines at inflection points now
  have equal Euclidean length regardless of slope, via `hw = length / sqrt(1 + s²)`.
- **White halo on markers** — query and yield markers are drawn twice (larger
  white, then coloured) to remain visible on any curve colour.

---

## [2.2.1] — 2026-03-24

### Fixed

- **SPC example data** — replaced all three SPC sample CSVs with more
  instructive data:
  - `p_sample.csv` — all lots were equal size (n=100), producing flat
    control limits that contradicted the documentation describing step
    lines. Replaced with variable lot sizes (n=50–200) so the example
    demonstrates the varying UCL/LCL behaviour.
  - `c_sample.csv` — all 15 subgroups were in control with no OOC signal.
    Replaced with 20 subgroups including a clear Rule 1 violation at
    subgroup 13 (14 defects, UCL = 12.45).
  - `xbar_r_sample.csv` and `xbar_s_sample.csv` — uniform within-subgroup
    spacing produced identical ranges/SDs across all subgroups (flat R/S
    charts). Replaced with realistic variation and meaningful OOC signals.
- **Script Guide** — C-chart EXAMPLES text clarified that flat UCL/LCL
  lines are correct for the C-chart (equal inspection area assumption),
  contrasting with the P-chart where varying limits are expected.

### Added

- `bin/jr_kill_app` — stops the Streamlit GUI when the browser tab is
  closed without pressing Stop. Uses `lsof` on macOS/Linux and `netstat`
  + `taskkill` on Windows to find and kill the process on port 8501.

---

## [2.2.0] — 2026-03-24

### Added

- **Process Capability module** (`repos/cap/`) — three new R scripts for
  process capability and performance analysis:
  - `jrc_cap_normal` — Cp, Cpk, Pp, Ppk, Cpm (Taguchi) for normally
    distributed data. Within-subgroup sigma estimated via moving range
    (MR-bar / d2). Reports sigma level and estimated PPM out-of-specification.
    Saves a histogram with normal curve overlay and spec limit lines to
    `~/Downloads/`.
  - `jrc_cap_nonnormal` — Pp and Ppk for non-normally distributed data
    using the percentile method (ISO 22514-2 / AIAG SPC manual). Process
    spread estimated from P0.135 and P99.865 sample quantiles — no
    distributional assumption. Shapiro-Wilk advisory if data appears normal.
    Saves a histogram with KDE overlay to `~/Downloads/`.
  - `jrc_cap_sixpack` — Six-panel process capability report: Individuals
    chart (with spec limits overlaid), Moving Range chart, capability
    histogram with normal curve, normal probability plot (Q-Q), numerical
    summary (Cp, Cpk, Cpm, Pp, Ppk, sigma level, PPM), and a colour-coded
    verdict panel (green / amber / red). Saves a 3600×2400 px PNG to
    `~/Downloads/` — suitable for direct inclusion in a validation report.
- **OQ** — 40 automated tests across 3 test files, all passing
  (JR-VP-CAP-001 v1.0). OQ runner: `repos/cap/admin_cap_oq`.
- **GUI** — Process Capability section added to `app/jr_app.py` using the
  existing `capability` param_type.

### Changed

- `web/index.html` — updated stat counters to 45 validated scripts and
  379 automated OQ tests.
- `SCRIPT_IDEAS.md` — Process Capability section added.

---

## [2.1.1] — 2026-03-23

### Fixed

- **`jrc_ss_discrete_ci` documentation** — help file and script_guide.html
  incorrectly described the first argument as `proportion` and the output as
  "confidence level achieved". The R script itself was correct (takes
  `confidence`, returns proportion via Clopper-Pearson). Fixed:
  `help/jrc_ss_discrete_ci.txt`, `web/script_guide.html` (description,
  when_to_use, syntax), and `app/jr_app.py` (GUI widget label and command
  argument order).

### Added

- **Streamlit GUI** (`app/jr_app.py`, `bin/jr_app`) — graphical interface
  covering all 41 community scripts across 8 modules. Script filenames shown
  below each title for cross-reference with the CLI. Streamlit toolbar hidden
  via `--client.toolbarMode minimal`.
- **macOS app bundle** (`JR Anchored.app`) — proper `.app` bundle with a
  custom anchor emoji icon (rendered via Swift/AppKit, packaged as `.icns`).
  Sits in the Dock with the correct icon; uses `osascript` to open a Terminal
  window running `bin/jr_app`.
- **Windows launchers** — `JR Anchored.bat` (calls bash to run `bin/jr_app`),
  `JR Anchored.ico` (multi-resolution anchor icon), and
  `Create JR Anchored Shortcut.ps1` (creates a Desktop shortcut with custom
  icon for taskbar pinning).
- **`web/gui.html`** — new website page documenting the GUI: requirements,
  macOS and Windows launch options, usage walkthrough, stopping, and
  troubleshooting. Added to site nav on all pages and to `sitemap.xml`.

### Changed

- **Canonical URLs** — all 9 web pages now carry their own
  `<link rel="canonical">` URL instead of pointing to the homepage.
- **Script Guide** — GUI display names cross-referenced on both tabs (All
  Scripts and Find a Script) so users can relate CLI names to GUI names.

---

## [2.1.0] — 2026-03-21

### Added

- **Corr module** (`repos/corr/`) — four new R scripts for correlation and
  method comparison analysis:
  - `jrc_corr_pearson` — Pearson product-moment correlation with Fisher
    z-transformed CI and two-sided hypothesis test.
  - `jrc_corr_spearman` — Spearman rank correlation; distribution-free,
    valid for non-normal data and ordinal measurements.
  - `jrc_corr_regression` — OLS simple linear regression with R², adjusted
    R², F-statistic, residual SE, coefficient CIs, and a two-panel residuals
    diagnostic plot.
  - `jrc_corr_passing_bablok` — Passing-Bablok method comparison regression
    (native implementation, no `mcr` package required). Tests slope = 1 and
    intercept = 0; Cusum linearity test included.
- OQ test suite: 45 automated test cases (TC-CORR-P-001..011,
  TC-CORR-S-001..011, TC-CORR-R-001..011, TC-CORR-PB-001..012) — 45/45 PASS.
- Validation plan JR-VP-CORR-001 v1.0 (18 URs, 45 TCs, RTM).
- Validation report JR-VR-CORR-001 v1.0 (45/45 PASS, 0 deviations).
- User manual `corr_user_manual.pdf` — routing table, per-script reference,
  interpretation guidance for r/ρ/R²/P-B, recommended workflows, glossary.
- Web: Corr module added to `modules.html`, `references.html`,
  `script_guide.html` (SCRIPTS, CATEGORIES, TREE), and `downloads.html`.

---

## [2.0.1] — 2026-03-20

### Fixed

- Mobile navigation — "Home" was clipped on narrow phone screens after the
  References link was added as a 7th nav item. `flex-wrap: wrap` and
  `justify-content: flex-start` applied at ≤480 px so all items remain
  visible.

---

## [2.0.0] — 2026-03-20

### Added

- **Windows support** — full cross-platform compatibility with Windows 10/11
  via Git Bash. All shell scripts ported from zsh to bash. Tested end-to-end
  on Windows: `admin_install_R --rebuild`, `admin_install_Python`,
  `admin_validate`, `jrrun`, and the complete 142-test OQ suite.
- `bin/jr_platform.sh` — shared OS/path helper library sourced by all scripts.
  Provides `jr_os()`, `jr_r_platform_dir()`, `jr_venv_python/pip/pytest()`,
  `jr_shell_rc()`, `jr_sed_inplace()`, `jr_os_version()`.
- `setup_jr_path.sh` — replaces `setup_jr_path.zsh`; writes PATH block to
  `~/.zprofile` (macOS) or `~/.bash_profile` (Windows Git Bash).
- **References page** — `web/references.html` listing ASTM/ISO/ANSI/AIAG
  standards and literature per module (Core, DoE, MSA, SPC, AS). Reachable
  from a button next to each module's browse button and from the site nav.

### Changed

- All 49 wrapper scripts and all scripts in `bin/` and `admin/` converted from
  zsh to bash (shebang `#!/bin/bash`).
- `bin/jrrun` — exports `JR_R_PLATFORM_DIR`; converts Git Bash paths to
  Windows-native paths via `cygpath -w` before passing to R; exports
  `PYTHONUTF8=1` in Python branch.
- `admin/admin_validate` and `admin/admin_validate_R_env` — export
  `JR_R_PLATFORM_DIR`; `admin_validate_R_env` now sources `jr_platform.sh`.
- `admin/admin_generate_validate_R` and `admin/admin_scaffold_R` — emit
  `Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos")` instead of hardcoded
  `"macos"` in renv library path.
- All OQ `conftest.py` files — `BASH_PREFIX = ["bash"]` on Windows; all
  `subprocess.run()` calls use `encoding="utf-8"` instead of `text=True`.

### Fixed

- Windows R install: renv download URL, `file:///` URL construction, Windows
  binary package download via `download_binaries_manually()`.
- Windows Python: venv `Scripts/` vs `bin/` path, `Lib/site-packages` path,
  `python` vs `python3.11` executable name.
- `jr_shell_rc()` returns `~/.bash_profile` on Windows (Git Bash login shell).
- `bin/jr_versions` — `declare -A` replaced with awk lookup for bash 3.2
  compatibility on macOS.
- Clear error message when script name not found in `jrrun` search paths.

## [1.9.0] — 2026-03-19

### Added

**Acceptance Sampling Module — `repos/as/`**

Four new R scripts for acceptance sampling plan design and evaluation,
self-contained under `repos/as/` with shared infrastructure (wrappers,
help files, sample data, OQ test suite).

- `jrc_as_attributes` — Design an attributes sampling plan. Finds both
  a single-sampling plan (n, c) and a double-sampling plan (n1, c1, n2, c2)
  satisfying user-specified AQL, RQL, producer's risk α, and consumer's risk β.
  Uses hypergeometric distribution when n/N > 0.10, binomial otherwise.
  Outputs OC curves for both plans and Average Sample Number (ASN) comparison.
  Saves dual-plan OC curve PNG to `~/Downloads/`.
- `jrc_as_variables` — Design a variables sampling plan using the k-method
  with unknown σ (ANSI/ASQ Z1.9 approach). Supports one-sided (`--sides 1`,
  default) and two-sided (`--sides 2`) specification limits. Reports efficiency
  gain versus an equivalent attributes plan. Saves OC curve PNG.
- `jrc_as_oc_curve` — Plot the Operating Characteristic (OC) curve for any
  user-specified (n, c) attributes plan. Supports finite lot correction via
  `--lot-size` and optional AQL/RQL annotations.
- `jrc_as_evaluate` — Apply a plan to actual lot data and produce an
  ACCEPT/REJECT verdict. Attributes mode: reads a CSV with `id, result`
  (0=conforming, 1=defective) and compares defective count to acceptance number c.
  Variables mode: reads a CSV with `id, value` and compares quality index
  Q = (x̄ − spec limit)/s to acceptability constant k for each applicable limit.
  Saves a summary PNG to `~/Downloads/`.

All scripts use base R distributions (`pbinom`, `phyper`, `pt`, `qt`) and
ggplot2 — no new package dependencies. No environment revalidation required.

OQ: 44 automated tests across 4 test files.
Validation plan: JR-VP-AS-001. Validation report: JR-VR-AS-001.

**Home page redesign (`web/index.html`, `web/style.css`)**

Replaced the plain text-only home page with a visually engaging layout
suited to the medical device development audience.

- Full-width dark navy hero section with two-column layout: marketing
  copy left, live terminal example right (shows `jrc_msa_gauge_rr`
  Gauge R&R output with ANOVA variance table and ndc/%GRR verdict)
- Stats bar: 34 validated scripts · 224 automated OQ tests · SHA-256 ·
  FDA/ISO compliance
- SVG icons on all four feature cards (lock, monitor+check, shield,
  clipboard+check)
- Responsive: hero stacks to single column on mobile; terminal widget
  visible at all screen widths
- CSS cache-busting bumped to `?v=3` across all five HTML pages

**Example output modal — all scripts**

Extended the example output modal (introduced in v1.8.0 for SPC and MSA)
to cover all 24 community scripts. Every script card in
`web/script_guide.html` now shows a "See example output →" button.

- 23 terminal screenshot PNGs generated with Pillow (Menlo font, dark
  navy terminal style, colour-coded ✅/❌/⚠️ output lines); content
  captured from live `jrrun` runs on OQ test data
- 3 visual chart PNGs for scripts that produce image output:
  `jrc_bland_altman`, `jrc_weibull`, `jrc_verify_attr`
- All 36 PNGs stored in `web/examples/`
- `web/make_terminal_pngs.py` — Pillow-based generator script for
  regenerating terminal screenshot PNGs; run `python3 web/make_terminal_pngs.py`
  from the repo root (requires `pip3 install pillow`)

### Fixed

- `web/faq.html`: "How can I arrange shared folders?" answer trimmed to
  two bullet sections (Dropbox™ with link, and SMB); alternatives
  paragraph (Syncthing, Nextcloud, Resilio Sync, iCloud Drive) removed
- `web/style.css`: `ul`/`li` styles added inside `.faq-answer` (left-border
  accent, block `strong` labels, no list markers)
- `.gitignore`: added `repos/spc/docs/ignore/` (was missing alongside the
  existing `repos/msa/docs/ignore/` entry)

---

## [1.8.0] — 2026-03-18

### Added

**SPC Module — `repos/spc/`**

Five new R scripts for Statistical Process Control, self-contained under
`repos/spc/` with shared infrastructure (wrappers, help files, sample data,
OQ test suite). All scripts implement all 8 Western Electric rules, save a
PNG chart to `~/Downloads/`, and include bypass protection.

- `jrc_spc_imr` — Individuals and Moving Range chart for individual
  continuous measurements. Uses d2=1.128, D4=3.267. Supports optional
  `--ucl`/`--lcl` to apply pre-established limits in monitoring phase.
  Two-panel PNG (Individuals chart + MR chart).
- `jrc_spc_xbar_r` — X-bar and R chart for subgrouped data with n = 2–10.
  Tabulated A2, D3, D4 constants embedded; rejects n > 10 with a suggestion
  to use X-bar/S. Supports optional `--ucl`/`--lcl`. Two-panel PNG.
- `jrc_spc_xbar_s` — X-bar and S chart for subgrouped data with any n ≥ 2.
  Analytical c4(n) using the gamma function; computes A3, B3, B4 dynamically.
  Supports optional `--ucl`/`--lcl`. Two-panel PNG.
- `jrc_spc_p` — P-chart (proportion defective) for attribute data with
  variable subgroup sizes. Per-subgroup UCL/LCL; Western Electric rules
  applied to standardised z-values. Step-line control limits in PNG.
- `jrc_spc_c` — C-chart (count of defects per unit) for constant-area
  inspection. UCL/LCL = c-bar ± 3√c-bar; sigma zone lines in PNG.

**SPC OQ test suite**
- `repos/spc/oq/` — 55 pytest-based tests across 5 test files (10–12 per
  script), covering happy paths, known-data numerical checks, error handling,
  and bypass protection
- `repos/spc/admin_spc_oq` — SPC OQ runner; reuses the `${PROJECT_ID}_oq`
  venv, writes timestamped evidence to `~/.jrscript/<PROJECT_ID>/validation/`

**SPC validation and user documentation**
- `repos/spc/docs/ignore/generate_spc_validation_plan.py` — python-docx
  generator for JR-VP-SPC-001 v1.0 (27 URs, 55 test cases, RTM)
- `repos/spc/docs/ignore/generate_spc_validation_report.py` — python-docx
  generator for JR-VR-SPC-001 v1.0 (55/55 PASS, RTM, OQ conclusion)
- `repos/spc/docs/ignore/generate_spc_user_manual.py` — python-docx generator
  for SPC User Guide (6 sections: chart selection, quick-reference table,
  results interpretation, per-script reference, data preparation, WE rules)
- `repos/spc/docs/spc_validation_plan.pdf`, `spc_validation_report.pdf`,
  `spc_user_manual.pdf` — generated PDFs

**Web interface**
- `web/script_guide.html`: 5 new SPC script entries; new "Statistical Process
  Control (SPC)" category in All Scripts tab; new "Monitor a process (SPC
  control chart)" root branch in the Find-a-script questionnaire with `spc`,
  `spc_individual`, and `spc_subgroup` decision-tree nodes
- `web/downloads.html`: SPC Module Validation Documents section (plan, report,
  user manual); footer version bumped to v1.8.0 on all five pages

### Fixed

- `admin/admin_install_R`: Intel macOS platform path corrected from
  `big-sur` to `big-sur-x86_64` — CRAN binary URL was resolving to a
  non-existent path, causing the binary download step to silently fail
- `admin/R/admin_R_install.R`: `packageVersion("renv")` called in BUILD mode
  before renv was installed on systems without it in the system library
  (Intel Mac first run); fixed by installing renv from CRAN before querying
  its version

---

## [1.7.0] — 2026-03-18

### Added

**MSA Module — `repos/msa/`**

Five new R scripts for Measurement System Analysis, self-contained under
`repos/msa/` with shared infrastructure (wrappers, help files, sample data,
OQ test suite, validation documents, user manual).

- `jrc_msa_gauge_rr` — Standard Gauge R&R (crossed design, two-way ANOVA).
  Computes repeatability, reproducibility, %GRR, ndc, variance components, and
  AIAG verdict. Four-panel PNG (components of variation, by-part, by-operator,
  interaction plot).
- `jrc_msa_nested_grr` — Nested Gauge R&R for destructive/semi-destructive
  measurement systems. Each operator receives their own specimens (no crossing).
  One-way nested ANOVA; estimates EV, AV, part-within-operator variation, %GRR.
  Two-panel PNG.
- `jrc_msa_linearity_bias` — Linearity and Bias study. Regresses observed bias
  against reference value; reports slope, intercept, R², %Linearity, and per-part
  bias with significance flags. Two-panel PNG.
- `jrc_msa_type1` — Type 1 Gauge Study (Cg/Cgk). Single reference part measured
  repeatedly; reports Cg, Cgk, bias, and t-test for bias significance. Run chart
  and histogram PNG.
- `jrc_msa_attribute` — Attribute Agreement Analysis. Computes within-appraiser
  % agreement and Cohen's Kappa, between-appraiser Fleiss' Kappa, and optionally
  each appraiser's Kappa vs a reference standard. Two-panel PNG.

**MSA OQ test suite**
- `repos/msa/oq/` — 53 pytest-based tests across 5 test files (10–11 per script),
  covering happy paths, known-data numerical checks, error handling, and bypass
  protection
- `repos/msa/admin_msa_oq` — MSA OQ runner; reuses the `${PROJECT_ID}_oq` venv,
  writes timestamped evidence to `~/.jrscript/<PROJECT_ID>/validation/`

**MSA validation documents** (`repos/msa/docs/`)
- `msa_validation_plan.docx` (JR-VP-MSA-001 v1.0) — OQ validation plan covering
  24 user requirements and 53 test cases with full RTM
- `msa_validation_report.docx` (JR-VR-MSA-001 v1.0) — OQ validation report;
  53/53 tests passed, 0 deviations
- `msa_user_manual.docx` — engineer-facing guide covering all 5 MSA scripts with
  recommended study workflow (Type 1 → Gauge R&R → Linearity/Bias), argument
  tables, worked examples, and interpretation guidance for %GRR, Cg/Cgk, and Kappa

**Web interface**
- `web/script_guide.html`: 5 new MSA script entries; new "Measurement System
  Analysis (MSA)" category in All Scripts tab; new "Qualify a measurement system
  (MSA)" root branch in the Find-a-script questionnaire with `msa` and
  `msa_continuous` decision-tree nodes
- `web/downloads.html`: MSA User Manual card (Manuals section); new MSA Module
  Validation Documents section with plan and report cards

**Infrastructure**
- `bin/jrrun`: bare filename resolution extended to search `repos/*/R/` and
  `repos/*/Python/` after the core `R/` and `Python/` directories; help lookup
  extended to `repos/*/help/`
- `setup_jr_path.zsh`: adds all `repos/*/wrapper/` directories to PATH
  dynamically via a `for` loop written to `~/.zprofile`
- `repos/msa/sample_data/` — sample CSV files for each of the 5 MSA scripts

---

## [1.6.1] — 2026-03-18

### Changed
- All web pages: footer version updated to v1.6.1.

### Removed
- `bin/jrwhich` — obsolete script that referenced `jr_animate` and `jr_static` (removed in v1.4.0) and listed none of the community scripts. Superseded by the website Script Guide.

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
