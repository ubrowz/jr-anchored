#!/usr/bin/env Rscript
#
# use as: Rscript jrc_rdt_verify.R <data.csv> --reliability R --confidence C --target_life T [options]
#
# data.csv    CSV with at least a time column and a status column (0=survived, 1=failed).
#
# Evaluates whether a pre-specified reliability claim is demonstrated by actual
# test results. Two methods are always reported:
#
#   Binomial (Clopper-Pearson): no Weibull shape assumption. Counts units that
#   failed at or before target_life as failures; all others as suspensions.
#
#   Weibayes (--beta required): uses accumulated Weibull time from all units.
#   Failures at or before target_life count toward k; all units contribute their
#   actual effective time to the Weibayes sum.
#
# Verdict exits 0 for both PASS and FAIL. Non-zero exit is reserved for input
# errors and runtime failures.
#
# Core formulas:
#   Binomial:  R_lower = 1 - qbeta(C, k+1, n-k)            [Clopper-Pearson]
#   Weibayes:  R_demo  = exp( -target_life^beta * qchisq(C, 2*(k+1)) / (2*T*) )
#              where T* = sum(t_eff_i ^ beta) over all n units
#
# Needs only base R and ggplot2 (already pinned).
#
# References:
#   Meeker, Hahn & Escobar (2017). Statistical Intervals, 2nd ed. Wiley. Ch. 8.
#   Nelson (2004). Accelerated Testing. Wiley.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Helpers (before renv)
# ---------------------------------------------------------------------------

parse_flag <- function(args, flag, default = NA, numeric = FALSE) {
  idx <- which(args == flag)
  if (length(idx) == 0) return(default)
  if (idx[1] >= length(args)) stop(paste(flag, "requires a value."))
  val <- args[idx[1] + 1]
  if (numeric) {
    num <- suppressWarnings(as.numeric(val))
    if (is.na(num)) stop(paste0(flag, " must be numeric. Got: ", val))
    return(num)
  }
  val
}

flag_present <- function(args, flag) flag %in% args

# ---------------------------------------------------------------------------
# Argument parsing (before renv)
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || flag_present(args, "--help") || flag_present(args, "-h")) {
  cat("\nUsage: jrc_rdt_verify <data.csv> --reliability R --confidence C --target_life T [options]\n\n")
  cat("Required:\n")
  cat("  data.csv            Path to CSV file with test results\n")
  cat("  --reliability R     Reliability claimed in the test plan (e.g. 0.95)\n")
  cat("  --confidence C      Confidence level from the test plan (e.g. 0.90)\n")
  cat("  --target_life T     Life at which reliability was claimed (e.g. 5000)\n\n")
  cat("Optional:\n")
  cat("  --time_col NAME     Column name for test times (default: \"time\")\n")
  cat("  --status_col NAME   Column name for event indicator (default: \"status\")\n")
  cat("                      0 = survived / right-censored, 1 = failed\n")
  cat("  --beta B            Weibull shape parameter. Enables Weibayes evaluation.\n")
  cat("                      Must match the value used in jrc_rdt_plan.\n")
  cat("  --accel_factor AF   Life-extension multiplier used in the test (default: 1.0)\n")
  cat("                      t_eff = time * accel_factor for each unit.\n")
  cat("                      Must match the value used in jrc_rdt_plan.\n\n")
  cat("CSV format:\n")
  cat("  unit_id,time,status\n")
  cat("  1,5000,0\n")
  cat("  2,4850,1\n")
  cat("  ...\n\n")
  cat("Example:\n")
  cat("  jrc_rdt_verify results.csv --reliability 0.95 --confidence 0.90 --target_life 5000\n")
  cat("  jrc_rdt_verify results.csv --reliability 0.95 --confidence 0.90 --target_life 5000 --beta 2.0\n\n")
  quit(status = 0)
}

# First non-flag argument is the CSV path
non_flag_args <- args[!startsWith(args, "--") & !startsWith(args, "-")]
flag_values   <- grep("^-", args)
# Remove values that follow a flag (they belong to the flag, not positional)
positional <- c()
skip_next  <- FALSE
for (i in seq_along(args)) {
  if (skip_next) { skip_next <- FALSE; next }
  if (startsWith(args[i], "-")) { skip_next <- TRUE; next }
  positional <- c(positional, args[i])
}

if (length(positional) == 0) stop("CSV file path is required as the first argument.")
file_path <- positional[1]

reliability  <- parse_flag(args, "--reliability",  NA,  numeric = TRUE)
confidence   <- parse_flag(args, "--confidence",   NA,  numeric = TRUE)
target_life  <- parse_flag(args, "--target_life",  NA,  numeric = TRUE)
time_col     <- parse_flag(args, "--time_col",     "time")
status_col   <- parse_flag(args, "--status_col",   "status")
beta         <- parse_flag(args, "--beta",         NA,  numeric = TRUE)
accel_factor <- parse_flag(args, "--accel_factor", 1.0, numeric = TRUE)

if (is.na(reliability)) stop("--reliability is required.")
if (is.na(confidence))  stop("--confidence is required.")
if (is.na(target_life)) stop("--target_life is required.")

if (reliability <= 0 || reliability >= 1)
  stop(paste("--reliability must be strictly between 0 and 1. Got:", reliability))
if (confidence <= 0 || confidence >= 1)
  stop(paste("--confidence must be strictly between 0 and 1. Got:", confidence))
if (target_life <= 0)
  stop(paste("--target_life must be > 0. Got:", target_life))
if (!is.na(beta) && beta <= 0)
  stop(paste("--beta must be > 0. Got:", beta))
if (accel_factor < 1.0)
  stop(paste("--accel_factor must be >= 1.0. Got:", accel_factor))
if (!file.exists(file_path))
  stop(paste("File not found:", file_path))

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

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})

# ---------------------------------------------------------------------------
# Style constants
# ---------------------------------------------------------------------------

BG        <- "#FFFFFF"
CLR_PASS  <- "#2166AC"
CLR_FAIL  <- "#D6604D"
CLR_CLAIM <- "#555555"
CLR_SURV  <- "#4393C3"
CLR_FAIL2 <- "#D6604D"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    plot.title       = element_text(size = 10, face = "bold"),
    plot.subtitle    = element_text(size = 8, color = "#555555"),
    axis.title       = element_text(size = 9),
    axis.text        = element_text(size = 8)
  )

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

dat <- tryCatch(
  read.csv(file_path, stringsAsFactors = FALSE),
  error = function(e) stop(paste("Could not read CSV:", conditionMessage(e)))
)

if (!time_col %in% names(dat))
  stop(paste0("Column '", time_col, "' not found in ", basename(file_path),
              ". Available columns: ", paste(names(dat), collapse = ", ")))
if (!status_col %in% names(dat))
  stop(paste0("Column '", status_col, "' not found in ", basename(file_path),
              ". Available columns: ", paste(names(dat), collapse = ", ")))

times   <- suppressWarnings(as.numeric(dat[[time_col]]))
statuses <- suppressWarnings(as.integer(dat[[status_col]]))

if (any(is.na(times)))
  stop(paste0("Non-numeric or missing values in column '", time_col, "'."))
if (any(is.na(statuses)) || any(!statuses %in% c(0L, 1L)))
  stop(paste0("Column '", status_col, "' must contain only 0 (survived) and 1 (failed)."))
if (any(times <= 0))
  stop(paste0("All values in '", time_col, "' must be positive."))
if (nrow(dat) < 2)
  stop("At least 2 units are required.")

# ---------------------------------------------------------------------------
# Compute effective times and classify units
# ---------------------------------------------------------------------------

t_eff <- times * accel_factor

# Failure at or before target_life: counts toward k in both binomial and Weibayes
is_failure_at_horizon <- (statuses == 1L) & (t_eff <= target_life)
n <- length(t_eff)
k <- sum(is_failure_at_horizon)

# Suspensions = survived to test end OR failed beyond target_life
n_failures    <- k
n_suspensions <- n - k

# ---------------------------------------------------------------------------
# Binomial (Clopper-Pearson)
# ---------------------------------------------------------------------------

# Upper confidence bound on failure fraction at target_life
# n - k == 0 (all units failed before target life): UCB on fail rate = 1 → R_lower = 0
if (n - k == 0L) {
  F_upper_binom <- 1.0
} else {
  F_upper_binom <- qbeta(confidence, k + 1, n - k)
}
R_lower_binom <- 1 - F_upper_binom
pass_binom    <- R_lower_binom >= reliability
margin_binom  <- R_lower_binom - reliability

# ---------------------------------------------------------------------------
# Weibayes (if beta provided)
# ---------------------------------------------------------------------------

use_weibayes  <- !is.na(beta)
R_demo_wb     <- NA
pass_wb       <- NA
margin_wb     <- NA
eta_demo      <- NA
T_star        <- NA
T_threshold   <- NA

if (use_weibayes) {
  # T* includes all units with their actual effective time
  T_star      <- sum(t_eff^beta)
  T_threshold <- qchisq(confidence, 2L * (k + 1L)) * target_life^beta /
                 (2 * (-log(reliability)))
  eta_demo    <- (2 * T_star / qchisq(confidence, 2L * (k + 1L)))^(1 / beta)
  R_demo_wb   <- exp(-(target_life / eta_demo)^beta)
  pass_wb     <- R_demo_wb >= reliability
  margin_wb   <- R_demo_wb - reliability
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Reliability Demonstration Test — Verification\n")
cat(sprintf("  File: %s\n", basename(file_path)))
cat(sprintf("  Claim: R >= %g at %g  |  Confidence: %g\n",
            reliability, target_life, confidence))
if (use_weibayes) {
  cat(sprintf("  Weibayes: beta = %.2f  |  Accel factor: %.4g\n", beta, accel_factor))
} else if (accel_factor > 1.0) {
  cat(sprintf("  Accel factor: %.4g\n", accel_factor))
}
cat("=================================================================\n\n")

cat(sprintf("  Units tested:               %d\n", n))
cat(sprintf("  Failures at target life:    %d\n", n_failures))
cat(sprintf("  Suspensions (survived):     %d\n", n_suspensions))
if (any((statuses == 1L) & (t_eff > target_life))) {
  n_late <- sum((statuses == 1L) & (t_eff > target_life))
  cat(sprintf("  Failures beyond target:     %d  (treated as suspensions)\n", n_late))
}
cat("\n")

# Binomial section
cat("--- Binomial Verification (Clopper-Pearson) ---------------------\n")
cat(sprintf("  Failures at target life:    k = %d of n = %d\n", k, n))
cat(sprintf("  Upper bound on fail rate:   F_upper = %.4f  (%.1f%%)\n",
            F_upper_binom, F_upper_binom * 100))
cat(sprintf("  Demonstrated R lower bound: R_lower = %.4f\n", R_lower_binom))
cat("\n")
cat(sprintf("  Claim:    R >= %g at %g, confidence %g\n",
            reliability, target_life, confidence))
cat(sprintf("  Margin:   R_lower - R_claim = %+.4f\n", margin_binom))
cat("\n")
if (pass_binom) {
  cat(sprintf("  Verdict: PASS  (R_lower %.4f >= claim %g)\n", R_lower_binom, reliability))
} else {
  cat(sprintf("  Verdict: FAIL  (R_lower %.4f < claim %g)\n", R_lower_binom, reliability))
}
cat("-----------------------------------------------------------------\n\n")

# Weibayes section
if (use_weibayes) {
  cat("--- Weibayes Verification ---------------------------------------\n")
  cat(sprintf("  beta = %.2f  |  T* = sum(t_eff_i ^ beta) = %.4e\n", beta, T_star))
  cat(sprintf("  T_threshold (plan criterion):          %.4e\n", T_threshold))
  cat(sprintf("  T* / T_threshold:                      %.3f  %s\n",
              T_star / T_threshold,
              if (T_star >= T_threshold) "[ PASS criterion met ]" else "[ PASS criterion NOT met ]"))
  cat(sprintf("  Demonstrated eta (char. life):         %.2f\n", eta_demo))
  cat(sprintf("  Demonstrated R at %g:               %.4f\n", target_life, R_demo_wb))
  cat("\n")
  cat(sprintf("  Claim:    R >= %g at %g, confidence %g\n",
              reliability, target_life, confidence))
  cat(sprintf("  Margin:   R_demo - R_claim = %+.4f\n", margin_wb))
  cat("\n")
  if (pass_wb) {
    cat(sprintf("  Verdict: PASS  (R_demo %.4f >= claim %g)\n", R_demo_wb, reliability))
  } else {
    cat(sprintf("  Verdict: FAIL  (R_demo %.4f < claim %g)\n", R_demo_wb, reliability))
  }
  cat("-----------------------------------------------------------------\n\n")
}

# Overall summary
overall_pass <- if (use_weibayes) (pass_binom || pass_wb) else pass_binom
cat("=================================================================\n")
cat(sprintf("  Overall Verdict: %s\n",
            if (overall_pass) "PASS" else "FAIL"))
if (use_weibayes && pass_binom != pass_wb) {
  cat("  Note: Binomial and Weibayes verdicts differ. The Weibayes result\n")
  cat("  is more powerful when beta is well-supported by prior data.\n")
  cat("  Document the basis for the assumed beta value.\n")
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# PNG output
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_rdt_verify.png"))

# --- Panel 1: Timeline ---
unit_ids <- if (!is.null(dat[[1]]) && length(unique(dat[[1]])) == n) {
  as.character(dat[[1]])
} else {
  paste0("U", seq_len(n))
}

df_time <- data.frame(
  unit   = factor(unit_ids, levels = rev(unit_ids)),
  t_eff  = t_eff,
  status = statuses,
  fail_at_horizon = is_failure_at_horizon
)

# Separate subsets for ggplot layers
df_surv <- df_time[!df_time$fail_at_horizon, ]
df_fail <- df_time[df_time$fail_at_horizon, ]

p1_title <- sprintf("Test Results Timeline  —  %s",
                    if (overall_pass) "PASS" else "FAIL")
p1_sub   <- sprintf("n = %d, k = %d failures at target life = %g", n, k, target_life)

p1 <- ggplot(df_time, aes(y = unit)) +
  geom_segment(aes(x = 0, xend = t_eff, yend = unit),
               color = CLR_SURV, linewidth = 0.6) +
  geom_vline(xintercept = target_life, linetype = "dashed",
             color = CLR_CLAIM, linewidth = 0.8) +
  annotate("text", x = target_life, y = n * 1.02,
           label = paste("target\n", target_life), hjust = 0.5, size = 2.5,
           color = CLR_CLAIM) +
  labs(title    = p1_title,
       subtitle = p1_sub,
       x        = "Effective test time",
       y        = NULL) +
  theme_jr +
  theme(axis.text.y = element_text(size = if (n <= 20) 7 else 5))

if (nrow(df_surv) > 0) {
  p1 <- p1 + geom_point(data = df_surv, aes(x = t_eff, y = unit),
                        shape = 3, size = 2, color = CLR_SURV)
}
if (nrow(df_fail) > 0) {
  p1 <- p1 + geom_point(data = df_fail, aes(x = t_eff, y = unit),
                        shape = 4, size = 3, color = CLR_FAIL2, stroke = 1.2)
}

# --- Panel 2: Demonstrated reliability bars ---
bar_labels <- "Claim"
bar_vals   <- reliability
bar_cols   <- CLR_CLAIM

bar_labels <- c(bar_labels, "Binomial\n(lower bound)")
bar_vals   <- c(bar_vals,   R_lower_binom)
bar_cols   <- c(bar_cols,   if (pass_binom) CLR_PASS else CLR_FAIL)

if (use_weibayes) {
  bar_labels <- c(bar_labels, "Weibayes\n(demonstrated)")
  bar_vals   <- c(bar_vals,   R_demo_wb)
  bar_cols   <- c(bar_cols,   if (pass_wb) CLR_PASS else CLR_FAIL)
}

df_bar <- data.frame(
  label = factor(bar_labels, levels = bar_labels),
  R     = bar_vals,
  col   = bar_cols
)

y_min <- min(0.5, min(bar_vals) - 0.05)
y_min <- max(0, y_min)

p2_title <- if (overall_pass) "Demonstrated Reliability — PASS" else "Demonstrated Reliability — FAIL"

p2 <- ggplot(df_bar, aes(x = label, y = R, fill = label)) +
  geom_col(width = 0.5, show.legend = FALSE) +
  geom_hline(yintercept = reliability, linetype = "dashed",
             color = CLR_CLAIM, linewidth = 0.8) +
  annotate("text", x = 0.55, y = reliability,
           label = paste("claim =", reliability),
           hjust = 0, vjust = -0.4, size = 3, color = CLR_CLAIM) +
  geom_text(aes(label = sprintf("%.4f", R)), vjust = -0.4, size = 3) +
  scale_fill_manual(values = setNames(bar_cols, bar_labels)) +
  coord_cartesian(ylim = c(y_min, 1.0)) +
  labs(title    = p2_title,
       subtitle = sprintf("Claim: R >= %g, C = %g", reliability, confidence),
       x        = NULL,
       y        = "Reliability") +
  theme_jr

# Save two-panel PNG
png(out_file, width = 2400, height = 1200, res = 200)
grid.newpage()
pushViewport(viewport(layout = grid.layout(1, 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
invisible(dev.off())

cat(sprintf("\u2728 Plot saved to: %s\n\n", out_file))
jr_log_output_hashes(c(out_file))
cat("\u2705 Done.\n")
