#!/usr/bin/env Rscript
#
# use as: Rscript jrc_bland_altman.R <file1> <col1> <file2> <col2>
#
# "file1"  path to CSV file for method 1 (reference method or device A)
# "col1"   column name in file1 containing the measurements
# "file2"  path to CSV file for method 2 (test method or device B)
# "col2"   column name in file2 containing the measurements
#
# Both files must have the same number of valid observations. Rows are matched
# by position: row 1 of file1 is paired with row 1 of file2.
#
# IMPORTANT! The CSV files must have at least 2 columns each: the first
# column is used for row names, the remaining columns contain data.
#
# Needs the <ggplot2> library.
#
# Performs a Bland-Altman method comparison analysis:
#
#   - Bias (mean difference): method2 - method1
#   - Limits of Agreement (LoA): bias +/- 1.96 * SD(differences)
#   - 95% CIs on bias and LoA (Bland & Altman, 1999)
#   - Proportional bias test: Pearson correlation of differences vs means
#     A significant correlation (p < 0.05) suggests the agreement between
#     methods depends on the magnitude of the measurement.
#
# Saves a Bland-Altman plot as PNG to the output directory (JR_OUT_DIR, default ~/Downloads), showing:
#   - Difference vs mean scatter plot
#   - Bias line (solid blue)
#   - Limits of Agreement (dashed blue)
#   - 95% CI bands on bias and LoA (shaded)
#   - Zero reference line (dashed grey)
#
# Use this script to compare two measurement methods or devices before
# deciding whether they can be used interchangeably in verification testing.
#
# Reference:
#   Bland, J.M., Altman, D.G. (1986). Statistical methods for assessing
#   agreement between two methods of clinical measurement.
#   Lancet, 327(8476), 307-310.
#   Bland, J.M., Altman, D.G. (1999). Measuring agreement in method
#   comparison studies. Statistical Methods in Medical Research, 8(2), 135-160.
#
# Author: Joep Rous
# Version: 1.1

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.1"   # single source for banner, report and JSON

suppressPackageStartupMessages({
  library(ggplot2)
})

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_bland_altman.R <file1> <col1> <file2> <col2>",
    "Example:",
    "  Rscript jrc_bland_altman.R method_a.csv ForceN method_b.csv ForceN",
    sep = "\n"
  ))
}

file1     <- args[1]
input_col1 <- args[2]
file2     <- args[3]
input_col2 <- args[4]
col1      <- make.names(input_col1)
col2      <- make.names(input_col2)

for (f in c(file1, file2)) {
  if (!file.exists(f)) stop(paste("File not found:", f))
}

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

load_col <- function(file_path, col, input_col) {
  dat <- tryCatch(
    read.table(file_path, header = TRUE, sep = ",", dec = ".", row.names = 1),
    error = function(e) stop(paste("Failed to read CSV file:", e$message))
  )
  if (ncol(dat) < 1) {
    stop(paste("The CSV file must have at least 2 columns:", file_path))
  }
  if (!col %in% names(dat)) {
    stop(paste0("Column '", input_col, "' not found in '", file_path, "'. ",
                "Available: ", paste(names(dat), collapse = ", ")))
  }
  dat[[col]]
}

x1_raw <- load_col(file1, col1, input_col1)
x2_raw <- load_col(file2, col2, input_col2)

# Rows are paired by position, so both files must have the same number of
# rows. Check BEFORE pairing: combining vectors of different lengths would
# silently recycle the shorter one (code review 2026-10, COR-23).
if (length(x1_raw) != length(x2_raw)) {
  stop(paste(
    "Files have different numbers of rows.",
    paste("file1:", length(x1_raw)), paste("file2:", length(x2_raw)),
    "Rows are matched by position — both files must have the same number of rows.",
    sep = "\n"
  ))
}

# Remove NA/Inf pairwise
valid  <- is.finite(x1_raw) & is.finite(x2_raw)
n_bad  <- sum(!valid)
if (n_bad > 0) {
  warning(paste(n_bad, "pair(s) removed due to NA or non-finite values."))
}

x1 <- x1_raw[valid]
x2 <- x2_raw[valid]
N  <- length(x1)

if (N < 3) {
  stop(paste("At least 3 paired observations are required. Got:", N))
}

# ---------------------------------------------------------------------------
# Bland-Altman calculations
# ---------------------------------------------------------------------------

means <- (x1 + x2) / 2
diffs <- x2 - x1           # difference: method2 - method1

bias    <- mean(diffs)
sd_diff <- sd(diffs)

# Limits of Agreement
loa_upper <- bias + 1.96 * sd_diff
loa_lower <- bias - 1.96 * sd_diff

# 95% CIs on bias and LoA (Bland & Altman, 1999)
# SE(bias) = sd_diff / sqrt(N)
# SE(LoA)  = sqrt(3 * sd_diff^2 / N)
t_crit    <- qt(0.975, df = N - 1)
se_bias   <- sd_diff / sqrt(N)
se_loa    <- sqrt(3 * sd_diff^2 / N)

bias_ci_lo    <- bias      - t_crit * se_bias
bias_ci_hi    <- bias      + t_crit * se_bias
loa_upper_lo  <- loa_upper - t_crit * se_loa
loa_upper_hi  <- loa_upper + t_crit * se_loa
loa_lower_lo  <- loa_lower - t_crit * se_loa
loa_lower_hi  <- loa_lower + t_crit * se_loa

# Proportional bias test: Pearson correlation of differences vs means
prop_test  <- cor.test(means, diffs, method = "pearson")
prop_r     <- prop_test$estimate
prop_p     <- prop_test$p.value

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

jr_say(" ")
jr_say("✅ Bland-Altman Method Comparison Analysis")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ==========================================")
jr_say(paste("   method 1 (reference): ", file1, "/", input_col1))
jr_say(paste("   method 2 (test):      ", file2, "/", input_col2))
jr_say(paste("   paired observations:  ", N))
jr_say(" ")
jr_say("   Note: difference = method 2 - method 1")
jr_say(" ")

jr_say("   Bias and Limits of Agreement:")
jr_say(" ")
jr_say("   -------------------------------------------------------")
jr_say("    statistic          value         95% CI")
jr_say("   -------------------------------------------------------")
jr_say(sprintf("    bias               %10.4f    [%8.4f, %8.4f]",
                bias, bias_ci_lo, bias_ci_hi))
jr_say(sprintf("    SD of differences  %10.4f",   sd_diff))
jr_say(sprintf("    upper LoA          %10.4f    [%8.4f, %8.4f]",
                loa_upper, loa_upper_lo, loa_upper_hi))
jr_say(sprintf("    lower LoA          %10.4f    [%8.4f, %8.4f]",
                loa_lower, loa_lower_lo, loa_lower_hi))
jr_say("   -------------------------------------------------------")
jr_say(" ")

# Bias interpretation
if (bias_ci_lo <= 0 && bias_ci_hi >= 0) {
  jr_say("✅ Bias: the 95% CI includes zero — no significant systematic bias detected.")
} else if (bias > 0) {
  jr_say("⚠️  Bias: the 95% CI is entirely above zero — method 2 reads systematically higher.")
} else {
  jr_say("⚠️  Bias: the 95% CI is entirely below zero — method 2 reads systematically lower.")
}

jr_say(" ")
jr_say("   Proportional Bias Test (Pearson correlation, differences vs means):")
jr_say(paste("   r =", round(prop_r, 4), "  p =", round(prop_p, 4)))

if (prop_p < 0.05) {
  jr_say("⚠️  Proportional bias detected (p < 0.05).")
  jr_say("   Agreement between methods depends on the magnitude of the measurement.")
  jr_say("   The Limits of Agreement may not be constant across the measurement range.")
  jr_say("   Consider a regression-based method comparison instead.")
} else {
  jr_say("✅ No significant proportional bias (p >= 0.05).")
  jr_say("   Agreement appears consistent across the measurement range.")
}

jr_say(" ")

# ---------------------------------------------------------------------------
# Bland-Altman plot
# ---------------------------------------------------------------------------

df_plot <- data.frame(means = means, diffs = diffs)

p <- ggplot(df_plot, aes(x = means, y = diffs)) +

  # CI bands on LoA (drawn first, behind everything)
  annotate("rect", xmin = -Inf, xmax = Inf,
           ymin = loa_upper_lo, ymax = loa_upper_hi,
           fill = "#AEC6E8", alpha = 0.35) +
  annotate("rect", xmin = -Inf, xmax = Inf,
           ymin = loa_lower_lo, ymax = loa_lower_hi,
           fill = "#AEC6E8", alpha = 0.35) +

  # CI band on bias
  annotate("rect", xmin = -Inf, xmax = Inf,
           ymin = bias_ci_lo, ymax = bias_ci_hi,
           fill = "#AEC6E8", alpha = 0.50) +

  # Zero reference line
  geom_hline(yintercept = 0,       colour = "grey50",  linetype = "dashed",
             linewidth = 0.5) +

  # LoA lines
  geom_hline(yintercept = loa_upper, colour = "#2166AC", linetype = "dashed",
             linewidth = 0.8) +
  geom_hline(yintercept = loa_lower, colour = "#2166AC", linetype = "dashed",
             linewidth = 0.8) +

  # Bias line
  geom_hline(yintercept = bias,      colour = "#2166AC", linetype = "solid",
             linewidth = 0.9) +

  # Data points
  geom_point(colour = "#1A1A2E", size = 2.0, alpha = 0.75) +

  # Annotations: bias and LoA values on right margin
  annotate("text", x = Inf, y = bias,
           label = sprintf("Bias = %.4g", bias),
           hjust = 1.05, vjust = -0.4, size = 3.0,
           colour = "#2166AC", fontface = "bold") +
  annotate("text", x = Inf, y = loa_upper,
           label = sprintf("+1.96 SD = %.4g", loa_upper),
           hjust = 1.05, vjust = -0.4, size = 3.0, colour = "#2166AC") +
  annotate("text", x = Inf, y = loa_lower,
           label = sprintf("-1.96 SD = %.4g", loa_lower),
           hjust = 1.05, vjust =  1.2, size = 3.0, colour = "#2166AC") +

  labs(
    title    = "Bland-Altman Method Comparison",
    subtitle = sprintf(
      "N = %d  |  Bias = %.4g  |  LoA = [%.4g, %.4g]  |  Proportional bias: %s",
      N, bias, loa_lower, loa_upper,
      if (prop_p < 0.05) sprintf("r=%.3f, p=%.3f (significant)", prop_r, prop_p)
      else               sprintf("r=%.3f, p=%.3f (NS)", prop_r, prop_p)
    ),
    x = sprintf("Mean of %s and %s", input_col1, input_col2),
    y = sprintf("Difference (%s - %s)", input_col2, input_col1)
  ) +

  theme_bw(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(size = 8.0, colour = "grey30"),
    panel.grid.minor = element_blank()
  )

# Save PNG to the output directory
datetime_prefix <- format(Sys.time(), "%Y%m%d_%H%M%S")
safe_col1 <- gsub("[^A-Za-z0-9_.-]", "_", input_col1)
safe_col2 <- gsub("[^A-Za-z0-9_.-]", "_", input_col2)
out_file  <- file.path(jr_out_dir(),
                       paste0(datetime_prefix, "_bland_altman_",
                              safe_col1, "_vs_", safe_col2, ".png"))
ggsave(out_file, plot = p, width = 9, height = 6, dpi = 150, bg = "white")
jr_say(paste("✅ Bland-Altman plot saved to:", out_file))
jr_say(" ")
jr_log_output_hashes(c(out_file))
