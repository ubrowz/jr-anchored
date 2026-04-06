# =============================================================================
# jrc_msa_linearity_bias.R
# JR Validated Environment — MSA module
#
# Gauge Linearity and Bias analysis.
# Reads a CSV with columns: part, reference, value.
# Fits a linear regression of bias (measured - reference) vs reference value
# to assess whether gauge accuracy varies across the measurement range.
# Reports linearity slope, per-part bias, significance tests, and saves a
# two-panel PNG to ~/Downloads/.
#
# Usage: jrc_msa_linearity_bias <data.csv> [--tolerance <value>]
#
# Arguments:
#   data.csv             CSV with columns: part, reference, value.
#                        reference = known true value for each part.
#                        All parts must have the same number of replicates.
#   --tolerance <value>  Optional: process tolerance (USL - LSL).
#                        When supplied, %Bias and %Linearity are reported
#                        relative to tolerance.
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

# Overall (average) bias across all measurements
overall_bias <- mean(dat$value - dat$reference)

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
# % metrics (relative to tolerance if provided, else reference range)
# ---------------------------------------------------------------------------
ref_spread <- max(dat$reference) - min(dat$reference)   # range of reference values
denom      <- if (!is.na(tolerance)) tolerance else ref_spread

linearity_abs <- abs(slope) * ref_spread           # bias change over the reference range
pct_linearity <- 100 * linearity_abs / denom

pct_bias_parts <- 100 * abs(part_bias) / denom
pct_overall_bias <- 100 * abs(overall_bias) / denom

verdict_linearity <- if (pct_linearity < 10) "ACCEPTABLE" else if (pct_linearity < 30) "MARGINAL" else "UNACCEPTABLE"
verdict_bias      <- if (pct_overall_bias < 10) "ACCEPTABLE" else if (pct_overall_bias < 30) "MARGINAL" else "UNACCEPTABLE"

denom_label <- if (!is.na(tolerance)) "tolerance" else "reference range"

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
cat(sprintf("  Intercept (bias):   %10.5f   p = %.4f%s\n",
            intcpt, p_intcpt,
            if (p_intcpt < 0.05) "  *" else ""))
cat(sprintf("  R\u00b2:                 %10.4f\n\n", r2))

cat("--- Summary -----------------------------------------------------\n")
cat(sprintf("  Overall bias:       %10.5f\n", overall_bias))
cat(sprintf("  Linearity (abs):    %10.5f  (|slope| \u00d7 reference range)\n", linearity_abs))
cat(sprintf("  %%Linearity:         %9.2f%%  (vs %s)\n", pct_linearity, denom_label))
cat(sprintf("  %%Bias (overall):    %9.2f%%  (vs %s)\n\n", pct_overall_bias, denom_label))

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %%Linearity: %.2f%%  \u2192  %s%s\n",
            pct_linearity, verdict_linearity,
            if (p_slope >= 0.05) "  (slope not significant)" else ""))
cat(sprintf("  %%Bias:      %.2f%%  \u2192  %s%s\n",
            pct_overall_bias, verdict_bias,
            if (p_intcpt >= 0.05) "  (bias not significant)" else ""))
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
    subtitle = sprintf("%%Bias = %.2f%%  \u2192  %s  |  Bars shaded orange = p < 0.05",
                       pct_overall_bias, verdict_bias),
    x        = "Part",
    y        = "Bias (Measured \u2212 Reference)"
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_msa_linearity_bias.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1100, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.07, 0.93), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Linearity & Bias  |  %s  |  %%Linearity = %.1f%%  %%Bias = %.1f%%  |  %s / %s",
          basename(csv_file), pct_linearity, pct_overall_bias,
          verdict_linearity, verdict_bias),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

dev.off()

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
