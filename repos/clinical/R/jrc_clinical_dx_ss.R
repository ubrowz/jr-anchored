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
# --power         target power for --method hypothesis; default 0.80. Each
#                 arm is sized at this power; the output also reports the
#                 joint power of meeting BOTH goals (product of the arm powers,
#                 independent arms), which is lower when both arms bind
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

jr_say(" ")
jr_say("✅ Clinical sample size — diagnostic accuracy study")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ======================================================")
jr_say(sprintf("   Method         : %s", method_label))
if (method == "precision") {
  jr_say(sprintf("   Alpha          : %g  (two-sided, z = %.4f)",
                  alpha, qnorm(1 - alpha / 2)))
  jr_say(sprintf("   CI half-width  : +/- %g", halfwidth))
} else {
  jr_say(sprintf("   Alpha / sides  : %g / %d-sided  (z = %.4f)",
                  alpha, as.integer(sides), qnorm(1 - alpha / sides)))
  jr_say(sprintf("   Power          : %g", power))
  jr_say(sprintf("   Goals          : sens > %g, spec > %g",
                  sens_goal, spec_goal))
}
jr_say(sprintf("   Expected sens  : %g", sens_exp))
jr_say(sprintf("   Expected spec  : %g", spec_exp))
jr_say(sprintf("   Prevalence     : %g", prevalence))
jr_say("   ------------------------------------------------------")
jr_say(sprintf("   n reference +  : %d   (needed to characterise sensitivity)",
                n_pos))
jr_say(sprintf("   n reference -  : %d   (needed to characterise specificity)",
                n_neg))
jr_say(sprintf("   N TOTAL        : %d  (evaluable subjects to enrol)", n_total))
jr_say(sprintf("   Binding arm    : %s", drives))
jr_say(sprintf("   At prevalence %g, N yields %.1f reference + and %.1f",
                prevalence, exp_pos, exp_neg))
jr_say("   reference - IN EXPECTATION. The realised split is binomial, so")
jr_say("   the arm requirements are met on average, not guaranteed; the")
jr_say("   totals follow Buderer and are not inflated for that variability.")
if (dropout > 0) {
  jr_say(sprintf("   Dropout %g%%    → ENROLL %d subjects",
                  dropout * 100, enrolled(n_total)))
}

if (sensitivity) {
  jr_say("   ------------------------------------------------------")
  jr_say("   Sensitivity — evaluable N if the true prevalence differs:")
  jr_say("      prevalence     N total")
  for (f in c(0.5, 0.75, 1.0, 1.5, 2.0)) {
    p <- prevalence * f
    if (p <= 0 || p >= 1) next
    jr_say(sprintf("      %-11.4f    %d%s", p, total_n(p),
                    if (f == 1.0) "   <- assumed" else ""))
  }
  jr_say("   Rarer conditions need disproportionately more enrolment: the")
  jr_say("   reference-positive arm is what the prevalence starves.")
}

jr_say("   ------------------------------------------------------")
if (method == "precision") {
  jr_say("   Method: normal-approximation (Wald) half-width per arm,")
  jr_say("   converted to enrolment by prevalence — Buderer (1996),")
  jr_say("   Acad Emerg Med 3:895-900.")
  jr_say("   For sens/spec near 0.95+ or small n, the Wald half-width")
  jr_say("   understates the exact interval; confirm the planned n against")
  jr_say("   the exact CI you will report (dx_accuracy --ci exact).")
} else {
  jr_say("   Method: one-sample binomial test against a performance goal")
  jr_say("   (normal approximation) per arm, converted to enrolment by")
  jr_say("   prevalence — Buderer (1996), Acad Emerg Med 3:895-900.")
  # Co-primary goals (code review 2026-10, CLN-01): each arm is sized at
  # --power, but a study that needs BOTH goals met succeeds with the product
  # of the arm powers (independent arms: different subjects).
  arm_power <- function(n, g, e) {
    z_a <- qnorm(1 - alpha / sides)
    pnorm((abs(e - g) * sqrt(n) - z_a * sqrt(g * (1 - g))) / sqrt(e * (1 - e)))
  }
  pw_sens  <- arm_power(exp_pos, sens_goal, sens_exp)
  pw_spec  <- arm_power(exp_neg, spec_goal, spec_exp)
  pw_joint <- pw_sens * pw_spec
  jr_say("   ------------------------------------------------------")
  jr_say(sprintf("   Power at N (expected arm sizes): sens %.3f, spec %.3f", pw_sens, pw_spec))
  jr_say(sprintf("   Joint power (BOTH goals met)   : %.3f", pw_joint))
  if (pw_joint < power) {
    jr_say(sprintf("   \u26a0\ufe0f  If both goals are co-primary (the study succeeds only when"))
    jr_say(sprintf("   both are met), the joint power is below the target %g. To", power))
    jr_say(sprintf("   reach it, size each arm at --power %.4f (= sqrt(%g)).", sqrt(power), power))
  }
}
jr_say("   Sizes both arms; the total satisfies whichever binds.")
jr_say(" ")
