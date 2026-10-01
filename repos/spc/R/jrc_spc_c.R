# =============================================================================
# jrc_spc_c.R
# JR Validated Environment — SPC module
#
# C-chart (count of defects per unit). Assumes constant inspection opportunity.
# Reads a CSV with columns: (subgroup or id) and defects.
# Computes c-bar, Poisson-based control limits, applies all 8 Western Electric
# rules, and saves a single-panel PNG to the output directory
# (JR_OUT_DIR, default ~/Downloads).
#
# Usage: jrc_spc_c <data.csv>
#
# Version: 1.0
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_spc_c <data.csv>")
}

csv_file <- args[1]

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

# Accept 'subgroup' or 'id' as the first identifying column
id_col <- NULL
if ("subgroup" %in% names(dat)) {
  id_col <- "subgroup"
} else if ("id" %in% names(dat)) {
  id_col <- "id"
} else {
  stop("\u274c Missing identifier column. Expected 'subgroup' or 'id'.")
}

if (!"defects" %in% names(dat)) {
  stop("\u274c Missing required column: defects\n   Required: (subgroup or id), defects")
}

dat$label   <- as.character(dat[[id_col]])
dat$defects <- suppressWarnings(as.numeric(dat$defects))

if (any(is.na(dat$defects))) {
  stop("\u274c Non-numeric values found in the 'defects' column.")
}
if (any(dat$defects < 0)) {
  stop("\u274c All defect counts must be non-negative.")
}
if (any(dat$defects != floor(dat$defects))) {
  stop("\u274c All defect counts must be non-negative integers.")
}
if (nrow(dat) < 2) {
  stop("\u274c At least 2 subgroups are required.")
}

# ---------------------------------------------------------------------------
# C-chart calculations
# ---------------------------------------------------------------------------
c_bar  <- mean(dat$defects)
sigma  <- sqrt(c_bar)
UCL    <- c_bar + 3 * sigma
LCL    <- max(0, c_bar - 3 * sigma)

# Apply WE rules
if (sigma <= 0) {
  cat("\u26a0\ufe0f  No variation in the data (c-bar = 0): control limits collapse onto\n")
  cat("   the centre line and the run rules cannot be evaluated. No signals reported.\n\n")
}
we        <- jr_spc_rules(dat$defects, cl = c_bar, sigma = sigma)
ooc_labels <- dat$label[we$ooc]

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
verdict <- if (length(ooc_labels) == 0) "IN CONTROL" else "OUT OF CONTROL"

cat("\n")
cat("=================================================================\n")
cat("  C-Chart (Count of Defects per Unit)\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Subgroups:  %d\n", nrow(dat)))
cat(sprintf("  c-bar:      %.6f\n", c_bar))
cat(sprintf("  Sigma:      %.6f\n", sigma))
cat(sprintf("  UCL:        %.6f\n", UCL))
cat(sprintf("  LCL:        %.6f\n", LCL))
cat("\n")

cat("--- WE Rules ----------------------------------------------------\n")
cat(sprintf("  Rules fired:  %s\n",
            if (length(we$rules_fired) == 0) "none" else paste(we$rules_fired, collapse = ", ")))
if (length(ooc_labels) > 0) {
  cat(sprintf("  OOC points:   %s\n", paste(ooc_labels, collapse = ", ")))
} else {
  cat("  OOC points:   none\n")
}
cat("\n")
cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
COL_IC   <- "#1F3A6E"
COL_OOC  <- "#CC2222"
COL_CL   <- "#444444"
COL_WARN <- "#E8891A"
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- jr_theme(10)

idx <- seq_len(nrow(dat))

df_plot <- data.frame(
  idx     = idx,
  label   = dat$label,
  defects = dat$defects,
  ooc     = we$ooc,
  stringsAsFactors = FALSE
)

p1 <- ggplot(df_plot, aes(x = idx)) +
  geom_hline(yintercept = c_bar, color = COL_CL,  linewidth = 0.8) +
  geom_hline(yintercept = UCL,   color = COL_OOC, linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = LCL,   color = COL_OOC, linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = c_bar + 2 * sigma, color = COL_WARN, linewidth = 0.4, linetype = "dotted") +
  geom_hline(yintercept = max(0, c_bar - 2 * sigma), color = COL_WARN, linewidth = 0.4, linetype = "dotted") +
  geom_hline(yintercept = c_bar +     sigma, color = COL_WARN, linewidth = 0.3, linetype = "dotted") +
  geom_hline(yintercept = max(0, c_bar -     sigma), color = COL_WARN, linewidth = 0.3, linetype = "dotted") +
  geom_line(aes(y = defects), color = COL_IC, linewidth = 0.6) +
  geom_point(aes(y = defects, color = ooc), size = 2.5, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  scale_x_continuous(breaks = idx, labels = dat$label) +
  labs(title = "C-Chart (Defects per Unit)",
       x = "Subgroup", y = "Defect Count") +
  theme_jr +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

p1 <- p1 +
  annotate("text", x = max(idx), y = UCL,   label = sprintf("UCL=%.4f", UCL),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_OOC) +
  annotate("text", x = max(idx), y = LCL,   label = sprintf("LCL=%.4f", LCL),
           hjust = 1.05, vjust =  1.2, size = 2.8, color = COL_OOC) +
  annotate("text", x = max(idx), y = c_bar, label = sprintf("CL=%.4f",  c_bar),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_CL)

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_spc_c.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

jr_save_titled_png(
  out_file,
  sprintf("C-Chart  |  %s  |  c-bar=%.4f  |  UCL=%.4f  |  Subgroups=%d  |  %s",
          basename(csv_file), c_bar, UCL, nrow(dat), verdict),
  list(p1),
  width = 2400,
  height = 1200,
  res = 180,
  strip = 0.08
)

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
