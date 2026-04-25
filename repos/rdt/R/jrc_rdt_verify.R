#!/usr/bin/env Rscript
#
# use as: Rscript jrc_rdt_verify.R <data.csv> --reliability R --confidence C --target_life T [options]
#
# data.csv    CSV with at least a time column and a status column (0=survived, 1=failed).
#
# Evaluates whether a pre-specified reliability claim is demonstrated by actual
# test results. Two methods are always reported:
#
#   Binomial (Clopper-Pearson): no Weibull shape assumption. Counts units that
#   failed at or before target_life as failures; all others as suspensions.
#
#   Weibayes (--beta required): uses accumulated Weibull time from all units.
#   Failures at or before target_life count toward k; all units contribute their
#   actual effective time to the Weibayes sum.
#
# Verdict exits 0 for both PASS and FAIL. Non-zero exit is reserved for input
# errors and runtime failures.
#
# Core formulas:
#   Binomial:  R_lower = 1 - qbeta(C, k+1, n-k)            [Clopper-Pearson]
#   Weibayes:  R_demo  = exp( -target_life^beta * qchisq(C, 2*(k+1)) / (2*T*) )
#              where T* = sum(t_eff_i ^ beta) over all n units
#
# Needs only base R and ggplot2 (already pinned).
#
# References:
#   Meeker, Hahn & Escobar (2017). Statistical Intervals, 2nd ed. Wiley. Ch. 8.
#   Nelson (2004). Accelerated Testing. Wiley.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Helpers (before renv)
# ---------------------------------------------------------------------------

parse_flag <- function(args, flag, default = NA, numeric = FALSE) {
  idx <- which(args == flag)
  if (length(idx) == 0) return(default)
  if (idx[1] >= length(args)) stop(paste(flag, "requires a value."))
  val <- args[idx[1] + 1]
  if (numeric) {
    num <- suppressWarnings(as.numeric(val))
    if (is.na(num)) stop(paste0(flag, " must be numeric. Got: ", val))
    return(num)
  }
  val
}

flag_present <- function(args, flag) flag %in% args

# ---------------------------------------------------------------------------
# Argument parsing (before renv)
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- flag_present(args, "--report")
args        <- args[args != "--report"]

if (length(args) == 0 || flag_present(args, "--help") || flag_present(args, "-h")) {
  cat("\nUsage: jrc_rdt_verify <data.csv> --reliability R --confidence C --target_life T [options]\n\n")
  cat("Required:\n")
  cat("  data.csv            Path to CSV file with test results\n")
  cat("  --reliability R     Reliability claimed in the test plan (e.g. 0.95)\n")
  cat("  --confidence C      Confidence level from the test plan (e.g. 0.90)\n")
  cat("  --target_life T     Life at which reliability was claimed (e.g. 5000)\n\n")
  cat("Optional:\n")
  cat("  --time_col NAME     Column name for test times (default: \"time\")\n")
  cat("  --status_col NAME   Column name for event indicator (default: \"status\")\n")
  cat("                      0 = survived / right-censored, 1 = failed\n")
  cat("  --beta B            Weibull shape parameter. Enables Weibayes evaluation.\n")
  cat("                      Must match the value used in jrc_rdt_plan.\n")
  cat("  --accel_factor AF   Life-extension multiplier used in the test (default: 1.0)\n")
  cat("                      t_eff = time * accel_factor for each unit.\n")
  cat("                      Must match the value used in jrc_rdt_plan.\n\n")
  cat("CSV format:\n")
  cat("  unit_id,time,status\n")
  cat("  1,5000,0\n")
  cat("  2,4850,1\n")
  cat("  ...\n\n")
  cat("Example:\n")
  cat("  jrc_rdt_verify results.csv --reliability 0.95 --confidence 0.90 --target_life 5000\n")
  cat("  jrc_rdt_verify results.csv --reliability 0.95 --confidence 0.90 --target_life 5000 --beta 2.0\n\n")
  quit(status = 0)
}

# First non-flag argument is the CSV path
non_flag_args <- args[!startsWith(args, "--") & !startsWith(args, "-")]
flag_values   <- grep("^-", args)
# Remove values that follow a flag (they belong to the flag, not positional)
positional <- c()
skip_next  <- FALSE
for (i in seq_along(args)) {
  if (skip_next) { skip_next <- FALSE; next }
  if (startsWith(args[i], "-")) { skip_next <- TRUE; next }
  positional <- c(positional, args[i])
}

if (length(positional) == 0) stop("CSV file path is required as the first argument.")
file_path <- positional[1]

reliability  <- parse_flag(args, "--reliability",  NA,  numeric = TRUE)
confidence   <- parse_flag(args, "--confidence",   NA,  numeric = TRUE)
target_life  <- parse_flag(args, "--target_life",  NA,  numeric = TRUE)
time_col     <- parse_flag(args, "--time_col",     "time")
status_col   <- parse_flag(args, "--status_col",   "status")
beta         <- parse_flag(args, "--beta",         NA,  numeric = TRUE)
accel_factor <- parse_flag(args, "--accel_factor", 1.0, numeric = TRUE)

if (is.na(reliability)) stop("--reliability is required.")
if (is.na(confidence))  stop("--confidence is required.")
if (is.na(target_life)) stop("--target_life is required.")

if (reliability <= 0 || reliability >= 1)
  stop(paste("--reliability must be strictly between 0 and 1. Got:", reliability))
if (confidence <= 0 || confidence >= 1)
  stop(paste("--confidence must be strictly between 0 and 1. Got:", confidence))
if (target_life <= 0)
  stop(paste("--target_life must be > 0. Got:", target_life))
if (!is.na(beta) && beta <= 0)
  stop(paste("--beta must be > 0. Got:", beta))
if (accel_factor < 1.0)
  stop(paste("--accel_factor must be >= 1.0. Got:", accel_factor))
if (!file.exists(file_path))
  stop(paste("File not found:", file_path))

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
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

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(base64enc)
})

# ---------------------------------------------------------------------------
# Report generator (--report flag, requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

save_rdt_report <- function(file_path, n, k, n_suspensions,
                             reliability, confidence, target_life, accel_factor,
                             use_weibayes, beta,
                             F_upper_binom, R_lower_binom, pass_binom, margin_binom,
                             T_star, T_threshold, eta_demo, R_demo_wb, pass_wb, margin_wb,
                             overall_pass, png_path) {

  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  fmt4 <- function(x) sprintf("%.4f", x)

  v_text  <- if (overall_pass) "PASS" else "FAIL"
  v_icon  <- if (overall_pass) "✅" else "❌"
  v_color <- if (overall_pass) "#155724" else "#721c24"
  v_bg    <- if (overall_pass) "#d4edda"  else "#f8d7da"
  v_bdr   <- if (overall_pass) "#c3e6cb"  else "#f5c6cb"
  p_icon  <- function(p) if (p) "✅ PASS" else "❌ FAIL"
  p_col   <- function(p) if (p) "#155724" else "#721c24"

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-RDT-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  if (!is.null(png_path) && file.exists(png_path)) {
    b64     <- base64encode(png_path)
    img_tag <- paste0('<img src="data:image/png;base64,', b64,
                      '" alt="RDT results chart" width="100%" ',
                      'style="width:100%;height:auto;display:block;border:1px solid #ccc;">')
  } else {
    img_tag <- "<p><em>(Chart not available.)</em></p>"
  }

  css <- paste(c(
    "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}",
    "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1a1a1a;background:#fff;padding:24px}",
    ".report{background:#fff;max-width:820px;margin:0 auto;padding:40px 48px;border:1px solid #ccc;box-shadow:0 2px 10px rgba(0,0,0,.10)}",
    ".rpt-hdr{border-bottom:3px solid #1a3a6b;padding-bottom:14px;margin-bottom:24px}",
    ".rpt-hdr h1{font-size:1.45em;color:#1a3a6b;margin-bottom:2px}",
    ".rpt-hdr h2{font-size:1em;font-weight:normal;color:#555;margin-bottom:14px}",
    "table.meta{border-collapse:collapse}",
    "table.meta td{padding:3px 14px 3px 0;vertical-align:top;font-size:.91em}",
    "table.meta td.k{font-weight:600;color:#333;min-width:160px}",
    ".draft{color:#a00;font-weight:bold}",
    ".section{margin-top:26px}",
    ".sec-ttl{font-weight:700;color:#1a3a6b;border-bottom:1.5px solid #1a3a6b;padding-bottom:4px;margin-bottom:10px;font-size:.95em;text-transform:uppercase;letter-spacing:.04em}",
    "table.dt{width:100%;border-collapse:collapse;font-size:.93em}",
    "table.dt td{padding:5px 10px;border:1px solid #ddd;vertical-align:top}",
    "table.dt td.l{width:240px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    "table.dt td.sub{padding-left:24px;font-style:italic;color:#555}",
    ".subsec{font-weight:600;color:#1a3a6b;margin-top:14px;margin-bottom:4px;font-size:.88em;text-transform:uppercase;letter-spacing:.03em}",
    paste0(".verdict{margin-top:12px;padding:11px 16px;border-radius:4px;font-size:1.05em;font-weight:bold;text-align:center;background:", v_bg, ";color:", v_color, ";border:2px solid ", v_bdr, "}"),
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;text-align:center;margin-bottom:24px;color:#999;font-size:.9em;min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;font-size:.79em;color:#999;text-align:center}",
    "@media print{body{background:#fff;padding:0}.report{border:none;box-shadow:none;padding:16px;max-width:100%}.verdict,table.dt td.f{-webkit-print-color-adjust:exact;print-color-adjust:exact}}"
  ), collapse = "\n")

  wb_method_row <- if (use_weibayes)
    paste0('<tr><td class="l">Weibayes Method</td><td>R_demo = exp(-(T_target/&eta;_demo)^&beta;), ',
           'where &eta;_demo = (2T* / &chi;&sup2;(C, 2(k+1)))^(1/&beta;) and T* = &Sigma;(t_eff^&beta;).</td></tr>')
  else ""

  wb_ref_row <- if (use_weibayes)
    '<tr><td class="l">Weibayes Reference</td><td>Nelson, W. (2004). <em>Accelerated Testing</em>. Wiley.</td></tr>'
  else ""

  binom_verdict_style <- paste0('style="font-weight:bold;color:', p_col(pass_binom), '"')
  wb_rows <- if (use_weibayes) c(
    '<tr><td class="l" colspan="2"><div class="subsec">Weibayes Method</div></td></tr>',
    paste0('<tr><td class="l">Weibull shape (&beta;)</td><td>', he(sprintf("%.2f", beta)), '</td></tr>'),
    paste0('<tr><td class="l">T* = &Sigma;(t_eff^&beta;)</td><td>', he(sprintf("%.4e", T_star)), '</td></tr>'),
    paste0('<tr><td class="l">T_threshold</td><td>', he(sprintf("%.4e", T_threshold)), '</td></tr>'),
    paste0('<tr><td class="l">T* / T_threshold</td><td>', he(sprintf("%.3f", T_star / T_threshold)),
           if (T_star >= T_threshold) ' &mdash; criterion met' else ' &mdash; criterion NOT met', '</td></tr>'),
    paste0('<tr><td class="l">Demonstrated &eta; (char. life)</td><td>', he(sprintf("%.2f", eta_demo)), '</td></tr>'),
    paste0('<tr><td class="l">Demonstrated R at target life</td><td>', he(fmt4(R_demo_wb)), '</td></tr>'),
    paste0('<tr><td class="l">Margin (R_demo &minus; claim)</td><td>', he(sprintf("%+.4f", margin_wb)), '</td></tr>'),
    paste0('<tr><td class="l">Weibayes Verdict</td><td ', paste0('style="font-weight:bold;color:', p_col(pass_wb), '"'), '>',
           p_icon(pass_wb), '</td></tr>')
  ) else character(0)

  out <- c(
    '<!DOCTYPE html><html lang="en"><head>',
    '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Design Verification Report &mdash; RDT</title>',
    '<style>', css, '</style></head><body><div class="report">',

    '<div class="logo-wrap">[Insert company logo here &mdash; replace this box with your logo in Word]</div>',

    '<div class="rpt-hdr">',
    '<h1>Design Verification Report</h1>',
    '<h2>Reliability Demonstration Test &mdash; Post-Test Evaluation</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_rdt_verify v1.0 &mdash; JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    # 1. Purpose and Scope
    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Requirement Reference</td><td class="f">[enter design input or design output requirement ID and description]</td></tr>',
    '<tr><td class="l">Design Input / Output</td><td class="f">[state whether this verifies a Design Input (DI) or Design Output (DO)]</td></tr>',
    '<tr><td class="l">Purpose of Verification</td><td class="f">[describe what reliability claim is being demonstrated and the test rationale]</td></tr>',
    paste0('<tr><td class="l">Acceptance Criterion</td><td class="f">Reliability R &ge; ', he(reliability),
           ' at target life ', he(target_life), ' demonstrated with ', he(confidence * 100), '% confidence.</td></tr>'),
    '</table></div>',

    # 2. Test Setup
    '<div class="section"><div class="sec-ttl">2. Test Setup</div><table class="dt">',
    paste0('<tr><td class="l">Data File</td><td>', he(basename(file_path)), '</td></tr>'),
    paste0('<tr><td class="l">Units Tested (n)</td><td>', he(n), '</td></tr>'),
    paste0('<tr><td class="l">Target Life</td><td>', he(target_life), '</td></tr>'),
    paste0('<tr><td class="l">Reliability Claim (R)</td><td>', he(reliability), '</td></tr>'),
    paste0('<tr><td class="l">Confidence Level (C)</td><td>', he(confidence), '</td></tr>'),
    if (accel_factor > 1.0) paste0('<tr><td class="l">Acceleration Factor</td><td>', he(accel_factor), '</td></tr>') else "",
    if (use_weibayes) paste0('<tr><td class="l">Weibull Shape (&beta;)</td><td>', he(sprintf("%.2f", beta)), '</td></tr>') else "",
    '<tr><td class="l">Test Conditions</td><td class="f">[describe test conditions, equipment, environment, and dates]</td></tr>',
    '</table></div>',

    # 3. Statistical Method
    '<div class="section"><div class="sec-ttl">3. Statistical Method</div><table class="dt">',
    '<tr><td class="l">Binomial Method</td><td>Clopper-Pearson exact one-sided CI on the failure fraction at target life. R_lower = 1 &minus; Beta(C; k+1, n&minus;k).</td></tr>',
    wb_method_row,
    '<tr><td class="l">Binomial Reference</td><td>Meeker, Hahn &amp; Escobar (2017). <em>Statistical Intervals</em>, 2nd ed. Wiley. Ch. 8.</td></tr>',
    wb_ref_row,
    '</table></div>',

    # 4. Results
    '<div class="section"><div class="sec-ttl">4. Results</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">Units Tested (n)</td><td>', he(n), '</td></tr>'),
    paste0('<tr><td class="l">Failures at Target Life (k)</td><td>', he(k), '</td></tr>'),
    paste0('<tr><td class="l">Suspensions (survived)</td><td>', he(n_suspensions), '</td></tr>'),
    '<tr><td class="l" colspan="2"><div class="subsec">Binomial Verification (Clopper-Pearson)</div></td></tr>',
    paste0('<tr><td class="l">Upper Bound on Fail Rate</td><td>F_upper = ', he(fmt4(F_upper_binom)),
           ' (', he(sprintf("%.1f%%", F_upper_binom * 100)), ')</td></tr>'),
    paste0('<tr><td class="l">Demonstrated R Lower Bound</td><td>R_lower = ', he(fmt4(R_lower_binom)), '</td></tr>'),
    paste0('<tr><td class="l">Margin (R_lower &minus; claim)</td><td>', he(sprintf("%+.4f", margin_binom)), '</td></tr>'),
    paste0('<tr><td class="l">Binomial Verdict</td><td ', binom_verdict_style, '>', p_icon(pass_binom), '</td></tr>'),
    wb_rows,
    '</table>',
    paste0('<div class="verdict">', v_icon, ' Overall Verification Outcome: ', v_text, '</div>',
           if (use_weibayes && pass_binom != pass_wb)
             '<p style="margin-top:8px;font-size:.88em;color:#555;">Note: Binomial and Weibayes verdicts differ. Document the basis for the assumed &beta; value.</p>'
           else ""),
    '</div>',

    # 5. Chart
    '<div class="section"><div class="sec-ttl">5. Test Results Chart</div>',
    '<div style="text-align:center;margin-top:8px;">', img_tag, '</div></div>',

    # 6. Conclusion
    '<div class="section"><div class="sec-ttl">6. Conclusion</div><table class="dt">',
    paste0('<tr><td class="l">Outcome</td><td style="font-weight:bold;color:', v_color, '">', v_icon, ' ', v_text, '</td></tr>'),
    '<tr><td class="l">Conclusion</td><td class="f">[state whether the reliability requirement is demonstrated; summarise the statistical evidence]</td></tr>',
    '<tr><td class="l">Deviations / Observations</td><td class="f">[NONE &mdash; or describe any deviations from the test plan]</td></tr>',
    '</table></div>',

    # 7. Approvals
    '<div class="section"><div class="sec-ttl">7. Approvals</div>',
    '<table class="appr">',
    '<tr><th style="width:22%">Role</th><th style="width:28%">Name</th><th style="width:28%">Signature</th><th style="width:22%">Date</th></tr>',
    '<tr><td>Performed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</table></div>',

    paste0('<div class="rpt-footer">Generated by jrc_rdt_verify v1.0 &mdash; JR Anchored &mdash; ', he(dt_str), '</div>'),
    '</div></body></html>'
  )

  out_file <- file.path(path.expand("~/Downloads"),
                        paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_rdt_verification_report.html"))
  writeLines(out, out_file, useBytes = TRUE)
  message(paste("✅ Verification report saved to:", out_file))

  jvs <- function(x) if (is.null(x) || (length(x) == 1 && is.na(x))) "null" else paste0('"', gsub('"', '\\"', as.character(x)), '"')
  jvn <- function(x, fmt = "%.6g") if (is.null(x) || (length(x) == 1 && is.na(x))) "null" else sprintf(fmt, as.numeric(x))
  jvb <- function(x) if (isTRUE(x)) "true" else "false"

  method_rows <- paste0(
    '{"k":"Method","v":', jvs(if (use_weibayes) "Binomial Clopper-Pearson + Weibayes" else "Binomial Clopper-Pearson"), '},',
    '{"k":"Binomial reference","v":"Meeker, Hahn & Escobar (2017). Statistical Intervals, 2nd ed."},',
    '{"k":"Reliability claim (R)","v":', jvn(reliability, "%.4f"), '},',
    '{"k":"Confidence level (C)","v":', jvn(confidence, "%.4f"), '},',
    '{"k":"Target life","v":', jvn(target_life), '},',
    '{"k":"Acceleration factor","v":', jvn(accel_factor), '},',
    '{"k":"Weibull shape (beta)","v":', jvn(beta, "%.2f"), '}'
  )

  wb_verdict_str <- if (!use_weibayes || is.na(pass_wb)) "null" else if (pass_wb) '"PASS"' else '"FAIL"'

  results_rows <- paste0(
    '{"k":"Data file","v":', jvs(basename(file_path)), '},',
    '{"k":"n (units tested)","v":', jvn(n, "%.0f"), '},',
    '{"k":"k (failures at target life)","v":', jvn(k, "%.0f"), '},',
    '{"k":"Suspensions","v":', jvn(n_suspensions, "%.0f"), '},',
    '{"k":"F_upper (binomial)","v":', jvn(F_upper_binom, "%.4f"), '},',
    '{"k":"R_lower (binomial)","v":', jvn(R_lower_binom, "%.4f"), '},',
    '{"k":"Binomial margin","v":', jvn(margin_binom, "%.4f"), '},',
    '{"k":"Binomial verdict","v":', jvs(if (pass_binom) "PASS" else "FAIL"), '},',
    '{"k":"T_star","v":', jvn(T_star, "%.4e"), '},',
    '{"k":"T_threshold","v":', jvn(T_threshold, "%.4e"), '},',
    '{"k":"eta_demo (char. life)","v":', jvn(eta_demo, "%.2f"), '},',
    '{"k":"R_demo (Weibayes)","v":', jvn(R_demo_wb, "%.4f"), '},',
    '{"k":"Weibayes margin","v":', jvn(margin_wb, "%.4f"), '},',
    '{"k":"Weibayes verdict","v":', wb_verdict_str, '},',
    '{"k":"Overall verdict","v":', jvs(if (overall_pass) "PASS" else "FAIL"), '}'
  )

  json_str <- paste0(
    '{"report_type":"rdt",',
    '"script":"jrc_rdt_verify",',
    '"version":"1.0",',
    '"report_id":', jvs(report_id), ',',
    '"generated":', jvs(dt_str), ',',
    '"verdict_pass":', jvb(overall_pass), ',',
    '"lsl":null,"usl":null,',
    '"use_weibayes":', if (use_weibayes) "true" else "false", ',',
    '"png_path":', jvs(png_path), ',',
    '"method":[', method_rows, '],',
    '"results":[', results_rows, ']}'
  )

  json_path <- sub("\\.html$", "_data.json", out_file)
  writeLines(json_str, json_path)
  message(sprintf("  JSON sidecar: %s", json_path))
  pack_py <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "pack", "jr_pack.py")
  if (file.exists(pack_py)) {
    ret       <- system2("python3",
                         args   = c(shQuote(pack_py), "deliverables", "rdt-report",
                                    "--json", shQuote(json_path)),
                         stdout = TRUE, stderr = TRUE)
    exit_code <- attr(ret, "status")
    if (is.null(exit_code)) exit_code <- 0L
    message(paste(ret, collapse = "\n"))
    if (exit_code != 0L) {
      message(sprintf("   Retry manually: jr_pack deliverables rdt-report --json %s", json_path))
    } else {
      docx_line <- grep("saved to:", ret, value = TRUE)
      if (length(docx_line) > 0L)
        jr_log_report(trimws(sub(".*saved to:\\s*", "", docx_line[1L])))
      if (file.exists(out_file))  file.remove(out_file)
      if (file.exists(json_path)) file.remove(json_path)
    }
  } else {
    message(sprintf("   Run: jr_pack deliverables rdt-report --json %s", json_path))
  }

  invisible(c(html = out_file, json = json_path))
}

# ---------------------------------------------------------------------------
# Style constants
# ---------------------------------------------------------------------------

BG        <- "#FFFFFF"
CLR_PASS  <- "#2166AC"
CLR_FAIL  <- "#D6604D"
CLR_CLAIM <- "#555555"
CLR_SURV  <- "#4393C3"
CLR_FAIL2 <- "#D6604D"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    plot.title       = element_text(size = 10, face = "bold"),
    plot.subtitle    = element_text(size = 8, color = "#555555"),
    axis.title       = element_text(size = 9),
    axis.text        = element_text(size = 8)
  )

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

dat <- tryCatch(
  read.csv(file_path, stringsAsFactors = FALSE),
  error = function(e) stop(paste("Could not read CSV:", conditionMessage(e)))
)

if (!time_col %in% names(dat))
  stop(paste0("Column '", time_col, "' not found in ", basename(file_path),
              ". Available columns: ", paste(names(dat), collapse = ", ")))
if (!status_col %in% names(dat))
  stop(paste0("Column '", status_col, "' not found in ", basename(file_path),
              ". Available columns: ", paste(names(dat), collapse = ", ")))

times   <- suppressWarnings(as.numeric(dat[[time_col]]))
statuses <- suppressWarnings(as.integer(dat[[status_col]]))

if (any(is.na(times)))
  stop(paste0("Non-numeric or missing values in column '", time_col, "'."))
if (any(is.na(statuses)) || any(!statuses %in% c(0L, 1L)))
  stop(paste0("Column '", status_col, "' must contain only 0 (survived) and 1 (failed)."))
if (any(times <= 0))
  stop(paste0("All values in '", time_col, "' must be positive."))
if (nrow(dat) < 2)
  stop("At least 2 units are required.")

# ---------------------------------------------------------------------------
# Compute effective times and classify units
# ---------------------------------------------------------------------------

t_eff <- times * accel_factor

# Failure at or before target_life: counts toward k in both binomial and Weibayes
is_failure_at_horizon <- (statuses == 1L) & (t_eff <= target_life)
n <- length(t_eff)
k <- sum(is_failure_at_horizon)

# Suspensions = survived to test end OR failed beyond target_life
n_failures    <- k
n_suspensions <- n - k

# ---------------------------------------------------------------------------
# Binomial (Clopper-Pearson)
# ---------------------------------------------------------------------------

# Upper confidence bound on failure fraction at target_life
# n - k == 0 (all units failed before target life): UCB on fail rate = 1 → R_lower = 0
if (n - k == 0L) {
  F_upper_binom <- 1.0
} else {
  F_upper_binom <- qbeta(confidence, k + 1, n - k)
}
R_lower_binom <- 1 - F_upper_binom
pass_binom    <- R_lower_binom >= reliability
margin_binom  <- R_lower_binom - reliability

# ---------------------------------------------------------------------------
# Weibayes (if beta provided)
# ---------------------------------------------------------------------------

use_weibayes  <- !is.na(beta)
R_demo_wb     <- NA
pass_wb       <- NA
margin_wb     <- NA
eta_demo      <- NA
T_star        <- NA
T_threshold   <- NA

if (use_weibayes) {
  # T* includes all units with their actual effective time
  T_star      <- sum(t_eff^beta)
  T_threshold <- qchisq(confidence, 2L * (k + 1L)) * target_life^beta /
                 (2 * (-log(reliability)))
  eta_demo    <- (2 * T_star / qchisq(confidence, 2L * (k + 1L)))^(1 / beta)
  R_demo_wb   <- exp(-(target_life / eta_demo)^beta)
  pass_wb     <- R_demo_wb >= reliability
  margin_wb   <- R_demo_wb - reliability
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Reliability Demonstration Test — Verification\n")
cat(sprintf("  File: %s\n", basename(file_path)))
cat(sprintf("  Claim: R >= %g at %g  |  Confidence: %g\n",
            reliability, target_life, confidence))
if (use_weibayes) {
  cat(sprintf("  Weibayes: beta = %.2f  |  Accel factor: %.4g\n", beta, accel_factor))
} else if (accel_factor > 1.0) {
  cat(sprintf("  Accel factor: %.4g\n", accel_factor))
}
cat("=================================================================\n\n")

cat(sprintf("  Units tested:               %d\n", n))
cat(sprintf("  Failures at target life:    %d\n", n_failures))
cat(sprintf("  Suspensions (survived):     %d\n", n_suspensions))
if (any((statuses == 1L) & (t_eff > target_life))) {
  n_late <- sum((statuses == 1L) & (t_eff > target_life))
  cat(sprintf("  Failures beyond target:     %d  (treated as suspensions)\n", n_late))
}
cat("\n")

# Binomial section
cat("--- Binomial Verification (Clopper-Pearson) ---------------------\n")
cat(sprintf("  Failures at target life:    k = %d of n = %d\n", k, n))
cat(sprintf("  Upper bound on fail rate:   F_upper = %.4f  (%.1f%%)\n",
            F_upper_binom, F_upper_binom * 100))
cat(sprintf("  Demonstrated R lower bound: R_lower = %.4f\n", R_lower_binom))
cat("\n")
cat(sprintf("  Claim:    R >= %g at %g, confidence %g\n",
            reliability, target_life, confidence))
cat(sprintf("  Margin:   R_lower - R_claim = %+.4f\n", margin_binom))
cat("\n")
if (pass_binom) {
  cat(sprintf("  Verdict: PASS  (R_lower %.4f >= claim %g)\n", R_lower_binom, reliability))
} else {
  cat(sprintf("  Verdict: FAIL  (R_lower %.4f < claim %g)\n", R_lower_binom, reliability))
}
cat("-----------------------------------------------------------------\n\n")

# Weibayes section
if (use_weibayes) {
  cat("--- Weibayes Verification ---------------------------------------\n")
  cat(sprintf("  beta = %.2f  |  T* = sum(t_eff_i ^ beta) = %.4e\n", beta, T_star))
  cat(sprintf("  T_threshold (plan criterion):          %.4e\n", T_threshold))
  cat(sprintf("  T* / T_threshold:                      %.3f  %s\n",
              T_star / T_threshold,
              if (T_star >= T_threshold) "[ PASS criterion met ]" else "[ PASS criterion NOT met ]"))
  cat(sprintf("  Demonstrated eta (char. life):         %.2f\n", eta_demo))
  cat(sprintf("  Demonstrated R at %g:               %.4f\n", target_life, R_demo_wb))
  cat("\n")
  cat(sprintf("  Claim:    R >= %g at %g, confidence %g\n",
              reliability, target_life, confidence))
  cat(sprintf("  Margin:   R_demo - R_claim = %+.4f\n", margin_wb))
  cat("\n")
  if (pass_wb) {
    cat(sprintf("  Verdict: PASS  (R_demo %.4f >= claim %g)\n", R_demo_wb, reliability))
  } else {
    cat(sprintf("  Verdict: FAIL  (R_demo %.4f < claim %g)\n", R_demo_wb, reliability))
  }
  cat("-----------------------------------------------------------------\n\n")
}

# Overall summary
overall_pass <- if (use_weibayes) (pass_binom || pass_wb) else pass_binom
cat("=================================================================\n")
cat(sprintf("  Overall Verdict: %s\n",
            if (overall_pass) "PASS" else "FAIL"))
if (use_weibayes && pass_binom != pass_wb) {
  cat("  Note: Binomial and Weibayes verdicts differ. The Weibayes result\n")
  cat("  is more powerful when beta is well-supported by prior data.\n")
  cat("  Document the basis for the assumed beta value.\n")
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# PNG output
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_rdt_verify.png"))

# --- Panel 1: Timeline ---
unit_ids <- if (!is.null(dat[[1]]) && length(unique(dat[[1]])) == n) {
  as.character(dat[[1]])
} else {
  paste0("U", seq_len(n))
}

df_time <- data.frame(
  unit   = factor(unit_ids, levels = rev(unit_ids)),
  t_eff  = t_eff,
  status = statuses,
  fail_at_horizon = is_failure_at_horizon
)

# Separate subsets for ggplot layers
df_surv <- df_time[!df_time$fail_at_horizon, ]
df_fail <- df_time[df_time$fail_at_horizon, ]

p1_title <- sprintf("Test Results Timeline  —  %s",
                    if (overall_pass) "PASS" else "FAIL")
p1_sub   <- sprintf("n = %d, k = %d failures at target life = %g", n, k, target_life)

p1 <- ggplot(df_time, aes(y = unit)) +
  geom_segment(aes(x = 0, xend = t_eff, yend = unit),
               color = CLR_SURV, linewidth = 0.6) +
  geom_vline(xintercept = target_life, linetype = "dashed",
             color = CLR_CLAIM, linewidth = 0.8) +
  annotate("text", x = target_life, y = n * 1.02,
           label = paste("target\n", target_life), hjust = 0.5, size = 2.5,
           color = CLR_CLAIM) +
  labs(title    = p1_title,
       subtitle = p1_sub,
       x        = "Effective test time",
       y        = NULL) +
  theme_jr +
  theme(axis.text.y = element_text(size = if (n <= 20) 7 else 5))

if (nrow(df_surv) > 0) {
  p1 <- p1 + geom_point(data = df_surv, aes(x = t_eff, y = unit),
                        shape = 3, size = 2, color = CLR_SURV)
}
if (nrow(df_fail) > 0) {
  p1 <- p1 + geom_point(data = df_fail, aes(x = t_eff, y = unit),
                        shape = 4, size = 3, color = CLR_FAIL2, stroke = 1.2)
}

# --- Panel 2: Demonstrated reliability bars ---
bar_labels <- "Claim"
bar_vals   <- reliability
bar_cols   <- CLR_CLAIM

bar_labels <- c(bar_labels, "Binomial\n(lower bound)")
bar_vals   <- c(bar_vals,   R_lower_binom)
bar_cols   <- c(bar_cols,   if (pass_binom) CLR_PASS else CLR_FAIL)

if (use_weibayes) {
  bar_labels <- c(bar_labels, "Weibayes\n(demonstrated)")
  bar_vals   <- c(bar_vals,   R_demo_wb)
  bar_cols   <- c(bar_cols,   if (pass_wb) CLR_PASS else CLR_FAIL)
}

df_bar <- data.frame(
  label = factor(bar_labels, levels = bar_labels),
  R     = bar_vals,
  col   = bar_cols
)

y_min <- min(0.5, min(bar_vals) - 0.05)
y_min <- max(0, y_min)

p2_title <- if (overall_pass) "Demonstrated Reliability — PASS" else "Demonstrated Reliability — FAIL"

p2 <- ggplot(df_bar, aes(x = label, y = R, fill = label)) +
  geom_col(width = 0.5, show.legend = FALSE) +
  geom_hline(yintercept = reliability, linetype = "dashed",
             color = CLR_CLAIM, linewidth = 0.8) +
  annotate("text", x = 0.55, y = reliability,
           label = paste("claim =", reliability),
           hjust = 0, vjust = -0.4, size = 3, color = CLR_CLAIM) +
  geom_text(aes(label = sprintf("%.4f", R)), vjust = -0.4, size = 3) +
  scale_fill_manual(values = setNames(bar_cols, bar_labels)) +
  coord_cartesian(ylim = c(y_min, 1.0)) +
  labs(title    = p2_title,
       subtitle = sprintf("Claim: R >= %g, C = %g", reliability, confidence),
       x        = NULL,
       y        = "Reliability") +
  theme_jr

# Save two-panel PNG
png(out_file, width = 2400, height = 1200, res = 200)
grid.newpage()
pushViewport(viewport(layout = grid.layout(1, 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
invisible(dev.off())

cat(sprintf("\u2728 Plot saved to: %s\n\n", out_file))

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
  report_path <- save_rdt_report(
    file_path, n, k, n_suspensions,
    reliability, confidence, target_life, accel_factor,
    use_weibayes, beta,
    F_upper_binom, R_lower_binom, pass_binom, margin_binom,
    T_star, T_threshold, eta_demo, R_demo_wb, pass_wb, margin_wb,
    overall_pass, out_file
  )
}

jr_log_output_hashes(c(out_file))
cat("\u2705 Done.\n")
