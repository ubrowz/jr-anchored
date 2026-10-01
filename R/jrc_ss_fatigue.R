#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_fatigue.R <reliability> <confidence> <shape> <af>
#
# "reliability" minimum fraction of units that must survive to the target
#               life (e.g. 0.90 for B10, 0.99 for B1, 0.999 for B0.1).
#               This is the reliability at the target life, not a proportion
#               of the test duration.
# "confidence"  statistical confidence level (e.g. 0.95)
# "shape"       Weibull shape parameter (beta). Must be estimated from prior
#               data, literature, or engineering knowledge. Controls how
#               quickly failures accumulate:
#                 beta < 1: early failures (infant mortality)
#                 beta = 1: constant failure rate (exponential)
#                 beta > 1: wear-out failures (typical for fatigue)
#                 beta ~ 2: common for metallic fatigue
#                 beta ~ 3-4: common for polymer fatigue
# "af"          acceleration factor: ratio of test duration to target life.
#               af = 1.0 means testing exactly to the target life.
#               af = 2.0 means testing to twice the target life (each unit
#               accumulates 2x the target life cycles or duration).
#               Must be >= 1.0. Higher af reduces the required sample size
#               but requires longer individual tests.
#
# Needs only base R — no external libraries required.
#
# Determines the minimum number of units to test to the target life (or
# accelerated life) to demonstrate Weibull reliability with a given confidence.
# Results are shown for f = 0 to 5 allowed failures.
#
# With an acceleration factor AF and Weibull shape beta, the effective
# per-unit failure probability at the test duration is:
#
#   p_eff = 1 - reliability^(AF^beta)
#
# The minimum n for at most f failures at confidence C is the exact binomial
# minimum (Clopper-Pearson), the same criterion as jrc_ss_discrete:
#
#   smallest n with pbinom(f, n, p_eff) <= 1 - C
#
# At AF = 1 the result equals jrc_ss_discrete for proportion = reliability.
# Up to v1.0 the chi-squared (Poisson) approximation
#   n = ceiling( qchisq(C, 2f + 2) / (2 p_eff) )
# was used, which overestimates n by 0-3 (code review 2026-10, COR-18/19).
#
# IMPORTANT: the Weibull shape parameter beta is an assumed value, not
# estimated from the test data. The result is sensitive to this assumption.
# If beta is uncertain, run the script for a range of plausible beta values
# and use the most conservative (largest n) result.
#
# Common uses in medical device development:
#   - Fatigue life demonstration for implants (e.g. hip stems, spinal rods)
#   - Cyclic loading tests for cardiovascular devices
#   - Accelerated lifetime testing for polymer components
#   - Wear testing for articulating surfaces
#
# Reference:
#   Meeker, W.Q., Hahn, G.J., Escobar, L.A. (2017). Statistical Intervals:
#   A Guide for Practitioners and Researchers, 2nd ed. Wiley. Chapter 8.
#   Nelson, W.B. (2004). Accelerated Testing: Statistical Models, Test Plans,
#   and Data Analysis. Wiley.
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

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_ss_fatigue.R <reliability> <confidence> <shape> <af>",
    "Example (B10 life, 95% confidence, Weibull beta=2, no acceleration):",
    "  Rscript jrc_ss_fatigue.R 0.90 0.95 2.0 1.0",
    "Example (B10 life, 95% confidence, Weibull beta=2, AF=2):",
    "  Rscript jrc_ss_fatigue.R 0.90 0.95 2.0 2.0",
    sep = "\n"
  ))
}

reliability <- suppressWarnings(as.double(args[1]))
confidence  <- suppressWarnings(as.double(args[2]))
shape       <- suppressWarnings(as.double(args[3]))
af          <- suppressWarnings(as.double(args[4]))

if (is.na(reliability) || reliability <= 0 || reliability >= 1) {
  stop(paste("'reliability' must be a number strictly between 0 and 1. Got:", args[1]))
}
if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be a number strictly between 0 and 1. Got:", args[2]))
}
if (is.na(shape) || shape <= 0) {
  stop(paste("'shape' must be a positive number. Got:", args[3]))
}
if (is.na(af) || af < 1.0) {
  stop(paste("'af' must be >= 1.0. Got:", args[4]))
}

# ---------------------------------------------------------------------------
# Formula
# ---------------------------------------------------------------------------

# Effective per-unit failure probability at the test duration
p_eff <- 1 - reliability^(af^shape)

if (p_eff <= 0 || p_eff >= 1) {
  stop(paste(
    "The combination of reliability, shape, and af gives an invalid effective",
    "failure probability:", round(p_eff, 6),
    "Check your input parameters."
  ))
}

min_n_fatigue <- function(confidence, f, p_eff) {
  jr_binom_min_n(1 - p_eff, confidence, f)
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

b_life <- round((1 - reliability) * 100, 3)

jr_say(" ")
jr_say("✅ Sample Size for Fatigue / Lifetime Testing (Weibull)")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ========================================================")
jr_say(paste("   target reliability (B-life):           ", reliability,
              paste0("  (B", b_life, " life)")))
jr_say(paste("   confidence:                            ", confidence))
jr_say(paste("   Weibull shape parameter (beta):        ", shape))
jr_say(paste("   acceleration factor (AF):              ", af))
jr_say(paste("   effective failure probability (p_eff): ", round(p_eff, 6)))
jr_say(" ")

if (af > 1.0) {
  jr_say(paste0("   Each unit is tested to ", af, "x the target life."))
  jr_say(paste0("   Equivalent reliability at test duration: ",
                 round(1 - p_eff, 6)))
  jr_say(" ")
}

# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------

jr_say("   Minimum sample sizes by number of allowed failures:")
jr_say(" ")
jr_say("   -----------------------------------------------")
jr_say("    failures (f)   min sample size (n)   note")
jr_say("   -----------------------------------------------")

for (f in 0:5) {
  n    <- min_n_fatigue(confidence, f, p_eff)
  note <- if (f == 0) "  \u2190 recommended (zero-failure)" else
          if (f <= 2) "  \u26a0  requires justification"    else
                      "  \u26a0  requires strong justification"
  jr_say(sprintf("    f = %d          n = %4d              %s", f, n, note))
}

jr_say("   -----------------------------------------------")
jr_say(" ")

# ---------------------------------------------------------------------------
# Sensitivity note on shape parameter
# ---------------------------------------------------------------------------

if (af > 1.0) {
  # Show n at f=0 for beta -/+ 0.5 (the low value stays below the assumed
  # beta: halved when beta <= 0.5) to illustrate sensitivity
  shape_low  <- if (shape > 0.5) shape - 0.5 else shape / 2
  shape_high <- shape + 0.5
  p_low  <- 1 - reliability^(af^shape_low)
  p_high <- 1 - reliability^(af^shape_high)
  n_low  <- if (p_low  > 0 && p_low  < 1) min_n_fatigue(confidence, 0, p_low)  else NA
  n_high <- if (p_high > 0 && p_high < 1) min_n_fatigue(confidence, 0, p_high) else NA

  jr_say("   Sensitivity to Weibull shape parameter (f = 0):")
  jr_say(" ")
  jr_say("   -----------------------------------------------")
  jr_say("    beta           min sample size (n, f=0)")
  jr_say("   -----------------------------------------------")
  if (!is.na(n_low)) {
    jr_say(sprintf("    %.2f (low)     n = %4d", shape_low, n_low))
  }
  jr_say(sprintf("    %.2f (assumed) n = %4d  \u2190 your input", shape,
                  min_n_fatigue(confidence, 0, p_eff)))
  if (!is.na(n_high)) {
    jr_say(sprintf("    %.2f (high)    n = %4d", shape_high, n_high))
  }
  jr_say("   -----------------------------------------------")
  jr_say(" ")
  jr_say("   Note:")
  jr_say("   The Weibull shape parameter (beta) is an assumed value.")
  jr_say("   The required sample size is sensitive to this assumption.")
  jr_say("   If beta is uncertain, use the value that gives the largest n")
  jr_say("   (most conservative result) or justify your assumed value with")
  jr_say("   prior test data or published literature for similar devices.")
  jr_say(" ")
} else {
  # At AF = 1 every unit is tested to exactly the target life, so
  # AF^beta = 1 and the sample size does not depend on beta.
  jr_say("   Note: at AF = 1 the sample size does not depend on the Weibull shape")
  jr_say("   parameter (AF^beta = 1); no beta sensitivity table is shown.")
  jr_say(" ")
}
jr_say("   In design verification, f = 0 (zero failures) is the usual")
jr_say("   acceptance criterion. f > 0 requires a pre-specified justification.")
jr_say(" ")
