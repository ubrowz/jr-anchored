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
#   Cpk >= 1.33  — capable process (common industry benchmark)
#   Cpk >= 1.67  — highly capable process
#   Cpk <  1.00  — process is not capable; specification will be violated
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.0"   # single source for banner, report and JSON

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
n_bad <- sum(!is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed before analysis."))
}
x <- x_raw[is.finite(x_raw)]
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
# SE(Cpk) ≈ sqrt(1/(9*N) + Cpk^2/(2*(N-1)))
# CI: Cpk +/- z * SE(Cpk)
z <- qnorm(1 - (1 - conf) / 2)
if (!is.na(cpk) && cpk > 0) {
  se_cpk    <- sqrt(1 / (9 * N) + cpk^2 / (2 * (N - 1)))
  cpk_lower <- cpk - z * se_cpk
  cpk_upper <- cpk + z * se_cpk
} else {
  cpk_lower <- NA
  cpk_upper <- NA
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Process Capability Analysis")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ================================")
jr_say(paste("   file:                          ", file_path))
jr_say(paste("   column:                        ", input_col))
jr_say(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
jr_say(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
jr_say(paste("   valid observations (N):        ", N))
jr_say(" ")
jr_say("   Process statistics:")
jr_say(paste("   mean:                          ", round(x_mean, 6)))
jr_say(paste("   standard deviation (overall):  ", round(x_sd, 6)))
jr_say(paste("   95% CI on sigma:               [", round(sd_lower, 6), ",",
              round(sd_upper, 6), "]"))
jr_say(" ")

# ---------------------------------------------------------------------------
# Capability indices
# ---------------------------------------------------------------------------

jr_say("   Capability indices (overall SD used for all indices):")
jr_say(" ")
jr_say("   -------------------------------------------------------")
jr_say("    index    value     95% CI              interpretation")
jr_say("   -------------------------------------------------------")

# Cp / Pp
if (!is.na(cp)) {
  interp_cp <- if (cp >= 1.67) "highly capable" else
               if (cp >= 1.33) "capable"        else
               if (cp >= 1.00) "marginal"       else "not capable"
  jr_say(sprintf("    Cp/Pp    %6.4f    [%6.4f, %6.4f]    %s",
                  cp, cp_lower, cp_upper, interp_cp))
} else {
  jr_say("    Cp/Pp    n/a       (requires both spec limits)")
}

# Cpk / Ppk
if (!is.na(cpk)) {
  interp_cpk <- if (cpk >= 1.67) "highly capable" else
                if (cpk >= 1.33) "capable"        else
                if (cpk >= 1.00) "marginal"       else "not capable"
  ci_str <- if (!is.na(cpk_lower)) sprintf("[%6.4f, %6.4f]", cpk_lower, cpk_upper) else "n/a"
  jr_say(sprintf("    Cpk/Ppk  %6.4f    %-20s    %s", cpk, ci_str, interp_cpk))

  if (!is.na(cpl)) jr_say(paste("    Cpl/Ppl  ", round(cpl, 4),
                                 "  (lower: distance from mean to LSL)"))
  if (!is.na(cpu)) jr_say(paste("    Cpu/Ppu  ", round(cpu, 4),
                                 "  (upper: distance from mean to USL)"))
}

jr_say("   -------------------------------------------------------")
jr_say(" ")

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

if (!is.na(cpk)) {
  if (cpk >= 1.33) {
    jr_say("✅ Process is capable (Cpk >= 1.33).")
  } else if (cpk >= 1.00) {
    jr_say("⚠️  Process is marginally capable (1.00 <= Cpk < 1.33).")
    jr_say("   Consider process improvement before verification testing.")
  } else {
    jr_say("❌ Process is not capable (Cpk < 1.00).")
    jr_say("   The specification will likely be violated. Design or process")
    jr_say("   improvement is required before verification testing.")
  }
}

jr_say(" ")
jr_say("   Note:")
jr_say("   Cp and Cpk traditionally use a within-subgroup SD estimate.")
jr_say("   Since no subgroup structure is available, the overall sample SD")
jr_say("   is used for all indices. Cp == Pp and Cpk == Ppk numerically.")
jr_say("   If subgroup data is available, consider dedicated SPC software.")
jr_say(" ")
