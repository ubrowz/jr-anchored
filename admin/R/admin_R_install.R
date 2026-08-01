# ==============================
# Admin setup script for renv
# R package versions in R_requirements.txt
#
# run as: Rscript --vanilla admin/R/admin_R_install.R
#         called via zsh wrapper admin_install_R
#
# Modes:
#   BUILD_REPO=true
#     → downloads pinned packages from internet into LOCAL_REPO, then installs
#   BUILD_REPO=false  (default)
#     → installs directly from LOCAL_REPO (no internet needed)
#   ADD_PACKAGE=packagename==version
#     → downloads ONE new package + dependencies into existing LOCAL_REPO,
#       updates R_requirements.txt, renv.lock, checksums.txt, then installs
#
# R_requirements.txt format (one per line, comments with #):
#   ggplot2==3.5.2
#   e1071==1.7.16
#   tolerance==2.0.0
#
# ==============================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOCAL_REPO  <- Sys.getenv("LOCAL_REPO")
if (LOCAL_REPO == "") {
  stop(paste(
    "❌ LOCAL_REPO environment variable is not set.",
    "   Call this R script only via zsh wrapper admin_install_R",
    "   to ensure correct environment variable setting.",
    sep = "\n"
  ))
}

RENV_HOME      <- Sys.getenv("RENV_PATHS_ROOT")
BUILD_REPO     <- Sys.getenv("BUILD_REPO",      unset = "false") == "true"
ADD_PACKAGE    <- Sys.getenv("ADD_PACKAGE",     unset = "")
POPULATE_ONLY  <- Sys.getenv("POPULATE_ONLY",   unset = "false") == "true"
MACOS_PLATFORM <- Sys.getenv("R_MACOS_PLATFORM", unset = "")
if (MACOS_PLATFORM == "") {
  stop(paste(
    "❌ R_MACOS_PLATFORM is not set.",
    "   Call this R script only via zsh wrapper admin_install_R",
    "   to ensure correct environment variable setting.",
    sep = "\n"
  ))
}
CRAN_MIRROR <- "https://cloud.r-project.org"

# Optional JR-hosted package repository, tried BEFORE CRAN.
#
# CRAN serves only the current binary for each package, so a pinned version
# disappears when the package is patched and a fresh --rebuild then fails. A
# JR-hosted repository holds the pinned versions frozen, which removes that
# failure entirely.
#
# Defaults to the JR-hosted repository. Set JR_PACKAGE_REPO to override it, or
# to "" to opt out entirely and install from CRAN alone. CRAN is always retained
# as the fallback entry, so an unreachable JR host degrades to CRAN-only
# behaviour rather than breaking installs.
#
# Anything downloaded is checked against admin/r_package_hashes.sha256 by
# admin_install_R before the manifest is regenerated — the signed manifest, not
# the host, is the root of trust.
JR_PACKAGE_REPO <- Sys.getenv("JR_PACKAGE_REPO",
                              unset = "https://www.dwylup.com/packages")
PKG_REPOS <- if (nzchar(JR_PACKAGE_REPO)) {
  c(JR = JR_PACKAGE_REPO, CRAN = CRAN_MIRROR)
} else {
  c(CRAN = CRAN_MIRROR)
}
if (nzchar(JR_PACKAGE_REPO)) {
  cat(sprintf("\U0001F4E6 Package source: %s (CRAN as fallback)\n", JR_PACKAGE_REPO))
}
BINARY_TYPE <- paste0("mac.binary.", MACOS_PLATFORM)
r_minor     <- paste(R.version$major,
                     sub("\\..*", "", R.version$minor), sep = ".")

# miniCRAN does not reliably download Windows binaries (win.binary) or
# Intel macOS binaries (mac.binary.big-sur-x86_64). For these platforms we
# fall back to downloading source via miniCRAN and fetching binaries manually.
MINICRAN_BINARY_TYPES <- c("mac.binary",
                            "mac.binary.el-capitan",
                            "mac.binary.big-sur-arm64")
USE_MINICRAN_BINARY <- BINARY_TYPE %in% MINICRAN_BINARY_TYPES

if (!USE_MINICRAN_BINARY) {
  cat(sprintf(
    "ℹ️  Binaries for '%s' will be fetched directly (not via miniCRAN).\n",
    BINARY_TYPE))
  cat("    Source packages will be fetched via miniCRAN.\n\n")
}

# ---------------------------------------------------------------------------
# Helper — download binary packages directly (Windows and Intel macOS)
# ---------------------------------------------------------------------------

# `mirrors` is an ordered character vector: the JR-hosted repository first (when
# configured) and CRAN last. Each package is taken from the first mirror whose
# index offers it, so a version CRAN has already dropped is still found in the
# JR repo, while anything the JR repo does not carry falls through to CRAN.
download_binaries_manually <- function(pkgs, local_repo, mirrors,
                                       platform, r_ver) {
  if (platform == "windows") {
    bin_dir  <- file.path(local_repo, "bin/windows", "contrib", r_ver)
    sub      <- sprintf("bin/windows/contrib/%s", r_ver)
    ext      <- ".zip"
    idx_type <- "win.binary"
  } else {
    bin_dir  <- file.path(local_repo, "bin/macosx", platform, "contrib", r_ver)
    sub      <- sprintf("bin/macosx/%s/contrib/%s", platform, r_ver)
    ext      <- ".tgz"
    idx_type <- "mac.binary"
  }
  dir.create(bin_dir, recursive = TRUE, showWarnings = FALSE)

  # Query every mirror once, in order, keeping those that answer.
  sources <- list()
  for (m in mirrors) {
    url <- sprintf("%s/%s", m, sub)
    idx <- tryCatch(available.packages(contriburl = url),
                    error = function(e) NULL)
    if (!is.null(idx) && nrow(idx) > 0) {
      sources[[length(sources) + 1]] <- list(url = url, avail = idx)
    } else if (identical(m, mirrors[length(mirrors)]) && length(sources) == 0) {
      warning(sprintf("Could not query binary index at %s", url))
    }
  }
  if (length(sources) == 0) {
    cat("⚠️  Could not retrieve binary package list — binaries skipped.\n\n")
    return(invisible(NULL))
  }

  for (pkg in pkgs) {
    # First mirror that offers this package wins. With the JR repo listed first
    # this resolves to the pinned version even after CRAN has dropped it.
    src <- NULL
    for (s in sources) {
      if (pkg %in% rownames(s$avail)) { src <- s; break }
    }
    if (is.null(src)) next

    ver   <- src$avail[pkg, "Version"]
    fname <- sprintf("%s_%s%s", pkg, ver, ext)
    dest  <- file.path(bin_dir, fname)

    if (file.exists(dest)) {
      cat(sprintf("   ✅ %s (already cached)\n", fname))
      next
    }

    # Try the chosen mirror, then any remaining ones that also list the package:
    # an index can advertise a file that 404s.
    got <- FALSE
    for (s in sources) {
      if (!(pkg %in% rownames(s$avail))) next
      if (s$avail[pkg, "Version"] != ver) next
      ok <- tryCatch({
        download.file(sprintf("%s/%s", s$url, fname), dest,
                      mode = "wb", quiet = TRUE)
        TRUE
      }, error = function(e) FALSE, warning = function(w) FALSE)
      if (ok && file.exists(dest) && file.size(dest) > 0) { got <- TRUE; break }
    }
    if (got) {
      cat(sprintf("   ✅ %s\n", fname))
    } else {
      cat(sprintf("   ⚠️  Failed to download %s from any configured repository\n",
                  fname))
    }
  }

  tools::write_PACKAGES(bin_dir, type = idx_type)
  cat("📋 Binary PACKAGES index written.\n\n")
}

# ---------------------------------------------------------------------------
# On Windows, ensure bootstrap packages can install without administrator rights
# ---------------------------------------------------------------------------
# install.packages() without lib= defaults to .libPaths()[1], which is the
# system library (C:/Program Files/R/.../library) and requires admin rights.
# If that path is not writable, prepend a user-writable personal library so
# miniCRAN and renv can be bootstrapped by a non-admin user.

if (.Platform$OS.type == "windows") {
  sys_lib <- .libPaths()[1]
  if (file.access(sys_lib, mode = 2) != 0) {
    user_lib <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R",
                          "win-library", r_minor)
    dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(user_lib, .libPaths()))
    cat(sprintf(
      "ℹ️  System R library not writable — bootstrap packages will go to:\n   %s\n\n",
      user_lib))
  }
}

# ---------------------------------------------------------------------------
# Determine mode
# ---------------------------------------------------------------------------

MODE <- if (nchar(ADD_PACKAGE) > 0) "ADD" else if (BUILD_REPO) "BUILD" else "INSTALL"
cat(sprintf("Mode: %s\n\n", MODE))

# ---------------------------------------------------------------------------
# Helper — parse requirements file into named vector
# ---------------------------------------------------------------------------

read_requirements <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[lines != "" & !startsWith(lines, "#")]
  bad   <- lines[!grepl("==", lines)]
  if (length(bad) > 0) {
    stop(paste0(
      "❌ R_requirements.txt entries must use 'package==version' format.\n",
      "   Offending lines: ", paste(bad, collapse = ", ")
    ))
  }
  setNames(sub(".*==", "", lines), sub("==.*", "", lines))
}

# ---------------------------------------------------------------------------
# Parse R_requirements.txt
# ---------------------------------------------------------------------------

REQ_FILE <- "R_requirements.txt"
if (!file.exists(REQ_FILE)) stop("❌ R_requirements.txt not found")

pkg_versions <- read_requirements(REQ_FILE)
pkg_names    <- names(pkg_versions)

cat("📋 Current packages in R_requirements.txt:\n")
for (nm in pkg_names) cat(sprintf("   %-20s %s\n", nm, pkg_versions[nm]))
cat("\n")

# ---------------------------------------------------------------------------
# ADD mode — download one new package + dependencies, update repo and files
# ---------------------------------------------------------------------------

if (MODE == "ADD") {

  # Validate format
  if (!grepl("==", ADD_PACKAGE)) {
    stop(paste0(
      "❌ --add requires format: packagename==version\n",
      "   Received: ", ADD_PACKAGE
    ))
  }

  add_name <- sub("==.*", "", ADD_PACKAGE)
  add_ver  <- sub(".*==", "", ADD_PACKAGE)

  cat(sprintf("➕ Adding package: %s version %s\n\n", add_name, add_ver))

  # Check if already in requirements
  if (add_name %in% pkg_names) {
    existing_ver <- pkg_versions[[add_name]]
    if (existing_ver == add_ver) {
      cat(sprintf("✅ %s==%s is already in R_requirements.txt — nothing to do.\n",
                  add_name, add_ver))
      quit(status = 0)
    } else {
      cat(sprintf("⚠️  %s already in R_requirements.txt at version %s — updating to %s\n",
                  add_name, existing_ver, add_ver))
    }
  }

  # Verify local repo exists — ADD requires an existing repo
  if (!dir.exists(LOCAL_REPO)) {
    stop(paste0(
      "❌ Local repo not found at: ", LOCAL_REPO, "\n",
      "   Run admin_install_R --rebuild first to create the repo,\n",
      "   then use --add to extend it."
    ))
  }

  # Resolve dependencies from CRAN
  cat(sprintf("🔍 Resolving dependencies for %s==%s...\n", add_name, add_ver))

  if (!requireNamespace("miniCRAN", quietly = TRUE)) {
    install.packages("miniCRAN", repos = CRAN_MIRROR)
  }
  library(miniCRAN)

  # pkgDep returns all recursive dependencies including the package itself
  all_deps <- pkgDep(add_name, repos = PKG_REPOS,
                     type = "source", suggests = FALSE)

  # Get the versions CRAN would download for each dependency
  cran_pkg_info <- tryCatch(
    available.packages(repos = PKG_REPOS, type = "source"),
    error = function(e) stop(paste("❌ Failed to query CRAN:", e$message))
  )

  cat("📦 Resolved dependencies:\n")
  for (dep in all_deps) {
    if (dep %in% rownames(cran_pkg_info)) {
      cran_ver <- cran_pkg_info[dep, "Version"]
      cat(sprintf("   %-20s %s (CRAN)\n", dep, cran_ver))
    }
  }
  cat("\n")

  # ---------------------------------------------------------------------------
  # Conflict check — compare CRAN versions against R_requirements.txt pins
  # ---------------------------------------------------------------------------
  # The target package itself is excluded from this check since we are
  # intentionally adding/updating it. Only its dependencies are checked.

  dep_conflicts <- character(0)

  for (dep in all_deps) {
    if (dep == add_name) next                          # skip the target package itself
    if (!dep %in% rownames(cran_pkg_info)) next        # skip if not on CRAN (base pkg)

    cran_ver <- cran_pkg_info[dep, "Version"]

    if (dep %in% pkg_names) {
      pinned_ver <- pkg_versions[[dep]]
      # Normalise hyphens for comparison (e.g. 7.3-65 vs 7.3.65)
      if (gsub("-", ".", cran_ver) != gsub("-", ".", pinned_ver)) {
        dep_conflicts <- c(dep_conflicts,
          sprintf("   %-20s pinned: %-12s  CRAN would download: %s",
                  dep, pinned_ver, cran_ver))
      }
    }
    # Note: dependencies not yet in requirements.txt are allowed through —
    # they will be added automatically with their CRAN version below.
  }

  if (length(dep_conflicts) > 0) {
    cat("❌ DEPENDENCY VERSION CONFLICT DETECTED\n\n")
    cat(sprintf("   %s==%s requires dependencies whose CRAN versions\n", add_name, add_ver))
    cat("   differ from the versions pinned in R_requirements.txt:\n\n")
    cat(paste(dep_conflicts, collapse = "\n"), "\n\n")
    cat("   Resolution options:\n")
    cat("   1. Update the pinned version(s) in R_requirements.txt to match\n")
    cat("      CRAN, then run --add again.\n")
    cat("   2. Choose a different version of", add_name, "whose dependencies\n")
    cat("      are compatible with your current pins.\n")
    cat("   3. Run --rebuild to update the entire environment at once\n")
    cat("      (note: this requires full re-validation).\n\n")
    stop("❌ Aborting --add due to dependency conflict. No files were changed.")
  }

  cat("✅ No dependency conflicts detected.\n\n")

  # Collect any new dependencies not yet in R_requirements.txt
  new_implicit_deps <- character(0)
  for (dep in all_deps) {
    if (dep == add_name) next
    if (!dep %in% pkg_names && dep %in% rownames(cran_pkg_info)) {
      new_implicit_deps <- c(new_implicit_deps, dep)
    }
  }
  if (length(new_implicit_deps) > 0) {
    cat("ℹ️  New implicit dependencies will be added to R_requirements.txt:\n")
    for (dep in new_implicit_deps) {
      cat(sprintf("   %s==%s\n", dep, cran_pkg_info[dep, "Version"]))
    }
    cat("\n")
  }

  # Download new package + all dependencies into existing repo
  cat(sprintf("\U0001F310 Downloading %s==%s + dependencies from %s...\n",
              add_name, add_ver, names(PKG_REPOS)[1]))

  if (USE_MINICRAN_BINARY) {
    makeRepo(all_deps,
             path  = LOCAL_REPO,
             repos = PKG_REPOS,
             type  = c("source", BINARY_TYPE),
             quiet = FALSE)
  } else {
    makeRepo(all_deps,
             path  = LOCAL_REPO,
             repos = PKG_REPOS,
             type  = "source",
             quiet = FALSE)
    cat(sprintf("\U0001F4E6 Downloading binary packages from %s...\n",
                paste(PKG_REPOS, collapse = ", then ")))
    download_binaries_manually(all_deps, LOCAL_REPO, PKG_REPOS, MACOS_PLATFORM, r_minor)
  }

  # Rebuild PACKAGES index
  if (MACOS_PLATFORM == "windows") {
    tools::write_PACKAGES(
      file.path(LOCAL_REPO, "bin/windows", "contrib", r_minor),
      type = "win.binary"
    )
  } else {
    tools::write_PACKAGES(
      file.path(LOCAL_REPO, "bin/macosx", MACOS_PLATFORM, "contrib", r_minor),
      type = "mac.binary"
    )
  }
  cat("📋 PACKAGES index rebuilt.\n\n")

  # Update R_requirements.txt — target package first, then new implicit deps
  req_lines      <- readLines(REQ_FILE, warn = FALSE)
  existing_entry <- grep(paste0("^", add_name, "=="), req_lines)
  new_entry      <- paste0(add_name, "==", add_ver)

  if (length(existing_entry) > 0) {
    req_lines[existing_entry] <- new_entry
  } else {
    req_lines <- c(req_lines, new_entry)
  }

  # Append any new implicit dependencies
  for (dep in new_implicit_deps) {
    dep_ver   <- cran_pkg_info[dep, "Version"]
    dep_entry <- paste0(dep, "==", dep_ver)
    if (!any(grepl(paste0("^", dep, "=="), req_lines))) {
      req_lines <- c(req_lines, dep_entry)
    }
  }

  writeLines(req_lines, REQ_FILE)
  cat(sprintf("📝 R_requirements.txt updated: %s==%s\n", add_name, add_ver))
  if (length(new_implicit_deps) > 0) {
    for (dep in new_implicit_deps) {
      cat(sprintf("📝 R_requirements.txt added implicit dep: %s==%s\n",
                  dep, cran_pkg_info[dep, "Version"]))
    }
  }
  cat("\n")

  # Reload pkg_versions to include the new package
  pkg_versions <- read_requirements(REQ_FILE)
  pkg_names    <- names(pkg_versions)

  # Recompute checksums for entire repo
  cat("🔒 Recomputing repo checksums...\n")
  repo_files <- list.files(LOCAL_REPO, recursive = TRUE, full.names = TRUE)
  repo_files <- repo_files[!grepl("VERSIONS.txt|checksums.txt", repo_files)]
  checksums  <- tools::md5sum(repo_files)
  writeLines(paste(checksums, repo_files), file.path(LOCAL_REPO, "checksums.txt"))
  cat("✅ checksums.txt updated.\n\n")

  # Update VERSIONS.txt
  renv_version   <- as.character(packageVersion("renv"))
  manifest_lines <- c(
    "# Pinned package versions — do not edit manually",
    paste0("# Generated: ", Sys.time()),
    paste0("# R version: ", paste(R.version$major,
                                  sub("\\..*", "", R.version$minor), sep = ".")),
    "",
    paste(pkg_names, pkg_versions, sep = " == "),
    paste("renv", renv_version, sep = " == ")
  )
  writeLines(manifest_lines, file.path(LOCAL_REPO, "VERSIONS.txt"))
  cat("📋 VERSIONS.txt updated.\n\n")
}

# ---------------------------------------------------------------------------
# BUILD mode — download all packages from internet into local repo
# ---------------------------------------------------------------------------

if (MODE == "BUILD") {

  cat(sprintf("\U0001F310 BUILD_REPO=true - downloading packages from %s...\n",
              paste(names(PKG_REPOS), collapse = ", then ")))
  cat(sprintf("   Destination: %s\n\n", LOCAL_REPO))

  if (!requireNamespace("miniCRAN", quietly = TRUE)) {
    install.packages("miniCRAN", repos = CRAN_MIRROR)
  }
  library(miniCRAN)

  deps <- pkgDep(pkg_names, repos = PKG_REPOS,
                 type = "source", suggests = FALSE)
  cat("📦 Packages + dependencies to download:\n")
  print(deps)
  cat("\n")

  if (!dir.exists(LOCAL_REPO)) dir.create(LOCAL_REPO, recursive = TRUE)

  if (USE_MINICRAN_BINARY) {
    makeRepo(deps,
             path  = LOCAL_REPO,
             repos = PKG_REPOS,
             type  = c("source", BINARY_TYPE))
  } else {
    makeRepo(deps,
             path  = LOCAL_REPO,
             repos = PKG_REPOS,
             type  = "source")
    cat(sprintf("\U0001F4E6 Downloading binary packages from %s...\n",
                paste(PKG_REPOS, collapse = ", then ")))
    download_binaries_manually(deps, LOCAL_REPO, PKG_REPOS, MACOS_PLATFORM, r_minor)
  }

  # Ensure renv is in the local repo.
  #
  # renv is the tool that builds the validated library, so its version belongs
  # in the validated configuration. It used to be installed as "latest from
  # CRAN", meaning the build tool was whatever CRAN served that day -- unpinned
  # and unrecorded in renv.lock. Pin it in R_requirements.txt like any other
  # package. The unpinned branch remains only for repositories predating this.
  # Pinned in admin/renv_version.txt, alongside r_version.txt and
  # python_version.txt. Deliberately NOT in R_requirements.txt: everything there
  # is installed into the validated library and version-checked, and renv is a
  # build tool rather than an analysis package.
  renv_pin_file <- "renv_version.txt"   # relative, like REQ_FILE (cwd = admin/)
  renv_pin <- if (file.exists(renv_pin_file)) trimws(readLines(renv_pin_file, warn = FALSE))[1] else NULL
  if (is.null(renv_pin) || !nzchar(renv_pin)) {
    cat("\U0001F4E6 renv is NOT pinned - installing latest from CRAN.\n")
    cat("   Create admin/renv_version.txt to pin the build tool.\n")
    install.packages("renv", repos = PKG_REPOS)
    renv_version <- as.character(packageVersion("renv"))
  } else {
    renv_version <- renv_pin
    cat(sprintf("\U0001F4E6 renv pinned at %s\n", renv_version))
    if (!requireNamespace("renv", quietly = TRUE) ||
        as.character(packageVersion("renv")) != renv_version) {
      install.packages("renv", repos = PKG_REPOS)
    }
  }
  if (MACOS_PLATFORM == "windows") {
    renv_binary   <- sprintf("renv_%s.zip", renv_version)
    renv_url      <- sprintf(
      "https://cran.r-project.org/bin/windows/contrib/%s/%s",
      r_minor, renv_binary
    )
    renv_dest     <- file.path(LOCAL_REPO, "bin/windows", "contrib", r_minor,
                               renv_binary)
    pkg_index_dir <- file.path(LOCAL_REPO, "bin/windows", "contrib", r_minor)
    pkg_index_type <- "win.binary"
  } else {
    renv_binary   <- sprintf("renv_%s.tgz", renv_version)
    renv_url      <- sprintf(
      "https://cran.r-project.org/bin/macosx/%s/contrib/%s/%s",
      MACOS_PLATFORM, r_minor, renv_binary
    )
    renv_dest     <- file.path(LOCAL_REPO,
                               "bin/macosx", MACOS_PLATFORM, "contrib", r_minor,
                               renv_binary)
    pkg_index_dir  <- file.path(LOCAL_REPO, "bin/macosx", MACOS_PLATFORM,
                                "contrib", r_minor)
    pkg_index_type <- "mac.binary"
  }

  dir.create(dirname(renv_dest), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(renv_dest)) {
    cat(sprintf("📦 Downloading renv %s into local repo...\n", renv_version))
    tryCatch(
      download.file(renv_url, destfile = renv_dest, mode = "wb", quiet = TRUE),
      error = function(e) stop(paste("❌ Failed to download renv:", e$message))
    )
    cat("✅ renv added to local repo.\n")
  } else {
    cat(sprintf("✅ renv %s already in local repo.\n", renv_version))
  }

  # Rebuild PACKAGES index
  tools::write_PACKAGES(pkg_index_dir, type = pkg_index_type)
  cat("📋 PACKAGES index updated.\n\n")

  # Write VERSIONS.txt
  manifest_lines <- c(
    "# Pinned package versions — do not edit manually",
    paste0("# Generated: ", Sys.time()),
    paste0("# R version: ", paste(R.version$major,
                                  sub("\\..*", "", R.version$minor), sep = ".")),
    "",
    paste(pkg_names, pkg_versions, sep = " == "),
    paste("renv", renv_version, sep = " == ")
  )
  writeLines(manifest_lines, file.path(LOCAL_REPO, "VERSIONS.txt"))

  # Compute checksums
  repo_files <- list.files(LOCAL_REPO, recursive = TRUE, full.names = TRUE)
  repo_files <- repo_files[!grepl("VERSIONS.txt|checksums.txt", repo_files)]
  checksums  <- tools::md5sum(repo_files)
  writeLines(paste(checksums, repo_files), file.path(LOCAL_REPO, "checksums.txt"))

  cat(sprintf("✅ Local repo built at: %s\n", LOCAL_REPO))
  cat("📋 VERSIONS.txt written\n")
  cat("🔒 checksums.txt written\n\n")

  # --populate-platform: the repo now holds binaries for a platform that is not
  # this machine's. Installing them into the local renv library would be wrong,
  # so stop here. Used to build the Windows / Intel-macOS trees of the published
  # package repository from a single build host.
  if (POPULATE_ONLY) {
    cat(sprintf("\U0001F4E6 Populated '%s' binaries only — skipping renv install.\n",
                MACOS_PLATFORM))
    cat("   Re-run without --populate-platform to install for this machine.\n\n")
    quit(save = "no", status = 0)
  }

} else if (MODE == "INSTALL") {

  # ---------------------------------------------------------------------------
  # INSTALL mode — verify existing repo integrity
  # ---------------------------------------------------------------------------

  cat(sprintf("📂 Using existing local repo: %s\n\n", LOCAL_REPO))

  if (!dir.exists(LOCAL_REPO)) {
    stop(paste0(
      "❌ Local repo not found at: ", LOCAL_REPO, "\n",
      "   Run admin_install_R --rebuild first to create it."
    ))
  }

  checksum_file <- file.path(LOCAL_REPO, "checksums.txt")
  if (file.exists(checksum_file)) {
    cat("🔒 Verifying repo integrity...\n")
    stored     <- read.table(checksum_file, header = FALSE,
                             col.names = c("hash", "path"),
                             stringsAsFactors = FALSE)
    current    <- tools::md5sum(stored$path)
    mismatches <- stored$path[current != stored$hash]
    if (length(mismatches) > 0) {
      stop(paste0(
        "❌ Repo integrity check FAILED. Modified or missing files:\n",
        paste0("   ", mismatches, collapse = "\n")
      ))
    }
    cat("✅ Repo integrity verified.\n\n")
  } else {
    warning("⚠️  No checksums.txt found in repo — skipping integrity check.")
  }
}

# ---------------------------------------------------------------------------
# Set local repo as sole package source  (all modes)
# ---------------------------------------------------------------------------

if (.Platform$OS.type == "windows") {
  local_repo_url <- paste0("file:///", gsub("\\\\", "/", normalizePath(LOCAL_REPO)))
} else {
  local_repo_url <- paste0("file://", normalizePath(LOCAL_REPO))
}

options(
  repos                                = c(LOCAL = local_repo_url),
  pkgType                              = "binary",
  install.packages.compile.from.source = "never"
)

cat(sprintf("📌 Installing from: %s\n\n", local_repo_url))

# ---------------------------------------------------------------------------
# Install renv if not present
# ---------------------------------------------------------------------------

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = local_repo_url)
}

# ---------------------------------------------------------------------------
# Write renv.lock from current pkg_versions  (all modes)
# ---------------------------------------------------------------------------

r_version <- paste(R.version$major, R.version$minor, sep = ".")

pkg_entries <- paste(
  sapply(pkg_names, function(nm) {
    sprintf(
      '    "%s": {\n      "Package": "%s",\n      "Version": "%s",\n      "Source": "Repository",\n      "Repository": "LOCAL"\n    }',
      nm, nm, pkg_versions[[nm]]
    )
  }),
  collapse = ",\n"
)

lock_json <- sprintf(
  '{\n  "R": {\n    "Version": "%s"\n  },\n  "Packages": {\n%s\n  }\n}',
  r_version, pkg_entries
)

lock_path <- "renv.lock"   # admin/ is the working dir — this is admin/renv.lock

writeLines(lock_json, lock_path)
cat(sprintf("📋 renv.lock written to: %s\n\n", normalizePath(lock_path)))

# ---------------------------------------------------------------------------
# Restore renv library from lock  (all modes)
# ---------------------------------------------------------------------------

r_ver        <- paste0("R-", R.version$major, ".",
                       sub("\\..*", "", R.version$minor))
platform     <- R.version$platform
platform_dir <- Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos")
lib_path     <- file.path(RENV_HOME, "renv", "library", platform_dir, r_ver, platform)
dir.create(lib_path, recursive = TRUE, showWarnings = FALSE)

cat("📦 Installing packages into validated library...\n")
install.packages(
  pkg_names,
  lib      = lib_path,
  repos    = local_repo_url,
  type     = "binary"
)

# ---------------------------------------------------------------------------
# Verify installed versions
# ---------------------------------------------------------------------------

cat("\n🔍 Verifying installed versions:\n")
all_ok <- TRUE
for (nm in pkg_names) {
  required  <- gsub("-", ".", pkg_versions[[nm]])
  installed <- tryCatch(as.character(packageVersion(nm, lib.loc = lib_path)), error = function(e) NA)
  if (is.na(installed)) {
    cat(sprintf("   ❌ %-20s NOT INSTALLED\n", nm))
    all_ok <- FALSE
  } else if (installed != required) {
    cat(sprintf("   ❌ %-20s installed: %s  required: %s\n",
                nm, installed, required))
    all_ok <- FALSE
  } else {
    cat(sprintf("   ✅ %-20s %s\n", nm, installed))
  }
}

if (!all_ok) stop("❌ Version mismatch detected. Check errors above.")

cat("\n✅ renv environment successfully created\n")
cat(sprintf("📦 R version  : %s\n", R.version.string))
cat(sprintf("📂 Repo       : %s\n", LOCAL_REPO))
cat(sprintf("📋 Packages   : %s\n", paste(pkg_names, collapse = ", ")))
if (MODE == "ADD") {
  cat(sprintf("➕ Added      : %s==%s\n", add_name, add_ver))
}

