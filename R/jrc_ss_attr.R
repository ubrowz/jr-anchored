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
# Helper functions
# ---------------------------------------------------------------------------

# Report that no sample size can demonstrate the requirement because the
# pilot mean is at or beyond the spec limit (sample k-factor <= 0), then stop.
report_cannot_demonstrate <- function(ks, where) {
  jr_say(" ")
  jr_say("\u274c Result: no sample size can demonstrate this requirement.")
  jr_say(paste("   k-factor from initial sample:          ", round(ks, 4)))
  jr_say(paste0("   The sample mean is ", where, " (k <= 0), so the tolerance"))
  jr_say("   interval cannot lie inside the specification for any N.")
  jr_say("   Improve the process (centre it / reduce variation) before verification.")
  jr_say(" ")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# Main — print header first so it appears before any analysis messages
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Minimal Sample Size for Statistical Tolerance Interval")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ======================================================")
jr_say(paste("   for proportion:                ", proportion))
jr_say(paste("   for confidence:                ", confidence))
jr_say(paste("   file:                          ", file_path))
jr_say(paste("   column:                        ", input_col))
jr_say(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
jr_say(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
jr_say(paste("   number of observations:        ", length(x)))
jr_say(" ")

result <- jr_auto_transform_normal(x, alpha = JR_BOXCOX_ALPHA)

# ---------------------------------------------------------------------------
# Sample size search
# ---------------------------------------------------------------------------

if (result$transformation == "none") {

  jr_say("❌ Result: Could not compute sample size.")
  jr_say("")
  jr_say("   The data do not appear to follow a normal distribution, and Box-Cox")
  jr_say("   transformation did not achieve sufficient normality.")
  jr_say("   (Note: sqrt is a Box-Cox special case at lambda=0.5 and is covered by that search.)")
  jr_say("")
  jr_say("   Suggestions:")
  jr_say("     - If data are heavily rounded, try using more decimal places.")
  jr_say("     - Plot your data and inspect for multimodality or outliers.")
  jr_say("     - Consider whether the process may have shifted over time (non-stationarity).")
  jr_say("     - A non-parametric tolerance interval may be appropriate for this dataset.")

} else {

  X     <- mean(result$transformed)
  sigma <- sd(result$transformed)

  jr_say(paste("   transformation applied: ", result$transformation))

  if (!two_sided) {

    # Warn if the mean is already on the wrong side of the spec
    if (lower_only) {
      # --- 1-sided case ---
      jr_say("   Mode: 1-sided (lower) tolerance interval")
      spec1 <- if (result$transformation != "normal") {
        jr_boxcox_transform(spec1_raw, result$lambda)
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

      ks1 <- jr_ksample_one_side(X, sigma, spec1, "lower")
      jr_say(paste("   k-factor from initial sample:          ", round(ks1, 4)))
    }
    
    if (upper_only) {
      jr_say("   Mode: 1-sided (upper) tolerance interval")
      spec2 <- if (result$transformation != "normal") {
        jr_boxcox_transform(spec2_raw, result$lambda)
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

      ks1 <- jr_ksample_one_side(X, sigma, spec2, "upper")
      jr_say(paste("   k-factor from initial sample:          ", round(ks1, 4)))
    }

    if (ks1 <= 0) {
      report_cannot_demonstrate(ks1, if (lower_only) "at or below the lower spec limit"
                                     else "at or above the upper spec limit")
    }

    # Step by 1 to find the true minimum N (original code stepped by 5, over-shooting by up to 4)
    n1    <- 2
    step  <- 1
    kfos1 <- jr_kfactor(n1, proportion, confidence, 1)

    jr_say("   Calculating minimal sample size....", appendLF = FALSE)
    last_dot <- n1
    while ((kfos1 > ks1) && (n1 < 250)) {
      n1    <- n1 + step
      if (n1 >= 30)  { step <- 10 }
      if (n1 >= 100) { step <- 25 }
      kfos1 <- jr_kfactor(n1, proportion, confidence, 1)
      if ((n1 - last_dot >= 5) & (n1 >= 1)) {
        cat(".")
        last_dot <- n1
      } 
      if ((n1 - last_dot >= 20) & (n1 >= 30)) {
        cat(".")
        last_dot <- n1
      }      
    }
    jr_say("")   # close the dot line with a newline

    if (n1 >= 250) {
      stop(paste(
        "   Required sample size exceeds 250 for the 1-sided verification.\n",
        "         Try to reduce variation in the data before re-running."
      ))
    }

    jr_say(" ")
    jr_say("✅ Result:")
    jr_say(paste("   required k-factor for verification:    ", round(kfos1, 4)))
    jr_say(paste("   required sample size for verification: ", n1))
    jr_say(paste("   (N is conservative by at most step size", step, "— use jrc_ss_attr_check to verify exact N)"))
    if (n1 <= length(x)) {
      jr_say("✅ The current sample is sufficient for verification.")
      jr_say(paste("   (required N =", n1, "<= available N =", length(x), ")"))
    } else {
      jr_say("❌ The current sample is NOT sufficient for verification.")
      jr_say(paste("   (required N =", n1, "> available N =", length(x), ")"))
    }
    if (n1 < 10) {
      jr_say(" ")
      jr_say("⚠️  Note: the suggested sample size is less than 10.")
      jr_say("   Many organisations set a floor of 10 samples (common practice, not a regulatory rule).")
      jr_say("   Consider using N = 10 as the minimum regardless of the statistical result.")
    }

  } else {

    # --- 2-sided case ---
    jr_say("   Mode: 2-sided tolerance interval")

    if (result$transformation != "normal") {
      spec1 <- jr_boxcox_transform(spec1_raw, result$lambda)
      spec2 <- jr_boxcox_transform(spec2_raw, result$lambda)
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

    ks2 <- jr_ksample_two_side(X, sigma, spec1, spec2)
    jr_say(paste("   k-factor from initial sample:          ", round(ks2, 4)))
    if (ks2 <= 0) {
      report_cannot_demonstrate(ks2, "at or outside the specification window")
    }

    # Step by 1 to find the true minimum N
    n2    <- 2
    step  <- 1
    kfos2 <- jr_kfactor(n2, proportion, confidence, 2)

    jr_say("   Calculating minimal sample size....", appendLF = FALSE)
    last_dot <- n2
    while ((kfos2 > ks2) && (n2 < 250)) {
      n2    <- n2 + step
      if (n2 >= 30)  { step <- 10 }
      if (n2 >= 100) { step <- 25 }
      kfos2 <- jr_kfactor(n2, proportion, confidence, 2)
      if ((n2 - last_dot >= 5) & (n2 >= 1)) {
        cat(".")
        last_dot <- n2
      } 
      if ((n2 - last_dot >= 20) & (n2 >= 30)) {
        cat(".")
        last_dot <- n2
      }
    }
    jr_say("")   # close the dot line with a newline

    if (n2 >= 250) {
      stop(paste(
        "   Required sample size exceeds 250 for the 2-sided verification.\n",
        "         Try to reduce variation in the data before re-running."
      ))
    }

    jr_say(" ")
    jr_say("✅ Result:")
    jr_say(paste("   required k-factor for verification:    ", round(kfos2, 4)))
    jr_say(paste("   required sample size for verification: ", n2))
    jr_say(paste("   (N is conservative by at most step size", step, "— use jrc_ss_attr_check to verify exact N)"))
    jr_say(" ")
    if (n2 <= length(x)) {
      jr_say("✅ The current sample is sufficient for verification.")
      jr_say(paste("   (required N =", n2, "<= available N =", length(x), ")"))
    } else {
      jr_say("❌ The current sample is NOT sufficient for verification.")
      jr_say(paste("   (required N =", n2, "> available N =", length(x), ")"))
    }
    if (n2 < 10) {
      jr_say(" ")
      jr_say("⚠️  Note: the suggested sample size is less than 10.")
      jr_say("   Many organisations set a floor of 10 samples (common practice, not a regulatory rule).")
      jr_say("   Consider using N = 10 as the minimum regardless of the statistical result.")
    }
  }

  jr_say(" ")
}
