# =============================================================================
# jrc_corr_spearman.R
# JR Validated Environment — Correlation Analysis module
#
# Spearman rank correlation — non-parametric alternative to Pearson.
# Does not assume linearity or normality.
#
# Usage: jrc_corr_spearman <data.csv> [--xcol x] [--ycol y]
#
# Version: 1.0
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_corr_spearman <data.csv> [--xcol x] [--ycol y]")
}

data_file <- args[1]
xcol      <- "x"
ycol      <- "y"

i <- 2
while (i <= length(args)) {
  if (args[i] == "--xcol" && i < length(args)) {
    xcol <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--ycol" && i < length(args)) {
    ycol <- args[i + 1]; i <- i + 2
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

SCRIPT_VERSION <- "1.0"   # single source for banner, report and JSON

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
# Computation
# ---------------------------------------------------------------------------
ct    <- cor.test(x, y, method = "spearman", exact = FALSE)
rho   <- as.numeric(ct$estimate)
S_stat <- as.numeric(ct$statistic)
p_val  <- ct$p.value
n      <- length(x)

# Interpretation
abs_rho <- abs(rho)
if (abs_rho < 0.3) {
  strength <- "weak"
} else if (abs_rho <= 0.7) {
  strength <- "moderate"
} else {
  strength <- "strong"
}
direction <- if (rho >= 0) "positive" else "negative"

sig_label <- if (p_val < 0.05) "significant at \u03b1 = 0.05" else "not significant at \u03b1 = 0.05"
p_str <- if (p_val < 0.0001) formatC(p_val, format = "e", digits = 4) else sprintf("%.4f", p_val)

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Spearman Rank Correlation Analysis\n")
cat(sprintf("  File: %s   n = %d\n", basename(data_file), n))
cat("=================================================================\n\n")

cat(sprintf("  Spearman rho:       %.4f\n", rho))
cat(sprintf("  S statistic:        %.4f\n", S_stat))
cat(sprintf("  p-value:            %s   [%s]\n\n", p_str, sig_label))

cat("  Note: Confidence interval for Spearman rho is not computed.\n")
cat("        Use jrc_corr_pearson for CI if normality assumptions hold.\n\n")

cat("  Interpretation:\n")
cat("    |rho| < 0.3  \u2192 weak\n")
cat("    0.3-0.7      \u2192 moderate\n")
cat("    |rho| > 0.7  \u2192 strong\n")
cat(sprintf("  This result: %s %s monotonic association.\n\n", strength, direction))

cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot (scatter of ranks)
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_LINE <- "#2E5BBA"
GRID_COL <- "#EEEEEE"

theme_jr <- jr_theme(10)

plot_df <- data.frame(rx = rank(x), ry = rank(y))

p_plot <- ggplot(plot_df, aes(x = rx, y = ry)) +
  geom_point(color = COL_LINE, alpha = 0.7, size = 2) +
  geom_smooth(method = "lm", se = FALSE, color = COL_LINE, linewidth = 1) +
  labs(
    title = sprintf("Spearman Rank Correlation  |  rho = %.4f  |  p = %s", rho, p_str),
    x     = paste("Rank of", xcol),
    y     = paste("Rank of", ycol)
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_corr_spearman.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

jr_save_titled_png(
  out_file,
  sprintf("Spearman Rank Correlation  |  File: %s  |  n=%d  rho=%.4f  p=%s",
          basename(data_file), n, rho, p_str),
  list(p_plot),
  width = 2400,
  height = 1600,
  res = 180
)

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
