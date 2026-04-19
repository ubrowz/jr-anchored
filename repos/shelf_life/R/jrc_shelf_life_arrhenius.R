#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_arrhenius.R <accel_temp> <real_temp>
#                                             <activation_energy> <accel_time>
#                                             [--unit C|K]
#
# accel_temp          Accelerated storage temperature.
# real_temp           Intended real-time storage temperature.
# activation_energy   Activation energy (Ea) in kcal/mol. Typical range: 10-25 kcal/mol.
#                     Use experimentally derived value where available; 12-15 kcal/mol
#                     is a common conservative default for polymeric device materials.
# accel_time          Duration in accelerated conditions (any consistent time unit).
# --unit C|K          Temperature unit: C = Celsius (default), K = Kelvin.
#
# Needs only base R — no external libraries required.
#
# Computes the real-time equivalent of an accelerated ageing study using
# Arrhenius kinetics:
#   AF = exp( Ea/R * (1/T_real - 1/T_accel) )
#   real_time = accel_time x AF
# where temperatures are in Kelvin and R = 1.987 cal/(mol*K).
#
# Also reports sensitivity to activation energy +/- 2 kcal/mol.
#
# References:
#   ISO 11607-1:2019, Packaging for terminally sterilized medical devices.
#   ICH Q1E, Evaluation for Stability Data, 2003.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_arrhenius <accel_temp> <real_temp> <activation_energy> <accel_time> [--unit C|K]\n\n")
  cat("  accel_temp         Accelerated temperature\n")
  cat("  real_temp          Real-time temperature\n")
  cat("  activation_energy  Ea in kcal/mol (typical 10-25; default assumption 12-15)\n")
  cat("  accel_time         Duration of accelerated ageing (any consistent time unit)\n")
  cat("  --unit C|K         Temperature unit (default: C)\n\n")
  cat("Example: jrc_shelf_life_arrhenius 55 25 17.0 26\n\n")
  quit(status = 0)
}

# Parse --unit flag
temp_unit <- "C"
clean_args <- c()
i <- 1
while (i <= length(args)) {
  if (args[i] == "--unit" && i < length(args)) {
    temp_unit <- toupper(args[i + 1])
    if (!temp_unit %in% c("C", "K")) {
      stop(paste("\u274c --unit must be 'C' or 'K'. Got:", args[i + 1]))
    }
    i <- i + 2
  } else {
    clean_args <- c(clean_args, args[i])
    i <- i + 1
  }
}

if (length(clean_args) < 4) {
  stop("Not enough arguments. Usage: jrc_shelf_life_arrhenius <accel_temp> <real_temp> <activation_energy> <accel_time> [--unit C|K]")
}

accel_temp_raw <- suppressWarnings(as.numeric(clean_args[1]))
real_temp_raw  <- suppressWarnings(as.numeric(clean_args[2]))
ea             <- suppressWarnings(as.numeric(clean_args[3]))
accel_time     <- suppressWarnings(as.numeric(clean_args[4]))

if (is.na(accel_temp_raw)) stop(paste("\u274c 'accel_temp' must be a number. Got:", clean_args[1]))
if (is.na(real_temp_raw))  stop(paste("\u274c 'real_temp' must be a number. Got:",  clean_args[2]))
if (is.na(ea) || ea <= 0)  stop(paste("\u274c 'activation_energy' must be a positive number. Got:", clean_args[3]))
if (is.na(accel_time) || accel_time <= 0) stop(paste("\u274c 'accel_time' must be a positive number. Got:", clean_args[4]))

# Convert to Kelvin
K_OFFSET <- 273.15
if (temp_unit == "C") {
  T_accel <- accel_temp_raw + K_OFFSET
  T_real  <- real_temp_raw  + K_OFFSET
} else {
  T_accel <- accel_temp_raw
  T_real  <- real_temp_raw
  if (T_accel < 200 || T_real < 200) {
    stop("\u274c Temperatures in Kelvin must be > 200 K. Check --unit flag.")
  }
}

if (T_accel <= T_real) {
  stop(sprintf(
    "\u274c Accelerated temperature must be higher than real-time temperature.\n   Got: accel=%g, real=%g (%s)",
    accel_temp_raw, real_temp_raw, temp_unit
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

R_GAS <- 1.987e-3  # kcal / (mol * K)

arrhenius_af <- function(ea_val, T_a, T_r) {
  exp(ea_val / R_GAS * (1 / T_r - 1 / T_a))
}

af        <- arrhenius_af(ea, T_accel, T_real)
real_time <- accel_time * af

# Sensitivity: Ea +/- 2 kcal/mol
ea_lo <- max(ea - 2, 0.01)
ea_hi <- ea + 2
af_lo <- arrhenius_af(ea_lo, T_accel, T_real)
af_hi <- arrhenius_af(ea_hi, T_accel, T_real)
rt_lo <- accel_time * af_lo
rt_hi <- accel_time * af_hi

# Display temperatures
if (temp_unit == "C") {
  t_accel_disp <- sprintf("%.1f \u00b0C  (%.2f K)", accel_temp_raw, T_accel)
  t_real_disp  <- sprintf("%.1f \u00b0C  (%.2f K)", real_temp_raw,  T_real)
} else {
  t_accel_disp <- sprintf("%.2f K", T_accel)
  t_real_disp  <- sprintf("%.2f K", T_real)
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Accelerated Ageing — Arrhenius Method  (ISO 11607 / ICH Q1E)\n")
cat("=================================================================\n\n")

cat(sprintf("  Accelerated temperature:  %s\n",   t_accel_disp))
cat(sprintf("  Real-time temperature:    %s\n",   t_real_disp))
cat(sprintf("  Activation energy (Ea):   %.2f kcal/mol\n", ea))
cat(sprintf("  Accelerated ageing time:  %g\n",   accel_time))
cat("\n")
cat(sprintf("  Acceleration factor (AF): %.4f\n",  af))
cat(sprintf("  Real-time equivalent:     %.4f  (same unit as accel_time)\n\n", real_time))

if (ea < 10 || ea > 25) {
  cat(sprintf("\u26a0\ufe0f  Ea = %.1f kcal/mol is outside the typical range (10-25 kcal/mol)\n", ea))
  cat("   for polymeric medical device materials. Verify with experimental\n")
  cat("   degradation data and document justification.\n\n")
}

cat("--- Ea Sensitivity (Ea \u00b1 2 kcal/mol) ----------------------------\n")
cat(sprintf("  Ea = %5.1f  \u2192  AF = %7.3f  \u2192  real-time = %.4f\n", ea_lo, af_lo, rt_lo))
cat(sprintf("  Ea = %5.1f  \u2192  AF = %7.3f  \u2192  real-time = %.4f  (stated value)\n", ea, af, real_time))
cat(sprintf("  Ea = %5.1f  \u2192  AF = %7.3f  \u2192  real-time = %.4f\n", ea_hi, af_hi, rt_hi))
cat("\n")

cat("--- Notes -------------------------------------------------------\n")
cat("  \u2022 Arrhenius kinetics assume a single dominant degradation mechanism.\n")
cat("    Multi-mechanism degradation (e.g. hydrolysis + oxidation) may\n")
cat("    require separate treatment.\n")
cat("  \u2022 ISO 11607 and ICH Q1E both require real-time confirmation studies.\n")
cat("  \u2022 For sterile barrier / packaging integrity, Q10 method (ASTM F1980)\n")
cat("    is also acceptable and may be simpler to justify.\n")
cat("=================================================================\n\n")

cat("\u2705 Done.\n")
