# =============================================================================
# jrc_msa_gauge_rr.R
# JR Validated Environment — MSA module
#
# Gauge Repeatability & Reproducibility (Gauge R&R) analysis — ANOVA method.
# Reads a CSV with columns: part, operator, value.
# Computes variance components (repeatability, reproducibility, part-to-part),
# reports %GRR and number of distinct categories (ndc), and saves a
# four-panel PNG to ~/Downloads/.
#
# Usage: jrc_msa_gauge_rr <data.csv> [--tolerance <value>]
#
# Arguments:
#   data.csv             CSV file with columns: part, operator, value
#   --tolerance <value>  Optional: process tolerance (USL - LSL). When
#                        supplied, %GRR vs tolerance is also reported.
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_msa_gauge_rr <data.csv> [--tolerance <value>]")
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
lib_path <- file.path(renv_lib, "renv", "library", "macos", r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

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

required_cols <- c("part", "operator", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: part, operator, value"))
}

dat$part     <- as.factor(as.character(dat$part))
dat$operator <- as.factor(as.character(dat$operator))
dat$value    <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$value))) {
  stop("\u274c Non-numeric values found in the 'value' column.")
}

n_parts     <- nlevels(dat$part)
n_operators <- nlevels(dat$operator)

if (n_parts < 2)     stop("\u274c At least 2 parts are required.")
if (n_operators < 2) stop("\u274c At least 2 operators are required.")

# --- Check for balanced design (equal replicates per part-operator cell)
cell_counts <- table(dat$part, dat$operator)
rep_counts  <- unique(as.vector(cell_counts))
if (length(rep_counts) > 1) {
  stop(paste("\u274c Unbalanced design: cells have", paste(rep_counts, collapse = "/"),
             "replicates.\n   All part-operator combinations must have the same number",
             "of replicates."))
}
n_reps  <- rep_counts[1]
n_total <- nrow(dat)

if (n_reps < 2) {
  stop("\u274c At least 2 replicates per part-operator combination are required.")
}

# ---------------------------------------------------------------------------
# Two-way ANOVA with interaction
# ---------------------------------------------------------------------------
fit     <- aov(value ~ part * operator, data = dat)
aov_tbl <- summary(fit)[[1]]
rownames(aov_tbl) <- trimws(rownames(aov_tbl))

MS_part <- aov_tbl["part",          "Mean Sq"]
MS_op   <- aov_tbl["operator",      "Mean Sq"]
MS_int  <- aov_tbl["part:operator", "Mean Sq"]
MS_res  <- aov_tbl["Residuals",     "Mean Sq"]

F_part  <- aov_tbl["part",          "F value"]
F_op    <- aov_tbl["operator",      "F value"]
F_int   <- aov_tbl["part:operator", "F value"]

p_part  <- aov_tbl["part",          "Pr(>F)"]
p_op    <- aov_tbl["operator",      "Pr(>F)"]
p_int   <- aov_tbl["part:operator", "Pr(>F)"]

df_part <- aov_tbl["part",          "Df"]
df_op   <- aov_tbl["operator",      "Df"]
df_int  <- aov_tbl["part:operator", "Df"]
df_res  <- aov_tbl["Residuals",     "Df"]

# ---------------------------------------------------------------------------
# Variance components (expected mean squares, balanced two-way random model)
#
#   E[MS_res]  = sigma2_e
#   E[MS_int]  = sigma2_e + n * sigma2_int
#   E[MS_op]   = sigma2_e + n * sigma2_int + n_parts * n * sigma2_op
#   E[MS_part] = sigma2_e + n * sigma2_int + n_operators * n * sigma2_part
# ---------------------------------------------------------------------------
var_e   <- MS_res
var_int <- max(0, (MS_int - MS_res)  / n_reps)
var_op  <- max(0, (MS_op  - MS_int)  / (n_parts     * n_reps))
var_p   <- max(0, (MS_part - MS_int) / (n_operators * n_reps))

var_repeat <- var_e
var_reprod <- var_op + var_int          # interaction attributed to reproducibility
var_grr    <- var_repeat + var_reprod
var_part   <- var_p
var_total  <- var_grr + var_part

sd_repeat  <- sqrt(var_repeat)
sd_reprod  <- sqrt(var_reprod)
sd_grr     <- sqrt(var_grr)
sd_part    <- sqrt(var_part)
sd_total   <- sqrt(var_total)

safe_pct <- function(num, den) if (den > 0) 100 * num / den else 0

pct_ev    <- safe_pct(sd_repeat, sd_total)
pct_av    <- safe_pct(sd_reprod, sd_total)
pct_grr   <- safe_pct(sd_grr,    sd_total)
pct_pv    <- safe_pct(sd_part,   sd_total)

pct_var_ev  <- safe_pct(var_repeat, var_total)
pct_var_av  <- safe_pct(var_reprod, var_total)
pct_var_grr <- safe_pct(var_grr,    var_total)
pct_var_pv  <- safe_pct(var_part,   var_total)

ndc <- if (sd_grr > 0) floor(1.41 * sd_part / sd_grr) else Inf

pct_grr_tol <- if (!is.na(tolerance)) 100 * 6 * sd_grr / tolerance else NA_real_

verdict_grr <- if (pct_grr < 10) "ACCEPTABLE" else if (pct_grr < 30) "MARGINAL" else "UNACCEPTABLE"
verdict_ndc <- if (is.infinite(ndc) || ndc >= 5) "ACCEPTABLE" else "UNACCEPTABLE"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Gauge R&R Analysis — ANOVA Method\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Parts:      %d\n", n_parts))
cat(sprintf("  Operators:  %d\n", n_operators))
cat(sprintf("  Replicates: %d per cell\n", n_reps))
cat(sprintf("  Total obs:  %d\n\n", n_total))

cat("--- ANOVA Table -------------------------------------------------\n")
cat(sprintf("  %-22s %6s %12s %8s %8s\n", "Source", "DF", "Mean Sq", "F", "p"))
cat(sprintf("  %-22s %6d %12.5f %8.3f %8.4f\n",
            "Part",          df_part, MS_part, F_part, p_part))
cat(sprintf("  %-22s %6d %12.5f %8.3f %8.4f\n",
            "Operator",      df_op,   MS_op,   F_op,   p_op))
cat(sprintf("  %-22s %6d %12.5f %8.3f %8.4f\n",
            "Part:Operator", df_int,  MS_int,  F_int,  p_int))
cat(sprintf("  %-22s %6d %12.5f\n",
            "Residual",      df_res,  MS_res))
cat("\n")

cat("--- Variance Components -----------------------------------------\n")
cat(sprintf("  %-24s %12s %14s\n", "Source", "Variance", "%Contribution"))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Repeatability (EV)", var_repeat, pct_var_ev))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Reproducibility (AV)", var_reprod, pct_var_av))
cat(sprintf("    %-22s %12.6f\n", "Operator", var_op))
cat(sprintf("    %-22s %12.6f\n", "Part:Operator", var_int))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Gauge R&R", var_grr, pct_var_grr))
cat(sprintf("  %-24s %12.6f %13.2f%%\n", "Part-to-Part", var_part, pct_var_pv))
cat(sprintf("  %-24s %12.6f\n", "Total", var_total))
cat("\n")

cat("--- Study Variation (%%Study Var) --------------------------------\n")
cat(sprintf("  %-24s %10s %12s\n", "Source", "StdDev", "%Study Var"))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Repeatability (EV)", sd_repeat, pct_ev))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Reproducibility (AV)", sd_reprod, pct_av))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Gauge R&R", sd_grr, pct_grr))
cat(sprintf("  %-24s %10.5f %11.2f%%\n", "Part-to-Part", sd_part, pct_pv))
cat(sprintf("  %-24s %10.5f\n", "Total", sd_total))
cat("\n")

if (!is.na(tolerance)) {
  cat(sprintf("  %%GRR vs Tolerance (6\u03c3 / tolerance): %.2f%%\n\n", pct_grr_tol))
}

ndc_str <- if (is.infinite(ndc)) "\u221e" else as.character(ndc)
cat(sprintf("  Number of Distinct Categories (ndc): %s\n\n", ndc_str))

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %%GRR (%%Study Var): %.2f%%  \u2192  %s\n", pct_grr, verdict_grr))
cat(sprintf("  ndc:               %s      \u2192  %s\n", ndc_str, verdict_ndc))
if (!is.na(tolerance)) {
  verdict_tol <- if (pct_grr_tol < 10) "ACCEPTABLE" else if (pct_grr_tol < 30) "MARGINAL" else "UNACCEPTABLE"
  cat(sprintf("  %%GRR (vs Tol):     %.2f%%  \u2192  %s\n", pct_grr_tol, verdict_tol))
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_EV   <- "#4472C4"
COL_AV   <- "#ED7D31"
COL_GRR  <- "#5DAD5D"
COL_PV   <- "#9E9E9E"
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

# --- Panel 1: Components of variation ---
comp_df <- data.frame(
  source = factor(
    c("Repeatability\n(EV)", "Reproducibility\n(AV)", "Gauge R&R", "Part-to-Part"),
    levels = c("Repeatability\n(EV)", "Reproducibility\n(AV)", "Gauge R&R", "Part-to-Part")
  ),
  pct   = c(pct_ev, pct_av, pct_grr, pct_pv),
  col   = c(COL_EV, COL_AV, COL_GRR, COL_PV)
)

p1 <- ggplot(comp_df, aes(x = source, y = pct, fill = source)) +
  geom_col(width = 0.6, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.1f%%", pct)), vjust = -0.4, size = 3) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "darkgreen", linewidth = 0.5, alpha = 0.8) +
  geom_hline(yintercept = 30, linetype = "dashed", color = "red",       linewidth = 0.5, alpha = 0.8) +
  scale_fill_manual(values = setNames(comp_df$col, comp_df$source)) +
  scale_y_continuous(
    limits = c(0, max(115, max(comp_df$pct) * 1.15)),
    labels = function(x) paste0(x, "%")
  ) +
  labs(title = "Components of Variation", x = NULL, y = "% Study Variation") +
  theme_jr

# --- Panel 2: Measurements by part ---
p2 <- ggplot(dat, aes(x = part, y = value)) +
  geom_boxplot(fill = COL_PV, color = "#555555", outlier.shape = NA, width = 0.5) +
  geom_jitter(width = 0.15, size = 1.4, alpha = 0.55, color = "#333333") +
  labs(title = "Measurements by Part", x = "Part", y = "Value") +
  theme_jr

# --- Panel 3: Measurements by operator ---
p3 <- ggplot(dat, aes(x = operator, y = value)) +
  geom_boxplot(fill = COL_AV, color = "#555555", outlier.shape = NA, width = 0.5) +
  geom_jitter(width = 0.15, size = 1.4, alpha = 0.55, color = "#333333") +
  labs(title = "Measurements by Operator", x = "Operator", y = "Value") +
  theme_jr

# --- Panel 4: Part × Operator interaction ---
inter_df <- aggregate(value ~ part + operator, data = dat, FUN = mean)
p4 <- ggplot(inter_df, aes(x = part, y = value, color = operator, group = operator)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5) +
  labs(title = "Part \u00d7 Operator Interaction",
       x = "Part", y = "Mean Value", color = "Operator") +
  theme_jr +
  theme(legend.position = "right", legend.key.size = unit(0.5, "cm"))

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_msa_gauge_rr.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1800, res = 180, bg = BG)

grid.newpage()

# Title strip at top
pushViewport(viewport(layout = grid.layout(
  nrow   = 2,
  ncol   = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Gauge R&R  |  %s  |  %%GRR = %.1f%%  |  ndc = %s  |  %s",
          basename(csv_file), pct_grr, ndc_str, verdict_grr),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 2, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
print(p3, vp = viewport(layout.pos.row = 2, layout.pos.col = 1))
print(p4, vp = viewport(layout.pos.row = 2, layout.pos.col = 2))
popViewport()

dev.off()

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
