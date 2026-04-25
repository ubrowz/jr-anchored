# =============================================================================
# jrc_spc_imr.R
# JR Validated Environment — SPC module
#
# Individuals and Moving Range (I-MR) control chart.
# Reads a CSV with columns: id, value (time-ordered).
# Computes control limits using the average moving range method,
# applies all 8 Western Electric rules to the Individuals chart,
# applies Rule 1 only to the MR chart, and saves a two-panel PNG
# to ~/Downloads/.
#
# Usage: jrc_spc_imr <data.csv> [--ucl <value>] [--lcl <value>] [--report]
#
# Arguments:
#   data.csv        CSV file with columns: id, value (time-ordered)
#   --ucl <value>   Optional: user-specified UCL for the Individuals chart
#   --lcl <value>   Optional: user-specified LCL for the Individuals chart
#   --report        Generate a Process Validation Report (requires Validation Pack)
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_spc_imr <data.csv> [--ucl <value>] [--lcl <value>] [--report]")
}

csv_file    <- args[1]
user_ucl    <- NA_real_
user_lcl    <- NA_real_
want_report <- FALSE
i <- 2
while (i <= length(args)) {
  if (args[i] == "--ucl" && i < length(args)) {
    user_ucl <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(user_ucl)) stop("--ucl must be a numeric value.")
    i <- i + 2
  } else if (args[i] == "--lcl" && i < length(args)) {
    user_lcl <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(user_lcl)) stop("--lcl must be a numeric value.")
    i <- i + 2
  } else if (args[i] == "--report") {
    want_report <- TRUE
    i <- i + 1
  } else {
    i <- i + 1
  }
}

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------
renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("❌ RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("❌ renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(base64enc)
}))

# ---------------------------------------------------------------------------
# Report generator — defined before any early exit
# ---------------------------------------------------------------------------
save_imr_report <- function(csv_file, n_obs,
                             X_bar, sigma, UCL_X, LCL_X,
                             MR_bar, UCL_MR, LCL_MR,
                             user_ucl, user_lcl,
                             n_ooc_x, n_ooc_mr,
                             ooc_x, rules_x, dat,
                             verdict, png_path) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates", "pv_report_template.html")
  if (!file.exists(sentinel)) {
    cat("⚠ --report requires the JR Anchored Validation Pack.\n")
    cat("  Install the pack and re-run to generate the Process Validation Report.\n")
    return(invisible(NULL))
  }

  ts         <- format(Sys.time(), "%Y%m%d_%H%M%S")
  report_id  <- paste0("VR-IMR-", ts)
  generated  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Embed chart
  chart_html <- ""
  if (!is.null(png_path) && file.exists(png_path)) {
    b64 <- base64enc::base64encode(png_path)
    chart_html <- sprintf(
      '<div class="chart-wrap"><img src="data:image/png;base64,%s" alt="I-MR chart"/></div>',
      b64
    )
  }

  is_pass       <- verdict == "STABLE"
  verdict_class  <- if (is_pass) "verdict verdict-pass" else "verdict verdict-fail"
  verdict_symbol <- if (is_pass) "✅" else "❌"
  verdict_color  <- if (is_pass) "color:#155724" else "color:#721c24"

  acceptance <- "Process is STABLE: zero Western Electric rule violations on the Individuals chart and zero points beyond UCL_MR on the Moving Range chart."

  spec_rows <- "<tr><td class=\"l\">Specification Limits</td><td>Not applicable — SPC stability assessment only.</td></tr>"

  ucl_note  <- if (!is.na(user_ucl)) sprintf("%.6f (user-specified)", user_ucl) else sprintf("%.6f (computed: X̅ + 3σ)", UCL_X)
  lcl_note  <- if (!is.na(user_lcl)) sprintf("%.6f (user-specified)", user_lcl) else sprintf("%.6f (computed: X̅ − 3σ)", LCL_X)

  method_rows <- paste0(
    "<tr><td class=\"l\">Method</td>",
    "<td>Shewhart Individuals and Moving Range (I-MR) control chart. Control limits computed from the average moving range (MR̅/d2, d2 = 1.128 for n = 2).</td></tr>\n",
    "<tr><td class=\"l\">Individuals Chart Rules</td>",
    "<td>All 8 Western Electric rules applied to the Individuals chart.</td></tr>\n",
    "<tr><td class=\"l\">MR Chart Rule</td>",
    "<td>Rule 1 only (1 point beyond 3σ) applied to the Moving Range chart.</td></tr>\n",
    "<tr><td class=\"l\">Pass Criterion</td>",
    "<td>Zero rule violations on both charts.</td></tr>"
  )

  # OOC table
  if (n_ooc_x > 0) {
    ooc_rows_html <- paste(
      vapply(which(ooc_x), function(idx) {
        rule_str <- paste(rules_x[[idx]], collapse = ", ")
        sprintf("<tr><td>%s</td><td>%.6f</td><td>[%s]</td></tr>",
                as.character(dat$id[idx]), dat$value[idx], rule_str)
      }, character(1)),
      collapse = "\n"
    )
    ooc_table <- sprintf(
      "<table class=\"dt\" style=\"margin-top:8px\"><tr><td class=\"l\">ID</td><td class=\"l\">Value</td><td class=\"l\">Rules</td></tr>\n%s\n</table>",
      ooc_rows_html
    )
    ooc_row <- sprintf(
      "<tr><td class=\"l\">Out-of-Control Points (X)</td><td>%d point(s) flagged%s</td></tr>",
      n_ooc_x, paste0("<br/>", ooc_table)
    )
  } else {
    ooc_row <- "<tr><td class=\"l\">Out-of-Control Points (X)</td><td>None — all points within control limits and no rule violations.</td></tr>"
  }

  mr_ooc_row <- if (n_ooc_mr > 0) {
    sprintf("<tr><td class=\"l\">MR Chart Violations</td><td>%d point(s) beyond UCL_MR.</td></tr>", n_ooc_mr)
  } else {
    "<tr><td class=\"l\">MR Chart Violations</td><td>None.</td></tr>"
  }

  results_rows <- paste(
    sprintf("<tr><td class=\"l\">Observations (n)</td><td>%d</td></tr>", n_obs),
    sprintf("<tr><td class=\"l\">X̅ (process mean)</td><td>%.6f</td></tr>", X_bar),
    sprintf("<tr><td class=\"l\">σ̂ (MR̅/d2)</td><td>%.6f</td></tr>", sigma),
    sprintf("<tr><td class=\"l\">UCL (Individuals)</td><td>%s</td></tr>", ucl_note),
    sprintf("<tr><td class=\"l\">LCL (Individuals)</td><td>%s</td></tr>", lcl_note),
    sprintf("<tr><td class=\"l\">MR̅</td><td>%.6f</td></tr>", MR_bar),
    sprintf("<tr><td class=\"l\">UCL_MR (D4 × MR̅)</td><td>%.6f</td></tr>", UCL_MR),
    ooc_row,
    mr_ooc_row,
    sep = "\n"
  )

  verdict_html <- sprintf("%s Process validation outcome: %s",
                          verdict_symbol,
                          if (is_pass) "PASS — Process is STABLE" else "FAIL — SIGNALS DETECTED")

  script_ver <- "jrc_spc_imr v1.1 — JR Anchored"
  footer_txt <- sprintf("Generated by %s — %s", script_ver, generated)

  html <- readLines(sentinel, warn = FALSE)
  html <- paste(html, collapse = "\n")

  html <- gsub("{{subtitle}}",
               "Process Stability Assessment — I-MR Control Chart (Western Electric Rules)", html, fixed = TRUE)
  html <- gsub("{{report_id}}",        report_id,        html, fixed = TRUE)
  html <- gsub("{{generated}}",        generated,        html, fixed = TRUE)
  html <- gsub("{{script_version}}",   script_ver,       html, fixed = TRUE)
  html <- gsub("{{acceptance_criterion}}", acceptance,    html, fixed = TRUE)
  html <- gsub("{{data_file}}",        basename(csv_file), html, fixed = TRUE)
  html <- gsub("{{col_name}}",         "value",          html, fixed = TRUE)
  html <- gsub("{{n}}",                as.character(n_obs), html, fixed = TRUE)
  html <- gsub("{{spec_rows}}",        spec_rows,        html, fixed = TRUE)
  html <- gsub("{{method_rows}}",      method_rows,      html, fixed = TRUE)
  html <- gsub("{{results_rows}}",     results_rows,     html, fixed = TRUE)
  html <- gsub("{{verdict_class}}",    verdict_class,    html, fixed = TRUE)
  html <- gsub("{{verdict_html}}",     verdict_html,     html, fixed = TRUE)
  html <- gsub("{{chart_html}}",       chart_html,       html, fixed = TRUE)
  html <- gsub("{{verdict_color}}",    verdict_color,    html, fixed = TRUE)
  html <- gsub("{{verdict_short}}",
               if (is_pass) "✅ PASS" else "❌ FAIL", html, fixed = TRUE)
  html <- gsub("{{footer}}",           footer_txt,       html, fixed = TRUE)

  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(ts, "_spc_imr_pv_report.html"))
  writeLines(html, out_path)
  cat(sprintf("✨ PV Report saved to: %s\n", out_path))

  # Write JSON sidecar for Word report generator
  json_path <- sub("\\.html$", "_data.json", out_path)

  jvs <- function(x) {
    x <- gsub("\\\\", "\\\\\\\\", as.character(x))
    x <- gsub('"',    '\\\\"',    x)
    paste0('"', x, '"')
  }
  jvn <- function(x, fmt = "%.6f") {
    if (is.null(x) || (length(x) == 1L && is.na(x))) "null"
    else sprintf(fmt, as.numeric(x))
  }
  jvb <- function(x) if (isTRUE(x)) "true" else "false"

  method_rows <- paste(
    '    {"label": "Method", "value": "Shewhart Individuals and Moving Range (I-MR) control chart. Control limits computed from the average moving range (MR_bar / d2, d2 = 1.128 for n = 2)."},',
    '    {"label": "Individuals Chart Rules", "value": "All 8 Western Electric rules applied to the Individuals chart."},',
    '    {"label": "MR Chart Rule", "value": "Rule 1 only (1 point beyond 3 sigma) applied to the Moving Range chart."},',
    '    {"label": "Pass Criterion", "value": "Zero rule violations on both charts (STABLE verdict)."}',
    sep = ",\n"
  )

  ucl_note <- if (!is.na(user_ucl)) sprintf("%.6f (user-specified)", user_ucl) else sprintf("%.6f (X_bar + 3*sigma)", UCL_X)
  lcl_note <- if (!is.na(user_lcl)) sprintf("%.6f (user-specified)", user_lcl) else sprintf("%.6f (X_bar - 3*sigma)", LCL_X)

  res_parts <- c(
    sprintf('    {"label": "Observations (n)",       "value": "%d"}', n_obs),
    sprintf('    {"label": "Process mean (X_bar)",   "value": "%.6f"}', X_bar),
    sprintf('    {"label": "sigma_w (MR_bar / d2)",  "value": "%.6f"}', sigma),
    sprintf('    {"label": "UCL (Individuals)",       "value": "%s"}', ucl_note),
    sprintf('    {"label": "LCL (Individuals)",       "value": "%s"}', lcl_note),
    sprintf('    {"label": "MR_bar",                  "value": "%.6f"}', MR_bar),
    sprintf('    {"label": "UCL_MR (D4 * MR_bar)",   "value": "%.6f"}', UCL_MR),
    sprintf('    {"label": "OOC signals (X chart)",   "value": "%d"}', n_ooc_x),
    sprintf('    {"label": "OOC signals (MR chart)",  "value": "%d"}', n_ooc_mr)
  )
  results_rows <- paste(res_parts, collapse = ",\n")

  json_lines <- c(
    "{",
    sprintf('  "report_type":          "pv",'),
    sprintf('  "script":               "jrc_spc_imr",'),
    sprintf('  "version":              "1.1",'),
    sprintf('  "report_id":            %s,', jvs(report_id)),
    sprintf('  "generated":            %s,', jvs(generated)),
    sprintf('  "subtitle":             %s,', jvs("Process Stability Assessment - I-MR Control Chart (Western Electric Rules)")),
    sprintf('  "data_file":            %s,', jvs(basename(csv_file))),
    '  "col_name":             "value",',
    sprintf('  "n":                    %d,', n_obs),
    '  "lsl":                  null,',
    '  "usl":                  null,',
    sprintf('  "acceptance_criterion": %s,', jvs(acceptance)),
    sprintf('  "method_rows": [\n%s\n  ],', method_rows),
    sprintf('  "results_rows": [\n%s\n  ],', results_rows),
    sprintf('  "verdict":              %s,', jvs(verdict)),
    sprintf('  "verdict_pass":         %s,', jvb(is_pass)),
    sprintf('  "png_path":             %s',  jvs(gsub("\\\\", "/", png_path))),
    "}"
  )

  con <- file(json_path, encoding = "UTF-8")
  writeLines(json_lines, con)
  close(con)
  cat(sprintf("📄 Report data saved to: %s\n", json_path))
  pack_py <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "pack", "jr_pack.py")
  if (file.exists(pack_py)) {
    ret       <- system2("python3",
                         args   = c(shQuote(pack_py), "deliverables", "pv-report",
                                    "--json", shQuote(json_path)),
                         stdout = TRUE, stderr = TRUE)
    exit_code <- attr(ret, "status")
    if (is.null(exit_code)) exit_code <- 0L
    cat(paste(ret, collapse = "\n"), "\n")
    if (exit_code != 0L) {
      cat(sprintf("   Retry manually: jr_pack deliverables pv-report --json %s\n", json_path))
    } else {
      docx_line <- grep("saved to:", ret, value = TRUE)
      if (length(docx_line) > 0L)
        jr_log_report(trimws(sub(".*saved to:\\s*", "", docx_line[1L])))
      if (file.exists(out_path))  file.remove(out_path)
      if (file.exists(json_path)) file.remove(json_path)
    }
  } else {
    cat(sprintf("   Run: jr_pack deliverables pv-report --json %s\n", json_path))
  }

  invisible(c(html = out_path, json = json_path))
}

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------
if (!file.exists(csv_file)) {
  stop(paste("❌ File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("id", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, value"))
}

dat$value <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$value))) {
  stop("❌ Non-numeric or NA values found in the 'value' column.")
}

n_obs <- nrow(dat)
if (n_obs < 2) {
  stop("❌ At least 2 observations are required.")
}

# ---------------------------------------------------------------------------
# I-MR calculations
# ---------------------------------------------------------------------------
x      <- dat$value
MR     <- c(NA_real_, abs(diff(x)))          # first MR is NA
MR_bar <- mean(MR, na.rm = TRUE)
sigma  <- MR_bar / 1.128                     # d2 = 1.128 for n=2 moving range
X_bar  <- mean(x)

UCL_X  <- if (!is.na(user_ucl)) user_ucl else X_bar + 3 * sigma
LCL_X  <- if (!is.na(user_lcl)) user_lcl else X_bar - 3 * sigma
UCL_MR <- 3.267 * MR_bar                     # D4 for n=2
LCL_MR <- 0                                  # D3 for n=2

# ---------------------------------------------------------------------------
# Western Electric rules
# ---------------------------------------------------------------------------
apply_we_rules <- function(x, cl, sigma) {
  n     <- length(x)
  ooc   <- rep(FALSE, n)
  rules <- vector("list", n)
  for (idx in seq_len(n)) rules[[idx]] <- character(0)

  # Rule 1: 1 point beyond 3 sigma
  for (idx in seq_len(n)) {
    if (abs(x[idx] - cl) > 3 * sigma) {
      ooc[idx]   <- TRUE
      rules[[idx]] <- c(rules[[idx]], "1")
    }
  }

  # Rule 2: 9 consecutive points same side of centerline
  if (n >= 9) {
    side <- sign(x - cl)
    for (idx in 9:n) {
      window <- side[(idx - 8):idx]
      if (all(window == 1) || all(window == -1)) {
        for (j in (idx - 8):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "2")
        }
      }
    }
  }

  # Rule 3: 6 consecutive points steadily increasing or decreasing
  if (n >= 6) {
    for (idx in 6:n) {
      window <- x[(idx - 5):idx]
      diffs  <- diff(window)
      if (all(diffs > 0) || all(diffs < 0)) {
        for (j in (idx - 5):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "3")
        }
      }
    }
  }

  # Rule 4: 14 points alternating up and down
  if (n >= 14) {
    for (idx in 14:n) {
      window <- x[(idx - 13):idx]
      diffs  <- diff(window)
      alternating <- all(diffs[-length(diffs)] * diffs[-1] < 0)
      if (alternating) {
        for (j in (idx - 13):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "4")
        }
      }
    }
  }

  # Rule 5: 2 of 3 consecutive points beyond 2 sigma, same side
  if (n >= 3) {
    beyond2 <- (x - cl) / sigma
    for (idx in 3:n) {
      window <- beyond2[(idx - 2):idx]
      if (sum(window > 2) >= 2 || sum(window < -2) >= 2) {
        for (j in (idx - 2):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "5")
        }
      }
    }
  }

  # Rule 6: 4 of 5 consecutive points beyond 1 sigma, same side
  if (n >= 5) {
    beyond1 <- (x - cl) / sigma
    for (idx in 5:n) {
      window <- beyond1[(idx - 4):idx]
      if (sum(window > 1) >= 4 || sum(window < -1) >= 4) {
        for (j in (idx - 4):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "6")
        }
      }
    }
  }

  # Rule 7: 15 consecutive points within 1 sigma of centerline
  if (n >= 15) {
    within1 <- abs(x - cl) < sigma
    for (idx in 15:n) {
      if (all(within1[(idx - 14):idx])) {
        for (j in (idx - 14):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "7")
        }
      }
    }
  }

  # Rule 8: 8 consecutive points more than 1 sigma from centerline, either side
  if (n >= 8) {
    beyond1_either <- abs(x - cl) > sigma
    for (idx in 8:n) {
      if (all(beyond1_either[(idx - 7):idx])) {
        for (j in (idx - 7):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "8")
        }
      }
    }
  }

  # Deduplicate rule labels per point
  for (idx in seq_len(n)) {
    rules[[idx]] <- unique(rules[[idx]])
  }

  list(ooc = ooc, rules = rules)
}

we_x  <- apply_we_rules(x, X_bar, sigma)
ooc_x <- we_x$ooc
rules_x <- we_x$rules

# Rule 1 only for MR chart (skip first NA)
MR_vals    <- MR[-1]
MR_ids     <- dat$id[-1]
ooc_mr     <- abs(MR_vals - MR_bar) > 3 * (MR_bar / 1.128)
n_ooc_x    <- sum(ooc_x)
n_ooc_mr   <- sum(ooc_mr)

verdict <- if (n_ooc_x == 0 && n_ooc_mr == 0) "STABLE" else "SIGNALS DETECTED"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  I-MR Control Chart\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Observations: %d\n\n", n_obs))

cat("--- Control Limits (Individuals) --------------------------------\n")
cat(sprintf("  X-bar:  %s\n", sprintf("%.6f", X_bar)))
cat(sprintf("  Sigma:  %s\n", sprintf("%.6f", sigma)))
if (!is.na(user_ucl)) {
  cat(sprintf("  UCL:    %s  (user-specified)\n", sprintf("%.6f", UCL_X)))
} else {
  cat(sprintf("  UCL:    %s\n", sprintf("%.6f", UCL_X)))
}
if (!is.na(user_lcl)) {
  cat(sprintf("  LCL:    %s  (user-specified)\n", sprintf("%.6f", LCL_X)))
} else {
  cat(sprintf("  LCL:    %s\n", sprintf("%.6f", LCL_X)))
}
cat("\n")

cat("--- Control Limits (Moving Range) -------------------------------\n")
cat(sprintf("  MR-bar: %s\n", sprintf("%.6f", MR_bar)))
cat(sprintf("  UCL_MR: %s  (D4 = 3.267)\n", sprintf("%.6f", UCL_MR)))
cat(sprintf("  LCL_MR: %s  (D3 = 0)\n", sprintf("%.6f", LCL_MR)))
cat("\n")

cat("--- Process Stability -------------------------------------------\n")
if (n_ooc_x == 0) {
  cat("  IN CONTROL — no Western Electric violations detected\n")
} else {
  cat(sprintf("  OUT OF CONTROL — %d point(s) flagged\n\n", n_ooc_x))
  cat(sprintf("  %-20s %12s  %s\n", "ID", "Value", "Rules"))
  for (idx in seq_len(n_obs)) {
    if (ooc_x[idx]) {
      rule_str <- paste(rules_x[[idx]], collapse = ", ")
      cat(sprintf("  %-20s %12s  [%s]\n",
                  as.character(dat$id[idx]),
                  sprintf("%.6f", x[idx]),
                  rule_str))
    }
  }
}
if (n_ooc_mr > 0) {
  cat(sprintf("\n  MR chart: %d point(s) beyond UCL_MR\n", n_ooc_mr))
}
cat("\n")

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_IC   <- "#1A1A2E"   # in-control points (navy)
COL_OOC  <- "#C0392B"   # out-of-control points (red)
COL_CL   <- "#2E5BBA"   # centerline
COL_UCL  <- "#C0392B"   # UCL/LCL lines
COL_2S   <- "#E67E22"   # 2-sigma zone lines
COL_1S   <- "#27AE60"   # 1-sigma zone lines
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9)
  )

# Build Individuals chart data frame
x_df <- data.frame(
  idx   = seq_len(n_obs),
  id    = as.character(dat$id),
  value = x,
  ooc   = ooc_x,
  stringsAsFactors = FALSE
)

x_label_df <- x_df[x_df$ooc, ]

# Build MR chart data frame (skip first NA)
mr_df <- data.frame(
  idx   = seq_len(n_obs - 1) + 1,
  id    = as.character(dat$id[-1]),
  value = MR_vals,
  ooc   = ooc_mr,
  stringsAsFactors = FALSE
)

mr_label_df <- mr_df[mr_df$ooc, ]

# --- Panel 1: Individuals chart ---
p1 <- ggplot(x_df, aes(x = idx, y = value)) +
  # Zone lines
  geom_hline(yintercept = X_bar + 2 * sigma, linetype = "dashed",
             color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = X_bar - 2 * sigma, linetype = "dashed",
             color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = X_bar + sigma, linetype = "dashed",
             color = COL_1S, linewidth = 0.5) +
  geom_hline(yintercept = X_bar - sigma, linetype = "dashed",
             color = COL_1S, linewidth = 0.5) +
  # UCL / LCL
  geom_hline(yintercept = UCL_X, linetype = "dashed",
             color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = LCL_X, linetype = "dashed",
             color = COL_UCL, linewidth = 0.7) +
  # Centerline
  geom_hline(yintercept = X_bar, linetype = "solid",
             color = COL_CL, linewidth = 0.7) +
  # Data line and points
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 2, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  # OOC labels
  geom_text(data = x_label_df, aes(label = id),
            nudge_y = 0.05 * diff(range(x)), size = 2.8,
            color = COL_OOC) +
  labs(title = "Individuals (X) Chart", x = "Observation", y = "Value") +
  theme_jr

# --- Panel 2: Moving Range chart ---
p2 <- ggplot(mr_df, aes(x = idx, y = value)) +
  # UCL
  geom_hline(yintercept = UCL_MR, linetype = "dashed",
             color = COL_UCL, linewidth = 0.7) +
  # Centerline (MR_bar)
  geom_hline(yintercept = MR_bar, linetype = "solid",
             color = COL_CL, linewidth = 0.7) +
  # LCL = 0 (implicit at baseline)
  geom_hline(yintercept = LCL_MR, linetype = "dashed",
             color = COL_UCL, linewidth = 0.5, alpha = 0.5) +
  # Data line and points
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 2, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  # OOC labels
  geom_text(data = mr_label_df, aes(label = id),
            nudge_y = 0.05 * diff(range(MR_vals)), size = 2.8,
            color = COL_OOC) +
  labs(title = "Moving Range (MR) Chart", x = "Observation", y = "Moving Range") +
  theme_jr

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_spc_imr.png"))

cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1800, res = 180, bg = BG)

grid.newpage()

pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

# Title strip
pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("I-MR Chart  |  %s  |  X-bar = %.4f  |  σ = %.4f  |  %s",
          basename(csv_file), X_bar, sigma, verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

# Two-panel vertical layout
pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 2, ncol = 1)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 2, layout.pos.col = 1))
popViewport()

dev.off()

cat(sprintf("✅ Done. Open %s to view your report.\n", basename(out_file)))

# ---------------------------------------------------------------------------
# Report and output hashes
# ---------------------------------------------------------------------------
report_path <- NULL
if (want_report) {
  report_path <- save_imr_report(
    csv_file, n_obs,
    X_bar, sigma, UCL_X, LCL_X,
    MR_bar, UCL_MR, LCL_MR,
    user_ucl, user_lcl,
    n_ooc_x, n_ooc_mr,
    ooc_x, rules_x, dat,
    verdict, out_file
  )
}

jr_log_output_hashes(c(out_file))
