# =============================================================================
# jrc_cap_nonnormal.R
# JR Validated Environment — Process Capability module
#
# Process Capability Analysis for non-normally distributed data.
# Uses the percentile method (ISO 22514-2 / AIAG): process spread is
# estimated from the 0.135th and 99.865th sample percentiles (equivalent
# to ±3σ for a normal distribution) rather than from the standard deviation.
# Also performs a Shapiro-Wilk normality test and warns if data appear normal.
#
# Usage: jrc_cap_nonnormal <data.csv> <col> <lsl> <usl>
#
# <lsl> and <usl> may each be "-" to omit one-sided. At least one must be a number.
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) {
  stop("Usage: jrc_cap_nonnormal <data.csv> <col> <lsl> <usl>\n  Use '-' for <lsl> or <usl> to analyse one-sided.")
}

data_file <- args[1]
col_name  <- args[2]
lsl_arg   <- args[3]
usl_arg   <- args[4]

lsl <- if (lsl_arg == "-") NA_real_ else suppressWarnings(as.numeric(lsl_arg))
usl <- if (usl_arg == "-") NA_real_ else suppressWarnings(as.numeric(usl_arg))

if (is.na(lsl) && lsl_arg != "-") stop("LSL must be a number or '-'.")
if (is.na(usl) && usl_arg != "-") stop("USL must be a number or '-'.")
if (is.na(lsl) && is.na(usl))     stop("At least one of LSL or USL must be provided.")
if (!is.na(lsl) && !is.na(usl) && lsl >= usl) stop("LSL must be less than USL.")

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------
renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided wrapper.")
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

if (!col_name %in% names(df)) {
  stop(paste("\u274c Column not found in CSV:", col_name))
}

x_raw <- suppressWarnings(as.numeric(df[[col_name]]))
if (all(is.na(x_raw))) stop(paste("\u274c Column", col_name, "is not numeric."))

x <- x_raw[!is.na(x_raw)]
n <- length(x)

if (n < 5) {
  stop(paste("\u274c Need at least 5 observations. Found:", n))
}

# ---------------------------------------------------------------------------
# Normality check (advisory only — does not block execution)
# ---------------------------------------------------------------------------
sw_result <- shapiro.test(x)
sw_p      <- sw_result$p.value
normal_flag <- sw_p >= 0.05

if (normal_flag) {
  cat(sprintf("\u26a0 Note: Shapiro-Wilk p = %.4f (\u2265 0.05). Data may be approximately normal.\n", sw_p))
  cat("   Consider jrc_cap_normal for a within-sigma Cpk analysis.\n\n")
} else {
  cat(sprintf("  Shapiro-Wilk: W = %.4f, p = %.4f (< 0.05) — non-normal distribution confirmed.\n\n",
              sw_result$statistic, sw_p))
}

# ---------------------------------------------------------------------------
# Computation — percentile method
# ---------------------------------------------------------------------------

x_bar   <- mean(x)
x_med   <- median(x)
s       <- sd(x)

# Key percentiles: 0.135% and 99.865% correspond to ±3σ for normal
p_lo    <- quantile(x, probs = 0.00135, type = 7)   # 0.135th percentile
p_hi    <- quantile(x, probs = 0.99865, type = 7)   # 99.865th percentile
p_med   <- quantile(x, probs = 0.50,   type = 7)

has_both   <- !is.na(lsl) && !is.na(usl)
spec_width <- if (has_both) usl - lsl else NA_real_

# Pp (percentile method — requires both limits)
Pp_pct <- if (has_both) spec_width / (p_hi - p_lo) else NA_real_

# Ppk components (percentile method)
ppk_u <- if (!is.na(usl)) (usl - p_med) / (p_hi - p_med) else NA_real_
ppk_l <- if (!is.na(lsl)) (p_med - lsl) / (p_med - p_lo) else NA_real_
Ppk_pct <- min(c(ppk_u, ppk_l), na.rm = TRUE)

# Observed % out of spec
pct_above <- if (!is.na(usl)) mean(x > usl) * 100 else NA_real_
pct_below <- if (!is.na(lsl)) mean(x < lsl) * 100 else NA_real_

# Verdict
verdict <- if (Ppk_pct >= 1.67) {
  "EXCELLENT  (Ppk \u2265 1.67)"
} else if (Ppk_pct >= 1.33) {
  "CAPABLE    (Ppk \u2265 1.33)"
} else if (Ppk_pct >= 1.00) {
  "MARGINAL   (1.00 \u2264 Ppk < 1.33)"
} else {
  "NOT CAPABLE (Ppk < 1.00)"
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Process Capability Analysis (Non-Normal, Percentile Method)\n")
cat(sprintf("  File: %s   Col: %s   n = %d\n",
            basename(data_file), col_name, n))
cat(sprintf("  LSL: %s   USL: %s\n",
            if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl),
            if (is.na(usl)) "(none)" else sprintf("%.4f", usl)))
cat("=================================================================\n\n")

cat("  Descriptives:\n")
cat(sprintf("    Mean:               %.4f\n",  x_bar))
cat(sprintf("    Median (P50):       %.4f\n",  x_med))
cat(sprintf("    SD:                 %.4f\n",  s))
cat(sprintf("    Min:                %.4f\n",  min(x)))
cat(sprintf("    Max:                %.4f\n",  max(x)))
cat("\n")

cat("  Distribution percentiles (equivalent to \u00b13\u03c3 boundaries):\n")
cat(sprintf("    P0.135  (low tail):  %.4f\n",  as.numeric(p_lo)))
cat(sprintf("    P50     (median):    %.4f\n",  as.numeric(p_med)))
cat(sprintf("    P99.865 (high tail): %.4f\n",  as.numeric(p_hi)))
cat(sprintf("    Estimated spread:    %.4f  (P99.865 \u2212 P0.135)\n\n",
            as.numeric(p_hi) - as.numeric(p_lo)))

cat("  Performance indices (percentile method):\n")
if (!is.na(Pp_pct))  cat(sprintf("    Pp  (percentile):   %.4f\n", Pp_pct))
cat(sprintf("    Ppk (percentile):   %.4f\n", Ppk_pct))
cat("\n")

cat("  Observed non-conformance:\n")
if (!is.na(pct_below)) cat(sprintf("    Below LSL:          %.2f%%\n", pct_below))
if (!is.na(pct_above)) cat(sprintf("    Above USL:          %.2f%%\n", pct_above))
cat("\n")

cat(sprintf("  Normality (Shapiro-Wilk): W = %.4f, p = %.4f\n\n",
            sw_result$statistic, sw_p))

cat("--- Verdict ---------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

cat("  Note: Percentile method uses sample quantiles to estimate process\n")
cat("  spread without assuming normality. Ppk \u2265 1.33 is a common\n")
cat("  acceptance criterion for non-normal process validation.\n\n")

# ---------------------------------------------------------------------------
# Plot — histogram with KDE and spec limits
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_HIST <- "#F5C8A0"
COL_KDE  <- "#C0392B"
COL_LSL  <- "#C0392B"
COL_USL  <- "#C0392B"
COL_MEAN <- "#1A1A2E"
COL_P    <- "#2E5BBA"
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

plot_df <- data.frame(value = x)
bw      <- max(diff(range(x)) / 30, s / 5)

# KDE scaled to histogram counts
kde       <- density(x, adjust = 1.0)
kde_scale <- n * bw
kde_df    <- data.frame(x = kde$x, y = kde$y * kde_scale)

cap_label <- if (!is.na(Pp_pct)) {
  sprintf("Pp=%.2f  Ppk=%.2f  (percentile)", Pp_pct, Ppk_pct)
} else {
  sprintf("Ppk=%.2f  (percentile)", Ppk_pct)
}

p_hist <- ggplot(plot_df, aes(x = value)) +
  geom_histogram(binwidth = bw, fill = COL_HIST, color = "white", alpha = 0.9) +
  geom_line(data = kde_df, aes(x = x, y = y),
            color = COL_KDE, linewidth = 1) +
  geom_vline(xintercept = x_bar, linetype = "solid",
             color = COL_MEAN, linewidth = 0.8) +
  labs(
    title = sprintf("Process Capability (Non-Normal)  |  %s", cap_label),
    x     = col_name,
    y     = "Count"
  ) +
  theme_jr

if (!is.na(lsl)) {
  p_hist <- p_hist +
    geom_vline(xintercept = lsl, linetype = "dashed",
               color = COL_LSL, linewidth = 1) +
    annotate("text", x = lsl, y = Inf,
             label = sprintf("LSL\n%.4g", lsl),
             hjust = 1.1, vjust = 1.5, color = COL_LSL, size = 3, fontface = "bold")
}
if (!is.na(usl)) {
  p_hist <- p_hist +
    geom_vline(xintercept = usl, linetype = "dashed",
               color = COL_USL, linewidth = 1) +
    annotate("text", x = usl, y = Inf,
             label = sprintf("USL\n%.4g", usl),
             hjust = -0.1, vjust = 1.5, color = COL_USL, size = 3, fontface = "bold")
}
# P0.135 and P99.865 markers
p_hist <- p_hist +
  geom_vline(xintercept = as.numeric(p_lo), linetype = "dotted",
             color = COL_P, linewidth = 0.7) +
  geom_vline(xintercept = as.numeric(p_hi), linetype = "dotted",
             color = COL_P, linewidth = 0.7)

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_cap_nonnormal.png"))

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
  sprintf("Cap Non-Normal  |  %s  |  n=%d  Ppk=%.4f  %s",
          basename(data_file), n, Ppk_pct, verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_hist, vp = viewport())
popViewport()

dev.off()

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
