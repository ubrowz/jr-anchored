#!/usr/bin/env Rscript
#
# use as: Rscript jrc_msa_grr_design.R <grr> <type> <sigma_or_tolerance>
#
# "grr"               target %GRR as a percentage (e.g. 10 for 10%, 30 for 30%)
# "type"              how %GRR is expressed:
#                       "process"   — %GRR as % of process variation (6*sigma)
#                       "tolerance" — %GRR as % of tolerance (USL - LSL)
# "sigma_or_tolerance" if type="process":   estimated process standard deviation
#                      if type="tolerance": tolerance width (USL - LSL)
#
# Needs only base R — no external libraries required.
#
# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

#
# Provides Gauge R&R study design guidance based on AIAG MSA (Measurement
# Systems Analysis) standard rules. Shows a table over standard operator and
# replicate combinations, reporting:
#   - Total number of measurements
#   - Number of distinct categories (ndc)
#   - Degrees of freedom for each variance component
#   - AIAG acceptance verdict
#
# ndc (number of distinct categories) is the key metric:
#   ndc >= 5   — measurement system is acceptable (can distinguish 5+ categories)
#   ndc >= 2   — marginal
#   ndc <  2   — inadequate measurement system
#
# The AIAG baseline study design is 10 parts x 3 operators x 2 replicates.
# This script shows how deviations from that baseline affect study quality.
#
# %GRR thresholds (AIAG MSA, 4th edition):
#   %GRR < 10%  — acceptable measurement system
#   %GRR < 30%  — may be acceptable depending on application
#   %GRR >= 30% — measurement system needs improvement
#
# Reference:
#   AIAG (2010). Measurement Systems Analysis Reference Manual, 4th edition.
#   Automotive Industry Action Group, Southfield, MI.
#   Montgomery, D.C. (2012). Introduction to Statistical Quality Control,
#   7th ed. Wiley. Chapter 12.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 3) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_msa_grr_design.R <grr> <type> <sigma_or_tolerance>",
    "Example (10% GRR of process variation, sigma=0.5):",
    "  Rscript jrc_msa_grr_design.R 10 process 0.5",
    "Example (10% GRR of tolerance, tolerance=5.0):",
    "  Rscript jrc_msa_grr_design.R 10 tolerance 5.0",
    sep = "\n"
  ))
}

grr_pct <- suppressWarnings(as.double(args[1]))
type    <- tolower(args[2])
ref_val <- suppressWarnings(as.double(args[3]))

if (is.na(grr_pct) || grr_pct <= 0 || grr_pct >= 100) {
  stop(paste("'grr' must be a number between 0 and 100 (exclusive). Got:", args[1]))
}
if (!type %in% c("process", "tolerance")) {
  stop(paste("'type' must be 'process' or 'tolerance'. Got:", args[2]))
}
if (is.na(ref_val) || ref_val <= 0) {
  stop(paste("'sigma_or_tolerance' must be a positive number. Got:", args[3]))
}

# ---------------------------------------------------------------------------
# Derived quantities
# ---------------------------------------------------------------------------

# AIAG uses 5.15*sigma = 99% spread of normal distribution
# %GRR = 100 * (5.15 * sigma_gauge) / (5.15 * sigma_ref) = 100 * sigma_gauge / sigma_ref
# so sigma_gauge = (grr_pct/100) * sigma_ref

if (type == "process") {
  sigma_total <- ref_val
  sigma_gauge <- (grr_pct / 100) * sigma_total
} else {
  # tolerance = 5.15 * sigma_total  (AIAG convention)
  sigma_total <- ref_val / 5.15
  sigma_gauge <- (grr_pct / 100) * (ref_val / 5.15)
}

# sigma_parts from total and gauge via variance additivity
var_parts <- sigma_total^2 - sigma_gauge^2
if (var_parts <= 0) {
  stop(paste(
    "The specified %GRR implies sigma_gauge >= sigma_total, leaving no",
    "part-to-part variation. Reduce %GRR or check your inputs."
  ))
}
sigma_parts <- sqrt(var_parts)

# ndc: number of distinct categories the measurement system can resolve
# ndc = floor(1.41 * sigma_parts / sigma_gauge)
ndc_val <- floor(1.41 * sigma_parts / sigma_gauge)

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

ref_label <- if (type == "process") {
  paste("process SD (sigma):", ref_val)
} else {
  paste("tolerance (USL - LSL):", ref_val)
}

message(" ")
message("✅ Gauge R&R Study Design (AIAG MSA)")
message("   version: 1.0, author: Joep Rous")
message("   ======================================")
message(paste("   target %GRR:                 ", grr_pct, "%"))
message(paste("   %GRR expressed as % of:      ", type))
message(paste("  ", ref_label))
message(paste("   sigma_total:                 ", round(sigma_total, 6)))
message(paste("   sigma_gauge (target):        ", round(sigma_gauge, 6)))
message(paste("   sigma_parts:                 ", round(sigma_parts, 6)))
message(paste("   ndc (distinct categories):   ", ndc_val))
message(" ")

# ndc verdict
if (ndc_val >= 5) {
  message(paste0("✅ ndc = ", ndc_val, " — measurement system is acceptable (ndc >= 5)."))
} else if (ndc_val >= 2) {
  message(paste0("⚠️  ndc = ", ndc_val, " — measurement system is marginal (2 <= ndc < 5)."))
  message("   The measurement system may not distinguish process variation adequately.")
} else {
  message(paste0("❌ ndc = ", ndc_val, " — measurement system is inadequate (ndc < 2)."))
  message("   The %GRR target is too high relative to process variation.")
  message("   Improve the measurement system before conducting the GRR study.")
}

message(" ")

# %GRR verdict
if (grr_pct < 10) {
  message(paste0("✅ %GRR = ", grr_pct, "% — excellent measurement system (< 10%)."))
} else if (grr_pct < 30) {
  message(paste0("⚠️  %GRR = ", grr_pct, "% — may be acceptable depending on application (10-30%)."))
  message("   Acceptable for many device applications if ndc >= 5.")
} else {
  message(paste0("❌ %GRR = ", grr_pct, "% — measurement system needs improvement (>= 30%)."))
}

message(" ")

# ---------------------------------------------------------------------------
# Study design table
# ---------------------------------------------------------------------------

operators_list  <- c(2, 3)
replicates_list <- c(2, 3)
parts_aiag      <- 10   # AIAG minimum

message("   Study design options (AIAG minimum: 10 parts):")
message(" ")
message("   -----------------------------------------------------------------------")
message("    operators   replicates   total meas.   df_repeat   df_reprod   note")
message("   -----------------------------------------------------------------------")

for (o in operators_list) {
  for (r in replicates_list) {
    p          <- parts_aiag
    total      <- p * o * r
    df_repeat  <- o * p * (r - 1)
    df_reprod  <- o - 1
    df_parts   <- p - 1

    # Flag low df for reproducibility
    reprod_warn <- if (df_reprod < 2) " \u26a0 low df" else ""

    # Flag AIAG baseline
    baseline <- if (o == 3 && r == 2) "  \u2190 AIAG baseline" else ""

    message(sprintf(
      "    o = %d        r = %d         %4d          %4d        %4d%s%s",
      o, r, total, df_repeat, df_reprod, reprod_warn, baseline
    ))
  }
}

message("   -----------------------------------------------------------------------")
message(" ")
message(paste("   All combinations use", parts_aiag,
              "parts (AIAG minimum for reliable variance estimates)."))
message(" ")

# ---------------------------------------------------------------------------
# Recommendation
# ---------------------------------------------------------------------------

message("   Recommendation:")
message(" ")
message("   Use at least 10 parts, 3 operators, 2 replicates (AIAG baseline).")
message("   Parts should span the full range of process variation, not just")
message("   a narrow range — part-to-part variation drives the ndc calculation.")
message(" ")
if (grr_pct >= 10) {
  message("   With %GRR >= 10%, consider increasing operators or replicates to")
  message("   improve precision of the variance component estimates.")
  message(" ")
}
message("   Degrees of freedom (df) guidelines:")
message("   df_repeat >= 20  — good precision for repeatability estimate")
message("   df_reprod >= 2   — minimum for reproducibility (3 operators preferred)")
message("   df_parts  >= 9   — minimum for part-to-part variance (10 parts)")
message(" ")
message("   Note:")
message("   This script provides study design guidance based on AIAG rules.")
message("   Formal power analysis for GRR studies requires assumed variance")
message("   components (sigma_repeatability, sigma_reproducibility) which are")
message("   typically unknown before the study. For critical measurement systems,")
message("   consider a pilot study with 5 parts to estimate variance components")
message("   before committing to the full study design.")
message(" ")
