#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_attr_check.R <proportion> <confidence> <file_path> <column_name> <spec1> <spec2> <planned_N>
#
# "proportion"  is the minimum fraction of the population that must be within
#               the tolerance interval (e.g. 0.95)
# "confidence"  is the confidence level for that claim (e.g. 0.95)
# "file_path"   should point to a csv file with column names as the first row
# "column_name" should be one of the column names in the csv file
#               (NOT the name of the first column, which is used for row names)
# "spec1"       lower spec limit, or "-" if not applicable
# "spec2"       upper spec limit, or "-" if not applicable
# "planned_N"   the sample size you plan to use for verification (positive integer)
#
# At least one of spec1 / spec2 must be numeric. Pass "-" for the one that
# does not apply:
#   1-sided lower:  spec1 = <value>  spec2 = -
#   1-sided upper:  spec1 = -        spec2 = <value>
#   2-sided:        spec1 = <value>  spec2 = <value>  (spec2 must be > spec1)
#
# IMPORTANT! It is assumed that the first column in the csv file is used for
# row names.
#
# Needs the <stats>, <tolerance>, <MASS> and <e1071> libraries.
#
# Checks whether a planned sample size meets the statistical tolerance interval
# requirement for attribute (continuous measurement) design verification, based
# on a pilot data set. Non-normal data are handled via Box-Cox transformation.
#
# Use this script first to validate your planned N quickly. If it fails, run
# jrc_ss_attr.R to find the true minimum sample size.
#
# Author: Joep Rous
# Version: 1.0

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("❌ RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("❌ renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

suppressPackageStartupMessages({
  library(tolerance)
  library(stats)
  library(MASS)   # For boxcox()
  library(e1071)  # For skewness()
})

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BOXCOX_ALPHA <- 0.01
LAMBDA_EPS   <- 1e-6

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 7) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_ss_attr_check.R <proportion> <confidence> <file_path> <column_name> <spec1> <spec2> <planned_N>",
    "Example (1-sided lower):",
    "  Rscript jrc_ss_attr_check.R 0.95 0.95 mydata.csv ForceN 8.0 - 30",
    "Example (1-sided upper):",
    "  Rscript jrc_ss_attr_check.R 0.95 0.95 mydata.csv ForceN - 12.0 30",
    "Example (2-sided):",
    "  Rscript jrc_ss_attr_check.R 0.95 0.95 mydata.csv ForceN 8.0 12.0 30",
    sep = "\n"
  ))
}

proportion <- suppressWarnings(as.double(args[1]))
confidence <- suppressWarnings(as.double(args[2]))
file_path  <- args[3]
input_col  <- args[4]
col        <- make.names(input_col)

if (is.na(proportion) || proportion <= 0 || proportion >= 1) {
  stop(paste("'proportion' must be a number strictly between 0 and 1. Got:", args[1]))
}
if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be a number strictly between 0 and 1. Got:", args[2]))
}
if (!file.exists(file_path)) {
  stop(paste("File not found:", file_path))
}

spec1_raw <- suppressWarnings(as.double(args[5]))
spec2_raw <- suppressWarnings(as.double(args[6]))

has_spec1 <- !is.na(spec1_raw)
has_spec2 <- !is.na(spec2_raw)

if (!has_spec1 && !has_spec2) {
  stop("Both spec1 and spec2 are '-'. At least one numeric spec limit must be provided.")
}
if (args[5] != "-" && !has_spec1) {
  stop(paste("'spec1' must be a numeric value or '-'. Got:", args[5]))
}
if (args[6] != "-" && !has_spec2) {
  stop(paste("'spec2' must be a numeric value or '-'. Got:", args[6]))
}
if (has_spec1 && has_spec2 && spec2_raw <= spec1_raw) {
  stop(paste("'spec2' must be greater than 'spec1'. Got spec1 =", spec1_raw,
             "and spec2 =", spec2_raw))
}

planned_N <- suppressWarnings(as.integer(args[7]))
if (is.na(planned_N) || planned_N < 2) {
  stop(paste("'planned_N' must be an integer >= 2. Got:", args[7]))
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

n_bad <- sum(is.na(x_raw) | !is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed from column before analysis."))
}
x <- x_raw[is.finite(x_raw) & !is.na(x_raw)]

if (length(x) < 3) {
  stop(paste(
    "Fewer than 3 valid (finite) observations remain after removing NA/Inf.",
    "Cannot estimate process parameters."
  ))
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

boxcox_transform <- function(val, lambda) {
  if (abs(lambda) < LAMBDA_EPS) log(val) else (val^lambda - 1) / lambda
}

k_factor_one_side <- function(N, p, c) {
  K.factor(N, f = NULL, alpha = (1 - as.double(c)), P = as.double(p),
           side = 1, method = "EXACT", m = 100)
}

k_factor_two_side <- function(N, p, c) {
  K.factor(N, f = NULL, alpha = (1 - as.double(c)), P = as.double(p),
           side = 2, method = "EXACT", m = 100)
}

#' Sample k-factor for a 1-sided interval: SIGNED distance from the mean to
#' the spec in SD units, positive when the mean is on the conforming side
#' (above a lower spec, below an upper spec). A value <= 0 means the mean is
#' at or beyond the spec, so no tolerance interval can be inside it.
k_sample_one_side <- function(sample_mean, sample_sd, spec, side) {
  if (side == "lower") (sample_mean - spec) / sample_sd else (spec - sample_mean) / sample_sd
}

# Returns the binding k-factor for a 2-sided interval: the minimum of the
# distances from the mean to each spec limit in SD units. Using the minimum
# ensures both bounds are within spec simultaneously. The symmetric half-window
# formula is only correct when the mean is exactly centred in the spec window.
k_sample_two_side <- function(sample_mean, sample_sd, s1, s2) {
  ks_lower <- (sample_mean - s1) / sample_sd
  ks_upper <- (s2 - sample_mean) / sample_sd
  min(ks_lower, ks_upper)
}

is_normal <- function(data, skew_threshold = 0.5) {
  if (length(data) < 3 || length(unique(data)) < 3) return(FALSE)
  if (any(is.na(data) | is.infinite(data))) return(FALSE)
  skew <- abs(e1071::skewness(data))
  message(paste("   Skewness value is:", round(skew, 4)))
  skew < skew_threshold
}

try_boxcox <- function(x, alpha = BOXCOX_ALPHA) {
  message("   Trying Box-Cox transformation (MLE-based)...")
  lm_model    <- stats::lm(x ~ 1)
  bc_result   <- MASS::boxcox(lm_model, plotit = FALSE)
  best_lambda <- bc_result$x[which.max(bc_result$y)]
  message(paste("   Optimal lambda =", round(best_lambda, 4)))
  x_bc        <- boxcox_transform(x, best_lambda)
  skew_before <- abs(e1071::skewness(x))
  skew_after  <- abs(e1071::skewness(x_bc))
  if (length(x_bc) >= 3 && length(x_bc) <= 5000) {
    p_val <- shapiro.test(x_bc)$p.value
    message(paste("   Shapiro-Wilk p-value after transform:", round(p_val, 4)))
  } else {
    p_val <- NA
    message(paste("   Shapiro-Wilk test skipped (N =", length(x_bc),
                  "is outside the valid range 3-5000); using skewness only."))
  }
  message(paste("   |Skew| before:", round(skew_before, 4),
                " |Skew| after:", round(skew_after, 4)))
  if (skew_after < skew_before || (!is.na(p_val) && p_val > alpha)) {
    message("   Box-Cox transformation accepted.\n")
    lam <- best_lambda
    if (abs(lam) < LAMBDA_EPS) {
      backtransform_fn <- function(val) exp(val)
    } else {
      backtransform_fn <- function(val) (lam * val + 1)^(1 / lam)
    }
    return(list(
      transformation = paste0("boxcox (lambda=", round(lam, 4), ")"),
      lambda         = lam,
      transformed    = x_bc,
      backtransform  = backtransform_fn
    ))
  }
  message("   Box-Cox did not sufficiently improve normality.")
  return(NULL)
}

auto_transform_normal <- function(x, alpha = BOXCOX_ALPHA) {
  results <- list(
    original       = x,
    transformation = "none",
    lambda         = NA,
    transformed    = x,
    backtransform  = function(val) val
  )
  message("✅ Analyzing data ...")
  if (is_normal(x)) {
    message("   Data is approximately normal.")
    results$transformation <- "normal"
    return(results)
  }
  message("   Data considered not normal. Trying Box-Cox transformation!")
  if (all(x > 0)) {
    bc <- try_boxcox(x, alpha)
    if (!is.null(bc)) {
      results$transformation <- bc$transformation
      results$lambda         <- bc$lambda
      results$transformed    <- bc$transformed
      results$backtransform  <- bc$backtransform
      return(results)
    }
  } else {
    message("   Box-Cox requires strictly positive data; skipping (data contains zeros or negatives).")
  }
  return(results)
}

# ---------------------------------------------------------------------------
# Main — header
# ---------------------------------------------------------------------------

message(" ")
message("✅ Attribute Sample Size Check for Design Verification")
message("   version: 1.0, author: Joep Rous")
message("   =====================================================")
message(paste("   proportion:                    ", proportion))
message(paste("   confidence:                    ", confidence))
message(paste("   file:                          ", file_path))
message(paste("   column:                        ", input_col))
message(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
message(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
message(paste("   pilot sample size:             ", length(x)))
message(paste("   planned verification N:        ", planned_N))
message(" ")

# ---------------------------------------------------------------------------
# Transformation
# ---------------------------------------------------------------------------

result <- auto_transform_normal(x, alpha = BOXCOX_ALPHA)

if (result$transformation == "none") {
  message(" ")
  message("❌ Could not assess sample size: data are not normally distributed")
  message("   and Box-Cox transformation did not achieve sufficient normality.")
  message("   (Note: sqrt is a Box-Cox special case at lambda=0.5 and is covered by that search.)")
  message(" ")
  message("   Suggestions:")
  message("     - If data are heavily rounded, try using more decimal places.")
  message("     - Plot your data and inspect for multimodality or outliers.")
  message("     - Consider whether the process may have shifted over time.")
  message("     - A non-parametric tolerance interval may be appropriate.")
  quit(save = "no", status = 1)
}

X     <- mean(result$transformed)
sigma <- sd(result$transformed)

message(paste("   transformation applied:        ", result$transformation))
message(" ")

# ---------------------------------------------------------------------------
# K-factor comparison — single calculation, no search loop
# ---------------------------------------------------------------------------

if (two_sided) {

  message("   Mode: 2-sided tolerance interval")

  spec1 <- if (result$transformation != "normal") boxcox_transform(spec1_raw, result$lambda) else spec1_raw
  spec2 <- if (result$transformation != "normal") boxcox_transform(spec2_raw, result$lambda) else spec2_raw

  if (X < spec1 || X > spec2) {
    warning(paste(
      "The sample mean (transformed:", round(X, 4),
      ") lies outside the spec window [transformed:", round(spec1, 4),
      ",", round(spec2, 4), "].",
      "The process may already be failing the specification.",
      "Interpret this result with caution."
    ))
  }

  ks   <- k_sample_two_side(X, sigma, spec1, spec2)
  kfos <- k_factor_two_side(planned_N, proportion, confidence)

} else if (lower_only) {

  message("   Mode: 1-sided (lower) tolerance interval")

  spec1 <- if (result$transformation != "normal") boxcox_transform(spec1_raw, result$lambda) else spec1_raw

  if (X < spec1) {
    warning(paste(
      "The sample mean (transformed:", round(X, 4),
      ") is below spec1 (transformed:", round(spec1, 4), ").",
      "The process may already be failing the specification.",
      "Interpret this result with caution."
    ))
  }

  ks   <- k_sample_one_side(X, sigma, spec1, "lower")
  kfos <- k_factor_one_side(planned_N, proportion, confidence)

} else {

  message("   Mode: 1-sided (upper) tolerance interval")

  spec2 <- if (result$transformation != "normal") boxcox_transform(spec2_raw, result$lambda) else spec2_raw

  if (X > spec2) {
    warning(paste(
      "The sample mean (transformed:", round(X, 4),
      ") is above spec2 (transformed:", round(spec2, 4), ").",
      "The process may already be failing the specification.",
      "Interpret this result with caution."
    ))
  }

  ks   <- k_sample_one_side(X, sigma, spec2, "upper")
  kfos <- k_factor_one_side(planned_N, proportion, confidence)

}

margin <- ks - kfos

# A sample k-factor <= 0 means the mean is at or beyond the spec limit: the
# requirement cannot be met by any N (signed distance, see k_sample_one_side).
mean_outside_spec <- ks <= 0

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

message(" ")
message("✅ Result:")
message(paste("   k-factor from pilot sample:    ", round(ks,   4)))
message(paste("   k-factor required for N =", planned_N, ":  ", round(kfos, 4)))
message(paste("   margin (k_sample - k_required):", round(margin, 4)))
message(" ")

if (margin >= 0) {
  message("✅ PASS: the planned sample size meets the tolerance interval requirement.")
  message(paste("   N =", planned_N, "is sufficient for verification."))
  if (planned_N < 10) {
    message(" ")
    message("⚠️  Note: planned N is less than 10.")
    message("   A minimum of 10 samples is typically required for FDA acceptance.")
    message("   Consider using N = 10 as the minimum regardless of the statistical result.")
  }
} else {
  message("❌ FAIL: the planned sample size does not meet the tolerance interval requirement.")
  if (mean_outside_spec) {
    message("   The sample mean is at or beyond the spec limit (k <= 0): no sample")
    message("   size can meet the requirement. Improve the process before verification.")
  } else {
    message(paste("   N =", planned_N, "is not sufficient for verification."))
    message("   The minimum sample size needed is higher than your planned N.")
    message("   Run jrc_ss_attr.R with this pilot data to find the true minimum N.")
  }
}

message(" ")
