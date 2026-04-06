#!/usr/bin/env Rscript
#
# use as: Rscript jrc_gen_uniform.R <n> <min> <max> <output_folder> [seed]
#
# "n"             number of observations to generate (positive integer)
# "min"           lower bound of the uniform distribution (numeric)
# "max"           upper bound of the uniform distribution (numeric, max > min)
# "output_folder" path to the folder where the CSV file will be written
# "seed"          optional random seed for reproducibility (positive integer)
#                 omit for a non-reproducible dataset
#
# Needs only base R — no external libraries required.
#
# Generates a synthetic uniformly distributed dataset and writes it to a CSV
# file in the specified output folder. The filename is auto-generated from
# the parameters:
#
#   uniform_n<n>_min<min>_max<max>.csv          (no seed)
#   uniform_n<n>_min<min>_max<max>_seed<s>.csv  (with seed)
#
# The CSV file has two columns:
#   id     — integer row identifier (1 to n)
#   value  — the generated numeric values
#
# The first column (id) is used as row names when read by jrc_ss_attr and
# related scripts, consistent with the expected CSV format.
#
# Uniform data is useful for testing edge cases in normality checks and
# Box-Cox transformation logic, since uniform distributions have bounded
# support and negative excess kurtosis.
#
# Author: Joep Rous
# Version: 1.0

source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_gen_uniform.R <n> <min> <max> <output_folder> [seed]",
    "Example (no seed):",
    "  Rscript jrc_gen_uniform.R 30 0.0 1.0 /path/to/output",
    "Example (with seed):",
    "  Rscript jrc_gen_uniform.R 30 0.0 1.0 /path/to/output 42",
    sep = "\n"
  ))
}

n             <- suppressWarnings(as.integer(args[1]))
min_value     <- suppressWarnings(as.double(args[2]))
max_value     <- suppressWarnings(as.double(args[3]))
output_folder <- args[4]
seed_arg      <- if (length(args) >= 5) suppressWarnings(as.integer(args[5])) else NA

if (is.na(n) || n < 1) {
  stop(paste("'n' must be a positive integer. Got:", args[1]))
}
if (is.na(min_value)) {
  stop(paste("'min' must be a numeric value. Got:", args[2]))
}
if (is.na(max_value)) {
  stop(paste("'max' must be a numeric value. Got:", args[3]))
}
if (max_value <= min_value) {
  stop(paste("'max' must be greater than 'min'. Got min =", min_value,
             "and max =", max_value))
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

fmt_num <- function(x) {
  s <- format(x, scientific = FALSE)
  s <- sub("(\\.\\d*?)0+$", "\\1", s)
  s <- sub("\\.$", "", s)
  s
}

seed_part <- if (!is.na(seed_arg)) paste0("_seed", seed_arg) else ""
filename  <- paste0(
  "uniform",
  "_n",   n,
  "_min", fmt_num(min_value),
  "_max", fmt_num(max_value),
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

values <- runif(n, min = min_value, max = max_value)

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
message("✅ Uniform Distribution Dataset Generated")
message("   version: 1.0, author: Joep Rous")
message("   ==========================================")
message(paste("   n:                  ", n))
message(paste("   min:                ", min_value))
message(paste("   max:                ", max_value))
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
