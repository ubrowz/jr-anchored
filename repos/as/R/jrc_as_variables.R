# =============================================================================
# jrc_as_variables.R
# JR Validated Environment — Acceptance Sampling module
#
# Design a variables acceptance sampling plan using the k-method with
# unknown sigma. Compares efficiency against an equivalent attributes plan.
# Saves an OC curve PNG to ~/Downloads/.
#
# Usage: jrc_as_variables <lot_size> <aql> <rql> [--alpha 0.05] [--beta 0.10] [--sides 1]
#
# Arguments:
#   lot_size        Positive integer — lot size N
#   aql             AQL as fraction strictly between 0 and 1
#   rql             RQL as fraction strictly between 0 and 1, must be > aql
#   --alpha <val>   Producer's risk (default 0.05)
#   --beta  <val>   Consumer's risk (default 0.10)
#   --sides <val>   1 (one-sided, default) or 2 (two-sided)
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_as_variables <lot_size> <aql> <rql> [--alpha 0.05] [--beta 0.10] [--sides 1]")
}

if (length(args) < 3) {
  stop("Usage: jrc_as_variables <lot_size> <aql> <rql> [--alpha 0.05] [--beta 0.10] [--sides 1]")
}

lot_size_raw <- suppressWarnings(as.integer(args[1]))
aql          <- suppressWarnings(as.numeric(args[2]))
rql          <- suppressWarnings(as.numeric(args[3]))

if (is.na(lot_size_raw) || lot_size_raw < 2) {
  stop("lot_size must be a positive integer >= 2.")
}
if (is.na(aql) || aql <= 0 || aql >= 1) {
  stop("aql must be a fraction strictly between 0 and 1.")
}
if (is.na(rql) || rql <= 0 || rql >= 1) {
  stop("rql must be a fraction strictly between 0 and 1.")
}
if (aql >= rql) {
  stop("rql must be strictly greater than aql.")
}

N     <- lot_size_raw
alpha <- 0.05
beta  <- 0.10
sides <- 1L

i <- 4
while (i <= length(args)) {
  if (args[i] == "--alpha" && i < length(args)) {
    alpha <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(alpha) || alpha <= 0 || alpha >= 1) stop("--alpha must be between 0 and 1.")
    i <- i + 2
  } else if (args[i] == "--beta" && i < length(args)) {
    beta <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(beta) || beta <= 0 || beta >= 1) stop("--beta must be between 0 and 1.")
    i <- i + 2
  } else if (args[i] == "--sides" && i < length(args)) {
    sides <- suppressWarnings(as.integer(args[i + 1]))
    if (is.na(sides) || !(sides %in% c(1L, 2L))) stop("--sides must be 1 or 2.")
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
# OC function for variables k-method (one-sided)
# ---------------------------------------------------------------------------

pa_var_1sided <- function(n, k, p) {
  ncp <- qnorm(1 - p) * sqrt(n)
  pt(k * sqrt(n), df = n - 1, ncp = ncp, lower.tail = FALSE)
}

pa_var_2sided <- function(n, k, p_total) {
  ncp <- qnorm(1 - p_total / 2) * sqrt(n)
  pa1 <- pt(k * sqrt(n), df = n - 1, ncp = ncp, lower.tail = FALSE)
  pa1^2
}

# ---------------------------------------------------------------------------
# Search for variables plan
# ---------------------------------------------------------------------------

find_variables <- function(aql, rql, alpha, beta, sides) {
  for (n in 2L:500L) {
    if (sides == 1L) {
      ncp_aql <- qnorm(1 - aql) * sqrt(n)
      k <- qt(alpha, df = n - 1, ncp = ncp_aql, lower.tail = TRUE) / sqrt(n)
      beta_act <- pa_var_1sided(n, k, rql)
    } else {
      # Effective risks for two-sided
      alpha_eff <- 1 - sqrt(1 - alpha)
      ncp_aql   <- qnorm(1 - aql / 2) * sqrt(n)
      k <- qt(alpha_eff, df = n - 1, ncp = ncp_aql, lower.tail = TRUE) / sqrt(n)
      beta_act <- pa_var_2sided(n, k, rql)
    }
    if (!is.na(beta_act) && beta_act <= beta) {
      if (sides == 1L) {
        alpha_act <- 1 - pa_var_1sided(n, k, aql)
      } else {
        alpha_act <- 1 - pa_var_2sided(n, k, aql)
      }
      return(list(n = n, k = k, alpha_act = alpha_act, beta_act = beta_act))
    }
  }
  NULL
}

# ---------------------------------------------------------------------------
# Also find equivalent attributes plan for comparison
# ---------------------------------------------------------------------------

find_single_attr <- function(N_lot, aql, rql, alpha, beta) {
  pa_s <- function(n, c_val, p) {
    use_h <- (n / N_lot > 0.10)
    D <- round(N_lot * p)
    if (use_h) phyper(c_val, D, N_lot - D, n) else pbinom(c_val, n, p)
  }
  n_max <- min(N_lot, 500L)
  for (n in 2L:n_max) {
    for (c_val in 0L:n) {
      pa_aql <- pa_s(n, c_val, aql)
      if ((1 - pa_aql) <= alpha) {
        pa_rql <- pa_s(n, c_val, rql)
        if (pa_rql <= beta) return(n)
        break
      }
    }
  }
  NA_integer_
}

# ---------------------------------------------------------------------------
# Run searches
# ---------------------------------------------------------------------------

vp <- find_variables(aql, rql, alpha, beta, sides)

if (is.null(vp)) {
  stop("\u274c No variables plan found within n \u2264 500.")
}

n_attr <- find_single_attr(N, aql, rql, alpha, beta)
reduction <- if (!is.na(n_attr)) n_attr - vp$n else NA_integer_
pct_reduction <- if (!is.na(n_attr) && n_attr > 0) 100 * reduction / n_attr else NA_real_

# ---------------------------------------------------------------------------
# OC curve table
# ---------------------------------------------------------------------------

p_grid <- c(0.001, 0.005, 0.010, 0.020, 0.050, 0.100, 0.150, 0.200)
p_grid <- sort(unique(c(p_grid, aql, rql)))
p_grid <- p_grid[p_grid < 1]

oc_vals <- sapply(p_grid, function(p) {
  if (sides == 1L) pa_var_1sided(vp$n, vp$k, p)
  else pa_var_2sided(vp$n, vp$k, p)
})

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Variables Sampling Plan \u2014 k-method (unknown \u03c3)\n")
cat(sprintf("  Lot size N: %d   AQL: %.3f   RQL: %.3f   Sides: %d\n",
            N, aql, rql, sides))
cat(sprintf("  Producer's risk \u03b1: %.2f   Consumer's risk \u03b2: %.2f\n", alpha, beta))
cat("=================================================================\n\n")

cat("--- Variables Plan (k-method) --------------------------------------\n")
cat(sprintf("  Sample size (n):              %d\n", vp$n))
cat(sprintf("  Acceptability constant (k):   %.4f\n", vp$k))
cat("\n")
cat(sprintf("  Achieved producer's risk (\u03b1):  %.4f   [target \u2264 %.3f]\n",
            vp$alpha_act, alpha))
cat(sprintf("  Achieved consumer's risk  (\u03b2):  %.4f   [target \u2264 %.3f]\n",
            vp$beta_act, beta))
cat("\n")

if (!is.na(n_attr)) {
  cat("--- Comparison with Attributes Plan --------------------------------\n")
  cat(sprintf("  Variables plan:   n = %d\n", vp$n))
  cat(sprintf("  Attributes plan:  n = %d\n", n_attr))
  if (reduction > 0) {
    cat(sprintf("  Sample reduction: %d units (%.1f%%)\n\n", reduction, pct_reduction))
    cat("  The variables plan requires fewer samples because it uses the\n")
    cat("  actual measurement values, not just pass/fail, giving more\n")
    cat("  information per unit inspected.\n")
  } else {
    cat("  No sample size reduction for these parameters.\n")
  }
  cat("\n")
}

cat("--- OC Curve -------------------------------------------------------\n")
cat(sprintf("  %-10s %s\n", "p", "Pa"))
for (j in seq_along(p_grid)) {
  cat(sprintf("  %-10s %.4f\n", sprintf("%.3f", p_grid[j]), oc_vals[j]))
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

COL_CL   <- "#2E5BBA"
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
    axis.title       = element_text(size = 9)
  )

p_dense <- seq(0.001, min(0.5, rql * 3), by = 0.001)
pa_v    <- sapply(p_dense, function(p) {
  if (sides == 1L) pa_var_1sided(vp$n, vp$k, p)
  else pa_var_2sided(vp$n, vp$k, p)
})

plot_df <- data.frame(p = p_dense, pa = pa_v)

p_oc <- ggplot(plot_df, aes(x = p, y = pa)) +
  geom_line(color = COL_CL, linewidth = 1) +
  geom_vline(xintercept = aql, linetype = "dashed", color = "#555555", linewidth = 0.6) +
  geom_vline(xintercept = rql, linetype = "dashed", color = "#555555", linewidth = 0.6) +
  annotate("text", x = aql, y = 0.05, label = "AQL", angle = 90,
           vjust = -0.3, size = 3, color = "#555555") +
  annotate("text", x = rql, y = 0.05, label = "RQL", angle = 90,
           vjust = -0.3, size = 3, color = "#555555") +
  labs(
    title = sprintf("OC Curve — Variables Plan (n=%d, k=%.4f, sides=%d)",
                    vp$n, vp$k, sides),
    x = "Fraction Nonconforming (p)",
    y = "Probability of Acceptance (Pa)"
  ) +
  scale_y_continuous(limits = c(0, 1)) +
  theme_jr

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_as_variables.png"))

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
  sprintf("Variables Sampling Plan  |  N=%d  AQL=%.3f  RQL=%.3f  Sides=%d  |  n=%d, k=%.4f",
          N, aql, rql, sides, vp$n, vp$k),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_oc, vp = viewport())
popViewport()

dev.off()

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
