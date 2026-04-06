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
    i <- i + 1
  }
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
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

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
x <- x_raw[valid_idx]
y <- y_raw[valid_idx]

if (length(x) < 3) {
  stop(paste("\u274c Need at least 3 complete observations. Found:", length(x)))
}

# ---------------------------------------------------------------------------
# Passing-Bablok algorithm (native implementation)
# ---------------------------------------------------------------------------
passing_bablok <- function(x, y, conf = 0.95) {
  n <- length(x)

  # Step 1: Compute all pairwise slopes (i < j)
  slopes <- numeric(0)
  for (i in seq_len(n - 1)) {
    for (j in (i + 1):n) {
      dx <- x[j] - x[i]
      dy <- y[j] - y[i]
      if (dx != 0) {
        slopes <- c(slopes, dy / dx)
      }
    }
  }
  slopes <- sort(slopes)
  N <- length(slopes)

  # Step 2: Count K = number of slopes strictly less than -1
  K <- sum(slopes < -1)

  # Step 3: Median slope (adjusted by K)
  M <- K + (N + 1) / 2
  if (M == round(M)) {
    beta <- slopes[as.integer(M)]
  } else {
    beta <- (slopes[floor(M)] + slopes[ceiling(M)]) / 2
  }

  # Step 4: Intercept
  alpha <- median(y - beta * x)

  # Step 5: CI for slope
  z_val  <- qnorm(1 - (1 - conf) / 2)
  C      <- z_val * sqrt(n * (n - 1) * (2 * n + 5) / 18)
  M1     <- floor((N - C) / 2) + K + 1
  M2     <- N - floor((N - C) / 2) + K
  M1     <- max(1L, M1)
  M2     <- min(N, M2)
  slope_lo <- slopes[M1]
  slope_hi <- slopes[M2]

  # Step 6: CI for intercept (derived from slope CI bounds)
  alpha_lo <- median(y - slope_hi * x)
  alpha_hi <- median(y - slope_lo * x)

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
# Cusum linearity test
# ---------------------------------------------------------------------------
cusum_test <- function(x, y, slope, intercept) {
  # Sort by x
  ord    <- order(x)
  xs     <- x[ord]; ys <- y[ord]
  fitted <- intercept + slope * xs
  resids <- ys - fitted
  signs  <- sign(resids)
  cs     <- cumsum(signs)
  max_cs <- max(abs(cs))
  n      <- length(x)
  crit   <- 1.36 * sqrt(n)   # KS critical value at 5%
  list(max_cs = max_cs, critical = crit, reject = max_cs > crit)
}

# ---------------------------------------------------------------------------
# Run analyses
# ---------------------------------------------------------------------------
pb_res  <- passing_bablok(x, y, conf = conf)
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
cat(sprintf("  Max cumulative sum: %.4f   Critical value (5%%): %.4f\n",
            cs_res$max_cs, cs_res$critical))
if (!cs_res$reject) {
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

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9)
  )

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
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_corr_passing_bablok.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1600, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Passing-Bablok Regression  |  File: %s  |  n=%d  slope=%.4f  intercept=%.4f  %d%% CI",
          basename(data_file), n, slope, intercept, conf_pct),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_plot, vp = viewport())
popViewport()

dev.off()

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
