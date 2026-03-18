# =============================================================================
# jrc_msa_attribute.R
# JR Validated Environment — MSA module
#
# Attribute Agreement Analysis.
# Evaluates agreement for categorical ratings (pass/fail, go/no-go, defect
# grades, etc.). Reports within-appraiser repeatability, between-appraiser
# reproducibility, and — when reference answers are supplied — accuracy
# against the known correct answer. Uses Cohen's Kappa (within-appraiser,
# each vs reference) and Fleiss' Kappa (between-appraiser).
# Saves a two-panel PNG to ~/Downloads/.
#
# Usage: jrc_msa_attribute <data.csv>
#
# Arguments:
#   data.csv    CSV with columns: part, appraiser, trial, rating.
#               An optional 'reference' column supplies the correct answer
#               for each part (same value for every row of a given part).
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_msa_attribute <data.csv>")
}
csv_file <- args[1]

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
if (!dir.exists(lib_path)) stop(paste("\u274c renv library not found at:", lib_path))
.libPaths(c(lib_path, .libPaths()))

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

required_cols <- c("part", "appraiser", "trial", "rating")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: part, appraiser, trial, rating"))
}

dat$part      <- as.character(dat$part)
dat$appraiser <- as.character(dat$appraiser)
dat$trial     <- as.integer(dat$trial)
dat$rating    <- as.character(trimws(dat$rating))

has_reference <- "reference" %in% names(dat)
if (has_reference) {
  dat$reference <- as.character(trimws(dat$reference))
  # Validate: each part must have exactly one reference value
  ref_check <- tapply(dat$reference, dat$part, function(x) length(unique(x)))
  if (any(ref_check > 1)) {
    stop("\u274c Each part must have exactly one reference value.")
  }
}

n_appraisers <- length(unique(dat$appraiser))
n_parts      <- length(unique(dat$part))
n_trials     <- length(unique(dat$trial))

if (n_appraisers < 2) stop("\u274c At least 2 appraisers are required.")
if (n_parts      < 2) stop("\u274c At least 2 parts are required.")
if (n_trials     < 2) stop("\u274c At least 2 trials are required.")

# Check balanced design
cell_counts <- table(dat$part, dat$appraiser)
trial_counts <- unique(as.vector(cell_counts))
if (length(trial_counts) > 1) {
  stop("\u274c Unbalanced design: not all part-appraiser combinations have the same number of trials.")
}

categories  <- sort(unique(dat$rating))
appraisers  <- sort(unique(dat$appraiser))
parts       <- sort(unique(dat$part))

# ---------------------------------------------------------------------------
# Helper: Cohen's Kappa
# ---------------------------------------------------------------------------
cohen_kappa <- function(r1, r2, cats) {
  n <- length(r1)
  if (n == 0) return(NA_real_)
  r1f <- factor(r1, levels = cats)
  r2f <- factor(r2, levels = cats)
  tab <- table(r1f, r2f)
  Po  <- sum(diag(tab)) / n
  Pe  <- sum(rowSums(tab) * colSums(tab)) / n^2
  if (abs(1 - Pe) < 1e-10) return(NA_real_)
  (Po - Pe) / (1 - Pe)
}

# ---------------------------------------------------------------------------
# Helper: Fleiss' Kappa (multiple raters, one rating per rater per subject)
# ---------------------------------------------------------------------------
fleiss_kappa <- function(ratings_mat, cats) {
  # ratings_mat: n_parts x n_raters character matrix
  n <- nrow(ratings_mat)  # subjects
  r <- ncol(ratings_mat)  # raters
  if (n < 2 || r < 2) return(NA_real_)
  n_ij <- sapply(cats, function(cat) rowSums(ratings_mat == cat))
  if (r == 1) return(NA_real_)
  P_bar <- mean((rowSums(n_ij^2) - r) / (r * (r - 1)))
  p_j   <- colSums(n_ij) / (n * r)
  P_e   <- sum(p_j^2)
  if (abs(1 - P_e) < 1e-10) return(NA_real_)
  (P_bar - P_e) / (1 - P_e)
}

kappa_verdict <- function(k) {
  if (is.na(k)) return("N/A")
  if (k > 0.9) "ACCEPTABLE" else if (k >= 0.7) "MARGINAL" else "UNACCEPTABLE"
}

pct_verdict <- function(p) {
  if (p > 90) "ACCEPTABLE" else if (p >= 80) "MARGINAL" else "UNACCEPTABLE"
}

# ---------------------------------------------------------------------------
# Within-appraiser analysis
# ---------------------------------------------------------------------------
within_results <- lapply(appraisers, function(ap) {
  d_ap <- dat[dat$appraiser == ap, ]
  # % within: proportion of parts where all trials give the same rating
  part_agree <- sapply(parts, function(pt) {
    ratings_pt <- d_ap$rating[d_ap$part == pt]
    length(unique(ratings_pt)) == 1
  })
  pct_within <- 100 * mean(part_agree)

  # Cohen's Kappa: trial 1 vs trial 2 (all pairs averaged if > 2 trials)
  trial_nums <- sort(unique(d_ap$trial))
  kappas <- c()
  for (ti in seq_along(trial_nums)) {
    for (tj in seq_along(trial_nums)) {
      if (tj <= ti) next
      t1 <- trial_nums[ti]; t2 <- trial_nums[tj]
      r1 <- sapply(parts, function(pt) d_ap$rating[d_ap$part == pt & d_ap$trial == t1])
      r2 <- sapply(parts, function(pt) d_ap$rating[d_ap$part == pt & d_ap$trial == t2])
      kappas <- c(kappas, cohen_kappa(r1, r2, categories))
    }
  }
  kappa_within <- mean(kappas, na.rm = TRUE)

  list(appraiser   = ap,
       pct_within  = pct_within,
       kappa_within = kappa_within)
})
names(within_results) <- appraisers

# ---------------------------------------------------------------------------
# Between-appraiser analysis (using trial 1)
# ---------------------------------------------------------------------------
# Build ratings matrix: n_parts x n_appraisers using trial 1
trial1 <- min(dat$trial)
ratings_mat <- sapply(appraisers, function(ap) {
  sapply(parts, function(pt) {
    r <- dat$rating[dat$part == pt & dat$appraiser == ap & dat$trial == trial1]
    if (length(r) == 0) NA_character_ else r[1]
  })
})
if (!is.matrix(ratings_mat)) ratings_mat <- matrix(ratings_mat, ncol = length(appraisers))
colnames(ratings_mat) <- appraisers
rownames(ratings_mat) <- parts

pct_between <- 100 * mean(apply(ratings_mat, 1, function(row) length(unique(row)) == 1))
kappa_between <- fleiss_kappa(ratings_mat, categories)

# ---------------------------------------------------------------------------
# Vs reference analysis (if available)
# ---------------------------------------------------------------------------
ref_results <- NULL
if (has_reference) {
  ref_map <- tapply(dat$reference, dat$part, unique)

  ref_results <- lapply(appraisers, function(ap) {
    d_ap <- dat[dat$appraiser == ap, ]
    # % match: all trials match reference for each part
    part_match <- sapply(parts, function(pt) {
      ratings_pt <- d_ap$rating[d_ap$part == pt]
      ref_val    <- ref_map[[pt]]
      all(ratings_pt == ref_val)
    })
    pct_ref <- 100 * mean(part_match)

    # Kappa: trial 1 vs reference
    r1  <- sapply(parts, function(pt)
      dat$rating[dat$part == pt & dat$appraiser == ap & dat$trial == trial1][1])
    ref <- sapply(parts, function(pt) ref_map[[pt]])
    k   <- cohen_kappa(r1, ref, categories)

    list(appraiser = ap, pct_ref = pct_ref, kappa_ref = k)
  })
  names(ref_results) <- appraisers

  # All appraisers vs reference: all trials of all appraisers match reference
  all_vs_ref <- sapply(parts, function(pt) {
    all_ratings <- dat$rating[dat$part == pt]
    ref_val     <- ref_map[[pt]]
    all(all_ratings == ref_val)
  })
  pct_all_ref <- 100 * mean(all_vs_ref)
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Attribute Agreement Analysis\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")
cat(sprintf("  Parts:      %d\n", n_parts))
cat(sprintf("  Appraisers: %d  (%s)\n", n_appraisers, paste(appraisers, collapse = ", ")))
cat(sprintf("  Trials:     %d\n", n_trials))
cat(sprintf("  Categories: %s\n", paste(categories, collapse = ", ")))
if (has_reference) cat("  Reference:  provided\n")
cat("\n")

cat("--- Within-Appraiser (Repeatability) ----------------------------\n")
cat(sprintf("  %-14s %12s %10s %14s\n", "Appraiser", "%Within", "Kappa", "Verdict"))
for (ap in appraisers) {
  wr <- within_results[[ap]]
  cat(sprintf("  %-14s %11.1f%% %10.4f %14s\n",
              ap, wr$pct_within, wr$kappa_within,
              kappa_verdict(wr$kappa_within)))
}
cat("\n")

cat("--- Between-Appraiser (Reproducibility) -------------------------\n")
cat(sprintf("  %%All appraisers agree (trial 1): %6.1f%%\n", pct_between))
cat(sprintf("  Fleiss' Kappa (trial 1):          %6.4f   \u2192  %s\n\n",
            kappa_between, kappa_verdict(kappa_between)))

if (has_reference) {
  cat("--- Each Appraiser vs Reference ---------------------------------\n")
  cat(sprintf("  %-14s %16s %10s %14s\n",
              "Appraiser", "%Match (all trials)", "Kappa", "Verdict"))
  for (ap in appraisers) {
    rr <- ref_results[[ap]]
    cat(sprintf("  %-14s %15.1f%% %10.4f %14s\n",
                ap, rr$pct_ref, rr$kappa_ref,
                kappa_verdict(rr$kappa_ref)))
  }
  cat(sprintf("\n  All appraisers vs reference:     %6.1f%%\n\n", pct_all_ref))
}

cat("--- Verdict -----------------------------------------------------\n")
for (ap in appraisers) {
  wr <- within_results[[ap]]
  cat(sprintf("  Within  %-10s  Kappa = %6.4f  \u2192  %s\n",
              ap, wr$kappa_within, kappa_verdict(wr$kappa_within)))
}
cat(sprintf("  Between (Fleiss') Kappa = %6.4f  \u2192  %s\n",
            kappa_between, kappa_verdict(kappa_between)))
if (has_reference) {
  for (ap in appraisers) {
    rr <- ref_results[[ap]]
    cat(sprintf("  Vs Ref  %-10s  Kappa = %6.4f  \u2192  %s\n",
                ap, rr$kappa_ref, kappa_verdict(rr$kappa_ref)))
  }
}
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plots
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"
COL_WITH <- "#4472C4"
COL_REF  <- "#ED7D31"
COL_BET  <- "#5DAD5D"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    plot.subtitle    = element_text(size = 8, color = "#555555"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9),
    legend.position  = "top",
    legend.text      = element_text(size = 8)
  )

# --- Panel 1: % Agreement bar chart ---
pct_df <- data.frame(
  appraiser = appraisers,
  Within    = sapply(appraisers, function(ap) within_results[[ap]]$pct_within),
  stringsAsFactors = FALSE
)
if (has_reference) {
  pct_df$VsRef <- sapply(appraisers, function(ap) ref_results[[ap]]$pct_ref)
}

pct_long <- reshape(pct_df,
                    varying   = if (has_reference) c("Within", "VsRef") else "Within",
                    v.names   = "pct",
                    timevar   = "type",
                    times     = if (has_reference) c("Within appraiser", "Vs reference") else "Within appraiser",
                    direction = "long")

p1 <- ggplot(pct_long, aes(x = appraiser, y = pct, fill = type)) +
  geom_col(position = position_dodge(0.7), width = 0.6) +
  geom_text(aes(label = sprintf("%.1f%%", pct)),
            position = position_dodge(0.7), vjust = -0.4, size = 2.8) +
  geom_hline(yintercept = 90, linetype = "dashed",
             color = "darkgreen", linewidth = 0.5, alpha = 0.8) +
  geom_hline(yintercept = 80, linetype = "dashed",
             color = "red",       linewidth = 0.5, alpha = 0.6) +
  scale_fill_manual(values = setNames(
    c(COL_WITH, COL_REF)[seq_along(unique(pct_long$type))],
    unique(pct_long$type)
  )) +
  scale_y_continuous(limits = c(0, 115), labels = function(x) paste0(x, "%")) +
  labs(title    = "% Agreement by Appraiser",
       subtitle = "Green dashed = 90% threshold  |  Red dashed = 80% threshold",
       x = "Appraiser", y = "% Agreement", fill = NULL) +
  theme_jr

# --- Panel 2: Kappa summary ---
kappa_rows <- data.frame(
  label  = character(),
  kappa  = numeric(),
  type   = character(),
  stringsAsFactors = FALSE
)
for (ap in appraisers) {
  kappa_rows <- rbind(kappa_rows, data.frame(
    label = paste("Within:", ap),
    kappa = within_results[[ap]]$kappa_within,
    type  = "Within appraiser",
    stringsAsFactors = FALSE
  ))
}
kappa_rows <- rbind(kappa_rows, data.frame(
  label = "Between (Fleiss')",
  kappa = kappa_between,
  type  = "Between appraisers",
  stringsAsFactors = FALSE
))
if (has_reference) {
  for (ap in appraisers) {
    kappa_rows <- rbind(kappa_rows, data.frame(
      label = paste("Vs Ref:", ap),
      kappa = ref_results[[ap]]$kappa_ref,
      type  = "Vs reference",
      stringsAsFactors = FALSE
    ))
  }
}
kappa_rows$label <- factor(kappa_rows$label, levels = rev(kappa_rows$label))

p2 <- ggplot(kappa_rows, aes(x = kappa, y = label, fill = type)) +
  geom_col(width = 0.6) +
  geom_vline(xintercept = 0.9, linetype = "dashed",
             color = "darkgreen", linewidth = 0.5, alpha = 0.8) +
  geom_vline(xintercept = 0.7, linetype = "dashed",
             color = "red",       linewidth = 0.5, alpha = 0.6) +
  geom_text(aes(label = sprintf("%.4f", kappa)),
            hjust = -0.1, size = 2.8) +
  scale_fill_manual(values = c(
    "Within appraiser"  = COL_WITH,
    "Between appraisers"= COL_BET,
    "Vs reference"      = COL_REF
  )) +
  scale_x_continuous(limits = c(min(0, min(kappa_rows$kappa) - 0.05),
                                 max(1.15, max(kappa_rows$kappa) + 0.15))) +
  labs(title    = "Kappa Statistics",
       subtitle = "Green dashed = 0.90  |  Red dashed = 0.70",
       x = "Kappa", y = NULL, fill = NULL) +
  theme_jr

# ---------------------------------------------------------------------------
# Combine and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_msa_attribute.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1100, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow = 2, ncol = 1, heights = unit(c(0.07, 0.93), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Attribute Agreement Analysis  |  %s  |  %d appraisers  |  %d parts  |  %d trials  |  Fleiss' \u03ba = %.4f (%s)",
          basename(csv_file), n_appraisers, n_parts, n_trials,
          kappa_between, kappa_verdict(kappa_between)),
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
