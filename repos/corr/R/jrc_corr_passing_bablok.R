# =============================================================================
# jrc_corr_passing_bablok.R
# JR Validated Environment — Correlation Analysis module
#
# Passing-Bablok regression for method comparison. Does not assume a
# gold-standard reference method. Tests whether slope = 1 and intercept = 0
# (methods are interchangeable). Includes Cusum linearity test.
#
# Usage: jrc_corr_passing_bablok <data.csv> [--xcol x] [--ycol y] [--conf 0.95]
#
# Reference: Passing H, Bablok W (1983). J Clin Chem Clin Biochem 21:709-720.
#
# Version: 1.1
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_corr_passing_bablok <data.csv> [--xcol x] [--ycol y] [--conf 0.95]")
}

data_file <- args[1]
xcol      <- "x"
ycol      <- "y"
conf      <- 0.95

i <- 2
while (i <= length(args)) {
  if (args[i] == "--xcol" && i < length(args)) {
    xcol <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--ycol" && i < length(args)) {
    ycol <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--conf" && i < length(args)) {
    conf <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(conf) || conf <= 0 || conf >= 1) {
      stop("--conf must be a number strictly between 0 and 1.")
    }
    i <- i + 2
  } else {
    # Unknown flags (e.g. typos) are errors, never silently ignored (X-05)
    stop(paste0("Unknown argument, or option without a value: ", args[i]))
  }
}

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.1"   # single source for banner, report and JSON

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
}))

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
if (!file.exists(data_file)) {
  stop(paste("\u274c File not found:", data_file))
}

df <- tryCatch(
  read.csv(data_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV file:", e$message))
)

if (!xcol %in% names(df)) {
  stop(paste("\u274c Column not found in CSV:", xcol))
}
if (!ycol %in% names(df)) {
  stop(paste("\u274c Column not found in CSV:", ycol))
}

x_raw <- suppressWarnings(as.numeric(df[[xcol]]))
y_raw <- suppressWarnings(as.numeric(df[[ycol]]))

if (all(is.na(x_raw))) {
  stop(paste("\u274c Column", xcol, "is not numeric."))
}
if (all(is.na(y_raw))) {
  stop(paste("\u274c Column", ycol, "is not numeric."))
}

valid_idx <- !is.na(x_raw) & !is.na(y_raw)
jr_report_excluded(sum(!valid_idx), "missing or non-numeric x or y",
                   if ("id" %in% names(df)) df$id[!valid_idx] else which(!valid_idx))
x <- x_raw[valid_idx]
y <- y_raw[valid_idx]

if (length(x) < 3) {
  stop(paste("\u274c Need at least 3 complete observations. Found:", length(x)))
}

# ---------------------------------------------------------------------------
# Passing-Bablok algorithm (native implementation)
# ---------------------------------------------------------------------------
passing_bablok <- function(x, y, conf = 0.95) {
  # Passing & Bablok (1983), positive correlation assumed (code review
  # 2026-10, CORR-02):
  #  - slopes S_ij for all pairs i < j; dx = dy = 0 is skipped, dx = 0 with
  #    dy != 0 gives +Inf; slopes of exactly -1 are discarded (decimal data
  #    give e.g. -0.9999999999999999 for a true -1, so |S + 1| < 1e-9 counts)
  #  - K = #(S < -1); beta = shifted median S_((N+1)/2 + K) (N odd) or the
  #    mean of S_(N/2 + K) and S_(N/2 + 1 + K) (N even)
  #  - CI: C = z * sqrt(n (n - 1) (2n + 5) / 18), M1 = round((N - C) / 2),
  #    M2 = N - M1 + 1, bounds S_(M1 + K) and S_(M2 + K); a rank outside
  #    1..N gives -Inf / Inf
  #  - alpha = median(y - beta x); its CI uses the slope CI bounds
  # Verified against an independent exact-arithmetic implementation of the
  # paper and against mcr::mc.paba (slope, intercept and cusum identical;
  # mcr's CI averages two adjacent order statistics and rounds C first, so it
  # can differ from the paper by one order-statistic step).
  n <- length(x)
  S <- numeric(0)
  for (i in seq_len(n - 1)) {
    for (j in (i + 1):n) {
      dx <- x[j] - x[i]
      dy <- y[j] - y[i]
      if (dx != 0) {
        S <- c(S, dy / dx)
      } else if (dy != 0) {
        S <- c(S, Inf)
      }
    }
  }
  S <- sort(S[abs(S + 1) >= 1e-9])
  N <- length(S)
  K <- sum(S < -1)
  at <- function(r) if (r >= 1 && r <= N) S[r] else NA_real_

  beta <- if (N %% 2 == 1) at((N + 1) / 2 + K) else (at(N / 2 + K) + at(N / 2 + 1 + K)) / 2

  z_val    <- qnorm(1 - (1 - conf) / 2)
  C        <- z_val * sqrt(n * (n - 1) * (2 * n + 5) / 18)
  M1       <- round((N - C) / 2)
  M2       <- N - M1 + 1
  slope_lo <- at(M1 + K)
  slope_hi <- at(M2 + K)
  if (is.na(slope_lo)) slope_lo <- -Inf
  if (is.na(slope_hi)) slope_hi <- Inf

  # Intercept and its CI from the slope and the slope CI bounds
  alpha    <- median(y - beta * x)
  alpha_lo <- if (is.finite(slope_hi)) median(y - slope_hi * x) else -Inf
  alpha_hi <- if (is.finite(slope_lo)) median(y - slope_lo * x) else Inf

  list(
    slope        = beta,
    intercept    = alpha,
    slope_ci     = c(slope_lo, slope_hi),
    intercept_ci = c(alpha_lo, alpha_hi),
    n            = n,
    K            = K,
    N_slopes     = N
  )
}

# ---------------------------------------------------------------------------
# Cusum linearity test (Passing & Bablok 1983)
#   residual sign scores: +sqrt(L / l) above the line, -sqrt(l / L) below,
#   0 on the line (l = #above, L = #below); points ordered by their position
#   along the fitted line, D_i = (y_i + x_i / b - a) / sqrt(1 + 1 / b^2);
#   linearity rejected at 5% when max|cusum| > 1.36 * sqrt(L + 1).
# Up to v1.0 a simplified version (ordered by x, unit scores, 1.36 sqrt(n))
# was used and attributed to Passing-Bablok (code review 2026-10, CORR-01).
# ---------------------------------------------------------------------------
cusum_test <- function(x, y, slope, intercept) {
  # A zero or infinite slope leaves residuals / projections undefined
  if (!is.finite(slope) || slope == 0 || !is.finite(intercept)) {
    return(list(max_cs = NA_real_, critical = NA_real_, reject = NA))
  }
  res    <- y - intercept - slope * x
  # points on the line in exact arithmetic can come out as +/-1e-15
  res[abs(res) < 1e-9 * max(1, abs(y))] <- 0
  l_pos  <- sum(res > 0)
  L_neg  <- sum(res < 0)
  if (l_pos == 0 || L_neg == 0) {
    return(list(max_cs = 0, critical = 1.36 * sqrt(L_neg + 1), reject = FALSE))
  }
  score  <- ifelse(res > 0, sqrt(L_neg / l_pos), ifelse(res < 0, -sqrt(l_pos / L_neg), 0))
  D      <- (y + x / slope - intercept) / sqrt(1 + 1 / slope^2)
  cs     <- cumsum(score[order(D)])
  max_cs <- max(abs(cs))
  crit   <- 1.36 * sqrt(L_neg + 1)
  list(max_cs = max_cs, critical = crit, reject = max_cs > crit)
}

# ---------------------------------------------------------------------------
# Run analyses
# ---------------------------------------------------------------------------
pb_res  <- passing_bablok(x, y, conf = conf)
# Passing-Bablok assumes positively correlated methods (it is a method
# comparison); with Kendall's tau <= 0 the estimate is not meaningful
kendall_tau <- suppressWarnings(stats::cor(x, y, method = "kendall"))
cs_res  <- cusum_test(x, y, pb_res$slope, pb_res$intercept)

slope     <- pb_res$slope
intercept <- pb_res$intercept
slope_lo  <- pb_res$slope_ci[1]
slope_hi  <- pb_res$slope_ci[2]
alpha_lo  <- pb_res$intercept_ci[1]
alpha_hi  <- pb_res$intercept_ci[2]
n         <- pb_res$n
conf_pct  <- round(conf * 100)

# Proportionality test (slope = 1)
slope_includes_1 <- (slope_lo <= 1 && slope_hi >= 1)

# Bias test (intercept = 0)
intercept_includes_0 <- (alpha_lo <= 0 && alpha_hi >= 0)

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Passing-Bablok Regression\n")
cat(sprintf("  File: %s   n = %d   Confidence: %d%%\n", basename(data_file), n, conf_pct))
cat("=================================================================\n\n")

if (!is.na(kendall_tau) && kendall_tau <= 0) {
  cat(sprintf("\u26a0\ufe0f  Kendall's tau = %.3f <= 0: Passing-Bablok assumes the two methods are\n", kendall_tau))
  cat("   positively correlated. These results are not meaningful for this data.\n\n")
}
cat(sprintf("  Model: %s = %.4f + %.4f * %s\n\n", ycol, intercept, slope, xcol))

cat("  --- Regression Coefficients ---\n")
cat(sprintf("  Slope     (\u03b2):      %.4f   [%.4f, %.4f]\n", slope, slope_lo, slope_hi))
cat(sprintf("  Intercept (\u03b1):      %.4f   [%.4f, %.4f]\n\n", intercept, alpha_lo, alpha_hi))

cat(sprintf("  --- Proportionality Test (slope = 1) ---\n"))
cat(sprintf("  %d%% CI for slope: [%.4f, %.4f]\n", conf_pct, slope_lo, slope_hi))
if (slope_includes_1) {
  cat("  Slope CI includes 1: methods do not differ proportionally (p > 0.05 equivalent).\n\n")
} else {
  cat("  Slope CI excludes 1: methods differ proportionally.\n\n")
}

cat(sprintf("  --- Systematic Bias Test (intercept = 0) ---\n"))
cat(sprintf("  %d%% CI for intercept: [%.4f, %.4f]\n", conf_pct, alpha_lo, alpha_hi))
if (intercept_includes_0) {
  cat("  Intercept CI includes 0: no constant bias detected.\n\n")
} else {
  cat("  Intercept CI excludes 0: constant bias detected.\n\n")
}

cat("  --- Cusum Linearity Test ---\n")
cat(sprintf("  Max |cusum|: %.4f   Critical value (5%%, 1.36 x sqrt(L + 1)): %.4f\n",
            cs_res$max_cs, cs_res$critical))
if (is.na(cs_res$reject)) {
  cat("  Not evaluable: the slope estimate is zero or infinite.\n\n")
} else if (!cs_res$reject) {
  cat("  Linearity assumption not rejected (p > 0.05).\n\n")
} else {
  cat("  Linearity assumption rejected (p < 0.05). Results may be unreliable.\n\n")
}

cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_LINE <- "#2E5BBA"
COL_IDENT <- "#AAAAAA"
GRID_COL <- "#EEEEEE"

theme_jr <- jr_theme(10)

plot_df <- data.frame(x = x, y = y)

p_plot <- ggplot(plot_df, aes(x = x, y = y)) +
  geom_point(color = COL_LINE, alpha = 0.7, size = 2) +
  # Line of identity (y = x) in grey dashed
  geom_abline(intercept = 0, slope = 1, color = COL_IDENT, linetype = "dashed",
              linewidth = 0.8) +
  # CI bounds as dashed blue lines
  geom_abline(intercept = alpha_lo, slope = slope_lo, color = COL_LINE,
              linetype = "dashed", linewidth = 0.7) +
  geom_abline(intercept = alpha_hi, slope = slope_hi, color = COL_LINE,
              linetype = "dashed", linewidth = 0.7) +
  # PB regression line (solid blue)
  geom_abline(intercept = intercept, slope = slope, color = COL_LINE,
              linewidth = 1) +
  labs(
    title = sprintf("Passing-Bablok Regression  |  slope=%.4f [%.4f, %.4f]  intercept=%.4f",
                    slope, slope_lo, slope_hi, intercept),
    x     = xcol,
    y     = ycol
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_corr_passing_bablok.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

jr_save_titled_png(
  out_file,
  sprintf("Passing-Bablok Regression  |  File: %s  |  n=%d  slope=%.4f  intercept=%.4f  %d%% CI",
          basename(data_file), n, slope, intercept, conf_pct),
  list(p_plot),
  width = 2400,
  height = 1600,
  res = 180
)

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
