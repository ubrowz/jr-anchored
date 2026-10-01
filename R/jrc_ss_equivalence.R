#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_equivalence.R <delta> <sd> <sides>
#
# "delta"   the equivalence margin — the maximum difference that is still
#           considered equivalent (absolute value, same units as the
#           measurement). Must be pre-specified in the protocol.
#           Example: 0.5 means differences up to 0.5N are acceptable.
# "sd"      expected standard deviation of the differences between the two
#           conditions. Estimate from a pilot study or prior data.
# "sides"   1 for 1-sided equivalence (non-inferiority: new >= predicate - delta)
#           2 for 2-sided equivalence (new is within +/- delta of predicate)
#
# Needs only base R — no external libraries required.
#
# Determines the minimum number of paired observations needed to demonstrate
# equivalence between two conditions using the TOST (Two One-Sided Tests)
# procedure at a given power and confidence level.
#
# The TOST sample size formula is:
#
#   n = ceiling( ((z_alpha + z_beta) / effect_size)^2 ) + 1
#
# where effect_size = delta / sd, z_alpha is the one-sided normal quantile
# for the significance level (= 1 - confidence), and z_beta is the normal
# quantile for the power. Note that z_alpha is always one-sided in TOST
# regardless of whether 1-sided or 2-sided equivalence is tested, because
# each of the two component tests is inherently directional.
#
# For 2-sided equivalence (true difference assumed 0) BOTH one-sided tests
# must reject, so the type II error is split over the two sides and
# z_beta = qnorm(1 - (1 - power) / 2) is used (Chow, Shao & Wang 2008,
# Sec. 3.2; consistent with jrc_clinical_ss_means). For 1-sided
# (non-inferiority) z_beta = qnorm(power).
#
# Results are shown as a table over standard combinations of power
# (0.90, 0.95, 0.99) and confidence (0.90, 0.95, 0.99).
#
# Common uses in medical device development:
#   - 510(k) substantial equivalence: new device performs within delta of
#     predicate across all critical performance characteristics
#   - Design change assessment: modified device is equivalent to original
#   - Method comparison: two measurement systems give equivalent results
#   - Manufacturing site transfer: output from new site is equivalent
#
# Note: 'n' is the number of pairs. Each pair consists of one measurement
# per condition on the same unit or subject.
#
# Reference:
#   Schuirmann, D.J. (1987). A comparison of the two one-sided tests
#   procedure and the power approach for assessing the equivalence of
#   average bioavailability. Journal of Pharmacokinetics and
#   Biopharmaceutics, 15(6), 657-680.
#   FDA Guidance: Statistical Approaches to Establishing Bioequivalence
#   (2001), applicable by analogy to device equivalence testing.
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
    "  Rscript jrc_ss_equivalence.R <delta> <sd> <sides>",
    "Example (2-sided, delta=0.5N, SD=1.0N):",
    "  Rscript jrc_ss_equivalence.R 0.5 1.0 2",
    "Example (1-sided non-inferiority):",
    "  Rscript jrc_ss_equivalence.R 0.5 1.0 1",
    sep = "\n"
  ))
}

delta <- suppressWarnings(as.double(args[1]))
sd    <- suppressWarnings(as.double(args[2]))
sides <- suppressWarnings(as.integer(args[3]))

if (is.na(delta) || delta <= 0) {
  stop(paste("'delta' must be a positive number. Got:", args[1]))
}
if (is.na(sd) || sd <= 0) {
  stop(paste("'sd' must be a positive number. Got:", args[2]))
}
if (is.na(sides) || !(sides %in% c(1, 2))) {
  stop(paste("'sides' must be 1 or 2. Got:", args[3]))
}

effect_size <- delta / sd
two_sided   <- sides == 2

# ---------------------------------------------------------------------------
# Sample size formula — TOST
# ---------------------------------------------------------------------------

# z_alpha is always one-sided in TOST (each component test is 1-sided).
# confidence = 1 - alpha, so alpha = 1 - confidence.
# z_beta: 2-sided equivalence needs both one-sided tests to reject, so beta is
# split over the two sides; non-inferiority uses the full beta.
min_n_tost <- function(effect_size, power, confidence, two_sided) {
  z_alpha <- qnorm(confidence)     # one-sided alpha = 1 - confidence
  z_beta  <- if (two_sided) qnorm(1 - (1 - power) / 2) else qnorm(power)
  ceiling(((z_alpha + z_beta) / effect_size)^2) + 1
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

sides_label <- if (two_sided) "2-sided (within +/- delta)" else
                               "1-sided (non-inferiority)"

message(" ")
message("✅ Sample Size for Equivalence Testing (TOST)")
message("   version: 1.0, author: Joep Rous")
message("   ==============================================")
message(paste("   delta (equivalence margin):            ", delta))
message(paste("   sd (of paired differences):            ", sd))
message(paste("   effect size (delta / sd):              ", round(effect_size, 4)))
message(paste("   equivalence type:                      ", sides_label))
message(" ")

powers      <- c(0.90, 0.95, 0.99)
confidences <- c(0.90, 0.95, 0.99)

# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------

message(paste0("   Minimum number of pairs (", sides_label, "):"))
message(" ")
message("   -----------------------------------------------")
message("                    confidence")
message("   power      0.90      0.95      0.99")
message("   -----------------------------------------------")

for (power in powers) {
  vals <- sapply(confidences, function(conf) {
    min_n_tost(effect_size, power, conf, two_sided)
  })
  message(sprintf("   p = %.2f   %4d      %4d      %4d",
                  power, vals[1], vals[2], vals[3]))
}

message("   -----------------------------------------------")
message(" ")

# ---------------------------------------------------------------------------
# Comparison with jrc_ss_paired (difference test)
# ---------------------------------------------------------------------------

# Show the difference test N for reference, so the engineer sees the contrast
min_n_diff <- function(effect_size, power, confidence, two_sided = FALSE) {
  z_alpha <- if (two_sided) qnorm((1 + confidence) / 2) else qnorm(confidence)
  z_beta  <- qnorm(power)
  ceiling(((z_alpha + z_beta) / effect_size)^2) + 1
}

n_equiv_9595 <- min_n_tost(effect_size, 0.95, 0.95, two_sided)
n_diff_9595  <- min_n_diff(effect_size, 0.95, 0.95, two_sided = two_sided)

message(paste0(
  "   For FDA submissions (power = 0.95, confidence = 0.95): N >= ",
  n_equiv_9595, " pairs."
))
message(" ")
message(sprintf(
  "   For reference: a difference test (jrc_ss_paired) at 95/95 requires N >= %d pairs.",
  n_diff_9595
))
message("   For the same delta and SD, equivalence testing needs at least as many")
message("   pairs as difference testing (equal under the normal approximation when")
message("   the true difference is assumed to be zero).")
message(" ")

# ---------------------------------------------------------------------------
# TOST explanation
# ---------------------------------------------------------------------------

message("   What is TOST?")
message("   TOST (Two One-Sided Tests) is the standard statistical method for")
message("   demonstrating equivalence. It works by testing two hypotheses")
message("   simultaneously:")
if (two_sided) {
  message("     H1: the true difference is greater than -delta")
  message("     H2: the true difference is less than  +delta")
  message("   Equivalence is demonstrated only if BOTH tests pass. This is")
  message("   equivalent to showing that the (1 - 2*alpha) two-sided confidence")
  message("   interval for the difference (e.g. 90% at confidence 0.95) falls")
  message("   entirely within [-delta, +delta].")
} else {
  message("     H1: the new condition is not worse than predicate - delta")
  message("   Non-inferiority is demonstrated if the one-sided lower confidence")
  message("   bound (at the chosen confidence, e.g. 95%) for the difference is")
  message("   above -delta.")
}
message(" ")
message("   Important: demonstrating equivalence is NOT the same as failing")
message("   to detect a difference. A non-significant difference test does")
message("   not establish equivalence. TOST must be pre-specified in the")
message("   protocol with a justified equivalence margin delta.")
message(" ")
