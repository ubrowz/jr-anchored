#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_attr_ci.R <confidence> <file_path> <column_name> <spec1> <spec2>
#
# "confidence"  is the confidence level at which to evaluate the tolerance
#               interval (e.g. 0.95). In medical device verification, 0.95 is
#               the accepted standard.
# "file_path"   should point to a csv file with column names as the first row
# "column_name" should be one of the column names in the csv file
#               (NOT the name of the first column, which is used for row names)
# "spec1"       lower spec limit, or "-" if not applicable
# "spec2"       upper spec limit, or "-" if not applicable
#
# At least one of spec1 / spec2 must be numeric. Pass "-" for the one that
# does not apply:
#   1-sided lower:  spec1 = <value>  spec2 = -
#   1-sided upper:  spec1 = -        spec2 = <value>
#   2-sided:        spec1 = <value>  spec2 = <value>  (spec2 must be > spec1)
#
# IMPORTANT! The CSV file must have at least 2 columns: the first column is
# used for row names, the remaining columns contain data.
#
# Needs the <stats>, <tolerance>, <MASS> and <e1071> libraries.
#
# Given a fixed confidence level and a verification dataset, determines the
# proportion of the population that the data demonstrate conforms to the
# specification (the largest P whose tolerance interval still lies within the
# spec). At that P the interval bound coincides with the spec limit, so the
# achieved proportion is the result to compare with the protocol requirement.
#
# This is the reporting companion to jrc_ss_attr and jrc_ss_attr_check:
#   jrc_ss_attr        — what minimum N do I need?
#   jrc_ss_attr_check  — does my planned N meet the requirement?
#   jrc_ss_attr_ci     — given my test result, what proportion did I achieve?
#
# The proportion is found by bisection: for fixed N and confidence, k_factor()
# is monotonically decreasing in proportion, so the proportion at which
# k_factor(N, p, confidence) == k_sample is located precisely in ~50 iterations.
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

suppressPackageStartupMessages({
  library(tolerance)
  library(MASS)
  library(e1071)
})

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BISECT_TOL    <- 1e-8   # Convergence tolerance for proportion search
BISECT_ITER   <- 100    # Maximum bisection iterations

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 5) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_ss_attr_ci.R <confidence> <file_path> <column_name> <spec1> <spec2>",
    "Example (1-sided lower):",
    "  Rscript jrc_ss_attr_ci.R 0.95 mydata.csv ForceN 8.0 -",
    "Example (1-sided upper):",
    "  Rscript jrc_ss_attr_ci.R 0.95 mydata.csv ForceN - 12.0",
    "Example (2-sided):",
    "  Rscript jrc_ss_attr_ci.R 0.95 mydata.csv ForceN 8.0 12.0",
    sep = "\n"
  ))
}

confidence <- suppressWarnings(as.double(args[1]))
file_path  <- args[2]
input_col  <- args[3]
col        <- make.names(input_col)

if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be a number strictly between 0 and 1. Got:", args[1]))
}
if (!file.exists(file_path)) {
  stop(paste("File not found:", file_path))
}

spec1_raw <- suppressWarnings(as.double(args[4]))
spec2_raw <- suppressWarnings(as.double(args[5]))

has_spec1 <- !is.na(spec1_raw)
has_spec2 <- !is.na(spec2_raw)

if (!has_spec1 && !has_spec2) {
  stop("Both spec1 and spec2 are '-'. At least one numeric spec limit must be provided.")
}
if (args[4] != "-" && !has_spec1) {
  stop(paste("'spec1' must be a numeric value or '-'. Got:", args[4]))
}
if (args[5] != "-" && !has_spec2) {
  stop(paste("'spec2' must be a numeric value or '-'. Got:", args[5]))
}
if (has_spec1 && has_spec2 && spec2_raw <= spec1_raw) {
  stop(paste("'spec2' must be greater than 'spec1'. Got spec1 =", spec1_raw,
             "and spec2 =", spec2_raw))
}

two_sided  <- has_spec1 && has_spec2
lower_only <- has_spec1 && !has_spec2
upper_only <- !has_spec1 && has_spec2

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

mydata <- tryCatch(
  read.table(file_path, header = TRUE, sep = ",", dec = ".", row.names = 1),
  error = function(e) stop(paste("Failed to read CSV file:", e$message))
)

if (ncol(mydata) < 1) {
  stop(paste(
    "The CSV file must have at least 2 columns: one for row names and at",
    "least one data column. The file appears to have only 1 column."
  ))
}

if (!col %in% names(mydata)) {
  stop(paste0(
    "Column '", col, "' not found in file. ",
    "Available columns: ", paste(names(mydata), collapse = ", ")
  ))
}

x_raw <- mydata[[col]]

n_bad <- sum(!is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed from column before analysis."))
}
x <- x_raw[is.finite(x_raw)]

if (length(x) < 3) {
  stop(paste(
    "Fewer than 3 valid (finite) observations remain after removing NA/Inf.",
    "Cannot estimate process parameters."
  ))
}

N <- length(x)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

#' Find the maximum proportion p such that k_factor(N, p, confidence) <= k_sample.
#' Uses bisection on p in (0, 1). k_factor is monotonically increasing in p,
#' so the crossing point is unique and well-defined.
find_proportion <- function(N, confidence, k_sample, side = 1) {
  k_fn <- function(N, p, c) jr_kfactor(N, p, c, side)

  # Mean at or beyond the spec (signed k <= 0): nothing can be demonstrated.
  if (k_sample <= 0) return(NA)

  # Guard: if even p -> 0 gives k_factor > k_sample, the data cannot support
  # any meaningful proportion claim.
  if (k_fn(N, 0.001, confidence) > k_sample) return(NA)

  # Guard: if p -> 1 gives k_factor <= k_sample, proportion is effectively 1.
  if (k_fn(N, 0.9999, confidence) <= k_sample) return(0.9999)

  lo <- 0.001
  hi <- 0.9999
  for (i in seq_len(BISECT_ITER)) {
    mid  <- (lo + hi) / 2
    k_mid <- k_fn(N, mid, confidence)
    if (k_mid <= k_sample) {
      lo <- mid
    } else {
      hi <- mid
    }
    if ((hi - lo) < BISECT_TOL) break
  }
  (lo + hi) / 2
}

# ---------------------------------------------------------------------------
# Main — header
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Attribute Tolerance Interval — Proportion Achieved")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   =====================================================")
jr_say(paste("   confidence:                    ", confidence))
jr_say(paste("   file:                          ", file_path))
jr_say(paste("   column:                        ", input_col))
jr_say(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
jr_say(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
jr_say(paste("   sample size (N):               ", N))
jr_say(" ")

# ---------------------------------------------------------------------------
# Transformation
# ---------------------------------------------------------------------------

result <- jr_auto_transform_normal(x, alpha = JR_BOXCOX_ALPHA)

if (result$transformation == "none") {
  jr_say(" ")
  jr_say("❌ Could not evaluate tolerance interval: data are not normally distributed")
  jr_say("   and Box-Cox transformation did not achieve sufficient normality.")
  jr_say(" ")
  jr_say("   Suggestions:")
  jr_say("     - If data are heavily rounded, try using more decimal places.")
  jr_say("     - Plot your data and inspect for multimodality or outliers.")
  jr_say("     - Consider whether the process may have shifted over time.")
  jr_say("     - A non-parametric tolerance interval may be appropriate.")
  quit(save = "no", status = 1)
}

X     <- mean(result$transformed)
sigma <- sd(result$transformed)
lam   <- result$lambda

jr_say(paste("   transformation applied:        ", result$transformation))
jr_say(" ")

# ---------------------------------------------------------------------------
# Proportion search
#
# The result is the proportion P at which the K-factor for N and the
# confidence level equals the sample k-factor. At that P the tolerance
# interval bound coincides with the spec limit by construction, so no bound
# is reported separately: the achieved proportion IS the result.
# ---------------------------------------------------------------------------

report_proportion <- function(ks, proportion, where) {
  jr_say(" ")
  if (ks <= 0) {
    jr_say("\u274c Result:")
    jr_say(paste("   k-factor from sample:                  ", round(ks, 4)))
    jr_say(paste0("   The sample mean is ", where, " (k <= 0)."))
    jr_say("   No conforming proportion can be demonstrated at this confidence.")
  } else if (is.na(proportion)) {
    jr_say("\u274c Result:")
    jr_say(paste("   k-factor from sample:                  ", round(ks, 4)))
    jr_say("   The sample k-factor is too low to support any meaningful proportion claim.")
    jr_say("   The dataset does not demonstrate conformance to the spec at this confidence.")
  } else {
    jr_say("\u2705 Result:")
    jr_say(paste("   k-factor from sample:                  ", round(ks, 4)))
    jr_say(paste("   proportion achieved at", confidence, "confidence: ", round(proportion, 4)))
    jr_say("   (at this proportion the tolerance interval bound coincides with the")
    jr_say("    spec limit; compare it with the proportion required by your protocol)")
  }
}

if (lower_only) {

  jr_say("   Mode: 1-sided (lower) tolerance interval")
  spec1_t    <- if (result$transformation != "normal") jr_boxcox_transform(spec1_raw, lam) else spec1_raw
  ks         <- jr_ksample_one_side(X, sigma, spec1_t, "lower")
  proportion <- find_proportion(N, confidence, ks, side = 1)
  report_proportion(ks, proportion, "at or below the lower spec limit")

} else if (upper_only) {

  jr_say("   Mode: 1-sided (upper) tolerance interval")
  spec2_t    <- if (result$transformation != "normal") jr_boxcox_transform(spec2_raw, lam) else spec2_raw
  ks         <- jr_ksample_one_side(X, sigma, spec2_t, "upper")
  proportion <- find_proportion(N, confidence, ks, side = 1)
  report_proportion(ks, proportion, "at or above the upper spec limit")

} else {

  jr_say("   Mode: 2-sided tolerance interval")
  spec1_t    <- if (result$transformation != "normal") jr_boxcox_transform(spec1_raw, lam) else spec1_raw
  spec2_t    <- if (result$transformation != "normal") jr_boxcox_transform(spec2_raw, lam) else spec2_raw
  ks         <- jr_ksample_two_side(X, sigma, spec1_t, spec2_t)
  proportion <- find_proportion(N, confidence, ks, side = 2)
  report_proportion(ks, proportion, "at or outside the specification window")

}

jr_say(" ")
