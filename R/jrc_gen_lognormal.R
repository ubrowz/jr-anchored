#!/usr/bin/env Rscript
#
# use as: Rscript jrc_gen_lognormal.R <n> <meanlog> <sdlog> <output_folder> [seed]
#
# "n"             number of observations to generate (positive integer)
# "meanlog"       mean of the log-normal distribution on the log scale (numeric)
# "sdlog"         standard deviation on the log scale (positive numeric)
# "output_folder" path to the folder where the CSV file will be written
# "seed"          optional random seed for reproducibility (positive integer)
#                 omit for a non-reproducible dataset
#
# Needs only base R — no external libraries required.
#
# Generates a synthetic log-normally distributed dataset and writes it to a CSV
# file in the specified output folder. All generated values are strictly positive, making this suitable for
# testing Box-Cox transformation in jrc_ss_attr and related scripts.
#
# The filename is auto-generated from
# the parameters:
#
#   lognormal_n<n>_meanlog<meanlog>_sdlog<sdlog>.csv          (no seed)
#   lognormal_n<n>_meanlog<meanlog>_sdlog<sdlog>_seed<s>.csv  (with seed)
#
# The CSV file has two columns:
#   id     — integer row identifier (1 to n)
#   value  — the generated numeric values
#
# The first column (id) is used as row names when read by jrc_ss_attr and
# related scripts, consistent with the expected CSV format.
#
# Intended use:
#   - Generate synthetic test datasets for OQ validation of jrc_ss_* scripts
#   - Generate pilot data for sample size calculations
#   - Explore the effect of mean and SD on required sample sizes
#
# Author: Joep Rous
# Version: 1.0

# Note: meanlog and sdlog are parameters of the underlying normal distribution
# (i.e. log(X) ~ N(meanlog, sdlog)). The resulting mean of X on the original
# scale is exp(meanlog + sdlog^2/2).

source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_gen_lognormal.R <n> <meanlog> <sdlog> <output_folder> [seed]",
    "Example (no seed):",
    "  Rscript jrc_gen_lognormal.R 30 0 0.5 /path/to/output",
    "Example (with seed):",
    "  Rscript jrc_gen_lognormal.R 30 0 0.5 /path/to/output 42",
    sep = "\n"
  ))
}

n             <- suppressWarnings(as.integer(args[1]))
meanlog_value <- suppressWarnings(as.double(args[2]))
sdlog_value   <- suppressWarnings(as.double(args[3]))
output_folder <- args[4]
seed_arg      <- if (length(args) >= 5) suppressWarnings(as.integer(args[5])) else NA

if (is.na(n) || n < 1) {
  stop(paste("'n' must be a positive integer. Got:", args[1]))
}
if (is.na(meanlog_value)) {
  stop(paste("'meanlog' must be a numeric value. Got:", args[2]))
}
if (is.na(sdlog_value) || sdlog_value <= 0) {
  stop(paste("'sdlog' must be a positive numeric value. Got:", args[3]))
}
if (!dir.exists(output_folder)) {
  stop(paste("Output folder not found:", output_folder))
}
if (length(args) >= 5 && is.na(seed_arg)) {
  stop(paste("'seed' must be a positive integer if specified. Got:", args[5]))
}

# ---------------------------------------------------------------------------
# Filename construction
# ---------------------------------------------------------------------------

# Format numbers for filename: remove trailing zeros but keep enough precision
fmt_num <- function(x) {
  s <- format(x, scientific = FALSE)
  # Remove trailing zeros after decimal point
  s <- sub("(\\.\\d*?)0+$", "\\1", s)
  # Remove trailing decimal point
  s <- sub("\\.$", "", s)
  s
}

seed_part <- if (!is.na(seed_arg)) paste0("_seed", seed_arg) else ""
filename  <- paste0(
  "lognormal",
  "_n",    n,
  "_meanlog", fmt_num(meanlog_value),
  "_sdlog",   fmt_num(sdlog_value),
  seed_part,
  ".csv"
)
output_path <- file.path(output_folder, filename)

# ---------------------------------------------------------------------------
# Data generation
# ---------------------------------------------------------------------------

if (!is.na(seed_arg)) {
  set.seed(seed_arg)
}

values <- rlnorm(n, meanlog = meanlog_value, sdlog = sdlog_value)

# ---------------------------------------------------------------------------
# Write CSV
# ---------------------------------------------------------------------------

df <- data.frame(id = seq_len(n), value = values)
write.table(df, file = output_path, sep = ",", dec = ".", row.names = FALSE,
            col.names = TRUE, quote = FALSE)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

message(" ")
message("✅ Log-Normal Distribution Dataset Generated")
message("   version: 1.0, author: Joep Rous")
message("   ========================================")
message(paste("   n:                  ", n))
message(paste("   meanlog:            ", meanlog_value))
message(paste("   sdlog:              ", sdlog_value))
message(paste("   seed:               ", if (!is.na(seed_arg)) seed_arg else "none (non-reproducible)"))
message(paste("   output file:        ", output_path))
message(" ")
message("   Sample statistics (generated data):")
message(paste("   sample mean:        ", round(mean(values), 6)))
message(paste("   sample sd:          ", round(sd(values), 6)))
message(paste("   min:                ", round(min(values), 6)))
message(paste("   max:                ", round(max(values), 6)))
message(" ")
message("   Column 'id' is used as row names when read by jrc_ss_attr")
message("   and related scripts. Use column name 'value' as the data column.")
message(" ")
jr_log_output_hashes(c(output_path))

