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
# Determines the minimum number of pilot samples needed to estimate the process
# standard deviation sigma with sufficient precision, so that the tolerance
# interval calculations in jrc_ss_attr and jrc_ss_attr_ci are trustworthy.
#
# The formula is based on the power of a one- or two-sided t-test to detect a
# process shift of 'precision' * sigma:
#
#   n = ceiling( ((z_alpha + z_beta) / precision)^2 ) + 1
#
# where z_alpha is the normal quantile for the confidence level (one-sided or
# two-sided) and z_beta is the normal quantile for the power/reliability.
#
# Results are shown as a table over standard combinations of power (0.90, 0.95,
# 0.99) and confidence (0.90, 0.95, 0.99).
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
# Version: 1.0

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
# Sample size formula
# ---------------------------------------------------------------------------

# Minimum n to detect a process shift of 'precision' * sigma with given
# power and confidence, using a one- or two-sided normal approximation.
min_n_sigma <- function(precision, power, confidence, two_sided = FALSE) {
  z_alpha <- if (two_sided) qnorm((1 + confidence) / 2) else qnorm(confidence)
  z_beta  <- qnorm(power)
  ceiling(((z_alpha + z_beta) / precision)^2) + 1
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

interval_type <- if (two_sided) "2-sided" else "1-sided"

message(" ")
message("✅ Minimum Pilot Sample Size for Sigma Estimation")
message("   version: 1.0, author: Joep Rous")
message("   =================================================")
message(paste("   precision (detectable shift in sigma units): ", precision))
message(paste("   spec limit 1 (lower):                       ", if (has_spec1) spec1_raw else "-"))
message(paste("   spec limit 2 (upper):                       ", if (has_spec2) spec2_raw else "-"))
message(paste("   interval type:                              ", interval_type))
message(" ")

powers      <- c(0.90, 0.95, 0.99)
confidences <- c(0.90, 0.95, 0.99)

# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------

message(paste0("   Minimum pilot N (", interval_type, " interval):"))
message(" ")
message("   -----------------------------------------------")
message("                    confidence")
message("   power      0.90      0.95      0.99")
message("   -----------------------------------------------")

for (power in powers) {
  vals <- sapply(confidences, function(conf) {
    min_n_sigma(precision, power, conf, two_sided = two_sided)
  })
  message(sprintf("   p = %.2f   %4d      %4d      %4d",
                  power, vals[1], vals[2], vals[3]))
}

message("   -----------------------------------------------")
message(" ")

# ---------------------------------------------------------------------------
# Interpretation note
# ---------------------------------------------------------------------------

n_fda <- min_n_sigma(precision, 0.95, 0.95, two_sided = two_sided)

message("   How to use this table:")
message(paste0(
  "   Select the cell matching your protocol's power and confidence requirements.",
  ""
))
message(paste0(
  "   For FDA design verification (power = 0.95, confidence = 0.95): N >= ", n_fda, "."
))
message(" ")
message("   If your pilot dataset is smaller than the required N, the sigma")
message("   estimate used in jrc_ss_attr may be unreliable, which could cause")
message("   the required verification sample size to be under-estimated.")
message(" ")
message("   Note:")
message("   The FDA minimum of 10 samples applies as an absolute floor regardless")
message("   of the statistical result. If the table value is below 10, use N = 10.")
message(" ")
message("   This table assumes the process follows a normal distribution.")
message("   For non-normal data, Box-Cox transformation is applied by jrc_ss_attr")
message("   before estimating sigma — run this script on the transformed data")
message("   if the pilot data is known to be non-normal.")
message(" ")
