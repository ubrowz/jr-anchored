#!/usr/bin/env Rscript
#
# use as: Rscript jrc_normality.R <file_path> <column_name>
#
# "file_path"   should point to a csv file with column names as the first row
# "column_name" should be one of the column names in the csv file
#               (NOT the name of the first column, which is used for row names)
#
# IMPORTANT! The CSV file must have at least 2 columns: the first column is
# used for row names, the remaining columns contain data.
#
# Needs the <stats>, <MASS>, <e1071> and <nortest> libraries.
#
# Tests whether a dataset follows a normal distribution using multiple
# complementary methods:
#   - Skewness and kurtosis (moment-based, robust for small N)
#   - Shapiro-Wilk test (gold standard for N <= 5000)
#   - Anderson-Darling test (sensitive to tail departures)
#
# If the data are not normal, a Box-Cox transformation is attempted and
# the transformation result is reported. This mirrors the normalisation
# logic used in jrc_ss_attr and related scripts.
#
# Use this script before running jrc_ss_attr to understand the distributional
# properties of your pilot data and confirm which transformation (if any)
# will be applied.
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
  library(MASS)
  library(e1071)
  library(nortest)   # For Anderson-Darling test
})

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BOXCOX_ALPHA   <- JR_BOXCOX_ALPHA     # shared with jrc_ss_attr & co.
LAMBDA_EPS     <- 1e-6
SKEW_THRESHOLD <- JR_SKEW_THRESHOLD

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_normality.R <file_path> <column_name>",
    "Example:",
    "  Rscript jrc_normality.R mydata.csv ForceN",
    sep = "\n"
  ))
}

file_path <- args[1]
input_col <- args[2]
col       <- make.names(input_col)

if (!file.exists(file_path)) {
  stop(paste("File not found:", file_path))
}

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
  warning(paste(n_bad, "NA or non-finite value(s) removed before analysis."))
}
x <- x_raw[is.finite(x_raw)]
N <- length(x)

if (N < 3) {
  stop("Fewer than 3 valid observations. Cannot test normality.")
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

boxcox_transform <- function(val, lambda) {
  if (abs(lambda) < LAMBDA_EPS) log(val) else (val^lambda - 1) / lambda
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Normality Check")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ==================================")
jr_say(paste("   file:                     ", file_path))
jr_say(paste("   column:                   ", input_col))
jr_say(paste("   valid observations (N):   ", N))
jr_say(" ")

# ---------------------------------------------------------------------------
# Descriptive moments
# ---------------------------------------------------------------------------

skew <- e1071::skewness(x)
kurt <- e1071::kurtosis(x)   # excess kurtosis (normal = 0)

jr_say("   Moment statistics:")
jr_say(paste("   skewness:                 ", round(skew, 4),
              if (abs(skew) < SKEW_THRESHOLD) "  (acceptable)" else "  (elevated)"))
jr_say(paste("   excess kurtosis:          ", round(kurt, 4),
              if (abs(kurt) < 1.0) "  (acceptable)" else "  (elevated)"))
jr_say(" ")

# ---------------------------------------------------------------------------
# Shapiro-Wilk test
# ---------------------------------------------------------------------------

jr_say("   Shapiro-Wilk test:")
if (N >= 3 && N <= 5000) {
  sw      <- shapiro.test(x)
  sw_pass <- sw$p.value > 0.05
  jr_say(paste("   W statistic:              ", round(sw$statistic, 4)))
  jr_say(paste("   p-value:                  ", round(sw$p.value, 4),
                if (sw_pass) "  (p > 0.05: consistent with normality)"
                else         "  (p <= 0.05: departure from normality)"))
} else {
  sw_pass <- NULL
  jr_say(paste("   Skipped: N =", N, "is outside the valid range (3-5000)."))
}
jr_say(" ")

# ---------------------------------------------------------------------------
# Anderson-Darling test
# ---------------------------------------------------------------------------

jr_say("   Anderson-Darling test:")
if (N >= 7) {
  ad      <- nortest::ad.test(x)
  ad_pass <- ad$p.value > 0.05
  jr_say(paste("   A statistic:              ", round(ad$statistic, 4)))
  jr_say(paste("   p-value:                  ", round(ad$p.value, 4),
                if (ad_pass) "  (p > 0.05: consistent with normality)"
                else         "  (p <= 0.05: departure from normality)"))
} else {
  ad_pass <- NULL
  jr_say(paste("   Skipped: N =", N, "is below the minimum of 7 for Anderson-Darling."))
}
jr_say(" ")

# ---------------------------------------------------------------------------
# Overall normality verdict
# ---------------------------------------------------------------------------

skew_pass <- abs(skew) < SKEW_THRESHOLD
all_tests <- c(skew_pass,
               if (!is.null(sw_pass)) sw_pass else NULL,
               if (!is.null(ad_pass)) ad_pass else NULL)
is_normal <- all(all_tests)

jr_say("   Overall verdict:")
if (is_normal) {
  jr_say("✅ Data are consistent with a normal distribution.")
} else {
  jr_say("⚠️  Data show departures from normality.")
}

# jrc_ss_attr, _check, _ci and jrc_verify_attr decide on skewness alone
# (|skewness| < SKEW_THRESHOLD: use as-is; otherwise try Box-Cox). Say what
# they will do, which can differ from the verdict above (COR-14).
jr_say(" ")
jr_say("   What jrc_ss_attr / _check / _ci and jrc_verify_attr will do")
jr_say(paste0("   (their rule: |skewness| < ", SKEW_THRESHOLD, " -> use as-is, else try Box-Cox):"))
if (abs(skew) < SKEW_THRESHOLD) {
  jr_say("   They will use the data as-is (no transformation).")
  if (!is_normal) {
    jr_say("⚠️  They do not apply Shapiro-Wilk or Anderson-Darling, so the departures")
    jr_say("   above are NOT acted upon. Review the histogram/Q-Q plot before relying")
    jr_say("   on a normal tolerance interval.")
  }
} else {
  jr_say("   They will attempt a Box-Cox transformation.")
}

if (abs(skew) >= SKEW_THRESHOLD) {
  jr_say(" ")

  # Attempt Box-Cox
  if (all(x > 0)) {
    jr_say("   Box-Cox transformation attempt:")
    lm_model    <- stats::lm(x ~ 1)
    bc_result   <- MASS::boxcox(lm_model, plotit = FALSE)
    best_lambda <- bc_result$x[which.max(bc_result$y)]
    x_bc        <- boxcox_transform(x, best_lambda)
    skew_after  <- abs(e1071::skewness(x_bc))

    jr_say(paste("   optimal lambda:           ", round(best_lambda, 4)))
    jr_say(paste("   |skewness| after:         ", round(skew_after, 4)))

    if (N >= 3 && N <= 5000) {
      p_after <- shapiro.test(x_bc)$p.value
      jr_say(paste("   Shapiro-Wilk p after:     ", round(p_after, 4)))
    } else {
      p_after <- NA
    }
    # Same acceptance rule as jrc_ss_attr & co. (bin/jr_stats_helpers.R)
    bc_accepted <- jr_boxcox_accepted(p_after, skew_after, BOXCOX_ALPHA)

    if (bc_accepted) {
      jr_say(paste0("✅ Box-Cox transformation accepted (lambda = ",
                     round(best_lambda, 4), ")."))
      jr_say("   jrc_ss_attr will apply this transformation automatically.")
    } else {
      jr_say("❌ Box-Cox transformation did not sufficiently improve normality.")
      jr_say("   Consider a non-parametric tolerance interval approach.")
    }
  } else {
    jr_say("   Box-Cox skipped: data contains zeros or negative values.")
    jr_say("   Consider a non-parametric tolerance interval approach.")
  }
}

jr_say(" ")
