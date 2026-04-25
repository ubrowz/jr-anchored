#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_arrhenius.R <accel_temp> <real_temp>
#                                             <activation_energy> <accel_time>
#                                             [--unit C|K]
#
# accel_temp          Accelerated storage temperature.
# real_temp           Intended real-time storage temperature.
# activation_energy   Activation energy (Ea) in kcal/mol. Typical range: 10-25 kcal/mol.
#                     Use experimentally derived value where available; 12-15 kcal/mol
#                     is a common conservative default for polymeric device materials.
# accel_time          Duration in accelerated conditions (any consistent time unit).
# --unit C|K          Temperature unit: C = Celsius (default), K = Kelvin.
#
# Needs only base R — no external libraries required.
#
# Computes the real-time equivalent of an accelerated ageing study using
# Arrhenius kinetics:
#   AF = exp( Ea/R * (1/T_real - 1/T_accel) )
#   real_time = accel_time x AF
# where temperatures are in Kelvin and R = 1.987 cal/(mol*K).
#
# Also reports sensitivity to activation energy +/- 2 kcal/mol.
#
# References:
#   ISO 11607-1:2019, Packaging for terminally sterilized medical devices.
#   ICH Q1E, Evaluation for Stability Data, 2003.
#
# Author: Joep Rous
# Version: 1.1

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_arrhenius <accel_temp> <real_temp> <activation_energy> <accel_time> [--unit C|K]\n\n")
  cat("  accel_temp         Accelerated temperature\n")
  cat("  real_temp          Real-time temperature\n")
  cat("  activation_energy  Ea in kcal/mol (typical 10-25; default assumption 12-15)\n")
  cat("  accel_time         Duration of accelerated ageing (any consistent time unit)\n")
  cat("  --unit C|K         Temperature unit (default: C)\n\n")
  cat("Example: jrc_shelf_life_arrhenius 55 25 17.0 26\n\n")
  quit(status = 0)
}

# Parse --unit flag
temp_unit <- "C"
clean_args <- c()
i <- 1
while (i <= length(args)) {
  if (args[i] == "--unit" && i < length(args)) {
    temp_unit <- toupper(args[i + 1])
    if (!temp_unit %in% c("C", "K")) {
      stop(paste("\u274c --unit must be 'C' or 'K'. Got:", args[i + 1]))
    }
    i <- i + 2
  } else {
    clean_args <- c(clean_args, args[i])
    i <- i + 1
  }
}

if (length(clean_args) < 4) {
  stop("Not enough arguments. Usage: jrc_shelf_life_arrhenius <accel_temp> <real_temp> <activation_energy> <accel_time> [--unit C|K]")
}

accel_temp_raw <- suppressWarnings(as.numeric(clean_args[1]))
real_temp_raw  <- suppressWarnings(as.numeric(clean_args[2]))
ea             <- suppressWarnings(as.numeric(clean_args[3]))
accel_time     <- suppressWarnings(as.numeric(clean_args[4]))

if (is.na(accel_temp_raw)) stop(paste("\u274c 'accel_temp' must be a number. Got:", clean_args[1]))
if (is.na(real_temp_raw))  stop(paste("\u274c 'real_temp' must be a number. Got:",  clean_args[2]))
if (is.na(ea) || ea <= 0)  stop(paste("\u274c 'activation_energy' must be a positive number. Got:", clean_args[3]))
if (is.na(accel_time) || accel_time <= 0) stop(paste("\u274c 'accel_time' must be a positive number. Got:", clean_args[4]))

# Convert to Kelvin
K_OFFSET <- 273.15
if (temp_unit == "C") {
  T_accel <- accel_temp_raw + K_OFFSET
  T_real  <- real_temp_raw  + K_OFFSET
} else {
  T_accel <- accel_temp_raw
  T_real  <- real_temp_raw
  if (T_accel < 200 || T_real < 200) {
    stop("\u274c Temperatures in Kelvin must be > 200 K. Check --unit flag.")
  }
}

if (T_accel <= T_real) {
  stop(sprintf(
    "\u274c Accelerated temperature must be higher than real-time temperature.\n   Got: accel=%g, real=%g (%s)",
    accel_temp_raw, real_temp_raw, temp_unit
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

save_arrhenius_report <- function(accel_temp_raw, real_temp_raw, ea, accel_time,
                                   temp_unit, T_accel, T_real,
                                   af, real_time,
                                   ea_lo, ea_hi, af_lo, af_hi, rt_lo, rt_hi) {
  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  f4 <- function(x) sprintf("%.4f", x)
  f2 <- function(x) sprintf("%.2f", x)

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-AA-ARR-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  t_accel_disp <- if (temp_unit == "C")
    sprintf("%.1f &deg;C (%.2f K)", accel_temp_raw, T_accel)
  else
    sprintf("%.2f K", T_accel)
  t_real_disp <- if (temp_unit == "C")
    sprintf("%.1f &deg;C (%.2f K)", real_temp_raw, T_real)
  else
    sprintf("%.2f K", T_real)

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
    '<title>Accelerated Ageing Report &mdash; Arrhenius Method</title>',
    paste0('<style>', css, '</style></head><body><div class="report">'),

    '<div class="logo-wrap">[Insert company logo here]</div>',

    '<div class="rpt-hdr">',
    '<h1>Accelerated Ageing Report</h1>',
    '<h2>Arrhenius Method &mdash; ISO 11607 / ICH Q1E</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_shelf_life_arrhenius v1.1 &mdash; JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Product / Study</td><td class="f">[describe the product and ageing study]</td></tr>',
    '<tr><td class="l">Objective</td><td class="f">[state the objective, e.g.: determine real-time shelf life equivalent of accelerated ageing study using Arrhenius kinetics]</td></tr>',
    '<tr><td class="l">Standards</td><td>ISO 11607-1:2019 — Packaging for terminally sterilized medical devices; ICH Q1E — Evaluation for Stability Data</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">2. Input Parameters</div><table class="dt">',
    paste0('<tr><td class="l">Accelerated temperature</td><td class="r">', t_accel_disp, '</td></tr>'),
    paste0('<tr><td class="l">Real-time temperature</td><td class="r">', t_real_disp, '</td></tr>'),
    paste0('<tr><td class="l">Activation energy (Ea)</td><td class="r">', f2(ea), ' kcal/mol</td></tr>'),
    paste0('<tr><td class="l">Gas constant (R)</td><td class="r">1.987 &times; 10<sup>&minus;3</sup> kcal/(mol&middot;K)</td></tr>'),
    paste0('<tr><td class="l">Accelerated ageing time</td><td class="r">', he(accel_time), '</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">3. Results</div><table class="dt">',
    paste0('<tr><td class="l">Acceleration factor (AF)</td><td class="r">', f4(af), '</td></tr>'),
    paste0('<tr><td class="l">Real-time equivalent</td><td class="r"><strong>', f4(real_time), '</strong> (same unit as accelerated ageing time)</td></tr>'),
    '</table>',
    paste0('<div class="result-box">AF = exp(Ea/R &times; (1/T<sub>real</sub> &minus; 1/T<sub>accel</sub>)) = ', f4(af),
           ' &nbsp;&nbsp;&mdash;&nbsp;&nbsp; Real-time = accel &times; AF = ', f4(real_time), '</div>'),
    '</div>',

    '<div class="section"><div class="sec-ttl">4. Ea Sensitivity (Ea &plusmn; 2 kcal/mol)</div>',
    '<table class="dt"><thead><tr><th>Ea (kcal/mol)</th><th style="text-align:right">AF</th><th style="text-align:right">Real-time equivalent</th><th>Note</th></tr></thead><tbody>',
    paste0('<tr><td class="r">', f2(ea_lo), '</td><td class="r">', f4(af_lo), '</td><td class="r">', f4(rt_lo), '</td><td></td></tr>'),
    paste0('<tr><td class="r"><strong>', f2(ea), '</strong></td><td class="r"><strong>', f4(af), '</strong></td><td class="r"><strong>', f4(real_time), '</strong></td><td><strong>Stated value</strong></td></tr>'),
    paste0('<tr><td class="r">', f2(ea_hi), '</td><td class="r">', f4(af_hi), '</td><td class="r">', f4(rt_hi), '</td><td></td></tr>'),
    '</tbody></table></div>',

    '<div class="section"><div class="sec-ttl">5. Notes and Limitations</div><table class="dt">',
    '<tr><td class="l">Single mechanism</td><td>Arrhenius kinetics assume a single dominant degradation mechanism. Multi-mechanism degradation (e.g. hydrolysis + oxidation) may require separate treatment.</td></tr>',
    '<tr><td class="l">Real-time confirmation</td><td>ISO 11607 and ICH Q1E both require real-time confirmation studies.</td></tr>',
    '<tr><td class="l">Alternative</td><td>For sterile barrier / packaging integrity, the Q10 method (ASTM F1980) is also acceptable and may be simpler to justify.</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">6. Approvals</div>',
    '<table class="appr"><thead><tr><th>Role</th><th>Name</th><th>Signature</th><th>Date</th></tr></thead><tbody>',
    '<tr><td>Prepared by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</tbody></table></div>',

    paste0('<div class="rpt-footer">Generated by JR Anchored &mdash; jrc_shelf_life_arrhenius v1.1 &mdash; ', he(dt_str), '</div>'),
    '</div></body></html>'
  )

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(datetime_pfx, "_arrhenius_dv_report.html"))
  writeLines(out, out_path)
  message(sprintf("\U0001f4c4 Report saved to: %s", out_path))

  jvs <- function(x) if (is.null(x) || is.na(x)) "null" else paste0('"', gsub('"', '\\"', as.character(x)), '"')
  jvn <- function(x, fmt = "%.6g") if (is.null(x) || is.na(x)) "null" else sprintf(fmt, as.numeric(x))

  method_rows <- paste0(
    '{"k":"Method","v":"Arrhenius kinetics"},',
    '{"k":"Standard","v":"ISO 11607-1:2019 / ICH Q1E"},',
    '{"k":"Temperature unit","v":', jvs(temp_unit), '},',
    '{"k":"Activation energy (Ea)","v":', jvs(sprintf("%.2f kcal/mol", ea)), '},',
    '{"k":"Gas constant (R)","v":"1.987e-3 kcal/(mol K)"}'
  )

  results_rows <- paste0(
    '{"k":"Accelerated temperature (K)","v":', jvn(T_accel, "%.4f"), '},',
    '{"k":"Real-time temperature (K)","v":', jvn(T_real, "%.4f"), '},',
    '{"k":"Accelerated ageing time","v":', jvn(accel_time), '},',
    '{"k":"Acceleration factor (AF)","v":', jvn(af, "%.4f"), '},',
    '{"k":"Real-time equivalent","v":', jvn(real_time, "%.4f"), '},',
    '{"k":"Sensitivity Ea-2 kcal/mol AF","v":', jvn(af_lo, "%.4f"), '},',
    '{"k":"Sensitivity Ea-2 kcal/mol real-time","v":', jvn(rt_lo, "%.4f"), '},',
    '{"k":"Sensitivity Ea+2 kcal/mol AF","v":', jvn(af_hi, "%.4f"), '},',
    '{"k":"Sensitivity Ea+2 kcal/mol real-time","v":', jvn(rt_hi, "%.4f"), '}'
  )

  json_str <- paste0(
    '{"report_type":"dv",',
    '"script":"jrc_shelf_life_arrhenius",',
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
    } else {
      docx_line <- grep("saved to:", ret, value = TRUE)
      if (length(docx_line) > 0L)
        jr_log_report(trimws(sub(".*saved to:\\s*", "", docx_line[1L])))
      if (file.exists(out_path))  file.remove(out_path)
      if (file.exists(json_path)) file.remove(json_path)
    }
  } else {
    message(sprintf("   Run: jr_pack deliverables dv-report --json %s", json_path))
  }

  invisible(c(html = out_path, json = json_path))
}

# ---------------------------------------------------------------------------
# Calculation
# ---------------------------------------------------------------------------

R_GAS <- 1.987e-3  # kcal / (mol * K)

arrhenius_af <- function(ea_val, T_a, T_r) {
  exp(ea_val / R_GAS * (1 / T_r - 1 / T_a))
}

af        <- arrhenius_af(ea, T_accel, T_real)
real_time <- accel_time * af

# Sensitivity: Ea +/- 2 kcal/mol
ea_lo <- max(ea - 2, 0.01)
ea_hi <- ea + 2
af_lo <- arrhenius_af(ea_lo, T_accel, T_real)
af_hi <- arrhenius_af(ea_hi, T_accel, T_real)
rt_lo <- accel_time * af_lo
rt_hi <- accel_time * af_hi

# Display temperatures
if (temp_unit == "C") {
  t_accel_disp <- sprintf("%.1f \u00b0C  (%.2f K)", accel_temp_raw, T_accel)
  t_real_disp  <- sprintf("%.1f \u00b0C  (%.2f K)", real_temp_raw,  T_real)
} else {
  t_accel_disp <- sprintf("%.2f K", T_accel)
  t_real_disp  <- sprintf("%.2f K", T_real)
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Accelerated Ageing — Arrhenius Method  (ISO 11607 / ICH Q1E)\n")
cat("=================================================================\n\n")

cat(sprintf("  Accelerated temperature:  %s\n",   t_accel_disp))
cat(sprintf("  Real-time temperature:    %s\n",   t_real_disp))
cat(sprintf("  Activation energy (Ea):   %.2f kcal/mol\n", ea))
cat(sprintf("  Accelerated ageing time:  %g\n",   accel_time))
cat("\n")
cat(sprintf("  Acceleration factor (AF): %.4f\n",  af))
cat(sprintf("  Real-time equivalent:     %.4f  (same unit as accel_time)\n\n", real_time))

if (ea < 10 || ea > 25) {
  cat(sprintf("\u26a0\ufe0f  Ea = %.1f kcal/mol is outside the typical range (10-25 kcal/mol)\n", ea))
  cat("   for polymeric medical device materials. Verify with experimental\n")
  cat("   degradation data and document justification.\n\n")
}

cat("--- Ea Sensitivity (Ea \u00b1 2 kcal/mol) ----------------------------\n")
cat(sprintf("  Ea = %5.1f  \u2192  AF = %7.3f  \u2192  real-time = %.4f\n", ea_lo, af_lo, rt_lo))
cat(sprintf("  Ea = %5.1f  \u2192  AF = %7.3f  \u2192  real-time = %.4f  (stated value)\n", ea, af, real_time))
cat(sprintf("  Ea = %5.1f  \u2192  AF = %7.3f  \u2192  real-time = %.4f\n", ea_hi, af_hi, rt_hi))
cat("\n")

cat("--- Notes -------------------------------------------------------\n")
cat("  \u2022 Arrhenius kinetics assume a single dominant degradation mechanism.\n")
cat("    Multi-mechanism degradation (e.g. hydrolysis + oxidation) may\n")
cat("    require separate treatment.\n")
cat("  \u2022 ISO 11607 and ICH Q1E both require real-time confirmation studies.\n")
cat("  \u2022 For sterile barrier / packaging integrity, Q10 method (ASTM F1980)\n")
cat("    is also acceptable and may be simpler to justify.\n")
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
  report_path <- save_arrhenius_report(
    accel_temp_raw, real_temp_raw, ea, accel_time,
    temp_unit, T_accel, T_real,
    af, real_time,
    ea_lo, ea_hi, af_lo, af_hi, rt_lo, rt_hi
  )
}

cat("\u2705 Done.\n")
