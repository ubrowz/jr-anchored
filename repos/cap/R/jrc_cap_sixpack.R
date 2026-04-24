# =============================================================================
# jrc_cap_sixpack.R
# JR Validated Environment — Process Capability module
# Version: 1.1
#
# Process Capability Sixpack — a single PNG combining:
#   Panel 1 (top-left):    Individuals (X) chart with control limits
#   Panel 2 (top-right):   Moving Range (MR) chart
#   Panel 3 (middle-left): Histogram with spec limits and normal curve
#   Panel 4 (middle-right): Normal probability plot (Q-Q plot)
#   Panel 5 (bottom-left): Capability indices summary (Cp, Cpk, Pp, Ppk, Cpm)
#   Panel 6 (bottom-right): Observed vs expected tail proportions
#
# Usage: jrc_cap_sixpack <data.csv> <col> <lsl> <usl>
#
# <lsl> and <usl> may each be "-" to omit one-sided. At least one must be a number.
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]
if (length(args) < 4) {
  stop("Usage: jrc_cap_sixpack <data.csv> <col> <lsl> <usl> [--report]\n  Use '-' for <lsl> or <usl> to analyse one-sided.")
}

data_file <- args[1]
col_name  <- args[2]
lsl_arg   <- args[3]
usl_arg   <- args[4]

lsl <- if (lsl_arg == "-") NA_real_ else suppressWarnings(as.numeric(lsl_arg))
usl <- if (usl_arg == "-") NA_real_ else suppressWarnings(as.numeric(usl_arg))

if (is.na(lsl) && lsl_arg != "-") stop("LSL must be a number or '-'.")
if (is.na(usl) && usl_arg != "-") stop("USL must be a number or '-'.")
if (is.na(lsl) && is.na(usl))     stop("At least one of LSL or USL must be provided.")
if (!is.na(lsl) && !is.na(usl) && lsl >= usl) stop("LSL must be less than USL.")

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------
renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(base64enc)
}))

# ---------------------------------------------------------------------------
# Report generator (requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------
save_sixpack_report <- function(data_file, col_name, n, lsl, usl,
                                 x_bar, s_overall, sigma_w,
                                 Cp, Cpk, Pp, Ppk, Cpm,
                                 sigma_level, ppm_total, ppm_above, ppm_below,
                                 UCL_X, LCL_X, UCL_MR, MR_bar,
                                 n_ooc, spc_verdict, cap_verdict,
                                 sw_p, png_path) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates",
                        "pv_report_template.html")
  if (!file.exists(sentinel)) {
    cat("⚠ --report requires the JR Anchored Validation Pack.\n")
    cat("  Install the pack and re-run to generate the Process Validation Report.\n")
    return(invisible(NULL))
  }

  ts        <- format(Sys.time(), "%Y%m%d_%H%M%S")
  report_id <- paste0("VR-SIXPACK-", ts)
  generated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  chart_html <- ""
  if (!is.null(png_path) && file.exists(png_path)) {
    b64 <- base64enc::base64encode(png_path)
    chart_html <- sprintf(
      '<div class="chart-wrap"><img src="data:image/png;base64,%s" alt="Capability sixpack"/></div>', b64)
  }

  has_both <- !is.na(lsl) && !is.na(usl)
  lsl_str  <- if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl)
  usl_str  <- if (is.na(usl)) "(none)" else sprintf("%.4f", usl)

  is_pass <- cap_verdict %in% c("EXCELLENT", "CAPABLE")
  verdict_class  <- if (is_pass) "verdict verdict-pass" else "verdict verdict-fail"
  verdict_symbol <- if (is_pass) "✅" else "❌"
  verdict_color  <- if (is_pass) "color:#155724" else "color:#721c24"
  verdict_html   <- sprintf("%s Process validation: %s — Cpk = %.4f, Ppk = %.4f",
                            verdict_symbol, cap_verdict, Cpk, Ppk)

  acceptance <- if (has_both)
    "Cpk ≥ 1.33 (CAPABLE) for process validation. SPC: no OOC signals on I-MR chart."
  else
    "Cpk ≥ 1.33 (one-sided spec). SPC: no OOC signals on I-MR chart."

  spec_rows <- paste(
    sprintf('<tr><td class="l">LSL</td><td>%s</td></tr>', lsl_str),
    sprintf('<tr><td class="l">USL</td><td>%s</td></tr>', usl_str),
    sep = "\n"
  )

  method_rows <- paste(
    '<tr><td class="l">Chart type</td><td>Process Capability Sixpack — I-MR chart, histogram, normal probability plot, capability indices, verdict panel</td></tr>',
    '<tr><td class="l">Within-sigma (&sigma;&#770;)</td><td>&sigma;&#770; = MR&#772; / d2, where d2 = 1.128 (moving range, n = 2)</td></tr>',
    '<tr><td class="l">Capability index</td><td>Cpk = min[(USL &minus; X&#772;) / (3&sigma;&#770;), (X&#772; &minus; LSL) / (3&sigma;&#770;)]</td></tr>',
    '<tr><td class="l">Performance index</td><td>Ppk = min[(USL &minus; X&#772;) / (3s), (X&#772; &minus; LSL) / (3s)] where s = overall sample SD</td></tr>',
    '<tr><td class="l">SPC method</td><td>Individuals (X) chart with Rule 1 (beyond 3&sigma;); Moving Range (MR) chart with Rule 1</td></tr>',
    sprintf('<tr><td class="l">Normality</td><td>Shapiro-Wilk W = %.4f, p = %.4f%s</td></tr>',
            sw_p, sw_p,
            if (sw_p < 0.05) " — <strong>non-normal data; capability indices should be interpreted with caution</strong>" else " — normality assumption satisfied"),
    sep = "\n"
  )

  cp_row  <- if (!is.na(Cp))  sprintf('<tr><td class="l">Cp</td><td>%.4f</td></tr>', Cp)  else ""
  cpm_row <- if (!is.na(Cpm)) sprintf('<tr><td class="l">Cpm (Taguchi)</td><td>%.4f</td></tr>', Cpm) else ""
  pp_row  <- if (!is.na(Pp))  sprintf('<tr><td class="l">Pp</td><td>%.4f</td></tr>', Pp)  else ""
  ppm_row <- if (!is.na(ppm_total)) {
    parts <- c()
    if (!is.na(ppm_above)) parts <- c(parts, sprintf("%.1f above USL", ppm_above))
    if (!is.na(ppm_below)) parts <- c(parts, sprintf("%.1f below LSL", ppm_below))
    sprintf('<tr><td class="l">Est. PPM Out-of-Spec</td><td>%.1f total (%s)</td></tr>',
            ppm_total, paste(parts, collapse = "; "))
  } else ""

  results_rows <- paste(
    sprintf('<tr><td class="l">Observations (n)</td><td>%d</td></tr>', n),
    sprintf('<tr><td class="l">Mean (X&#772;)</td><td>%.4f</td></tr>', x_bar),
    sprintf('<tr><td class="l">SD — Overall (s)</td><td>%.4f</td></tr>', s_overall),
    sprintf('<tr><td class="l">SD — Within (&sigma;&#770;, MR/d2)</td><td>%.4f</td></tr>', sigma_w),
    sprintf('<tr><td class="l">I-chart UCL / LCL</td><td>%.4f / %.4f</td></tr>', UCL_X, LCL_X),
    sprintf('<tr><td class="l">MR-chart UCL</td><td>%.4f (MR&#772; = %.4f)</td></tr>', UCL_MR, MR_bar),
    sprintf('<tr><td class="l">OOC signals</td><td>%d</td></tr>', n_ooc),
    cp_row,
    sprintf('<tr><td class="l">Cpk</td><td>%.4f</td></tr>', Cpk),
    cpm_row,
    pp_row,
    sprintf('<tr><td class="l">Ppk</td><td>%.4f</td></tr>', Ppk),
    sprintf('<tr><td class="l">Sigma level</td><td>%.2f&sigma;</td></tr>', sigma_level),
    ppm_row,
    sep = "\n"
  )

  script_ver <- "jrc_cap_sixpack v1.1 — JR Anchored"
  footer_txt <- sprintf("Generated by %s — %s", script_ver, generated)

  html <- readLines(sentinel, warn = FALSE)
  html <- paste(html, collapse = "\n")

  html <- gsub("{{subtitle}}",             "Process Capability Sixpack (I-MR, Histogram, Q-Q, Indices)", html, fixed = TRUE)
  html <- gsub("{{report_id}}",            report_id,            html, fixed = TRUE)
  html <- gsub("{{generated}}",            generated,            html, fixed = TRUE)
  html <- gsub("{{script_version}}",       script_ver,           html, fixed = TRUE)
  html <- gsub("{{acceptance_criterion}}", acceptance,           html, fixed = TRUE)
  html <- gsub("{{data_file}}",            basename(data_file),  html, fixed = TRUE)
  html <- gsub("{{col_name}}",             col_name,             html, fixed = TRUE)
  html <- gsub("{{n}}",                    as.character(n),      html, fixed = TRUE)
  html <- gsub("{{spec_rows}}",            spec_rows,            html, fixed = TRUE)
  html <- gsub("{{method_rows}}",          method_rows,          html, fixed = TRUE)
  html <- gsub("{{results_rows}}",         results_rows,         html, fixed = TRUE)
  html <- gsub("{{verdict_class}}",        verdict_class,        html, fixed = TRUE)
  html <- gsub("{{verdict_html}}",         verdict_html,         html, fixed = TRUE)
  html <- gsub("{{chart_html}}",           chart_html,           html, fixed = TRUE)
  html <- gsub("{{verdict_color}}",        verdict_color,        html, fixed = TRUE)
  html <- gsub("{{verdict_short}}",
               if (is_pass) paste0("✅ ", cap_verdict) else paste0("❌ ", cap_verdict),
               html, fixed = TRUE)
  html <- gsub("{{footer}}",              footer_txt,            html, fixed = TRUE)

  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(ts, "_cap_sixpack_pv_report.html"))
  writeLines(html, out_path)
  cat(sprintf("✨ PV Report saved to: %s\n", out_path))

  # Write JSON sidecar for Word report generator
  json_path <- sub("\\.html$", "_data.json", out_path)

  jvs <- function(x) {
    x <- gsub("\\\\", "\\\\\\\\", as.character(x))
    x <- gsub('"',    '\\\\"',    x)
    paste0('"', x, '"')
  }
  jvn <- function(x, fmt = "%.4f") {
    if (is.null(x) || (length(x) == 1L && is.na(x))) "null"
    else sprintf(fmt, as.numeric(x))
  }
  jvb <- function(x) if (isTRUE(x)) "true" else "false"

  method_rows <- paste(
    '    {"label": "Chart type", "value": "Process Capability Sixpack — I-MR chart, histogram, normal probability plot, capability indices, SPC verdict panel"},',
    '    {"label": "Within-sigma", "value": "sigma_w = MR_bar / d2, where d2 = 1.128 (moving range, n = 2)"},',
    '    {"label": "Capability index", "value": "Cpk = min[(USL - X_bar) / (3*sigma_w), (X_bar - LSL) / (3*sigma_w)]"},',
    '    {"label": "Performance index", "value": "Ppk = min[(USL - X_bar) / (3s), (X_bar - LSL) / (3s)]"},',
    '    {"label": "SPC method", "value": "Individuals (X) chart with Rule 1 (beyond 3 sigma); Moving Range (MR) chart with Rule 1"},',
    sprintf('    {"label": "Normality (Shapiro-Wilk)", "value": "p = %.4f%s"}',
            sw_p, if (sw_p < 0.05) " — non-normal; indices should be interpreted with caution" else " — normality assumption satisfied"),
    '    {"label": "Pass Criterion", "value": "Cpk >= 1.33 (CAPABLE). SPC: no OOC signals on I-MR chart."}',
    sep = ",\n"
  )

  res_parts <- c(
    sprintf('    {"label": "Observations (n)",        "value": "%d"}', n),
    sprintf('    {"label": "Mean (X_bar)",             "value": "%.4f"}', x_bar),
    sprintf('    {"label": "SD - Overall (s)",         "value": "%.4f"}', s_overall),
    sprintf('    {"label": "SD - Within (MR/d2)",      "value": "%.4f"}', sigma_w)
  )
  if (!is.na(Cp))  res_parts <- c(res_parts, sprintf('    {"label": "Cp",              "value": "%.4f"}', Cp))
  res_parts <- c(res_parts, sprintf('    {"label": "Cpk",             "value": "%.4f"}', Cpk))
  if (!is.na(Cpm)) res_parts <- c(res_parts, sprintf('    {"label": "Cpm (Taguchi)",   "value": "%.4f"}', Cpm))
  if (!is.na(Pp))  res_parts <- c(res_parts, sprintf('    {"label": "Pp",              "value": "%.4f"}', Pp))
  res_parts <- c(res_parts, sprintf('    {"label": "Ppk",             "value": "%.4f"}', Ppk))
  res_parts <- c(res_parts, sprintf('    {"label": "Sigma level",     "value": "%.2f sigma"}', sigma_level))
  if (!is.na(ppm_total)) {
    ppm_parts <- c()
    if (!is.na(ppm_above)) ppm_parts <- c(ppm_parts, sprintf("%.1f above USL", ppm_above))
    if (!is.na(ppm_below)) ppm_parts <- c(ppm_parts, sprintf("%.1f below LSL", ppm_below))
    res_parts <- c(res_parts,
      sprintf('    {"label": "Est. PPM Out-of-Spec",  "value": "%.1f total (%s)"}',
              ppm_total, paste(ppm_parts, collapse = "; ")))
  }
  res_parts <- c(res_parts,
    sprintf('    {"label": "I-chart UCL / LCL",      "value": "%.4f / %.4f"}', UCL_X, LCL_X),
    sprintf('    {"label": "MR-chart UCL",            "value": "%.4f (MR_bar = %.4f)"}', UCL_MR, MR_bar),
    sprintf('    {"label": "OOC signals",             "value": "%d"}', n_ooc),
    sprintf('    {"label": "SPC verdict",             "value": "%s"}', spc_verdict)
  )
  results_rows <- paste(res_parts, collapse = ",\n")

  json_lines <- c(
    "{",
    sprintf('  "report_type":          "pv",'),
    sprintf('  "script":               "jrc_cap_sixpack",'),
    sprintf('  "version":              "1.1",'),
    sprintf('  "report_id":            %s,', jvs(report_id)),
    sprintf('  "generated":            %s,', jvs(generated)),
    sprintf('  "subtitle":             %s,', jvs("Process Capability Sixpack (I-MR, Histogram, Q-Q, Indices)")),
    sprintf('  "data_file":            %s,', jvs(basename(data_file))),
    sprintf('  "col_name":             %s,', jvs(col_name)),
    sprintf('  "n":                    %d,', n),
    sprintf('  "lsl":                  %s,', jvn(lsl)),
    sprintf('  "usl":                  %s,', jvn(usl)),
    sprintf('  "acceptance_criterion": %s,', jvs(acceptance)),
    sprintf('  "method_rows": [\n%s\n  ],', method_rows),
    sprintf('  "results_rows": [\n%s\n  ],', results_rows),
    sprintf('  "verdict":              %s,', jvs(cap_verdict)),
    sprintf('  "verdict_pass":         %s,', jvb(is_pass)),
    sprintf('  "png_path":             %s',  jvs(gsub("\\\\", "/", png_path))),
    "}"
  )

  con <- file(json_path, encoding = "UTF-8")
  writeLines(json_lines, con)
  close(con)
  cat(sprintf("📄 Report data saved to: %s\n", json_path))
  cat(sprintf("   Run: jr_pack deliverables pv-report --json %s\n", json_path))

  invisible(c(html = out_path, json = json_path))
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
if (!file.exists(data_file)) {
  stop(paste("\u274c File not found:", data_file))
}

df <- tryCatch(
  read.csv(data_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV file:", e$message))
)

if (!col_name %in% names(df)) {
  stop(paste("\u274c Column not found in CSV:", col_name))
}

x_raw <- suppressWarnings(as.numeric(df[[col_name]]))
if (all(is.na(x_raw))) stop(paste("\u274c Column", col_name, "is not numeric."))

x <- x_raw[!is.na(x_raw)]
n <- length(x)

if (n < 5) {
  stop(paste("\u274c Need at least 5 observations. Found:", n))
}

# ---------------------------------------------------------------------------
# Computation — descriptives and capability
# ---------------------------------------------------------------------------
x_bar     <- mean(x)
s_overall <- sd(x)
n_obs     <- n

# Moving range
MR        <- abs(diff(x))
MR_bar    <- mean(MR)
d2        <- 1.128
sigma_w   <- MR_bar / d2

# Control chart limits (Individuals)
UCL_X <- x_bar + 3 * sigma_w
LCL_X <- x_bar - 3 * sigma_w
UCL_MR <- 3.267 * MR_bar    # D4 * MR_bar, D4=3.267 for n=2
LCL_MR <- 0

# OOC detection
ooc_x  <- x < LCL_X | x > UCL_X
ooc_mr <- c(FALSE, MR > UCL_MR)

# Spec / capability
has_both   <- !is.na(lsl) && !is.na(usl)
spec_width <- if (has_both) usl - lsl else NA_real_

Cp  <- if (has_both) spec_width / (6 * sigma_w)   else NA_real_
Pp  <- if (has_both) spec_width / (6 * s_overall)  else NA_real_

cpk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * sigma_w)   else NA_real_
cpk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * sigma_w)   else NA_real_
Cpk   <- min(c(cpk_u, cpk_l), na.rm = TRUE)

ppk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * s_overall) else NA_real_
ppk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * s_overall) else NA_real_
Ppk   <- min(c(ppk_u, ppk_l), na.rm = TRUE)

target <- if (has_both) (lsl + usl) / 2 else x_bar
Cpm    <- if (has_both) {
  spec_width / (6 * sqrt(s_overall^2 + (x_bar - target)^2))
} else NA_real_

sigma_level <- Cpk * 3

# PPM estimate
if (!is.na(usl) && !is.na(lsl)) {
  ppm_above <- pnorm((usl - x_bar) / sigma_w, lower.tail = FALSE) * 1e6
  ppm_below <- pnorm((lsl - x_bar) / sigma_w, lower.tail = TRUE)  * 1e6
  ppm_total <- ppm_above + ppm_below
} else if (!is.na(usl)) {
  ppm_above <- pnorm((usl - x_bar) / sigma_w, lower.tail = FALSE) * 1e6
  ppm_below <- NA_real_
  ppm_total <- ppm_above
} else {
  ppm_below <- pnorm((lsl - x_bar) / sigma_w, lower.tail = TRUE) * 1e6
  ppm_above <- NA_real_
  ppm_total <- ppm_below
}

# Normality
sw_result <- shapiro.test(x)

# SPC verdict
n_ooc   <- sum(ooc_x) + sum(ooc_mr[-1])
spc_verdict <- if (n_ooc == 0) "In Control" else sprintf("%d OOC signal(s)", n_ooc)

# Capability verdict
cap_verdict <- if (Cpk >= 1.67) {
  "EXCELLENT"
} else if (Cpk >= 1.33) {
  "CAPABLE"
} else if (Cpk >= 1.00) {
  "MARGINAL"
} else {
  "NOT CAPABLE"
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Process Capability Sixpack\n")
cat(sprintf("  File: %s   Col: %s   n = %d\n",
            basename(data_file), col_name, n))
cat(sprintf("  LSL: %s   USL: %s\n",
            if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl),
            if (is.na(usl)) "(none)" else sprintf("%.4f", usl)))
cat("=================================================================\n\n")

cat("  Descriptives:\n")
cat(sprintf("    Mean (X-bar):       %.4f\n",  x_bar))
cat(sprintf("    SD (overall, s):    %.4f\n",  s_overall))
cat(sprintf("    SD (within, MR/d2): %.4f\n",  sigma_w))
cat("\n")

cat("  Control chart limits (I-MR):\n")
cat(sprintf("    X: UCL = %.4f  CL = %.4f  LCL = %.4f\n",  UCL_X, x_bar, LCL_X))
cat(sprintf("    MR: UCL = %.4f  CL = %.4f  LCL = %.4f\n", UCL_MR, MR_bar, LCL_MR))
cat(sprintf("    OOC signals:        %d\n\n", n_ooc))

cat("  Capability indices:\n")
if (!is.na(Cp))  cat(sprintf("    Cp:                 %.4f\n", Cp))
cat(sprintf("    Cpk:                %.4f\n", Cpk))
if (!is.na(Cpm)) cat(sprintf("    Cpm (Taguchi):      %.4f\n", Cpm))
if (!is.na(Pp))  cat(sprintf("    Pp:                 %.4f\n", Pp))
cat(sprintf("    Ppk:                %.4f\n", Ppk))
cat(sprintf("    Sigma level:        %.2f\u03c3\n", sigma_level))
if (!is.na(ppm_total)) {
  cat(sprintf("    Est. PPM OOS:       %.1f\n", ppm_total))
}
cat("\n")

cat(sprintf("  Normality (Shapiro-Wilk): W = %.4f, p = %.4f\n\n",
            sw_result$statistic, sw_result$p.value))

cat("--- Verdict ---------------------------------------------------\n")
cat(sprintf("  SPC:  %s\n", spc_verdict))
cat(sprintf("  Cap:  %s  (Cpk = %.4f)\n", cap_verdict, Cpk))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_IC   <- "#1A1A2E"
COL_OOC  <- "#C0392B"
COL_CL   <- "#2E5BBA"
COL_UCL  <- "#C0392B"
COL_2S   <- "#E67E22"
COL_1S   <- "#27AE60"
COL_HIST <- "#AEC6E8"
COL_CURV <- "#2E5BBA"
COL_SPEC <- "#C0392B"
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- theme_minimal(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 9, face = "bold"),
    axis.text        = element_text(size = 7),
    axis.title       = element_text(size = 8)
  )

# --- Panel 1: Individuals chart ---
x_df <- data.frame(
  idx   = seq_len(n_obs),
  id    = if ("id" %in% names(df)) as.character(df$id[!is.na(x_raw)]) else as.character(seq_len(n_obs)),
  value = x,
  ooc   = ooc_x
)
x_label_df <- x_df[x_df$ooc, ]

p1 <- ggplot(x_df, aes(x = idx, y = value)) +
  geom_hline(yintercept = x_bar + 2 * sigma_w, linetype = "dashed", color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = x_bar - 2 * sigma_w, linetype = "dashed", color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = x_bar + sigma_w,     linetype = "dashed", color = COL_1S, linewidth = 0.5) +
  geom_hline(yintercept = x_bar - sigma_w,     linetype = "dashed", color = COL_1S, linewidth = 0.5) +
  geom_hline(yintercept = UCL_X,  linetype = "dashed", color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = LCL_X,  linetype = "dashed", color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = x_bar,  linetype = "solid",  color = COL_CL,  linewidth = 0.7)

if (!is.na(usl)) {
  p1 <- p1 + geom_hline(yintercept = usl, linetype = "dotted", color = COL_SPEC, linewidth = 0.8)
}
if (!is.na(lsl)) {
  p1 <- p1 + geom_hline(yintercept = lsl, linetype = "dotted", color = COL_SPEC, linewidth = 0.8)
}

p1 <- p1 +
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 1.8, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  labs(title = "Individuals (X) Chart", x = "Observation", y = "Value") +
  theme_jr

if (nrow(x_label_df) > 0) {
  p1 <- p1 + geom_text(data = x_label_df, aes(label = id),
                        nudge_y = 0.05 * diff(range(x)), size = 2.5, color = COL_OOC)
}

# --- Panel 2: Moving Range chart ---
MR_vals <- c(NA_real_, MR)
mr_df <- data.frame(
  idx   = seq_len(n_obs),
  value = MR_vals,
  ooc   = ooc_mr
)
mr_df_plot <- mr_df[!is.na(mr_df$value), ]

p2 <- ggplot(mr_df_plot, aes(x = idx, y = value)) +
  geom_hline(yintercept = UCL_MR, linetype = "dashed", color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = MR_bar, linetype = "solid",  color = COL_CL,  linewidth = 0.7) +
  geom_hline(yintercept = LCL_MR, linetype = "dashed", color = COL_UCL, linewidth = 0.5, alpha = 0.4) +
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 1.8, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  labs(title = "Moving Range (MR) Chart", x = "Observation", y = "Moving Range") +
  theme_jr

# --- Panel 3: Capability histogram ---
bw <- max(diff(range(x)) / 25, s_overall / 5)

x_seq   <- seq(min(x) - 3 * s_overall, max(x) + 3 * s_overall, length.out = 400)
norm_df <- data.frame(
  x = x_seq,
  y = dnorm(x_seq, mean = x_bar, sd = s_overall) * n * bw
)

p3 <- ggplot(data.frame(value = x), aes(x = value)) +
  geom_histogram(binwidth = bw, fill = COL_HIST, color = "white", alpha = 0.9) +
  geom_line(data = norm_df, aes(x = x, y = y), color = COL_CURV, linewidth = 1) +
  geom_vline(xintercept = x_bar, linetype = "solid", color = COL_IC, linewidth = 0.8)

if (!is.na(lsl)) {
  p3 <- p3 + geom_vline(xintercept = lsl, linetype = "dashed",
                         color = COL_SPEC, linewidth = 1) +
    annotate("text", x = lsl, y = Inf, label = sprintf("LSL\n%.4g", lsl),
             hjust = 1.1, vjust = 1.5, color = COL_SPEC, size = 2.5, fontface = "bold")
}
if (!is.na(usl)) {
  p3 <- p3 + geom_vline(xintercept = usl, linetype = "dashed",
                         color = COL_SPEC, linewidth = 1) +
    annotate("text", x = usl, y = Inf, label = sprintf("USL\n%.4g", usl),
             hjust = -0.1, vjust = 1.5, color = COL_SPEC, size = 2.5, fontface = "bold")
}

cap_label <- if (!is.na(Cp)) sprintf("Cp=%.2f  Cpk=%.2f", Cp, Cpk) else sprintf("Cpk=%.2f", Cpk)

p3 <- p3 +
  labs(title = sprintf("Histogram  |  %s", cap_label), x = col_name, y = "Count") +
  theme_jr

# --- Panel 4: Normal probability plot (Q-Q) ---
qq_df <- data.frame(
  theoretical = qnorm(ppoints(n)),
  sample      = sort(x)
)

# Fit line through Q1/Q3
q_th  <- qnorm(c(0.25, 0.75))
q_sam <- quantile(x, c(0.25, 0.75))
slope <- diff(q_sam) / diff(q_th)
inter <- q_sam[1] - slope * q_th[1]
qq_line_df <- data.frame(
  x = range(qq_df$theoretical),
  y = inter + slope * range(qq_df$theoretical)
)

p4 <- ggplot(qq_df, aes(x = theoretical, y = sample)) +
  geom_line(data = qq_line_df, aes(x = x, y = y),
            color = COL_CL, linewidth = 0.8, linetype = "solid") +
  geom_point(color = COL_IC, size = 1.5, alpha = 0.8) +
  labs(
    title = sprintf("Normal Probability Plot  |  SW p=%.3f", sw_result$p.value),
    x     = "Theoretical Quantiles",
    y     = col_name
  ) +
  theme_jr

# --- Panel 5: Capability summary text ---
summary_lines <- c(
  sprintf("n = %d", n),
  sprintf("X-bar = %.4f", x_bar),
  sprintf("s (overall) = %.4f", s_overall),
  sprintf("sigma_w = %.4f", sigma_w),
  "",
  if (!is.na(Cp))  sprintf("Cp  = %.4f", Cp)  else NULL,
  sprintf("Cpk = %.4f", Cpk),
  if (!is.na(Cpm)) sprintf("Cpm = %.4f", Cpm) else NULL,
  "",
  if (!is.na(Pp))  sprintf("Pp  = %.4f", Pp)  else NULL,
  sprintf("Ppk = %.4f", Ppk),
  "",
  sprintf("Sigma level = %.2f\u03c3", sigma_level),
  if (!is.na(ppm_total)) sprintf("Est. PPM OOS = %.1f", ppm_total) else NULL
)
summary_lines <- summary_lines[!sapply(summary_lines, is.null)]

p5 <- ggplot() +
  annotate("text",
           x = 0.05, y = seq(0.95, 0.05, length.out = length(summary_lines)),
           label = summary_lines,
           hjust = 0, vjust = 1,
           size = 3.2, family = "mono") +
  xlim(0, 1) + ylim(0, 1) +
  labs(title = "Summary") +
  theme_void() +
  theme(plot.background = element_rect(fill = BG, color = NA),
        plot.title = element_text(size = 9, face = "bold", hjust = 0, margin = margin(b = 4)))

# --- Panel 6: Verdict box ---
verdict_lines <- c(
  sprintf("Verdict: %s", cap_verdict),
  sprintf("Cpk = %.4f", Cpk),
  sprintf("Ppk = %.4f", Ppk),
  "",
  sprintf("SPC: %s", spc_verdict),
  "",
  "Thresholds:",
  "Cpk >= 1.67 : Excellent",
  "Cpk >= 1.33 : Capable",
  "Cpk >= 1.00 : Marginal",
  "Cpk <  1.00 : Not Capable"
)

verdict_col <- if (Cpk >= 1.33) "#E8F5E9" else if (Cpk >= 1.00) "#FFF3CD" else "#FDECEA"

p6 <- ggplot() +
  annotation_custom(
    grid::rectGrob(gp = grid::gpar(fill = verdict_col, col = NA))
  ) +
  annotate("text",
           x = 0.05, y = seq(0.95, 0.05, length.out = length(verdict_lines)),
           label = verdict_lines,
           hjust = 0, vjust = 1,
           size = 3.2, family = "mono",
           fontface = ifelse(seq_along(verdict_lines) == 1, "bold", "plain")) +
  xlim(0, 1) + ylim(0, 1) +
  labs(title = "Capability Verdict") +
  theme_void() +
  theme(plot.background = element_rect(fill = verdict_col, color = NA),
        plot.title = element_text(size = 9, face = "bold", hjust = 0, margin = margin(b = 4)))

# ---------------------------------------------------------------------------
# Save PNG — 3x2 grid
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_cap_sixpack.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 3600, height = 2400, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow    = 4,
  ncol    = 1,
  heights = unit(c(0.05, 0.31, 0.31, 0.33), "npc")
)))

# Title strip
pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
header_cp  <- if (!is.na(Cp)) sprintf("Cp=%.2f  ", Cp) else ""
header_pp  <- if (!is.na(Pp)) sprintf("  Pp=%.2f", Pp) else ""
grid.text(
  sprintf("Process Capability Sixpack  |  %s  |  n=%d  X-bar=%.4f  %sCpk=%.4f  Ppk=%.4f%s  |  %s",
          basename(data_file), n, x_bar, header_cp, Cpk, Ppk, header_pp, cap_verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

# Row 2: I chart + MR chart
pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

# Row 3: Histogram + Q-Q plot
pushViewport(viewport(layout.pos.row = 3,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p3, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p4, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

# Row 4: Summary + Verdict
pushViewport(viewport(layout.pos.row = 4,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p5, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p6, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

dev.off()

report_path <- NULL
if (want_report) {
  report_path <- save_sixpack_report(
    data_file, col_name, n, lsl, usl,
    x_bar, s_overall, sigma_w,
    Cp, Cpk, Pp, Ppk, Cpm,
    sigma_level, ppm_total, ppm_above, ppm_below,
    UCL_X, LCL_X, UCL_MR, MR_bar,
    n_ooc, spc_verdict, cap_verdict,
    sw_result$p.value, out_file
  )
}

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file, if (!is.null(report_path)) report_path else character(0)))
