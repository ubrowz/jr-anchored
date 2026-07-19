#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_dx_compare.R <data.csv> [--tests colA,colB]
#                 [--conf C] [--direction {higher|lower}] [--positive LABEL]
#                 [--ci-method {delong|logit}]
#
# Compare the AUCs of TWO continuous tests measured on the SAME subjects
# against a common binary reference standard — the correlated-ROC case. Reports
# each test's AUC with a confidence interval, the difference in AUCs with a
# confidence interval, and a DeLong test of H0: AUC_A = AUC_B that accounts for
# the correlation between the two tests (they are measured on the same people,
# so their AUCs are not independent). Saves a two-panel PNG (overlaid ROC
# curves; difference with its CI) to the output directory (~/Downloads by
# default).
#
# <data.csv>       CSV with columns: id, reference, and two score columns.
#                    id         subject identifier (unique)
#                    reference  reference-standard condition
#                    <two score columns> the two continuous tests
#                  Labels accepted for reference (case-insensitive): 1/0,
#                  pos/neg, positive/negative, yes/no, true/false, +/-.
# --tests colA,colB
#                  the two score column names, comma-separated. If omitted and
#                  the file has exactly two columns besides id and reference,
#                  those two are used (colA vs colB).
# --conf C         two-sided confidence level in (0, 1); default 0.95.
# --direction      higher  higher score => more likely positive (default)
#                  lower   lower score  => more likely positive
#                  Applied to BOTH tests. If the two tests read in opposite
#                  directions, flip one test's sign in the CSV before running.
# --positive LABEL label to treat as positive in the reference column.
# --ci-method      delong AUC +/- z*SE on the raw scale (default)
#                  logit  interval on the logit scale, back-transformed
#                         (per-test AUC CIs only; the difference CI is always
#                         on the raw scale).
#
# Method: nonparametric AUC by the tie-aware Mann-Whitney kernel; the variance
# of each AUC and the COVARIANCE between the two use the placement-value method
# of DeLong, DeLong & Clarke-Pearson (1988), Biometrics 44:837-845 — the method
# written for exactly this correlated-curve comparison (see also Hanley &
# McNeil 1983, Radiology 148:839-843). Var(AUC_A - AUC_B) = Var(A) + Var(B)
# - 2 Cov(A, B); z = (AUC_A - AUC_B) / sqrt(Var of the difference).
#
# Needs ggplot2 (for the plot only; all statistics are base R).
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("❌ RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
platform_dir <- Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos")
lib_path <- file.path(renv_lib, "renv", "library", platform_dir, r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("❌ renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

LABEL_SCHEMES <- list(
  list(pos = "1",        neg = "0"),
  list(pos = "pos",      neg = "neg"),
  list(pos = "positive", neg = "negative"),
  list(pos = "yes",      neg = "no"),
  list(pos = "y",        neg = "n"),
  list(pos = "true",     neg = "false"),
  list(pos = "t",        neg = "f"),
  list(pos = "+",        neg = "-")
)

BG       <- "#FFFFFF"
BANNER   <- "#2E5BBA"
COL_A    <- "#2E5BBA"
COL_B    <- "#ED7D31"
COL_CH   <- "#BBBBBB"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_dx_compare <data.csv> [--tests colA,colB] [--conf C]",
  "                          [--direction {higher|lower}] [--positive LABEL]",
  "                          [--ci-method {delong|logit}]",
  "Example:",
  "  jrc_clinical_dx_compare paired.csv --tests marker_a,marker_b --conf 0.95",
  sep = "\n"
)

csv_file <- NULL; tests <- NULL; conf <- 0.95
direction <- "higher"; positive_label <- NULL; ci_method <- "delong"

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0("❌ ", flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--tests" && i < length(args)) {
    tests <- tolower(trimws(strsplit(args[i + 1], ",")[[1]]))
    tests <- tests[tests != ""]
    i <- i + 2
  } else if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--direction" && i < length(args)) {
    direction <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--positive" && i < length(args)) {
    positive_label <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--ci-method" && i < length(args)) {
    ci_method <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (grepl("^--", a)) {
    stop(paste0("❌ Unknown argument: ", a, "\n", usage))
  } else {
    if (!is.null(csv_file)) {
      stop(paste0("❌ Only one data file may be given. Got a second: ", a,
                  "\n", usage))
    }
    csv_file <- a; i <- i + 1
  }
}

if (is.null(csv_file)) stop(paste("❌ A data CSV is required.\n", usage))
if (conf <= 0 || conf >= 1) stop("❌ --conf must be strictly between 0 and 1 (e.g. 0.95).")
if (!(direction %in% c("higher", "lower"))) stop("❌ --direction must be 'higher' or 'lower'.")
if (!(ci_method %in% c("delong", "logit"))) stop("❌ --ci-method must be 'delong' or 'logit'.")
if (!is.null(tests) && length(tests) != 2) {
  stop("❌ --tests must name exactly two columns, e.g. --tests marker_a,marker_b.")
}

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) stop(paste("❌ File not found:", csv_file))

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV:", e$message))
)
names(dat) <- tolower(trimws(names(dat)))

if (!all(c("id", "reference") %in% names(dat))) {
  stop(paste("❌ Missing column(s):",
             paste(setdiff(c("id", "reference"), names(dat)), collapse = ", "),
             "\n   Required: id, reference, and two score columns."))
}

# Resolve the two test columns.
if (is.null(tests)) {
  others <- setdiff(names(dat), c("id", "reference"))
  if (length(others) != 2) {
    stop(paste0("❌ Could not infer the two test columns (found ",
                length(others), " besides id/reference). ",
                "Name them with --tests colA,colB."))
  }
  tests <- others
}
missing_tests <- setdiff(tests, names(dat))
if (length(missing_tests) > 0) {
  stop(paste("❌ Test column(s) not found:", paste(missing_tests, collapse = ", "),
             "\n   Columns present:", paste(names(dat), collapse = ", ")))
}
if (tests[1] == tests[2]) stop("❌ The two --tests columns must be different.")
col_a <- tests[1]; col_b <- tests[2]

dat$id        <- as.character(trimws(dat$id))
dat$reference <- tolower(as.character(trimws(dat$reference)))
score_a <- suppressWarnings(as.numeric(dat[[col_a]]))
score_b <- suppressWarnings(as.numeric(dat[[col_b]]))

is_blank <- function(x) is.na(x) | x == "" | x == "na"
keep <- !(is_blank(dat$id) | is_blank(dat$reference) |
          is.na(score_a) | is.na(score_b))
n_dropped <- sum(!keep)
dat <- dat[keep, , drop = FALSE]
score_a <- score_a[keep]; score_b <- score_b[keep]

if (nrow(dat) == 0) stop("❌ No complete rows: every row has a missing value.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}
if (!all(is.finite(score_a)) || !all(is.finite(score_b))) {
  stop("❌ Both test columns must be finite numeric (no Inf/NaN).")
}

map_binary <- function(x, colname) {
  lv <- sort(unique(x))
  if (length(lv) > 2) {
    stop(paste0("❌ Column '", colname, "' must have at most 2 distinct ",
                "values. Got: ", paste(lv, collapse = ", ")))
  }
  if (!is.null(positive_label)) {
    if (!(positive_label %in% lv)) {
      stop(paste0("❌ --positive '", positive_label, "' does not appear in ",
                  "column '", colname, "'. Values present: ",
                  paste(lv, collapse = ", ")))
    }
    return(as.integer(x == positive_label))
  }
  for (s in LABEL_SCHEMES) {
    if (all(lv %in% c(s$pos, s$neg))) return(as.integer(x == s$pos))
  }
  stop(paste0("❌ Column '", colname, "' uses labels this script does not ",
              "recognise: ", paste(lv, collapse = ", "),
              "\n   Use 1/0, pos/neg, positive/negative, yes/no, true/false,",
              " +/-\n   or name the positive label with --positive."))
}
ref <- map_binary(dat$reference, "reference")

# Orient both tests so that a higher oriented score means "more likely positive".
orient <- if (direction == "higher") 1 else -1
oa <- orient * score_a
ob <- orient * score_b

a_pos <- oa[ref == 1]; a_neg <- oa[ref == 0]
b_pos <- ob[ref == 1]; b_neg <- ob[ref == 0]
m <- sum(ref == 1); n <- sum(ref == 0)

if (m < 2) stop("❌ At least 2 reference-positive subjects are required.")
if (n < 2) stop("❌ At least 2 reference-negative subjects are required.")

# ---------------------------------------------------------------------------
# DeLong AUC + placement values (same kernel as jrc_clinical_dx_roc)
# ---------------------------------------------------------------------------

delong_auc <- function(x, y) {
  mm <- length(x); nn <- length(y)
  z  <- c(x, y)
  tz <- rank(z, ties.method = "average")
  tx <- rank(x, ties.method = "average")
  ty <- rank(y, ties.method = "average")
  auc <- (sum(tz[1:mm]) - mm * (mm + 1) / 2) / (mm * nn)
  v10 <- (tz[1:mm] - tx) / nn
  v01 <- 1 - (tz[(mm + 1):(mm + nn)] - ty) / mm
  list(auc = auc, v10 = v10, v01 = v01,
       var = var(v10) / mm + var(v01) / nn)
}

dA <- delong_auc(a_pos, a_neg)
dB <- delong_auc(b_pos, b_neg)

# Covariance of the two AUCs via aligned placement values (same subjects).
cov_ab   <- cov(dA$v10, dB$v10) / m + cov(dA$v01, dB$v01) / n
var_diff <- dA$var + dB$var - 2 * cov_ab
diff_auc <- dA$auc - dB$auc
se_diff  <- sqrt(max(var_diff, 0))
z_stat   <- if (se_diff > 0) diff_auc / se_diff else NA_real_
p_val    <- if (is.na(z_stat)) NA_real_ else 2 * pnorm(-abs(z_stat))
auc_corr <- if (dA$var > 0 && dB$var > 0) cov_ab / sqrt(dA$var * dB$var) else NA_real_

z_crit <- qnorm(1 - (1 - conf) / 2)

# Per-test AUC CI (raw DeLong, or logit-transformed), mirroring dx_roc.
auc_ci <- function(auc, v) {
  se <- sqrt(v)
  if (ci_method == "delong") {
    c(max(0, auc - z_crit * se), min(1, auc + z_crit * se))
  } else {
    if (auc <= 0 || auc >= 1) return(c(NA_real_, NA_real_))
    lg    <- qlogis(auc)
    se_lg <- se / (auc * (1 - auc))
    plogis(lg + c(-1, 1) * z_crit * se_lg)
  }
}
ci_a <- auc_ci(dA$auc, dA$var)
ci_b <- auc_ci(dB$auc, dB$var)
diff_ci <- c(diff_auc - z_crit * se_diff, diff_auc + z_crit * se_diff)

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

conf_pct <- conf * 100
ci_label <- if (ci_method == "delong") "DeLong (raw scale)" else "DeLong (logit-transformed)"

cat("Paired ROC comparison (correlated AUCs, DeLong 1988)\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d  (reference + = %d, reference - = %d)\n",
            m + n, m, n))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
cat(sprintf("Tests         : A = %s   vs   B = %s\n", col_a, col_b))
cat(sprintf("Direction     : %s score => positive\n", direction))
cat(sprintf("Confidence    : %g%%   CI method: %s\n", conf_pct, ci_label))
cat("\n")

cat("Area under the ROC curve\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("AUC A (%-14s: %.4f  (%g%% CI %.4f, %.4f)\n",
            paste0(col_a, ")"), dA$auc, conf_pct, ci_a[1], ci_a[2]))
cat(sprintf("AUC B (%-14s: %.4f  (%g%% CI %.4f, %.4f)\n",
            paste0(col_b, ")"), dB$auc, conf_pct, ci_b[1], ci_b[2]))
cat("\n")

cat("Difference A - B (paired DeLong test)\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Difference    : %+.4f  (%g%% CI %+.4f, %+.4f)\n",
            diff_auc, conf_pct, diff_ci[1], diff_ci[2]))
cat(sprintf("Correlation   : %.4f  (between the two AUCs)\n", auc_corr))
cat(sprintf("H0: AUC A = AUC B   z = %.4f   p = %.4g\n", z_stat, p_val))
better <- if (diff_auc > 0) col_a else col_b
if (!is.na(p_val) && p_val < (1 - conf)) {
  cat(sprintf("=> Test %s has the higher AUC, and the difference is significant\n",
              better))
  cat(sprintf("   at the %g%% level (p = %.4g).\n", conf_pct, p_val))
} else {
  cat(sprintf("=> No significant difference at the %g%% level (p = %.4g): the\n",
              conf_pct, p_val))
  cat("   data do not establish that either test has the higher AUC.\n")
}
cat("\n")

# ---------------------------------------------------------------------------
# Two-panel PNG: overlaid ROC curves + difference with CI
# ---------------------------------------------------------------------------

roc_points <- function(pos, neg) {
  thr <- sort(unique(c(pos, neg, Inf, -Inf)), decreasing = TRUE)
  tpr <- sapply(thr, function(t) mean(pos >= t))
  fpr <- sapply(thr, function(t) mean(neg >= t))
  data.frame(fpr = fpr, tpr = tpr)
}
ra <- roc_points(a_pos, a_neg); ra$test <- col_a
rb <- roc_points(b_pos, b_neg); rb$test <- col_b
roc_df <- rbind(ra, rb)

p1 <- ggplot(roc_df, aes(fpr, tpr, colour = test)) +
  geom_abline(slope = 1, intercept = 0, colour = COL_CH, linetype = 2) +
  geom_line(linewidth = 1.1) +
  scale_colour_manual(values = setNames(c(COL_A, COL_B), c(col_a, col_b))) +
  coord_equal() +
  labs(x = "False positive rate (1 - specificity)",
       y = "True positive rate (sensitivity)", colour = "Test") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = c(0.72, 0.18),
        plot.background = element_rect(fill = BG, colour = NA))

diff_df <- data.frame(lab = "AUC A - AUC B", est = diff_auc,
                      lo = diff_ci[1], hi = diff_ci[2])
p2 <- ggplot(diff_df, aes(est, lab)) +
  geom_vline(xintercept = 0, colour = COL_CH, linetype = 2) +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.15,
                colour = COL_A, linewidth = 1) +
  geom_point(size = 3, colour = COL_A) +
  labs(x = sprintf("Difference in AUC  (%g%% CI)   z = %.2f, p = %.3g",
                   conf_pct, z_stat, p_val), y = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = BG, colour = NA))

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_clinical_dx_compare.png"))
cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1100, res = 180, bg = BG)
grid.newpage()
pushViewport(viewport(layout = grid.layout(nrow = 2, ncol = 1,
                                           heights = unit(c(0.07, 0.93), "npc"))))
pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = BANNER, col = NA))
grid.text(sprintf("Paired ROC comparison  |  %s  |  AUC %s = %.4f  vs  %s = %.4f  |  diff %+.4f, p = %.3g",
                  basename(csv_file), col_a, dA$auc, col_b, dB$auc, diff_auc, p_val),
          gp = gpar(col = "white", fontsize = 10, fontface = "bold"))
popViewport()
pushViewport(viewport(layout.pos.row = 2, layout = grid.layout(nrow = 1, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()
invisible(dev.off())

cat(sprintf("✅ Done. Open %s to view the overlaid ROC curves.\n",
            basename(out_file)))
jr_log_output_hashes(c(out_file))
