# =============================================================================
# jrc_spc_imr.R
# JR Validated Environment — SPC module
#
# Individuals and Moving Range (I-MR) control chart.
# Reads a CSV with columns: id, value (time-ordered).
# Computes control limits using the average moving range method,
# applies all 8 Western Electric rules to the Individuals chart,
# applies Rule 1 only to the MR chart, and saves a two-panel PNG
# to the output directory
# (JR_OUT_DIR, default ~/Downloads).
#
# Usage: jrc_spc_imr <data.csv> [--ucl <value>] [--lcl <value>] [--report]
#
# Arguments:
#   data.csv        CSV file with columns: id, value (time-ordered)
#   --ucl <value>   Optional: user-specified UCL for the Individuals chart
#   --lcl <value>   Optional: user-specified LCL for the Individuals chart
#   --report        Generate a Process Validation Report (requires Validation Pack)
#
# Version: 1.2
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
    # Unknown flags (e.g. typos) are errors, never silently ignored (X-05)
    stop(paste0("Unknown argument, or option without a value: ", args[i]))
  }
}

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.2"   # single source for banner, report and JSON

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
  jr_require_report_template("pv_report_template.html", log_files = png_path)
  sentinel <- jr_report_template_path("pv_report_template.html")

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

  script_ver <- paste0("jrc_spc_imr v", SCRIPT_VERSION, " — JR Anchored")
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

  out_path <- file.path(jr_out_dir(),
                        paste0(ts, "_spc_imr_pv_report.html"))
  writeLines(html, out_path)
  cat(sprintf("✨ PV Report saved to: %s\n", out_path))

  # Write JSON sidecar for Word report generator
  json_path <- sub("\\.html$", "_data.json", out_path)

  jvs <- jr_json_str
  jvn <- function(x, fmt = "%.6f") jr_json_num(x, fmt)
  jvb <- jr_json_bool

  method_rows <- paste(
    '    {"label": "Method", "value": "Shewhart Individuals and Moving Range (I-MR) control chart. Control limits computed from the average moving range (MR_bar / d2, d2 = 1.128 for n = 2)."}',
    '    {"label": "Individuals Chart Rules", "value": "All 8 Western Electric rules applied to the Individuals chart."}',
    '    {"label": "MR Chart Rule", "value": "Rule 1 only (1 point beyond 3 sigma) applied to the Moving Range chart."}',
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

  input_sha256 <- jr_sha256_file(csv_file)

  json_lines <- c(
    "{",
    sprintf('  "report_type":          "pv",'),
    sprintf('  "script":               "jrc_spc_imr",'),
    sprintf('  "version":              "%s",', SCRIPT_VERSION),
    sprintf('  "report_id":            %s,', jvs(report_id)),
    sprintf('  "generated":            %s,', jvs(generated)),
    sprintf('  "subtitle":             %s,', jvs("Process Stability Assessment - I-MR Control Chart (Western Electric Rules)")),
    sprintf('  "data_file":            %s,', jvs(basename(csv_file))),
    sprintf('  "data_sha256":          %s,', jvs(input_sha256)),
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
  jr_run_pack(json_path, "pv-report", out_path, log_files = png_path)

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

if (sigma <= 0) {
  cat("\u26a0\ufe0f  No variation in the data (MR-bar = 0): control limits collapse onto\n")
  cat("   the centre line and the run rules cannot be evaluated. No signals reported.\n\n")
}
we_x  <- jr_spc_rules(x, X_bar, sigma, ucl = user_ucl, lcl = user_lcl)
ooc_x <- we_x$ooc
rules_x <- we_x$rules

# Rule 1 only for MR chart (skip first NA)
MR_vals    <- MR[-1]
MR_ids     <- dat$id[-1]
ooc_mr     <- MR_vals > UCL_MR                  # beyond the plotted UCL_MR (D4 * MR_bar)
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

if (!is.na(user_ucl) || !is.na(user_lcl)) {
  cat("  Rule 1 uses the user-specified limit(s); zone rules 2-8 use the\n")
  cat("  sigma computed from this data.\n")
}
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

theme_jr <- jr_theme(10)

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
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_spc_imr.png"))

cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

jr_save_titled_png(
  out_file,
  sprintf("I-MR Chart  |  %s  |  X-bar = %.4f  |  σ = %.4f  |  %s",
          basename(csv_file), X_bar, sigma, verdict),
  list(p1, p2),
  nrow = 2,
  ncol = 1,
  width = 2400,
  height = 1800,
  res = 180
)

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
