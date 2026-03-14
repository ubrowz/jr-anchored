#!/usr/bin/env Rscript
#
# use as: Rscript jrc_outliers.R <file_path> <column_name>
#
# "file_path"   should point to a csv file with column names as the first row
# "column_name" should be one of the column names in the csv file
#               (NOT the name of the first column, which is used for row names)
#
# IMPORTANT! The CSV file must have at least 2 columns: the first column is
# used for row names, the remaining columns contain data.
#
# Needs the <stats> and <outliers> libraries.
#
# Tests for outliers using two complementary methods:
#
#   Grubbs test (iterative):
#     Tests for a single outlier at a time. Iterates until no further
#     outliers are found or the maximum of 10% of N is reached.
#     Standard method for small samples in medical device testing.
#     Assumes approximately normal data.
#
#   IQR method:
#     Flags observations outside [Q1 - 1.5*IQR, Q3 + 1.5*IQR].
#     Distribution-free. Robust for non-normal data.
#     Observations outside [Q1 - 3*IQR, Q3 + 3*IQR] are flagged as
#     extreme outliers.
#
# Both methods report the row ID of flagged observations so they can be
# located in the original data file.
#
# Note: flagged observations should be investigated for assignable causes
# before removal. Statistical outlier tests do not justify removal without
# a documented physical or procedural reason.
#
# Author: Joep Rous
# Version: 1.0

suppressPackageStartupMessages({
  library(stats)
  library(outliers)   # For Grubbs test
})

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_outliers.R <file_path> <column_name>",
    "Example:",
    "  Rscript jrc_outliers.R mydata.csv ForceN",
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

x_raw  <- mydata[[col]]
ids    <- rownames(mydata)
n_bad  <- sum(is.na(x_raw) | !is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed before analysis."))
}
keep   <- is.finite(x_raw) & !is.na(x_raw)
x      <- x_raw[keep]
ids    <- ids[keep]
N      <- length(x)

if (N < 6) {
  stop(paste("At least 6 valid observations are required for outlier testing. Got:", N))
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

message(" ")
message("✅ Outlier Detection")
message("   version: 1.0, author: Joep Rous")
message("   ====================================")
message(paste("   file:                     ", file_path))
message(paste("   column:                   ", input_col))
message(paste("   valid observations (N):   ", N))
message(" ")

# ---------------------------------------------------------------------------
# Grubbs test — iterative
# ---------------------------------------------------------------------------

MAX_OUTLIERS <- max(1, floor(0.10 * N))   # cap at 10% of N

message("   Grubbs Test (iterative, alpha = 0.05):")
message("   Assumes approximately normal data.")
message(paste("   Maximum outliers to flag:  ", MAX_OUTLIERS))
message(" ")
message("   -----------------------------------------------")
message("    iteration   row ID         value    p-value")
message("   -----------------------------------------------")

x_grubbs       <- x
ids_grubbs     <- ids
grubbs_flagged <- character(0)
iter           <- 0

repeat {
  if (length(x_grubbs) < 6) break
  if (iter >= MAX_OUTLIERS) break

  g        <- outliers::grubbs.test(x_grubbs, type = 10)
  p_val    <- g$p.value

  # Identify which value is the candidate (min or max, whichever is more extreme)
  candidate_idx <- if (abs(x_grubbs[which.max(x_grubbs)] - mean(x_grubbs)) >=
                       abs(x_grubbs[which.min(x_grubbs)] - mean(x_grubbs))) {
    which.max(x_grubbs)
  } else {
    which.min(x_grubbs)
  }

  candidate_id  <- ids_grubbs[candidate_idx]
  candidate_val <- x_grubbs[candidate_idx]
  iter          <- iter + 1

  if (p_val < 0.05) {
    message(sprintf("    %2d          %-12s   %8.4f   %.4f  ← outlier",
                    iter, candidate_id, candidate_val, p_val))
    grubbs_flagged <- c(grubbs_flagged, candidate_id)
    x_grubbs   <- x_grubbs[-candidate_idx]
    ids_grubbs <- ids_grubbs[-candidate_idx]
  } else {
    message(sprintf("    %2d          %-12s   %8.4f   %.4f  (not significant)",
                    iter, candidate_id, candidate_val, p_val))
    break
  }
}

message("   -----------------------------------------------")
message(" ")

if (length(grubbs_flagged) == 0) {
  message("✅ Grubbs: no outliers detected.")
} else {
  message(paste0("⚠️  Grubbs: ", length(grubbs_flagged), " outlier(s) flagged: ",
                 paste(grubbs_flagged, collapse = ", ")))
}

message(" ")

# ---------------------------------------------------------------------------
# IQR method
# ---------------------------------------------------------------------------

Q1     <- quantile(x, 0.25)
Q3     <- quantile(x, 0.75)
IQR_x  <- Q3 - Q1
lower  <- Q1 - 1.5 * IQR_x
upper  <- Q3 + 1.5 * IQR_x
lower_extreme <- Q1 - 3.0 * IQR_x
upper_extreme <- Q3 + 3.0 * IQR_x

mild_idx    <- which(x < lower | x > upper)
extreme_idx <- which(x < lower_extreme | x > upper_extreme)

message("   IQR Method (distribution-free):")
message(paste("   Q1:                       ", round(Q1, 4)))
message(paste("   Q3:                       ", round(Q3, 4)))
message(paste("   IQR:                      ", round(IQR_x, 4)))
message(paste("   mild outlier fence:       [", round(lower, 4), ",", round(upper, 4), "]"))
message(paste("   extreme outlier fence:    [", round(lower_extreme, 4), ",",
              round(upper_extreme, 4), "]"))
message(" ")

if (length(mild_idx) == 0) {
  message("✅ IQR: no outliers detected.")
} else {
  message("   -----------------------------------------------")
  message("    row ID         value        classification")
  message("   -----------------------------------------------")
  for (i in mild_idx) {
    classification <- if (i %in% extreme_idx) "extreme outlier" else "mild outlier"
    message(sprintf("    %-12s   %8.4f     %s", ids[i], x[i], classification))
  }
  message("   -----------------------------------------------")
  message(" ")
  n_extreme <- length(extreme_idx)
  n_mild    <- length(mild_idx) - n_extreme
  if (n_extreme > 0) {
    message(paste0("⚠️  IQR: ", length(mild_idx), " outlier(s) flagged (",
                   n_mild, " mild, ", n_extreme, " extreme)."))
  } else {
    message(paste0("⚠️  IQR: ", length(mild_idx), " mild outlier(s) flagged."))
  }
}

message(" ")
message("   Note:")
message("   Flagged observations should be investigated for assignable causes")
message("   (measurement error, procedural deviation, data entry error) before")
message("   any removal is considered. Removal requires documented justification.")
message("   Statistical significance alone is not sufficient grounds for removal.")
message(" ")
