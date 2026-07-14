#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_ss_props.R --framework <fw> --power P --alpha A
#                 --sides {1|2} --p-control PC [--p-treat PT] [--margin M]
#                 [--ratio R] [--dropout d] [--sensitivity]
#
# Two-arm parallel-group sample size for a BINARY primary endpoint
# (success/failure), effect expressed as a RISK DIFFERENCE.
#
# --framework   superiority | non_inferiority | equivalence
# --power       target power, e.g. 0.80 or 0.90
# --alpha       significance level as passed by the design (see --sides)
# --sides       1 or 2; z_alpha = qnorm(1 - alpha/sides). The GUI passes
#               superiority → alpha 0.05, sides 2; non-inferiority →
#               alpha 0.025, sides 1; equivalence (TOST) → alpha 0.05, sides 1.
# --p-control   control-arm event (success) rate, in (0, 1)
# --p-treat     expected treatment-arm rate. REQUIRED for superiority;
#               optional for NI / equivalence (default: equal to control)
# --margin      non-inferiority / equivalence margin on the risk difference (> 0)
# --ratio       allocation ratio k = n_treatment : n_control (default 1)
# --dropout     expected dropout fraction in [0, 0.9); returns enrolled N
# --sensitivity print an n-vs-p_control scenario table (PC × 0.8 … 1.2)
#
# Needs only base R — no external libraries required.
#
# Formulas (normal approximation, unpooled variance; per-group n for the
# CONTROL arm, treatment arm = k × n_control, both rounded up), with
# V = p_t(1−p_t)/k + p_c(1−p_c) and d = p_t − p_c:
#
#   superiority      n_c = V (z_{1-α/sides} + z_{1-β})² / d²
#   non-inferiority  n_c = V (z_{1-α}       + z_{1-β})² / (d + M)²
#   equivalence      n_c = V (z_{1-α} + z_{1-(1-power)/2})² / (M − |d|)²
#
# Reference:
#   Chow, Shao & Wang (2008), Sample Size Calculations in Clinical Research,
#   2nd ed., Chapman & Hall/CRC, Chapter 4 (two-sample parallel design).
#   Note: R's power.prop.test uses a pooled-variance variant and will differ
#   slightly; the unpooled form here is the one tabulated in Chow et al.
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
  "  jrc_clinical_ss_props --framework <superiority|non_inferiority|equivalence>",
  "                        --power P --alpha A --sides {1|2} --p-control PC",
  "                        [--p-treat PT] [--margin M] [--ratio R]",
  "                        [--dropout d] [--sensitivity]",
  "Example (non-inferiority):",
  "  jrc_clinical_ss_props --framework non_inferiority --power 0.80 --alpha 0.025 \\",
  "                        --sides 1 --p-control 0.85 --margin 0.10",
  sep = "\n"
)

framework <- NULL; power <- NA; alpha <- NA; sides <- NA
p_control <- NA; p_treat <- NA; margin <- NA; ratio <- 1; dropout <- 0
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
  } else if (a == "--p-control" && i < length(args)) {
    p_control <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--p-treat" && i < length(args)) {
    p_treat <- num_flag(args[i + 1], a); i <- i + 2
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
if (is.na(p_control) || p_control <= 0 || p_control >= 1) {
  stop("--p-control must be strictly between 0 and 1 (e.g. 0.85).")
}
if (is.na(ratio) || ratio <= 0) {
  stop("--ratio must be a positive number (treatment:control, e.g. 1 or 2).")
}
if (is.na(dropout) || dropout < 0 || dropout >= 0.9) {
  stop("--dropout must be in [0, 0.9).")
}
p_treat_defaulted <- FALSE
if (framework == "superiority") {
  if (is.na(p_treat)) {
    stop("superiority requires --p-treat, the expected treatment-arm rate.")
  }
  if (p_treat <= 0 || p_treat >= 1) {
    stop("--p-treat must be strictly between 0 and 1.")
  }
  if (p_treat == p_control) {
    stop("superiority requires p-treat different from p-control.")
  }
} else {
  if (is.na(p_treat)) {
    p_treat <- p_control          # default: same true rate in both arms
    p_treat_defaulted <- TRUE
  }
  if (p_treat <= 0 || p_treat >= 1) {
    stop("--p-treat must be strictly between 0 and 1.")
  }
  if (is.na(margin) || margin <= 0) {
    stop(paste0(framework, " requires --margin M > 0 (risk difference)."))
  }
  d0 <- p_treat - p_control
  if (framework == "non_inferiority" && (d0 + margin) <= 0) {
    stop("non-inferiority needs (p-treat − p-control) + margin > 0.")
  }
  if (framework == "equivalence" && abs(d0) >= margin) {
    stop("equivalence needs |p-treat − p-control| < margin.")
  }
}

# ---------------------------------------------------------------------------
# Sample size core
# ---------------------------------------------------------------------------

# Per-group n (control arm) before rounding, at control rate pc_use. When the
# treatment rate was defaulted to "equal to control", it tracks pc_use in the
# sensitivity scan; an explicitly given p_treat stays fixed.
n_control_raw <- function(pc_use) {
  z_a    <- qnorm(1 - alpha / sides)
  pt_use <- if (p_treat_defaulted) pc_use else p_treat
  v      <- pt_use * (1 - pt_use) / ratio + pc_use * (1 - pc_use)
  d      <- pt_use - pc_use
  if (framework == "equivalence") {
    z_b   <- qnorm(1 - (1 - power) / 2)
    denom <- (margin - abs(d))^2
  } else if (framework == "non_inferiority") {
    z_b   <- qnorm(power)
    denom <- (d + margin)^2
  } else {
    z_b   <- qnorm(power)
    denom <- d^2
  }
  v * (z_a + z_b)^2 / denom
}

arm_sizes <- function(pc_use) {
  n_c <- ceiling(n_control_raw(pc_use))
  n_t <- ceiling(ratio * n_control_raw(pc_use))
  c(treat = n_t, control = n_c, total = n_t + n_c)
}

enrolled <- function(n) ceiling(n / (1 - dropout))

n <- arm_sizes(p_control)

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

fw_label <- c(superiority     = "superiority",
              non_inferiority = "non-inferiority",
              equivalence     = "equivalence (TOST)")[framework]

message(" ")
message("✅ Clinical sample size — two-arm parallel, binary endpoint (proportions)")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(sprintf("   Framework      : %s", fw_label))
message(sprintf("   Alpha / sides  : %g / %d-sided  (z = %.4f)",
                alpha, as.integer(sides), qnorm(1 - alpha / sides)))
message(sprintf("   Power          : %g", power))
message(sprintf("   p control      : %g", p_control))
message(sprintf("   p treatment    : %g%s", p_treat,
                if (p_treat_defaulted) "  (assumed equal to control)" else ""))
if (framework != "superiority") {
  message(sprintf("   Margin M       : %g  (risk difference)", margin))
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
  message("   Sensitivity — evaluable total n if the true control rate differs:")
  message("      p control   n treat   n control   n total")
  for (f in c(0.8, 0.9, 1.0, 1.1, 1.2)) {
    pc <- p_control * f
    if (pc <= 0 || pc >= 1) next
    ns <- arm_sizes(pc)
    message(sprintf("      %-11.3f %-9d %-11d %d%s",
                    pc, ns["treat"], ns["control"], ns["total"],
                    if (f == 1.0) "   <- assumed" else ""))
  }
}

message("   ------------------------------------------------------")
message("   Method: normal-approximation (unpooled variance) risk-")
message("   difference formula, Chow, Shao & Wang (2008), Sample Size")
message("   Calculations in Clinical Research, 2nd ed., Chapter 4.")
message("   For rates near 0 or 1, or very small n, consider an exact")
message("   (e.g. Farrington-Manning / exact binomial) confirmation.")
message(" ")
