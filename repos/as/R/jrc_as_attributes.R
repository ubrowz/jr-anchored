# =============================================================================
# jrc_as_attributes.R
# JR Validated Environment — Acceptance Sampling module
#
# Design an attributes acceptance sampling plan (single AND double sampling).
# Uses the hypergeometric distribution when n/N > 0.10, binomial otherwise.
# Outputs a single sampling plan (n, c), a double sampling plan (n1, c1, c2),
# OC curve table, and saves a dual-plan OC curve PNG to ~/Downloads/.
#
# Usage: jrc_as_attributes <lot_size> <aql> <rql> [--alpha 0.05] [--beta 0.10]
#
# Arguments:
#   lot_size        Positive integer — lot size N
#   aql             AQL as fraction (e.g. 0.01 = 1%), strictly between 0 and 1
#   rql             RQL as fraction, strictly between 0 and 1, must be > aql
#   --alpha <val>   Producer's risk (default 0.05)
#   --beta  <val>   Consumer's risk (default 0.10)
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_as_attributes <lot_size> <aql> <rql> [--alpha 0.05] [--beta 0.10]")
}

if (length(args) < 3) {
  stop("Usage: jrc_as_attributes <lot_size> <aql> <rql> [--alpha 0.05] [--beta 0.10]")
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
# Acceptance probability helpers
# ---------------------------------------------------------------------------

pa_single <- function(n, c_val, p, N_lot) {
  use_h <- (n / N_lot > 0.10)
  D <- round(N_lot * p)
  if (use_h) {
    phyper(c_val, D, N_lot - D, n)
  } else {
    pbinom(c_val, n, p)
  }
}

pa_double <- function(n1, c1, c2, p, N_lot) {
  use_h <- (n1 / N_lot > 0.10)
  D <- round(N_lot * p)

  # Stage 1: P(accept on first sample)
  if (use_h) {
    pa1 <- phyper(c1, D, N_lot - D, n1)
  } else {
    pa1 <- pbinom(c1, n1, p)
  }

  # Stage 2: conditional acceptance
  pa2 <- 0
  for (d1 in (c1 + 1):c2) {
    if (use_h) {
      pd1 <- dhyper(d1, D, N_lot - D, n1)
      D_rem   <- max(0L, D - d1)
      N_rem   <- N_lot - n1
      N_rem_ok <- max(0L, N_rem - D_rem)
      pa2_given_d1 <- phyper(c2 - d1, D_rem, N_rem_ok, n1)
    } else {
      pd1 <- dbinom(d1, n1, p)
      pa2_given_d1 <- pbinom(c2 - d1, n1, p)
    }
    pa2 <- pa2 + pd1 * pa2_given_d1
  }

  pa1 + pa2
}

asn_double <- function(n1, c1, c2, p, N_lot) {
  use_h <- (n1 / N_lot > 0.10)
  D <- round(N_lot * p)
  if (use_h) {
    p_cont <- phyper(c2, D, N_lot - D, n1) - phyper(c1, D, N_lot - D, n1)
  } else {
    p_cont <- pbinom(c2, n1, p) - pbinom(c1, n1, p)
  }
  n1 * (1 + p_cont)
}

# ---------------------------------------------------------------------------
# Search for single sampling plan
# ---------------------------------------------------------------------------

find_single <- function(N_lot, aql, rql, alpha, beta) {
  n_max <- min(N_lot, 500L)
  for (n in 2L:n_max) {
    for (c_val in 0L:n) {
      pa_aql <- pa_single(n, c_val, aql, N_lot)
      alpha_act <- 1 - pa_aql
      if (alpha_act <= alpha) {
        pa_rql <- pa_single(n, c_val, rql, N_lot)
        if (pa_rql <= beta) {
          return(list(n = n, c = c_val,
                      alpha_act = alpha_act,
                      beta_act  = pa_rql))
        }
        break  # larger c only worsens beta for this n
      }
    }
  }
  NULL
}

# ---------------------------------------------------------------------------
# Search for double sampling plan
# ---------------------------------------------------------------------------

find_double <- function(N_lot, aql, rql, alpha, beta) {
  n1_max <- min(as.integer(N_lot / 2), 250L)
  for (n1 in 2L:n1_max) {
    for (c1 in 0L:min(n1, 12L)) {
      for (c2 in (c1 + 1L):min(2L * n1, c1 + 8L)) {
        pa_aql <- pa_double(n1, c1, c2, aql, N_lot)
        pa_rql <- pa_double(n1, c1, c2, rql, N_lot)
        if ((1 - pa_aql) <= alpha && pa_rql <= beta) {
          return(list(
            n1 = n1, c1 = c1, c2 = c2,
            alpha_act = 1 - pa_aql,
            beta_act  = pa_rql
          ))
        }
      }
    }
  }
  NULL
}

# ---------------------------------------------------------------------------
# Run searches
# ---------------------------------------------------------------------------

sp <- find_single(N, aql, rql, alpha, beta)
dp <- find_double(N, aql, rql, alpha, beta)

if (is.null(sp)) {
  stop("\u274c No single sampling plan found within search bounds (n \u2264 500).")
}

# ---------------------------------------------------------------------------
# OC curve data (single plan)
# ---------------------------------------------------------------------------

p_grid <- c(0.001, 0.005, 0.010, 0.020, 0.050, 0.100, 0.150, 0.200)
p_grid <- sort(unique(c(p_grid, aql, rql)))
p_grid <- p_grid[p_grid < 1]

oc_single <- sapply(p_grid, function(p) pa_single(sp$n, sp$c, p, N))

oc_double <- NULL
if (!is.null(dp)) {
  oc_double <- sapply(p_grid, function(p) pa_double(dp$n1, dp$c1, dp$c2, p, N))
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Attributes Sampling Plan\n")
cat(sprintf("  Lot size N: %d   AQL: %.3f   RQL: %.3f\n", N, aql, rql))
cat(sprintf("  Producer's risk \u03b1: %.2f   Consumer's risk \u03b2: %.2f\n", alpha, beta))
cat("=================================================================\n\n")

cat("--- Single Sampling Plan -------------------------------------------\n")
cat(sprintf("  Sample size (n):        %d\n", sp$n))
cat(sprintf("  Acceptance number (c):  %d\n", sp$c))
cat(sprintf("  Rejection number (r):   %d\n", sp$c + 1L))
cat("\n")
cat(sprintf("  Achieved producer's risk (\u03b1):  %.4f   [target \u2264 %.3f]\n",
            sp$alpha_act, alpha))
cat(sprintf("  Achieved consumer's risk  (\u03b2):  %.4f   [target \u2264 %.3f]\n",
            sp$beta_act, beta))
cat("\n")

if (!is.null(dp)) {
  cat("--- Double Sampling Plan -------------------------------------------\n")
  cat(sprintf("  Stage 1: sample n1 = %d   Accept if d1 \u2264 %d   Reject if d1 > %d\n",
              dp$n1, dp$c1, dp$c2))
  cat(sprintf("  Stage 2: sample n2 = %d   Accept if d1+d2 \u2264 %d\n",
              dp$n1, dp$c2))
  cat("\n")
  cat(sprintf("  Achieved producer's risk (\u03b1):  %.4f   [target \u2264 %.3f]\n",
              dp$alpha_act, alpha))
  cat(sprintf("  Achieved consumer's risk  (\u03b2):  %.4f   [target \u2264 %.3f]\n",
              dp$beta_act, beta))
  cat("\n")
  asn_aql <- asn_double(dp$n1, dp$c1, dp$c2, aql, N)
  asn_rql <- asn_double(dp$n1, dp$c1, dp$c2, rql, N)
  cat(sprintf("  ASN at AQL (p = %.3f):  %.1f  (vs single: %d)\n", aql, asn_aql, sp$n))
  cat(sprintf("  ASN at RQL (p = %.3f):  %.1f  (vs single: %d)\n", rql, asn_rql, sp$n))
  cat("\n")
}

cat("--- OC Curve (Single) -----------------------------------------------\n")
cat(sprintf("  %-10s %s\n", "p", "Pa"))
for (j in seq_along(p_grid)) {
  cat(sprintf("  %-10s %.4f\n", sprintf("%.3f", p_grid[j]), oc_single[j]))
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

COL_IC   <- "#1A1A2E"
COL_OOC  <- "#C0392B"
COL_CL   <- "#2E5BBA"
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"
COL_SINGLE <- "#2E5BBA"
COL_DOUBLE <- "#C0392B"

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
pa_s    <- sapply(p_dense, function(p) pa_single(sp$n, sp$c, p, N))

plot_df <- data.frame(p = p_dense, pa_single = pa_s)

p_oc <- ggplot(plot_df, aes(x = p, y = pa_single)) +
  geom_line(color = COL_SINGLE, linewidth = 1, linetype = "solid") +
  labs(title = sprintf("OC Curve — Single (n=%d, c=%d) vs Double Plan", sp$n, sp$c),
       x = "Fraction Defective (p)", y = "Probability of Acceptance (Pa)") +
  scale_y_continuous(limits = c(0, 1)) +
  theme_jr

if (!is.null(dp)) {
  pa_d <- sapply(p_dense, function(p) pa_double(dp$n1, dp$c1, dp$c2, p, N))
  plot_df$pa_double <- pa_d
  p_oc <- p_oc +
    geom_line(data = plot_df, aes(x = p, y = pa_double),
              color = COL_DOUBLE, linewidth = 1, linetype = "dashed")
}

# Mark AQL and RQL
p_oc <- p_oc +
  geom_vline(xintercept = aql, linetype = "dashed", color = "#555555", linewidth = 0.6) +
  geom_vline(xintercept = rql, linetype = "dashed", color = "#555555", linewidth = 0.6) +
  annotate("text", x = aql, y = 0.05, label = "AQL", angle = 90,
           vjust = -0.3, size = 3, color = "#555555") +
  annotate("text", x = rql, y = 0.05, label = "RQL", angle = 90,
           vjust = -0.3, size = 3, color = "#555555")

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_as_attributes.png"))

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
  sprintf("Attributes Sampling Plan  |  N=%d  AQL=%.3f  RQL=%.3f  |  Single: n=%d, c=%d",
          N, aql, rql, sp$n, sp$c),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_oc, vp = viewport())
popViewport()

dev.off()

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
