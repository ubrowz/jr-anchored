#!/usr/bin/env Rscript
#
# jrc_verify_discrete.R
#
# Discrete (pass/fail) verification assessment using the exact Clopper-Pearson
# one-sided binomial confidence interval.
#
# Given N units tested, f failures observed, and a pre-specified requirement
# (proportion P at confidence C), computes the upper one-sided CI bound on
# the true failure rate and reports PASS/FAIL with margin.
#
# Author: Joep Rous
# Version: 1.1

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("❌ RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"),
                      r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("❌ renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

# ---------------------------------------------------------------------------
# Report generator
# ---------------------------------------------------------------------------

save_discrete_report <- function(N_val, f_val, proportion, confidence,
                                 upper_bound, allowable_failure_rate,
                                 observed_failure_rate, margin, passed) {

  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  pct <- function(x) sprintf("%.2f%%", x * 100)

  v_text  <- if (passed) "PASS" else "FAIL"
  v_icon  <- if (passed) "✅" else "❌"
  v_color <- if (passed) "#155724" else "#721c24"
  v_bg    <- if (passed) "#d4edda"  else "#f8d7da"
  v_bdr   <- if (passed) "#c3e6cb"  else "#f5c6cb"

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-DISC-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  css <- paste(c(
    "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}",
    "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1a1a1a;",
    "     background:#fff;padding:24px}",
    ".report{background:#fff;max-width:820px;margin:0 auto;padding:40px 48px;",
    "        border:1px solid #ccc;box-shadow:0 2px 10px rgba(0,0,0,.10)}",
    ".rpt-hdr{border-bottom:3px solid #1a3a6b;padding-bottom:14px;margin-bottom:24px}",
    ".rpt-hdr h1{font-size:1.45em;color:#1a3a6b;margin-bottom:2px}",
    ".rpt-hdr h2{font-size:1em;font-weight:normal;color:#555;margin-bottom:14px}",
    "table.meta{border-collapse:collapse}",
    "table.meta td{padding:3px 14px 3px 0;vertical-align:top;font-size:.91em}",
    "table.meta td.k{font-weight:600;color:#333;min-width:160px}",
    ".draft{color:#a00;font-weight:bold}",
    ".section{margin-top:26px}",
    ".sec-ttl{font-weight:700;color:#1a3a6b;border-bottom:1.5px solid #1a3a6b;",
    "         padding-bottom:4px;margin-bottom:10px;font-size:.95em;",
    "         text-transform:uppercase;letter-spacing:.04em}",
    "table.dt{width:100%;border-collapse:collapse;font-size:.93em}",
    "table.dt td{padding:5px 10px;border:1px solid #ddd;vertical-align:top}",
    "table.dt td.l{width:240px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    paste0(".verdict{margin-top:12px;padding:11px 16px;border-radius:4px;",
           "font-size:1.05em;font-weight:bold;text-align:center;",
           "background:", v_bg, ";color:", v_color, ";border:2px solid ", v_bdr, "}"),
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;",
    "           text-align:center;margin-bottom:24px;color:#999;font-size:.9em;",
    "           min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;",
    "              text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;",
    "            font-size:.79em;color:#999;text-align:center}",
    "@media print{",
    "  body{background:#fff;padding:0}",
    "  .report{border:none;box-shadow:none;padding:16px;max-width:100%}",
    "  .verdict,table.dt td.f{-webkit-print-color-adjust:exact;print-color-adjust:exact}",
    "}"
  ), collapse = "\n")

  out <- c(
    '<!DOCTYPE html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="UTF-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Design Verification Report — Discrete Pass/Fail</title>',
    '<style>', css, '</style>',
    '</head>',
    '<body>',
    '<div class="report">',

    '<div class="logo-wrap">[Insert company logo here — replace this box with your logo in Word]</div>',

    '<div class="rpt-hdr">',
    '<h1>Design Verification Report</h1>',
    '<h2>Discrete Pass/Fail Assessment — Clopper-Pearson Exact Binomial CI</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_verify_discrete v1.1 — JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT — complete all highlighted fields before use</td></tr>',
    '</table>',
    '</div>',

    # 1. Purpose and Scope
    '<div class="section">',
    '<div class="sec-ttl">1. Purpose and Scope</div>',
    '<table class="dt">',
    '<tr><td class="l">Requirement Reference</td>',
    '<td class="f">[enter design input or design output requirement ID and description]</td></tr>',
    '<tr><td class="l">Design Input / Output</td>',
    '<td class="f">[state whether this verifies a Design Input (DI) or Design Output (DO)]</td></tr>',
    '<tr><td class="l">Purpose of Verification</td>',
    '<td class="f">[describe what is being verified and why the pass/fail binomial method was selected]</td></tr>',
    paste0('<tr><td class="l">Acceptance Criterion</td>',
           '<td class="f">At least ', pct(proportion), ' of units conform to requirements, demonstrated ',
           'with ', pct(confidence), ' confidence (Clopper-Pearson exact one-sided CI).</td></tr>'),
    '</table>',
    '</div>',

    # 2. Test Setup
    '<div class="section">',
    '<div class="sec-ttl">2. Test Setup</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">Units Tested (N)</td><td>', he(N_val), '</td></tr>'),
    paste0('<tr><td class="l">Failures Observed (f)</td><td>', he(f_val), '</td></tr>'),
    paste0('<tr><td class="l">Required Proportion (P)</td><td>', he(proportion),
           ' (i.e. at most ', pct(allowable_failure_rate), ' failure rate allowed)</td></tr>'),
    paste0('<tr><td class="l">Confidence Level (C)</td><td>', he(confidence), '</td></tr>'),
    '<tr><td class="l">Test Conditions</td>',
    '<td class="f">[describe test conditions, equipment used, operator, and date of measurements]</td></tr>',
    '</table>',
    '</div>',

    # 3. Statistical Method
    '<div class="section">',
    '<div class="sec-ttl">3. Statistical Method</div>',
    '<table class="dt">',
    '<tr><td class="l">Method</td>',
    '<td>Clopper-Pearson exact one-sided binomial confidence interval on the failure rate.</td></tr>',
    '<tr><td class="l">Upper CI Bound Formula</td>',
    '<td>Beta(C; f+1, N−f) — computed via <code>qbeta(C, f+1, N-f)</code> in R.</td></tr>',
    '<tr><td class="l">Pass Criterion</td>',
    '<td>Upper CI bound &lt; allowable failure rate (= 1 − P).</td></tr>',
    '<tr><td class="l">Reference</td>',
    '<td>Clopper, C.J. &amp; Pearson, E.S. (1934). The use of confidence or fiducial limits illustrated in the case of the binomial. <em>Biometrika</em>, 26(4), 404–413.</td></tr>',
    '</table>',
    '</div>',

    # 4. Results
    '<div class="section">',
    '<div class="sec-ttl">4. Results</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">Units Tested (N)</td><td>', he(N_val), '</td></tr>'),
    paste0('<tr><td class="l">Failures Observed (f)</td><td>', he(f_val), '</td></tr>'),
    paste0('<tr><td class="l">Observed Failure Rate</td><td>', pct(observed_failure_rate),
           ' (', he(f_val), '/', he(N_val), ')</td></tr>'),
    paste0('<tr><td class="l">Upper ', pct(confidence), ' CI Bound</td><td>',
           pct(upper_bound), '</td></tr>'),
    paste0('<tr><td class="l">Allowable Failure Rate (1−P)</td><td>',
           pct(allowable_failure_rate), '</td></tr>'),
    paste0('<tr><td class="l">Margin</td><td>',
           sprintf("%.4g", margin * 100), ' percentage points</td></tr>'),
    '</table>',
    paste0('<div class="verdict">', v_icon, ' Verification outcome: ', v_text, '</div>'),
    '</div>',

    # 5. Conclusion
    '<div class="section">',
    '<div class="sec-ttl">5. Conclusion</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">Outcome</td>',
           '<td style="font-weight:bold;color:', v_color, '">', v_icon, ' ', v_text, '</td></tr>'),
    '<tr><td class="l">Conclusion</td>',
    '<td class="f">[state whether the design requirement is verified; summarise the statistical evidence]</td></tr>',
    '<tr><td class="l">Deviations / Observations</td>',
    '<td class="f">[NONE — or describe any deviations from the planned test method]</td></tr>',
    '</table>',
    '</div>',

    # 6. Approvals
    '<div class="section">',
    '<div class="sec-ttl">6. Approvals</div>',
    '<table class="appr">',
    '<tr><th style="width:22%">Role</th><th style="width:28%">Name</th>',
    '<th style="width:28%">Signature</th><th style="width:22%">Date</th></tr>',
    '<tr><td>Performed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</table>',
    '</div>',

    paste0('<div class="rpt-footer">Generated by jrc_verify_discrete v1.1 — JR Anchored — ',
           he(dt_str), '</div>'),
    '</div>',
    '</body>',
    '</html>'
  )

  out_file <- file.path(path.expand("~/Downloads"),
                        paste0(format(Sys.time(), "%Y%m%d_%H%M%S"),
                               "_discrete_verification_report.html"))
  writeLines(out, out_file, useBytes = TRUE)
  message(paste("✅ Verification report saved to:", out_file))

  # ── JSON sidecar ─────────────────────────────────────────────────────────
  jvs <- function(x) if (is.null(x) || (length(x) == 1 && is.na(x))) "null" else paste0('"', gsub('"', '\\\\"', as.character(x)), '"')
  jvn <- function(x, fmt = "%.6g") if (is.null(x) || (length(x) == 1 && is.na(x))) "null" else sprintf(fmt, as.numeric(x))
  jvb <- function(x) if (isTRUE(x)) "true" else "false"

  method_rows <- paste0(
    '{"k":"Method","v":"Clopper-Pearson exact one-sided CI on failure rate"},',
    '{"k":"Reference","v":"Clopper & Pearson (1934). Biometrika 26(4):404-413"},',
    '{"k":"N (units tested)","v":', jvn(N_val, "%.0f"), '},',
    '{"k":"f (failures observed)","v":', jvn(f_val, "%.0f"), '},',
    '{"k":"Required proportion (P)","v":', jvn(proportion, "%.4g"), '},',
    '{"k":"Confidence level (C)","v":', jvn(confidence, "%.4g"), '}'
  )

  results_rows <- paste0(
    '{"k":"Observed failure rate","v":', jvs(pct(observed_failure_rate)), '},',
    '{"k":"Upper confidence bound","v":', jvs(pct(upper_bound)), '},',
    '{"k":"Allowable failure rate (1\u2212P)","v":', jvs(pct(allowable_failure_rate)), '},',
    '{"k":"Margin","v":', jvs(sprintf("%.4g pp", margin * 100)), '},',
    '{"k":"Verdict","v":', jvs(v_text), '}'
  )

  json_str <- paste0(
    '{"report_type":"dv",',
    '"script":"jrc_verify_discrete",',
    '"version":"1.0",',
    '"report_id":', jvs(report_id), ',',
    '"generated":', jvs(dt_str), ',',
    '"verdict_pass":', jvb(passed), ',',
    '"png_path":null,',
    '"method":[', method_rows, '],',
    '"results":[', results_rows, ']}' 
  )

  json_path <- sub("\\.html$", "_data.json", out_file)
  writeLines(json_str, json_path)
  message(sprintf("  JSON sidecar: %s", json_path))

  pack_py <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "pack", "jr_pack.py")
  if (file.exists(pack_py)) {
    ret       <- system2("python3",
                         args   = c(shQuote(pack_py), "deliverables", "dv-report",
                                    "--json", shQuote(json_path)),
                         stdout = TRUE, stderr = TRUE)
    exit_code <- attr(ret, "status")
    if (is.null(exit_code)) exit_code <- 0L
    message(paste(ret, collapse = "\n"))
    if (exit_code != 0L) {
      message(sprintf("   Retry manually: jr_pack deliverables dv-report --json %s", json_path))
    } else {
      if (file.exists(out_file))  file.remove(out_file)
      if (file.exists(json_path)) file.remove(json_path)
    }
  } else {
    message(sprintf("   Run: jr_pack deliverables dv-report --json %s", json_path))
  }

  invisible(out_file)
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_verify_discrete.R <N> <f> <proportion> <confidence> [--report]",
    "Example:",
    "  Rscript jrc_verify_discrete.R 125 2 0.95 0.95",
    sep = "\n"
  ))
}

N_val      <- suppressWarnings(as.integer(args[1]))
f_val      <- suppressWarnings(as.integer(args[2]))
proportion <- suppressWarnings(as.double(args[3]))
confidence <- suppressWarnings(as.double(args[4]))

if (is.na(N_val) || N_val <= 0) {
  stop(paste("'N' must be a positive integer. Got:", args[1]))
}
if (is.na(f_val) || f_val < 0) {
  stop(paste("'f' must be a non-negative integer. Got:", args[2]))
}
if (f_val > N_val) {
  stop(paste0("'f' (failures) cannot exceed 'N' (units tested). Got f = ",
              f_val, ", N = ", N_val))
}
if (f_val == N_val) {
  stop(paste0("All ", N_val, " units failed. Cannot compute a meaningful confidence ",
              "bound — review your test data."))
}
if (is.na(proportion) || proportion <= 0 || proportion >= 1) {
  stop(paste("'proportion' must be strictly between 0 and 1. Got:", args[3]))
}
if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be strictly between 0 and 1. Got:", args[4]))
}

# ---------------------------------------------------------------------------
# Clopper-Pearson upper one-sided CI on the failure rate
# Upper bound: qbeta(C, f+1, N-f)
# ---------------------------------------------------------------------------

allowable_failure_rate <- 1 - proportion
upper_bound            <- qbeta(confidence, f_val + 1, N_val - f_val)
observed_failure_rate  <- f_val / N_val
margin                 <- allowable_failure_rate - upper_bound
passed                 <- upper_bound < allowable_failure_rate

pct <- function(x) sprintf("%.2f%%", x * 100)

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

message(" ")
message("=================================================================")
message("  Discrete Verification — Pass/Fail Assessment")
message("=================================================================")
message(" ")
message(sprintf("  units tested (N):              %d", N_val))
message(sprintf("  failures observed (f):         %d", f_val))
message(sprintf("  required proportion (P):       %.4g", proportion))
message(sprintf("  confidence level (C):          %.4g", confidence))
message(" ")
message(sprintf("  Observed failure rate:         %s  (%d/%d)",
                pct(observed_failure_rate), f_val, N_val))
message(sprintf("  Upper %s CI bound:         %s",
                pct(confidence), pct(upper_bound)))
message(sprintf("  Allowable failure rate:        %s  (= 1 − P)",
                pct(allowable_failure_rate)))
message(sprintf("  Margin:                        %.4g percentage points",
                margin * 100))
message(" ")

if (passed) {
  message("✅ VERIFICATION PASSED")
  message(sprintf("   Upper confidence bound (%s) is within the", pct(upper_bound)))
  message(sprintf("   allowable failure rate (%s).", pct(allowable_failure_rate)))
} else {
  message("❌ VERIFICATION FAILED")
  message(sprintf("   Upper confidence bound (%s) exceeds the", pct(upper_bound)))
  message(sprintf("   allowable failure rate (%s).", pct(allowable_failure_rate)))
  message("   Consider increasing sample size or investigating")
  message("   the root cause of failures.")
}

if (f_val == 0) {
  message(" ")
  message("   ℹ️  Note: f = 0 (zero failures observed).")
  message("   For zero-failure studies, jrc_ss_discrete_ci is the canonical tool.")
  message("   It reports the proportion achieved given N and f = 0.")
}

message(" ")

# ---------------------------------------------------------------------------
# HTML report (--report flag, requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

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
  save_discrete_report(
    N_val, f_val, proportion, confidence,
    upper_bound, allowable_failure_rate, observed_failure_rate, margin, passed
  )
}

jr_log_output_hashes(character(0))
