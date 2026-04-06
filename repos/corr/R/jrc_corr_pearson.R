# =============================================================================
# jrc_corr_pearson.R
# JR Validated Environment — Correlation Analysis module
#
# Pearson product-moment correlation with 95% CI (Fisher z-transformation)
# and two-sided hypothesis test.
#
# Usage: jrc_corr_pearson <data.csv> [--xcol x] [--ycol y] [--conf 0.95]
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_corr_pearson <data.csv> [--xcol x] [--ycol y] [--conf 0.95]")
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
ct  <- cor.test(x, y, method = "pearson", conf.level = conf)
r   <- as.numeric(ct$estimate)
t_stat <- as.numeric(ct$statistic)
p_val  <- ct$p.value
ci_lo  <- ct$conf.int[1]
ci_hi  <- ct$conf.int[2]
n      <- length(x)
df_val <- ct$parameter

# Interpretation
abs_r <- abs(r)
if (abs_r < 0.3) {
  strength <- "weak"
} else if (abs_r <= 0.7) {
  strength <- "moderate"
} else {
  strength <- "strong"
}
direction <- if (r >= 0) "positive" else "negative"

sig_label <- if (p_val < 0.05) "significant at \u03b1 = 0.05" else "not significant at \u03b1 = 0.05"
p_str <- if (p_val < 0.0001) formatC(p_val, format = "e", digits = 4) else sprintf("%.4f", p_val)
conf_pct <- round(conf * 100)

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Pearson Correlation Analysis\n")
cat(sprintf("  File: %s   n = %d   Confidence: %d%%\n", basename(data_file), n, conf_pct))
cat("=================================================================\n\n")

cat(sprintf("  Pearson r:          %.4f   (df = %d)\n", r, df_val))
cat(sprintf("  %d%% CI:             [%.4f, %.4f]   (Fisher z)\n", conf_pct, ci_lo, ci_hi))
cat(sprintf("  t-statistic:        %.4f\n", t_stat))
cat(sprintf("  p-value:            %s   [%s]\n\n", p_str, sig_label))

cat("  Interpretation:\n")
cat("    |r| < 0.3  \u2192 weak\n")
cat("    0.3-0.7    \u2192 moderate\n")
cat("    |r| > 0.7  \u2192 strong\n")
cat(sprintf("  This result: %s %s correlation.\n\n", strength, direction))

cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
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

p_plot <- ggplot(plot_df, aes(x = x, y = y)) +
  geom_point(color = COL_LINE, alpha = 0.7, size = 2) +
  geom_smooth(method = "lm", se = FALSE, color = COL_LINE, linewidth = 1) +
  labs(
    title = sprintf("Pearson Correlation  |  r = %.4f  |  p = %s", r, p_str),
    x     = xcol,
    y     = ycol
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_corr_pearson.png"))

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
  sprintf("Pearson Correlation  |  File: %s  |  n=%d  r=%.4f  p=%s  %d%% CI",
          basename(data_file), n, r, p_str, conf_pct),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_plot, vp = viewport())
popViewport()

dev.off()

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
