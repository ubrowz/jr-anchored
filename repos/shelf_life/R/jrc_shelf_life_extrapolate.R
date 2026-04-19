#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_extrapolate.R <model.csv> <target_time>
#
# model.csv     Model coefficient CSV produced by jrc_shelf_life_linear.
#               Contains intercept, slope, residual SE, and study metadata.
# target_time   The time point at which to project the value (numeric).
#               Must be in the same unit as the original stability study.
#
# Needs only base R — no external libraries required.
#
# Projects the mean value and its confidence interval to a target time point
# using the linear model fitted by jrc_shelf_life_linear. The confidence
# level is read from the model file (set when jrc_shelf_life_linear was run).
#
# Extrapolation warnings per ICH Q1E guidance:
#   ⚠️  Target time > 50% beyond last observation — confidence bounds are
#       wide; consider collecting additional data.
#   ❌  Target time > 100% beyond last observation — extrapolation is too
#       speculative to support a regulatory submission. Script exits with
#       code 1.
#
# Both thresholds are documented in the help file as design decisions.
#
# Author: Joep Rous
# Version: 1.1

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_extrapolate <model.csv> <target_time>\n\n")
  cat("  model.csv     Output of jrc_shelf_life_linear (*_model.csv)\n")
  cat("  target_time   Time point to project to (same unit as original study)\n\n")
  cat("Example: jrc_shelf_life_extrapolate 20260418_model.csv 36\n\n")
  quit(status = 0)
}

if (length(args) < 2) {
  stop("Not enough arguments. Usage: jrc_shelf_life_extrapolate <model.csv> <target_time>")
}

model_file  <- args[1]
target_time <- suppressWarnings(as.numeric(args[2]))

if (!file.exists(model_file)) {
  stop(paste("\u274c Model file not found:", model_file))
}
if (is.na(target_time) || target_time < 0) {
  stop(paste("\u274c 'target_time' must be a non-negative number. Got:", args[2]))
}

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

# ---------------------------------------------------------------------------
# Parse model CSV
# ---------------------------------------------------------------------------

model_df <- tryCatch(
  read.csv(model_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read model file:", e$message))
)

if (!all(c("parameter", "value") %in% tolower(names(model_df)))) {
  stop("\u274c Model file must have columns 'parameter' and 'value'.")
}
names(model_df) <- tolower(names(model_df))

get_param <- function(name) {
  row <- model_df[model_df$parameter == name, "value"]
  if (length(row) == 0 || is.na(row[1]) || nchar(trimws(row[1])) == 0) {
    stop(paste("\u274c Required parameter missing from model file:", name))
  }
  row[1]
}

# Verify this is a jrc_shelf_life_linear model file
script_id <- get_param("script")
if (!grepl("jrc_shelf_life_linear", script_id)) {
  stop(paste("\u274c Model file does not appear to be from jrc_shelf_life_linear.",
             "Got script:", script_id))
}

b0         <- as.numeric(get_param("intercept"))
b1         <- as.numeric(get_param("slope"))
sigma      <- as.numeric(get_param("se_residual"))
n          <- as.numeric(get_param("n"))
t_bar      <- as.numeric(get_param("t_bar"))
Sxx        <- as.numeric(get_param("Sxx"))
last_time  <- as.numeric(get_param("last_time"))
spec_limit <- as.numeric(get_param("spec_limit"))
confidence <- as.numeric(get_param("confidence"))
direction  <- get_param("direction")
transform  <- tryCatch(get_param("transform"), error = function(e) "none")
if (!transform %in% c("none", "log")) transform <- "none"
source_f   <- get_param("source_file")
run_ts     <- get_param("run_timestamp")

for (nm in c("b0", "b1", "sigma", "n", "t_bar", "Sxx", "last_time",
             "spec_limit", "confidence")) {
  if (is.na(get(nm))) stop(paste("\u274c Non-numeric value for parameter:", nm))
}
if (!direction %in% c("low", "high")) {
  stop(paste("\u274c Unrecognised direction in model file:", direction))
}

df_res <- n - 2

# ---------------------------------------------------------------------------
# Extrapolation distance check
# ---------------------------------------------------------------------------

extrap_frac <- (target_time - last_time) / last_time

if (extrap_frac > 1.0) {
  cat("\u274c Extrapolation rejected.\n\n")
  cat(sprintf("  Target time (%g) is %.0f%% beyond the last observation (%g).\n",
              target_time, extrap_frac * 100, last_time))
  cat("  Extrapolation beyond 100% of the last observed time point is\n")
  cat("  too speculative to be scientifically defensible for a\n")
  cat("  regulatory submission. Conduct additional real-time or accelerated\n")
  cat("  ageing studies to support a longer shelf life claim.\n\n")
  quit(status = 1)
}

extrap_warning <- extrap_frac > 0.5

# ---------------------------------------------------------------------------
# Confidence interval calculation
# ---------------------------------------------------------------------------

t_crit   <- qt((1 + confidence) / 2, df = df_res)
fit_val  <- b0 + b1 * target_time
se_mean  <- sigma * sqrt(1 / n + (target_time - t_bar)^2 / Sxx)
margin   <- t_crit * se_mean

ci_lo    <- fit_val - margin
ci_hi    <- fit_val + margin

if (transform == "log") {
  fit_val <- exp(fit_val)
  ci_lo   <- exp(ci_lo)
  ci_hi   <- exp(ci_hi)
}

ci_bound <- if (direction == "low") ci_lo else ci_hi
spec_ok  <- if (direction == "low") ci_bound >= spec_limit else ci_bound <= spec_limit

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

ci_pct       <- sprintf("%.0f%%", confidence * 100)
bound_label  <- if (direction == "low") "Lower" else "Upper"

cat("\n")
cat("=================================================================\n")
cat("  Shelf Life Extrapolation\n")
cat(sprintf("  Model from: %s\n", basename(model_file)))
cat("=================================================================\n\n")

cat(sprintf("  Source study:     %s\n",   source_f))
cat(sprintf("  Model fitted:     %s\n",   run_ts))
cat(sprintf("  Intercept:        %.5f\n", b0))
cat(sprintf("  Slope:            %.5f\n", b1))
cat(sprintf("  Residual SE:      %.5f\n", sigma))
cat(sprintf("  n:                %d\n",   as.integer(n)))
cat(sprintf("  Last observation: %g\n",   last_time))
cat(sprintf("  Spec limit:       %g  (%s)\n", spec_limit,
            if (direction == "low") "lower bound" else "upper bound"))
cat(sprintf("  Transform:        %s\n\n",
            if (transform == "log") "log  (CI back-transformed via exp)" else "none"))

if (extrap_warning) {
  extrap_pct <- round(extrap_frac * 100)
  cat(sprintf("\u26a0\ufe0f  Target (%g) is %d%% beyond the last observation (%g).\n",
              target_time, extrap_pct, last_time))
  cat("   Confidence bounds are wide at this distance. Consider\n")
  cat("   additional real-time confirmation data before use in\n")
  cat("   a regulatory submission.\n\n")
}

cat("--- Projection --------------------------------------------------\n")
cat(sprintf("  Target time:      %g\n",     target_time))
cat(sprintf("  Fitted value:     %.5f\n",   fit_val))
cat(sprintf("  %s %s CI:   [%.5f,  %.5f]\n", ci_pct, "CI", ci_lo, ci_hi))
cat(sprintf("  %s %s CI bound: %.5f\n\n",   bound_label, ci_pct, ci_bound))

if (spec_ok) {
  cat(sprintf("  \u2705 %s %s CI bound (%.5f) is %s spec limit (%g).\n",
              bound_label, ci_pct, ci_bound,
              if (direction == "low") "above" else "below",
              spec_limit))
  cat("   The stability claim is supported at this time point.\n")
} else {
  cat(sprintf("  \u274c %s %s CI bound (%.5f) has crossed the spec limit (%g).\n",
              bound_label, ci_pct, ci_bound, spec_limit))
  cat("   The stability claim is NOT supported at this time point.\n")
}
cat("=================================================================\n\n")

cat("\u2705 Done.\n")
