# =============================================================================
# jrc_as_oc_curve.R
# JR Validated Environment — Acceptance Sampling module
#
# Plot the Operating Characteristic (OC) curve for any attributes sampling
# plan given (n, c). Uses the hypergeometric distribution when n/lot-size > 0.10,
# binomial otherwise. Saves a PNG to the output directory
# (JR_OUT_DIR, default ~/Downloads).
#
# Usage: jrc_as_oc_curve <n> <c> [--lot-size N] [--aql value] [--rql value]
#
# Arguments:
#   n               Sample size (positive integer)
#   c               Acceptance number (non-negative integer, must be < n)
#   --lot-size N    Lot size (if provided and n/N > 0.10, uses hypergeometric)
#   --aql <value>   Optional: marks AQL on the OC curve
#   --rql <value>   Optional: marks RQL on the OC curve
#
# Version: 1.0
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_as_oc_curve <n> <c> [--lot-size N] [--aql value] [--rql value]")
}

if (length(args) < 2) {
  stop("Usage: jrc_as_oc_curve <n> <c> [--lot-size N] [--aql value] [--rql value]")
}

n_val   <- suppressWarnings(as.integer(args[1]))
c_val   <- suppressWarnings(as.integer(args[2]))

if (is.na(n_val) || n_val <= 0) {
  stop("n must be a positive integer.")
}
if (is.na(c_val) || c_val < 0) {
  stop("c must be a non-negative integer.")
}
if (c_val >= n_val) {
  stop("c must be strictly less than n.")
}

lot_size <- NA_integer_
aql_val  <- NA_real_
rql_val  <- NA_real_

i <- 3
while (i <= length(args)) {
  if (args[i] == "--lot-size" && i < length(args)) {
    lot_size <- suppressWarnings(as.integer(args[i + 1]))
    if (is.na(lot_size) || lot_size <= 0) stop("--lot-size must be a positive integer.")
    i <- i + 2
  } else if (args[i] == "--aql" && i < length(args)) {
    aql_val <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(aql_val) || aql_val <= 0 || aql_val >= 1) stop("--aql must be between 0 and 1.")
    i <- i + 2
  } else if (args[i] == "--rql" && i < length(args)) {
    rql_val <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(rql_val) || rql_val <= 0 || rql_val >= 1) stop("--rql must be between 0 and 1.")
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

SCRIPT_VERSION <- "1.0"   # single source for banner, report and JSON

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
}))

# ---------------------------------------------------------------------------
# Determine distribution
# ---------------------------------------------------------------------------

use_hyper <- !is.na(lot_size) && (n_val / lot_size > 0.10)
dist_label <- if (use_hyper) "hypergeometric" else "binomial"

pa_fun <- function(p) {
  if (use_hyper) {
    D <- round(lot_size * p)
    phyper(c_val, D, lot_size - D, n_val)
  } else {
    pbinom(c_val, n_val, p)
  }
}

# ---------------------------------------------------------------------------
# OC table
# ---------------------------------------------------------------------------

p_grid <- c(0.000, 0.005, 0.010, 0.020, 0.050, 0.100, 0.150, 0.200, 0.300, 0.500)
if (!is.na(aql_val)) p_grid <- sort(unique(c(p_grid, aql_val)))
if (!is.na(rql_val)) p_grid <- sort(unique(c(p_grid, rql_val)))
p_grid <- p_grid[p_grid <= 1]

pa_vals <- sapply(p_grid, function(p) if (p == 0) 1.0 else pa_fun(p))

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  OC Curve \u2014 Attributes Plan\n")
cat(sprintf("  n = %d   c = %d   (%s)\n", n_val, c_val, dist_label))
if (!is.na(lot_size)) cat(sprintf("  Lot size N = %d\n", lot_size))
if (!is.na(aql_val))  cat(sprintf("  AQL = %.3f\n", aql_val))
if (!is.na(rql_val))  cat(sprintf("  RQL = %.3f\n", rql_val))
cat("=================================================================\n\n")

cat(sprintf("  %-10s %-12s %s\n", "p", "Pa", "1 - Pa"))
cat("  \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n")
for (j in seq_along(p_grid)) {
  cat(sprintf("  %-10s %-12s %.4f\n",
              sprintf("%.3f", p_grid[j]),
              sprintf("%.4f", pa_vals[j]),
              1 - pa_vals[j]))
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

COL_CL   <- "#2E5BBA"
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- jr_theme(10)

p_dense <- seq(0.001, 0.999, by = 0.001)
pa_d    <- sapply(p_dense, pa_fun)

plot_df <- data.frame(p = p_dense, pa = pa_d)

title_str <- sprintf("OC Curve  |  n = %d, c = %d  (%s)", n_val, c_val, dist_label)

p_oc <- ggplot(plot_df, aes(x = p, y = pa)) +
  geom_line(color = COL_CL, linewidth = 1) +
  labs(title = title_str, x = "Fraction Defective (p)",
       y = "Probability of Acceptance (Pa)") +
  scale_y_continuous(limits = c(0, 1)) +
  theme_jr

if (!is.na(aql_val)) {
  pa_at_aql <- pa_fun(aql_val)
  p_oc <- p_oc +
    geom_vline(xintercept = aql_val, linetype = "dashed",
               color = "#2E5BBA", linewidth = 0.6) +
    annotate("text", x = aql_val, y = 0.05, label = sprintf("AQL\nPa=%.3f", pa_at_aql),
             angle = 90, vjust = -0.3, size = 2.8, color = "#2E5BBA")
}

if (!is.na(rql_val)) {
  pa_at_rql <- pa_fun(rql_val)
  p_oc <- p_oc +
    geom_vline(xintercept = rql_val, linetype = "dashed",
               color = "#C0392B", linewidth = 0.6) +
    annotate("text", x = rql_val, y = 0.05, label = sprintf("RQL\nPa=%.3f", pa_at_rql),
             angle = 90, vjust = -0.3, size = 2.8, color = "#C0392B")
}

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_as_oc_curve.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

jr_save_titled_png(
  out_file,
  sprintf("OC Curve  |  n=%d, c=%d  (%s)", n_val, c_val, dist_label),
  list(p_oc),
  width = 2400,
  height = 1600,
  res = 180
)

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
