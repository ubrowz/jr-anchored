#!/usr/bin/env Rscript
#
# use as: Rscript jrc_capability.R <file_path> <column_name> <spec1> <spec2>
#
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
# Needs only base R — no external libraries required.
#
# Computes process capability and performance indices:
#
#   Cp  / Pp   — spread-only index (requires both spec limits)
#                Cp = Pp = (USL - LSL) / (6 * sigma)
#   Cpk / Ppk  — centring-aware index (works with one or both spec limits)
#                Cpk = Ppk = min((mean - LSL), (USL - mean)) / (3 * sigma)
#
# Note: this script uses the overall sample standard deviation for all
# indices. Cp and Cpk traditionally use a within-subgroup SD estimate, but
# since no subgroup structure is available in a flat CSV file, the overall
# SD is used throughout. This means Cp == Pp and Cpk == Ppk numerically,
# but both are reported for completeness and labelled accordingly.
# Confidence intervals are computed using the noncentral chi-squared method.
#
# Common benchmark values:
#   Cpk >= 1.33  — capable process (typical FDA/ISO 13485 expectation)
#   Cpk >= 1.67  — highly capable process
#   Cpk <  1.00  — process is not capable; specification will be violated
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_capability.R <file_path> <column_name> <spec1> <spec2>",
    "Example (2-sided):",
    "  Rscript jrc_capability.R mydata.csv ForceN 8.0 12.0",
    "Example (1-sided lower):",
    "  Rscript jrc_capability.R mydata.csv ForceN 8.0 -",
    sep = "\n"
  ))
}

file_path <- args[1]
input_col <- args[2]
col       <- make.names(input_col)
spec1_raw <- suppressWarnings(as.double(args[3]))
spec2_raw <- suppressWarnings(as.double(args[4]))

has_spec1 <- !is.na(spec1_raw)
has_spec2 <- !is.na(spec2_raw)

if (!file.exists(file_path)) {
  stop(paste("File not found:", file_path))
}
if (!has_spec1 && !has_spec2) {
  stop("Both spec1 and spec2 are '-'. At least one numeric spec limit must be provided.")
}
if (args[3] != "-" && !has_spec1) {
  stop(paste("'spec1' must be a numeric value or '-'. Got:", args[3]))
}
if (args[4] != "-" && !has_spec2) {
  stop(paste("'spec2' must be a numeric value or '-'. Got:", args[4]))
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
n_bad <- sum(is.na(x_raw) | !is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed before analysis."))
}
x <- x_raw[is.finite(x_raw) & !is.na(x_raw)]
N <- length(x)

if (N < 4) {
  stop(paste("At least 4 valid observations are required for capability analysis. Got:", N))
}

# ---------------------------------------------------------------------------
# Capability calculations
# ---------------------------------------------------------------------------

x_mean <- mean(x)
x_sd   <- sd(x)        # overall SD (n-1 denominator)
conf   <- 0.95         # confidence level for CIs

# Chi-squared based CI for sigma:
# sigma_lower = sd * sqrt((N-1) / qchisq(1 - (1-conf)/2, N-1))
# sigma_upper = sd * sqrt((N-1) / qchisq(    (1-conf)/2, N-1))
chi2_lower <- qchisq((1 - conf) / 2, df = N - 1)
chi2_upper <- qchisq(1 - (1 - conf) / 2, df = N - 1)
sd_lower   <- x_sd * sqrt((N - 1) / chi2_upper)
sd_upper   <- x_sd * sqrt((N - 1) / chi2_lower)

# Cp / Pp (spread only — requires both spec limits)
if (two_sided) {
  cp  <- (spec2_raw - spec1_raw) / (6 * x_sd)
  cp_lower <- (spec2_raw - spec1_raw) / (6 * sd_upper)
  cp_upper <- (spec2_raw - spec1_raw) / (6 * sd_lower)
} else {
  cp  <- NA
  cp_lower <- NA
  cp_upper <- NA
}

# Cpk / Ppk (centring-aware)
if (two_sided) {
  cpu <- (spec2_raw - x_mean) / (3 * x_sd)
  cpl <- (x_mean - spec1_raw) / (3 * x_sd)
  cpk <- min(cpu, cpl)
} else if (lower_only) {
  cpl <- (x_mean - spec1_raw) / (3 * x_sd)
  cpu <- NA
  cpk <- cpl
} else {
  cpu <- (spec2_raw - x_mean) / (3 * x_sd)
  cpl <- NA
  cpk <- cpu
}

# Cpk CI using the approximation from Bissell (1990):
# SE(Cpk) ≈ sqrt(1/(9*N*Cpk^2) + 1/(2*(N-1)))
# CI: Cpk +/- z * SE(Cpk)
z <- qnorm(1 - (1 - conf) / 2)
if (!is.na(cpk) && cpk > 0) {
  se_cpk    <- sqrt(1 / (9 * N * cpk^2) + 1 / (2 * (N - 1)))
  cpk_lower <- cpk - z * se_cpk
  cpk_upper <- cpk + z * se_cpk
} else {
  cpk_lower <- NA
  cpk_upper <- NA
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

message(" ")
message("✅ Process Capability Analysis")
message("   version: 1.0, author: Joep Rous")
message("   ================================")
message(paste("   file:                          ", file_path))
message(paste("   column:                        ", input_col))
message(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
message(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
message(paste("   valid observations (N):        ", N))
message(" ")
message("   Process statistics:")
message(paste("   mean:                          ", round(x_mean, 6)))
message(paste("   standard deviation (overall):  ", round(x_sd, 6)))
message(paste("   95% CI on sigma:               [", round(sd_lower, 6), ",",
              round(sd_upper, 6), "]"))
message(" ")

# ---------------------------------------------------------------------------
# Capability indices
# ---------------------------------------------------------------------------

message("   Capability indices (overall SD used for all indices):")
message(" ")
message("   -------------------------------------------------------")
message("    index    value     95% CI              interpretation")
message("   -------------------------------------------------------")

# Cp / Pp
if (!is.na(cp)) {
  interp_cp <- if (cp >= 1.67) "highly capable" else
               if (cp >= 1.33) "capable"        else
               if (cp >= 1.00) "marginal"       else "not capable"
  message(sprintf("    Cp/Pp    %6.4f    [%6.4f, %6.4f]    %s",
                  cp, cp_lower, cp_upper, interp_cp))
} else {
  message("    Cp/Pp    n/a       (requires both spec limits)")
}

# Cpk / Ppk
if (!is.na(cpk)) {
  interp_cpk <- if (cpk >= 1.67) "highly capable" else
                if (cpk >= 1.33) "capable"        else
                if (cpk >= 1.00) "marginal"       else "not capable"
  ci_str <- if (!is.na(cpk_lower)) sprintf("[%6.4f, %6.4f]", cpk_lower, cpk_upper) else "n/a"
  message(sprintf("    Cpk/Ppk  %6.4f    %-20s    %s", cpk, ci_str, interp_cpk))

  if (!is.na(cpl)) message(paste("    Cpl/Ppl  ", round(cpl, 4),
                                 "  (lower: distance from mean to LSL)"))
  if (!is.na(cpu)) message(paste("    Cpu/Ppu  ", round(cpu, 4),
                                 "  (upper: distance from mean to USL)"))
}

message("   -------------------------------------------------------")
message(" ")

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

if (!is.na(cpk)) {
  if (cpk >= 1.33) {
    message("✅ Process is capable (Cpk >= 1.33).")
  } else if (cpk >= 1.00) {
    message("⚠️  Process is marginally capable (1.00 <= Cpk < 1.33).")
    message("   Consider process improvement before verification testing.")
  } else {
    message("❌ Process is not capable (Cpk < 1.00).")
    message("   The specification will likely be violated. Design or process")
    message("   improvement is required before verification testing.")
  }
}

message(" ")
message("   Note:")
message("   Cp and Cpk traditionally use a within-subgroup SD estimate.")
message("   Since no subgroup structure is available, the overall sample SD")
message("   is used for all indices. Cp == Pp and Cpk == Ppk numerically.")
message("   If subgroup data is available, consider dedicated SPC software.")
message(" ")
