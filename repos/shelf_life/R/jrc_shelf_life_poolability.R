#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_poolability.R <data.csv>
#
# data.csv     CSV with three columns: batch, time, value.
#              'batch'  — batch identifier (any string or number).
#              'time'   — time point of measurement (numeric; same unit throughout).
#              'value'  — measured property value (numeric).
#              Minimum: 2 batches, 3 time points per batch.
#
# Needs only base R and ggplot2.
#
# Performs the ICH Q1E batch poolability analysis to determine whether
# stability data from multiple batches can be combined for a single shelf
# life estimate.
#
# Two-step ANCOVA approach (ICH Q1E Section 4.5):
#   Step 1 — Test batch-by-time interaction (H0: equal slopes).
#             alpha = 0.25 per ICH Q1E (conservative test to avoid pooling
#             when slopes differ).
#   Step 2 — If Step 1 not significant, test batch main effect (H0: equal
#             intercepts). alpha = 0.25.
#
# Decision:
#   Interaction significant  (p < 0.25)  -> DO NOT POOL. Batches have
#                                            different degradation rates.
#                                            Estimate shelf life per batch.
#   Intercept difference     (p < 0.25)  -> PARTIAL POOL. Same slope, use
#                                            the batch with the lowest (or
#                                            highest, per direction) projection.
#   Both not significant                 -> FULL POOL. Combine all batches
#                                            into a single regression.
#
# Saves a multi-panel PNG to ~/Downloads/ showing per-batch scatter and
# regression lines.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_poolability <data.csv>\n\n")
  cat("  data.csv  CSV with columns: batch, time, value\n\n")
  cat("Example: jrc_shelf_life_poolability stability_batches.csv\n\n")
  quit(status = 0)
}

csv_file <- args[1]

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
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
}))

# ---------------------------------------------------------------------------
# Load and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) {
  stop(paste("\u274c File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("batch", "time", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: batch, time, value"))
}

dat$batch <- as.factor(as.character(dat$batch))
dat$time  <- suppressWarnings(as.numeric(dat$time))
dat$value <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$time)))  stop("\u274c Non-numeric values in 'time' column.")
if (any(is.na(dat$value))) stop("\u274c Non-numeric values in 'value' column.")

n_batches <- nlevels(dat$batch)
if (n_batches < 2) {
  stop("\u274c At least 2 batches are required for poolability analysis.")
}

# Check minimum time points per batch
tp_per_batch <- tapply(dat$time, dat$batch, function(x) length(unique(x)))
if (any(tp_per_batch < 3)) {
  bad <- names(tp_per_batch)[tp_per_batch < 3]
  stop(paste("\u274c At least 3 time points per batch required. Insufficient data for batch(es):",
             paste(bad, collapse = ", ")))
}

n_total <- nrow(dat)

# ---------------------------------------------------------------------------
# ICH Q1E poolability analysis — two-step ANCOVA
# ---------------------------------------------------------------------------

ICH_ALPHA <- 0.25

# Step 1: full model with batch:time interaction
fit_interaction <- lm(value ~ batch * time, data = dat)
fit_parallel    <- lm(value ~ batch + time, data = dat)
fit_pooled      <- lm(value ~ time,         data = dat)

# Test interaction (batch slopes differ?)
anova_interaction <- anova(fit_parallel, fit_interaction)
p_interaction     <- anova_interaction$`Pr(>F)`[2]

# Test batch main effect (batch intercepts differ?) — only meaningful if interaction ns
anova_batch <- anova(fit_pooled, fit_parallel)
p_batch     <- anova_batch$`Pr(>F)`[2]

# Per-batch regressions for reporting
batch_fits <- lapply(levels(dat$batch), function(b) {
  sub_dat <- dat[dat$batch == b, ]
  fit     <- lm(value ~ time, data = sub_dat)
  cf      <- coef(fit)
  sm      <- summary(fit)
  list(
    batch     = b,
    n         = nrow(sub_dat),
    intercept = cf[1],
    slope     = cf[2],
    r2        = sm$r.squared,
    p_slope   = coef(sm)[2, "Pr(>|t|)"]
  )
})

# Poolability decision
if (p_interaction < ICH_ALPHA) {
  decision     <- "DO NOT POOL"
  decision_sym <- "\u274c"
  rationale    <- sprintf(
    "Batch-by-time interaction is significant (p = %.4f < %.2f).\n   Batches have different degradation rates. Estimate shelf life\n   separately for each batch and use the most conservative result.",
    p_interaction, ICH_ALPHA
  )
} else if (p_batch < ICH_ALPHA) {
  decision     <- "PARTIAL POOL"
  decision_sym <- "\u26a0\ufe0f"
  rationale    <- sprintf(
    "Slopes are similar (interaction p = %.4f >= %.2f) but intercepts\n   differ (batch p = %.4f < %.2f). Use the common slope with the batch\n   that has the lowest/worst projected value at the spec limit.",
    p_interaction, ICH_ALPHA, p_batch, ICH_ALPHA
  )
} else {
  decision     <- "FULL POOL"
  decision_sym <- "\u2705"
  rationale    <- sprintf(
    "Neither interaction (p = %.4f) nor batch main effect (p = %.4f)\n   is significant at alpha = %.2f. Combine all batches into a single\n   regression for shelf life estimation.",
    p_interaction, p_batch, ICH_ALPHA
  )
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Batch Poolability Analysis  (ICH Q1E Section 4.5)\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Batches:      %d\n", n_batches))
cat(sprintf("  Total obs:    %d\n", n_total))
cat(sprintf("  ICH Q1E alpha: %.2f  (conservative threshold for poolability)\n\n", ICH_ALPHA))

cat("--- Per-Batch Regressions ---------------------------------------\n")
cat(sprintf("  %-10s %6s %12s %12s %8s %10s\n",
            "Batch", "n", "Intercept", "Slope", "R\u00b2", "p (slope)"))
for (bf in batch_fits) {
  cat(sprintf("  %-10s %6d %12.4f %12.4f %8.4f %10.4f\n",
              bf$batch, bf$n, bf$intercept, bf$slope, bf$r2, bf$p_slope))
}
cat("\n")

cat("--- ANCOVA Summary ----------------------------------------------\n")
cat(sprintf("  Step 1 — Batch:time interaction:  F = %.3f,  p = %.4f  %s\n",
            anova_interaction$F[2],
            p_interaction,
            if (p_interaction < ICH_ALPHA) "  * significant" else "  ns"))
cat(sprintf("  Step 2 — Batch main effect:       F = %.3f,  p = %.4f  %s\n",
            anova_batch$F[2],
            p_batch,
            if (p_batch < ICH_ALPHA) "  * significant" else "  ns"))
cat("\n")

cat("--- Decision ----------------------------------------------------\n")
cat(sprintf("  %s  %s\n\n", decision_sym, decision))
cat(sprintf("  %s\n", rationale))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9),
    legend.position  = "bottom"
  )

p <- ggplot(dat, aes(x = time, y = value, colour = batch)) +
  geom_point(size = 2, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.8, alpha = 0.15) +
  labs(
    title    = sprintf("Batch Poolability  |  Decision: %s", decision),
    subtitle = sprintf("Interaction p = %.4f  |  Batch main effect p = %.4f  |  ICH Q1E alpha = %.2f",
                       p_interaction, p_batch, ICH_ALPHA),
    x        = "Time",
    y        = "Value",
    colour   = "Batch"
  ) +
  theme_jr

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_shelf_life_poolability.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))
ggsave(out_file, plot = p, width = 8, height = 5, dpi = 150, bg = BG)

cat(sprintf("\u2705 Done.\n"))
jr_log_output_hashes(c(out_file))
