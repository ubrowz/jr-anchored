# =============================================================================
# jrc_cap_sixpack.R
# JR Validated Environment — Process Capability module
#
# Process Capability Sixpack — a single PNG combining:
#   Panel 1 (top-left):    Individuals (X) chart with control limits
#   Panel 2 (top-right):   Moving Range (MR) chart
#   Panel 3 (middle-left): Histogram with spec limits and normal curve
#   Panel 4 (middle-right): Normal probability plot (Q-Q plot)
#   Panel 5 (bottom-left): Capability indices summary (Cp, Cpk, Pp, Ppk, Cpm)
#   Panel 6 (bottom-right): Observed vs expected tail proportions
#
# Usage: jrc_cap_sixpack <data.csv> <col> <lsl> <usl>
#
# <lsl> and <usl> may each be "-" to omit one-sided. At least one must be a number.
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) {
  stop("Usage: jrc_cap_sixpack <data.csv> <col> <lsl> <usl>\n  Use '-' for <lsl> or <usl> to analyse one-sided.")
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

# ---------------------------------------------------------------------------
# Computation — descriptives and capability
# ---------------------------------------------------------------------------
x_bar     <- mean(x)
s_overall <- sd(x)
n_obs     <- n

# Moving range
MR        <- abs(diff(x))
MR_bar    <- mean(MR)
d2        <- 1.128
sigma_w   <- MR_bar / d2

# Control chart limits (Individuals)
UCL_X <- x_bar + 3 * sigma_w
LCL_X <- x_bar - 3 * sigma_w
UCL_MR <- 3.267 * MR_bar    # D4 * MR_bar, D4=3.267 for n=2
LCL_MR <- 0

# OOC detection
ooc_x  <- x < LCL_X | x > UCL_X
ooc_mr <- c(FALSE, MR > UCL_MR)

# Spec / capability
has_both   <- !is.na(lsl) && !is.na(usl)
spec_width <- if (has_both) usl - lsl else NA_real_

Cp  <- if (has_both) spec_width / (6 * sigma_w)   else NA_real_
Pp  <- if (has_both) spec_width / (6 * s_overall)  else NA_real_

cpk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * sigma_w)   else NA_real_
cpk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * sigma_w)   else NA_real_
Cpk   <- min(c(cpk_u, cpk_l), na.rm = TRUE)

ppk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * s_overall) else NA_real_
ppk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * s_overall) else NA_real_
Ppk   <- min(c(ppk_u, ppk_l), na.rm = TRUE)

target <- if (has_both) (lsl + usl) / 2 else x_bar
Cpm    <- if (has_both) {
  spec_width / (6 * sqrt(s_overall^2 + (x_bar - target)^2))
} else NA_real_

sigma_level <- Cpk * 3

# PPM estimate
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

# Normality
sw_result <- shapiro.test(x)

# SPC verdict
n_ooc   <- sum(ooc_x) + sum(ooc_mr[-1])
spc_verdict <- if (n_ooc == 0) "In Control" else sprintf("%d OOC signal(s)", n_ooc)

# Capability verdict
cap_verdict <- if (Cpk >= 1.67) {
  "EXCELLENT"
} else if (Cpk >= 1.33) {
  "CAPABLE"
} else if (Cpk >= 1.00) {
  "MARGINAL"
} else {
  "NOT CAPABLE"
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Process Capability Sixpack\n")
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
cat("\n")

cat("  Control chart limits (I-MR):\n")
cat(sprintf("    X: UCL = %.4f  CL = %.4f  LCL = %.4f\n",  UCL_X, x_bar, LCL_X))
cat(sprintf("    MR: UCL = %.4f  CL = %.4f  LCL = %.4f\n", UCL_MR, MR_bar, LCL_MR))
cat(sprintf("    OOC signals:        %d\n\n", n_ooc))

cat("  Capability indices:\n")
if (!is.na(Cp))  cat(sprintf("    Cp:                 %.4f\n", Cp))
cat(sprintf("    Cpk:                %.4f\n", Cpk))
if (!is.na(Cpm)) cat(sprintf("    Cpm (Taguchi):      %.4f\n", Cpm))
if (!is.na(Pp))  cat(sprintf("    Pp:                 %.4f\n", Pp))
cat(sprintf("    Ppk:                %.4f\n", Ppk))
cat(sprintf("    Sigma level:        %.2f\u03c3\n", sigma_level))
if (!is.na(ppm_total)) {
  cat(sprintf("    Est. PPM OOS:       %.1f\n", ppm_total))
}
cat("\n")

cat(sprintf("  Normality (Shapiro-Wilk): W = %.4f, p = %.4f\n\n",
            sw_result$statistic, sw_result$p.value))

cat("--- Verdict ---------------------------------------------------\n")
cat(sprintf("  SPC:  %s\n", spc_verdict))
cat(sprintf("  Cap:  %s  (Cpk = %.4f)\n", cap_verdict, Cpk))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_IC   <- "#1A1A2E"
COL_OOC  <- "#C0392B"
COL_CL   <- "#2E5BBA"
COL_UCL  <- "#C0392B"
COL_2S   <- "#E67E22"
COL_1S   <- "#27AE60"
COL_HIST <- "#AEC6E8"
COL_CURV <- "#2E5BBA"
COL_SPEC <- "#C0392B"
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- theme_minimal(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 9, face = "bold"),
    axis.text        = element_text(size = 7),
    axis.title       = element_text(size = 8)
  )

# --- Panel 1: Individuals chart ---
x_df <- data.frame(
  idx   = seq_len(n_obs),
  id    = if ("id" %in% names(df)) as.character(df$id[!is.na(x_raw)]) else as.character(seq_len(n_obs)),
  value = x,
  ooc   = ooc_x
)
x_label_df <- x_df[x_df$ooc, ]

p1 <- ggplot(x_df, aes(x = idx, y = value)) +
  geom_hline(yintercept = x_bar + 2 * sigma_w, linetype = "dashed", color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = x_bar - 2 * sigma_w, linetype = "dashed", color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = x_bar + sigma_w,     linetype = "dashed", color = COL_1S, linewidth = 0.5) +
  geom_hline(yintercept = x_bar - sigma_w,     linetype = "dashed", color = COL_1S, linewidth = 0.5) +
  geom_hline(yintercept = UCL_X,  linetype = "dashed", color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = LCL_X,  linetype = "dashed", color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = x_bar,  linetype = "solid",  color = COL_CL,  linewidth = 0.7)

if (!is.na(usl)) {
  p1 <- p1 + geom_hline(yintercept = usl, linetype = "dotted", color = COL_SPEC, linewidth = 0.8)
}
if (!is.na(lsl)) {
  p1 <- p1 + geom_hline(yintercept = lsl, linetype = "dotted", color = COL_SPEC, linewidth = 0.8)
}

p1 <- p1 +
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 1.8, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  labs(title = "Individuals (X) Chart", x = "Observation", y = "Value") +
  theme_jr

if (nrow(x_label_df) > 0) {
  p1 <- p1 + geom_text(data = x_label_df, aes(label = id),
                        nudge_y = 0.05 * diff(range(x)), size = 2.5, color = COL_OOC)
}

# --- Panel 2: Moving Range chart ---
MR_vals <- c(NA_real_, MR)
mr_df <- data.frame(
  idx   = seq_len(n_obs),
  value = MR_vals,
  ooc   = ooc_mr
)
mr_df_plot <- mr_df[!is.na(mr_df$value), ]

p2 <- ggplot(mr_df_plot, aes(x = idx, y = value)) +
  geom_hline(yintercept = UCL_MR, linetype = "dashed", color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = MR_bar, linetype = "solid",  color = COL_CL,  linewidth = 0.7) +
  geom_hline(yintercept = LCL_MR, linetype = "dashed", color = COL_UCL, linewidth = 0.5, alpha = 0.4) +
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 1.8, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  labs(title = "Moving Range (MR) Chart", x = "Observation", y = "Moving Range") +
  theme_jr

# --- Panel 3: Capability histogram ---
bw <- max(diff(range(x)) / 25, s_overall / 5)

x_seq   <- seq(min(x) - 3 * s_overall, max(x) + 3 * s_overall, length.out = 400)
norm_df <- data.frame(
  x = x_seq,
  y = dnorm(x_seq, mean = x_bar, sd = s_overall) * n * bw
)

p3 <- ggplot(data.frame(value = x), aes(x = value)) +
  geom_histogram(binwidth = bw, fill = COL_HIST, color = "white", alpha = 0.9) +
  geom_line(data = norm_df, aes(x = x, y = y), color = COL_CURV, linewidth = 1) +
  geom_vline(xintercept = x_bar, linetype = "solid", color = COL_IC, linewidth = 0.8)

if (!is.na(lsl)) {
  p3 <- p3 + geom_vline(xintercept = lsl, linetype = "dashed",
                         color = COL_SPEC, linewidth = 1) +
    annotate("text", x = lsl, y = Inf, label = sprintf("LSL\n%.4g", lsl),
             hjust = 1.1, vjust = 1.5, color = COL_SPEC, size = 2.5, fontface = "bold")
}
if (!is.na(usl)) {
  p3 <- p3 + geom_vline(xintercept = usl, linetype = "dashed",
                         color = COL_SPEC, linewidth = 1) +
    annotate("text", x = usl, y = Inf, label = sprintf("USL\n%.4g", usl),
             hjust = -0.1, vjust = 1.5, color = COL_SPEC, size = 2.5, fontface = "bold")
}

cap_label <- if (!is.na(Cp)) sprintf("Cp=%.2f  Cpk=%.2f", Cp, Cpk) else sprintf("Cpk=%.2f", Cpk)

p3 <- p3 +
  labs(title = sprintf("Histogram  |  %s", cap_label), x = col_name, y = "Count") +
  theme_jr

# --- Panel 4: Normal probability plot (Q-Q) ---
qq_df <- data.frame(
  theoretical = qnorm(ppoints(n)),
  sample      = sort(x)
)

# Fit line through Q1/Q3
q_th  <- qnorm(c(0.25, 0.75))
q_sam <- quantile(x, c(0.25, 0.75))
slope <- diff(q_sam) / diff(q_th)
inter <- q_sam[1] - slope * q_th[1]
qq_line_df <- data.frame(
  x = range(qq_df$theoretical),
  y = inter + slope * range(qq_df$theoretical)
)

p4 <- ggplot(qq_df, aes(x = theoretical, y = sample)) +
  geom_line(data = qq_line_df, aes(x = x, y = y),
            color = COL_CL, linewidth = 0.8, linetype = "solid") +
  geom_point(color = COL_IC, size = 1.5, alpha = 0.8) +
  labs(
    title = sprintf("Normal Probability Plot  |  SW p=%.3f", sw_result$p.value),
    x     = "Theoretical Quantiles",
    y     = col_name
  ) +
  theme_jr

# --- Panel 5: Capability summary text ---
summary_lines <- c(
  sprintf("n = %d", n),
  sprintf("X-bar = %.4f", x_bar),
  sprintf("s (overall) = %.4f", s_overall),
  sprintf("sigma_w = %.4f", sigma_w),
  "",
  if (!is.na(Cp))  sprintf("Cp  = %.4f", Cp)  else NULL,
  sprintf("Cpk = %.4f", Cpk),
  if (!is.na(Cpm)) sprintf("Cpm = %.4f", Cpm) else NULL,
  "",
  if (!is.na(Pp))  sprintf("Pp  = %.4f", Pp)  else NULL,
  sprintf("Ppk = %.4f", Ppk),
  "",
  sprintf("Sigma level = %.2f\u03c3", sigma_level),
  if (!is.na(ppm_total)) sprintf("Est. PPM OOS = %.1f", ppm_total) else NULL
)
summary_lines <- summary_lines[!sapply(summary_lines, is.null)]

p5 <- ggplot() +
  annotate("text",
           x = 0.05, y = seq(0.95, 0.05, length.out = length(summary_lines)),
           label = summary_lines,
           hjust = 0, vjust = 1,
           size = 3.2, family = "mono") +
  xlim(0, 1) + ylim(0, 1) +
  labs(title = "Summary") +
  theme_void() +
  theme(plot.background = element_rect(fill = BG, color = NA),
        plot.title = element_text(size = 9, face = "bold", hjust = 0, margin = margin(b = 4)))

# --- Panel 6: Verdict box ---
verdict_lines <- c(
  sprintf("Verdict: %s", cap_verdict),
  sprintf("Cpk = %.4f", Cpk),
  sprintf("Ppk = %.4f", Ppk),
  "",
  sprintf("SPC: %s", spc_verdict),
  "",
  "Thresholds:",
  "Cpk >= 1.67 : Excellent",
  "Cpk >= 1.33 : Capable",
  "Cpk >= 1.00 : Marginal",
  "Cpk <  1.00 : Not Capable"
)

verdict_col <- if (Cpk >= 1.33) "#E8F5E9" else if (Cpk >= 1.00) "#FFF3CD" else "#FDECEA"

p6 <- ggplot() +
  annotation_custom(
    grid::rectGrob(gp = grid::gpar(fill = verdict_col, col = NA))
  ) +
  annotate("text",
           x = 0.05, y = seq(0.95, 0.05, length.out = length(verdict_lines)),
           label = verdict_lines,
           hjust = 0, vjust = 1,
           size = 3.2, family = "mono",
           fontface = ifelse(seq_along(verdict_lines) == 1, "bold", "plain")) +
  xlim(0, 1) + ylim(0, 1) +
  labs(title = "Capability Verdict") +
  theme_void() +
  theme(plot.background = element_rect(fill = verdict_col, color = NA),
        plot.title = element_text(size = 9, face = "bold", hjust = 0, margin = margin(b = 4)))

# ---------------------------------------------------------------------------
# Save PNG — 3x2 grid
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_cap_sixpack.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 3600, height = 2400, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow    = 4,
  ncol    = 1,
  heights = unit(c(0.05, 0.31, 0.31, 0.33), "npc")
)))

# Title strip
pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
header_cp  <- if (!is.na(Cp)) sprintf("Cp=%.2f  ", Cp) else ""
header_pp  <- if (!is.na(Pp)) sprintf("  Pp=%.2f", Pp) else ""
grid.text(
  sprintf("Process Capability Sixpack  |  %s  |  n=%d  X-bar=%.4f  %sCpk=%.4f  Ppk=%.4f%s  |  %s",
          basename(data_file), n, x_bar, header_cp, Cpk, Ppk, header_pp, cap_verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

# Row 2: I chart + MR chart
pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

# Row 3: Histogram + Q-Q plot
pushViewport(viewport(layout.pos.row = 3,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p3, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p4, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

# Row 4: Summary + Verdict
pushViewport(viewport(layout.pos.row = 4,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p5, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p6, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

dev.off()

cat("\u2705 Done.\n")
jr_log_output_hashes(c(out_file))
