# ==============================
# Admin setup script for renv
# R package versions in R_requirements.txt
#
# run as: Rscript --vanilla admin_R_install.R
#
# Modes:
#   BUILD_REPO=true  Rscript --vanilla admin_R_install.R
#     → downloads pinned packages from internet into LOCAL_REPO, then installs from it
#   BUILD_REPO=false Rscript --vanilla admin_R_install.R   (default)
#     → installs directly from LOCAL_REPO (no internet needed)
#
# R_requirements.txt format (one per line, comments with #):
#   ggplot2==3.5.2
#   MASS==7.3.65
#   e1071==1.7.16
#   tolerance==2.0.0
#
# ==============================

# ---------------------------------------------------------------------------
# Configuration — edit these paths to match your environment
# ---------------------------------------------------------------------------

LOCAL_REPO <- Sys.getenv("LOCAL_REPO")
if (LOCAL_REPO == "") {
  stop(paste(
    "❌ LOCAL_REPO environment variable is not set.",
    "   Call this R script only via zsh-shell script admin_R_install ",
    "   to ensure correct envrionment variable setting. ",
    sep = "\n"
  ))
}
BUILD_REPO  <- Sys.getenv("BUILD_REPO",
               unset = "false") == "true"           # set to true to (re)build repo from internet
CRAN_MIRROR <- "https://cloud.r-project.org"        # only used when BUILD_REPO=true

# Binary type for your platform — change if not on macOS Apple Silicon
BINARY_TYPE <- "mac.binary.big-sur-arm64"

# ---------------------------------------------------------------------------
# Parse R_requirements.txt  (format: packagename==version)
# ---------------------------------------------------------------------------

REQ_FILE <- "R_requirements.txt"
if (!file.exists(REQ_FILE)) {
  stop("❌ R_requirements.txt not found")
}

lines <- readLines(REQ_FILE, warn = FALSE)
lines <- trimws(lines)
lines <- lines[lines != "" & !startsWith(lines, "#")]

if (length(lines) == 0) {
  stop("❌ No packages found in R_requirements.txt")
}

# Split "pkg==version" into a named vector  c(pkg = "version")
pkg_versions <- setNames(
  sub(".*==", "", lines),    # everything after ==
  sub("==.*", "", lines)     # everything before ==
)

# Validate format
bad <- lines[!grepl("==", lines)]
if (length(bad) > 0) {
  stop(paste0(
    "❌ R_requirements.txt entries must use 'package==version' format.\n",
    "   Offending lines: ", paste(bad, collapse = ", ")
  ))
}

pkg_names <- names(pkg_versions)

cat("📋 Required packages:\n")
for (nm in pkg_names) cat(sprintf("   %-20s %s\n", nm, pkg_versions[nm]))
cat("\n")

# ---------------------------------------------------------------------------
# Optionally (re)build the local miniCRAN repo from the internet
# ---------------------------------------------------------------------------

if (BUILD_REPO) {

  cat("🌐 BUILD_REPO=true — downloading packages from CRAN into local repo...\n")
  cat(sprintf("   Destination: %s\n\n", LOCAL_REPO))

  if (!requireNamespace("miniCRAN", quietly = TRUE)) {
    install.packages("miniCRAN", repos = CRAN_MIRROR)
  }
  library(miniCRAN)

  # Expand to include all recursive dependencies
  deps <- pkgDep(pkg_names, repos = CRAN_MIRROR,
                 type = "source", suggests = FALSE)
  cat("📦 Packages + dependencies to download:\n")
  print(deps)
  cat("\n")

  # Create or update the local repo
  if (!dir.exists(LOCAL_REPO)) dir.create(LOCAL_REPO, recursive = TRUE)

  makeRepo(deps,
           path  = LOCAL_REPO,
           repos = CRAN_MIRROR,
           type  = c("source", BINARY_TYPE))

# --- Ensure renv package is in the local repo ---
  # renv is not in R_requirements.txt but is needed by user scripts to
  # bootstrap the environment. Download it explicitly so the local repo
  # is fully self-contained.
  renv_version <- as.character(packageVersion("renv"))
  renv_binary  <- sprintf("renv_%s.tgz", renv_version)
  renv_url     <- sprintf(
    "https://cran.r-project.org/bin/macosx/big-sur-arm64/contrib/4.5/%s",
    renv_binary
  )
  renv_dest <- file.path(LOCAL_REPO,
                         "bin/macosx/big-sur-arm64/contrib/4.5",
                         renv_binary)

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

  # Rebuild the PACKAGES index to include renv
  tools::write_PACKAGES(
    file.path(LOCAL_REPO, "bin/macosx/big-sur-arm64/contrib/4.5"),
    type = "mac.binary"
  )
  cat("📋 PACKAGES index updated.\n\n")

  # Write version manifest for audit trail
  manifest_lines <- c(
    "# Pinned package versions — do not edit manually",
    paste0("# Generated: ", Sys.time()),
    paste0("# R version: ", paste(R.version$major,
                                  sub("\\..*", "", R.version$minor),
                                  sep = ".")),
    "",
    paste(pkg_names, pkg_versions, sep = " == "),

    paste("renv", renv_version, sep = " == ")
  )
  writeLines(manifest_lines, file.path(LOCAL_REPO, "VERSIONS.txt"))

  # Compute and write checksums for integrity verification
  repo_files <- list.files(LOCAL_REPO, recursive = TRUE, full.names = TRUE)
  repo_files <- repo_files[!grepl("VERSIONS.txt|checksums.txt", repo_files)]
  checksums  <- tools::md5sum(repo_files)
  writeLines(paste(checksums, repo_files), file.path(LOCAL_REPO, "checksums.txt"))

  cat(sprintf("\n✅ Local repo built at: %s\n", LOCAL_REPO))
  cat("📋 Version manifest written to VERSIONS.txt\n")
  cat("🔒 Checksums written to checksums.txt\n\n")

} else {

  cat(sprintf("📂 BUILD_REPO=false — using existing local repo: %s\n\n", LOCAL_REPO))

  # Verify repo exists
  if (!dir.exists(LOCAL_REPO)) {
    stop(paste0(
      "❌ Local repo not found at: ", LOCAL_REPO, "\n",
      "   Run with BUILD_REPO=true first to create it."
    ))
  }

  # Integrity check against stored checksums
  checksum_file <- file.path(LOCAL_REPO, "checksums.txt")
  if (file.exists(checksum_file)) {
    cat("🔒 Verifying repo integrity...\n")
    stored   <- read.table(checksum_file, header = FALSE,
                           col.names = c("hash", "path"), stringsAsFactors = FALSE)
    current  <- tools::md5sum(stored$path)
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
# Set local repo as the sole package source
# ---------------------------------------------------------------------------

local_repo_url <- paste0("file://", normalizePath(LOCAL_REPO))

options(
  repos                                = c(LOCAL = local_repo_url),
  pkgType                              = "binary",
  install.packages.compile.from.source = "never"
)

cat(sprintf("📌 Installing from: %s\n\n", local_repo_url))

# ---------------------------------------------------------------------------
# Clean and reinitialise renv
# ---------------------------------------------------------------------------

if (dir.exists("renv")) {
  message("⚠️  Existing renv folder detected — removing")
  unlink("renv", recursive = TRUE)
}
if (file.exists("renv.lock")) {
  unlink("renv.lock")
}

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = local_repo_url)
}
#renv::init(bare = TRUE)

# ---------------------------------------------------------------------------
# Install pinned packages from local repo via renv::restore()
# ---------------------------------------------------------------------------

cat("📦 Installing packages from local repo via renv.lock...\n")

# Build renv.lock manually — avoids jsonlite dependency before renv is populated
r_version <- paste(R.version$major, R.version$minor, sep = ".")

pkg_entries <- paste(
  sapply(pkg_names, function(nm) {
    sprintf('    "%s": {\n      "Package": "%s",\n      "Version": "%s",\n      "Source": "Repository",\n      "Repository": "LOCAL"\n    }',
            nm, nm, pkg_versions[[nm]])
  }),
  collapse = ",\n"
)

lock_json <- sprintf(
  '{\n  "R": {\n    "Version": "%s"\n  },\n  "Packages": {\n%s\n  }\n}',
  r_version, pkg_entries
)

writeLines(lock_json, "renv.lock")
cat("📋 renv.lock written.\n\n")

renv::restore(lockfile = "renv.lock",
              repos    = c(LOCAL = local_repo_url),
              prompt   = FALSE)
              
# ---------------------------------------------------------------------------
# Verify installed versions match requirements
# ---------------------------------------------------------------------------

cat("\n🔍 Verifying installed versions:\n")
all_ok <- TRUE
for (nm in pkg_names) {
  required  <- gsub("-", ".", pkg_versions[[nm]])   # normalise: 7.3-65 -> 7.3.65
  installed <- tryCatch(as.character(packageVersion(nm)), error = function(e) NA)
  if (is.na(installed)) {
    cat(sprintf("   ❌ %-20s NOT INSTALLED\n", nm))
    all_ok <- FALSE
  } else if (installed != required) {
    cat(sprintf("   ❌ %-20s installed: %s  required: %s\n", nm, installed, required))
    all_ok <- FALSE
  } else {
    cat(sprintf("   ✅ %-20s %s\n", nm, installed))
  }
}

if (!all_ok) {
  stop("❌ Version mismatch detected — aborting snapshot. Check errors above.")
}

cat("\n✅ renv environment successfully created\n")
cat(sprintf("📦 R version: %s\n", R.version.string))
cat(sprintf("📂 Repo:      %s\n", LOCAL_REPO))
cat(sprintf("📋 Packages:  %s\n", paste(pkg_names, collapse = ", ")))
