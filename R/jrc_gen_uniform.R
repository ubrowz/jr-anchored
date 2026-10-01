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

seed_part <- if (!is.na(seed_arg)) paste0("_seed", seed_arg) else ""
filename  <- paste0(
  "uniform",
  "_n",   n,
  "_min", jr_fmt_num(min_value),
  "_max", jr_fmt_num(max_value),
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

jr_say(" ")
jr_say("✅ Uniform Distribution Dataset Generated")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ==========================================")
jr_say(paste("   n:                  ", n))
jr_say(paste("   min:                ", min_value))
jr_say(paste("   max:                ", max_value))
jr_say(paste("   seed:               ", if (!is.na(seed_arg)) seed_arg else "none (non-reproducible)"))
jr_say(paste("   output file:        ", output_path))
jr_say(" ")
jr_say("   Sample statistics (generated data):")
jr_say(paste("   sample mean:        ", round(mean(values), 6)))
jr_say(paste("   sample sd:          ", round(sd(values), 6)))
jr_say(paste("   min:                ", round(min(values), 6)))
jr_say(paste("   max:                ", round(max(values), 6)))
jr_say(" ")
jr_say("   Column 'id' is used as row names when read by jrc_ss_attr")
jr_say("   and related scripts. Use column name 'value' as the data column.")
jr_say(" ")
jr_log_output_hashes(c(output_path))
