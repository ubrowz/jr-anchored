# =============================================================================
# jrc_corr_regression.R
# JR Validated Environment — Correlation Analysis module
#
# Simple linear regression: fits y = b0 + b1*x, reports coefficients,
# R-squared, diagnostics, and saves a two-panel plot (scatter + residuals).
#
# Usage: jrc_corr_regression <data.csv> [--xcol x] [--ycol y] [--conf 0.95]
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_corr_regression <data.csv> [--xcol x] [--ycol y] [--conf 0.95]")
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
# Computation
# ---------------------------------------------------------------------------
fit       <- lm(y ~ x)
sm        <- summary(fit)
b0        <- as.numeric(coef(fit)[1])
b1        <- as.numeric(coef(fit)[2])
r2        <- sm$r.squared
adj_r2    <- sm$adj.r.squared
rse       <- sm$sigma
df_resid  <- sm$df[2]
f_stat    <- sm$fstatistic[1]
f_df1     <- sm$fstatistic[2]
f_df2     <- sm$fstatistic[3]
p_overall <- pf(f_stat, f_df1, f_df2, lower.tail = FALSE)
n         <- length(x)

ci_all   <- confint(fit, level = conf)
b0_lo    <- ci_all[1, 1]; b0_hi <- ci_all[1, 2]
b1_lo    <- ci_all[2, 1]; b1_hi <- ci_all[2, 2]

fitted_vals <- fitted(fit)
resids      <- residuals(fit)

conf_pct   <- round(conf * 100)
p_str      <- if (p_overall < 0.0001) formatC(p_overall, format = "e", digits = 4) else sprintf("%.4f", p_overall)
sig_label  <- if (p_overall < 0.05) "significant" else "not significant"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Simple Linear Regression\n")
cat(sprintf("  File: %s   n = %d   Confidence: %d%%\n", basename(data_file), n, conf_pct))
cat("=================================================================\n\n")

cat(sprintf("  Model: %s = %.4f + %.4f * %s\n\n", ycol, b0, b1, xcol))

cat("  --- Coefficients ---\n")
cat(sprintf("  Intercept (b0):     %.4f   [%.4f, %.4f]\n", b0, b0_lo, b0_hi))
cat(sprintf("  Slope     (b1):     %.4f   [%.4f, %.4f]\n\n", b1, b1_lo, b1_hi))

cat("  --- Model Fit ---\n")
cat(sprintf("  R-squared:          %.4f\n", r2))
cat(sprintf("  Adjusted R-squared: %.4f\n", adj_r2))
cat(sprintf("  Residual SE:        %.4f   (df = %d)\n", rse, df_resid))
cat(sprintf("  F-statistic:        %.4f   p-value: %s   [%s]\n\n", f_stat, p_str, sig_label))

cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot (two-panel: scatter+fit left, residuals vs fitted right)
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_LINE <- "#2E5BBA"
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

p_scatter <- ggplot(plot_df, aes(x = x, y = y)) +
  geom_point(color = COL_LINE, alpha = 0.7, size = 2) +
  geom_smooth(method = "lm", se = TRUE, color = COL_LINE, fill = COL_LINE,
              alpha = 0.15, linewidth = 1) +
  labs(
    title = sprintf("Regression: %s = %.4f + %.4f * %s  (R\u00b2=%.4f)", ycol, b0, b1, xcol, r2),
    x     = xcol,
    y     = ycol
  ) +
  theme_jr

resid_df <- data.frame(fitted = fitted_vals, residuals = resids)

p_resid <- ggplot(resid_df, aes(x = fitted, y = residuals)) +
  geom_point(color = COL_LINE, alpha = 0.7, size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#555555", linewidth = 0.8) +
  labs(
    title = "Residuals vs Fitted",
    x     = "Fitted values",
    y     = "Residuals"
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_corr_regression.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1600, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow    = 3,
  ncol    = 1,
  heights = unit(c(0.06, 0.47, 0.47), "npc")
)))

# Header bar
pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Simple Linear Regression  |  File: %s  |  n=%d  b0=%.4f  b1=%.4f  R\u00b2=%.4f",
          basename(data_file), n, b0, b1, r2),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

# Scatter + fit
pushViewport(viewport(layout.pos.row = 2))
print(p_scatter, vp = viewport())
popViewport()

# Residuals
pushViewport(viewport(layout.pos.row = 3))
print(p_resid, vp = viewport())
popViewport()

dev.off()

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
