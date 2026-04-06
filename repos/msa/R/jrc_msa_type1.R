# =============================================================================
# jrc_msa_type1.R
# JR Validated Environment — MSA module
#
# Type 1 Gauge Study — repeatability and bias against a known reference value.
# One operator measures one reference part repeatedly. Reports Cg, Cgk,
# %Var, %Bias, and a significance test for bias. Saves a two-panel PNG
# (run chart + histogram) to ~/Downloads/.
#
# Usage: jrc_msa_type1 <data.csv> --reference <value> --tolerance <value>
#
# Arguments:
#   data.csv              CSV with a 'value' column (repeated measurements).
#                         An optional 'id' column is used for the run chart
#                         x-axis; if absent, observation order is used.
#   --reference <value>   Known true value of the reference part (required).
#   --tolerance <value>   Process tolerance USL - LSL (required).
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_msa_type1 <data.csv> --reference <value> --tolerance <value>")
}

csv_file  <- args[1]
reference <- NA_real_
tolerance <- NA_real_
i <- 2
while (i <= length(args)) {
  if (args[i] == "--reference" && i < length(args)) {
    reference <- suppressWarnings(as.numeric(args[i + 1])); i <- i + 2
  } else if (args[i] == "--tolerance" && i < length(args)) {
    tolerance <- suppressWarnings(as.numeric(args[i + 1])); i <- i + 2
  } else {
    i <- i + 1
  }
}

if (is.na(reference)) stop("--reference <value> is required.")
if (is.na(tolerance) || tolerance <= 0) stop("--tolerance must be a positive number.")

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
if (!file.exists(csv_file)) stop(paste("\u274c File not found:", csv_file))

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)
names(dat) <- tolower(trimws(names(dat)))

if (!"value" %in% names(dat)) {
  stop("\u274c Missing required column 'value'.")
}

dat$value <- suppressWarnings(as.numeric(dat$value))
if (any(is.na(dat$value))) stop("\u274c Non-numeric values found in 'value' column.")

n <- nrow(dat)
if (n < 10) stop(paste("\u274c At least 10 measurements are required (found", n, ")."))

dat$id <- if ("id" %in% names(dat)) dat$id else seq_len(n)

# ---------------------------------------------------------------------------
# Core statistics
# ---------------------------------------------------------------------------
x_bar <- mean(dat$value)
s     <- sd(dat$value)
bias  <- x_bar - reference

# Cg and Cgk (AIAG/VDA Type 1 formulae)
Cg  <- (0.2 * tolerance) / (6 * s)
Cgk <- (0.1 * tolerance - abs(bias)) / (3 * s)

pct_var  <- 100 * 6 * s   / tolerance   # % of tolerance consumed by 6-sigma gauge spread
pct_bias <- 100 * bias    / tolerance   # signed %Bias vs tolerance

# t-test for H0: mean = reference
t_stat <- bias / (s / sqrt(n))
p_bias <- 2 * pt(abs(t_stat), df = n - 1, lower.tail = FALSE)

# 95% CI on mean
ci_half <- qt(0.975, df = n - 1) * s / sqrt(n)
ci_lo   <- x_bar - ci_half
ci_hi   <- x_bar + ci_half

# ±10% tolerance limits for run chart and histogram
lim_lo <- reference - 0.1 * tolerance
lim_hi <- reference + 0.1 * tolerance

verdict_cg  <- if (Cg  >= 1.33) "ACCEPTABLE" else if (Cg  >= 1.00) "MARGINAL" else "UNACCEPTABLE"
verdict_cgk <- if (Cgk >= 1.33) "ACCEPTABLE" else if (Cgk >= 1.00) "MARGINAL" else "UNACCEPTABLE"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Type 1 Gauge Study\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Reference value:  %.5g\n", reference))
cat(sprintf("  Tolerance (T):    %.5g\n", tolerance))
cat(sprintf("  Observations (n): %d\n\n", n))

cat("--- Descriptive Statistics --------------------------------------\n")
cat(sprintf("  Mean:             %10.5f\n", x_bar))
cat(sprintf("  Std Dev (\u03c3):       %10.5f\n", s))
cat(sprintf("  Bias:             %10.5f\n", bias))
cat(sprintf("  95%% CI on mean:   [%.5f, %.5f]\n", ci_lo, ci_hi))
cat(sprintf("  t = %.3f,  p = %.4f%s\n\n",
            t_stat, p_bias,
            if (p_bias < 0.05) "  * (bias significant)" else "  (bias not significant)"))

cat("--- Gauge Capability --------------------------------------------\n")
cat(sprintf("  6\u03c3 (gauge spread): %10.5f\n", 6 * s))
cat(sprintf("  0.2 \u00d7 T:           %10.5f\n\n", 0.2 * tolerance))

cat(sprintf("  Cg:               %10.3f   \u2192  %s\n", Cg,  verdict_cg))
cat(sprintf("  Cgk:              %10.3f   \u2192  %s\n\n", Cgk, verdict_cgk))

cat("--- % Metrics ---------------------------------------------------\n")
cat(sprintf("  %%Var (6\u03c3/T):     %9.2f%%\n", pct_var))
cat(sprintf("  %%Bias:           %9.2f%%  (%s)\n\n",
            abs(pct_bias),
            if (bias >= 0) "reads high" else "reads low"))

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  Cg  = %.3f  \u2192  %s\n", Cg,  verdict_cg))
cat(sprintf("  Cgk = %.3f  \u2192  %s\n", Cgk, verdict_cgk))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"
COL_REF  <- "#CC2222"
COL_MEAN <- "#2E5BBA"
COL_LIM  <- "#ED7D31"
COL_PT   <- "#333333"
COL_FILL <- "#C8D8F0"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    plot.subtitle    = element_text(size = 8, color = "#555555"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9)
  )

# --- Panel 1: Run chart ---
p1 <- ggplot(dat, aes(x = id, y = value)) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = lim_lo, ymax = lim_hi,
           fill = COL_FILL, alpha = 0.3) +
  geom_line(color = COL_PT, linewidth = 0.5, alpha = 0.7) +
  geom_point(size = 1.8, color = COL_PT, alpha = 0.8) +
  geom_hline(yintercept = reference, color = COL_REF,
             linetype = "dashed", linewidth = 0.7) +
  geom_hline(yintercept = x_bar,    color = COL_MEAN,
             linetype = "solid",  linewidth = 0.7) +
  geom_hline(yintercept = lim_lo,   color = COL_LIM,
             linetype = "dotted", linewidth = 0.6) +
  geom_hline(yintercept = lim_hi,   color = COL_LIM,
             linetype = "dotted", linewidth = 0.6) +
  annotate("text", x = max(dat$id), y = reference,
           label = "Reference", color = COL_REF,
           hjust = 1.05, vjust = -0.4, size = 2.8) +
  annotate("text", x = max(dat$id), y = x_bar,
           label = sprintf("Mean = %.4f", x_bar), color = COL_MEAN,
           hjust = 1.05, vjust = 1.4, size = 2.8) +
  annotate("text", x = max(dat$id), y = lim_hi,
           label = "+0.1T", color = COL_LIM,
           hjust = 1.05, vjust = -0.4, size = 2.5) +
  annotate("text", x = max(dat$id), y = lim_lo,
           label = "-0.1T", color = COL_LIM,
           hjust = 1.05, vjust = 1.4, size = 2.5) +
  labs(
    title    = "Run Chart",
    subtitle = "Blue = mean  |  Red dashed = reference  |  Orange dotted = \u00b10.1\u00d7T  |  Shaded = acceptance band",
    x        = "Observation",
    y        = "Measured Value"
  ) +
  theme_jr

# --- Panel 2: Histogram ---
bw <- if (n >= 25) (max(dat$value) - min(dat$value)) / 10 else
                   (max(dat$value) - min(dat$value)) / 7

x_seq  <- seq(min(dat$value) - 3 * s, max(dat$value) + 3 * s, length.out = 300)
norm_df <- data.frame(
  x = x_seq,
  y = dnorm(x_seq, mean = x_bar, sd = s) * bw * n
)

p2 <- ggplot(dat, aes(x = value)) +
  annotate("rect", xmin = lim_lo, xmax = lim_hi, ymin = -Inf, ymax = Inf,
           fill = COL_FILL, alpha = 0.3) +
  geom_histogram(binwidth = bw, fill = "#AABBD4", color = "white",
                 linewidth = 0.3) +
  geom_line(data = norm_df, aes(x = x, y = y),
            color = COL_MEAN, linewidth = 0.9) +
  geom_vline(xintercept = reference, color = COL_REF,
             linetype = "dashed", linewidth = 0.7) +
  geom_vline(xintercept = x_bar,    color = COL_MEAN,
             linetype = "solid",  linewidth = 0.7) +
  geom_vline(xintercept = lim_lo,   color = COL_LIM,
             linetype = "dotted", linewidth = 0.6) +
  geom_vline(xintercept = lim_hi,   color = COL_LIM,
             linetype = "dotted", linewidth = 0.6) +
  labs(
    title    = "Distribution of Measurements",
    subtitle = sprintf("Bias = %.4f  |  p = %.4f%s  |  %%Var = %.1f%%  |  %%Bias = %.1f%%",
                       bias, p_bias,
                       if (p_bias < 0.05) "*" else "",
                       pct_var, abs(pct_bias)),
    x        = "Measured Value",
    y        = "Count"
  ) +
  theme_jr

# ---------------------------------------------------------------------------
# Combine and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_msa_type1.png"))

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
  sprintf("Type 1 Gauge Study  |  %s  |  Cg = %.3f (%s)  |  Cgk = %.3f (%s)",
          basename(csv_file), Cg, verdict_cg, Cgk, verdict_cgk),
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
