#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_dx_roc.R <data.csv> [--conf C]
#                 [--direction {higher|lower}] [--positive LABEL]
#                 [--ci-method {delong|logit}]
#
# ROC analysis of a CONTINUOUS index test (a score, titre, concentration)
# against a binary reference standard. Reports the empirical ROC curve, the
# area under it (AUC) with a DeLong confidence interval, and the Youden-
# optimal cutoff. Saves a two-panel PNG to ~/Downloads/.
#
# <data.csv>      CSV with columns: id, reference, score.
#                   id         subject identifier (unique)
#                   reference  reference-standard condition (positive/negative)
#                   score      continuous index-test measurement
#                 Accepted reference labels (case-insensitive): 1/0, pos/neg,
#                 positive/negative, yes/no, true/false, +/-.
# --conf          two-sided confidence level in (0, 1); default 0.95
# --direction     higher  higher score => more likely positive (default)
#                 lower   lower score  => more likely positive
#                 Not auto-detected: the direction is a claim about the assay
#                 and must be stated by the design, not inferred from the data.
# --positive      override the label treated as "positive" in the reference
#                 column (e.g. --positive diseased). Case-insensitive.
# --ci-method     delong  AUC +/- z*SE on the raw scale (default; matches the
#                         conventional DeLong interval)
#                 logit   interval built on the logit scale then back-
#                         transformed; stays inside (0,1) and behaves better
#                         when AUC is near 1
#
# Needs the following libraries: ggplot2, grid
#
# AUC (Mann-Whitney form, with the tie-aware kernel):
#   psi(x, y) = 1 if x > y ; 0.5 if x == y ; 0 if x < y
#   AUC = (1 / (m*n)) * sum_{i=1..m} sum_{j=1..n} psi(X_i, Y_j)
# with X the m reference-positive scores and Y the n reference-negative
# scores. Ties contribute 0.5, which is what makes the empirical AUC equal the
# trapezoidal area under the empirical ROC curve.
#
# DeLong variance, computed by the O((m+n)log(m+n)) midrank algorithm of
# Sun & Xu (2014) rather than the O(m*n) double sum:
#   Z  = c(X, Y)
#   TZ = midrank of each element of Z within Z
#   TX = midrank of each element of X within X alone
#   TY = midrank of each element of Y within Y alone
#   AUC   = (sum(TZ[1..m]) - m*(m+1)/2) / (m*n)
#   V10_i = (TZ_i - TX_i) / n            i = 1..m   (placement values)
#   V01_j = 1 - (TZ_{m+j} - TY_j) / m    j = 1..n
#   S10   = var(V10) ; S01 = var(V01)
#   Var(AUC) = S10/m + S01/n
# "midrank" is the average rank within tied groups (R: rank(ties="average")).
#
# References:
#   DeLong ER, DeLong DM, Clarke-Pearson DL (1988), Comparing the areas under
#   two or more correlated receiver operating characteristic curves: a
#   nonparametric approach, Biometrics 44:837-845.
#   Sun X, Xu W (2014), Fast implementation of DeLong's algorithm for
#   comparing the areas under correlated receiver operating characteristic
#   curves, IEEE Signal Processing Letters 21:1389-1393.
#   Hanley JA, McNeil BJ (1982), The meaning and use of the area under a
#   receiver operating characteristic (ROC) curve, Radiology 143:29-36.
#   Youden WJ (1950), Index for rating diagnostic tests, Cancer 3:32-35.
#
# Note: the Youden-optimal cutoff is a data-derived quantity. Selecting it on
# the same data used to report sensitivity and specificity at that cutoff is
# optimistically biased. Pre-specify the cutoff, or validate it on an
# independent set, before making a performance claim.
#
# Cutoff convention: the reported cutoff is an OBSERVED score value, applied
# with an explicit rule ("score >= c => positive"). Some tools (pROC among
# them) instead report the midpoint between the two adjacent observed values.
# Both name the identical classifier and give identical sensitivity and
# specificity; only the printed number differs. An observed value is used here
# because it is directly reportable and cannot fall outside the measured range.
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

BG        <- "#FFFFFF"
GRID_COL  <- "#EEEEEE"
COL_ROC   <- "#2E5BBA"
COL_CHANCE<- "#BBBBBB"
COL_YOUDEN<- "#ED7D31"
COL_SENS  <- "#2E5BBA"
COL_SPEC  <- "#5DAD5D"

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_dx_roc <data.csv> [--conf C] [--direction {higher|lower}]",
  "                      [--positive LABEL] [--ci-method {delong|logit}]",
  "Example:",
  "  jrc_clinical_dx_roc marker_study.csv --conf 0.95 --direction higher",
  sep = "\n"
)

csv_file <- NULL; conf <- 0.95; direction <- "higher"
positive_label <- NULL; ci_method <- "delong"

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0(flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--direction" && i < length(args)) {
    direction <- tolower(args[i + 1]); i <- i + 2
  } else if (a == "--positive" && i < length(args)) {
    positive_label <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--ci-method" && i < length(args)) {
    ci_method <- tolower(args[i + 1]); i <- i + 2
  } else if (grepl("^--", a)) {
    stop(paste0("Unknown argument: ", a, "\n", usage))
  } else {
    if (!is.null(csv_file)) {
      stop(paste0("Only one data file may be given. Got a second: ", a,
                  "\n", usage))
    }
    csv_file <- a; i <- i + 1
  }
}

if (is.null(csv_file)) {
  stop(paste("A data CSV is required.\n", usage))
}
if (is.na(conf) || conf <= 0 || conf >= 1) {
  stop("--conf must be strictly between 0 and 1 (e.g. 0.95).")
}
if (!(direction %in% c("higher", "lower"))) {
  stop("--direction must be 'higher' or 'lower'.")
}
if (!(ci_method %in% c("delong", "logit"))) {
  stop("--ci-method must be 'delong' or 'logit'.")
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

required_cols <- c("id", "reference", "score")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, reference, score"))
}

dat$id        <- as.character(trimws(dat$id))
dat$reference <- tolower(as.character(trimws(dat$reference)))
dat$score     <- suppressWarnings(as.numeric(dat$score))

is_blank  <- function(x) is.na(x) | x == "" | x == "na"
keep      <- !(is_blank(dat$id) | is_blank(dat$reference) | is.na(dat$score))
n_dropped <- sum(!keep)
dat       <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) {
  stop("❌ No complete rows: every row has a missing id, reference or score.")
}
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}
if (!all(is.finite(dat$score))) {
  stop("❌ Column 'score' must be finite numeric (no Inf/NaN).")
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

# Orient so that a HIGHER oriented score always means "more likely positive".
# All internal maths uses the oriented score; cutoffs are reported back on the
# original scale.
orient <- if (direction == "higher") 1 else -1
dat$oscore <- orient * dat$score

x_pos <- dat$oscore[ref == 1]
y_neg <- dat$oscore[ref == 0]
m     <- length(x_pos)
n     <- length(y_neg)

if (m < 2) stop("❌ At least 2 reference-positive subjects are required.")
if (n < 2) stop("❌ At least 2 reference-negative subjects are required.")

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Fast DeLong (Sun & Xu 2014). Returns AUC and its variance.
delong_auc <- function(x, y) {
  m <- length(x); n <- length(y)
  z  <- c(x, y)
  tz <- rank(z, ties.method = "average")
  tx <- rank(x, ties.method = "average")
  ty <- rank(y, ties.method = "average")

  auc <- (sum(tz[1:m]) - m * (m + 1) / 2) / (m * n)

  v10 <- (tz[1:m] - tx) / n
  v01 <- 1 - (tz[(m + 1):(m + n)] - ty) / m

  s10 <- var(v10)
  s01 <- var(v01)
  list(auc = auc, var = s10 / m + s01 / n, v10 = v10, v01 = v01)
}

# Direct O(m*n) Mann-Whitney AUC — the definition, used to cross-check the
# midrank result at runtime on small inputs. Kept deliberately naive.
auc_direct <- function(x, y) {
  s <- 0
  for (xi in x) s <- s + sum(xi > y) + 0.5 * sum(xi == y)
  s / (length(x) * length(y))
}

# ---------------------------------------------------------------------------
# AUC and its confidence interval
# ---------------------------------------------------------------------------

dl      <- delong_auc(x_pos, y_neg)
auc     <- dl$auc
auc_var <- dl$var
auc_se  <- sqrt(auc_var)

# Runtime self-check: on inputs small enough to afford it, the O((m+n)log)
# midrank AUC must reproduce the O(m*n) definitional sum exactly. This guards
# the algorithm that is the whole point of the script.
if (as.numeric(m) * as.numeric(n) <= 4e6) {
  auc_chk <- auc_direct(x_pos, y_neg)
  if (!isTRUE(all.equal(auc, auc_chk, tolerance = 1e-10))) {
    stop(sprintf(paste("❌ Internal check failed: midrank AUC %.12f does not",
                       "match the definitional Mann-Whitney sum %.12f.",
                       "Do not use this result."), auc, auc_chk))
  }
}

z_crit <- qnorm(1 - (1 - conf) / 2)

if (ci_method == "delong") {
  auc_ci <- c(max(0, auc - z_crit * auc_se), min(1, auc + z_crit * auc_se))
} else {
  # Logit interval: transform, add the delta-method SE, back-transform.
  if (auc <= 0 || auc >= 1 || auc_var == 0) {
    auc_ci <- c(NA_real_, NA_real_)
  } else {
    lg    <- log(auc / (1 - auc))
    se_lg <- auc_se / (auc * (1 - auc))
    auc_ci <- plogis(lg + c(-1, 1) * z_crit * se_lg)
  }
}

# Test of AUC = 0.5 (no discrimination), two-sided, using the DeLong SE.
auc_z <- if (auc_se > 0) (auc - 0.5) / auc_se else NA_real_
auc_p <- if (is.na(auc_z)) NA_real_ else 2 * pnorm(-abs(auc_z))

# ---------------------------------------------------------------------------
# Empirical ROC curve and the Youden-optimal cutoff
# ---------------------------------------------------------------------------

# Candidate cutoffs on the ORIENTED scale; predict positive when oscore >= t.
cuts <- sort(unique(dat$oscore))
thr  <- c(-Inf, cuts, Inf)

sens_at <- vapply(thr, function(t) sum(x_pos >= t) / m, numeric(1))
spec_at <- vapply(thr, function(t) sum(y_neg <  t) / n, numeric(1))

roc_df <- data.frame(fpr = 1 - spec_at, tpr = sens_at)
roc_df <- roc_df[order(roc_df$fpr, roc_df$tpr), ]

youden   <- sens_at + spec_at - 1
best_i   <- which.max(youden)
best_thr <- thr[best_i]
# Report the cutoff on the ORIGINAL scale, and state the rule in that scale.
best_cut_orig <- orient * best_thr

# The Youden optimum can land on one of the infinite sentinel thresholds, which
# is the degenerate "call everything positive" / "call everything negative"
# rule. That happens when no cutoff beats chance in the stated --direction.
# Report it as having no usable cutoff rather than printing "score <= Inf".
cutoff_degenerate <- !is.finite(best_thr)

rule_txt <- if (cutoff_degenerate) {
  "none — no cutoff beats chance in this direction"
} else if (direction == "higher") {
  sprintf("score >= %.6g => positive", best_cut_orig)
} else {
  sprintf("score <= %.6g => positive", best_cut_orig)
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

ci_label <- c(delong = "DeLong (raw scale)",
              logit  = "DeLong (logit-transformed)")[ci_method]

message(" ")
message("✅ ROC analysis — continuous test vs reference standard")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(sprintf("   Data file      : %s", basename(csv_file)))
message(sprintf("   Subjects       : %d evaluable%s", m + n,
                if (n_dropped > 0)
                  sprintf("  (%d row(s) dropped: missing data)", n_dropped)
                else ""))
message(sprintf("   Reference +    : %d", m))
message(sprintf("   Reference -    : %d", n))
message(sprintf("   Direction      : %s score => positive", direction))
message("   ------------------------------------------------------")
message(sprintf("   AUC            : %.4f", auc))
message(sprintf("   SE (DeLong)    : %.4f", auc_se))
if (any(is.na(auc_ci))) {
  message(sprintf("   %g%% CI         : not estimable (AUC at a boundary)",
                  conf * 100))
} else {
  message(sprintf("   %g%% CI         : (%.4f, %.4f)   [%s]",
                  conf * 100, auc_ci[1], auc_ci[2], ci_label))
}
if (!is.na(auc_p)) {
  message(sprintf("   H0: AUC = 0.5  : z = %.4f, p = %s",
                  auc_z, format.pval(auc_p, digits = 4, eps = 1e-16)))
}
message("   ------------------------------------------------------")
message("   Youden-optimal cutoff (J = sens + spec - 1):")
message(sprintf("   Cutoff         : %s", rule_txt))
if (cutoff_degenerate) {
  message("   Every candidate cutoff has J <= 0, so the best Youden rule is")
  message("   the trivial one that classifies all subjects the same way. No")
  message("   sensitivity/specificity pair is reported: there is nothing to")
  message("   report a cutoff FOR.")
} else {
  message(sprintf("   J              : %.4f", youden[best_i]))
  message(sprintf("   Sensitivity    : %.4f", sens_at[best_i]))
  message(sprintf("   Specificity    : %.4f", spec_at[best_i]))
}
message("   ------------------------------------------------------")

if (auc < 0.5) {
  message("   ⚠️  AUC < 0.5: the test discriminates in the OPPOSITE direction")
  message(sprintf("   to --direction %s. Check the assay orientation; if a",
                  direction))
  message(sprintf("   %s score really means positive, re-run with --direction %s.",
                  if (direction == "higher") "lower" else "higher",
                  if (direction == "higher") "lower" else "higher"))
  message("   ------------------------------------------------------")
}

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

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

p1 <- ggplot(roc_df, aes(x = fpr, y = tpr)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed",
              color = COL_CHANCE) +
  geom_step(color = COL_ROC, linewidth = 0.7, direction = "hv") +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(title = "Empirical ROC curve",
       subtitle = sprintf("AUC = %.4f  |  dashed = chance%s", auc,
                          if (cutoff_degenerate) ""
                          else "  |  orange = Youden optimum"),
       x = "1 - specificity (false positive rate)",
       y = "Sensitivity (true positive rate)") +
  theme_jr

# Only mark the Youden optimum when it is a real, finite cutoff.
if (!cutoff_degenerate) {
  youden_pt <- data.frame(fpr = 1 - spec_at[best_i], tpr = sens_at[best_i])
  p1 <- p1 + geom_point(data = youden_pt, aes(x = fpr, y = tpr),
                        color = COL_YOUDEN, size = 2.5)
}

# Sensitivity and specificity against the cutoff, on the ORIGINAL scale.
finite_i <- is.finite(thr)
cut_df <- rbind(
  data.frame(cutoff = orient * thr[finite_i], value = sens_at[finite_i],
             measure = "Sensitivity"),
  data.frame(cutoff = orient * thr[finite_i], value = spec_at[finite_i],
             measure = "Specificity")
)

p2 <- ggplot(cut_df, aes(x = cutoff, y = value, color = measure)) +
  geom_line(linewidth = 0.7) +
  scale_color_manual(values = c(Sensitivity = COL_SENS,
                                Specificity = COL_SPEC)) +
  ylim(0, 1) +
  labs(title = "Sensitivity and specificity vs cutoff",
       subtitle = if (cutoff_degenerate) "Youden cutoff: none"
                  else sprintf("Orange dashed = Youden cutoff (%s)", rule_txt),
       x = "Cutoff (original score scale)", y = NULL, color = NULL) +
  theme_jr

if (!cutoff_degenerate) {
  p2 <- p2 + geom_vline(xintercept = best_cut_orig, color = COL_YOUDEN,
                        linetype = "dashed")
}

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_clinical_dx_roc.png"))

cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1100, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow = 2, ncol = 1, heights = unit(c(0.07, 0.93), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = COL_ROC, col = NA))
grid.text(
  sprintf("ROC Analysis  |  %s  |  %d ref+ / %d ref-  |  AUC = %.4f (%g%% CI %.4f-%.4f)",
          basename(csv_file), m, n, auc, conf * 100,
          if (is.na(auc_ci[1])) NA else auc_ci[1],
          if (is.na(auc_ci[2])) NA else auc_ci[2]),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 1, ncol = 2)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 1, layout.pos.col = 2))
popViewport()

dev.off()

message("   Method: empirical (trapezoidal) ROC; AUC by the tie-aware")
message("   Mann-Whitney kernel; variance by DeLong (1988) via the midrank")
message("   algorithm of Sun & Xu (2014), cross-checked at runtime against")
message("   the definitional O(m*n) sum.")
message("   The Youden cutoff is chosen ON THIS DATA and is optimistically")
message("   biased: pre-specify a cutoff, or validate it on an independent")
message("   set, before making a performance claim.")
message(" ")

cat(sprintf("✅ Done. Open %s to view your report.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
