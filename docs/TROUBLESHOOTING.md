# Troubleshooting — JR Validated Environment

This document covers the most common issues encountered when installing,
running, or validating the JR environment. Each entry describes the symptom,
likely cause, and resolution steps.

---

## Table of Contents

1. [Dropbox not synced](#1-dropbox-not-synced)
2. [Wrong R or Python version installed](#2-wrong-r-or-python-version-installed)
3. [renv library empty after rebuild](#3-renv-library-empty-after-rebuild)
4. [Integrity check failing](#4-integrity-check-failing)
5. [PATH not set up correctly](#5-path-not-set-up-correctly)
6. [Packages loading from system library instead of renv](#6-packages-loading-from-system-library-instead-of-renv)
7. [pip install failing during venv rebuild](#7-pip-install-failing-during-venv-rebuild)
8. [RENV_PATHS_ROOT not set error](#8-renv_paths_root-not-set-error)
9. [Rscript not found](#9-rscript-not-found)
10. [project_id.txt not found](#10-project_idtxt-not-found)
11. [validate_R_env.R not found](#11-validate_r_envr-not-found)
12. [Two copies of JR Anchored installed on the same machine](#12-two-copies-of-jr-anchored-installed-on-the-same-machine)
13. [Package version mismatch after CRAN binary update](#13-package-version-mismatch-after-cran-binary-update)
14. [GUI Settings page cannot find jr_pack_config.json](#14-gui-settings-page-cannot-find-jr_pack_configjson)

---

## 1. Dropbox not synced

**Symptom**

`admin_install_R` or `admin_install_Python` fails with a message like:

```
❌ Local repo not found at: /Users/.../R_repo/my-cran-repo
   Run admin_install_R --rebuild first to create it.
```

**Cause**

The local package repository lives in Dropbox and has not finished syncing
to this machine, or Dropbox is not running.

**Resolution**

1. Open Dropbox and confirm it is running and signed in.
2. Navigate to the `R_repo/` or `Python_repo/` folder in Finder and wait
   for the sync indicator to show a green tick on all files.
3. If the folder is missing entirely, check that the Dropbox account is the
   correct one and that the folder has been shared with you.
4. Run `admin_install_R` or `admin_install_Python` again once sync is complete.

---

## 2. Wrong R or Python version installed

**Symptom — R**

```
❌ Wrong R version installed.
   Required : R 4.6  (admin/r_version.txt)
   Installed: R 4.5

   Download the validated R 4.6 from:
   https://www.dwylup.com/guide_install.html
```

**Symptom — Python**

```
❌ Wrong Python version installed.
   Required : Python 3.11.9  (admin/python_version.txt)
   Installed: Python 3.12.0

   Download the validated Python 3.11.9 from:
   https://www.dwylup.com/guide_install.html
```

**Cause**

The system R or Python version does not match the version pinned in
`admin/r_version.txt` or `admin/python_version.txt`.

**Resolution**

1. Download the pinned installer from the JR installer store:

   | | |
   |---|---|
   | R, macOS (Apple Silicon) | https://www.dwylup.com/packages/installers/R-4.6.0-arm64.pkg |
   | R, Windows | https://www.dwylup.com/packages/installers/R-4.6.0-win.exe |
   | Python, macOS | https://www.dwylup.com/packages/installers/python-3.11.9-macos11.pkg |
   | Python, Windows | https://www.dwylup.com/packages/installers/python-3.11.9-amd64.exe |

   These are the exact versions the OQ suite was run against, kept available
   after CRAN and python.org move on. CRAN removes superseded R installers from
   its main directory — R 4.6.0 has already moved to `base/old/` on Windows.

2. Install it. Multiple R and Python versions coexist happily; installing the
   pinned one will not remove your existing version.
3. Re-run the admin install script.

**Note on patch versions.** The pin in `admin/r_version.txt` is *minor*-level
(`4.6`), so R 4.6.1 also satisfies it and there is no need to downgrade if you
already have it — differences between patch releases are minimal by design. If
you want certainty for a particular deployment, run the full OQ suite yourself
on that machine.

---

## 3. renv library empty after rebuild

**Symptom**

`admin_install_R` completes without errors but user wrappers immediately
trigger a rebuild, or `jr_versions` shows packages as NOT INSTALLED.

**Cause**

The renv library path contains an empty or partial installation. This can
happen if a previous install was interrupted, or if the library path has
changed (e.g. after a PROJECT_ID change).

**Resolution**

1. Check the renv library path:
```zsh
ls ~/.renv/MyProject/renv/library/
```
2. If the folder is missing or empty, delete it and re-run:
```zsh
rm -rf ~/.renv/MyProject
admin_install_R
```
3. If the issue persists after a clean install, run with `--rebuild` to
   re-download all packages from the local repo:
```zsh
admin_install_R --rebuild
```
   Note: `--rebuild` re-downloads from the local Dropbox repo only — it does
   not access the internet unless `BUILD_REPO=true` is also set.

---

## 4. Integrity check failing

**Symptom**

```
❌ PROJECT INTEGRITY CHECK FAILED
   Modified or missing files:
   /Users/.../R/calctltf.R
```

**Cause**

One or more project files have been modified since the integrity hash was
last generated. This may be intentional (a file was legitimately updated)
or unintentional (accidental edit, file corruption, or sync conflict).

**Resolution**

1. Review the listed files carefully. If the change was unintentional,
   restore the file from git:
```zsh
git checkout R/calctltf.R
```
2. If the change was intentional and reviewed, regenerate the integrity
   file as admin:
```zsh
admin_create_hash
```
3. If multiple files are listed and the cause is unclear, check git status:
```zsh
git status
git diff
```
4. Never regenerate the integrity file without reviewing and approving all
   listed changes — this is a Quality event.

---

## 5. PATH not set up correctly

**Symptom**

```
zsh: command not found: jrrun
zsh: command not found: jr_versions
```

**Cause**

`setup_jr_path.sh` has not been run, or the Terminal window was not
reopened after running it.

**Resolution**

1. Run the path setup script from the project root:
```zsh
./setup_jr_path.sh
```
2. Open a **new Terminal window** — PATH changes do not apply to the current
   window.
3. Verify the PATH entry was added:
```zsh
grep "JR Validated Environment" ~/.zprofile
```
   You should see:
```
# JR Validated Environment — begin
export PATH="$PATH:/path/to/your/project"
# JR Validated Environment — end
```
4. If the entry is present but scripts are still not found, confirm the
   project folder path in `.zprofile` matches the actual project location.

---

## 6. Packages loading from system library instead of renv

**Symptom**

`validate_R_env` reports a package is loading from a path outside the
validated renv library, such as `/Library/Frameworks/R.framework/...`
instead of `~/.renv/MyProject/renv/library/...`.

**Cause**

One or more of the R library override environment variables (`R_LIBS`,
`R_LIBS_USER`, `R_LIBS_SITE`) is set in the shell environment, overriding
the renv library path. This is the most common cause of packages being found
outside the validated library.

**Resolution**

1. Check for conflicting environment variables:
```zsh
echo $R_LIBS
echo $R_LIBS_USER
echo $R_LIBS_SITE
```
2. If any are set, locate where they are defined:
```zsh
grep -r "R_LIBS" ~/.zprofile ~/.zshrc ~/.Renviron 2>/dev/null
```
3. Remove or comment out any `R_LIBS*` exports that are not part of the
   JR environment setup.
4. The JR wrappers (`jrr`, `jrpy`) always unset these variables before
   calling Rscript — if the issue only occurs when running scripts directly
   with `Rscript`, that is expected behaviour. Always use the wrappers.

---

## 7. pip install failing during venv rebuild

**Symptom**

`admin_install_Python` fails during the pip install step with an error such as:

```
ERROR: Could not find a version that satisfies the requirement matplotlib==3.8.2
ERROR: No matching distribution found for matplotlib==3.8.2
```

**Cause**

The package file is missing from the local Python repo (`Python_repo/my-repo/`),
or the Dropbox sync is incomplete.

**Resolution**

1. Check the local repo contains the expected wheel or sdist file:
```zsh
ls Python_repo/my-repo/ | grep matplotlib
```
2. If the file is missing, wait for Dropbox to finish syncing and try again.
3. If the file is genuinely absent (e.g. after adding a new package without
   running `--add`), run:
```zsh
admin_install_Python --add matplotlib==3.8.2
```
4. If the repo was built on a different platform (e.g. Intel vs Apple Silicon),
   the wheel file may be incompatible. Contact your administrator to rebuild
   the repo on the correct platform.

---

## 8. RENV_PATHS_ROOT not set error

**Symptom**

Running an R script directly with `Rscript` produces:

```
Error: RENV_PATHS_ROOT is not set.
Run this script from the provided zsh wrapper.
```

**Cause**

This is expected behaviour, not a bug. The JR environment requires scripts
to be run through their zsh wrappers (e.g. `jrrun`, `jrc_R_hello`) so that
`RENV_PATHS_ROOT` and other environment variables are set correctly before
R starts.

**Resolution**

Always run scripts through their wrapper:

```zsh
# Correct
jrr R/calctltf.R mydata.csv

# Incorrect — will fail with the above error
Rscript --vanilla R/calctltf.R mydata.csv
```

If you need to run a script interactively in RStudio or similar, contact
your administrator — a separate setup is required for interactive use.

---

## 9. Rscript not found

**Symptom**

```
❌ Rscript not found.
   Install R from: .../R_repo/
```

**Cause**

R is not installed on this machine, or the R installation is not on the PATH.

**Resolution**

1. Check whether R is installed:
```zsh
which Rscript
ls /Library/Frameworks/R.framework/Versions/
```
2. If R is installed but not found, the PATH may be incomplete. R installers
   on macOS add `/usr/local/bin/Rscript` — check this exists:
```zsh
ls -la /usr/local/bin/Rscript
```
3. If R is not installed, obtain the correct installer from `R_repo/` in
   Dropbox. The required version is in `admin/r_version.txt`.

---

## 10. project_id.txt not found

**Symptom**

```
❌ project_id.txt not found at: /Users/.../admin/project_id.txt
   Contact your administrator.
```

**Cause**

The `project_id.txt` file is missing from the `admin/` folder. This file
is committed to Git and should always be present after cloning the repository.

**Resolution**

1. Check whether the file exists:
```zsh
ls admin/project_id.txt
```
2. If missing after a fresh clone, the clone may be incomplete. Try:
```zsh
git status
git pull
```
3. If the file was accidentally deleted, restore it from git:
```zsh
git checkout admin/project_id.txt
```
4. If none of the above resolves the issue, contact your administrator to
   confirm the correct `PROJECT_ID` value and recreate the file manually:
```zsh
echo "MyProject" > admin/project_id.txt
```

---

## 12. Two copies of JR Anchored installed on the same machine

**Symptom**

You have cloned JR Anchored into a second folder (e.g. for testing a new
release). After running `setup_jr_path.sh` in the second copy, running
`jr_versions` or any wrapper still executes the script from the **first**
installation.

**Cause**

Both installations add their `bin/` and `wrapper/` directories to `PATH`.
The shell searches `PATH` entries in order and stops at the first match,
so the first-installed copy always wins when commands are entered by name.

**Resolution**

This is expected shell behaviour. For most users there is only ever one
installation per machine and this is not an issue.

If you genuinely need to run commands from a second copy:

1. Use explicit paths:
```zsh
~/path/to/second-copy/bin/jr_versions
```
2. Or `cd` into the second copy and call scripts with `./`:
```zsh
cd ~/path/to/second-copy
./bin/jr_versions
```

To switch which installation is active long-term, edit `~/.zprofile` (macOS)
or `~/.bashrc` (Windows Git Bash) and move the desired installation's `PATH`
entry to appear first.

**Important — Project ID conflict**

If both installations share the same `admin/project_id.txt` value, they also
share the same renv library (`~/.renv/<PROJECT_ID>/`), Python venv
(`~/.venvs/<PROJECT_ID>/`), run log, and validation evidence folder. If the
two installations have identical `renv.lock` and `python_requirements.txt`
files this is harmless. However, if the package versions differ — for example
when testing a new release alongside a production copy — each installation
will see the other's library as stale and trigger a rebuild, overwriting the
shared library. The two installations will continuously break each other.

To avoid this, give the test installation a distinct Project ID before running
any scripts:

```zsh
echo "MyProject-test" > admin/project_id.txt
admin_create_hash
```

This ensures each installation maintains its own isolated renv library, venv,
and audit log.

---

## 11. validate_R_env.R not found

**Symptom**

`jr_env_check` fails with:

```
❌ admin/R/validate_R_env.R not found.
   Run admin_validate first to generate it.
```

**Cause**

The validation scripts (`admin/R/validate_R_env.R` and
`admin/Python/validate_Python_env.py`) are auto-generated and excluded from
Git. They must be generated by the administrator before users can run
`jr_env_check`.

**Resolution**

Ask your administrator to run:

```zsh
admin_validate
```

This regenerates both validation scripts and runs a full IQ/OQ/PQ check.
The generated scripts will then be available for `jr_env_check`.

Note: this is by design — the validation scripts are generated from
`generate_validate_R.zsh` and `generate_validate_Python.zsh`, which are
the version-controlled source of truth. Only the administrator can regenerate
them to ensure the validation logic matches the approved configuration.

---

## 13. Package version mismatch after CRAN binary update

**Symptom**

`admin_install_R` fails at the version verification step with a message like:

```
🔍 Verifying installed versions:
   ✅ tolerance            3.0.0
   ✅ e1071                1.7.17
   ❌ ggplot2              installed: 4.0.3  required: 4.0.2
   ...
Error: ❌ Version mismatch detected. Check errors above.
```

**Which direction?**

Two different causes produce this same error. Read the mismatch line to tell
them apart — the direction is the diagnostic:

| Mismatch line | Cause | Go to |
|---|---|---|
| `installed: 4.0.3  required: 4.0.2` — installed **newer** than the pin | CRAN replaced the pinned binary | 13a below |
| `installed: 1.4.13  required: 1.4.14` — installed **older** than the pin | The pin names a version CRAN has no binary for | 13b below |

### 13a. CRAN replaced the pinned binary

> **Since v4.10.0 this should no longer happen on macOS.** Packages are fetched
> from https://www.dwylup.com/packages first, which keeps pinned versions frozen
> after CRAN drops them. If you hit 13a on macOS, check that the JR repository
> is reachable and that `JR_PACKAGE_REPO` has not been set to `""`. Windows
> still fetches binaries from CRAN, so 13a remains possible there.

**Cause**

CRAN only serves the current binary for each package on a given R version.
When a package is patched (e.g. ggplot2 4.0.2 → 4.0.3), the previous binary
is removed from CRAN and only the new version is available for download.
`admin_install_R` therefore installs the newer version, which does not match
the version pinned in `admin/R_requirements.txt`.

This typically surfaces when upgrading an older installation on a machine that
needs to rebuild the local repo from CRAN — the installed binary is newer than
the pin recorded at the time of the original installation.

**Resolution**

This is an admin task. Update the pinned version to match what CRAN now serves:

1. Open `admin/R_requirements.txt` and update the affected line:
```
ggplot2==4.0.3   # was: ggplot2==4.0.2
```
2. Re-run the installer — it will re-download the package and verify clean:
```zsh
admin_install_R
```
3. Regenerate the integrity file:
```zsh
admin_create_hash
```

The `renv.lock` is updated automatically in step 2. A patch-version bump of
a dependency carries low risk of breaking scripts, but raise a change-control
record in your QMS if your validation scope requires it.

**Note:** if multiple packages show a mismatch in the same run, update all of
them in `R_requirements.txt` before re-running `admin_install_R`.

### 13b. The pin names a version CRAN has no binary for

**Cause**

CRAN publishes a package's **source** release before it builds the macOS
binary, so for a window of hours to days the two indexes disagree:

```
CRAN source  (src/contrib)                        vcd 1.4-14
CRAN binary  (bin/macosx/sonoma-arm64/contrib/4.6) vcd 1.4-13
```

If `R_requirements.txt` is pinned to the source-only version, the installer
downloads the newest binary it can find (1.4-13), which is *older* than the
pin — so verification fails. Bumping the pin again cannot help; no binary
exists at that version yet.

You can hit this by hand-editing a pin to a version you read off CRAN's
package page (that page shows the **source** version).

**Resolution**

Pin back to the version CRAN actually serves as a binary, and wait for the
binary build to appear before bumping. Check what is really available:

```zsh
curl -s https://cloud.r-project.org/bin/macosx/sonoma-arm64/contrib/4.6/PACKAGES \
  | awk '/^Package: vcd$/{f=1} f&&/^Version:/{print $2; exit}'
```

Then revert the pin and re-run the installer:

```
# admin/R_requirements.txt
vcd==1.4-13   # was: vcd==1.4-14  (no macOS binary at 1.4-14 yet)
```
```zsh
admin_install_R
admin_create_hash
```

**A failed run leaves more than the pin behind.** If `admin_install_R` got as
far as writing its indexes before failing, these also need reverting — only
the first is tracked by Git, so `git status` will not show the rest:

| File | Fix |
|---|---|
| `admin/R_requirements.txt` | revert the pin |
| `admin/renv.lock` | revert the package's `"Version"` field |
| `R_repo/my-cran-repo/VERSIONS.txt` | revert the `pkg == ver` line |
| `R_repo/my-cran-repo/checksums.txt` | delete the line for the tarball that was removed |
| `R_repo/my-cran-repo/src/contrib/` | delete the stray source tarball, then rebuild the index: `Rscript -e 'tools::write_PACKAGES("R_repo/my-cran-repo/src/contrib", type="source")'` |

**Owner note:** `tools/owner_check_versions.py` compares pins against the
macOS binary index precisely so the daily auto-fix cannot walk into this. If
it ever reports a source-only version as required drift, the binary-flavour
probe has likely gone stale — add the current flavour name to
`R_BINARY_FLAVOURS` (R 4.5 was `big-sur-arm64`, R 4.6 is `sonoma-arm64`).

---

## 14. GUI Settings page cannot find jr_pack_config.json

**Symptom**

Opening the Settings page in the JR Anchored GUI shows one of the following:

```
Configuration file not found.
Expected: /Users/.../jrscripts/pack/jr_pack_config.json
```

Or, on older installations (before v3.8.1), the message may read:

```
JR Anchored Validation Pack not found.
Expected config at: /Users/.../jr-anchored-pack/jr_pack_config.json
```

**Cause**

Two separate issues, depending on the installation:

1. **Wrong path (pre-v3.8.1 GUI):** The GUI was looking for the config file in
   `../jr-anchored-pack/` (the developer's repo layout) instead of `./pack/`
   (the customer deployment path). Fixed in v3.8.1 — `git pull` resolves this.

2. **Missing file:** `jr_pack_config.json` was not created during installation.
   Versions of `install.sh` prior to v3.8.1 did not create this file; it was
   also absent from the zip archive. Fixed in pack installer v3.8.1.

**Resolution**

**If you have not yet run `git pull`:** do that first, then restart the GUI. The
path issue is fixed in v3.8.1 and the Settings page will point to the correct
location.

**If the file is still missing** after pulling, create it manually from the JR
Anchored root:

```zsh
python3 -c "
import json
with open('pack/jr_pack_config.json', 'w') as f:
    json.dump({'company_name': '', 'logo_path': '', 'doc_number_prefix': ''}, f, indent=2)
    f.write('\n')
"
```

Then restart the GUI and go to Settings to fill in your company details.

**Future installs:** `install.sh` v3.8.1 and later creates the config file
automatically as part of the installation — this issue will not occur.

## 15. "package '…' was built under R version 4.6.1" warning

**Symptom**

Running a script that uses a pinned add-on package prints a warning on stderr,
for example:

```
package 'survival' was built under R version 4.6.1
package 'emmeans' was built under R version 4.6.1
```

Packages that can trigger it include `survival` (`jrc_weibull`,
`jrc_clinical_km`, `jrc_clinical_coxph`) and `emmeans`/`mvtnorm`
(`jrc_clinical_ancova`). The script still runs and produces correct output;
the message is a warning, not an error.

**Cause**

The package is pinned at a validated version whose CRAN binary was compiled
under R 4.6.1, while the validated environment pins R at 4.6.0. R notes the
minor-version difference on load. These packages are binary-compatible across
the R 4.6.x series, so this is cosmetic — the pinned, hash-verified package
loads and behaves identically. The OQ suites all pass against these exact
binaries, which is the validation evidence that the warning carries no
functional weight.

**Resolution**

None required. The warning is expected and documented. It is deliberately
**not** suppressed: hiding it would also hide any genuine future load warning,
which the validated environment must never do. Ignore this specific message.

It disappears on its own if the environment is later re-pinned to R 4.6.1 (the
version survival 3.8-9 was built under), which will happen naturally at the
next R version bump.
