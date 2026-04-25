#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_extrapolate.R <model.csv> <target_time>
#
# model.csv     Model coefficient CSV produced by jrc_shelf_life_linear.
#               Contains intercept, slope, residual SE, and study metadata.
# target_time   The time point at which to project the value (numeric).
#               Must be in the same unit as the original stability study.
#
# Needs only base R — no external libraries required.
#
# Projects the mean value and its confidence interval to a target time point
# using the linear model fitted by jrc_shelf_life_linear. The confidence
# level is read from the model file (set when jrc_shelf_life_linear was run).
#
# Extrapolation warnings per ICH Q1E guidance:
#   ⚠️  Target time > 50% beyond last observation — confidence bounds are
#       wide; consider collecting additional data.
#   ❌  Target time > 100% beyond last observation — extrapolation is too
#       speculative to support a regulatory submission. Script exits with
#       code 1.
#
# Both thresholds are documented in the help file as design decisions.
#
# Author: Joep Rous
# Version: 1.2

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_extrapolate <model.csv> <target_time>\n\n")
  cat("  model.csv     Output of jrc_shelf_life_linear (*_model.csv)\n")
  cat("  target_time   Time point to project to (same unit as original study)\n\n")
  cat("Example: jrc_shelf_life_extrapolate 20260418_model.csv 36\n\n")
  quit(status = 0)
}

if (length(args) < 2) {
  stop("Not enough arguments. Usage: jrc_shelf_life_extrapolate <model.csv> <target_time>")
}

model_file  <- args[1]
target_time <- suppressWarnings(as.numeric(args[2]))

if (!file.exists(model_file)) {
  stop(paste("\u274c Model file not found:", model_file))
}
if (is.na(target_time) || target_time < 0) {
  stop(paste("\u274c 'target_time' must be a non-negative number. Got:", args[2]))
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

save_extrapolate_report <- function(model_file, source_f, run_ts,
                                     b0, b1, sigma, n, last_time,
                                     spec_limit, confidence, direction, transform,
                                     target_time, fit_val, ci_lo, ci_hi,
                                     ci_bound, spec_ok, extrap_frac) {
  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  f5 <- function(x) sprintf("%.5f", x)
  f4 <- function(x) sprintf("%.4f", x)
  f0 <- function(x) sprintf("%.0f%%", x * 100)

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-SHELF-EXT-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  ci_pct      <- sprintf("%.0f%%", confidence * 100)
  bound_label <- if (direction == "low") "Lower" else "Upper"
  v_color <- if (spec_ok) "#155724" else "#721c24"
  v_bg    <- if (spec_ok) "#d4edda"  else "#f8d7da"
  v_bdr   <- if (spec_ok) "#c3e6cb"  else "#f5c6cb"
  verdict_text <- if (spec_ok)
    paste0("PASS — Stability claim supported at t = ", target_time)
  else
    paste0("FAIL — CI bound has crossed spec limit at t = ", target_time)

  extrap_row <- if (extrap_frac > 0) {
    extrap_pct <- sprintf("%.0f%%", extrap_frac * 100)
    warn_note  <- if (extrap_frac > 0.5)
      paste0(" <strong>(⚠️ &gt;50% extrapolation — confidence bounds wide)</strong>")
    else ""
    paste0('<tr><td class="l">Extrapolation</td><td>', extrap_pct, ' beyond last observation', warn_note, '</td></tr>')
  } else {
    '<tr><td class="l">Extrapolation</td><td>Interpolation within observed range</td></tr>'
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
    "table.dt td.l{width:240px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    "table.dt td.r{text-align:right;font-family:monospace}",
    paste0(".verdict{margin-top:12px;padding:11px 16px;border-radius:4px;font-size:1.05em;font-weight:bold;text-align:center;background:", v_bg, ";color:", v_color, ";border:2px solid ", v_bdr, "}"),
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;text-align:center;margin-bottom:24px;color:#999;font-size:.9em;min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;font-size:.79em;color:#999;text-align:center}",
    "@media print{body{background:#fff;padding:0}.report{border:none;box-shadow:none;padding:16px;max-width:100%}.verdict{-webkit-print-color-adjust:exact;print-color-adjust:exact}}"
  ), collapse = "\n")

  out <- c(
    '<!DOCTYPE html><html lang="en"><head>',
    '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Shelf Life Extrapolation Report</title>',
    paste0('<style>', css, '</style></head><body><div class="report">'),

    '<div class="logo-wrap">[Insert company logo here]</div>',

    '<div class="rpt-hdr">',
    '<h1>Shelf Life Extrapolation Report</h1>',
    '<h2>ICH Q1E Linear Stability Model Projection</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_shelf_life_extrapolate v1.2 &mdash; JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Product / Study</td><td class="f">[describe the product and stability study]</td></tr>',
    '<tr><td class="l">Objective</td><td class="f">[state the objective, e.g.: project stability at target time point using fitted linear model from jrc_shelf_life_linear]</td></tr>',
    '<tr><td class="l">Standard</td><td>ICH Q1E — Evaluation for Stability Data</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">2. Model Source</div><table class="dt">',
    paste0('<tr><td class="l">Model file</td><td>', he(basename(model_file)), '</td></tr>'),
    paste0('<tr><td class="l">Source data</td><td>', he(source_f), '</td></tr>'),
    paste0('<tr><td class="l">Model fitted</td><td>', he(run_ts), '</td></tr>'),
    paste0('<tr><td class="l">Intercept</td><td class="r">', f5(b0), '</td></tr>'),
    paste0('<tr><td class="l">Slope</td><td class="r">', f5(b1), '</td></tr>'),
    paste0('<tr><td class="l">Residual SE</td><td class="r">', f5(sigma), '</td></tr>'),
    paste0('<tr><td class="l">n (observations)</td><td class="r">', he(as.integer(n)), '</td></tr>'),
    paste0('<tr><td class="l">Last observation</td><td class="r">', he(last_time), '</td></tr>'),
    paste0('<tr><td class="l">Spec limit</td><td class="r">', he(spec_limit),
           ' (', if (direction == "low") "lower bound" else "upper bound", ')</td></tr>'),
    paste0('<tr><td class="l">Confidence level</td><td class="r">', ci_pct, '</td></tr>'),
    paste0('<tr><td class="l">Transform</td><td>',
           if (transform == "log") "log (CI back-transformed via exp)" else "none", '</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">3. Projection Results</div><table class="dt">',
    paste0('<tr><td class="l">Target time</td><td class="r">', he(target_time), '</td></tr>'),
    extrap_row,
    paste0('<tr><td class="l">Fitted value</td><td class="r">', f5(fit_val), '</td></tr>'),
    paste0('<tr><td class="l">', ci_pct, ' CI</td><td class="r">[', f5(ci_lo), ',  ', f5(ci_hi), ']</td></tr>'),
    paste0('<tr><td class="l">', bound_label, ' ', ci_pct, ' CI bound</td><td class="r"><strong>', f5(ci_bound), '</strong></td></tr>'),
    paste0('<tr><td class="l">Spec limit</td><td class="r">', he(spec_limit), '</td></tr>'),
    '</table>',
    paste0('<div class="verdict">', he(verdict_text), '</div>'),
    '</div>',

    '<div class="section"><div class="sec-ttl">4. Approvals</div>',
    '<table class="appr"><thead><tr><th>Role</th><th>Name</th><th>Signature</th><th>Date</th></tr></thead><tbody>',
    '<tr><td>Prepared by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</tbody></table></div>',

    paste0('<div class="rpt-footer">Generated by JR Anchored &mdash; jrc_shelf_life_extrapolate v1.2 &mdash; ', he(dt_str), '</div>'),
    '</div></body></html>'
  )

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(datetime_pfx, "_extrapolate_dv_report.html"))
  writeLines(out, out_path)
  message(sprintf("\U0001f4c4 Report saved to: %s", out_path))

  jvs <- function(x) if (is.null(x) || is.na(x)) "null" else paste0('"', gsub('"', '\\"', as.character(x)), '"')
  jvn <- function(x, fmt = "%.6g") if (is.null(x) || is.na(x)) "null" else sprintf(fmt, as.numeric(x))
  jvb <- function(x) if (isTRUE(x)) "true" else "false"

  lsl_json <- if (direction == "low")  jvn(spec_limit) else "null"
  usl_json <- if (direction == "high") jvn(spec_limit) else "null"

  method_rows <- paste0(
    '{"k":"Method","v":"Linear stability projection (ICH Q1E)"},',
    '{"k":"Standard","v":"ICH Q1E - Evaluation for Stability Data"},',
    '{"k":"Transform","v":', jvs(if (transform == "log") "log (CI back-transformed via exp)" else "none"), '},',
    '{"k":"Confidence level","v":', jvs(ci_pct), '},',
    '{"k":"Direction","v":', jvs(if (direction == "low") "low (LSL)" else "high (USL)"), '},',
    '{"k":"Spec limit","v":', jvn(spec_limit), '}'
  )

  results_rows <- paste0(
    '{"k":"Model file","v":', jvs(basename(model_file)), '},',
    '{"k":"Source data","v":', jvs(source_f), '},',
    '{"k":"Model fitted","v":', jvs(run_ts), '},',
    '{"k":"n (observations)","v":', jvn(n, "%.0f"), '},',
    '{"k":"Last observation","v":', jvn(last_time), '},',
    '{"k":"Intercept","v":', jvn(b0, "%.5f"), '},',
    '{"k":"Slope","v":', jvn(b1, "%.5f"), '},',
    '{"k":"Residual SE","v":', jvn(sigma, "%.5f"), '},',
    '{"k":"Target time","v":', jvn(target_time), '},',
    '{"k":"Extrapolation fraction","v":', jvn(max(0, extrap_frac), "%.4f"), '},',
    '{"k":"Fitted value","v":', jvn(fit_val, "%.5f"), '},',
    '{"k":"CI lower","v":', jvn(ci_lo, "%.5f"), '},',
    '{"k":"CI upper","v":', jvn(ci_hi, "%.5f"), '},',
    '{"k":"', bound_label, ' CI bound","v":', jvn(ci_bound, "%.5f"), '}'
  )

  json_str <- paste0(
    '{"report_type":"dv",',
    '"script":"jrc_shelf_life_extrapolate",',
    '"version":"1.2",',
    '"report_id":', jvs(report_id), ',',
    '"generated":', jvs(dt_str), ',',
    '"verdict_pass":', jvb(spec_ok), ',',
    '"lsl":', lsl_json, ',"usl":', usl_json, ',',
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
# Parse model CSV
# ---------------------------------------------------------------------------

model_df <- tryCatch(
  read.csv(model_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read model file:", e$message))
)

if (!all(c("parameter", "value") %in% tolower(names(model_df)))) {
  stop("\u274c Model file must have columns 'parameter' and 'value'.")
}
names(model_df) <- tolower(names(model_df))

get_param <- function(name) {
  row <- model_df[model_df$parameter == name, "value"]
  if (length(row) == 0 || is.na(row[1]) || nchar(trimws(row[1])) == 0) {
    stop(paste("\u274c Required parameter missing from model file:", name))
  }
  row[1]
}

# Verify this is a jrc_shelf_life_linear model file
script_id <- get_param("script")
if (!grepl("jrc_shelf_life_linear", script_id)) {
  stop(paste("\u274c Model file does not appear to be from jrc_shelf_life_linear.",
             "Got script:", script_id))
}

b0         <- as.numeric(get_param("intercept"))
b1         <- as.numeric(get_param("slope"))
sigma      <- as.numeric(get_param("se_residual"))
n          <- as.numeric(get_param("n"))
t_bar      <- as.numeric(get_param("t_bar"))
Sxx        <- as.numeric(get_param("Sxx"))
last_time  <- as.numeric(get_param("last_time"))
spec_limit <- as.numeric(get_param("spec_limit"))
confidence <- as.numeric(get_param("confidence"))
direction  <- get_param("direction")
transform  <- tryCatch(get_param("transform"), error = function(e) "none")
if (!transform %in% c("none", "log")) transform <- "none"
source_f   <- get_param("source_file")
run_ts     <- get_param("run_timestamp")

for (nm in c("b0", "b1", "sigma", "n", "t_bar", "Sxx", "last_time",
             "spec_limit", "confidence")) {
  if (is.na(get(nm))) stop(paste("\u274c Non-numeric value for parameter:", nm))
}
if (!direction %in% c("low", "high")) {
  stop(paste("\u274c Unrecognised direction in model file:", direction))
}

df_res <- n - 2

# ---------------------------------------------------------------------------
# Extrapolation distance check
# ---------------------------------------------------------------------------

extrap_frac <- (target_time - last_time) / last_time

if (extrap_frac > 1.0) {
  cat("\u274c Extrapolation rejected.\n\n")
  cat(sprintf("  Target time (%g) is %.0f%% beyond the last observation (%g).\n",
              target_time, extrap_frac * 100, last_time))
  cat("  Extrapolation beyond 100% of the last observed time point is\n")
  cat("  too speculative to be scientifically defensible for a\n")
  cat("  regulatory submission. Conduct additional real-time or accelerated\n")
  cat("  ageing studies to support a longer shelf life claim.\n\n")
  quit(status = 1)
}

extrap_warning <- extrap_frac > 0.5

# ---------------------------------------------------------------------------
# Confidence interval calculation
# ---------------------------------------------------------------------------

t_crit   <- qt((1 + confidence) / 2, df = df_res)
fit_val  <- b0 + b1 * target_time
se_mean  <- sigma * sqrt(1 / n + (target_time - t_bar)^2 / Sxx)
margin   <- t_crit * se_mean

ci_lo    <- fit_val - margin
ci_hi    <- fit_val + margin

if (transform == "log") {
  fit_val <- exp(fit_val)
  ci_lo   <- exp(ci_lo)
  ci_hi   <- exp(ci_hi)
}

ci_bound <- if (direction == "low") ci_lo else ci_hi
spec_ok  <- if (direction == "low") ci_bound >= spec_limit else ci_bound <= spec_limit

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

ci_pct       <- sprintf("%.0f%%", confidence * 100)
bound_label  <- if (direction == "low") "Lower" else "Upper"

cat("\n")
cat("=================================================================\n")
cat("  Shelf Life Extrapolation\n")
cat(sprintf("  Model from: %s\n", basename(model_file)))
cat("=================================================================\n\n")

cat(sprintf("  Source study:     %s\n",   source_f))
cat(sprintf("  Model fitted:     %s\n",   run_ts))
cat(sprintf("  Intercept:        %.5f\n", b0))
cat(sprintf("  Slope:            %.5f\n", b1))
cat(sprintf("  Residual SE:      %.5f\n", sigma))
cat(sprintf("  n:                %d\n",   as.integer(n)))
cat(sprintf("  Last observation: %g\n",   last_time))
cat(sprintf("  Spec limit:       %g  (%s)\n", spec_limit,
            if (direction == "low") "lower bound" else "upper bound"))
cat(sprintf("  Transform:        %s\n\n",
            if (transform == "log") "log  (CI back-transformed via exp)" else "none"))

if (extrap_warning) {
  extrap_pct <- round(extrap_frac * 100)
  cat(sprintf("\u26a0\ufe0f  Target (%g) is %d%% beyond the last observation (%g).\n",
              target_time, extrap_pct, last_time))
  cat("   Confidence bounds are wide at this distance. Consider\n")
  cat("   additional real-time confirmation data before use in\n")
  cat("   a regulatory submission.\n\n")
}

cat("--- Projection --------------------------------------------------\n")
cat(sprintf("  Target time:      %g\n",     target_time))
cat(sprintf("  Fitted value:     %.5f\n",   fit_val))
cat(sprintf("  %s %s CI:   [%.5f,  %.5f]\n", ci_pct, "CI", ci_lo, ci_hi))
cat(sprintf("  %s %s CI bound: %.5f\n\n",   bound_label, ci_pct, ci_bound))

if (spec_ok) {
  cat(sprintf("  \u2705 %s %s CI bound (%.5f) is %s spec limit (%g).\n",
              bound_label, ci_pct, ci_bound,
              if (direction == "low") "above" else "below",
              spec_limit))
  cat("   The stability claim is supported at this time point.\n")
} else {
  cat(sprintf("  \u274c %s %s CI bound (%.5f) has crossed the spec limit (%g).\n",
              bound_label, ci_pct, ci_bound, spec_limit))
  cat("   The stability claim is NOT supported at this time point.\n")
}
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
  report_path <- save_extrapolate_report(
    model_file, source_f, run_ts,
    b0, b1, sigma, n, last_time,
    spec_limit, confidence, direction, transform,
    target_time, fit_val, ci_lo, ci_hi,
    ci_bound, spec_ok, extrap_frac
  )
}

cat("\u2705 Done.\n")
