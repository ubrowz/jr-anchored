#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_q10.R <q10> <accel_temp> <real_temp> <accel_time>
#
# q10          Q10 coefficient — factor by which reaction rate increases per 10°C
#              rise in temperature. ASTM F1980 default is 2.0. Typical range: 1.5-3.0.
# accel_temp   Accelerated storage temperature (degrees C).
# real_temp    Intended real-time storage temperature (degrees C).
# accel_time   Duration in accelerated conditions (any consistent unit: days, months).
#
# Needs only base R — no external libraries required.
#
# Computes the real-time equivalent of an accelerated ageing study per ASTM F1980.
#   AF = Q10 ^ ((T_accel - T_real) / 10)
#   real_time = accel_time x AF
#
# Also reports sensitivity to Q10 +/- 0.5 so the engineer can bracket uncertainty
# in the Q10 value.
#
# Reference:
#   ASTM F1980-21, Standard Guide for Accelerated Aging of Sterile Barrier Systems
#   for Medical Devices, ASTM International.
#
# Author: Joep Rous
# Version: 1.1

# ---------------------------------------------------------------------------
# Argument validation (before renv — argument errors surface immediately)
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_q10 <q10> <accel_temp> <real_temp> <accel_time>\n\n")
  cat("  q10          Q10 coefficient (ASTM F1980 default: 2.0; typical range 1.5-3.0)\n")
  cat("  accel_temp   Accelerated storage temperature (degrees C)\n")
  cat("  real_temp    Real-time storage temperature (degrees C)\n")
  cat("  accel_time   Duration of accelerated ageing (any consistent time unit)\n\n")
  cat("Example: jrc_shelf_life_q10 2.0 55 25 26\n\n")
  quit(status = 0)
}

if (length(args) < 4) {
  stop("Not enough arguments. Usage: jrc_shelf_life_q10 <q10> <accel_temp> <real_temp> <accel_time>")
}

q10        <- suppressWarnings(as.numeric(args[1]))
accel_temp <- suppressWarnings(as.numeric(args[2]))
real_temp  <- suppressWarnings(as.numeric(args[3]))
accel_time <- suppressWarnings(as.numeric(args[4]))

if (is.na(q10) || q10 <= 0) {
  stop(paste("\u274c 'q10' must be a positive number. Got:", args[1]))
}
if (is.na(accel_temp)) {
  stop(paste("\u274c 'accel_temp' must be a number. Got:", args[2]))
}
if (is.na(real_temp)) {
  stop(paste("\u274c 'real_temp' must be a number. Got:", args[3]))
}
if (is.na(accel_time) || accel_time <= 0) {
  stop(paste("\u274c 'accel_time' must be a positive number. Got:", args[4]))
}
if (accel_temp <= real_temp) {
  stop(sprintf(
    "\u274c Accelerated temperature (%g\u00b0C) must be higher than real-time temperature (%g\u00b0C).",
    accel_temp, real_temp
  ))
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
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

# ---------------------------------------------------------------------------
# Report function (requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

save_q10_report <- function(q10, accel_temp, real_temp, delta_t, accel_time,
                             af, real_time,
                             q10_lo, q10_hi, af_lo, af_hi, rt_lo, rt_hi) {
  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  f4 <- function(x) sprintf("%.4f", x)
  f2 <- function(x) sprintf("%.2f", x)

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-AA-Q10-", format(Sys.time(), "%Y%m%d-%H%M%S"))

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
    "table.dt td.l{width:240px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    "table.dt td.r{text-align:right;font-family:monospace}",
    ".result-box{margin-top:12px;padding:14px 18px;border-radius:4px;background:#e8f5e9;border:2px solid #a5d6a7;font-size:1.08em;font-weight:600;color:#1a5c2a}",
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;text-align:center;margin-bottom:24px;color:#999;font-size:.9em;min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;font-size:.79em;color:#999;text-align:center}",
    "@media print{body{background:#fff;padding:0}.report{border:none;box-shadow:none;padding:16px;max-width:100%}.result-box{-webkit-print-color-adjust:exact;print-color-adjust:exact}}"
  ), collapse = "\n")

  out <- c(
    '<!DOCTYPE html><html lang="en"><head>',
    '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Accelerated Ageing Report &mdash; Q10 Method</title>',
    paste0('<style>', css, '</style></head><body><div class="report">'),

    '<div class="logo-wrap">[Insert company logo here]</div>',

    '<div class="rpt-hdr">',
    '<h1>Accelerated Ageing Report</h1>',
    '<h2>Q10 Method &mdash; ASTM F1980</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_shelf_life_q10 v1.1 &mdash; JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Product / Study</td><td class="f">[describe the product and ageing study]</td></tr>',
    '<tr><td class="l">Objective</td><td class="f">[state the objective, e.g.: determine real-time shelf life equivalent of accelerated ageing study]</td></tr>',
    '<tr><td class="l">Standard</td><td>ASTM F1980-21, Standard Guide for Accelerated Aging of Sterile Barrier Systems for Medical Devices</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">2. Input Parameters</div><table class="dt">',
    paste0('<tr><td class="l">Q10 coefficient</td><td class="r">', f2(q10), '</td></tr>'),
    paste0('<tr><td class="l">Accelerated temperature</td><td class="r">', f2(accel_temp), ' &deg;C</td></tr>'),
    paste0('<tr><td class="l">Real-time temperature</td><td class="r">', f2(real_temp), ' &deg;C</td></tr>'),
    paste0('<tr><td class="l">Temperature difference (&Delta;T)</td><td class="r">', f2(delta_t), ' &deg;C</td></tr>'),
    paste0('<tr><td class="l">Accelerated ageing time</td><td class="r">', he(accel_time), '</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">3. Results</div><table class="dt">',
    paste0('<tr><td class="l">Acceleration factor (AF)</td><td class="r">', f4(af), '</td></tr>'),
    paste0('<tr><td class="l">Real-time equivalent</td><td class="r"><strong>', f4(real_time), '</strong> (same unit as accelerated ageing time)</td></tr>'),
    '</table>',
    paste0('<div class="result-box">AF = Q10<sup>&Delta;T/10</sup> = ', f2(q10), '<sup>', f2(delta_t), '/10</sup> = ', f4(af),
           ' &nbsp;&nbsp;&mdash;&nbsp;&nbsp; Real-time = accel&nbsp;&times;&nbsp;AF = ', f4(real_time), '</div>'),
    '</div>',

    '<div class="section"><div class="sec-ttl">4. Q10 Sensitivity (Q10 &plusmn; 0.5)</div>',
    '<table class="dt"><thead><tr><th>Q10</th><th style="text-align:right">AF</th><th style="text-align:right">Real-time equivalent</th><th>Note</th></tr></thead><tbody>',
    paste0('<tr><td class="r">', f2(q10_lo), '</td><td class="r">', f4(af_lo), '</td><td class="r">', f4(rt_lo), '</td><td></td></tr>'),
    paste0('<tr><td class="r"><strong>', f2(q10), '</strong></td><td class="r"><strong>', f4(af), '</strong></td><td class="r"><strong>', f4(real_time), '</strong></td><td><strong>Stated value</strong></td></tr>'),
    paste0('<tr><td class="r">', f2(q10_hi), '</td><td class="r">', f4(af_hi), '</td><td class="r">', f4(rt_hi), '</td><td></td></tr>'),
    '</tbody></table></div>',

    '<div class="section"><div class="sec-ttl">5. Notes and Limitations</div><table class="dt">',
    '<tr><td class="l">Real-time confirmation</td><td>ASTM F1980 requires parallel real-time ageing to confirm accelerated ageing claims before shelf life labelling.</td></tr>',
    '<tr><td class="l">Scope</td><td>This calculation covers sterile barrier / packaging integrity. Device functionality, biocompatibility, and material stability require separate assessment and may not follow Q10 kinetics.</td></tr>',
    '<tr><td class="l">Biologics / drug-device</td><td>For biologics and drug-device combinations, use Arrhenius kinetics with experimentally derived activation energy.</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">6. Approvals</div>',
    '<table class="appr"><thead><tr><th>Role</th><th>Name</th><th>Signature</th><th>Date</th></tr></thead><tbody>',
    '<tr><td>Prepared by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</tbody></table></div>',

    paste0('<div class="rpt-footer">Generated by JR Anchored &mdash; jrc_shelf_life_q10 v1.1 &mdash; ', he(dt_str), '</div>'),
    '</div></body></html>'
  )

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(datetime_pfx, "_q10_dv_report.html"))
  writeLines(out, out_path)
  message(sprintf("\U0001f4c4 Report saved to: %s", out_path))

  jvs <- function(x) if (is.null(x) || is.na(x)) "null" else paste0('"', gsub('"', '\\"', as.character(x)), '"')
  jvn <- function(x, fmt = "%.6g") if (is.null(x) || is.na(x)) "null" else sprintf(fmt, as.numeric(x))

  method_rows <- paste0(
    '{"k":"Method","v":"Q10 accelerated ageing"},',
    '{"k":"Standard","v":"ASTM F1980-21 - Accelerated Aging of Sterile Barrier Systems"},',
    '{"k":"Q10 coefficient","v":', jvn(q10, "%.2f"), '},',
    '{"k":"Temperature unit","v":"Celsius (degrees C)"}'
  )

  results_rows <- paste0(
    '{"k":"Accelerated temperature (C)","v":', jvn(accel_temp, "%.1f"), '},',
    '{"k":"Real-time temperature (C)","v":', jvn(real_temp, "%.1f"), '},',
    '{"k":"Temperature difference (delta T)","v":', jvn(delta_t, "%.1f"), '},',
    '{"k":"Accelerated ageing time","v":', jvn(accel_time), '},',
    '{"k":"Acceleration factor (AF)","v":', jvn(af, "%.4f"), '},',
    '{"k":"Real-time equivalent","v":', jvn(real_time, "%.4f"), '},',
    '{"k":"Sensitivity Q10-0.5 AF","v":', jvn(af_lo, "%.4f"), '},',
    '{"k":"Sensitivity Q10-0.5 real-time","v":', jvn(rt_lo, "%.4f"), '},',
    '{"k":"Sensitivity Q10+0.5 AF","v":', jvn(af_hi, "%.4f"), '},',
    '{"k":"Sensitivity Q10+0.5 real-time","v":', jvn(rt_hi, "%.4f"), '}'
  )

  json_str <- paste0(
    '{"report_type":"dv",',
    '"script":"jrc_shelf_life_q10",',
    '"version":"1.1",',
    '"report_id":', jvs(report_id), ',',
    '"generated":', jvs(dt_str), ',',
    '"verdict_pass":true,',
    '"lsl":null,"usl":null,',
    '"png_path":null,',
    '"method":[', method_rows, '],',
    '"results":[', results_rows, ']}'
  )

  json_path <- sub("\\.html$", "_data.json", out_path)
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
    }
  } else {
    message(sprintf("   Run: jr_pack deliverables dv-report --json %s", json_path))
  }

  c(html = out_path, json = json_path)
}

# ---------------------------------------------------------------------------
# Calculation
# ---------------------------------------------------------------------------

delta_t   <- accel_temp - real_temp
af        <- q10 ^ (delta_t / 10)
real_time <- accel_time * af

# Sensitivity bracket: Q10 +/- 0.5
q10_lo  <- max(q10 - 0.5, 0.01)
q10_hi  <- q10 + 0.5
af_lo   <- q10_lo ^ (delta_t / 10)
af_hi   <- q10_hi ^ (delta_t / 10)
rt_lo   <- accel_time * af_lo
rt_hi   <- accel_time * af_hi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Accelerated Ageing — Q10 Method  (ASTM F1980)\n")
cat("=================================================================\n\n")

cat(sprintf("  Q10 coefficient:          %.2f\n",     q10))
cat(sprintf("  Accelerated temperature:  %.1f \u00b0C\n",  accel_temp))
cat(sprintf("  Real-time temperature:    %.1f \u00b0C\n",  real_temp))
cat(sprintf("  Temperature difference:   %.1f \u00b0C\n",  delta_t))
cat(sprintf("  Accelerated ageing time:  %g\n",       accel_time))
cat("\n")
cat(sprintf("  Acceleration factor (AF): %.4f\n",     af))
cat(sprintf("  Real-time equivalent:     %.4f  (same unit as accel_time)\n\n", real_time))

if (q10 < 1.5 || q10 > 3.0) {
  cat(sprintf("\u26a0\ufe0f  Q10 = %.2f is outside the typical range (1.5-3.0) for medical device\n", q10))
  cat("   materials. ASTM F1980 recommends Q10 = 2.0 when experimental data\n")
  cat("   are not available. Justify this value in your ageing protocol.\n\n")
}

cat("--- Q10 Sensitivity (Q10 \u00b1 0.5) ----------------------------------\n")
cat(sprintf("  Q10 = %.1f  \u2192  AF = %6.3f  \u2192  real-time = %.4f\n", q10_lo, af_lo, rt_lo))
cat(sprintf("  Q10 = %.1f  \u2192  AF = %6.3f  \u2192  real-time = %.4f  (stated value)\n", q10, af, real_time))
cat(sprintf("  Q10 = %.1f  \u2192  AF = %6.3f  \u2192  real-time = %.4f\n", q10_hi, af_hi, rt_hi))
cat("\n")

cat("--- Notes -------------------------------------------------------\n")
cat("  \u2022 ASTM F1980 requires parallel real-time ageing to confirm\n")
cat("    accelerated ageing claims before shelf life labelling.\n")
cat("  \u2022 This calculation covers sterile barrier / packaging integrity.\n")
cat("    Device functionality, biocompatibility, and material stability\n")
cat("    require separate assessment and may not follow Q10 kinetics.\n")
cat("  \u2022 For biologics and drug-device combinations, use Arrhenius\n")
cat("    kinetics with experimentally derived activation energy.\n")
cat("=================================================================\n\n")

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
  report_path <- save_q10_report(
    q10, accel_temp, real_temp, delta_t, accel_time,
    af, real_time,
    q10_lo, q10_hi, af_lo, af_hi, rt_lo, rt_hi
  )
}

jr_log_output_hashes(if (!is.null(report_path)) report_path else character(0))
cat("\u2705 Done.\n")
