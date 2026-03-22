# JR Anchored

A framework for running validated R and Python scripts in a controlled,
reproducible environment — designed for medical device development teams
working under FDA and ISO 13485 requirements.

**Website & documentation:** [www.dwylup.com](https://www.dwylup.com)

---

## What is this?

JR Anchored provides a structured way to:

- Run R and Python analysis scripts with **pinned, auditable package versions**
- Ensure every team member uses **exactly the same packages** regardless of their machine setup
- Install packages exclusively from a **controlled local repository** — never directly from the internet during normal use
- Verify **project integrity** before every script run
- Generate **validation evidence** for auditors with a single command

It is designed for small to medium medical device development teams on macOS and Windows who need a pragmatic, FDA-friendly approach to software validation without the overhead of a full enterprise solution.

---

## Requirements

**macOS (Apple Silicon or Intel)**
- [R](https://cran.r-project.org/bin/macosx/) — version specified in `admin/r_version.txt`
- [Python](https://www.python.org/downloads/macos/) — version specified in `admin/python_version.txt`

**Windows 10/11**
- [R for Windows](https://cran.r-project.org/bin/windows/base/) — version specified in `admin/r_version.txt`
- [Python for Windows](https://www.python.org/downloads/windows/) — version specified in `admin/python_version.txt`
- [Git for Windows](https://git-scm.com/download/win) — provides Git Bash (the terminal used to run all JR commands)

**File sharing (choose one)**
- **SMB network share** (recommended, zero cost) — any shared folder on your company network
- **Dropbox** — convenient for distributed teams; free tier (2 GB) is typically sufficient

---

## Quick Start for End Users

> If you are a team member who has been given access to JR Anchored by your administrator, follow these steps.

**macOS**

**Step 1** — Open Terminal. Press `Command + Space`, type `Terminal`, press `Enter`.

**Step 2** — Find the file `setup_jr_path.sh` in the JR project folder in Finder. Drag it into the Terminal window and press `Enter`.

**Step 3** — You will see:
```
✅ PATH updated successfully.
```

**Step 4** — Open a new Terminal window (`Command + N`). You are ready.

**Windows**

**Step 1** — Open Git Bash (search for "Git Bash" in the Start menu).

**Step 2** — Navigate to the JR project folder and run:
```bash
bash setup_jr_path.sh
```

**Step 3** — Close and reopen Git Bash. You are ready.

---

**Step 5 (both platforms)** — Type the name of any JR script and press `Enter`. On first run the environment will be set up automatically — this may take a minute. All subsequent runs are fast.

> You only need to run `setup_jr_path.sh` once per machine.

---

## Quick Start for Administrators

> See the [Admin Manual](docs/admin_manual.pdf) for full instructions. This is a summary.

**First-time setup** (requires internet):

```bash
# 1. Clone the repository
git clone https://github.com/ubrowz/jr-anchored.git
cd jr-anchored

# 2. Build the local package repositories and install the environments
./admin/admin_install_R --rebuild
./admin/admin_install_Python --rebuild
```

> **Windows:** Open Git Bash as Administrator before running admin commands
> (right-click Git Bash → Run as administrator).

**Subsequent setups** (no internet needed):

```bash
./admin/admin_install_R
./admin/admin_install_Python
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Admin (once)                            │
│                                                             │
│  R_requirements.txt ──► admin_install_R ──► shared repo     │
│  python_requirements.txt ► admin_install_Python             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Dropbox sync or SMB share)
┌─────────────────────────────────────────────────────────────┐
│                  Each User (automatic)                      │
│                                                             │
│  bash wrapper ──► integrity check ──► rebuild if needed     │
│               ──► run R or Python script                    │
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
├── setup_jr_path.zsh                ← macOS zsh variant
│
├── bin/
│   ├── jrrun                        ← run any R or Python script in the environment
│   ├── jr_versions                  ← show installed R, Python, and package versions
│   └── jr_uninstall                 ← remove local environment components
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
│   ├── admin_install_R              ← set up R environment
│   ├── admin_install_Python         ← set up Python environment
│   ├── admin_create_hash            ← regenerate integrity file
│   ├── admin_validate               ← generate validation scripts and IQ evidence
│   └── admin_uninstall              ← remove entire environment from this machine
│
└── docs/
    ├── admin_manual.pdf             ← full administrator manual (macOS + Windows)
    └── user_manual.pdf              ← end-user manual
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

## Important Note on Validation Scope

The validation evidence included in `docs/` covers the specific R version, Python version, and package versions listed in the requirements files at the time of release. If you install JR Anchored with different versions, the included validation evidence no longer applies to your installation. You must perform your own revalidation using the provided Validation Plan and Validation Report templates before using the environment in a regulated context.

---

## Adapting for Your Project

There are two ways to use JR Anchored depending on your needs.

---

**Usage 1 — Install and configure for your project (recommended for most teams)**

Download the `.pkg` installer from the [Releases](https://github.com/ubrowz/jr-anchored/releases)
page and follow the Admin Manual. After installation the admin performs these steps to configure
the environment for your project:

1. Edit `admin/R_requirements.txt` and `admin/python_requirements.txt` with the packages your scripts require.
2. Edit `admin/r_version.txt` and `admin/python_version.txt` with the R and Python versions you want to pin.
3. Run `./admin/admin_install_R --rebuild` and `./admin/admin_install_Python --rebuild` to build your own local package repository.
4. Add your R and Python scripts to the `R/` and `Python/` subfolders following the Admin Manual.
5. Optionally add per-script help files to `help/` and named wrappers to `wrapper/`.
6. Run `./admin/admin_create_hash` to generate the project integrity file.
7. Run `./admin/admin_validate` to generate the validation scripts and confirm the environment is working.

Team members then run `setup_jr_path.sh` once on their machine and the environment is ready.

---

**Usage 2 — Fork and extend the framework**

If you want to modify the architecture, contribute improvements, or significantly extend the
framework for your own purposes, fork this repository on GitHub, make your changes, and submit
a pull request if you would like your improvements included in the main project. Please read
the Contributing section before submitting.

---

## Regulatory Context

This framework is designed to support compliance with:

- **FDA 21 CFR Part 11** — electronic records and signatures
- **ISO 13485:2016** — quality management systems for medical devices
- **GAMP 5** — good automated manufacturing practice

The combination of pinned package versions, a controlled local repository, SHA256 integrity checking, and auto-generated validation reports provides the documentation trail typically required during a software audit or FDA submission.

> **Disclaimer:** This software is provided as a framework for building validated environments. It is the responsibility of each organisation to perform their own validation activities in accordance with applicable regulations. The authors make no warranties regarding the suitability of this software for any regulated purpose.

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request so the proposed change can be discussed. All contributions must maintain compatibility with the validation framework — changes that weaken integrity checking or bypass the controlled package repository will not be accepted.

---

## Licence

Copyright 2026 dwylup

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full licence text.

---

## Support

For questions about adapting this framework for your project, open a GitHub issue or visit [www.dwylup.com](https://www.dwylup.com).
