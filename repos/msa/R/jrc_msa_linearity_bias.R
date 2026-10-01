# =============================================================================
# jrc_msa_linearity_bias.R
# JR Validated Environment — MSA module
#
# Gauge Linearity and Bias analysis.
# Reads a CSV with columns: part, reference, value.
# Fits a linear regression of bias (measured - reference) vs reference value
# to assess whether gauge accuracy varies across the measurement range.
# Reports linearity slope, per-part bias, significance tests, and saves a
# two-panel PNG to the output directory
# (JR_OUT_DIR, default ~/Downloads).
#
# Usage: jrc_msa_linearity_bias <data.csv> [--tolerance <value>]
#
# Arguments:
#   data.csv             CSV with columns: part, reference, value.
#                        reference = known true value for each part.
#                        All parts must have the same number of replicates.
#   --tolerance <value>  Optional: process tolerance (USL - LSL), used as
#                        the process variation for %Bias and Linearity.
#
# Verdicts follow AIAG MSA 4th ed. and are based on significance, not on
# percentage thresholds (code review 2026-10, MSA-03):
#   Linearity acceptable  <=> the bias = 0 line lies entirely within the 95%
#                             confidence band of the fitted bias line over the
#                             reference range.
#   Bias acceptable       <=> average bias not significantly different from 0
#                             (one-sample t-test on all individual biases).
# The % metrics are reported as information only, with the AIAG definitions:
#   %Linearity = 100 * |slope|           (Linearity = |slope| x process variation)
#   %Bias      = 100 * |average bias| / process variation  (only with --tolerance)
# The regression intercept is the bias extrapolated to reference = 0; it is
# not the average bias.
#
# Version: 1.1
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_msa_linearity_bias <data.csv> [--tolerance <value>]")
}

csv_file  <- args[1]
tolerance <- NA_real_
i <- 2
while (i <= length(args)) {
  if (args[i] == "--tolerance" && i < length(args)) {
    tolerance <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(tolerance) || tolerance <= 0) {
      stop("--tolerance must be a positive number.")
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
# Read and validate data
# ---------------------------------------------------------------------------
if (!file.exists(csv_file)) {
  stop(paste("\u274c File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("part", "reference", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: part, reference, value"))
}

dat$part      <- as.factor(as.character(dat$part))
dat$reference <- suppressWarnings(as.numeric(dat$reference))
dat$value     <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$reference))) stop("\u274c Non-numeric values in 'reference' column.")
if (any(is.na(dat$value)))     stop("\u274c Non-numeric values in 'value' column.")

n_parts <- nlevels(dat$part)
if (n_parts < 2) stop("\u274c At least 2 parts are required.")

# Each part must have a single unique reference value
ref_check <- tapply(dat$reference, dat$part, function(x) length(unique(x)))
if (any(ref_check > 1)) {
  stop("\u274c Each part must have exactly one reference value (multiple found).")
}

# Minimum replicates per part
rep_counts <- table(dat$part)
if (any(rep_counts < 2)) {
  stop("\u274c At least 2 replicates per part are required.")
}

n_total <- nrow(dat)

# ---------------------------------------------------------------------------
# Per-part bias
# ---------------------------------------------------------------------------
part_ref  <- tapply(dat$reference, dat$part, unique)
part_mean <- tapply(dat$value,     dat$part, mean)
part_sd   <- tapply(dat$value,     dat$part, sd)
part_n    <- as.integer(table(dat$part))

part_bias <- part_mean - part_ref

# t-test for H0: bias = 0 per part
part_tstat <- part_bias / (part_sd / sqrt(part_n))
part_df    <- part_n - 1
part_pval  <- 2 * pt(abs(part_tstat), df = part_df, lower.tail = FALSE)

# 95% CI on mean bias per part
part_se    <- part_sd / sqrt(part_n)
part_t95   <- qt(0.975, df = part_df)
part_ci_lo <- part_bias - part_t95 * part_se
part_ci_hi <- part_bias + part_t95 * part_se

# Overall (average) bias across all measurements, with a one-sample t-test
overall_bias <- mean(dat$value - dat$reference)
bias_tt      <- stats::t.test(dat$value - dat$reference, mu = 0)
p_bias       <- bias_tt$p.value
bias_ci      <- as.numeric(bias_tt$conf.int)

# ---------------------------------------------------------------------------
# Linearity regression: bias ~ reference  (all individual observations)
# ---------------------------------------------------------------------------
dat$bias <- dat$value - dat$reference

fit    <- lm(bias ~ reference, data = dat)
cf     <- coef(fit)
slope  <- cf["reference"]
intcpt <- cf["(Intercept)"]

sm     <- summary(fit)
r2     <- sm$r.squared
p_slope  <- coef(sm)["reference",    "Pr(>|t|)"]
p_intcpt <- coef(sm)["(Intercept)", "Pr(>|t|)"]

# Prediction + confidence band for plot
ref_range_vals <- seq(min(dat$reference), max(dat$reference), length.out = 100)
pred_df <- data.frame(reference = ref_range_vals)
pred_out <- predict(fit, newdata = pred_df, interval = "confidence", level = 0.95)
pred_df$fit <- pred_out[, "fit"]
pred_df$lwr <- pred_out[, "lwr"]
pred_df$upr <- pred_out[, "upr"]

# ---------------------------------------------------------------------------
# Verdicts (AIAG, significance based) and % metrics (information only)
# ---------------------------------------------------------------------------
ref_spread <- max(dat$reference) - min(dat$reference)   # range of reference values

# Linearity: is bias = 0 inside the 95% confidence band over the whole range?
zero_in_band      <- all(pred_df$lwr <= 0 & pred_df$upr >= 0)
verdict_linearity <- if (zero_in_band) "ACCEPTABLE" else "NOT ACCEPTABLE"
verdict_bias      <- if (p_bias >= 0.05) "ACCEPTABLE" else "SIGNIFICANT BIAS"

pct_linearity <- 100 * abs(slope)                       # AIAG %Linearity
if (!is.na(tolerance)) {
  linearity_abs    <- abs(slope) * tolerance            # Linearity = |slope| x PV
  pct_overall_bias <- 100 * abs(overall_bias) / tolerance
  lin_abs_label    <- "|slope| \u00d7 tolerance"
} else {
  linearity_abs    <- abs(slope) * ref_spread           # bias change over the range
  pct_overall_bias <- NA_real_
  lin_abs_label    <- "|slope| \u00d7 reference range"
}
pct_bias_txt <- if (is.na(pct_overall_bias)) "n/a (needs --tolerance)" else
  sprintf("%.2f%%", pct_overall_bias)

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Gauge Linearity and Bias Analysis\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Parts:      %d\n", n_parts))
cat(sprintf("  Total obs:  %d\n", n_total))
if (!is.na(tolerance)) {
  cat(sprintf("  Tolerance:  %.4g\n", tolerance))
}
cat("\n")

cat("--- Per-Part Bias -----------------------------------------------\n")
cat(sprintf("  %-8s %10s %10s %10s %10s %10s %10s\n",
            "Part", "Reference", "Mean", "Bias", "95% CI Lo", "95% CI Hi", "p (=0)"))
part_names <- levels(dat$part)
for (j in seq_along(part_names)) {
  pn <- part_names[j]
  cat(sprintf("  %-8s %10.4f %10.4f %10.4f %10.4f %10.4f %10.4f\n",
              pn,
              part_ref[pn],  part_mean[pn], part_bias[pn],
              part_ci_lo[pn], part_ci_hi[pn], part_pval[pn]))
}
cat("\n")

cat("--- Linearity Regression ----------------------------------------\n")
cat(sprintf("  Slope (linearity):  %10.5f   p = %.4f%s\n",
            slope, p_slope,
            if (p_slope < 0.05) "  *" else ""))
cat(sprintf("  Intercept:          %10.5f   p = %.4f%s  (bias extrapolated to reference 0)\n",
            intcpt, p_intcpt,
            if (p_intcpt < 0.05) "  *" else ""))
cat(sprintf("  R\u00b2:                 %10.4f\n\n", r2))

cat("--- Summary -----------------------------------------------------\n")
cat(sprintf("  Average bias:       %10.5f   95%% CI [%.5f, %.5f]   p = %.4f%s\n",
            overall_bias, bias_ci[1], bias_ci[2], p_bias,
            if (p_bias < 0.05) "  *" else ""))
cat(sprintf("  Linearity (abs):    %10.5f  (%s)\n", linearity_abs, lin_abs_label))
cat(sprintf("  %%Linearity:         %9.2f%%  (100 \u00d7 |slope|, information)\n", pct_linearity))
cat(sprintf("  %%Bias:              %10s  (|average bias| / tolerance, information)\n\n", pct_bias_txt))

cat("--- Verdict (AIAG, 95%) -----------------------------------------\n")
cat(sprintf("  Linearity: %s  (bias = 0 line %s the 95%% confidence band of the fit)\n",
            verdict_linearity, if (zero_in_band) "within" else "outside"))
cat(sprintf("  Bias:      %s  (average bias %.5f, p = %.4f)\n",
            verdict_bias, overall_bias, p_bias))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"
COL_REG  <- "#2E5BBA"
COL_ZERO <- "#CC2222"
COL_BIAS <- "#ED7D31"
COL_PT   <- "#333333"

theme_jr <- jr_theme(10)

# --- Panel 1: Bias vs Reference (linearity plot) ---
part_summary_df <- data.frame(
  reference = as.numeric(part_ref),
  bias      = as.numeric(part_bias),
  part      = names(part_bias)
)

p1 <- ggplot() +
  geom_ribbon(data = pred_df,
              aes(x = reference, ymin = lwr, ymax = upr),
              fill = COL_REG, alpha = 0.15) +
  geom_line(data = pred_df,
            aes(x = reference, y = fit),
            color = COL_REG, linewidth = 0.9) +
  geom_hline(yintercept = 0, linetype = "dashed",
             color = COL_ZERO, linewidth = 0.6, alpha = 0.8) +
  geom_jitter(data = dat,
              aes(x = reference, y = bias),
              width = diff(range(dat$reference)) * 0.01,
              size = 1.5, alpha = 0.45, color = COL_PT) +
  geom_point(data = part_summary_df,
             aes(x = reference, y = bias),
             size = 3, color = COL_BIAS, shape = 18) +
  geom_text(data = part_summary_df,
            aes(x = reference, y = bias,
                label = sprintf("P%s\nb=%.4f", part, bias)),
            size = 2.5, vjust = -0.6, color = COL_BIAS) +
  labs(
    title   = sprintf("Linearity  (slope = %.4f, p = %.4f, R\u00b2 = %.3f)",
                      slope, p_slope, r2),
    x       = "Reference Value",
    y       = "Bias (Measured \u2212 Reference)"
  ) +
  theme_jr

# --- Panel 2: Per-part bias bar chart with 95% CI ---
bias_df <- data.frame(
  part   = factor(names(part_bias), levels = names(part_bias)),
  bias   = as.numeric(part_bias),
  ci_lo  = as.numeric(part_ci_lo),
  ci_hi  = as.numeric(part_ci_hi),
  sig    = part_pval < 0.05
)

p2 <- ggplot(bias_df, aes(x = part, y = bias, fill = sig)) +
  geom_col(width = 0.6, show.legend = FALSE) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                width = 0.2, linewidth = 0.6, color = "#555555") +
  geom_hline(yintercept = 0, linetype = "dashed",
             color = COL_ZERO, linewidth = 0.6, alpha = 0.8) +
  geom_text(aes(label = sprintf("%.4f\np=%.3f", bias, part_pval)),
            vjust = ifelse(bias_df$bias >= 0, -0.4, 1.3),
            size = 2.5) +
  scale_fill_manual(values = c("FALSE" = "#9E9E9E", "TRUE" = COL_BIAS)) +
  labs(
    title    = sprintf("Bias by Part  (overall bias = %.4f)", overall_bias),
    subtitle = sprintf("Bias: %s (p = %.3f)  |  Bars shaded orange = p < 0.05",
                       verdict_bias, p_bias),
    x        = "Part",
    y        = "Bias (Measured \u2212 Reference)"
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_msa_linearity_bias.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

jr_save_titled_png(
  out_file,
  sprintf("Linearity & Bias  |  %s  |  Linearity: %s  |  Bias: %s",
          basename(csv_file), verdict_linearity, verdict_bias),
  list(p1, p2),
  nrow = 1,
  ncol = 2,
  width = 2400,
  height = 1100,
  res = 180,
  strip = 0.07
)

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
