#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_ss_means.R --framework <fw> --power P --alpha A
#                 --sides {1|2} --sd SD [--delta D] [--margin M] [--ratio R]
#                 [--dropout d] [--sensitivity]
#
# Two-arm parallel-group sample size for a CONTINUOUS primary endpoint.
#
# --framework   superiority | non_inferiority | equivalence
# --power       target power, e.g. 0.80 or 0.90
# --alpha       significance level as passed by the design (see --sides)
# --sides       1 or 2; z_alpha = qnorm(1 - alpha/sides). The GUI passes
#               superiority → alpha 0.05, sides 2; non-inferiority →
#               alpha 0.025, sides 1; equivalence (TOST) → alpha 0.05, sides 1.
# --sd          expected common SD of the outcome (> 0)
# --delta       superiority: the clinically meaningful difference (≠ 0).
#               NI / equivalence: optional assumed TRUE difference
#               (treatment − control), default 0.
# --margin      non-inferiority / equivalence margin M (> 0)
# --ratio       allocation ratio k = n_treatment : n_control (default 1)
# --dropout     expected dropout fraction in [0, 0.9); returns enrolled N
# --sensitivity print an n-vs-SD scenario table (SD × 0.8 … 1.2)
#
# Needs only base R — no external libraries required.
#
# Formulas (normal approximation, per-group n for the CONTROL arm; the
# treatment arm is k × n_control; both rounded up):
#
#   superiority      n_c = (1 + 1/k) σ² (z_{1-α/sides} + z_{1-β})² / δ²
#   non-inferiority  n_c = (1 + 1/k) σ² (z_{1-α}       + z_{1-β})² / (δ + M)²
#   equivalence      n_c = (1 + 1/k) σ² (z_{1-α}       + z_{1-(1-power)/2})²
#                          / (M − |δ|)²
#
# Reference:
#   Chow, Shao & Wang (2008), Sample Size Calculations in Clinical Research,
#   2nd ed., Chapman & Hall/CRC, Chapter 3 (two-sample parallel design).
#   Note: the normal approximation can undershoot the t-based answer by ~1
#   subject per arm at small n; the report states the method explicitly.
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
  "  jrc_clinical_ss_means --framework <superiority|non_inferiority|equivalence>",
  "                        --power P --alpha A --sides {1|2} --sd SD",
  "                        [--delta D] [--margin M] [--ratio R]",
  "                        [--dropout d] [--sensitivity]",
  "Example (superiority):",
  "  jrc_clinical_ss_means --framework superiority --power 0.80 --alpha 0.05 \\",
  "                        --sides 2 --sd 10 --delta 5",
  sep = "\n"
)

framework <- NULL; power <- NA; alpha <- NA; sides <- NA
sd_val <- NA; delta <- 0; margin <- NA; ratio <- 1; dropout <- 0
sensitivity <- FALSE; delta_given <- FALSE

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
  } else if (a == "--sd" && i < length(args)) {
    sd_val <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--delta" && i < length(args)) {
    delta <- num_flag(args[i + 1], a); delta_given <- TRUE; i <- i + 2
  } else if (a == "--margin" && i < length(args)) {
    margin <- num_flag(args[i + 1], a); i <- i + 2
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

frameworks <- c("superiority", "non_inferiority", "equivalence")
if (is.null(framework) || !(framework %in% frameworks)) {
  stop(paste("--framework must be one of:",
             paste(frameworks, collapse = " | "), "\n", usage))
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
if (is.na(sd_val) || sd_val <= 0) {
  stop("--sd must be a positive number.")
}
if (is.na(ratio) || ratio <= 0) {
  stop("--ratio must be a positive number (treatment:control, e.g. 1 or 2).")
}
if (is.na(dropout) || dropout < 0 || dropout >= 0.9) {
  stop("--dropout must be in [0, 0.9).")
}
if (framework == "superiority") {
  if (!delta_given || delta == 0) {
    stop("superiority requires --delta, the clinically meaningful difference (non-zero).")
  }
} else {
  if (is.na(margin) || margin <= 0) {
    stop(paste0(framework, " requires --margin M > 0."))
  }
  if (framework == "non_inferiority" && (delta + margin) <= 0) {
    stop("non-inferiority needs delta + margin > 0 (true difference must not exceed the margin).")
  }
  if (framework == "equivalence" && abs(delta) >= margin) {
    stop("equivalence needs |delta| < margin (true difference inside the equivalence zone).")
  }
}

# ---------------------------------------------------------------------------
# Sample size core
# ---------------------------------------------------------------------------

# Per-group n (control arm) before rounding; treatment arm = ratio × control.
n_control_raw <- function(sd_use) {
  z_a <- qnorm(1 - alpha / sides)
  if (framework == "equivalence") {
    z_b  <- qnorm(1 - (1 - power) / 2)
    denom <- (margin - abs(delta))^2
  } else if (framework == "non_inferiority") {
    z_b  <- qnorm(power)
    denom <- (delta + margin)^2
  } else {
    z_b  <- qnorm(power)
    denom <- delta^2
  }
  (1 + 1 / ratio) * sd_use^2 * (z_a + z_b)^2 / denom
}

arm_sizes <- function(sd_use) {
  n_c <- ceiling(n_control_raw(sd_use))
  n_t <- ceiling(ratio * n_control_raw(sd_use))
  c(treat = n_t, control = n_c, total = n_t + n_c)
}

enrolled <- function(n) ceiling(n / (1 - dropout))

n <- arm_sizes(sd_val)

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

fw_label <- c(superiority     = "superiority",
              non_inferiority = "non-inferiority",
              equivalence     = "equivalence (TOST)")[framework]

message(" ")
message("✅ Clinical sample size — two-arm parallel, continuous endpoint (means)")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(sprintf("   Framework      : %s", fw_label))
message(sprintf("   Alpha / sides  : %g / %d-sided  (z = %.4f)",
                alpha, as.integer(sides), qnorm(1 - alpha / sides)))
message(sprintf("   Power          : %g", power))
message(sprintf("   SD (assumed)   : %g", sd_val))
if (framework == "superiority") {
  message(sprintf("   Delta          : %g  (clinically meaningful difference)", delta))
} else {
  message(sprintf("   Margin M       : %g", margin))
  message(sprintf("   True difference: %g  (assumed)", delta))
}
message(sprintf("   Allocation     : %g : 1  (treatment : control)", ratio))
message("   ------------------------------------------------------")
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
  message("   Sensitivity — evaluable total n if the true SD differs:")
  message("      SD        n treat   n control   n total")
  for (f in c(0.8, 0.9, 1.0, 1.1, 1.2)) {
    s  <- sd_val * f
    ns <- arm_sizes(s)
    message(sprintf("      %-9g %-9d %-11d %d%s",
                    s, ns["treat"], ns["control"], ns["total"],
                    if (f == 1.0) "   <- assumed" else ""))
  }
}

message("   ------------------------------------------------------")
message("   Method: normal-approximation two-sample formula,")
message("   Chow, Shao & Wang (2008), Sample Size Calculations in")
message("   Clinical Research, 2nd ed., Chapter 3. The approximation")
message("   can undershoot an exact t-based answer by ~1 subject/arm")
message("   at small n; round design decisions up, never down.")
message(" ")
