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
  library(MASS)   # For boxcox()
  library(e1071)  # For skewness()
})

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

# ---------------------------------------------------------------------------
# Main — header
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Attribute Sample Size Check for Design Verification")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   =====================================================")
jr_say(paste("   proportion:                    ", proportion))
jr_say(paste("   confidence:                    ", confidence))
jr_say(paste("   file:                          ", file_path))
jr_say(paste("   column:                        ", input_col))
jr_say(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
jr_say(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
jr_say(paste("   pilot sample size:             ", length(x)))
jr_say(paste("   planned verification N:        ", planned_N))
jr_say(" ")

# ---------------------------------------------------------------------------
# Transformation
# ---------------------------------------------------------------------------

result <- jr_auto_transform_normal(x, alpha = JR_BOXCOX_ALPHA)

if (result$transformation == "none") {
  jr_say(" ")
  jr_say("❌ Could not assess sample size: data are not normally distributed")
  jr_say("   and Box-Cox transformation did not achieve sufficient normality.")
  jr_say("   (Note: sqrt is a Box-Cox special case at lambda=0.5 and is covered by that search.)")
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

jr_say(paste("   transformation applied:        ", result$transformation))
jr_say(" ")

# ---------------------------------------------------------------------------
# K-factor comparison — single calculation, no search loop
# ---------------------------------------------------------------------------

if (two_sided) {

  jr_say("   Mode: 2-sided tolerance interval")

  spec1 <- if (result$transformation != "normal") jr_boxcox_transform(spec1_raw, result$lambda) else spec1_raw
  spec2 <- if (result$transformation != "normal") jr_boxcox_transform(spec2_raw, result$lambda) else spec2_raw

  if (X < spec1 || X > spec2) {
    warning(paste(
      "The sample mean (transformed:", round(X, 4),
      ") lies outside the spec window [transformed:", round(spec1, 4),
      ",", round(spec2, 4), "].",
      "The process may already be failing the specification.",
      "Interpret this result with caution."
    ))
  }

  ks   <- jr_ksample_two_side(X, sigma, spec1, spec2)
  kfos <- jr_kfactor(planned_N, proportion, confidence, 2)

} else if (lower_only) {

  jr_say("   Mode: 1-sided (lower) tolerance interval")

  spec1 <- if (result$transformation != "normal") jr_boxcox_transform(spec1_raw, result$lambda) else spec1_raw

  if (X < spec1) {
    warning(paste(
      "The sample mean (transformed:", round(X, 4),
      ") is below spec1 (transformed:", round(spec1, 4), ").",
      "The process may already be failing the specification.",
      "Interpret this result with caution."
    ))
  }

  ks   <- jr_ksample_one_side(X, sigma, spec1, "lower")
  kfos <- jr_kfactor(planned_N, proportion, confidence, 1)

} else {

  jr_say("   Mode: 1-sided (upper) tolerance interval")

  spec2 <- if (result$transformation != "normal") jr_boxcox_transform(spec2_raw, result$lambda) else spec2_raw

  if (X > spec2) {
    warning(paste(
      "The sample mean (transformed:", round(X, 4),
      ") is above spec2 (transformed:", round(spec2, 4), ").",
      "The process may already be failing the specification.",
      "Interpret this result with caution."
    ))
  }

  ks   <- jr_ksample_one_side(X, sigma, spec2, "upper")
  kfos <- jr_kfactor(planned_N, proportion, confidence, 1)

}

margin <- ks - kfos

# A sample k-factor <= 0 means the mean is at or beyond the spec limit: the
# requirement cannot be met by any N (signed distance, see k_sample_one_side).
mean_outside_spec <- ks <= 0

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Result:")
jr_say(paste("   k-factor from pilot sample:    ", round(ks,   4)))
jr_say(paste("   k-factor required for N =", planned_N, ":  ", round(kfos, 4)))
jr_say(paste("   margin (k_sample - k_required):", round(margin, 4)))
jr_say(" ")

if (margin >= 0) {
  jr_say("✅ PASS: the planned sample size meets the tolerance interval requirement.")
  jr_say(paste("   N =", planned_N, "is sufficient for verification."))
  if (planned_N < 10) {
    jr_say(" ")
    jr_say("⚠️  Note: planned N is less than 10.")
    jr_say("   Many organisations set a floor of 10 samples (common practice, not a regulatory rule).")
    jr_say("   Consider using N = 10 as the minimum regardless of the statistical result.")
  }
} else {
  jr_say("❌ FAIL: the planned sample size does not meet the tolerance interval requirement.")
  if (mean_outside_spec) {
    jr_say("   The sample mean is at or beyond the spec limit (k <= 0): no sample")
    jr_say("   size can meet the requirement. Improve the process before verification.")
  } else {
    jr_say(paste("   N =", planned_N, "is not sufficient for verification."))
    jr_say("   The minimum sample size needed is higher than your planned N.")
    jr_say("   Run jrc_ss_attr.R with this pilot data to find the true minimum N.")
  }
}

jr_say(" ")
