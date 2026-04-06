# =============================================================================
# jrc_msa_nested_grr.R
# JR Validated Environment — MSA module
#
# Nested Gauge R&R — for destructive or semi-destructive measurement systems
# where the same specimen cannot be measured by multiple operators.
# Each operator receives a unique set of specimens (nested design). Reports
# repeatability, reproducibility, part-to-part variation, and %GRR.
# Saves a two-panel PNG to ~/Downloads/.
#
# Usage: jrc_msa_nested_grr <data.csv> [--tolerance <value>]
#
# Arguments:
#   data.csv             CSV with columns: operator, part, replicate, value.
#                        Parts are nested within operators — each operator
#                        measures a different set of physical specimens.
#                        Part IDs may be reused across operators (e.g., both
#                        operator A and B can have a "part 1" — they are
#                        different physical specimens).
#   --tolerance <value>  Optional. Process tolerance (USL - LSL).
#                        When supplied, %GRR vs tolerance is also reported.
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_msa_nested_grr <data.csv> [--tolerance <value>]")
}

csv_file  <- args[1]
tolerance <- NA_real_
i <- 2
while (i <= length(args)) {
  if (args[i] == "--tolerance" && i < length(args)) {
    tolerance <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(tolerance) || tolerance <= 0) stop("--tolerance must be a positive number.")
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
if (!dir.exists(lib_path)) stop(paste("\u274c renv library not found at:", lib_path))
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

required_cols <- c("operator", "part", "replicate", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: operator, part, replicate, value"))
}

dat$operator  <- as.character(dat$operator)
dat$part      <- as.character(dat$part)
dat$replicate <- as.integer(dat$replicate)
dat$value     <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$value)))     stop("\u274c Non-numeric values in 'value' column.")
if (any(is.na(dat$replicate))) stop("\u274c Non-integer values in 'replicate' column.")

n_operators <- length(unique(dat$operator))
if (n_operators < 2) stop("\u274c At least 2 operators are required.")

# Check balance: each operator must have the same number of parts
parts_per_op <- tapply(dat$part, dat$operator, function(x) length(unique(x)))
if (length(unique(parts_per_op)) > 1) {
  stop(paste("\u274c Unbalanced design: operators have different numbers of parts.",
             "\n   Counts:", paste(names(parts_per_op), parts_per_op, sep = "=", collapse = ", ")))
}
n_parts <- unique(parts_per_op)[[1]]
if (n_parts < 2) stop("\u274c At least 2 parts per operator are required.")

# Check balance: each operator-part cell must have the same number of replicates
cell_reps <- table(dat$operator, dat$part)
# For nested design, many operator-part cells are empty (other operators' parts)
# Count only the non-zero cells (each part belongs to one operator)
nonzero_reps <- as.vector(cell_reps[cell_reps > 0])
if (length(unique(nonzero_reps)) > 1) {
  stop("\u274c Unbalanced design: not all operator-part cells have the same number of replicates.")
}
n_reps <- unique(nonzero_reps)[[1]]
if (n_reps < 2) {
  stop(paste("\u274c At least 2 replicates per specimen are required.",
             "\n   For truly destructive testing where each specimen can only be",
             "measured once,\n   include 2 specimens from the same unit/position",
             "as replicates."))
}

n_total <- nrow(dat)
operators <- sort(unique(dat$operator))

# ---------------------------------------------------------------------------
# Nested ANOVA: value ~ operator / part
# (parts nested within operators — no crossed interaction term)
# ---------------------------------------------------------------------------
dat$operator_f <- factor(dat$operator)
dat$part_f     <- factor(paste(dat$operator, dat$part, sep = ":"))  # globally unique part IDs

fit     <- aov(value ~ operator_f / part_f, data = dat)
aov_tbl <- summary(fit)[[1]]
rownames(aov_tbl) <- trimws(rownames(aov_tbl))

# Row names: "operator_f", "operator_f:part_f", "Residuals"
MS_O <- aov_tbl["operator_f",             "Mean Sq"]
MS_P <- aov_tbl["operator_f:part_f",      "Mean Sq"]
MS_e <- aov_tbl["Residuals",              "Mean Sq"]

F_O  <- aov_tbl["operator_f",             "F value"]
F_P  <- aov_tbl["operator_f:part_f",      "F value"]

p_O  <- aov_tbl["operator_f",             "Pr(>F)"]
p_P  <- aov_tbl["operator_f:part_f",      "Pr(>F)"]

df_O <- aov_tbl["operator_f",             "Df"]
df_P <- aov_tbl["operator_f:part_f",      "Df"]
df_e <- aov_tbl["Residuals",              "Df"]

# ---------------------------------------------------------------------------
# Variance components (expected mean squares, balanced nested model)
#
#   E[MS_e]   = sigma2_e
#   E[MS_P(O)] = sigma2_e + n_reps * sigma2_P
#   E[MS_O]   = sigma2_e + n_reps * sigma2_P + n_parts * n_reps * sigma2_O
# ---------------------------------------------------------------------------
var_e <- MS_e
var_P <- max(0, (MS_P - MS_e) / n_reps)
var_O <- max(0, (MS_O - MS_P) / (n_parts * n_reps))

var_repeat <- var_e
var_reprod <- var_O
var_grr    <- var_repeat + var_reprod
var_part   <- var_P
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

pct_grr_tol <- if (!is.na(tolerance)) 100 * 6 * sd_grr / tolerance else NA_real_

verdict_grr <- if (pct_grr < 10) "ACCEPTABLE" else if (pct_grr < 30) "MARGINAL" else "UNACCEPTABLE"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Nested Gauge R&R Analysis (Destructive / Semi-Destructive)\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Operators:  %d  (%s)\n", n_operators, paste(operators, collapse = ", ")))
cat(sprintf("  Parts/op:   %d  (unique specimens per operator)\n", n_parts))
cat(sprintf("  Replicates: %d  per specimen\n", n_reps))
cat(sprintf("  Total obs:  %d\n\n", n_total))

cat("  \u26a0\ufe0f  Nested design: parts are NOT shared across operators.\n")
cat("     Part-to-part variation is estimated within each operator's specimens.\n")
cat("     This assumes all operators received specimens from the same population.\n\n")

cat("--- ANOVA Table (Nested) ----------------------------------------\n")
cat(sprintf("  %-26s %6s %12s %8s %8s\n", "Source", "DF", "Mean Sq", "F", "p"))
cat(sprintf("  %-26s %6d %12.5f %8.3f %8.4f\n",
            "Operator",              df_O, MS_O, F_O, p_O))
cat(sprintf("  %-26s %6d %12.5f %8.3f %8.4f\n",
            "Part(Operator)",        df_P, MS_P, F_P, p_P))
cat(sprintf("  %-26s %6d %12.5f\n",
            "Residual (Repeat.)",    df_e, MS_e))
cat("\n")

cat("--- Variance Components -----------------------------------------\n")
cat(sprintf("  %-26s %12s %14s\n", "Source", "Variance", "%Contribution"))
cat(sprintf("  %-26s %12.6f %13.2f%%\n", "Repeatability (EV)", var_repeat, pct_var_ev))
cat(sprintf("  %-26s %12.6f %13.2f%%\n", "Reproducibility (AV)", var_reprod, pct_var_av))
cat(sprintf("  %-26s %12.6f %13.2f%%\n", "Gauge R&R",  var_grr,    pct_var_grr))
cat(sprintf("  %-26s %12.6f %13.2f%%\n", "Part-to-Part (nested)", var_part, pct_var_pv))
cat(sprintf("  %-26s %12.6f\n",          "Total", var_total))
cat("\n")

cat("--- Study Variation (%%Study Var) --------------------------------\n")
cat(sprintf("  %-26s %10s %12s\n", "Source", "StdDev", "%Study Var"))
cat(sprintf("  %-26s %10.5f %11.2f%%\n", "Repeatability (EV)", sd_repeat, pct_ev))
cat(sprintf("  %-26s %10.5f %11.2f%%\n", "Reproducibility (AV)", sd_reprod, pct_av))
cat(sprintf("  %-26s %10.5f %11.2f%%\n", "Gauge R&R", sd_grr, pct_grr))
cat(sprintf("  %-26s %10.5f %11.2f%%\n", "Part-to-Part (nested)", sd_part, pct_pv))
cat(sprintf("  %-26s %10.5f\n",          "Total", sd_total))
cat("\n")

if (!is.na(tolerance)) {
  cat(sprintf("  %%GRR vs Tolerance (6\u03c3 / tolerance): %.2f%%\n\n", pct_grr_tol))
}

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %%GRR (%%Study Var): %.2f%%  \u2192  %s\n", pct_grr, verdict_grr))
if (!is.na(tolerance)) {
  verdict_tol <- if (pct_grr_tol < 10) "ACCEPTABLE" else if (pct_grr_tol < 30) "MARGINAL" else "UNACCEPTABLE"
  cat(sprintf("  %%GRR (vs Tol):    %.2f%%  \u2192  %s\n", pct_grr_tol, verdict_tol))
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plots
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"
COL_EV   <- "#4472C4"
COL_AV   <- "#ED7D31"
COL_GRR  <- "#5DAD5D"
COL_PV   <- "#9E9E9E"

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

# --- Panel 1: Components of variation ---
comp_df <- data.frame(
  source = factor(
    c("Repeatability\n(EV)", "Reproducibility\n(AV)", "Gauge R&R", "Part-to-Part\n(nested)"),
    levels = c("Repeatability\n(EV)", "Reproducibility\n(AV)", "Gauge R&R", "Part-to-Part\n(nested)")
  ),
  pct = c(pct_ev, pct_av, pct_grr, pct_pv),
  col = c(COL_EV, COL_AV, COL_GRR, COL_PV)
)

p1 <- ggplot(comp_df, aes(x = source, y = pct, fill = source)) +
  geom_col(width = 0.6, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.1f%%", pct)), vjust = -0.4, size = 3) +
  geom_hline(yintercept = 10, linetype = "dashed",
             color = "darkgreen", linewidth = 0.5, alpha = 0.8) +
  geom_hline(yintercept = 30, linetype = "dashed",
             color = "red",       linewidth = 0.5, alpha = 0.8) +
  scale_fill_manual(values = setNames(comp_df$col, comp_df$source)) +
  scale_y_continuous(limits = c(0, max(115, max(comp_df$pct) * 1.15)),
                     labels = function(x) paste0(x, "%")) +
  labs(title    = "Components of Variation",
       subtitle = "Green dashed = 10%  |  Red dashed = 30%",
       x = NULL, y = "% Study Variation") +
  theme_jr

# --- Panel 2: Measurements by operator (all specimens, coloured by part) ---
dat$part_label <- paste0(dat$operator, "-", dat$part)
n_parts_total  <- length(unique(dat$part_label))
part_palette   <- colorRampPalette(c("#4472C4","#ED7D31","#5DAD5D","#FF6B6B",
                                     "#9B59B6","#1ABC9C","#F39C12","#E74C3C"))(n_parts_total)

# Per-operator means for annotation
op_means <- aggregate(value ~ operator, data = dat, FUN = mean)

p2 <- ggplot(dat, aes(x = operator, y = value, color = part_label)) +
  geom_jitter(width = 0.18, size = 2.2, alpha = 0.8, show.legend = FALSE) +
  stat_summary(fun = mean, geom = "crossbar",
               width = 0.5, linewidth = 0.6,
               color = "#222222", show.legend = FALSE) +
  scale_color_manual(values = part_palette) +
  labs(title    = "Measurements by Operator",
       subtitle = "Each point = one replicate  |  Crossbar = operator mean  |  Colour = specimen",
       x = "Operator", y = "Value") +
  theme_jr

# ---------------------------------------------------------------------------
# Combine and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_msa_nested_grr.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1200, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow = 2, ncol = 1, heights = unit(c(0.07, 0.93), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Nested Gauge R&R  |  %s  |  %%GRR = %.1f%%  |  %s",
          basename(csv_file), pct_grr, verdict_grr),
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
