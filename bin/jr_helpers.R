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

# --- Output directory for artifacts a script writes (plots, reports, data)
# Usage: file.path(jr_out_dir(), "myplot.png")
#
# Honours $JR_OUT_DIR, defaulting to ~/Downloads. The default keeps end-user
# behaviour and every help file unchanged; the OQ runners set the variable so
# a test run's artifacts land in a per-run folder under ~/.jrscript/ instead
# of flooding the user's Downloads.
#
# Creates the directory if it does not exist, so a caller can write straight
# into the returned path. Falls back to ~/Downloads if the configured
# directory cannot be created — never returns a path that does not exist.
jr_out_dir <- function() {
  d <- Sys.getenv("JR_OUT_DIR", unset = "")
  if (!nzchar(d)) d <- path.expand("~/Downloads")
  d <- path.expand(d)
  if (!dir.exists(d)) {
    ok <- dir.create(d, recursive = TRUE, showWarnings = FALSE)
    if (!ok && !dir.exists(d)) {
      fallback <- path.expand("~/Downloads")
      warning(sprintf(
        "JR_OUT_DIR '%s' could not be created; falling back to %s", d, fallback))
      dir.create(fallback, recursive = TRUE, showWarnings = FALSE)
      return(fallback)
    }
  }
  d
}

# --- JSON string literal for report sidecars
# Returns a quoted, escaped JSON string, or the literal null for NULL / NA.
# Escapes backslash, double quote and control characters (RFC 8259), so file
# names, column names and Windows paths always produce valid JSON.
jr_json_str <- function(x) {
  if (is.null(x) || (length(x) == 1L && is.na(x))) return("null")
  s <- enc2utf8(as.character(x))
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub("\"", "\\\"", s, fixed = TRUE)
  s <- gsub("\n", "\\n",  s, fixed = TRUE)
  s <- gsub("\r", "\\r",  s, fixed = TRUE)
  s <- gsub("\t", "\\t",  s, fixed = TRUE)
  # any remaining control characters U+0000..U+001F as \u00XX
  ctl <- utf8ToInt(s)
  if (any(ctl < 32L)) {
    s <- paste(vapply(ctl, function(cp) if (cp < 32L) sprintf("\\u%04x", cp)
                      else intToUtf8(cp), character(1)), collapse = "")
  }
  paste0("\"", s, "\"")
}

# ===========================================================================
# Shared infrastructure for all jrc_* R scripts (code review 2026-10, X-01..X-10)
# ===========================================================================

# --- Validated renv library (X-01)
# Every script starts with the same three-line preamble:
#   if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT")))
#     stop("❌ RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
#   source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
#   jr_use_renv_library()
# This function puts the project's renv library first on the library path,
# so library() calls load the pinned, hash-verified packages.
jr_use_renv_library <- function() {
  renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
  if (!nzchar(renv_lib)) {
    stop("❌ RENV_PATHS_ROOT is not set. Run this script via jrrun or its wrapper.")
  }
  r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
  lib_path <- file.path(renv_lib, "renv", "library",
                        Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"),
                        r_ver, R.version$platform)
  if (!dir.exists(lib_path)) {
    stop(paste("❌ renv library not found at:", lib_path))
  }
  .libPaths(c(lib_path, .libPaths()))
  invisible(lib_path)
}

# --- Results output (X-10)
# Results go to stdout; errors (stop) and warnings (warning) stay on stderr.
# Drop-in for message(): arguments are pasted without a separator and a
# newline is added unless appendLF = FALSE.
jr_say <- function(..., appendLF = TRUE) {
  cat(..., if (appendLF) "\n", sep = "")
  invisible(NULL)
}

# --- Excluded rows (X-06)
# Report how many rows were left out of an analysis and why, so data are
# never dropped silently. ids (optional) are listed, up to 10.
jr_report_excluded <- function(n, reason = "missing or non-numeric value", ids = NULL) {
  if (is.na(n) || n <= 0) return(invisible(0L))
  id_txt <- if (length(ids) > 0) {
    paste0(": ", paste(utils::head(as.character(ids), 10), collapse = ", "),
           if (length(ids) > 10) sprintf(" ... (+%d more)", length(ids) - 10) else "")
  } else ""
  jr_say(sprintf("⚠️  %d row(s) excluded (%s)%s", n, reason, id_txt))
  invisible(n)
}

# --- Number formatting for file names (shared by the jrc_gen_* scripts)
jr_fmt_num <- function(x) {
  s <- format(x, scientific = FALSE)
  s <- sub("(\\.\\d*?)0+$", "\\1", s)   # drop trailing zeros after the point
  sub("\\.$", "", s)                     # drop a trailing decimal point
}

# --- HTML / JSON helpers for reports (X-03, X-04)
jr_html_escape <- function(s) {
  s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
  s <- gsub("<", "&lt;",   s, fixed = TRUE)
  s <- gsub(">", "&gt;",   s, fixed = TRUE)
  gsub("\"", "&quot;", s, fixed = TRUE)
}

jr_json_num <- function(x, fmt = "%.6g") {
  if (is.null(x) || (length(x) == 1L && is.na(x))) "null" else sprintf(fmt, as.numeric(x))
}

jr_json_bool <- function(x) if (isTRUE(x)) "true" else "false"

# --- Validation Pack report availability (X-07)
# A requested --report that cannot be produced is a failed run: explain,
# log the hashes of anything already written, and exit with status 1.
jr_report_template_path <- function(template) {
  file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates", template)
}

jr_require_report_template <- function(template, log_files = character(0)) {
  if (file.exists(jr_report_template_path(template))) return(invisible(TRUE))
  message("❌  --report is not available.")
  message("")
  message("   This feature requires the JR Anchored Validation Pack.")
  message("   To enable it, install the Validation Pack and run install.sh.")
  message(paste0("   The installer copies ", template, " into:"))
  message(paste0("     ", dirname(jr_report_template_path(template))))
  message("")
  message("   Contact dwylup.com to obtain the JR Anchored Validation Pack.")
  message("")
  if (length(log_files) > 0) jr_log_output_hashes(log_files)
  quit(save = "no", status = 1)
}

# --- Word report via the Validation Pack (X-03, X-07)
# Converts the JSON sidecar with `jr_pack deliverables <deliverable>`. On
# success the intermediate HTML/JSON are removed and the .docx is logged; on
# failure both are kept, a retry command is shown and the run exits with
# status 1 (after logging log_files). Without the pack CLI, the HTML and JSON
# are kept and the manual command is shown.
jr_run_pack <- function(json_path, deliverable, html_path = NULL,
                        log_files = character(0)) {
  pack_py <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "pack", "jr_pack.py")
  if (!file.exists(pack_py)) {
    jr_say(sprintf("   Run: jr_pack deliverables %s --json %s", deliverable, json_path))
    return(invisible(NA))
  }
  ret <- system2(jr_python_bin(),
                 args   = c(shQuote(pack_py), "deliverables", deliverable,
                            "--json", shQuote(json_path)),
                 stdout = TRUE, stderr = TRUE)
  status <- attr(ret, "status")
  if (is.null(status)) status <- 0L
  jr_say(paste(ret, collapse = "\n"))
  if (status != 0L) {
    message(sprintf("   Retry manually: jr_pack deliverables %s --json %s", deliverable, json_path))
    if (length(log_files) > 0) jr_log_output_hashes(log_files)
    quit(save = "no", status = 1)
  }
  docx_line <- grep("saved to:", ret, value = TRUE)
  if (length(docx_line) > 0L) jr_log_report(trimws(sub(".*saved to:\\s*", "", docx_line[1L])))
  if (!is.null(html_path) && file.exists(html_path)) file.remove(html_path)
  if (file.exists(json_path)) file.remove(json_path)
  invisible(TRUE)
}

# --- Plot styling (X-03)
# Common ggplot theme for module PNGs; scripts add their own extras with
# `+ ggplot2::theme(...)`.
jr_theme <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = "#FFFFFF", color = NA),
      panel.background = ggplot2::element_rect(fill = "#FFFFFF", color = NA),
      panel.grid.major = ggplot2::element_line(color = "#EEEEEE"),
      panel.grid.minor = ggplot2::element_blank(),
      plot.title       = ggplot2::element_text(size = base_size, face = "bold"),
      plot.subtitle    = ggplot2::element_text(size = base_size - 2, color = "#555555"),
      axis.text        = ggplot2::element_text(size = base_size - 2),
      axis.title       = ggplot2::element_text(size = base_size - 1)
    )
}

# Save ggplot panels under a coloured title strip, as one PNG.
#   plots   list of ggplot objects, filled row by row into nrow x ncol
#   heights optional relative row heights (length nrow)
jr_save_titled_png <- function(out_file, title, plots, nrow = 1, ncol = 1,
                               width = 2400, height = 1600, res = 180,
                               strip = 0.06, strip_fill = "#2E5BBA",
                               heights = NULL) {
  grDevices::png(out_file, width = width, height = height, res = res, bg = "#FFFFFF")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(
    nrow = 2, ncol = 1, heights = grid::unit(c(strip, 1 - strip), "npc"))))
  grid::pushViewport(grid::viewport(layout.pos.row = 1))
  grid::grid.rect(gp = grid::gpar(fill = strip_fill, col = NA))
  grid::grid.text(title, gp = grid::gpar(col = "white", fontsize = 10, fontface = "bold"))
  grid::popViewport()
  lay <- if (is.null(heights)) grid::grid.layout(nrow = nrow, ncol = ncol)
         else grid::grid.layout(nrow = nrow, ncol = ncol,
                                heights = grid::unit(heights, "null"))
  grid::pushViewport(grid::viewport(layout.pos.row = 2, layout = lay))
  for (k in seq_along(plots)) {
    r <- (k - 1) %/% ncol + 1; cc <- (k - 1) %% ncol + 1
    print(plots[[k]], vp = grid::viewport(layout.pos.row = r, layout.pos.col = cc))
  }
  grid::popViewport()
  invisible(out_file)
}

# --- Statistical building blocks shared between scripts
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_stats_helpers.R"))
