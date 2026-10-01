#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_linear.R <data.csv> <spec_limit> <confidence>
#                                          [--direction low|high]
#                                          [--transform log]
#                                          [--pool auto|full|partial|none]
#
# data.csv      Two-column CSV with headers 'time' and 'value'. One row per
#               unit tested (pull-and-test / cross-sectional design). Do NOT
#               supply aggregated time-point means — individual measurements
#               are required so that both within-time-point and between-time-
#               point variability are correctly propagated into the confidence
#               bounds. Example: 6 time points x 3 units per point = 18 rows.
# spec_limit    The specification limit (numeric). The one-sided confidence
#               bound of the predicted mean must not cross this value.
# confidence    One-sided confidence level for the shelf life estimate
#               (e.g. 0.95, as specified by ICH Q1E). Must be > 0.5.
# --direction   'low'  — value must stay ABOVE spec_limit (default).
#                        Used for degrading properties (e.g. peel strength).
#               'high' — value must stay BELOW spec_limit.
#                        Used for growing properties (e.g. impurity level).
# batch column  Optional. With a 'batch' column (>= 2 batches) the model follows
#               the ICH Q1E poolability decision (same test as
#               jrc_shelf_life_poolability, alpha = 0.25):
#                 full    — one regression on all batches
#                 partial — common slope, separate batch intercepts
#                 none    — a separate regression per batch
#               Shelf life is the earliest crossing over the batches; the
#               limiting batch is reported (code review 2026-10, SL-03).
# --pool        'auto' (default: the poolability decision) or force
#               'full' / 'partial' / 'none'. Requires a batch column.
# --transform   'log'  — fit lm(log(value) ~ time); CI is back-transformed
#                        via exp() before comparing to spec_limit. Use when
#                        residuals are right-skewed or variance grows with
#                        the mean (log-normal data). All values must be > 0.
#               'none' — no transformation (default).
#
# Needs only base R and ggplot2.
#
# Fits lm(value ~ time) [or lm(log(value) ~ time)] on all individual
# measurements. Performs a Brown-Forsythe homogeneity-of-variance test across
# time groups (robust to non-normal distributions — does not assume normality).
# Reports shelf life as the time at which the ONE-SIDED confidence bound
# (ICH Q1E: one-sided 95 %; computed as one limit of the two-sided
# (2C - 1) interval, i.e. t(C, n-2)) of the
# predicted mean (lower for 'low', upper for 'high') crosses spec_limit.
# Saves a PNG plot and a model coefficient CSV to the output directory
# (JR_OUT_DIR, default ~/Downloads).
# The model CSV can be used as input to jrc_shelf_life_extrapolate (for a
# batch model: the limiting batch's line, with its residual df).
#
# Verdict (report / JSON): PASS when the confidence bound does not cross the
# spec limit within the observed time range (shelf life >= last time point),
# FAIL when it crosses earlier (code review 2026-10, SL-02).
#
# Author: Joep Rous
# Version: 1.3

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_linear <data.csv> <spec_limit> <confidence> [--direction low|high] [--transform log]\n\n")
  cat("  data.csv      CSV with columns: time, value (one row per test unit)\n")
  cat("  spec_limit    Specification limit (numeric)\n")
  cat("  confidence    Confidence level, e.g. 0.95\n")
  cat("  --direction   'low' (value must stay above limit, default) or\n")
  cat("                'high' (value must stay below limit)\n")
  cat("  --transform   'log' — fit on log(value); use for right-skewed data\n")
  cat("                'none' (default)\n")
  cat("  --pool        With a 'batch' column: 'auto' (ICH Q1E poolability\n")
  cat("                decision, default), 'full', 'partial' or 'none'\n\n")
  cat("Example: jrc_shelf_life_linear stability_data.csv 80.0 0.95\n")
  cat("         jrc_shelf_life_linear stability_data.csv 80.0 0.95 --transform log\n\n")
  quit(status = 0)
}

# Parse --direction and --transform flags
direction <- "low"
transform <- "none"
pool_opt  <- NA_character_
clean_args <- c()
i <- 1
while (i <= length(args)) {
  if (args[i] == "--direction" && i < length(args)) {
    direction <- tolower(args[i + 1])
    if (!direction %in% c("low", "high")) {
      stop(paste("\u274c --direction must be 'low' or 'high'. Got:", args[i + 1]))
    }
    i <- i + 2
  } else if (args[i] == "--pool" && i < length(args)) {
    pool_opt <- tolower(args[i + 1])
    if (!pool_opt %in% c("auto", "full", "partial", "none")) {
      stop(paste("\u274c --pool must be 'auto', 'full', 'partial' or 'none'. Got:", args[i + 1]))
    }
    i <- i + 2
  } else if (args[i] == "--transform" && i < length(args)) {
    transform <- tolower(args[i + 1])
    if (!transform %in% c("none", "log")) {
      stop(paste("\u274c --transform must be 'none' or 'log'. Got:", args[i + 1]))
    }
    i <- i + 2
  } else {
    clean_args <- c(clean_args, args[i])
    i <- i + 1
  }
}

if (length(clean_args) < 3) {
  stop("Not enough arguments. Usage: jrc_shelf_life_linear <data.csv> <spec_limit> <confidence> [--direction low|high] [--transform log]")
}

csv_file   <- clean_args[1]
spec_limit <- suppressWarnings(as.numeric(clean_args[2]))
confidence <- suppressWarnings(as.numeric(clean_args[3]))

if (is.na(spec_limit)) stop(paste("\u274c 'spec_limit' must be a number. Got:", clean_args[2]))
if (is.na(confidence) || confidence <= 0.5 || confidence >= 1) {
  stop(paste("\u274c 'confidence' must be a one-sided confidence level between 0.5 and 1 (e.g. 0.95). Got:", clean_args[3]))
}

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "1.3"   # single source for banner, report and JSON

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(base64enc)
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

required_cols <- c("time", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: time, value"))
}

dat$time  <- suppressWarnings(as.numeric(dat$time))
dat$value <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$time)))  stop("\u274c Non-numeric values in 'time' column.")
if (any(is.na(dat$value))) stop("\u274c Non-numeric values in 'value' column.")

has_batch <- "batch" %in% names(dat) && length(unique(dat$batch)) >= 2
if (!is.na(pool_opt) && !has_batch) {
  stop("\u274c --pool requires a 'batch' column with at least 2 batches.")
}
if (has_batch) {
  dat$batch <- as.character(dat$batch)
  if (any(is.na(dat$batch) | !nzchar(trimws(dat$batch)))) stop("\u274c Empty values in 'batch' column.")
}

if (transform == "log" && any(dat$value <= 0)) {
  stop("\u274c --transform log requires all values to be strictly positive. Found values <= 0.")
}

n_total     <- nrow(dat)
n_timepoints <- length(unique(dat$time))

if (n_total < 4) stop("\u274c At least 4 observations are required.")
if (n_timepoints < 3) stop("\u274c At least 3 distinct time points are required.")

time_group_sizes <- table(dat$time)
n_units_per_tp   <- as.integer(time_group_sizes)
if (any(n_units_per_tp < 1)) stop("\u274c Each time point must have at least one observation.")

# Warn if only one obs per time point (aggregated means suspected)
if (all(n_units_per_tp == 1)) {
  cat("\u26a0\ufe0f  Each time point has exactly 1 observation. If this represents an\n")
  cat("   aggregated mean rather than a single test unit, the confidence\n")
  cat("   bounds will be underestimated. Use individual measurements.\n\n")
}

# ---------------------------------------------------------------------------
# Brown-Forsythe homogeneity-of-variance test
# Robust to non-normality — uses absolute deviations from group medians.
# Equivalent to car::leveneTest(..., center = median).
# ---------------------------------------------------------------------------

brown_forsythe_test <- function(time_vec, value_vec) {
  groups <- split(value_vec, time_vec)
  if (length(groups) < 2) return(list(stat = NA_real_, p_value = NA_real_))

  z_vals   <- unlist(lapply(groups, function(g) abs(g - median(g))))
  grp_lbls <- rep(names(groups), sapply(groups, length))

  fit    <- lm(z_vals ~ factor(grp_lbls))
  a      <- anova(fit)
  list(stat = a$`F value`[1], p_value = a$`Pr(>F)`[1])
}

bf_values <- if (transform == "log") log(dat$value) else dat$value
bf <- brown_forsythe_test(dat$time, bf_values)

# ---------------------------------------------------------------------------
# Linear regression (on transformed scale if requested)
# ---------------------------------------------------------------------------

y_term <- if (transform == "log") "log(value)" else "value"

# Batch model (SL-03): "single" without a batch column, else the ICH Q1E
# poolability decision or the forced --pool model.
pool_res   <- NULL
pool_model <- "single"
if (has_batch) {
  y_scale    <- if (transform == "log") log(dat$value) else dat$value
  pool_res   <- jr_shelf_poolability(dat$batch, dat$time, y_scale)
  pool_model <- if (is.na(pool_opt) || pool_opt == "auto") pool_res$model else pool_opt
}
batches <- if (has_batch) sort(unique(dat$batch)) else NA_character_

# One "unit" per regression line whose confidence bound is evaluated:
# fit, newdata builder and the data subset it describes
if (pool_model %in% c("single", "full")) {
  fit_all <- lm(as.formula(paste(y_term, "~ time")), data = dat)
  units <- list(list(label = if (pool_model == "full") "all batches (pooled)" else NA_character_,
                     fit = fit_all, nd = function(t) data.frame(time = t), sub = dat))
} else if (pool_model == "partial") {
  fit_all <- lm(as.formula(paste(y_term, "~ batch + time")), data = dat)
  units <- lapply(batches, function(b) {
    list(label = b, fit = fit_all,
         nd = function(t) data.frame(time = t, batch = b), sub = dat[dat$batch == b, ])
  })
} else {
  units <- lapply(batches, function(b) {
    sub_b <- dat[dat$batch == b, ]
    if (nrow(sub_b) < 3 || length(unique(sub_b$time)) < 2) {
      stop(paste0("\u274c Batch '", b, "' needs at least 3 observations at 2 or more time points ",
                  "for a separate regression (--pool none)."))
    }
    list(label = b, fit = lm(as.formula(paste(y_term, "~ time")), data = sub_b),
         nd = function(t) data.frame(time = t), sub = sub_b)
  })
}

# ---------------------------------------------------------------------------
# Check specification at t = min(time): fail if already violated
# ---------------------------------------------------------------------------

t_min  <- min(dat$time)
t_max  <- max(dat$time)

ci_bound_at_t <- function(t, u) {
  # One-sided bound at level C = one limit of the two-sided (2C - 1) interval
  pred <- predict(u$fit, newdata = u$nd(t),
                  interval = "confidence", level = 2 * confidence - 1)
  raw <- if (direction == "low") pred[1, "lwr"] else pred[1, "upr"]
  if (transform == "log") exp(raw) else raw
}

unit_tag <- function(u) if (is.na(u$label)) "" else paste0(" (batch ", u$label, ")")
for (u in units) {
  bound_at_tmin <- ci_bound_at_t(t_min, u)
  if (direction == "low" && bound_at_tmin < spec_limit) {
    stop(sprintf(
      "\u274c Lower one-sided %.0f%% confidence bound (%.4f) is already below the spec limit (%.4f)\n   at the first time point (t = %g)%s. Product does not meet spec at t=0.",
      confidence * 100, bound_at_tmin, spec_limit, t_min, unit_tag(u)
    ))
  }
  if (direction == "high" && bound_at_tmin > spec_limit) {
    stop(sprintf(
      "\u274c Upper one-sided %.0f%% confidence bound (%.4f) is already above the spec limit (%.4f)\n   at the first time point (t = %g)%s. Product does not meet spec at t=0.",
      confidence * 100, bound_at_tmin, spec_limit, t_min, unit_tag(u)
    ))
  }
}

# ---------------------------------------------------------------------------
# Shelf life estimate — find t where CI bound crosses spec_limit (per unit;
# the earliest crossing over the batches is the shelf life)
# ---------------------------------------------------------------------------

t_search_max <- t_max * 20

unit_sl <- vapply(units, function(u) {
  bound_at_end <- ci_bound_at_t(t_search_max, u)
  crosses <- (direction == "low"  && bound_at_end < spec_limit) ||
             (direction == "high" && bound_at_end > spec_limit)
  if (!crosses) return(NA_real_)
  uniroot(function(t) ci_bound_at_t(t, u) - spec_limit,
          interval = c(t_min, t_search_max), tol = 1e-6)$root
}, numeric(1))

crossing_exists <- any(!is.na(unit_sl))
lim_idx         <- if (crossing_exists) which.min(unit_sl) else 1L
lim_unit        <- units[[lim_idx]]
shelf_life      <- if (crossing_exists) unit_sl[lim_idx] else NA_real_

if (!crossing_exists) {
  shelf_life_label <- sprintf("> %.4g", t_search_max)
  cat(sprintf(
    "\u26a0\ufe0f  The one-sided %.0f%% confidence bound does not cross the spec limit within %.4g\n   time units (20x observed range). Shelf life appears very long or the\n   slope is negligible.\n\n",
    confidence * 100, t_search_max
  ))
} else {
  shelf_life_label <- sprintf("%.4f", shelf_life)
}

# Verdict (SL-02): the bound must not cross the spec limit within the
# observed time range
verdict_pass <- !crossing_exists || shelf_life >= t_max

# Reported regression: the limiting unit's line
fit    <- lim_unit$fit
cf     <- coef(fit)
b1     <- cf["time"]
b0     <- if (pool_model == "partial") {
  coef_b <- paste0("batch", lim_unit$label)
  cf["(Intercept)"] + (if (coef_b %in% names(cf)) cf[coef_b] else 0)
} else cf["(Intercept)"]
sm     <- summary(fit)
r2     <- sm$r.squared
sigma  <- sm$sigma
df_res <- fit$df.residual
t_bar  <- mean(lim_unit$sub$time)
Sxx    <- if (pool_model == "partial") {
  # common slope: within-batch sum of squares of time
  sum(vapply(split(dat$time, dat$batch), function(tt) sum((tt - mean(tt))^2), numeric(1)))
} else sum((lim_unit$sub$time - t_bar)^2)
n_line <- nrow(lim_unit$sub)

p_intercept <- if (pool_model == "partial") NA_real_ else coef(sm)["(Intercept)", "Pr(>|t|)"]
p_slope     <- coef(sm)["time", "Pr(>|t|)"]

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

bound_label <- if (direction == "low") "Lower" else "Upper"
ci_pct      <- sprintf("one-sided %.0f%%", confidence * 100)

cat("\n")
cat("=================================================================\n")
cat("  Shelf Life Estimation — Linear Degradation Model\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Observations:    %d\n", n_total))
cat(sprintf("  Time points:     %d  (t_min = %g, t_max = %g)\n",
            n_timepoints, t_min, t_max))
cat(sprintf("  Spec limit:      %g  (%s bound)\n",
            spec_limit, if (direction == "low") "lower" else "upper"))
cat(sprintf("  Confidence:      %s\n", ci_pct))
cat(sprintf("  Direction:       %s  (%s)\n", direction,
            if (direction == "low") "value must stay above spec"
            else "value must stay below spec"))
cat(sprintf("  Transform:       %s\n\n",
            if (transform == "log") "log  (fit on log(value); CI back-transformed via exp)"
            else "none"))

cat("--- Homogeneity of Variance (Brown-Forsythe) --------------------\n")
if (!is.na(bf$p_value)) {
  if (bf$p_value >= 0.05) {
    cat(sprintf("  \u2705 Variance homogeneous  (Brown-Forsythe F = %.3f,  p = %.4f)\n\n",
                bf$stat, bf$p_value))
  } else {
    cat(sprintf("  \u26a0\ufe0f Variance may be heterogeneous  (Brown-Forsythe F = %.3f,  p = %.4f)\n",
                bf$stat, bf$p_value))
    cat("   Variance changes significantly across time points. Consider\n")
    cat("   weighted regression or log transformation. Results below\n")
    cat("   are from unweighted regression — treat with caution.\n\n")
  }
} else {
  cat("  (test not applicable — fewer than 2 groups)\n\n")
}

if (has_batch) {
  model_txt <- switch(pool_model,
    full    = "FULL POOL — one regression on all batches",
    partial = "PARTIAL POOL — common slope, separate batch intercepts",
    none    = "DO NOT POOL — separate regression per batch")
  cat("--- Batch Poolability (ICH Q1E, alpha = 0.25) -------------------\n")
  cat(sprintf("  Batches: %d   Interaction p = %.4f   Batch p = %.4f\n",
              length(batches), pool_res$p_interaction, pool_res$p_batch))
  cat(sprintf("  Model:   %s%s\n", model_txt,
              if (!is.na(pool_opt) && pool_opt != "auto") "  [forced by --pool]" else ""))
  if (pool_model != "full") {
    for (k in seq_along(units)) {
      cat(sprintf("    batch %-10s shelf life: %s%s\n", units[[k]]$label,
                  if (is.na(unit_sl[k])) sprintf("> %.4g", t_search_max) else sprintf("%.4f", unit_sl[k]),
                  if (k == lim_idx && crossing_exists) "  <- limiting" else ""))
    }
  }
  cat("\n")
}

reg_label <- if (transform == "log") "log(value) ~ time" else "value ~ time"
if (pool_model %in% c("partial", "none")) {
  reg_label <- paste0(reg_label, ", limiting batch ", lim_unit$label)
}
cat(sprintf("--- Regression: %s ------------------------------------\n", reg_label))
if (is.na(p_intercept)) {
  cat(sprintf("  Intercept:  %12.5f   (batch intercept in the common-slope model)\n", b0))
} else {
  cat(sprintf("  Intercept:  %12.5f   p = %.4f\n", b0, p_intercept))
}
slope_note <- if (p_slope >= 0.05) "  (not significant — rate of change not confirmed)" else ""
if (transform == "log") {
  cat(sprintf("  Slope:      %12.5f   p = %.4f%s\n", b1, p_slope, slope_note))
  cat(sprintf("  (slope is on log scale: %.4f%% change per unit time)\n", (exp(b1) - 1) * 100))
} else {
  cat(sprintf("  Slope:      %12.5f   p = %.4f%s\n", b1, p_slope, slope_note))
}
cat(sprintf("  R\u00b2:         %12.4f\n\n", r2))

cat("--- Shelf Life Estimate -----------------------------------------\n")
cat(sprintf("  %s %s CI bound crosses spec limit at:  %s\n",
            bound_label, ci_pct, shelf_life_label))
cat(sprintf("  Verdict: %s  (bound %s the spec limit within the observed range, t_max = %g)\n\n",
            if (verdict_pass) "PASS" else "FAIL",
            if (verdict_pass) "does not cross" else "crosses", t_max))

if (p_slope >= 0.05) {
  cat("  \u26a0\ufe0f  Slope is not statistically significant. The data do not\n")
  cat("   confirm a trend over time. Shelf life estimate may be\n")
  cat("   unreliable. Consider collecting more data or longer time points.\n\n")
}

cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Save model coefficients CSV (input for jrc_shelf_life_extrapolate)
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")

model_file <- file.path(jr_out_dir(),
                        paste0(datetime_pfx, "_jrc_shelf_life_linear_model.csv"))

model_df <- data.frame(
  parameter = c("script", "version", "source_file", "run_timestamp",
                "intercept", "slope", "se_residual", "n", "t_bar", "Sxx",
                "df_residual", "batch_model", "limiting_batch",
                "last_time", "spec_limit", "confidence", "direction", "transform"),
  value     = c("jrc_shelf_life_linear", SCRIPT_VERSION, basename(csv_file),
                format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
                b0, b1, sigma, n_line, t_bar, Sxx,
                df_res, pool_model, if (is.na(lim_unit$label)) "" else lim_unit$label,
                t_max, spec_limit, confidence, direction, transform),
  stringsAsFactors = FALSE
)
write.csv(model_df, model_file, row.names = FALSE, quote = TRUE)
cat(sprintf("\U0001f4be Model coefficients saved to: %s\n",   model_file))

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

t_plot_max <- if (!is.na(shelf_life)) shelf_life * 1.15 else t_max * 1.5
t_seq <- seq(t_min, t_plot_max, length.out = 200)

pred_df <- as.data.frame(
  predict(fit, newdata = lim_unit$nd(t_seq),
          interval = "confidence", level = 2 * confidence - 1)
)
pred_df$time <- t_seq

# Back-transform to original scale for log model
if (transform == "log") {
  pred_df$fit <- exp(pred_df$fit)
  pred_df$lwr <- exp(pred_df$lwr)
  pred_df$upr <- exp(pred_df$upr)
}

# Extend regression line as dashed beyond last observation
pred_df$region <- ifelse(pred_df$time <= t_max, "observed", "extrapolated")

BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"
COL_REG  <- "#2E5BBA"
COL_SPEC <- "#CC2222"
COL_SL   <- "#2CA02C"
COL_PT   <- "#333333"

theme_jr <- jr_theme(10)

ci_lo_col <- if (direction == "low") "lwr" else "upr"

p <- ggplot() +
  geom_ribbon(data = pred_df,
              aes(x = time, ymin = lwr, ymax = upr),
              fill = COL_REG, alpha = 0.15) +
  geom_line(data = pred_df[pred_df$region == "observed", ],
            aes(x = time, y = fit),
            colour = COL_REG, linewidth = 0.9) +
  geom_line(data = pred_df[pred_df$region == "extrapolated", ],
            aes(x = time, y = fit),
            colour = COL_REG, linewidth = 0.9, linetype = "dashed") +
  geom_line(data = pred_df,
            aes(x = time, y = .data[[ci_lo_col]]),
            colour = COL_REG, linewidth = 0.6, linetype = "dotted") +
  geom_jitter(data = dat,
              aes(x = time, y = value),
              width = diff(range(dat$time)) * 0.01,
              size  = 2, alpha = 0.55, colour = COL_PT) +
  geom_hline(yintercept = spec_limit,
             colour = COL_SPEC, linewidth = 0.8, linetype = "dashed") +
  annotate("text", x = t_plot_max * 0.02, y = spec_limit,
           label = sprintf("Spec limit = %g", spec_limit),
           hjust = 0, vjust = -0.4, size = 3, colour = COL_SPEC) +
  labs(
    title    = sprintf("Shelf Life Estimation  |  %s  |  %s = %g%s",
                       basename(csv_file), ci_pct, spec_limit,
                       if (transform == "log") "  [log-linear model]" else ""),
    subtitle = sprintf("Slope = %.4f  R\u00b2 = %.3f  |  %s %s CI bound crosses spec at %s%s",
                       b1, r2, bound_label, ci_pct, shelf_life_label,
                       if (pool_model %in% c("partial", "none")) paste0("  |  limiting batch ", lim_unit$label)
                       else if (pool_model == "full") "  |  batches pooled" else ""),
    x        = "Time",
    y        = "Value"
  ) +
  theme_jr

if (!is.na(shelf_life)) {
  p <- p +
    geom_vline(xintercept = shelf_life,
               colour = COL_SL, linewidth = 0.8, linetype = "dashed") +
    annotate("text",
             x     = shelf_life,
             y     = min(dat$value) + 0.05 * diff(range(dat$value)),
             label = sprintf("Shelf life\n%.2f", shelf_life),
             hjust = -0.1, size = 3, colour = COL_SL)
}

out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_shelf_life_linear.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))
ggsave(out_file, plot = p, width = 8, height = 5, dpi = 150, bg = BG)

# ---------------------------------------------------------------------------
# HTML report (--report flag, requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

save_linear_report <- function(csv_file, spec_limit, confidence, direction,
                                transform, n_total, n_timepoints, t_min, t_max,
                                bf, b0, b1, r2, sigma, p_slope, p_intercept,
                                shelf_life_label,
                                png_path) {
  he <- jr_html_escape
  f5 <- function(x) sprintf("%.5f", x)
  f4 <- function(x) sprintf("%.4f", x)

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-SHELF-LIN-", format(Sys.time(), "%Y%m%d-%H%M%S"))
  ci_pct    <- sprintf("one-sided %.0f%%", confidence * 100)
  bound_label <- if (direction == "low") "Lower" else "Upper"

  bf_row <- if (!is.na(bf$p_value)) {
    bf_ok <- bf$p_value >= 0.05
    paste0('<tr><td class="l">Brown-Forsythe test</td><td>F = ', f4(bf$stat),
           ', p = ', f4(bf$p_value),
           if (bf_ok) ' &mdash; variance homogeneous' else ' &mdash; <strong>\u26a0\ufe0f variance may be heterogeneous</strong>',
           '</td></tr>')
  } else {
    '<tr><td class="l">Brown-Forsythe test</td><td>Not applicable (fewer than 2 groups)</td></tr>'
  }

  transform_note <- if (transform == "log")
    "log \u2014 fit on log(value); CI back-transformed via exp()"
  else
    "none"

  if (file.exists(png_path)) {
    b64     <- base64encode(png_path)
    img_tag <- paste0('<img src="data:image/png;base64,', b64,
                      '" alt="Shelf life chart" width="100%" ',
                      'style="width:100%;height:auto;display:block;border:1px solid #ccc;">')
  } else {
    img_tag <- "<p><em>(Chart not available.)</em></p>"
  }

  css <- paste(c(
    "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}",
    "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1a1a1a;background:#fff;padding:24px}",
    ".report{background:#fff;max-width:900px;margin:0 auto;padding:40px 48px;border:1px solid #ccc;box-shadow:0 2px 10px rgba(0,0,0,.10)}",
    ".rpt-hdr{border-bottom:3px solid #1a3a6b;padding-bottom:14px;margin-bottom:24px}",
    ".rpt-hdr h1{font-size:1.45em;color:#1a3a6b;margin-bottom:2px}",
    ".rpt-hdr h2{font-size:1em;font-weight:normal;color:#555;margin-bottom:14px}",
    "table.meta{border-collapse:collapse}",
    "table.meta td{padding:3px 14px 3px 0;vertical-align:top;font-size:.91em}",
    "table.meta td.k{font-weight:600;color:#333;min-width:160px}",
    ".draft{color:#a00;font-weight:bold}",
    ".section{margin-top:26px}",
    ".sec-ttl{font-weight:700;color:#1a3a6b;border-bottom:1.5px solid #1a3a6b;padding-bottom:4px;margin-bottom:10px;font-size:.95em;text-transform:uppercase;letter-spacing:.04em}",
    "table.dt{width:100%;border-collapse:collapse;font-size:.91em}",
    "table.dt th{padding:5px 10px;border:1px solid #ccc;background:#f0f4f8;font-weight:600;text-align:left;font-size:.88em}",
    "table.dt td{padding:5px 10px;border:1px solid #ddd;vertical-align:top}",
    "table.dt td.l{width:240px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    "table.dt td.r{text-align:right;font-family:monospace}",
    ".result-box{margin-top:12px;padding:14px 18px;border-radius:4px;background:#e8f5e9;border:2px solid #a5d6a7;font-size:1.08em;font-weight:600;color:#1a5c2a}",
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;text-align:center;margin-bottom:24px;color:#999;font-size:.9em;min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;font-size:.79em;color:#999;text-align:center}",
    "@media print{body{background:#fff;padding:0}.report{border:none;box-shadow:none;padding:16px;max-width:100%}.result-box{-webkit-print-color-adjust:exact;print-color-adjust:exact}}"
  ), collapse = "\n")

  out <- c(
    '<!DOCTYPE html><html lang="en"><head>',
    '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Shelf Life Estimation Report</title>',
    paste0('<style>', css, '</style></head><body><div class="report">'),

    '<div class="logo-wrap">[Insert company logo here]</div>',

    '<div class="rpt-hdr">',
    '<h1>Shelf Life Estimation Report</h1>',
    '<h2>Linear Degradation Model &mdash; ICH Q1E</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    paste0('<tr><td class="k">Script</td><td>jrc_shelf_life_linear v', SCRIPT_VERSION, ' &mdash; JR Anchored</td></tr>'),
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Product / Study</td><td class="f">[describe the product and stability study]</td></tr>',
    '<tr><td class="l">Objective</td><td class="f">[state the objective, e.g.: estimate shelf life using linear regression model on stability data]</td></tr>',
    '<tr><td class="l">Standard</td><td>ICH Q1E \u2014 Evaluation for Stability Data</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">2. Study Setup</div><table class="dt">',
    paste0('<tr><td class="l">Data file</td><td>', he(basename(csv_file)), '</td></tr>'),
    paste0('<tr><td class="l">Observations</td><td class="r">', he(n_total), '</td></tr>'),
    paste0('<tr><td class="l">Time points</td><td class="r">', he(n_timepoints),
           ' (t<sub>min</sub> = ', he(t_min), ', t<sub>max</sub> = ', he(t_max), ')</td></tr>'),
    paste0('<tr><td class="l">Spec limit</td><td class="r">', he(spec_limit),
           ' (', if (direction == "low") "lower bound" else "upper bound", ')</td></tr>'),
    paste0('<tr><td class="l">Confidence</td><td class="r">', ci_pct, '</td></tr>'),
    paste0('<tr><td class="l">Direction</td><td>', he(direction),
           ' (', if (direction == "low") "value must stay above spec" else "value must stay below spec", ')</td></tr>'),
    paste0('<tr><td class="l">Transform</td><td>', he(transform_note), '</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">3. Statistical Results</div><table class="dt">',
    bf_row,
    if (has_batch) paste0('<tr><td class="l">Batch model (ICH Q1E)</td><td>', he(pool_model),
                          if (pool_model %in% c("partial", "none")) paste0(' &mdash; limiting batch ', he(lim_unit$label)) else '',
                          sprintf(' (interaction p = %.4f, batch p = %.4f)', pool_res$p_interaction, pool_res$p_batch),
                          '</td></tr>') else '',
    paste0('<tr><td class="l">Intercept</td><td class="r">', f5(b0),
           if (is.na(p_intercept)) '' else paste0(' (p = ', f4(p_intercept), ')'), '</td></tr>'),
    paste0('<tr><td class="l">Slope</td><td class="r">', f5(b1), ' (p = ', f4(p_slope), ')</td></tr>'),
    paste0('<tr><td class="l">R&sup2;</td><td class="r">', f4(r2), '</td></tr>'),
    paste0('<tr><td class="l">Residual SE</td><td class="r">', f5(sigma), '</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">4. Shelf Life Estimate</div><table class="dt">',
    paste0('<tr><td class="l">', bound_label, ' ', ci_pct, ' CI bound crosses spec</td>',
           '<td class="r"><strong>', he(shelf_life_label), '</strong></td></tr>'),
    '</table>',
    paste0('<div class="result-box">Shelf life estimate: ', he(shelf_life_label),
           ' &mdash; ', if (verdict_pass) 'PASS' else 'FAIL', '</div>'),
    '</div>',

    '<div class="section"><div class="sec-ttl">5. Chart</div>',
    img_tag,
    '</div>',

    '<div class="section"><div class="sec-ttl">6. Approvals</div>',
    '<table class="appr"><thead><tr><th>Role</th><th>Name</th><th>Signature</th><th>Date</th></tr></thead><tbody>',
    '<tr><td>Prepared by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</tbody></table></div>',

    paste0(paste0('<div class="rpt-footer">Generated by JR Anchored &mdash; jrc_shelf_life_linear v', SCRIPT_VERSION, ' &mdash; '), he(dt_str), '</div>'),
    '</div></body></html>'
  )

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path <- file.path(jr_out_dir(),
                        paste0(datetime_pfx, "_shelf_life_linear_dv_report.html"))
  writeLines(out, out_path)
  jr_say(sprintf("\U0001f4c4 Report saved to: %s", out_path))

  # Write JSON sidecar for Word report generator
  json_path <- sub("\\.html$", "_data.json", out_path)

  jvs <- jr_json_str
  jvn <- function(x, fmt = "%.5f") jr_json_num(x, fmt)

  transform_note <- if (transform == "log")
    "log — fit on log(value); CI back-transformed via exp()"
  else "none"

  bf_note <- if (!is.na(bf$p_value)) {
    sprintf("Brown-Forsythe F = %.4f, p = %.4f (%s)",
            bf$stat, bf$p_value,
            if (bf$p_value >= 0.05) "variance homogeneous" else "WARNING: variance may be heterogeneous")
  } else "Not applicable (fewer than 2 groups)"

  bound_label_json <- if (direction == "low") "Lower" else "Upper"
  ci_pct_json <- sprintf("one-sided %.0f%%", confidence * 100)
  acceptance_json <- sprintf("%s %s CI bound must not cross spec limit %g within the observed time range (t_max = %g; direction: %s, ICH Q1E).",
                             bound_label_json, ci_pct_json, spec_limit, t_max, direction)

  method_rows <- paste0(
    '{"k":"Method","v":"Linear regression: value ~ time. ICH Q1E — Evaluation for Stability Data."},',
    '{"k":"Transform","v":', jvs(transform_note), '},',
    '{"k":"Homogeneity of Variance","v":', jvs(bf_note), '},',
    '{"k":"Confidence level","v":', jvs(ci_pct_json), '},',
    '{"k":"Spec limit","v":', jvs(sprintf("%g (%s)", spec_limit,
      if (direction == "low") "lower bound" else "upper bound")), '},',
    '{"k":"Direction","v":', jvs(sprintf("%s (%s)", direction,
      if (direction == "low") "value must stay above spec" else "value must stay below spec")), '},',
    '{"k":"Pass Criterion","v":', jvs(acceptance_json), '}'
  )

  results_rows <- paste0(
    '{"k":"Observations (n)","v":', jvs(as.character(n_total)), '},',
    '{"k":"Time points","v":', jvs(sprintf("%d (t_min=%g, t_max=%g)", n_timepoints, t_min, t_max)), '},',
    if (has_batch) paste0('{"k":"Batch model (ICH Q1E)","v":', jvs(sprintf("%s%s (interaction p=%.4f, batch p=%.4f)",
      pool_model, if (pool_model %in% c("partial", "none")) paste0(", limiting batch ", lim_unit$label) else "",
      pool_res$p_interaction, pool_res$p_batch)), '},') else '',
    '{"k":"Intercept","v":', jvs(if (is.na(p_intercept)) sprintf("%.5f", b0) else sprintf("%.5f (p=%.4f)", b0, p_intercept)), '},',
    '{"k":"Slope","v":', jvs(sprintf("%.5f (p=%.4f)", b1, p_slope)), '},',
    '{"k":"R-squared","v":', jvs(sprintf("%.4f", r2)), '},',
    '{"k":"Residual SE","v":', jvs(sprintf("%.5f", sigma)), '},',
    '{"k":"Shelf life estimate","v":', jvs(shelf_life_label), '}'
  )

  input_sha256 <- jr_sha256_file(csv_file)

  json_lines <- c(
    "{",
    '  "report_type":          "dv",',
    '  "script":               "jrc_shelf_life_linear",',
    sprintf('  "version":              "%s",', SCRIPT_VERSION),
    sprintf('  "report_id":            %s,', jvs(report_id)),
    sprintf('  "generated":            %s,', jvs(dt_str)),
    '  "subtitle":             "Shelf Life Estimation - Linear Degradation Model (ICH Q1E)",',
    sprintf('  "data_file":            %s,', jvs(basename(csv_file))),
    sprintf('  "input_file":           %s,', jvs(basename(csv_file))),
    sprintf('  "input_sha256":         %s,', jvs(input_sha256)),
    '  "col_name":             "value",',
    sprintf('  "n":                    %d,', n_total),
    '  "lsl":                  null,',
    '  "usl":                  null,',
    sprintf('  "acceptance_criterion": %s,', jvs(acceptance_json)),
    sprintf('  "method": [%s],', method_rows),
    sprintf('  "results": [%s],', results_rows),
    sprintf('  "verdict":              %s,', jvs(sprintf("Shelf life estimate: %s (%s)", shelf_life_label,
                                                         if (verdict_pass) "PASS" else "FAIL"))),
    sprintf('  "verdict_pass":         %s,', jr_json_bool(verdict_pass)),
    sprintf('  "png_path":             %s', jvs(gsub("\\\\", "/", png_path))),
    "}"
  )

  con <- file(json_path, encoding = "UTF-8")
  writeLines(json_lines, con)
  close(con)
  jr_say(sprintf("📄 Report data saved to: %s", json_path))
  jr_run_pack(json_path, "dv-report", out_path, log_files = png_path)

  invisible(c(html = out_path, json = json_path))
}

report_path <- NULL

if (want_report) {
  jr_require_report_template("dv_report_template.html", log_files = c(out_file, model_file))
  report_path <- save_linear_report(
    csv_file, spec_limit, confidence, direction,
    transform, n_total, n_timepoints, t_min, t_max,
    bf, b0, b1, r2, sigma, p_slope, p_intercept,
    shelf_life_label,
    out_file
  )
}

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file, model_file))
