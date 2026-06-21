# jr_helpers.R
# Sourced by JR Anchored scripts at startup (via jrrun).
# Provides jr_log_output_hashes() for logging output file SHA-256 hashes
# to the run log after a script completes.
#
# Requires env vars set by jrrun:
#   JR_PROJECT_ROOT  — project root directory
#   PROJECT_ID       — project identifier (used to locate run.log)

jr_log_output_hashes <- function(files) {
  project_id <- Sys.getenv("PROJECT_ID")
  if (nchar(project_id) == 0L) {
    warning("jr_log_output_hashes: PROJECT_ID not set — output hashes not logged.")
    return(invisible(NULL))
  }
  log_file <- file.path(path.expand("~"), ".jrscript", project_id, "run.log")
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  for (f in files) {
    if (!file.exists(f)) {
      warning(sprintf("jr_log_output_hashes: file not found, skipping: %s", f))
      next
    }
    # Use the shared cross-platform hasher: shasum on macOS/Linux, with a
    # certutil fallback on Windows where R.exe cannot reach shasum on PATH.
    hash <- jr_sha256_file(f)
    if (is.na(hash)) {
      warning(sprintf("jr_log_output_hashes: could not hash file: %s", f))
      next
    }
    cat(sprintf("%s\tjrrun_output\t%s\t%s\n",
                timestamp, basename(f), hash),
        file = log_file, append = TRUE)
  }
  invisible(NULL)
}

jr_log_report <- function(docx_path) {
  project_id <- Sys.getenv("PROJECT_ID")
  if (nchar(project_id) == 0L) return(invisible(NULL))
  log_file  <- file.path(path.expand("~"), ".jrscript", project_id, "run.log")
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  cat(sprintf("%s\tjrrun_report\t%s\n", timestamp, basename(docx_path)),
      file = log_file, append = TRUE)
  invisible(NULL)
}

jr_sha256_file <- function(path) {
  fp <- normalizePath(path, winslash = "/", mustWork = FALSE)
  raw <- tryCatch(
    system2("shasum", args = c("-a", "256", fp), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)
  )
  if (length(raw) > 0L && nchar(raw[1L]) > 0L) {
    return(strsplit(raw[1L], "\\s+")[[1L]][1L])
  }
  if (.Platform$OS.type == "windows") {
    fp_win <- normalizePath(path, winslash = "\\", mustWork = FALSE)
    raw2 <- tryCatch(
      system2("certutil", args = c("-hashfile", fp_win, "SHA256"),
              stdout = TRUE, stderr = FALSE),
      error = function(e) character(0)
    )
    if (length(raw2) >= 2L) {
      # certutil prints the hash on line 2; some versions space-separate the
      # byte pairs — strip non-hex chars and require a full 64-char SHA-256.
      h <- gsub("[^0-9a-fA-F]", "", raw2[2L])
      if (nchar(h) == 64L) return(tolower(h))
    }
  }
  NA_character_
}

jr_python_bin <- function() {
  # Force UTF-8 I/O for the Python subprocess — prevents cp1252 UnicodeEncodeError
  # on Windows when jr_pack.py prints emoji (e.g. ✅) to stdout.
  Sys.setenv(PYTHONUTF8 = "1")
  if (.Platform$OS.type != "windows") return("python3")
  # Locate the real python.exe via admin/python_version.txt (same logic as jrrun)
  ver_file <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "admin", "python_version.txt")
  if (file.exists(ver_file)) {
    ver <- trimws(readLines(ver_file, warn = FALSE)[1L])
    mm  <- paste(strsplit(ver, "\\.")[[1L]][1:2], collapse = "")
    py  <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "Programs",
                     "Python", paste0("Python", mm), "python.exe")
    if (file.exists(py)) return(normalizePath(py, winslash = "/"))
  }
  "python"  # fallback: python in PATH
}
