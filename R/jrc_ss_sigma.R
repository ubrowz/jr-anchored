#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_sigma.R <precision> <spec1> <spec2>
#
# "precision"   the process shift (in multiples of sigma) that the pilot study
#               must be able to detect. Common values:
#                 1.0 — detect a 1-sigma shift (demanding, more samples needed)
#                 1.5 — detect a 1.5-sigma shift (moderate)
#                 2.0 — detect a 2-sigma shift (lenient, fewer samples needed)
# "spec1"       lower spec limit, or "-" if not applicable
# "spec2"       upper spec limit, or "-" if not applicable
#
# At least one of spec1 / spec2 must be numeric. Pass "-" for the one that
# does not apply:
#   1-sided lower:  spec1 = <value>  spec2 = -
#   1-sided upper:  spec1 = -        spec2 = <value>
#   2-sided:        spec1 = <value>  spec2 = <value>
#
# The interval type (1-sided or 2-sided) determines whether a one-sided or
# two-sided hypothesis test is assumed, which affects the required sample size.
# Use the same interval type here as in jrc_ss_attr and jrc_ss_attr_ci.
#
# Needs only base R — no external libraries required.
#
# Determines a minimum pilot sample size from the power of a one- or
# two-sided test to DETECT A SHIFT of the process mean of 'precision' * sigma
# (normal approximation):
#
#   n = ceiling( ((z_alpha + z_beta) / precision)^2 ) + 1
#
# where z_alpha is the normal quantile for the confidence level (one-sided or
# two-sided) and z_beta is the normal quantile for the power/reliability.
#
# Results are shown as a table over standard combinations of power (0.90, 0.95,
# 0.99) and confidence (0.90, 0.95, 0.99).
#
# What this is NOT: a criterion for how precisely sigma itself is estimated.
# The width of a confidence interval for sigma follows the chi-squared
# distribution and is not computed here. Up to v1.0 the script was titled
# "Minimum Pilot Sample Size for Sigma Estimation", which overstated what
# the formula delivers (code review 2026-10, COR-20).
#
# Use this script before running jrc_ss_attr to verify that your pilot dataset
# is large enough to give a reliable sigma estimate. If your pilot N is below
# the value in the relevant cell, the tolerance interval sample size result
# from jrc_ss_attr may be under-estimated.
#
# Reference:
#   Browne, R.H. (2001). Using the sample range as a basis for calculating
#   sample size in power calculations. The American Statistician, 55(4), 293-298.
#   Montgomery, D.C. (2012). Introduction to Statistical Quality Control,
#   7th ed. Wiley. Section 3.3: Estimating process standard deviation.
#
# Author: Joep Rous
# Version: 1.1

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.1"   # single source for banner, report and JSON

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 3) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_ss_sigma.R <precision> <spec1> <spec2>",
    "Example (1-sided lower, detect 1-sigma shift):",
    "  Rscript jrc_ss_sigma.R 1.0 8.0 -",
    "Example (2-sided, detect 1.5-sigma shift):",
    "  Rscript jrc_ss_sigma.R 1.5 8.0 12.0",
    sep = "\n"
  ))
}

precision <- suppressWarnings(as.double(args[1]))
spec1_raw <- suppressWarnings(as.double(args[2]))
spec2_raw <- suppressWarnings(as.double(args[3]))

if (is.na(precision) || precision <= 0) {
  stop(paste("'precision' must be a positive number (e.g. 1.0, 1.5, 2.0). Got:", args[1]))
}
if (precision < 0.5) {
  warning(paste(
    "'precision' =", precision, "is very small and will require a very large pilot sample.",
    "Typical values are 1.0, 1.5, or 2.0."
  ))
}

has_spec1 <- !is.na(spec1_raw)
has_spec2 <- !is.na(spec2_raw)

if (!has_spec1 && !has_spec2) {
  stop("Both spec1 and spec2 are '-'. At least one numeric spec limit must be provided.")
}
if (args[2] != "-" && !has_spec1) {
  stop(paste("'spec1' must be a numeric value or '-'. Got:", args[2]))
}
if (args[3] != "-" && !has_spec2) {
  stop(paste("'spec2' must be a numeric value or '-'. Got:", args[3]))
}
if (has_spec1 && has_spec2 && spec2_raw <= spec1_raw) {
  stop(paste("'spec2' must be greater than 'spec1'. Got spec1 =", spec1_raw,
             "and spec2 =", spec2_raw))
}

two_sided  <- has_spec1 && has_spec2
lower_only <- has_spec1 && !has_spec2
upper_only <- !has_spec1 && has_spec2

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

interval_type <- if (two_sided) "2-sided" else "1-sided"

jr_say(" ")
jr_say("✅ Minimum Pilot Sample Size (detect a mean shift of precision x sigma)")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   =================================================")
jr_say(paste("   precision (detectable shift in sigma units): ", precision))
jr_say(paste("   spec limit 1 (lower):                       ", if (has_spec1) spec1_raw else "-"))
jr_say(paste("   spec limit 2 (upper):                       ", if (has_spec2) spec2_raw else "-"))
jr_say(paste("   interval type:                              ", interval_type))
jr_say(" ")

powers      <- c(0.90, 0.95, 0.99)
confidences <- c(0.90, 0.95, 0.99)

# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------

jr_say(paste0("   Minimum pilot N (", interval_type, " interval):"))
jr_say(" ")
jr_say("   -----------------------------------------------")
jr_say("                    confidence")
jr_say("   power      0.90      0.95      0.99")
jr_say("   -----------------------------------------------")

for (power in powers) {
  vals <- sapply(confidences, function(conf) {
    jr_min_n_normal(precision, power, conf, two_sided = two_sided)
  })
  jr_say(sprintf("   p = %.2f   %4d      %4d      %4d",
                  power, vals[1], vals[2], vals[3]))
}

jr_say("   -----------------------------------------------")
jr_say(" ")

# ---------------------------------------------------------------------------
# Interpretation note
# ---------------------------------------------------------------------------

n_fda <- jr_min_n_normal(precision, 0.95, 0.95, two_sided = two_sided)

jr_say("   How to use this table:")
jr_say(paste0(
  "   Select the cell matching your protocol's power and confidence requirements.",
  ""
))
jr_say(paste0(
  "   At power = 0.95 and confidence = 0.95 (a common choice): N >= ", n_fda, "."
))
jr_say(" ")
jr_say("   If your pilot dataset is smaller than the required N, the sigma")
jr_say("   estimate used in jrc_ss_attr may be unreliable, which could cause")
jr_say("   the required verification sample size to be under-estimated.")
jr_say(" ")
jr_say("   Note:")
jr_say("   Many organisations apply a floor of 10 samples (common practice,")
jr_say("   not a regulatory rule): if the table value is below 10, use N = 10.")
jr_say(" ")
jr_say("   This N gives the stated power to detect a mean shift of precision x sigma.")
jr_say("   It does not quantify how precisely sigma itself is estimated.")
jr_say(" ")
jr_say("   This table assumes the process follows a normal distribution.")
jr_say("   For non-normal data, Box-Cox transformation is applied by jrc_ss_attr")
jr_say("   before estimating sigma — run this script on the transformed data")
jr_say("   if the pilot data is known to be non-normal.")
jr_say(" ")
