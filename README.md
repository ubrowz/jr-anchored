# JR Anchored

[![Latest release](https://img.shields.io/github/v/release/ubrowz/jr-anchored)](https://github.com/ubrowz/jr-anchored/releases/latest)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows-blue)
![Made with R](https://img.shields.io/badge/R-validated%20environment-276DC3?logo=r&logoColor=white)
![Made with Python](https://img.shields.io/badge/Python-validated%20environment-3776AB?logo=python&logoColor=white)

A framework for running validated R and Python scripts in a controlled,
reproducible environment — designed for medical device development teams
working under FDA and ISO 13485 requirements.

**Website & documentation:** [www.dwylup.com](https://www.dwylup.com)

![JR Anchored graphical interface — point-and-click access to all validated scripts](https://www.dwylup.com/img/gui_screenshot.png)

---

## What is this?

JR Anchored provides a structured way to:

- Run R and Python analysis scripts with **pinned, auditable package versions**
- Ensure every team member uses **exactly the same packages** regardless of their machine setup
- Install packages exclusively from a **controlled local repository** — never directly from the internet during normal use
- Verify **project integrity** before every script run
- Generate **validation evidence** for auditors with a single command
- Run all **56 validated scripts** — and perform **every administrator task** — from a **point-and-click graphical interface**; the only terminal step on a new machine is the initial `git clone`

It spans **10 analysis modules** with **621 automated OQ tests**, and is designed for small to medium medical device development teams on macOS and Windows who need a pragmatic, FDA-friendly approach to software validation without the overhead of a full enterprise solution.

---

## Requirements

**macOS (Apple Silicon or Intel)**
- [R](https://cran.r-project.org/bin/macosx/) — version specified in `admin/r_version.txt`
- [Python](https://www.python.org/downloads/macos/) — version specified in `admin/python_version.txt`

**Windows 10/11**
- [R for Windows](https://cran.r-project.org/bin/windows/base/) — version specified in `admin/r_version.txt`
- [Python for Windows](https://www.python.org/downloads/windows/) — version specified in `admin/python_version.txt`
- [Git for Windows](https://git-scm.com/download/win) — **administrators only**, provides Git Bash for the one-time setup; end users running the GUI do not need it

**File sharing** (choose one)
- **Dropbox** — a shared Dropbox folder; no server or IT infrastructure required
- **SMB network share** — any shared folder on your company network (zero cost)

---

## Quick Start for End Users

> If your administrator has shared JR Anchored with you, you only need the GUI — no Terminal.

**Step 1** — Make sure the shared project folder is accessible on your machine (Dropbox fully synced, or the SMB network share mounted).

**Step 2** — Launch the app:
- **macOS** — double-click **`JR Anchored.app`** (right-click → **Open** the first time to clear Gatekeeper).
- **Windows** — double-click **`JR Anchored.bat`**.

**Step 3** — Your browser opens the GUI automatically. On first launch Streamlit installs (~30 seconds, once). Select a script from the sidebar, provide your data, fill in the parameters, and click **Run**. The first script run builds the local environment automatically — **this can take 1–3 minutes, do not interrupt** — and every run after that is fast.

That's it — no setup, no Terminal.

> **Prefer the command line?** Run `setup_jr_path.sh` once (drag it into Terminal on macOS, or `bash setup_jr_path.sh` in Git Bash on Windows), open a new terminal, and you can call scripts directly — e.g. `jrc_ss_discrete --help`.

---

## Graphical Interface

The GUI is the primary way to use JR Anchored — a Streamlit interface covering
all 56 validated scripts **and** the full administrator workflow (setup,
validation, OQ, updates, Validation Pack install). It runs locally in your
browser — no cloud connection, no account required.

**macOS** — double-click `JR Anchored.app` (or run `bin/jr_app` in Terminal).

**Windows** — double-click `JR Anchored.bat` (or use the Desktop shortcut
created by `Create JR Anchored Shortcut.ps1`).

The GUI opens at `http://localhost:8501`. Select a module, choose a script,
upload your data file if required, fill in the parameters, and click Run.
All scripts run through `jrrun` with the same integrity checking as the CLI.
Press `Ctrl+C` in the Terminal window to stop.

> See [gui.html](https://www.dwylup.com/gui.html) on the website for full
> installation and usage instructions.

---

## Quick Start for Administrators

> See the [Admin Manual](docs/admin_manual.pdf) for full instructions. This is a summary.

The only terminal step is the initial `git clone`. Everything after that runs
from the GUI's **🔧 Admin** tab.

**First-time setup** (requires internet):

```bash
# The one and only terminal step — clone the repository (release branch is the default)
git clone https://github.com/ubrowz/jr-anchored.git
cd jr-anchored
```

Then double-click **`JR Anchored.app`** (macOS) or **`JR Anchored.bat`** (Windows)
to launch the GUI, open the **🔧 Admin** tab, set an admin password, and click
**▶ admin_setup --rebuild** under *Setup & Environments*. That one action downloads
all packages, installs the R and Python environments, generates the integrity file,
and runs IQ validation — output streams live in the browser (10–30 minutes).

> **Prefer the terminal?** `./admin/admin_setup --rebuild` does exactly the same thing.
> On Windows, open Git Bash as Administrator first.

Everything else — rebuilding environments, adding a package, regenerating the
integrity file, IQ validation, the OQ suites, updates, Validation Pack install, and
uninstall — is a button in the **🔧 Admin** tab (each with a terminal equivalent under `admin/`).

**Upgrading to a new release** — click **▶ admin_update** in the Admin tab (or run
`./admin/admin_update`). It runs pre-flight conflict checks, pulls the latest release,
regenerates the integrity file, rebuilds the environments if their requirements changed,
and re-validates — refusing to report success if validation fails.

> JR Anchored uses a `release` branch as the default, so you only ever receive changes
> promoted to a validated release — never unfinished development from `main`. Check your
> version with `git describe --tags`.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│              Admin (once, from the GUI Admin tab)           │
│                                                             │
│  R/python_requirements.txt ──► admin_setup --rebuild        │
│        ──► builds local package repos + envs + integrity    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Dropbox sync or SMB share)
┌─────────────────────────────────────────────────────────────┐
│              Each User (GUI or CLI, automatic)              │
│                                                             │
│  launch app / wrapper ──► integrity check ──► rebuild if    │
│        needed ──► run R or Python script via jrrun          │
└─────────────────────────────────────────────────────────────┘
```

Package versions are pinned in `R_requirements.txt` and `python_requirements.txt`. Packages are downloaded once into a local repository and never fetched from the internet again. Each user's environment is built automatically from this local repository on first run.

---

## Why Not Docker?

Docker is a legitimate alternative for running scripts in a controlled environment,
and the right choice depends on your team. Here is a concise comparison:

| | JR Anchored | Docker |
|---|---|---|
| Learning curve | Low — basic Terminal only | High — images, registries, Dockerfile |
| Audit transparency | High — plain text requirements files | Moderate — binary image requires tooling |
| macOS/Windows GUI output | Native, no configuration | Requires X11 or volume mapping |
| Resource usage | Minimal — no background processes | Heavy — Linux VM always running |
| Distribution | Dropbox or SMB share | Registry + Docker Desktop install |
| Package updates | Edit one file, auto-propagated | Rebuild and redistribute entire image |
| Offline use | Yes | Requires local registry |
| Cross-platform | macOS and Windows | macOS, Windows, Linux |
| System dependencies | R and Python packages only | Full OS-level control |

**Choose JR Anchored if** your team consists of researchers or analysts rather than
software engineers, and you want validation evidence in plain text files that a
Quality Manager can read directly without additional tooling.

**Choose Docker instead if** your scripts depend on system-level libraries, or you
are already working in a DevOps environment with Docker expertise in the team.

The two approaches can also be combined — the `R_requirements.txt` and
`python_requirements.txt` files can serve as the source of truth for both the JR
local repository and a Dockerfile.

---

## Repository Structure

```
jr-anchored/
│
├── README.md                        ← this file
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── PLATFORMS.md
├── setup_jr_path.sh                 ← run once per machine to add bin/ and wrapper/ to PATH
│
├── bin/
│   ├── jrrun                        ← run any R or Python script in the environment
│   ├── jr_app                       ← launch the graphical interface (CLI entry point)
│   ├── jr_versions                  ← show installed R, Python, and package versions
│   └── jr_uninstall                 ← remove local environment components
│
├── app/
│   └── jr_app.py                    ← Streamlit GUI (all 56 scripts + Admin tab)
│
├── JR Anchored.app                  ← macOS app bundle with anchor icon (Dock-ready)
├── JR Anchored.bat                  ← Windows launcher
├── JR Anchored.ico                  ← Windows icon file
├── Create JR Anchored Shortcut.ps1  ← creates a Desktop shortcut with custom icon
│
├── wrapper/                         ← per-script wrappers (no editing needed)
├── help/                            ← per-script help text files
│
├── R/                               ← R analysis scripts
├── Python/                          ← Python analysis scripts
│
├── repos/                           ← validated module scripts (MSA, SPC, AS, Corr, …)
│
├── admin/
│   ├── R_requirements.txt           ← pinned R package versions
│   ├── python_requirements.txt      ← pinned Python package versions
│   ├── renv.lock                    ← R package lockfile (auto-generated)
│   ├── r_version.txt                ← required R version
│   ├── python_version.txt           ← required Python version
│   ├── project_id.txt               ← unique project identifier
│   ├── admin_setup                  ← one-step first-time setup (install + hash + IQ + PATH)
│   ├── admin_update                 ← pull a new release, rebuild if needed, re-validate
│   ├── admin_install_R              ← set up / rebuild R environment
│   ├── admin_install_Python         ← set up / rebuild Python environment
│   ├── admin_create_hash            ← regenerate integrity file
│   ├── admin_validate               ← generate validation scripts and IQ evidence
│   ├── admin_oq                     ← run the core/community OQ test suite
│   ├── admin_oq_all                 ← run every OQ suite (core + all modules)
│   ├── admin_oq_validate            ← pre-flight check before running OQ
│   ├── admin_scaffold_R             ← scaffold a new community R script
│   ├── admin_scaffold_Python        ← scaffold a new community Python script
│   ├── admin_create_repo            ← scaffold a new module repository
│   └── admin_uninstall              ← remove entire environment from this machine
│
└── docs/
    ├── TROUBLESHOOTING.md           ← common issues and resolutions
    ├── CREATING_MODULES.md          ← guide for adding new module repositories
    ├── admin_manual.pdf             ← full administrator manual (macOS + Windows)
    ├── user_manual.pdf              ← end-user manual
    └── templates/                   ← validation plan and report templates
```

---

## Validation Evidence

To generate validation scripts and a timestamped IQ evidence file suitable for an audit, run:

```bash
./admin/admin_validate
```

This generates the R and Python validation scripts from the requirements files, runs a full IQ check, and writes a timestamped evidence file to `~/.jrscript/[PROJECT_ID]/validation/`.

To check currently installed versions at any time:

```bash
jr_versions
```

---

## Verifying Authenticity

Every JR Anchored release is published as a **cryptographically signed Git tag**,
so you can confirm the code you cloned is a genuine, unmodified release — not a
tampered copy or a look-alike repository.

You normally do not need to do anything: **`admin_update` and `admin_setup`
verify the signature automatically and refuse to apply an update whose signature
does not check out.** The GUI shows the result in the sidebar — e.g.
*✅ Verified release v4.0.4*. End users launching the GUI without Git installed
inherit the release the administrator already verified.

To verify by hand on any machine with Git:

```bash
bin/jr_verify_release            # verify the current checkout
bin/jr_verify_release origin/release   # verify the latest fetched release
```

To anchor the signing key to the genuine maintainer (defeating a fake
repository), compare the key fingerprint against the value published on
[www.dwylup.com](https://www.dwylup.com):

```bash
ssh-keygen -lf admin/allowed_signers
```

See [docs/VERIFYING.md](docs/VERIFYING.md) for full details.

---

## Important Note on Validation Scope

The validation evidence included in `docs/` covers the specific R version, Python version, and package versions listed in the requirements files at the time of release. If you install JR Anchored with different versions, the included validation evidence no longer applies to your installation. You must perform your own revalidation using the provided Validation Plan and Validation Report templates before using the environment in a regulated context.

---

## Adapting for Your Project

There are two ways to use JR Anchored depending on your needs.

---

**Usage 1 — Clone and configure for your project (recommended for most teams)**

Clone the repository and follow the Admin Manual. The admin then configures
the environment for the project:

1. Edit `admin/R_requirements.txt` and `admin/python_requirements.txt` with the packages your scripts require.
2. Edit `admin/r_version.txt` and `admin/python_version.txt` with the R and Python versions you want to pin.
3. Run `./admin/admin_install_R --rebuild` and `./admin/admin_install_Python --rebuild` to build your own local package repository.
4. Add community scripts using `./admin/admin_scaffold_R` or `./admin/admin_scaffold_Python`, or create a new module with `./admin/admin_create_repo`.
5. Run `./admin/admin_create_hash` to generate the project integrity file.
6. Run `./admin/admin_validate` to generate the validation scripts and confirm the environment is working.

Team members then just launch the GUI app (or run `setup_jr_path.sh` once for command-line use) and the environment is ready.

---

**Usage 2 — Fork and extend the framework**

If you want to modify the architecture, contribute improvements, or significantly extend the
framework for your own purposes, fork this repository on GitHub, make your changes, and submit
a pull request if you would like your improvements included in the main project. Please read
the Contributing section before submitting.

---

## Regulatory Context

This framework is designed to support compliance with:

- **FDA 21 CFR 820.70(i)** — automated data processing in manufacturing
- **ISO 13485:2016** — quality management systems for medical devices
- **GAMP 5** — good automated manufacturing practice

The combination of pinned package versions, a controlled local repository, SHA256 integrity checking, and auto-generated validation reports provides the documentation trail typically required during a software audit or FDA submission.

> **Disclaimer:** This software is provided as a framework for building validated environments. It is the responsibility of each organisation to perform their own validation activities in accordance with applicable regulations. The authors make no warranties regarding the suitability of this software for any regulated purpose.

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request so the proposed change can be discussed. All contributions must maintain compatibility with the validation framework — changes that weaken integrity checking or bypass the controlled package repository will not be accepted.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full process, including the three levels of contribution (personal use, team scripts, and public contributions).

---

## Licence

Copyright 2026 dwylup

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full licence text.

---

## Acknowledgements

JR Anchored was designed and built with the assistance of [Claude Code](https://claude.com/claude-code) by Anthropic.

---

## Support

For questions about adapting this framework for your project, open a GitHub issue or visit [www.dwylup.com](https://www.dwylup.com).
