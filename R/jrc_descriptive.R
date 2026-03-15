#!/usr/bin/env Rscript
#
# use as: Rscript jrc_descriptive.R <file_path> <column_name>
#
# "file_path"   should point to a csv file with column names as the first row
# "column_name" should be one of the column names in the csv file
#               (NOT the name of the first column, which is used for row names)
#
# IMPORTANT! The CSV file must have at least 2 columns: the first column is
# used for row names, the remaining columns contain data.
#
# Needs the <stats> and <e1071> libraries.
#
# Computes a descriptive statistics summary for the specified column.
# Intended as a quick data characterisation step before running jrc_normality,
# jrc_ss_attr, or jrc_verify_attr. The output is formatted for direct
# inclusion in a test report.
#
# Statistics reported:
#   Sample size    — N valid, N removed (NA/Inf)
#   Central tendency — mean, median
#   Spread         — SD, variance, CV (%)
#   Range          — min, max, range
#   Percentiles    — 5th, 25th, 75th, 95th
#   Distribution   — skewness, excess kurtosis
#   Confidence     — 95% CI on the mean (t-distribution)
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", "macos", r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

suppressPackageStartupMessages({
  library(stats)
  library(e1071)   # For skewness() and kurtosis()
})

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_descriptive.R <file_path> <column_name>",
    "Example:",
    "  Rscript jrc_descriptive.R mydata.csv ForceN",
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
N_raw <- length(x_raw)
n_bad <- sum(is.na(x_raw) | !is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed before analysis."))
}
x <- x_raw[is.finite(x_raw) & !is.na(x_raw)]
N <- length(x)

if (N < 2) {
  stop(paste("At least 2 valid observations are required. Got:", N))
}

# ---------------------------------------------------------------------------
# Calculations
# ---------------------------------------------------------------------------

x_mean   <- mean(x)
x_median <- median(x)
x_sd     <- sd(x)
x_var    <- var(x)
x_cv     <- if (x_mean != 0) abs(x_sd / x_mean) * 100 else NA
x_min    <- min(x)
x_max    <- max(x)
x_range  <- x_max - x_min
x_skew   <- e1071::skewness(x)
x_kurt   <- e1071::kurtosis(x)   # excess kurtosis (normal = 0)

# Percentiles
pct  <- quantile(x, probs = c(0.05, 0.25, 0.75, 0.95))

# 95% CI on the mean (t-distribution)
se      <- x_sd / sqrt(N)
t_crit  <- qt(0.975, df = N - 1)
ci_lo   <- x_mean - t_crit * se
ci_hi   <- x_mean + t_crit * se

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

message(" ")
message("✅ Descriptive Statistics")
message("   version: 1.0, author: Joep Rous")
message("   ==========================")
message(paste("   file:                     ", file_path))
message(paste("   column:                   ", input_col))
message(" ")
message("   Sample size:")
message(paste("   N (valid):                ", N))
if (n_bad > 0) {
  message(paste("   N (removed):              ", n_bad,
                " (NA or non-finite)"))
}
message(" ")
message("   Central tendency:")
message(paste("   mean:                     ", round(x_mean,   6)))
message(paste("   median:                   ", round(x_median, 6)))
message(" ")
message("   Spread:")
message(paste("   SD:                       ", round(x_sd,  6)))
message(paste("   variance:                 ", round(x_var, 6)))
if (!is.na(x_cv)) {
  message(paste("   CV:                       ", round(x_cv, 2), "%"))
} else {
  message("   CV:                        n/a  (mean is zero)")
}
message(" ")
message("   Range:")
message(paste("   min:                      ", round(x_min,   6)))
message(paste("   max:                      ", round(x_max,   6)))
message(paste("   range:                    ", round(x_range, 6)))
message(" ")
message("   Percentiles:")
message(paste("   5th:                      ", round(pct["5%"],  6)))
message(paste("   25th (Q1):                ", round(pct["25%"], 6)))
message(paste("   75th (Q3):                ", round(pct["75%"], 6)))
message(paste("   95th:                     ", round(pct["95%"], 6)))
message(paste("   IQR (Q3 - Q1):            ", round(pct["75%"] - pct["25%"], 6)))
message(" ")
message("   Distribution shape:")
message(paste("   skewness:                 ", round(x_skew, 4),
              if (abs(x_skew) < 0.5) "  (approximately symmetric)"
              else if (x_skew > 0)   "  (right-skewed)"
              else                   "  (left-skewed)"))
message(paste("   excess kurtosis:          ", round(x_kurt, 4),
              if (abs(x_kurt) < 1.0) "  (approximately normal)"
              else if (x_kurt > 0)   "  (heavy tails / leptokurtic)"
              else                   "  (light tails / platykurtic)"))
message(" ")
message("   95% confidence interval on the mean (t-distribution):")
message(paste("   lower:                    ", round(ci_lo, 6)))
message(paste("   upper:                    ", round(ci_hi, 6)))
message(paste("   margin of error:          ", round(t_crit * se, 6)))
message(" ")
