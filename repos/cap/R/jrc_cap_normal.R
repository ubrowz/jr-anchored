# =============================================================================
# jrc_cap_normal.R
# JR Validated Environment — Process Capability module
#
# Process Capability Analysis for normally distributed data.
# Computes Cp, Cpk, Pp, Ppk, Cpm (Taguchi) using within-subgroup (MR-based)
# and overall (sample SD) estimates of process spread.
#
# Usage: jrc_cap_normal <data.csv> <col> <lsl> <usl>
#
# <lsl> and <usl> may each be "-" to omit one-sided. At least one must be a number.
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) {
  stop("Usage: jrc_cap_normal <data.csv> <col> <lsl> <usl>\n  Use '-' for <lsl> or <usl> to analyse one-sided.")
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

# Check spec limit violations
if (!is.na(lsl) && any(x < lsl)) {
  n_below <- sum(x < lsl)
  cat(sprintf("\u26a0 Warning: %d observation(s) below LSL.\n", n_below))
}
if (!is.na(usl) && any(x > usl)) {
  n_above <- sum(x > usl)
  cat(sprintf("\u26a0 Warning: %d observation(s) above USL.\n", n_above))
}

# ---------------------------------------------------------------------------
# Computation
# ---------------------------------------------------------------------------

# Basic descriptives
x_bar  <- mean(x)
s_overall <- sd(x)

# Within-subgroup sigma (moving range estimate for individual data)
MR       <- abs(diff(x))
MR_bar   <- mean(MR)
d2       <- 1.128          # d2 constant for n=2 (moving range of 2)
sigma_w  <- MR_bar / d2

# Spec width
has_both <- !is.na(lsl) && !is.na(usl)
spec_width <- if (has_both) usl - lsl else NA_real_

# --- Cp / Pp (require both limits) ---
Cp  <- if (has_both) spec_width / (6 * sigma_w)   else NA_real_
Pp  <- if (has_both) spec_width / (6 * s_overall)  else NA_real_

# --- Cpk ---
cpk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * sigma_w)   else NA_real_
cpk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * sigma_w)   else NA_real_
Cpk   <- min(c(cpk_u, cpk_l), na.rm = TRUE)

# --- Ppk ---
ppk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * s_overall) else NA_real_
ppk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * s_overall) else NA_real_
Ppk   <- min(c(ppk_u, ppk_l), na.rm = TRUE)

# --- Cpm (Taguchi — requires both limits; target = midpoint) ---
target <- if (has_both) (lsl + usl) / 2 else x_bar
Cpm    <- if (has_both) {
  spec_width / (6 * sqrt(s_overall^2 + (x_bar - target)^2))
} else NA_real_

# --- Sigma level ---
sigma_level <- Cpk * 3

# --- PPM estimate ---
if (!is.na(usl) && !is.na(lsl)) {
  ppm_above <- pnorm((usl - x_bar) / sigma_w, lower.tail = FALSE) * 1e6
  ppm_below <- pnorm((lsl - x_bar) / sigma_w, lower.tail = TRUE)  * 1e6
  ppm_total <- ppm_above + ppm_below
} else if (!is.na(usl)) {
  ppm_above <- pnorm((usl - x_bar) / sigma_w, lower.tail = FALSE) * 1e6
  ppm_below <- NA_real_
  ppm_total <- ppm_above
} else {
  ppm_below <- pnorm((lsl - x_bar) / sigma_w, lower.tail = TRUE) * 1e6
  ppm_above <- NA_real_
  ppm_total <- ppm_below
}

# --- Verdict ---
verdict <- if (Cpk >= 1.67) {
  "EXCELLENT  (Cpk \u2265 1.67)"
} else if (Cpk >= 1.33) {
  "CAPABLE    (Cpk \u2265 1.33)"
} else if (Cpk >= 1.00) {
  "MARGINAL   (1.00 \u2264 Cpk < 1.33)"
} else {
  "NOT CAPABLE (Cpk < 1.00)"
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Process Capability Analysis (Normal)\n")
cat(sprintf("  File: %s   Col: %s   n = %d\n",
            basename(data_file), col_name, n))
cat(sprintf("  LSL: %s   USL: %s\n",
            if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl),
            if (is.na(usl)) "(none)" else sprintf("%.4f", usl)))
cat("=================================================================\n\n")

cat("  Descriptives:\n")
cat(sprintf("    Mean (X-bar):       %.4f\n",  x_bar))
cat(sprintf("    SD (overall, s):    %.4f\n",  s_overall))
cat(sprintf("    SD (within, MR/d2): %.4f\n",  sigma_w))
cat(sprintf("    Min:                %.4f\n",  min(x)))
cat(sprintf("    Max:                %.4f\n",  max(x)))
cat("\n")

cat("  Capability indices (within sigma):\n")
if (!is.na(Cp))  cat(sprintf("    Cp:                 %.4f\n", Cp))
cat(sprintf("    Cpk:                %.4f\n", Cpk))
if (!is.na(Cpm)) cat(sprintf("    Cpm (Taguchi):      %.4f\n", Cpm))
cat("\n")

cat("  Performance indices (overall sigma):\n")
if (!is.na(Pp))  cat(sprintf("    Pp:                 %.4f\n", Pp))
cat(sprintf("    Ppk:                %.4f\n", Ppk))
cat("\n")

cat(sprintf("  Sigma level:          %.2f\u03c3\n", sigma_level))
if (!is.na(ppm_total)) {
  cat(sprintf("  Est. PPM out-of-spec: %.1f\n", ppm_total))
}
cat("\n")

cat("--- Verdict ---------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

cat("  Thresholds:\n")
cat("    Cpk \u2265 1.67  \u2192 excellent\n")
cat("    Cpk \u2265 1.33  \u2192 capable (typical FDA / ISO 13485 requirement)\n")
cat("    Cpk \u2265 1.00  \u2192 marginal (process meeting spec, but barely)\n")
cat("    Cpk < 1.00  \u2192 not capable\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_HIST <- "#AEC6E8"
COL_CURV <- "#2E5BBA"
COL_LSL  <- "#C0392B"
COL_USL  <- "#C0392B"
COL_MEAN <- "#1A1A2E"
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

plot_df  <- data.frame(value = x)
bw       <- max(diff(range(x)) / 30, s_overall / 5)

# Normal curve overlay (using within-sigma for Cpk line)
x_seq    <- seq(min(x) - 3 * s_overall, max(x) + 3 * s_overall, length.out = 400)
norm_df  <- data.frame(
  x = x_seq,
  y = dnorm(x_seq, mean = x_bar, sd = s_overall) * n * bw
)

cap_label <- if (!is.na(Cp)) {
  sprintf("Cp=%.2f  Cpk=%.2f  Pp=%.2f  Ppk=%.2f", Cp, Cpk, Pp, Ppk)
} else {
  sprintf("Cpk=%.2f  Ppk=%.2f", Cpk, Ppk)
}

p_hist <- ggplot(plot_df, aes(x = value)) +
  geom_histogram(binwidth = bw, fill = COL_HIST, color = "white", alpha = 0.9) +
  geom_line(data = norm_df, aes(x = x, y = y),
            color = COL_CURV, linewidth = 1) +
  geom_vline(xintercept = x_bar, linetype = "solid",
             color = COL_MEAN, linewidth = 0.8) +
  labs(
    title = sprintf("Process Capability (Normal)  |  %s", cap_label),
    x     = col_name,
    y     = "Count"
  ) +
  theme_jr

# Add spec limit lines
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

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_cap_normal.png"))

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
  sprintf("Cap Normal  |  %s  |  n=%d  X-bar=%.4f  s=%.4f  %s",
          basename(data_file), n, x_bar, s_overall, verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_hist, vp = viewport())
popViewport()

dev.off()

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
