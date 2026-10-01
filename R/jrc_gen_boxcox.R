#!/usr/bin/env Rscript
#
# use as: Rscript jrc_gen_boxcox.R <n> <shape> <scale> <output_folder> [seed]
#
# "n"             number of observations to generate (positive integer)
# "shape"         shape parameter of the Weibull distribution (positive numeric)
#               shape < 1: heavy right skew; shape = 1: exponential;
#               shape > 1: less skewed; shape ~3.6: approximately normal
# "scale"         scale parameter of the Weibull distribution (positive numeric)
#               Controls the magnitude of the generated values
# "output_folder" path to the folder where the CSV file will be written
# "seed"          optional random seed for reproducibility (positive integer)
#                 omit for a non-reproducible dataset
#
# Needs only base R — no external libraries required.
#
# Generates a synthetic right-skewed dataset from a Weibull distribution,
# suitable for testing Box-Cox transformation in jrc_ss_attr and related
# scripts. All values are strictly positive. The Weibull distribution is
# commonly used in reliability and lifetime data analysis and writes it to a CSV
# file in the specified output folder. The filename is auto-generated from
# the parameters:
#
#   boxcox_n<n>_shape<shape>_scale<scale>.csv          (no seed)
#   boxcox_n<n>_shape<shape>_scale<scale>_seed<s>.csv  (with seed)
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
    "  Rscript jrc_gen_boxcox.R <n> <shape> <scale> <output_folder> [seed]",
    "Example (no seed):",
    "  Rscript jrc_gen_boxcox.R 30 1.5 0.05 /path/to/output",
    "Example (with seed):",
    "  Rscript jrc_gen_boxcox.R 30 1.5 0.05 /path/to/output 42",
    sep = "\n"
  ))
}

n             <- suppressWarnings(as.integer(args[1]))
shape_value   <- suppressWarnings(as.double(args[2]))
scale_value   <- suppressWarnings(as.double(args[3]))
output_folder <- args[4]
seed_arg      <- if (length(args) >= 5) suppressWarnings(as.integer(args[5])) else NA

if (is.na(n) || n < 1) {
  stop(paste("'n' must be a positive integer. Got:", args[1]))
}
if (is.na(shape_value) || shape_value <= 0) {
  stop(paste("'shape' must be a positive numeric value. Got:", args[2]))
}
if (is.na(scale_value) || scale_value <= 0) {
  stop(paste("'scale' must be a positive numeric value. Got:", args[3]))
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
  "boxcox",
  "_n",    n,
  "_shape", jr_fmt_num(shape_value),
  "_scale", jr_fmt_num(scale_value),
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

values <- rweibull(n, shape = shape_value, scale = scale_value)

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
jr_say("✅ Box-Cox-Transformable Dataset Generated")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ========================================")
jr_say(paste("   n:                  ", n))
jr_say(paste("   shape (Weibull):    ", shape_value))
jr_say(paste("   scale (Weibull):    ", scale_value))
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

