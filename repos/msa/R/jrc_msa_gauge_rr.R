# =============================================================================
# jrc_msa_gauge_rr.R
# JR Validated Environment — MSA module
#
# Gauge Repeatability & Reproducibility (Gauge R&R) analysis — ANOVA method.
# Reads a CSV with columns: part, operator, value.
# Computes variance components (repeatability, reproducibility, part-to-part),
# reports %GRR and number of distinct categories (ndc), and saves a
# four-panel PNG to ~/Downloads/.
#
# Usage: jrc_msa_gauge_rr <data.csv> [--tolerance <value>]
#
# Arguments:
#   data.csv             CSV file with columns: part, operator, value
#   --tolerance <value>  Optional: process tolerance (USL - LSL). When
#                        supplied, %GRR vs tolerance is also reported.
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_msa_gauge_rr <data.csv> [--tolerance <value>] [--report]")
}

csv_file    <- args[1]
tolerance   <- NA_real_
want_report <- FALSE
i <- 2
while (i <= length(args)) {
  if (args[i] == "--tolerance" && i < length(args)) {
    tolerance <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(tolerance) || tolerance <= 0) {
      stop("--tolerance must be a positive number.")
    }
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
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
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
# Report generator (--report flag, requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

save_grr_report <- function(csv_file, tolerance,
                             n_parts, n_operators, n_reps, n_total,
                             df_part, MS_part, F_part, p_part,
                             df_op, MS_op, F_op, p_op,
                             df_int, MS_int, F_int, p_int,
                             df_res, MS_res,
                             var_repeat, var_reprod, var_op, var_int,
                             var_grr, var_part, var_total,
                             sd_repeat, sd_reprod, sd_grr, sd_part, sd_total,
                             pct_ev, pct_av, pct_grr, pct_pv,
                             pct_var_ev, pct_var_av, pct_var_grr, pct_var_pv,
                             pct_grr_tol, ndc, ndc_str,
                             verdict_grr, verdict_ndc,
                             png_path) {

  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  pf  <- function(x) sprintf("%.5f", x)
  p2  <- function(x) sprintf("%.2f%%", x)
  p4  <- function(x) sprintf("%.4f", x)

  overall_acceptable <- (verdict_grr != "UNACCEPTABLE") && (verdict_ndc == "ACCEPTABLE")
  v_color <- if (overall_acceptable) "#155724" else "#721c24"
  v_bg    <- if (overall_acceptable) "#d4edda"  else "#f8d7da"
  v_bdr   <- if (overall_acceptable) "#c3e6cb"  else "#f5c6cb"
  vdict_color <- function(v) {
    switch(v, "ACCEPTABLE" = "#155724", "MARGINAL" = "#856404", "#721c24")
  }

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("MSA-GRR-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  if (!is.null(png_path) && file.exists(png_path)) {
    b64     <- base64encode(png_path)
    img_tag <- paste0('<img src="data:image/png;base64,', b64,
                      '" alt="Gauge R&amp;R chart" width="100%" ',
                      'style="width:100%;height:auto;display:block;border:1px solid #ccc;">')
  } else {
    img_tag <- "<p><em>(Chart not available.)</em></p>"
  }

  css <- paste(c(
    "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}",
    "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1a1a1a;background:#fff;padding:24px}",
    ".report{background:#fff;max-width:900px;margin:0 auto;padding:40px 48px;border:1px solid #ccc;box-shadow:0 2px 10px rgba(0,0,0,.10)}",
    ".rpt-hdr{border-bottom:3px solid #1a3a6b;padding-bottom:14px;margin-bottom:24px}",
    ".rpt-hdr h1{font-size:1.45em;color:#1a3a6b;margin-bottom:2px}",
    ".rpt-hdr h2{font-size:1em;font-weight:normal;color:#555;margin-bottom:14px}",
    "table.meta{border-collapse:collapse}",
    "table.meta td{padding:3px 14px 3px 0;vertical-align:top;font-size:.91em}",
    "table.meta td.k{font-weight:600;color:#333;min-width:160px}",
    ".draft{color:#a00;font-weight:bold}",
    ".section{margin-top:26px}",
    ".sec-ttl{font-weight:700;color:#1a3a6b;border-bottom:1.5px solid #1a3a6b;padding-bottom:4px;margin-bottom:10px;font-size:.95em;text-transform:uppercase;letter-spacing:.04em}",
    "table.dt{width:100%;border-collapse:collapse;font-size:.91em}",
    "table.dt th{padding:5px 10px;border:1px solid #ccc;background:#f0f4f8;font-weight:600;text-align:left;font-size:.88em}",
    "table.dt td{padding:5px 10px;border:1px solid #ddd;vertical-align:top}",
    "table.dt td.l{width:220px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    "table.dt td.r{text-align:right;font-family:monospace}",
    paste0(".verdict{margin-top:12px;padding:11px 16px;border-radius:4px;font-size:1.05em;font-weight:bold;text-align:center;background:", v_bg, ";color:", v_color, ";border:2px solid ", v_bdr, "}"),
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;text-align:center;margin-bottom:24px;color:#999;font-size:.9em;min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;font-size:.79em;color:#999;text-align:center}",
    "@media print{body{background:#fff;padding:0}.report{border:none;box-shadow:none;padding:16px;max-width:100%}.verdict,table.dt td.f{-webkit-print-color-adjust:exact;print-color-adjust:exact}}"
  ), collapse = "\n")

  tol_setup_row <- if (!is.na(tolerance))
    paste0('<tr><td class="l">Tolerance (USL&minus;LSL)</td><td>', he(tolerance), '</td></tr>')
  else ""

  tol_result_row <- if (!is.na(tolerance))
    paste0('<tr><td class="l">%GRR vs Tolerance</td>',
           '<td class="r">', p2(pct_grr_tol), '</td>',
           '<td style="font-weight:bold;color:', vdict_color(if (pct_grr_tol < 10) "ACCEPTABLE" else if (pct_grr_tol < 30) "MARGINAL" else "UNACCEPTABLE"), '">',
           if (pct_grr_tol < 10) "ACCEPTABLE" else if (pct_grr_tol < 30) "MARGINAL" else "UNACCEPTABLE",
           '</td></tr>')
  else ""

  out <- c(
    '<!DOCTYPE html><html lang="en"><head>',
    '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>MSA Report &mdash; Gauge R&amp;R</title>',
    '<style>', css, '</style></head><body><div class="report">',

    '<div class="logo-wrap">[Insert company logo here &mdash; replace this box with your logo in Word]</div>',

    '<div class="rpt-hdr">',
    '<h1>Measurement System Analysis Report</h1>',
    '<h2>Gauge Repeatability &amp; Reproducibility &mdash; ANOVA Method</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_msa_gauge_rr v1.0 &mdash; JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    # 1. Purpose and Scope
    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Measurement System</td><td class="f">[describe the gauge / instrument under study]</td></tr>',
    '<tr><td class="l">Characteristic Measured</td><td class="f">[describe the product characteristic and unit of measure]</td></tr>',
    '<tr><td class="l">Purpose</td><td class="f">[state why this MSA is required, e.g.: qualification of measurement system prior to design verification testing]</td></tr>',
    paste0('<tr><td class="l">Acceptance Criterion</td><td class="f">%GRR &lt; 10% (ACCEPTABLE) per AIAG MSA 4th edition. ndc &ge; 5.</td></tr>'),
    '</table></div>',

    # 2. Study Setup
    '<div class="section"><div class="sec-ttl">2. Study Setup</div><table class="dt">',
    paste0('<tr><td class="l">Data File</td><td>', he(basename(csv_file)), '</td></tr>'),
    paste0('<tr><td class="l">Parts (samples)</td><td>', he(n_parts), '</td></tr>'),
    paste0('<tr><td class="l">Operators</td><td>', he(n_operators), '</td></tr>'),
    paste0('<tr><td class="l">Replicates per cell</td><td>', he(n_reps), '</td></tr>'),
    paste0('<tr><td class="l">Total observations</td><td>', he(n_total), '</td></tr>'),
    tol_setup_row,
    '<tr><td class="l">Study Conditions</td><td class="f">[describe measurement conditions, equipment calibration status, and date of study]</td></tr>',
    '</table></div>',

    # 3. Statistical Method
    '<div class="section"><div class="sec-ttl">3. Statistical Method</div><table class="dt">',
    '<tr><td class="l">Method</td><td>Two-way ANOVA with interaction (Part &times; Operator). Variance components estimated from ANOVA mean squares.</td></tr>',
    '<tr><td class="l">%GRR (%Study Var)</td><td>100 &times; (6 &times; SD_GRR) / (6 &times; SD_Total).</td></tr>',
    '<tr><td class="l">ndc</td><td>floor(1.41 &times; SD_Part / SD_GRR) &mdash; number of distinct product categories the gauge can discriminate.</td></tr>',
    '<tr><td class="l">Reference</td><td>AIAG (2010). <em>Measurement System Analysis Reference Manual</em>, 4th ed.</td></tr>',
    '</table></div>',

    # 4. Results
    '<div class="section"><div class="sec-ttl">4. Results</div>',

    # ANOVA table
    '<p style="font-weight:600;color:#333;margin-bottom:6px;margin-top:10px;">ANOVA Table</p>',
    '<table class="dt">',
    '<tr><th>Source</th><th style="text-align:right">DF</th><th style="text-align:right">Mean Sq</th><th style="text-align:right">F</th><th style="text-align:right">p</th></tr>',
    paste0('<tr><td>Part</td><td class="r">', df_part, '</td><td class="r">', pf(MS_part), '</td><td class="r">', sprintf("%.3f", F_part), '</td><td class="r">', sprintf("%.4f", p_part), '</td></tr>'),
    paste0('<tr><td>Operator</td><td class="r">', df_op, '</td><td class="r">', pf(MS_op), '</td><td class="r">', sprintf("%.3f", F_op), '</td><td class="r">', sprintf("%.4f", p_op), '</td></tr>'),
    paste0('<tr><td>Part:Operator</td><td class="r">', df_int, '</td><td class="r">', pf(MS_int), '</td><td class="r">', sprintf("%.3f", F_int), '</td><td class="r">', sprintf("%.4f", p_int), '</td></tr>'),
    paste0('<tr><td>Residual</td><td class="r">', df_res, '</td><td class="r">', pf(MS_res), '</td><td></td><td></td></tr>'),
    '</table>',

    # Variance components + %GRR summary
    '<p style="font-weight:600;color:#333;margin-bottom:6px;margin-top:14px;">Variance Components &amp; Study Variation</p>',
    '<table class="dt">',
    '<tr><th>Source</th><th style="text-align:right">Variance</th><th style="text-align:right">%Contribution</th><th style="text-align:right">StdDev</th><th style="text-align:right">%Study Var</th></tr>',
    paste0('<tr><td>Repeatability (EV)</td><td class="r">', pf(var_repeat), '</td><td class="r">', p2(pct_var_ev), '</td><td class="r">', pf(sd_repeat), '</td><td class="r">', p2(pct_ev), '</td></tr>'),
    paste0('<tr><td>Reproducibility (AV)</td><td class="r">', pf(var_reprod), '</td><td class="r">', p2(pct_var_av), '</td><td class="r">', pf(sd_reprod), '</td><td class="r">', p2(pct_av), '</td></tr>'),
    paste0('<tr><td style="padding-left:20px;font-style:italic">Operator</td><td class="r">', pf(var_op), '</td><td></td><td></td><td></td></tr>'),
    paste0('<tr><td style="padding-left:20px;font-style:italic">Part:Operator</td><td class="r">', pf(var_int), '</td><td></td><td></td><td></td></tr>'),
    paste0('<tr><td><strong>Gauge R&amp;R</strong></td><td class="r"><strong>', pf(var_grr), '</strong></td><td class="r"><strong>', p2(pct_var_grr), '</strong></td><td class="r"><strong>', pf(sd_grr), '</strong></td><td class="r"><strong>', p2(pct_grr), '</strong></td></tr>'),
    paste0('<tr><td>Part-to-Part</td><td class="r">', pf(var_part), '</td><td class="r">', p2(pct_var_pv), '</td><td class="r">', pf(sd_part), '</td><td class="r">', p2(pct_pv), '</td></tr>'),
    paste0('<tr><td>Total</td><td class="r">', pf(var_total), '</td><td class="r">100.00%</td><td class="r">', pf(sd_total), '</td><td class="r">100.00%</td></tr>'),
    '</table>',

    # Verdict table
    '<p style="font-weight:600;color:#333;margin-bottom:6px;margin-top:14px;">Verdict</p>',
    '<table class="dt">',
    paste0('<tr><td class="l">%GRR (%Study Var)</td><td class="r">', p2(pct_grr), '</td>',
           '<td style="font-weight:bold;color:', vdict_color(verdict_grr), '">', verdict_grr, '</td></tr>'),
    paste0('<tr><td class="l">ndc</td><td class="r">', he(ndc_str), '</td>',
           '<td style="font-weight:bold;color:', vdict_color(verdict_ndc), '">', verdict_ndc, '</td></tr>'),
    tol_result_row,
    '</table>',

    paste0('<div class="verdict">',
           if (overall_acceptable) "✅ Measurement system ACCEPTABLE" else "❌ Measurement system requires attention",
           '</div>'),
    '</div>',

    # 5. Chart
    '<div class="section"><div class="sec-ttl">5. Gauge R&amp;R Chart</div>',
    '<div style="text-align:center;margin-top:8px;">', img_tag, '</div></div>',

    # 6. Conclusion
    '<div class="section"><div class="sec-ttl">6. Conclusion</div><table class="dt">',
    paste0('<tr><td class="l">Outcome</td><td style="font-weight:bold;color:', v_color, '">',
           if (overall_acceptable) "✅ ACCEPTABLE" else "❌ NOT ACCEPTABLE", '</td></tr>'),
    '<tr><td class="l">Conclusion</td><td class="f">[state whether the measurement system is qualified for use; note any limitations]</td></tr>',
    '<tr><td class="l">Deviations / Observations</td><td class="f">[NONE &mdash; or describe any deviations from the planned study]</td></tr>',
    '</table></div>',

    # 7. Approvals
    '<div class="section"><div class="sec-ttl">7. Approvals</div>',
    '<table class="appr">',
    '<tr><th style="width:22%">Role</th><th style="width:28%">Name</th><th style="width:28%">Signature</th><th style="width:22%">Date</th></tr>',
    '<tr><td>Performed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</table></div>',

    paste0('<div class="rpt-footer">Generated by jrc_msa_gauge_rr v1.0 &mdash; JR Anchored &mdash; ', he(dt_str), '</div>'),
    '</div></body></html>'
  )

  out_file <- file.path(path.expand("~/Downloads"),
                        paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_gauge_rr_report.html"))
  writeLines(out, out_file, useBytes = TRUE)
  message(paste("✅ MSA report saved to:", out_file))
  invisible(out_file)
}

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------
if (!file.exists(csv_file)) {
  stop(paste("\u274c File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("part", "operator", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: part, operator, value"))
}

dat$part     <- as.factor(as.character(dat$part))
dat$operator <- as.factor(as.character(dat$operator))
dat$value    <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$value))) {
  stop("\u274c Non-numeric values found in the 'value' column.")
}

n_parts     <- nlevels(dat$part)
n_operators <- nlevels(dat$operator)

if (n_parts < 2)     stop("\u274c At least 2 parts are required.")
if (n_operators < 2) stop("\u274c At least 2 operators are required.")

# --- Check for balanced design (equal replicates per part-operator cell)
cell_counts <- table(dat$part, dat$operator)
rep_counts  <- unique(as.vector(cell_counts))
if (length(rep_counts) > 1) {
  stop(paste("\u274c Unbalanced design: cells have", paste(rep_counts, collapse = "/"),
             "replicates.\n   All part-operator combinations must have the same number",
             "of replicates."))
}
n_reps  <- rep_counts[1]
n_total <- nrow(dat)

if (n_reps < 2) {
  stop("\u274c At least 2 replicates per part-operator combination are required.")
}

# ---------------------------------------------------------------------------
# Two-way ANOVA with interaction
# ---------------------------------------------------------------------------
fit     <- aov(value ~ part * operator, data = dat)
aov_tbl <- summary(fit)[[1]]
rownames(aov_tbl) <- trimws(rownames(aov_tbl))

MS_part <- aov_tbl["part",          "Mean Sq"]
MS_op   <- aov_tbl["operator",      "Mean Sq"]
MS_int  <- aov_tbl["part:operator", "Mean Sq"]
MS_res  <- aov_tbl["Residuals",     "Mean Sq"]

F_part  <- aov_tbl["part",          "F value"]
F_op    <- aov_tbl["operator",      "F value"]
F_int   <- aov_tbl["part:operator", "F value"]

p_part  <- aov_tbl["part",          "Pr(>F)"]
p_op    <- aov_tbl["operator",      "Pr(>F)"]
p_int   <- aov_tbl["part:operator", "Pr(>F)"]

df_part <- aov_tbl["part",          "Df"]
df_op   <- aov_tbl["operator",      "Df"]
df_int  <- aov_tbl["part:operator", "Df"]
df_res  <- aov_tbl["Residuals",     "Df"]

# ---------------------------------------------------------------------------
# Variance components (expected mean squares, balanced two-way random model)
#
#   E[MS_res]  = sigma2_e
#   E[MS_int]  = sigma2_e + n * sigma2_int
#   E[MS_op]   = sigma2_e + n * sigma2_int + n_parts * n * sigma2_op
#   E[MS_part] = sigma2_e + n * sigma2_int + n_operators * n * sigma2_part
# ---------------------------------------------------------------------------
var_e   <- MS_res
var_int <- max(0, (MS_int - MS_res)  / n_reps)
var_op  <- max(0, (MS_op  - MS_int)  / (n_parts     * n_reps))
var_p   <- max(0, (MS_part - MS_int) / (n_operators * n_reps))

var_repeat <- var_e
var_reprod <- var_op + var_int          # interaction attributed to reproducibility
var_grr    <- var_repeat + var_reprod
var_part   <- var_p
var_total  <- var_grr + var_part

sd_repeat  <- sqrt(var_repeat)
sd_reprod  <- sqrt(var_reprod)
sd_grr     <- sqrt(var_grr)
sd_part    <- sqrt(var_part)
sd_total   <- sqrt(var_total)

safe_pct <- function(num, den) if (den > 0) 100 * num / den else 0

pct_ev    <- safe_pct(sd_repeat, sd_total)
pct_av    <- safe_pct(sd_reprod, sd_total)
pct_grr   <- safe_pct(sd_grr,    sd_total)
pct_pv    <- safe_pct(sd_part,   sd_total)

pct_var_ev  <- safe_pct(var_repeat, var_total)
pct_var_av  <- safe_pct(var_reprod, var_total)
pct_var_grr <- safe_pct(var_grr,    var_total)
pct_var_pv  <- safe_pct(var_part,   var_total)

ndc <- if (sd_grr > 0) floor(1.41 * sd_part / sd_grr) else Inf

pct_grr_tol <- if (!is.na(tolerance)) 100 * 6 * sd_grr / tolerance else NA_real_

verdict_grr <- if (pct_grr < 10) "ACCEPTABLE" else if (pct_grr < 30) "MARGINAL" else "UNACCEPTABLE"
verdict_ndc <- if (is.infinite(ndc) || ndc >= 5) "ACCEPTABLE" else "UNACCEPTABLE"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Gauge R&R Analysis — ANOVA Method\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Parts:      %d\n", n_parts))
cat(sprintf("  Operators:  %d\n", n_operators))
cat(sprintf("  Replicates: %d per cell\n", n_reps))
cat(sprintf("  Total obs:  %d\n\n", n_total))

cat("--- ANOVA Table -------------------------------------------------\n")
cat(sprintf("  %-22s %6s %12s %8s %8s\n", "Source", "DF", "Mean Sq", "F", "p"))
cat(sprintf("  %-22s %6d %12.5f %8.3f %8.4f\n",
            "Part",          df_part, MS_part, F_part, p_part))
cat(sprintf("  %-22s %6d %12.5f %8.3f %8.4f\n",
            "Operator",      df_op,   MS_op,   F_op,   p_op))
cat(sprintf("  %-22s %6d %12.5f %8.3f %8.4f\n",
            "Part:Operator", df_int,  MS_int,  F_int,  p_int))
cat(sprintf("  %-22s %6d %12.5f\n",
            "Residual",      df_res,  MS_res))
cat("\n")

cat("--- Variance Components -----------------------------------------\n")
cat(sprintf("  %-24s %12s %14s\n", "Source", "Variance", "%Contribution"))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Repeatability (EV)", var_repeat, pct_var_ev))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Reproducibility (AV)", var_reprod, pct_var_av))
cat(sprintf("    %-22s %12.6f\n", "Operator", var_op))
cat(sprintf("    %-22s %12.6f\n", "Part:Operator", var_int))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Gauge R&R", var_grr, pct_var_grr))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Part-to-Part", var_part, pct_var_pv))
cat(sprintf("  %-24s %12.6f\n", "Total", var_total))
cat("\n")

cat("--- Study Variation (%%Study Var) --------------------------------\n")
cat(sprintf("  %-24s %10s %12s\n", "Source", "StdDev", "%Study Var"))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Repeatability (EV)", sd_repeat, pct_ev))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Reproducibility (AV)", sd_reprod, pct_av))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Gauge R&R", sd_grr, pct_grr))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Part-to-Part", sd_part, pct_pv))
cat(sprintf("  %-24s %10.5f\n", "Total", sd_total))
cat("\n")

if (!is.na(tolerance)) {
  cat(sprintf("  %%GRR vs Tolerance (6\u03c3 / tolerance): %.2f%%\n\n", pct_grr_tol))
}

ndc_str <- if (is.infinite(ndc)) "\u221e" else as.character(ndc)
cat(sprintf("  Number of Distinct Categories (ndc): %s\n\n", ndc_str))

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %%GRR (%%Study Var): %.2f%%  \u2192  %s\n", pct_grr, verdict_grr))
cat(sprintf("  ndc:               %s      \u2192  %s\n", ndc_str, verdict_ndc))
if (!is.na(tolerance)) {
  verdict_tol <- if (pct_grr_tol < 10) "ACCEPTABLE" else if (pct_grr_tol < 30) "MARGINAL" else "UNACCEPTABLE"
  cat(sprintf("  %%GRR (vs Tol):     %.2f%%  \u2192  %s\n", pct_grr_tol, verdict_tol))
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_EV   <- "#4472C4"
COL_AV   <- "#ED7D31"
COL_GRR  <- "#5DAD5D"
COL_PV   <- "#9E9E9E"
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

# --- Panel 1: Components of variation ---
comp_df <- data.frame(
  source = factor(
    c("Repeatability\n(EV)", "Reproducibility\n(AV)", "Gauge R&R", "Part-to-Part"),
    levels = c("Repeatability\n(EV)", "Reproducibility\n(AV)", "Gauge R&R", "Part-to-Part")
  ),
  pct   = c(pct_ev, pct_av, pct_grr, pct_pv),
  col   = c(COL_EV, COL_AV, COL_GRR, COL_PV)
)

p1 <- ggplot(comp_df, aes(x = source, y = pct, fill = source)) +
  geom_col(width = 0.6, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.1f%%", pct)), vjust = -0.4, size = 3) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "darkgreen", linewidth = 0.5, alpha = 0.8) +
  geom_hline(yintercept = 30, linetype = "dashed", color = "red",       linewidth = 0.5, alpha = 0.8) +
  scale_fill_manual(values = setNames(comp_df$col, comp_df$source)) +
  scale_y_continuous(
    limits = c(0, max(115, max(comp_df$pct) * 1.15)),
    labels = function(x) paste0(x, "%")
  ) +
  labs(title = "Components of Variation", x = NULL, y = "% Study Variation") +
  theme_jr

# --- Panel 2: Measurements by part ---
p2 <- ggplot(dat, aes(x = part, y = value)) +
  geom_boxplot(fill = COL_PV, color = "#555555", outlier.shape = NA, width = 0.5) +
  geom_jitter(width = 0.15, size = 1.4, alpha = 0.55, color = "#333333") +
  labs(title = "Measurements by Part", x = "Part", y = "Value") +
  theme_jr

# --- Panel 3: Measurements by operator ---
p3 <- ggplot(dat, aes(x = operator, y = value)) +
  geom_boxplot(fill = COL_AV, color = "#555555", outlier.shape = NA, width = 0.5) +
  geom_jitter(width = 0.15, size = 1.4, alpha = 0.55, color = "#333333") +
  labs(title = "Measurements by Operator", x = "Operator", y = "Value") +
  theme_jr

# --- Panel 4: Part × Operator interaction ---
inter_df <- aggregate(value ~ part + operator, data = dat, FUN = mean)
p4 <- ggplot(inter_df, aes(x = part, y = value, color = operator, group = operator)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5) +
  labs(title = "Part \u00d7 Operator Interaction",
       x = "Part", y = "Mean Value", color = "Operator") +
  theme_jr +
  theme(legend.position = "right", legend.key.size = unit(0.5, "cm"))

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_msa_gauge_rr.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1800, res = 180, bg = BG)

grid.newpage()

# Title strip at top
pushViewport(viewport(layout = grid.layout(
  nrow   = 2,
  ncol   = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Gauge R&R  |  %s  |  %%GRR = %.1f%%  |  ndc = %s  |  %s",
          basename(csv_file), pct_grr, ndc_str, verdict_grr),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 2, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
print(p3, vp = viewport(layout.pos.row = 2, layout.pos.col = 1))
print(p4, vp = viewport(layout.pos.row = 2, layout.pos.col = 2))
popViewport()

dev.off()

cat(sprintf("\u2705 Done. Open %s to view your plot.\n", basename(out_file)))

# ---------------------------------------------------------------------------
# HTML report (--report flag, requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

report_path <- NULL

if (want_report) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates",
                        "dv_report_template.html")
  if (!file.exists(sentinel)) {
    message("\u274c  --report is not available.")
    message("")
    message("   This feature requires the JR Anchored Validation Pack.")
    message("   To enable it, install the Validation Pack and run install.sh.")
    message("   The installer copies dv_report_template.html into:")
    message(paste0("     ", file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates")))
    message("")
    message("   Contact dwylup.com to purchase the JR Anchored Validation Pack.")
    message("")
    quit(save = "no", status = 1)
  }
  report_path <- save_grr_report(
    csv_file, tolerance,
    n_parts, n_operators, n_reps, n_total,
    df_part, MS_part, F_part, p_part,
    df_op, MS_op, F_op, p_op,
    df_int, MS_int, F_int, p_int,
    df_res, MS_res,
    var_repeat, var_reprod, var_op, var_int,
    var_grr, var_part, var_total,
    sd_repeat, sd_reprod, sd_grr, sd_part, sd_total,
    pct_ev, pct_av, pct_grr, pct_pv,
    pct_var_ev, pct_var_av, pct_var_grr, pct_var_pv,
    pct_grr_tol, ndc, ndc_str,
    verdict_grr, verdict_ndc,
    out_file
  )
}

jr_log_output_hashes(c(out_file, if (!is.null(report_path)) report_path else character(0)))
