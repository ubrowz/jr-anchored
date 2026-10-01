#!/usr/bin/env Rscript
#
# use as: Rscript jrc_ss_attr.R <proportion> <confidence> <file_path> <column_name> <spec1> <spec2>
#
# "proportion"  is the minimum fraction of the population that must be within
#               the tolerance interval (e.g. 0.95)
# "confidence"  is the confidence level for that claim (e.g. 0.95)
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
# Determines the minimal sample size needed to satisfy a 1-sided or 2-sided
# statistical tolerance interval requirement, based on a pilot data set.
# Non-normal data are handled via Box-Cox transformation.
#
# The sample size search uses an adaptive step size for performance: steps of 1
# up to N=30, steps of 10 up to N=100, steps of 25 beyond N=100. The reported
# N is therefore conservative by at most the current step size. For the exact
# minimum, run with a tight range around the reported value.
#
# Use jrc_ss_attr_check first to quickly verify whether a specific planned N
# meets the requirement before running the full search.
#
# Reference:
#   Meeker, W.Q., Hahn, G.J., Escobar, L.A. (2017). Statistical Intervals:
#   A Guide for Practitioners and Researchers, 2nd ed. Wiley.
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

# Significance level for Box-Cox acceptance test (Shapiro-Wilk).
# 0.01 is stricter than the default 0.05: Box-Cox is only accepted when the
# transformed data clearly passes normality. Adjust if needed.
BOXCOX_ALPHA <- 0.01

# Lambda threshold below which Box-Cox collapses to a log transformation.
# Must be the same value everywhere lambda is evaluated to guarantee that
# spec limits and data are always transformed identically.
LAMBDA_EPS <- 1e-6

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 6) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_ss_attr.R <proportion> <confidence> <file_path> <column_name> <spec1> <spec2>",
    "Example (1-sided lower):",
    "  Rscript jrc_ss_attr.R 0.95 0.95 mydata.csv ForceN 8.0 -",
    "Example (1-sided upper):",
    "  Rscript jrc_ss_attr.R 0.95 0.95 mydata.csv ForceN - 12.0",
    "Example (2-sided):",
    "  Rscript jrc_ss_attr.R 0.95 0.95 mydata.csv ForceN 8.0 12.0",
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

has_spec1 <- !is.na(spec1_raw)   # FALSE when user passed "-"
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

# Determines which interval side(s) to show on the plot
two_sided   <- has_spec1 && has_spec2
lower_only  <- has_spec1 && !has_spec2   # spec1 = LSL, show lower TI
upper_only  <- !has_spec1 && has_spec2   # spec2 = USL, show upper TI

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

myforces <- tryCatch(
  read.table(file_path, header = TRUE, sep = ",", dec = ".", row.names = 1),
  error = function(e) stop(paste("Failed to read CSV file:", e$message))
)

if (ncol(myforces) < 1) {
  stop(paste(
    "The CSV file must have at least 2 columns: one for row names and at",
    "least one data column. The file appears to have only 1 column."
  ))
}

if (!col %in% names(myforces)) {
  stop(paste0(
    "Column '", col, "' not found in file. ",
    "Available columns: ", paste(names(myforces), collapse = ", ")
  ))
}

x_raw <- myforces[[col]]

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

#' Apply a Box-Cox transformation using the unified LAMBDA_EPS threshold.
#' Using this function for both data and spec limits guarantees they are
#' always transformed by exactly the same rule.
#'
#' @param val    Numeric vector or scalar (must be strictly positive).
#' @param lambda Box-Cox lambda parameter.
boxcox_transform <- function(val, lambda) {
  if (abs(lambda) < LAMBDA_EPS) {
    return(log(val))
  } else {
    return((val^lambda - 1) / lambda)
  }
}

#' K-factor for a 1-sided tolerance interval.
k_factor_one_side <- function(N, p, c) {
  K.factor(N, f = NULL, alpha = (1 - as.double(c)), P = as.double(p),
           side = 1, method = "EXACT", m = 100)
}

#' K-factor for a 2-sided tolerance interval.
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

#' Sample k-factor for a 2-sided interval: half the spec window in SD units.
# Returns the binding k-factor for a 2-sided interval: the minimum of the
# distances from the mean to each spec limit in SD units. Using the minimum
# ensures both bounds are within spec simultaneously. The symmetric half-window
# formula is only correct when the mean is exactly centred in the spec window.
k_sample_two_side <- function(sample_mean, sample_sd, s1, s2) {
  ks_lower <- (sample_mean - s1) / sample_sd
  ks_upper <- (s2 - sample_mean) / sample_sd
  min(ks_lower, ks_upper)
}

#' Test whether a numeric vector is approximately normally distributed.
#' Uses skewness as the primary criterion (robust for small N).
#'
#' @param data           Numeric vector to test (NA/Inf already removed upstream).
#' @param skew_threshold Maximum absolute skewness considered acceptable.
is_normal <- function(data, skew_threshold = 0.5) {
  if (length(data) < 3 || length(unique(data)) < 3) return(FALSE)
  if (any(is.na(data) | is.infinite(data))) return(FALSE)
  skew <- abs(e1071::skewness(data))   # FIX: was incorrectly referencing outer 'x'
  message(paste("   Skewness value is:", round(skew, 4)))
  skew < skew_threshold
}

#' Attempt Box-Cox transformation and evaluate whether it improves normality.
#'
#' @param x      Strictly positive numeric vector.
#' @param alpha  Significance level for Shapiro-Wilk test.
#' @return A list (transformation, lambda, transformed, backtransform) or NULL if rejected.
try_boxcox <- function(x, alpha = BOXCOX_ALPHA) {

  message("   Trying Box-Cox transformation (MLE-based)...")

  lm_model    <- stats::lm(x ~ 1)
  bc_result   <- MASS::boxcox(lm_model, plotit = FALSE)
  best_lambda <- bc_result$x[which.max(bc_result$y)]

  message(paste("   Optimal lambda =", round(best_lambda, 4)))

  x_bc        <- boxcox_transform(x, best_lambda)
  skew_before <- abs(e1071::skewness(x))
  skew_after  <- abs(e1071::skewness(x_bc))

  # shapiro.test() only accepts 3 <= N <= 5000
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

    lam <- best_lambda   # capture by value
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

#' Determine the appropriate transformation for x and return transformed data + metadata.
auto_transform_normal <- function(x, alpha = BOXCOX_ALPHA) {

  results <- list(
    original       = x,
    transformation = "none",
    lambda         = NA,
    transformed    = x,
    backtransform  = function(val) val
  )

  message("✅ Analyzing data ...")

  # FIX: normality check no longer gated by no_negatives — normal data can be negative.
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

# Report that no sample size can demonstrate the requirement because the
# pilot mean is at or beyond the spec limit (sample k-factor <= 0), then stop.
report_cannot_demonstrate <- function(ks, where) {
  message(" ")
  message("\u274c Result: no sample size can demonstrate this requirement.")
  message(paste("   k-factor from initial sample:          ", round(ks, 4)))
  message(paste0("   The sample mean is ", where, " (k <= 0), so the tolerance"))
  message("   interval cannot lie inside the specification for any N.")
  message("   Improve the process (centre it / reduce variation) before verification.")
  message(" ")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# Main — print header first so it appears before any analysis messages
# ---------------------------------------------------------------------------

message(" ")
message("✅ Minimal Sample Size for Statistical Tolerance Interval")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(paste("   for proportion:                ", proportion))
message(paste("   for confidence:                ", confidence))
message(paste("   file:                          ", file_path))
message(paste("   column:                        ", input_col))
message(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
message(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
message(paste("   number of observations:        ", length(x)))
message(" ")

result <- auto_transform_normal(x, alpha = BOXCOX_ALPHA)

# ---------------------------------------------------------------------------
# Sample size search
# ---------------------------------------------------------------------------

if (result$transformation == "none") {

  message("❌ Result: Could not compute sample size.")
  message("")
  message("   The data do not appear to follow a normal distribution, and Box-Cox")
  message("   transformation did not achieve sufficient normality.")
  message("   (Note: sqrt is a Box-Cox special case at lambda=0.5 and is covered by that search.)")
  message("")
  message("   Suggestions:")
  message("     - If data are heavily rounded, try using more decimal places.")
  message("     - Plot your data and inspect for multimodality or outliers.")
  message("     - Consider whether the process may have shifted over time (non-stationarity).")
  message("     - A non-parametric tolerance interval may be appropriate for this dataset.")

} else {

  X     <- mean(result$transformed)
  sigma <- sd(result$transformed)

  message(paste("   transformation applied: ", result$transformation))

  if (!two_sided) {


    # Warn if the mean is already on the wrong side of the spec
    if (lower_only) {
      # --- 1-sided case ---
      message("   Mode: 1-sided (lower) tolerance interval")
      spec1 <- if (result$transformation != "normal") {
        boxcox_transform(spec1_raw, result$lambda)
      } else {
        spec1_raw
      }      
      if (X < spec1) {
        warning(paste(
          "   The sample mean (transformed:", round(X, 4), ") is below spec1 (transformed:",
          round(spec1, 4), ").",
          "   The process may already be failing the specification.",
          "   Interpret the sample size result with caution."
        ))
      }

      ks1 <- k_sample_one_side(X, sigma, spec1, "lower")
      message(paste("   k-factor from initial sample:          ", round(ks1, 4)))
    }
    
    if (upper_only) {
      message("   Mode: 1-sided (upper) tolerance interval")
      spec2 <- if (result$transformation != "normal") {
        boxcox_transform(spec2_raw, result$lambda)
      } else {
        spec2_raw
      }
      if (X > spec2) {
        warning(paste(
          "   The sample mean (transformed:", round(X, 4), ") is greater than spec2 (transformed:",
          round(spec2, 4), ").",
          "   The process may already be failing the specification.",
          "   Interpret the sample size result with caution."
      ))
      }

      ks1 <- k_sample_one_side(X, sigma, spec2, "upper")
      message(paste("   k-factor from initial sample:          ", round(ks1, 4)))
    }

    if (ks1 <= 0) {
      report_cannot_demonstrate(ks1, if (lower_only) "at or below the lower spec limit"
                                     else "at or above the upper spec limit")
    }

    # Step by 1 to find the true minimum N (original code stepped by 5, over-shooting by up to 4)
    n1    <- 2
    step  <- 1
    kfos1 <- k_factor_one_side(n1, proportion, confidence)

    message("   Calculating minimal sample size....", appendLF = FALSE)
    last_dot <- n1
    while ((kfos1 > ks1) && (n1 < 250)) {
      n1    <- n1 + step
      if (n1 >= 30)  { step <- 10 }
      if (n1 >= 100) { step <- 25 }
      kfos1 <- k_factor_one_side(n1, proportion, confidence)
      if ((n1 - last_dot >= 5) & (n1 >= 1)) {
        cat(".")
        last_dot <- n1
      } 
      if ((n1 - last_dot >= 20) & (n1 >= 30)) {
        cat(".")
        last_dot <- n1
      }      
    }
    message("")   # close the dot line with a newline

    if (n1 >= 250) {
      stop(paste(
        "   Required sample size exceeds 250 for the 1-sided verification.\n",
        "         Try to reduce variation in the data before re-running."
      ))
    }

    message(" ")
    message("✅ Result:")
    message(paste("   required k-factor for verification:    ", round(kfos1, 4)))
    message(paste("   required sample size for verification: ", n1))
    message(paste("   (N is conservative by at most step size", step, "— use jrc_ss_attr_check to verify exact N)"))
    if (n1 <= length(x)) {
      message("✅ The current sample is sufficient for verification.")
      message(paste("   (required N =", n1, "<= available N =", length(x), ")"))
    } else {
      message("❌ The current sample is NOT sufficient for verification.")
      message(paste("   (required N =", n1, "> available N =", length(x), ")"))
    }
    if (n1 < 10) {
      message(" ")
      message("⚠️  Note: the suggested sample size is less than 10.")
      message("   A minimum of 10 samples is typically required for FDA acceptance.")
      message("   Consider using N = 10 as the minimum regardless of the statistical result.")
    }

  } else {

    # --- 2-sided case ---
    message("   Mode: 2-sided tolerance interval")

    if (result$transformation != "normal") {
      spec1 <- boxcox_transform(spec1_raw, result$lambda)
      spec2 <- boxcox_transform(spec2_raw, result$lambda)
    } else {
      spec1 <- spec1_raw
      spec2 <- spec2_raw
    }

    # Warn if the mean falls outside the spec window
    if (X < spec1 || X > spec2) {
      warning(paste(
        "   The sample mean (transformed:", round(X, 4),
        "   ) lies outside the spec window [transformed:", round(spec1, 4),
        ",", round(spec2, 4), "].",
        "   The process may already be failing the specification.",
        "   Interpret the sample size result with caution."
      ))
    }

    ks2 <- k_sample_two_side(X, sigma, spec1, spec2)
    message(paste("   k-factor from initial sample:          ", round(ks2, 4)))
    if (ks2 <= 0) {
      report_cannot_demonstrate(ks2, "at or outside the specification window")
    }

    # Step by 1 to find the true minimum N
    n2    <- 2
    step  <- 1
    kfos2 <- k_factor_two_side(n2, proportion, confidence)

    message("   Calculating minimal sample size....", appendLF = FALSE)
    last_dot <- n2
    while ((kfos2 > ks2) && (n2 < 250)) {
      n2    <- n2 + step
      if (n2 >= 30)  { step <- 10 }
      if (n2 >= 100) { step <- 25 }
      kfos2 <- k_factor_two_side(n2, proportion, confidence)
      if ((n2 - last_dot >= 5) & (n2 >= 1)) {
        cat(".")
        last_dot <- n2
      } 
      if ((n2 - last_dot >= 20) & (n2 >= 30)) {
        cat(".")
        last_dot <- n2
      }
    }
    message("")   # close the dot line with a newline

    if (n2 >= 250) {
      stop(paste(
        "   Required sample size exceeds 250 for the 2-sided verification.\n",
        "         Try to reduce variation in the data before re-running."
      ))
    }

    message(" ")
    message("✅ Result:")
    message(paste("   required k-factor for verification:    ", round(kfos2, 4)))
    message(paste("   required sample size for verification: ", n2))
    message(paste("   (N is conservative by at most step size", step, "— use jrc_ss_attr_check to verify exact N)"))
    message(" ")
    if (n2 <= length(x)) {
      message("✅ The current sample is sufficient for verification.")
      message(paste("   (required N =", n2, "<= available N =", length(x), ")"))
    } else {
      message("❌ The current sample is NOT sufficient for verification.")
      message(paste("   (required N =", n2, "> available N =", length(x), ")"))
    }
    if (n2 < 10) {
      message(" ")
      message("⚠️  Note: the suggested sample size is less than 10.")
      message("   A minimum of 10 samples is typically required for FDA acceptance.")
      message("   Consider using N = 10 as the minimum regardless of the statistical result.")
    }
  }

  message(" ")
}
