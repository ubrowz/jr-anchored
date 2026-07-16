#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_dx_ss.R --method {precision|hypothesis}
#                 --sens-expected SE --spec-expected SP --prevalence P
#                 [--halfwidth W] [--sens-goal G0] [--spec-goal G1]
#                 [--power PW] [--alpha A] [--sides {1|2}]
#                 [--dropout d] [--sensitivity]
#
# Sample size for a DIAGNOSTIC ACCURACY study of a binary index test against
# a binary reference standard. Sensitivity is estimated only from
# reference-POSITIVE subjects and specificity only from reference-NEGATIVE
# subjects, so the binding constraint is whichever arm the prevalence makes
# scarcer. This script sizes both arms and reports the total enrolment that
# satisfies BOTH.
#
# --method        precision   size so the two-sided CI on sensitivity and on
#                             specificity is no wider than +/- --halfwidth
#                 hypothesis  size to reject a performance goal: H0 sens <=
#                             --sens-goal vs H1 sens = --sens-expected (and
#                             likewise for specificity), at --power
# --sens-expected anticipated sensitivity, in (0, 1). The planning value.
# --spec-expected anticipated specificity, in (0, 1). The planning value.
# --prevalence    prevalence of the condition in the intended-use population,
#                 in (0, 1); converts per-arm n into total enrolment
# --halfwidth     target CI half-width for --method precision, in (0, 0.5)
# --sens-goal     performance goal for sensitivity, for --method hypothesis;
#                 must be < --sens-expected
# --spec-goal     performance goal for specificity, for --method hypothesis;
#                 must be < --spec-expected
# --power         target power for --method hypothesis; default 0.80
# --alpha         significance level as passed by the design (see --sides);
#                 default 0.05
# --sides         1 or 2; z_alpha = qnorm(1 - alpha/sides). --method precision
#                 is inherently two-sided and always uses alpha/2 regardless.
#                 Performance-goal tests are conventionally 1-sided; default 1
#                 for --method hypothesis, 2 for --method precision.
# --dropout       expected fraction of subjects unevaluable (no valid
#                 reference or index result), in [0, 0.9); returns enrolled N
# --sensitivity   print an N-vs-prevalence scenario table (P x 0.5 ... 2.0)
#
# Needs only base R — no external libraries required.
#
# Formulas. With z_a = qnorm(1 - alpha/sides), z_b = qnorm(power):
#
#   precision (Buderer 1996), per arm:
#     n_pos = z_{1-alpha/2}^2 * SE(1-SE) / W^2      reference-positive needed
#     n_neg = z_{1-alpha/2}^2 * SP(1-SP) / W^2      reference-negative needed
#
#   hypothesis (one-sample binomial, normal approximation), per arm:
#     n_pos = (z_a*sqrt(G0(1-G0)) + z_b*sqrt(SE(1-SE)))^2 / (SE - G0)^2
#     n_neg = (z_a*sqrt(G1(1-G1)) + z_b*sqrt(SP(1-SP)))^2 / (SP - G1)^2
#
#   Total enrolment satisfying BOTH arms at prevalence P:
#     N = max( n_pos / P , n_neg / (1 - P) )
#   which is Buderer's step of dividing each arm's requirement by the fraction
#   of enrolees that lands in that arm, then taking the larger.
#
# References:
#   Buderer NM (1996), Statistical methodology: I. Incorporating the
#   prevalence of disease into the sample size calculation for sensitivity and
#   specificity, Acad Emerg Med 3:895-900. The prevalence-to-enrolment step.
#   Flahault A, Cadilhac M, Thomas G (2005), Sample size calculation should be
#   performed for design accuracy in diagnostic test studies, J Clin Epidemiol
#   58:859-862.
#   FDA (2007), Statistical Guidance on Reporting Results from Studies
#   Evaluating Diagnostic Tests, CDRH.
#
# Note: these are normal-approximation sizes. Near sens/spec of 0.95+, or for
# small n, the Wald half-width understates the exact (Clopper-Pearson)
# interval; confirm the final n against the exact interval actually planned
# for the report — jrc_clinical_dx_accuracy --ci exact reports that interval.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("❌ RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
platform_dir <- Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos")
lib_path <- file.path(renv_lib, "renv", "library", platform_dir, r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("❌ renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_dx_ss --method <precision|hypothesis>",
  "                     --sens-expected SE --spec-expected SP --prevalence P",
  "                     [--halfwidth W] [--sens-goal G0] [--spec-goal G1]",
  "                     [--power PW] [--alpha A] [--sides {1|2}]",
  "                     [--dropout d] [--sensitivity]",
  "Example (precision):",
  "  jrc_clinical_dx_ss --method precision --sens-expected 0.90 \\",
  "                     --spec-expected 0.95 --halfwidth 0.05 --prevalence 0.10",
  "Example (hypothesis):",
  "  jrc_clinical_dx_ss --method hypothesis --sens-expected 0.90 \\",
  "                     --spec-expected 0.95 --sens-goal 0.80 --spec-goal 0.90 \\",
  "                     --power 0.80 --alpha 0.025 --sides 1 --prevalence 0.10",
  sep = "\n"
)

method <- NULL; sens_exp <- NA; spec_exp <- NA; prevalence <- NA
halfwidth <- NA; sens_goal <- NA; spec_goal <- NA
power <- 0.80; alpha <- 0.05; sides <- NA; dropout <- 0
sensitivity <- FALSE

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0(flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--method" && i < length(args)) {
    method <- tolower(args[i + 1]); i <- i + 2
  } else if (a == "--sens-expected" && i < length(args)) {
    sens_exp <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--spec-expected" && i < length(args)) {
    spec_exp <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--prevalence" && i < length(args)) {
    prevalence <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--halfwidth" && i < length(args)) {
    halfwidth <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--sens-goal" && i < length(args)) {
    sens_goal <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--spec-goal" && i < length(args)) {
    spec_goal <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--power" && i < length(args)) {
    power <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--alpha" && i < length(args)) {
    alpha <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--sides" && i < length(args)) {
    sides <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--dropout" && i < length(args)) {
    dropout <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--sensitivity") {
    sensitivity <- TRUE; i <- i + 1
  } else {
    stop(paste0("Unknown argument: ", a, "\n", usage))
  }
}

methods <- c("precision", "hypothesis")
if (is.null(method) || !(method %in% methods)) {
  stop(paste("--method must be one of:", paste(methods, collapse = " | "),
             "\n", usage))
}

# --sides defaults by method: precision is two-sided; a performance-goal test
# is conventionally one-sided.
if (is.na(sides)) sides <- if (method == "precision") 2 else 1
if (!(sides %in% c(1, 2))) stop("--sides must be 1 or 2.")

if (is.na(sens_exp) || sens_exp <= 0 || sens_exp >= 1) {
  stop("--sens-expected must be strictly between 0 and 1 (e.g. 0.90).")
}
if (is.na(spec_exp) || spec_exp <= 0 || spec_exp >= 1) {
  stop("--spec-expected must be strictly between 0 and 1 (e.g. 0.95).")
}
if (is.na(prevalence) || prevalence <= 0 || prevalence >= 1) {
  stop("--prevalence must be strictly between 0 and 1 (e.g. 0.10).")
}
if (is.na(alpha) || alpha <= 0 || alpha >= 0.5) {
  stop("--alpha must be strictly between 0 and 0.5 (e.g. 0.05).")
}
if (is.na(dropout) || dropout < 0 || dropout >= 0.9) {
  stop("--dropout must be in [0, 0.9).")
}

if (method == "precision") {
  if (is.na(halfwidth) || halfwidth <= 0 || halfwidth >= 0.5) {
    stop("--method precision requires --halfwidth W in (0, 0.5), e.g. 0.05.")
  }
} else {
  if (is.na(power) || power <= 0 || power >= 1) {
    stop("--power must be strictly between 0 and 1 (e.g. 0.80).")
  }
  if (is.na(sens_goal) || sens_goal <= 0 || sens_goal >= 1) {
    stop("--method hypothesis requires --sens-goal G0 in (0, 1), e.g. 0.80.")
  }
  if (is.na(spec_goal) || spec_goal <= 0 || spec_goal >= 1) {
    stop("--method hypothesis requires --spec-goal G1 in (0, 1), e.g. 0.90.")
  }
  if (sens_goal >= sens_exp) {
    stop("--sens-goal must be strictly less than --sens-expected.")
  }
  if (spec_goal >= spec_exp) {
    stop("--spec-goal must be strictly less than --spec-expected.")
  }
}

# ---------------------------------------------------------------------------
# Sample size core
# ---------------------------------------------------------------------------

# Reference-positive subjects needed to characterise sensitivity, and
# reference-negative subjects needed to characterise specificity. Both are
# arm sizes — they do not yet account for prevalence.
arm_n <- function() {
  if (method == "precision") {
    z <- qnorm(1 - alpha / 2)      # a CI half-width is always two-sided
    c(pos = z^2 * sens_exp * (1 - sens_exp) / halfwidth^2,
      neg = z^2 * spec_exp * (1 - spec_exp) / halfwidth^2)
  } else {
    z_a <- qnorm(1 - alpha / sides)
    z_b <- qnorm(power)
    c(pos = (z_a * sqrt(sens_goal * (1 - sens_goal)) +
             z_b * sqrt(sens_exp  * (1 - sens_exp)))^2 / (sens_exp - sens_goal)^2,
      neg = (z_a * sqrt(spec_goal * (1 - spec_goal)) +
             z_b * sqrt(spec_exp  * (1 - spec_exp)))^2 / (spec_exp - spec_goal)^2)
  }
}

# Total enrolment at prevalence p that satisfies BOTH arms.
total_n <- function(p) {
  a <- arm_n()
  ceiling(max(a["pos"] / p, a["neg"] / (1 - p)))
}

enrolled <- function(n) ceiling(n / (1 - dropout))

a_raw   <- arm_n()
n_pos   <- ceiling(a_raw["pos"])
n_neg   <- ceiling(a_raw["neg"])
n_total <- total_n(prevalence)

# Which arm drives the total, and the split the total is expected to yield.
# Kept as raw expectations: the realised split is binomial, so N satisfies the
# arm requirements on average rather than with certainty.
drives  <- if (a_raw["pos"] / prevalence >= a_raw["neg"] / (1 - prevalence))
  "sensitivity (reference-positive)" else "specificity (reference-negative)"
exp_pos <- n_total * prevalence
exp_neg <- n_total * (1 - prevalence)

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

method_label <- c(precision  = "precision (target CI half-width)",
                  hypothesis = "hypothesis (vs performance goal)")[method]

message(" ")
message("✅ Clinical sample size — diagnostic accuracy study")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(sprintf("   Method         : %s", method_label))
if (method == "precision") {
  message(sprintf("   Alpha          : %g  (two-sided, z = %.4f)",
                  alpha, qnorm(1 - alpha / 2)))
  message(sprintf("   CI half-width  : +/- %g", halfwidth))
} else {
  message(sprintf("   Alpha / sides  : %g / %d-sided  (z = %.4f)",
                  alpha, as.integer(sides), qnorm(1 - alpha / sides)))
  message(sprintf("   Power          : %g", power))
  message(sprintf("   Goals          : sens > %g, spec > %g",
                  sens_goal, spec_goal))
}
message(sprintf("   Expected sens  : %g", sens_exp))
message(sprintf("   Expected spec  : %g", spec_exp))
message(sprintf("   Prevalence     : %g", prevalence))
message("   ------------------------------------------------------")
message(sprintf("   n reference +  : %d   (needed to characterise sensitivity)",
                n_pos))
message(sprintf("   n reference -  : %d   (needed to characterise specificity)",
                n_neg))
message(sprintf("   N TOTAL        : %d  (evaluable subjects to enrol)", n_total))
message(sprintf("   Binding arm    : %s", drives))
message(sprintf("   At prevalence %g, N yields %.1f reference + and %.1f",
                prevalence, exp_pos, exp_neg))
message("   reference - IN EXPECTATION. The realised split is binomial, so")
message("   the arm requirements are met on average, not guaranteed; the")
message("   totals follow Buderer and are not inflated for that variability.")
if (dropout > 0) {
  message(sprintf("   Dropout %g%%    → ENROLL %d subjects",
                  dropout * 100, enrolled(n_total)))
}

if (sensitivity) {
  message("   ------------------------------------------------------")
  message("   Sensitivity — evaluable N if the true prevalence differs:")
  message("      prevalence     N total")
  for (f in c(0.5, 0.75, 1.0, 1.5, 2.0)) {
    p <- prevalence * f
    if (p <= 0 || p >= 1) next
    message(sprintf("      %-11.4f    %d%s", p, total_n(p),
                    if (f == 1.0) "   <- assumed" else ""))
  }
  message("   Rarer conditions need disproportionately more enrolment: the")
  message("   reference-positive arm is what the prevalence starves.")
}

message("   ------------------------------------------------------")
if (method == "precision") {
  message("   Method: normal-approximation (Wald) half-width per arm,")
  message("   converted to enrolment by prevalence — Buderer (1996),")
  message("   Acad Emerg Med 3:895-900.")
  message("   For sens/spec near 0.95+ or small n, the Wald half-width")
  message("   understates the exact interval; confirm the planned n against")
  message("   the exact CI you will report (dx_accuracy --ci exact).")
} else {
  message("   Method: one-sample binomial test against a performance goal")
  message("   (normal approximation) per arm, converted to enrolment by")
  message("   prevalence — Buderer (1996), Acad Emerg Med 3:895-900.")
}
message("   Sizes both arms; the total satisfies whichever binds.")
message(" ")
