#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_discrete.R <proportion> <confidence>
#
# "proportion"  is the minimum fraction of the population that must conform
#               to the specification (e.g. 0.99)
# "confidence"  is the statistical confidence level for that claim (e.g. 0.95)
#
# Needs only base R — no external libraries required.
#
# Computes the minimum sample size required for discrete (pass/fail) design
# verification, assuming a binomial process model. Results are shown for
# 0 to 10 allowed failures so the engineer can evaluate the full trade-off
# between sample size and acceptance criterion.
#
# The sample size is the exact binomial minimum: the smallest n for which f or
# fewer failures demonstrate the proportion at the given confidence,
#
#   pbinom(f, n, 1 - proportion) <= 1 - confidence
#   (equivalently 1 - qbeta(confidence, f + 1, n - f) >= proportion)
#
# the same Clopper-Pearson criterion jrc_ss_discrete_ci uses to evaluate a
# result. At f = 0 this is the classic zero-failure rule
#   n = ceiling( log(1 - confidence) / log(proportion) )
# Up to v1.0 the chi-squared (Poisson) approximation
#   n = ceiling( qchisq(confidence, 2f + 2) / (2 (1 - proportion)) )
# was used; it overestimates n by 0-3 (code review 2026-10, COR-18).
#
# Reference:
#   ASTM F3172-15 Standard Guide for Design Verification Device Size and
#   Sample Size Selection for Endovascular Devices
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

if (length(args) < 2) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_ss_discrete.R <proportion> <confidence>",
    "Example:",
    "  Rscript jrc_ss_discrete.R 0.99 0.95",
    sep = "\n"
  ))
}

proportion <- suppressWarnings(as.double(args[1]))
confidence <- suppressWarnings(as.double(args[2]))

if (is.na(proportion) || proportion <= 0 || proportion >= 1) {
  stop(paste("'proportion' must be a number strictly between 0 and 1. Got:", args[1]))
}
if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be a number strictly between 0 and 1. Got:", args[2]))
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Sample Size for Discrete (Pass/Fail) Design Verification")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ==========================================================")
jr_say(paste("   proportion (minimum conforming fraction):  ", proportion))
jr_say(paste("   confidence:                                ", confidence))
jr_say(" ")
jr_say("   Minimum sample sizes by number of allowed failures:")
jr_say(" ")
jr_say("   -----------------------------------------------")
jr_say("    failures (f)   min sample size (n)   note")
jr_say("   -----------------------------------------------")

for (f in 0:10) {
  n    <- jr_binom_min_n(proportion, confidence, f)
  note <- if (f == 0) "  ← recommended (zero-failure)" else
          if (f <= 2) "  ⚠  requires justification"    else
                      "  ⚠  requires strong justification"
  jr_say(sprintf("    f = %2d         n = %4d              %s", f, n, note))
}

jr_say("   -----------------------------------------------")
jr_say(" ")
jr_say("   Note:")
jr_say("   In design verification, f = 0 (zero failures) is the usual")
jr_say("   acceptance criterion. Allowing f > 0 failures requires a pre-specified")
jr_say("   statistical justification and an Acceptable Quality Level (AQL) rationale")
jr_say("   documented in the verification protocol before testing begins.")
jr_say(" ")
jr_say("   References:")
jr_say("   - ASTM F3172-15(2021), Standard Guide for Design Verification Device Size")
jr_say("     and Sample Size Selection for Endovascular Devices, ASTM International.")
jr_say("     FDA-recognized consensus standard.")
jr_say("   - NIST/SEMATECH e-Handbook of Statistical Methods, Section 7.2.4.1,")
jr_say("     Binomial confidence intervals (exact method):")
jr_say("     https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm")
jr_say(" ")
