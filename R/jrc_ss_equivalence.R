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
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.0"   # single source for banner, report and JSON

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

jr_say(" ")
jr_say("✅ Sample Size for Equivalence Testing (TOST)")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ==============================================")
jr_say(paste("   delta (equivalence margin):            ", delta))
jr_say(paste("   sd (of paired differences):            ", sd))
jr_say(paste("   effect size (delta / sd):              ", round(effect_size, 4)))
jr_say(paste("   equivalence type:                      ", sides_label))
jr_say(" ")

powers      <- c(0.90, 0.95, 0.99)
confidences <- c(0.90, 0.95, 0.99)

# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------

jr_say(paste0("   Minimum number of pairs (", sides_label, "):"))
jr_say(" ")
jr_say("   -----------------------------------------------")
jr_say("                    confidence")
jr_say("   power      0.90      0.95      0.99")
jr_say("   -----------------------------------------------")

for (power in powers) {
  vals <- sapply(confidences, function(conf) {
    min_n_tost(effect_size, power, conf, two_sided)
  })
  jr_say(sprintf("   p = %.2f   %4d      %4d      %4d",
                  power, vals[1], vals[2], vals[3]))
}

jr_say("   -----------------------------------------------")
jr_say(" ")

# ---------------------------------------------------------------------------
# Comparison with jrc_ss_paired (difference test)
# ---------------------------------------------------------------------------

n_equiv_9595 <- min_n_tost(effect_size, 0.95, 0.95, two_sided)
n_diff_9595  <- jr_min_n_normal(effect_size, 0.95, 0.95, two_sided = two_sided)

jr_say(paste0(
  "   At power = 0.95 and confidence = 0.95 (a common choice): N >= ",
  n_equiv_9595, " pairs."
))
jr_say(" ")
jr_say(sprintf(
  "   For reference: a difference test (jrc_ss_paired) at 95/95 requires N >= %d pairs.",
  n_diff_9595
))
jr_say("   For the same delta and SD, equivalence testing needs at least as many")
jr_say("   pairs as difference testing (equal under the normal approximation when")
jr_say("   the true difference is assumed to be zero).")
jr_say(" ")

# ---------------------------------------------------------------------------
# TOST explanation
# ---------------------------------------------------------------------------

jr_say("   What is TOST?")
jr_say("   TOST (Two One-Sided Tests) is the standard statistical method for")
jr_say("   demonstrating equivalence. It works by testing two hypotheses")
jr_say("   simultaneously:")
if (two_sided) {
  jr_say("     H1: the true difference is greater than -delta")
  jr_say("     H2: the true difference is less than  +delta")
  jr_say("   Equivalence is demonstrated only if BOTH tests pass. This is")
  jr_say("   equivalent to showing that the (1 - 2*alpha) two-sided confidence")
  jr_say("   interval for the difference (e.g. 90% at confidence 0.95) falls")
  jr_say("   entirely within [-delta, +delta].")
} else {
  jr_say("     H1: the new condition is not worse than predicate - delta")
  jr_say("   Non-inferiority is demonstrated if the one-sided lower confidence")
  jr_say("   bound (at the chosen confidence, e.g. 95%) for the difference is")
  jr_say("   above -delta.")
}
jr_say(" ")
jr_say("   Important: demonstrating equivalence is NOT the same as failing")
jr_say("   to detect a difference. A non-significant difference test does")
jr_say("   not establish equivalence. TOST must be pre-specified in the")
jr_say("   protocol with a justified equivalence margin delta.")
jr_say(" ")
