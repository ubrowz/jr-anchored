#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_ss_survival.R --framework <fw> --power P
#                 --alpha A --sides {1|2} --hr HR --event-prob PE [--margin M]
#                 [--ratio R] [--dropout d] [--sensitivity]
#
# Two-arm parallel-group sample size for a TIME-TO-EVENT primary endpoint
# (log-rank test), effect expressed as a HAZARD RATIO. Computes the required
# number of EVENTS (Schoenfeld) and converts to subjects via the expected
# event probability over follow-up.
#
# --framework   superiority | non_inferiority   (no equivalence for survival)
# --power       target power, e.g. 0.80 or 0.90
# --alpha       significance level as passed by the design (see --sides)
# --sides       1 or 2; z_alpha = qnorm(1 - alpha/sides). The GUI passes
#               superiority → alpha 0.05, sides 2; non-inferiority →
#               alpha 0.025, sides 1.
# --hr          hazard ratio treatment vs control. Superiority: the target
#               effect (≠ 1). Non-inferiority: the assumed TRUE hazard ratio
#               (often 1.0 — treatments truly equal).
# --margin      non-inferiority margin on the hazard ratio (> 1, and > --hr)
# --event-prob  overall probability a randomized subject has an event during
#               follow-up, in (0, 1]; converts required events → subjects
# --ratio       allocation ratio k = n_treatment : n_control (default 1)
# --dropout     expected dropout fraction in [0, 0.9); returns enrolled N.
#               Keep it distinct from censoring already reflected in
#               --event-prob — do not double-count.
# --sensitivity print an n-vs-event-prob scenario table (PE × 0.8 … 1.2)
#
# Needs only base R — no external libraries required.
#
# Formulas (Schoenfeld; total required events E with allocation k):
#
#   superiority      E = (1 + k)²/k × (z_{1-α/sides} + z_{1-β})² / (log HR)²
#   non-inferiority  E = (1 + k)²/k × (z_{1-α} + z_{1-β})² /
#                        (log(margin) − log(HR))²
#
#   Subjects: N_total = E / event_prob, split k:1 and rounded up per arm.
#
# References:
#   Schoenfeld (1983), Sample-size formula for the proportional-hazards
#   regression model, Biometrics 39, 499-503.
#   Chow, Shao & Wang (2008), Sample Size Calculations in Clinical Research,
#   2nd ed., Chapman & Hall/CRC, Chapter 7 (comparing time-to-event data).
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
  "  jrc_clinical_ss_survival --framework <superiority|non_inferiority>",
  "                           --power P --alpha A --sides {1|2}",
  "                           --hr HR --event-prob PE [--margin M]",
  "                           [--ratio R] [--dropout d] [--sensitivity]",
  "Example (superiority):",
  "  jrc_clinical_ss_survival --framework superiority --power 0.80 --alpha 0.05 \\",
  "                           --sides 2 --hr 0.70 --event-prob 0.6",
  sep = "\n"
)

framework <- NULL; power <- NA; alpha <- NA; sides <- NA
hr <- NA; margin <- NA; event_prob <- NA; ratio <- 1; dropout <- 0
sensitivity <- FALSE

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0(flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--framework" && i < length(args)) {
    framework <- args[i + 1]; i <- i + 2
  } else if (a == "--power" && i < length(args)) {
    power <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--alpha" && i < length(args)) {
    alpha <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--sides" && i < length(args)) {
    sides <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--hr" && i < length(args)) {
    hr <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--margin" && i < length(args)) {
    margin <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--event-prob" && i < length(args)) {
    event_prob <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--ratio" && i < length(args)) {
    ratio <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--dropout" && i < length(args)) {
    dropout <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--sensitivity") {
    sensitivity <- TRUE; i <- i + 1
  } else {
    stop(paste0("Unknown argument: ", a, "\n", usage))
  }
}

frameworks <- c("superiority", "non_inferiority")
if (is.null(framework) || !(framework %in% frameworks)) {
  stop(paste("--framework must be one of:",
             paste(frameworks, collapse = " | "),
             "(equivalence is not offered for time-to-event endpoints)\n", usage))
}
if (is.na(power) || power <= 0 || power >= 1) {
  stop("--power must be strictly between 0 and 1 (e.g. 0.80).")
}
if (is.na(alpha) || alpha <= 0 || alpha >= 0.5) {
  stop("--alpha must be strictly between 0 and 0.5 (e.g. 0.05).")
}
if (is.na(sides) || !(sides %in% c(1, 2))) {
  stop("--sides must be 1 or 2.")
}
if (is.na(hr) || hr <= 0) {
  stop("--hr must be a positive number (hazard ratio treatment vs control).")
}
if (is.na(event_prob) || event_prob <= 0 || event_prob > 1) {
  stop("--event-prob must be in (0, 1].")
}
if (is.na(ratio) || ratio <= 0) {
  stop("--ratio must be a positive number (treatment:control, e.g. 1 or 2).")
}
if (is.na(dropout) || dropout < 0 || dropout >= 0.9) {
  stop("--dropout must be in [0, 0.9).")
}
if (framework == "superiority") {
  if (hr == 1) {
    stop("superiority requires --hr different from 1 (a real target effect).")
  }
} else {
  if (is.na(margin) || margin <= 1) {
    stop("non-inferiority requires --margin M > 1 (margin on the hazard ratio).")
  }
  if (hr >= margin) {
    stop("non-inferiority needs --hr < --margin (assumed true HR inside the margin).")
  }
}

# ---------------------------------------------------------------------------
# Sample size core — Schoenfeld events, then subjects via event probability
# ---------------------------------------------------------------------------

events_required <- function() {
  z_a <- qnorm(1 - alpha / sides)
  z_b <- qnorm(power)
  log_eff <- if (framework == "non_inferiority") {
    log(margin) - log(hr)
  } else {
    log(hr)
  }
  ((1 + ratio)^2 / ratio) * (z_a + z_b)^2 / log_eff^2
}

arm_sizes <- function(pe_use) {
  n_total_raw <- events_required() / pe_use
  n_c <- ceiling(n_total_raw / (1 + ratio))
  n_t <- ceiling(ratio * n_total_raw / (1 + ratio))
  c(treat = n_t, control = n_c, total = n_t + n_c)
}

enrolled <- function(n) ceiling(n / (1 - dropout))

ev <- ceiling(events_required())
n  <- arm_sizes(event_prob)

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

fw_label <- c(superiority     = "superiority",
              non_inferiority = "non-inferiority")[framework]

message(" ")
message("✅ Clinical sample size — two-arm parallel, time-to-event endpoint (log-rank)")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(sprintf("   Framework      : %s", fw_label))
message(sprintf("   Alpha / sides  : %g / %d-sided  (z = %.4f)",
                alpha, as.integer(sides), qnorm(1 - alpha / sides)))
message(sprintf("   Power          : %g", power))
if (framework == "non_inferiority") {
  message(sprintf("   True HR        : %g  (assumed)", hr))
  message(sprintf("   Margin M       : %g  (on the hazard ratio)", margin))
} else {
  message(sprintf("   Hazard ratio   : %g  (target effect)", hr))
}
message(sprintf("   P(event)       : %g  (over follow-up)", event_prob))
message(sprintf("   Allocation     : %g : 1  (treatment : control)", ratio))
message("   ------------------------------------------------------")
message(sprintf("   Events required: %d  (drives the power)", ev))
message(sprintf("   n treatment    : %d", n["treat"]))
message(sprintf("   n control      : %d", n["control"]))
message(sprintf("   n TOTAL        : %d  (evaluable subjects)", n["total"]))
if (dropout > 0) {
  e_t <- enrolled(n["treat"]); e_c <- enrolled(n["control"])
  message(sprintf("   Dropout %g%%    → ENROLL %d + %d = %d",
                  dropout * 100, e_t, e_c, e_t + e_c))
}

if (sensitivity) {
  message("   ------------------------------------------------------")
  message("   Sensitivity — evaluable total n if the true event probability differs:")
  message("      P(event)   n treat   n control   n total")
  for (f in c(0.8, 0.9, 1.0, 1.1, 1.2)) {
    pe <- event_prob * f
    if (pe <= 0 || pe > 1) next
    ns <- arm_sizes(pe)
    message(sprintf("      %-10.3f %-9d %-11d %d%s",
                    pe, ns["treat"], ns["control"], ns["total"],
                    if (f == 1.0) "   <- assumed" else ""))
  }
}

message("   ------------------------------------------------------")
message("   Method: Schoenfeld (1983) events formula for the log-rank /")
message("   proportional-hazards test; subjects = events / P(event).")
message("   See also Chow, Shao & Wang (2008), Chapter 7. The follow-up")
message("   time, accrual pattern and censoring are summarized entirely")
message("   by --event-prob; validate it against the expected accrual.")
message(" ")
