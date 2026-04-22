#!/usr/bin/env Rscript
#
# use as: Rscript jrc_rdt_plan.R --reliability R --confidence C --target_life T [options]
#
# Plans a Reliability Demonstration Test (RDT) using either the Bogey/binomial
# method (no Weibull shape assumption) or the Weibayes method (Weibull shape
# beta assumed from prior data or engineering judgment).
#
# accel_factor is a life-extension multiplier: each test unit accumulates
# accel_factor x target_life effective hours. At accel_factor=1 (default),
# units are tested exactly to target_life. accel_factor=2 means each unit
# is tested to twice the target life, which reduces the required sample size
# in Weibayes mode. For thermal rate acceleration (Arrhenius), pass the
# rate-acceleration factor as accel_factor and note that the calendar test
# duration = target_life / accel_factor.
#
# Needs only base R and ggplot2 (already pinned).
#
# Core formula (Weibayes, k allowed failures):
#   n = ceiling( qchisq(C, 2*(k+1)) / (2 * (-log(R)) * accel_factor^beta) )
#
# At accel_factor=1 this reduces to the exact zero-failure binomial rule
# (equivalent to jrc_ss_discrete at k=0) and generalises consistently to k>0.
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
# Argument parsing (before renv — errors surface immediately)
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || flag_present(args, "--help") || flag_present(args, "-h")) {
  cat("\nUsage: jrc_rdt_plan --reliability R --confidence C --target_life T [options]\n\n")
  cat("Required:\n")
  cat("  --reliability R     Minimum reliability to demonstrate, e.g. 0.95\n")
  cat("  --confidence C      Confidence level, e.g. 0.90\n")
  cat("  --target_life T     Life at which reliability is claimed, e.g. 5000 (hours, cycles, etc.)\n\n")
  cat("Optional:\n")
  cat("  --beta B            Weibull shape parameter. Enables Weibayes mode.\n")
  cat("                      If omitted, Bogey/binomial method is used (no shape assumption).\n")
  cat("                      Obtain from jrc_weibull, published data, or engineering judgment.\n")
  cat("  --k_allowed K       Maximum allowed failures in the test (default: 0)\n")
  cat("  --accel_factor AF   Life-extension multiplier (default: 1.0).\n")
  cat("                      Each unit is tested to AF x target_life effective hours.\n")
  cat("                      AF > 1 reduces required units in Weibayes mode.\n")
  cat("                      Ignored in Bogey mode (no beta).\n\n")
  cat("Examples:\n")
  cat("  jrc_rdt_plan --reliability 0.95 --confidence 0.90 --target_life 5000\n")
  cat("  jrc_rdt_plan --reliability 0.95 --confidence 0.90 --target_life 5000 --beta 2.0\n")
  cat("  jrc_rdt_plan --reliability 0.95 --confidence 0.90 --target_life 5000 --beta 2.0 --accel_factor 2.0\n")
  cat("  jrc_rdt_plan --reliability 0.95 --confidence 0.90 --target_life 5000 --beta 2.0 --k_allowed 1\n\n")
  quit(status = 0)
}

reliability  <- parse_flag(args, "--reliability",  NA,  numeric = TRUE)
confidence   <- parse_flag(args, "--confidence",   NA,  numeric = TRUE)
target_life  <- parse_flag(args, "--target_life",  NA,  numeric = TRUE)
beta         <- parse_flag(args, "--beta",         NA,  numeric = TRUE)
k_allowed    <- parse_flag(args, "--k_allowed",    0,   numeric = TRUE)
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
if (k_allowed < 0 || k_allowed != floor(k_allowed))
  stop(paste("--k_allowed must be a non-negative integer. Got:", k_allowed))
if (accel_factor < 1.0)
  stop(paste("--accel_factor must be >= 1.0. Got:", accel_factor))

k_allowed <- as.integer(k_allowed)

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

BG       <- "#FFFFFF"
CLR_BLUE <- "#2166AC"
CLR_AMB  <- "#D6604D"
CLR_GREY <- "#AAAAAA"

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
# Core formula
#
# Weibayes criterion: sum(t_eff_i ^ beta) >= T_threshold
#   T_threshold = qchisq(C, 2*(k+1)) * target_life^beta / (2 * (-log(R)))
#
# For n equal units all tested to t_eff = accel_factor * target_life:
#   n = ceiling( T_threshold / t_eff^beta )
#     = ceiling( qchisq(C, 2*(k+1)) / (2 * (-log(R)) * accel_factor^beta) )
#
# In Bogey mode (no beta): accel_factor is set to 1 (units tested to target_life).
# At k=0 and accel_factor=1 this is algebraically identical to the exact
# zero-failure success-run formula: ceiling( log(1-C) / log(R) ).
# ---------------------------------------------------------------------------

rdt_n <- function(R, C, k, beta_val, af) {
  ceiling(qchisq(C, df = 2L * (k + 1L)) / (2 * (-log(R)) * af^beta_val))
}

use_weibayes <- !is.na(beta)
k_vals       <- 0L:5L

if (use_weibayes) {
  n_table   <- sapply(k_vals, function(k) rdt_n(reliability, confidence, k, beta, accel_factor))
  t_eff     <- accel_factor * target_life
} else {
  n_table   <- sapply(k_vals, function(k) rdt_n(reliability, confidence, k, 1.0, 1.0))
  t_eff     <- target_life
  if (accel_factor > 1.0)
    message("Note: --accel_factor has no effect in Bogey mode (no beta). Showing accel_factor in display only.")
}

# ---------------------------------------------------------------------------
# Beta sensitivity table (Weibayes only, k = k_allowed)
# ---------------------------------------------------------------------------

beta_sens_df <- NULL
if (use_weibayes) {
  beta_grid <- pmax(0.5, beta * c(0.5, 0.75, 1.0, 1.25, 1.5))
  beta_grid <- unique(sort(round(beta_grid, 6)))
  n_sens    <- sapply(beta_grid, function(b) rdt_n(reliability, confidence, 0L, b, accel_factor))
  beta_sens_df <- data.frame(beta_val = beta_grid, n_req = n_sens)
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Reliability Demonstration Test Plan\n")
cat(sprintf("  Reliability: %g  |  Confidence: %g  |  Target life: %g\n",
            reliability, confidence, target_life))
if (use_weibayes) {
  cat(sprintf("  Method: Weibayes  (beta = %.2f)\n", beta))
} else {
  cat("  Method: Bogey / Binomial  (no Weibull shape assumption)\n")
}
af_display <- if (accel_factor == 1.0) "1.0 (none)" else sprintf("%.4g  (t_eff = %g)", accel_factor, t_eff)
cat(sprintf("  Accel factor: %s\n", af_display))
cat("=================================================================\n\n")

cat("--- Test Plan ---------------------------------------------------\n")
cat(sprintf("  %-14s  %-18s  %s\n", "failures (k)", "units (n)", "eff. test time per unit"))
cat("  ----------------------------------------------------------------\n")
for (i in seq_along(k_vals)) {
  k <- k_vals[i]
  n <- n_table[i]
  marker <- if (k == k_allowed) "  <- plan" else ""
  cat(sprintf("  k = %-9d  n = %-14d  %g%s\n", k, n, t_eff, marker))
}
cat("  ----------------------------------------------------------------\n\n")

if (use_weibayes) {
  Tstar <- qchisq(confidence, 2L * (k_allowed + 1L)) * target_life^beta /
           (2 * (-log(reliability)))
  cat(sprintf("  Weibayes criterion (k=%d):  sum(t_eff_i ^ %.2f) >= %.4e\n\n", k_allowed, beta, Tstar))
}

if (!is.null(beta_sens_df)) {
  cat(sprintf("--- Beta Sensitivity (k = 0, accel_factor = %.4g) ---------------\n", accel_factor))
  if (accel_factor == 1.0) {
    cat("  At accel_factor = 1, required n is independent of beta.\n")
    cat("  Use accel_factor > 1 to show the benefit of life-extension testing.\n\n")
  } else {
    cat(sprintf("  %-12s  %s\n", "beta", "n required"))
    cat("  ---------------------------\n")
    for (i in seq_len(nrow(beta_sens_df))) {
      b      <- beta_sens_df$beta_val[i]
      n      <- beta_sens_df$n_req[i]
      marker <- if (abs(b - beta) < 1e-6) "  <- assumed" else ""
      cat(sprintf("  %-12.4g  %d%s\n", b, n, marker))
    }
    cat("  ---------------------------\n")
    cat("  If beta is uncertain, use the largest n (most conservative).\n\n")
  }
}

cat("--- Notes -------------------------------------------------------\n")
cat("  \u2022 k = 0 (zero-failure test) is the FDA standard for design verification.\n")
cat("    Allowing k > 0 requires pre-specified statistical justification.\n")

if (use_weibayes) {
  cat(sprintf("  \u2022 beta = %.2f assumed. Derive from jrc_weibull, published data for\n", beta))
  cat("    similar devices, or conservative engineering judgment.\n")
  if (accel_factor > 1.0) {
    cat(sprintf("  \u2022 Accel factor: %.4g. Each unit accumulates %g effective hours.\n", accel_factor, t_eff))
    cat("    Document and justify the acceleration mechanism in your protocol.\n")
  }
} else {
  if (accel_factor > 1.0) {
    cat(sprintf("  \u2022 Accel factor %.4g noted for reference. Use --beta to incorporate it\n", accel_factor))
    cat("    into the sample size calculation (Weibayes mode).\n")
  }
}

beta_hint <- if (use_weibayes) sprintf(" --beta %.4g", beta) else ""
af_hint   <- if (accel_factor > 1.0) sprintf(" --accel_factor %.4g", accel_factor) else ""
cat(sprintf("  \u2022 After testing, run: jrc_rdt_verify --reliability %g --confidence %g\n",
            reliability, confidence))
cat(sprintf("    --target_life %g%s%s\n", target_life, beta_hint, af_hint))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# PNG output
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_rdt_plan.png"))

subtitle_base <- sprintf("R = %g, C = %g, target life = %g", reliability, confidence, target_life)

df_bar <- data.frame(
  k    = factor(k_vals),
  n    = n_table,
  grp  = ifelse(k_vals == k_allowed, "plan",
          ifelse(k_vals == 0, "zero", "other"))
)

p1 <- ggplot(df_bar, aes(x = k, y = n, fill = grp)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = n), vjust = -0.4, size = 3) +
  scale_fill_manual(
    values = c(plan = CLR_BLUE, zero = "#4393C3", other = CLR_AMB),
    labels = c(plan = paste0("k = ", k_allowed, " (plan)"), zero = "k = 0", other = "k > 0"),
    name   = NULL
  ) +
  expand_limits(y = max(n_table) * 1.12) +
  labs(
    title    = "Required Units vs Allowed Failures",
    subtitle = subtitle_base,
    x        = "Allowed failures (k)",
    y        = "Units required (n)"
  ) +
  theme_jr +
  theme(legend.position = "bottom", legend.text = element_text(size = 8))

if (!is.null(beta_sens_df) && nrow(beta_sens_df) > 1) {
  df_sens <- beta_sens_df
  df_sens$assumed <- abs(df_sens$beta_val - beta) < 1e-6

  p2 <- ggplot(df_sens, aes(x = beta_val, y = n_req)) +
    geom_line(color = CLR_GREY, linewidth = 0.8) +
    geom_point(aes(color = assumed, size = assumed)) +
    scale_color_manual(values = c(`FALSE` = CLR_GREY, `TRUE` = CLR_BLUE), guide = "none") +
    scale_size_manual(values  = c(`FALSE` = 2,         `TRUE` = 4),        guide = "none") +
    geom_text(
      data = df_sens[df_sens$assumed, , drop = FALSE],
      aes(label = paste0("beta = ", beta_val)),
      vjust = -1.1, size = 3, color = CLR_BLUE
    ) +
    expand_limits(y = max(df_sens$n_req) * 1.15) +
    labs(
      title    = paste0("Beta Sensitivity (k = 0, AF = ", accel_factor, ")"),
      subtitle = "Conservative: choose the largest n",
      x        = "Weibull shape (beta)",
      y        = "Units required (n)"
    ) +
    theme_jr

  png(out_file, width = 2400, height = 1200, res = 200)
  grid.newpage()
  pushViewport(viewport(layout = grid.layout(1, 2)))
  print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
  invisible(dev.off())
} else {
  ggsave(out_file, plot = p1, width = 5, height = 4, dpi = 200, bg = BG)
}

cat(sprintf("\u2728 Plot saved to: %s\n\n", out_file))
jr_log_output_hashes(c(out_file))
cat("\u2705 Done.\n")
