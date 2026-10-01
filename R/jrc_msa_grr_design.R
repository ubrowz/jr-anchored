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
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.1"   # single source for banner, report and JSON

#
# Provides Gauge R&R study design guidance based on AIAG MSA (Measurement
# Systems Analysis) standard rules. Reports, for the target %GRR:
#   - the implied gauge, part and total standard deviations
#   - the number of distinct categories (ndc) with its AIAG verdict
#   - the %GRR verdict
# followed by a table of operator x replicate combinations (10 parts) showing
# the total number of measurements and the repeatability / reproducibility
# degrees of freedom. The table does not depend on the inputs.
#
# Spreads use 6 sigma (AIAG MSA 4th ed.), as in jrc_msa_gauge_rr, _nested_grr
# and _type1. Up to v1.0 this script used 5.15 sigma (3rd ed.) (code review
# 2026-10, COR-22).
#
# Tolerance mode assumption: the process spread 6 * sigma_total is taken to
# equal the tolerance (process Cp = 1), which fixes the part-to-part variation
# used for ndc. ndc then depends only on the %GRR. If the process is more
# capable (Cp > 1), the actual ndc for the same %GRR of tolerance is LOWER.
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
# Version: 1.1

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

# AIAG MSA 4th ed.: spread = 6 * sigma
#   process:   %GRR = 100 * 6 sigma_gauge / (6 sigma_total) -> sigma_gauge = g * sigma_total
#   tolerance: %GRR = 100 * 6 sigma_gauge / tolerance       -> sigma_gauge = g * tolerance / 6
SPREAD_SIGMAS <- 6

if (type == "process") {
  sigma_total <- ref_val
  sigma_gauge <- (grr_pct / 100) * sigma_total
} else {
  # Assumption (stated in the output): tolerance = 6 * sigma_total, i.e. Cp = 1
  sigma_total <- ref_val / SPREAD_SIGMAS
  sigma_gauge <- (grr_pct / 100) * (ref_val / SPREAD_SIGMAS)
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

jr_say(" ")
jr_say("✅ Gauge R&R Study Design (AIAG MSA)")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ======================================")
jr_say(paste("   target %GRR:                 ", grr_pct, "%"))
jr_say(paste("   %GRR expressed as % of:      ", type))
jr_say(paste("  ", ref_label))
jr_say(paste("   sigma_total:                 ", round(sigma_total, 6)))
jr_say(paste("   sigma_gauge (target):        ", round(sigma_gauge, 6)))
jr_say(paste("   sigma_parts:                 ", round(sigma_parts, 6)))
jr_say(paste("   ndc (distinct categories):   ", ndc_val))
jr_say(" ")
if (type == "tolerance") {
  jr_say("   Assumption (tolerance mode): the process spread 6 x sigma_total equals")
  jr_say("   the tolerance (process Cp = 1). sigma_total and ndc follow from that.")
  jr_say("   If your process is more capable (Cp > 1), the actual ndc for this")
  jr_say("   %GRR of tolerance is LOWER; use type = process with your sigma instead.")
  jr_say(" ")
}

# ndc verdict
if (ndc_val >= 5) {
  jr_say(paste0("✅ ndc = ", ndc_val, " — measurement system is acceptable (ndc >= 5)."))
} else if (ndc_val >= 2) {
  jr_say(paste0("⚠️  ndc = ", ndc_val, " — measurement system is marginal (2 <= ndc < 5)."))
  jr_say("   The measurement system may not distinguish process variation adequately.")
} else {
  jr_say(paste0("❌ ndc = ", ndc_val, " — measurement system is inadequate (ndc < 2)."))
  jr_say("   The %GRR target is too high relative to process variation.")
  jr_say("   Improve the measurement system before conducting the GRR study.")
}

jr_say(" ")

# %GRR verdict
if (grr_pct < 10) {
  jr_say(paste0("✅ %GRR = ", grr_pct, "% — excellent measurement system (< 10%)."))
} else if (grr_pct < 30) {
  jr_say(paste0("⚠️  %GRR = ", grr_pct, "% — may be acceptable depending on application (10-30%)."))
  jr_say("   Acceptable for many device applications if ndc >= 5.")
} else {
  jr_say(paste0("❌ %GRR = ", grr_pct, "% — measurement system needs improvement (>= 30%)."))
}

jr_say(" ")

# ---------------------------------------------------------------------------
# Study design table
# ---------------------------------------------------------------------------

operators_list  <- c(2, 3)
replicates_list <- c(2, 3)
parts_aiag      <- 10   # AIAG minimum

jr_say("   Study design options (AIAG minimum: 10 parts):")
jr_say(" ")
jr_say("   -----------------------------------------------------------------------")
jr_say("    operators   replicates   total meas.   df_repeat   df_reprod   note")
jr_say("   -----------------------------------------------------------------------")

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

    jr_say(sprintf(
      "    o = %d        r = %d         %4d          %4d        %4d%s%s",
      o, r, total, df_repeat, df_reprod, reprod_warn, baseline
    ))
  }
}

jr_say("   -----------------------------------------------------------------------")
jr_say(" ")
jr_say(paste("   All combinations use", parts_aiag,
              "parts (AIAG minimum for reliable variance estimates)."))
jr_say(" ")

# ---------------------------------------------------------------------------
# Recommendation
# ---------------------------------------------------------------------------

jr_say("   Recommendation:")
jr_say(" ")
jr_say("   Use at least 10 parts, 3 operators, 2 replicates (AIAG baseline).")
jr_say("   Parts should span the full range of process variation, not just")
jr_say("   a narrow range — part-to-part variation drives the ndc calculation.")
jr_say(" ")
if (grr_pct >= 10) {
  jr_say("   With %GRR >= 10%, consider increasing operators or replicates to")
  jr_say("   improve precision of the variance component estimates.")
  jr_say(" ")
}
jr_say("   Degrees of freedom (df) guidelines:")
jr_say("   df_repeat >= 20  — good precision for repeatability estimate")
jr_say("   df_reprod >= 2   — minimum for reproducibility (3 operators preferred)")
jr_say("   df_parts  >= 9   — minimum for part-to-part variance (10 parts)")
jr_say(" ")
jr_say("   Note:")
jr_say("   This script provides study design guidance based on AIAG rules.")
jr_say("   Formal power analysis for GRR studies requires assumed variance")
jr_say("   components (sigma_repeatability, sigma_reproducibility) which are")
jr_say("   typically unknown before the study. For critical measurement systems,")
jr_say("   consider a pilot study with 5 parts to estimate variance components")
jr_say("   before committing to the full study design.")
jr_say(" ")
