#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_q10.R <q10> <accel_temp> <real_temp> <accel_time>
#
# q10          Q10 coefficient — factor by which reaction rate increases per 10°C
#              rise in temperature. ASTM F1980 default is 2.0. Typical range: 1.5-3.0.
# accel_temp   Accelerated storage temperature (degrees C).
# real_temp    Intended real-time storage temperature (degrees C).
# accel_time   Duration in accelerated conditions (any consistent unit: days, months).
#
# Needs only base R — no external libraries required.
#
# Computes the real-time equivalent of an accelerated ageing study per ASTM F1980.
#   AF = Q10 ^ ((T_accel - T_real) / 10)
#   real_time = accel_time x AF
#
# Also reports sensitivity to Q10 +/- 0.5 so the engineer can bracket uncertainty
# in the Q10 value.
#
# Reference:
#   ASTM F1980-21, Standard Guide for Accelerated Aging of Sterile Barrier Systems
#   for Medical Devices, ASTM International.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Argument validation (before renv — argument errors surface immediately)
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_q10 <q10> <accel_temp> <real_temp> <accel_time>\n\n")
  cat("  q10          Q10 coefficient (ASTM F1980 default: 2.0; typical range 1.5-3.0)\n")
  cat("  accel_temp   Accelerated storage temperature (degrees C)\n")
  cat("  real_temp    Real-time storage temperature (degrees C)\n")
  cat("  accel_time   Duration of accelerated ageing (any consistent time unit)\n\n")
  cat("Example: jrc_shelf_life_q10 2.0 55 25 26\n\n")
  quit(status = 0)
}

if (length(args) < 4) {
  stop("Not enough arguments. Usage: jrc_shelf_life_q10 <q10> <accel_temp> <real_temp> <accel_time>")
}

q10        <- suppressWarnings(as.numeric(args[1]))
accel_temp <- suppressWarnings(as.numeric(args[2]))
real_temp  <- suppressWarnings(as.numeric(args[3]))
accel_time <- suppressWarnings(as.numeric(args[4]))

if (is.na(q10) || q10 <= 0) {
  stop(paste("\u274c 'q10' must be a positive number. Got:", args[1]))
}
if (is.na(accel_temp)) {
  stop(paste("\u274c 'accel_temp' must be a number. Got:", args[2]))
}
if (is.na(real_temp)) {
  stop(paste("\u274c 'real_temp' must be a number. Got:", args[3]))
}
if (is.na(accel_time) || accel_time <= 0) {
  stop(paste("\u274c 'accel_time' must be a positive number. Got:", args[4]))
}
if (accel_temp <= real_temp) {
  stop(sprintf(
    "\u274c Accelerated temperature (%g\u00b0C) must be higher than real-time temperature (%g\u00b0C).",
    accel_temp, real_temp
  ))
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
# Calculation
# ---------------------------------------------------------------------------

delta_t   <- accel_temp - real_temp
af        <- q10 ^ (delta_t / 10)
real_time <- accel_time * af

# Sensitivity bracket: Q10 +/- 0.5
q10_lo  <- max(q10 - 0.5, 0.01)
q10_hi  <- q10 + 0.5
af_lo   <- q10_lo ^ (delta_t / 10)
af_hi   <- q10_hi ^ (delta_t / 10)
rt_lo   <- accel_time * af_lo
rt_hi   <- accel_time * af_hi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Accelerated Ageing — Q10 Method  (ASTM F1980)\n")
cat("=================================================================\n\n")

cat(sprintf("  Q10 coefficient:          %.2f\n",     q10))
cat(sprintf("  Accelerated temperature:  %.1f \u00b0C\n",  accel_temp))
cat(sprintf("  Real-time temperature:    %.1f \u00b0C\n",  real_temp))
cat(sprintf("  Temperature difference:   %.1f \u00b0C\n",  delta_t))
cat(sprintf("  Accelerated ageing time:  %g\n",       accel_time))
cat("\n")
cat(sprintf("  Acceleration factor (AF): %.4f\n",     af))
cat(sprintf("  Real-time equivalent:     %.4f  (same unit as accel_time)\n\n", real_time))

if (q10 < 1.5 || q10 > 3.0) {
  cat(sprintf("\u26a0\ufe0f  Q10 = %.2f is outside the typical range (1.5-3.0) for medical device\n", q10))
  cat("   materials. ASTM F1980 recommends Q10 = 2.0 when experimental data\n")
  cat("   are not available. Justify this value in your ageing protocol.\n\n")
}

cat("--- Q10 Sensitivity (Q10 \u00b1 0.5) ----------------------------------\n")
cat(sprintf("  Q10 = %.1f  \u2192  AF = %6.3f  \u2192  real-time = %.4f\n", q10_lo, af_lo, rt_lo))
cat(sprintf("  Q10 = %.1f  \u2192  AF = %6.3f  \u2192  real-time = %.4f  (stated value)\n", q10, af, real_time))
cat(sprintf("  Q10 = %.1f  \u2192  AF = %6.3f  \u2192  real-time = %.4f\n", q10_hi, af_hi, rt_hi))
cat("\n")

cat("--- Notes -------------------------------------------------------\n")
cat("  \u2022 ASTM F1980 requires parallel real-time ageing to confirm\n")
cat("    accelerated ageing claims before shelf life labelling.\n")
cat("  \u2022 This calculation covers sterile barrier / packaging integrity.\n")
cat("    Device functionality, biocompatibility, and material stability\n")
cat("    require separate assessment and may not follow Q10 kinetics.\n")
cat("  \u2022 For biologics and drug-device combinations, use Arrhenius\n")
cat("    kinetics with experimentally derived activation energy.\n")
cat("=================================================================\n\n")

cat("\u2705 Done.\n")
