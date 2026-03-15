#!/usr/bin/env Rscript
#
# use as: Rscript jrc_weibull.R <file_path> <time_col> <status_col>
#
# "file_path"   path to a CSV file with column names as the first row
# "time_col"    column name containing observed times (failure time or
#               censoring time for surviving units). Must be positive.
# "status_col"  column name containing the event indicator:
#                 1 = unit failed (event observed)
#                 0 = unit survived / right-censored (test ended before failure)
#
# IMPORTANT! The CSV file must have at least 3 columns: the first column is
# used for row names, then the time and status columns.
#
# Needs the <stats>, <survival>, and <ggplot2> libraries.
# <survival> is included with base R — no additional installation required.
#
# Fits a 2-parameter Weibull distribution to lifetime or fatigue data,
# including right-censored observations, using Maximum Likelihood Estimation
# via survreg() from the survival package.
#
# Reports:
#   - Shape parameter (beta) and scale parameter (eta) with 95% CIs
#   - B1, B10, and B50 life estimates with 95% CIs
#   - Interpretation of the shape parameter
#
# Saves a Weibull probability plot as PNG to the directory of the input CSV.
# The probability plot uses median rank positions (Benard's approximation)
# for the failed units and shows the fitted Weibull line with 95% CI bands.
#
# Common uses in medical device development:
#   - Fatigue life analysis for implants and reusable devices
#   - Accelerated lifetime test (ALT) result analysis
#   - Wear analysis for articulating surfaces
#   - Estimating B-life for reliability demonstration planning (jrc_ss_fatigue)
#
# Reference:
#   Nelson, W.B. (2004). Accelerated Testing: Statistical Models, Test Plans,
#   and Data Analysis. Wiley.
#   Meeker, W.Q., Escobar, L.A. (1998). Statistical Methods for Reliability
#   Data. Wiley.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", "macos", r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

suppressPackageStartupMessages({
  library(stats)
  library(survival)  # survreg() for censored MLE — included with base R
  library(ggplot2)
})

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 3) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_weibull.R <file_path> <time_col> <status_col>",
    "Example:",
    "  Rscript jrc_weibull.R fatigue_data.csv cycles status",
    sep = "\n"
  ))
}

file_path       <- args[1]
input_time_col  <- args[2]
input_stat_col  <- args[3]
time_col        <- make.names(input_time_col)
stat_col        <- make.names(input_stat_col)

if (!file.exists(file_path)) {
  stop(paste("File not found:", file_path))
}

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

mydata <- tryCatch(
  read.table(file_path, header = TRUE, sep = ",", dec = ".", row.names = 1),
  error = function(e) stop(paste("Failed to read CSV file:", e$message))
)

if (ncol(mydata) < 2) {
  stop(paste(
    "The CSV file must have at least 3 columns: one for row names,",
    "one for time, and one for status."
  ))
}

for (col in c(time_col, stat_col)) {
  if (!col %in% names(mydata)) {
    stop(paste0("Column '", col, "' not found. Available: ",
                paste(names(mydata), collapse = ", ")))
  }
}

times_raw  <- mydata[[time_col]]
status_raw <- mydata[[stat_col]]

# Pairwise clean
valid <- is.finite(times_raw) & !is.na(times_raw) &
         is.finite(status_raw) & !is.na(status_raw)
n_bad <- sum(!valid)
if (n_bad > 0) warning(paste(n_bad, "row(s) removed due to NA or non-finite values."))

times  <- times_raw[valid]
status <- as.integer(status_raw[valid])
N      <- length(times)

if (any(times <= 0)) {
  stop("All time values must be strictly positive.")
}
if (!all(status %in% c(0L, 1L))) {
  stop("Status column must contain only 0 (censored) and 1 (failed).")
}

n_failed   <- sum(status == 1)
n_censored <- sum(status == 0)

if (n_failed < 2) {
  stop(paste("At least 2 failure events are required for Weibull fitting. Got:", n_failed))
}

# ---------------------------------------------------------------------------
# Weibull MLE via survreg()
# ---------------------------------------------------------------------------

# survreg() with dist="weibull" fits the extreme value distribution to log(T).
# Parameterisation: log(T) = mu + sigma * W  where W ~ Gumbel(0,1)
# Conversion to standard Weibull: beta = 1/sigma, eta = exp(mu)

fit <- survreg(Surv(times, status) ~ 1, dist = "weibull")

mu    <- fit$coefficients[["(Intercept)"]]
sigma <- fit$scale

beta <- 1 / sigma
eta  <- exp(mu)

# CIs via delta method on log scale (asymptotically normal)
# survreg reports SE for log(sigma) and mu
vcov_fit  <- vcov(fit)
se_mu     <- sqrt(vcov_fit["(Intercept)", "(Intercept)"])
se_lsigma <- sqrt(vcov_fit["Log(scale)", "Log(scale)"])

z95 <- qnorm(0.975)

# eta CI: exp(mu +/- z * se_mu)
eta_lo <- exp(mu - z95 * se_mu)
eta_hi <- exp(mu + z95 * se_mu)

# beta CI: 1/sigma -> beta = exp(-log(sigma))
# SE(log(beta)) = SE(log(1/sigma)) = SE(log(sigma)) = se_lsigma
log_beta    <- log(beta)
beta_lo <- exp(log_beta - z95 * se_lsigma)
beta_hi <- exp(log_beta + z95 * se_lsigma)

# ---------------------------------------------------------------------------
# B-life estimates with 95% CIs
# ---------------------------------------------------------------------------

# B-life at fraction p: t_p = eta * (-log(1-p))^(1/beta)
# On log scale: log(t_p) = mu + (1/beta) * log(-log(1-p))
#                        = mu + sigma * log(-log(1-p))
# SE(log(t_p)) via delta method:
#   Var(log(t_p)) = Var(mu) + log(-log(1-p))^2 * Var(log(sigma))
#                  + 2 * log(-log(1-p)) * Cov(mu, log(sigma))

cov_mu_lsigma <- vcov_fit["(Intercept)", "Log(scale)"]

b_life_ci <- function(p) {
  log_neg_log  <- log(-log(1 - p))
  log_t        <- mu + sigma * log_neg_log
  var_log_t    <- vcov_fit["(Intercept)", "(Intercept)"] +
                  log_neg_log^2 * vcov_fit["Log(scale)", "Log(scale)"] +
                  2 * log_neg_log * cov_mu_lsigma
  se_log_t     <- sqrt(max(var_log_t, 0))
  c(
    estimate = exp(log_t),
    lower    = exp(log_t - z95 * se_log_t),
    upper    = exp(log_t + z95 * se_log_t)
  )
}

b01 <- b_life_ci(0.01)
b10 <- b_life_ci(0.10)
b50 <- b_life_ci(0.50)

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

shape_interp <- if (beta < 1) {
  "< 1: decreasing failure rate (infant mortality / early failures)"
} else if (abs(beta - 1) < 0.05) {
  "≈ 1: constant failure rate (random / exponential failures)"
} else if (beta < 3) {
  "> 1: increasing failure rate (wear-out / fatigue failures)"
} else {
  "> 3: rapidly increasing failure rate (wear-out / tight distribution)"
}

message(" ")
message("✅ Weibull Reliability Analysis")
message("   version: 1.0, author: Joep Rous")
message("   ================================")
message(paste("   file:                     ", file_path))
message(paste("   time column:              ", input_time_col))
message(paste("   status column:            ", input_stat_col))
message(paste("   total observations (N):   ", N))
message(paste("   failures:                 ", n_failed))
message(paste("   censored (survivors):     ", n_censored))
message(" ")
message("   Weibull Parameters (MLE, 2-parameter):")
message(" ")
message("   -------------------------------------------------------")
message("    parameter   estimate      95% CI")
message("   -------------------------------------------------------")
message(sprintf("    beta (\u03b2)    %10.4f    [%8.4f, %8.4f]", beta, beta_lo, beta_hi))
message(sprintf("    eta (\u03b7)     %10.4f    [%8.4f, %8.4f]", eta,  eta_lo,  eta_hi))
message("   -------------------------------------------------------")
message(" ")
message(paste("   Shape interpretation: beta", shape_interp))
message(" ")
message("   B-Life Estimates:")
message(" ")
message("   -------------------------------------------------------")
message("    B-life    estimate      95% CI")
message("   -------------------------------------------------------")
message(sprintf("    B1      %10.4f    [%8.4f, %8.4f]", b01["estimate"], b01["lower"], b01["upper"]))
message(sprintf("    B10     %10.4f    [%8.4f, %8.4f]", b10["estimate"], b10["lower"], b10["upper"]))
message(sprintf("    B50     %10.4f    [%8.4f, %8.4f]", b50["estimate"], b50["lower"], b50["upper"]))
message("   -------------------------------------------------------")
message(" ")
message("   Note: B10 is the time at which 10% of units are expected to have")
message("   failed (= 90th percentile reliability). Use B-life estimates as")
message("   input to jrc_ss_fatigue for reliability demonstration planning.")
message(" ")

# ---------------------------------------------------------------------------
# Weibull probability plot
# ---------------------------------------------------------------------------

# Median rank positions (Benard's approximation) for failed units only
# Sort failed times for plotting
failed_times <- sort(times[status == 1])
n_f          <- length(failed_times)

# Median ranks: F_i = (i - 0.3) / (N + 0.4)
# Note: N is total sample size (failed + censored) for correct rank adjustment
# For censored data, use adjusted ranks via Kaplan-Meier
# Simple approach: use KM estimate at each failure time
km_fit   <- survfit(Surv(times, status) ~ 1)
km_times <- km_fit$time[km_fit$n.event > 0]
km_surv  <- km_fit$surv[km_fit$n.event > 0]
km_F     <- 1 - km_surv

# Linearised Weibull: y = log(-log(1-F)), x = log(t)
# Fitted line: y = beta * log(t) - beta * log(eta)
x_plot   <- log(km_times)
y_plot   <- log(-log(1 - km_F))

# Fitted line over range
x_seq    <- seq(min(log(times)) * 0.95, max(log(times)) * 1.05, length.out = 100)
y_fit    <- beta * x_seq - beta * log(eta)

# 95% CI on the fitted line via delta method
y_ci <- sapply(x_seq, function(lx) {
  p_val     <- 1 - exp(-exp(beta * lx - beta * log(eta)))
  p_val     <- max(min(p_val, 1 - 1e-9), 1e-9)
  log_neg_log_p <- log(-log(1 - p_val))
  var_log_t     <- vcov_fit["(Intercept)", "(Intercept)"] +
                   log_neg_log_p^2 * vcov_fit["Log(scale)", "Log(scale)"] +
                   2 * log_neg_log_p * cov_mu_lsigma
  se_lx <- sqrt(max(var_log_t, 0))
  c(lo = beta * (lx - z95 * se_lx) - beta * log(eta),
    hi = beta * (lx + z95 * se_lx) - beta * log(eta))
})

ci_df <- data.frame(
  x  = x_seq,
  lo = y_ci["lo", ],
  hi = y_ci["hi", ]
)

# B-life reference lines
b_refs <- data.frame(
  p     = c(0.01, 0.10, 0.50),
  label = c("B1", "B10", "B50"),
  y_val = log(-log(1 - c(0.01, 0.10, 0.50)))
)

df_points <- data.frame(x = x_plot, y = y_plot)
df_line   <- data.frame(x = x_seq,  y = y_fit)

# X-axis breaks: nice values on original (not log) scale
x_breaks_orig <- pretty(exp(x_seq), n = 6)
x_breaks_log  <- log(x_breaks_orig[x_breaks_orig > 0])

# Y-axis breaks: F values 1%, 5%, 10%, 20%, 50%, 90%, 99%
f_breaks <- c(0.01, 0.05, 0.10, 0.20, 0.50, 0.90, 0.99)
y_breaks <- log(-log(1 - f_breaks))

p <- ggplot() +

  # CI band
  geom_ribbon(data = ci_df, aes(x = x, ymin = lo, ymax = hi),
              fill = "#AEC6E8", alpha = 0.40) +

  # Fitted Weibull line
  geom_line(data = df_line, aes(x = x, y = y),
            colour = "#2166AC", linewidth = 0.9) +

  # B-life reference lines
  geom_hline(data = b_refs, aes(yintercept = y_val),
             colour = "grey60", linetype = "dotted", linewidth = 0.5) +
  geom_text(data = b_refs,
            aes(x = min(x_seq), y = y_val, label = label),
            hjust = -0.1, vjust = -0.4, size = 2.8, colour = "grey40") +

  # Data points
  geom_point(data = df_points, aes(x = x, y = y),
             colour = "#1A1A2E", size = 2.5, alpha = 0.80) +

  # Axes
  scale_x_continuous(
    name   = input_time_col,
    breaks = x_breaks_log,
    labels = signif(x_breaks_orig[x_breaks_orig > 0], 3)
  ) +
  scale_y_continuous(
    name   = "Cumulative failure probability F(t)",
    breaks = y_breaks,
    labels = paste0(f_breaks * 100, "%")
  ) +

  labs(
    title    = "Weibull Probability Plot",
    subtitle = sprintf(
      "N = %d  |  failures = %d  |  \u03b2 = %.3f [%.3f, %.3f]  |  \u03b7 = %.3f [%.3f, %.3f]",
      N, n_failed, beta, beta_lo, beta_hi, eta, eta_lo, eta_hi
    )
  ) +

  theme_bw(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(size = 8.0, colour = "grey30"),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.4)
  )

# Save PNG
datetime_prefix <- format(Sys.time(), "%Y%m%d_%H%M%S")
safe_col        <- gsub("[^A-Za-z0-9_.-]", "_", input_time_col)
out_file        <- file.path(dirname(normalizePath(file_path)),
                             paste0(datetime_prefix, "_weibull_", safe_col, ".png"))
ggsave(out_file, plot = p, width = 9, height = 6, dpi = 150, bg = "white")
message(paste("✅ Weibull probability plot saved to:", out_file))
message(" ")
