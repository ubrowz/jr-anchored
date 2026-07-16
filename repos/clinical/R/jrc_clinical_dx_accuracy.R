#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_dx_accuracy.R <data.csv> [--ci {exact|wilson}]
#                 [--conf C] [--prevalence P] [--positive LABEL]
#
# Diagnostic accuracy of a BINARY index test against a binary reference
# standard ("gold standard"). Reports the 2x2 table and the full set of
# operating characteristics with two-sided confidence intervals:
# sensitivity, specificity, PPV, NPV, LR+, LR- and overall accuracy.
#
# <data.csv>      CSV with columns: id, reference, result.
#                   id         subject identifier (unique)
#                   reference  reference-standard condition (positive/negative)
#                   result     index-test outcome (positive/negative)
#                 Accepted labels for each of reference/result (case-
#                 insensitive): 1/0, pos/neg, positive/negative, yes/no,
#                 true/false, +/-. Each column must use a single scheme and
#                 contain at most two distinct levels.
# --ci            interval method for the proportions:
#                   exact   Clopper-Pearson (default; guaranteed coverage)
#                   wilson  Wilson score (shorter, better mean coverage)
#                 LR+ / LR- always use the log (Katz/Simel) interval.
# --conf          two-sided confidence level in (0, 1); default 0.95
# --prevalence    population prevalence in (0, 1). PPV/NPV computed from the
#                 study's own row totals are only valid when the study
#                 prevalence equals the population's. Supplying --prevalence
#                 additionally reports Bayes-adjusted PPV/NPV at that
#                 prevalence, which is what a case-control / enriched design
#                 must report.
# --positive      override the label treated as "positive" in BOTH columns
#                 (e.g. --positive detected). Case-insensitive.
#
# Needs only base R — no external libraries required.
#
# Definitions, from the 2x2 with reference standard in columns:
#
#                      reference +      reference -
#     test +               TP               FP
#     test -               FN               TN
#
#   sensitivity = TP / (TP + FN)        specificity = TN / (TN + FP)
#   PPV         = TP / (TP + FP)        NPV         = TN / (TN + FN)
#   accuracy    = (TP + TN) / N
#   LR+         = sens / (1 - spec)     LR-         = (1 - sens) / spec
#
# Intervals:
#   Proportions       Clopper-Pearson exact (stats::binom.test) or Wilson
#                     score, per --ci.
#   LR+ / LR-         log interval (Katz 1978; Simel, Samsa & Matchar 1991):
#                       SE(log LR+) = sqrt((1-sens)/(sens*n1) + spec/((1-spec)*n0))
#                       SE(log LR-) = sqrt(sens/((1-sens)*n1) + (1-spec)/(spec*n0))
#                     with n1 = TP+FN reference-positive, n0 = TN+FP
#                     reference-negative. Undefined (n/a) when a rate is 0 or 1.
#   Bayes PPV/NPV     PPV = sens*p / (sens*p + (1-spec)*(1-p))
#                     NPV = spec*(1-p) / (spec*(1-p) + (1-sens)*p)
#                     Interval propagates the sens/spec interval bounds; both
#                     PPV and NPV are monotone increasing in sens and in spec.
#
# References:
#   FDA (2007), Statistical Guidance on Reporting Results from Studies
#   Evaluating Diagnostic Tests, CDRH. Reports sensitivity and specificity
#   with two-sided 95% CIs; cautions against PPV/NPV from non-representative
#   prevalence, and against reporting overall accuracy alone.
#   CLSI EP12-A2, User Protocol for Evaluation of Qualitative Test Performance.
#   Simel DL, Samsa GP, Matchar DB (1991), Likelihood ratios with confidence,
#   J Clin Epidemiol 44:763-770.
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

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Accepted binary label schemes, tried in order. Each: positive, negative.
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

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_dx_accuracy <data.csv> [--ci {exact|wilson}] [--conf C]",
  "                           [--prevalence P] [--positive LABEL]",
  "Example:",
  "  jrc_clinical_dx_accuracy dx_study.csv --ci exact --conf 0.95 --prevalence 0.02",
  sep = "\n"
)

csv_file <- NULL; ci_method <- "exact"; conf <- 0.95
prevalence <- NA; positive_label <- NULL

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0(flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--ci" && i < length(args)) {
    ci_method <- tolower(args[i + 1]); i <- i + 2
  } else if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--prevalence" && i < length(args)) {
    prevalence <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--positive" && i < length(args)) {
    positive_label <- tolower(trimws(args[i + 1])); i <- i + 2
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
if (!(ci_method %in% c("exact", "wilson"))) {
  stop("--ci must be 'exact' or 'wilson'.")
}
if (is.na(conf) || conf <= 0 || conf >= 1) {
  stop("--conf must be strictly between 0 and 1 (e.g. 0.95).")
}
if (!is.na(prevalence) && (prevalence <= 0 || prevalence >= 1)) {
  stop("--prevalence must be strictly between 0 and 1 (e.g. 0.02).")
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

required_cols <- c("id", "reference", "result")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, reference, result"))
}

dat$id        <- as.character(trimws(dat$id))
dat$reference <- tolower(as.character(trimws(dat$reference)))
dat$result    <- tolower(as.character(trimws(dat$result)))

# Drop rows with a missing value in any required column, and report how many.
is_blank  <- function(x) is.na(x) | x == "" | x == "na"
keep      <- !(is_blank(dat$id) | is_blank(dat$reference) | is_blank(dat$result))
n_dropped <- sum(!keep)
dat       <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) {
  stop("❌ No complete rows: every row has a missing id, reference or result.")
}
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}

# Map a column's labels onto 1 (positive) / 0 (negative).
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
    if (all(lv %in% c(s$pos, s$neg))) {
      return(as.integer(x == s$pos))
    }
  }
  stop(paste0("❌ Column '", colname, "' uses labels this script does not ",
              "recognise: ", paste(lv, collapse = ", "),
              "\n   Use 1/0, pos/neg, positive/negative, yes/no, true/false,",
              " +/-\n   or name the positive label with --positive."))
}

ref <- map_binary(dat$reference, "reference")
res <- map_binary(dat$result,    "result")

# ---------------------------------------------------------------------------
# 2x2 table
# ---------------------------------------------------------------------------

tp <- sum(res == 1 & ref == 1)
fp <- sum(res == 1 & ref == 0)
fn <- sum(res == 0 & ref == 1)
tn <- sum(res == 0 & ref == 0)

n_total <- tp + fp + fn + tn
n1      <- tp + fn          # reference positive
n0      <- tn + fp          # reference negative

if (n1 == 0) {
  stop("❌ No reference-positive subjects: sensitivity is undefined.")
}
if (n0 == 0) {
  stop("❌ No reference-negative subjects: specificity is undefined.")
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Two-sided CI for a binomial proportion x/n, by the selected method.
prop_ci <- function(x, n) {
  if (n == 0) return(c(NA_real_, NA_real_))
  if (ci_method == "exact") {
    as.numeric(binom.test(x, n, conf.level = conf)$conf.int)
  } else {
    z   <- qnorm(1 - (1 - conf) / 2)
    ph  <- x / n
    den <- 1 + z^2 / n
    ctr <- (ph + z^2 / (2 * n)) / den
    hw  <- z * sqrt(ph * (1 - ph) / n + z^2 / (4 * n^2)) / den
    c(max(0, ctr - hw), min(1, ctr + hw))
  }
}

fmt_ci <- function(est, ci) {
  if (is.na(est)) return("   n/a  (   n/a,    n/a)")
  if (any(is.na(ci))) return(sprintf("%.4f  (   n/a,    n/a)", est))
  sprintf("%.4f  (%.4f, %.4f)", est, ci[1], ci[2])
}

fmt_lr <- function(est, ci) {
  if (is.na(est) || !is.finite(est)) return("   Inf  (   n/a,    n/a)")
  if (any(is.na(ci))) return(sprintf("%.4f  (   n/a,    n/a)", est))
  sprintf("%.4f  (%.4f, %.4f)", est, ci[1], ci[2])
}

# ---------------------------------------------------------------------------
# Operating characteristics
# ---------------------------------------------------------------------------

sens <- tp / n1
spec <- tn / n0
acc  <- (tp + tn) / n_total

sens_ci <- prop_ci(tp, n1)
spec_ci <- prop_ci(tn, n0)
acc_ci  <- prop_ci(tp + tn, n_total)

# Study-prevalence PPV/NPV: valid only for a consecutive / representative
# cohort, where the study prevalence estimates the population prevalence.
ppv    <- if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
npv    <- if ((tn + fn) > 0) tn / (tn + fn) else NA_real_
ppv_ci <- if ((tp + fp) > 0) prop_ci(tp, tp + fp) else c(NA_real_, NA_real_)
npv_ci <- if ((tn + fn) > 0) prop_ci(tn, tn + fn) else c(NA_real_, NA_real_)

study_prev <- n1 / n_total

# Likelihood ratios, with the log (Simel) interval.
z <- qnorm(1 - (1 - conf) / 2)

lr_pos <- if (spec < 1) sens / (1 - spec) else Inf
lr_neg <- if (spec > 0) (1 - sens) / spec else Inf

lr_pos_ci <- c(NA_real_, NA_real_)
if (is.finite(lr_pos) && lr_pos > 0 && sens > 0 && spec < 1) {
  se_lp     <- sqrt((1 - sens) / (sens * n1) + spec / ((1 - spec) * n0))
  lr_pos_ci <- exp(log(lr_pos) + c(-1, 1) * z * se_lp)
}
lr_neg_ci <- c(NA_real_, NA_real_)
if (is.finite(lr_neg) && lr_neg > 0 && sens < 1 && spec > 0) {
  se_ln     <- sqrt(sens / ((1 - sens) * n1) + (1 - spec) / (spec * n0))
  lr_neg_ci <- exp(log(lr_neg) + c(-1, 1) * z * se_ln)
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------

ci_label <- c(exact = "Clopper-Pearson exact", wilson = "Wilson score")[ci_method]

message(" ")
message("✅ Diagnostic accuracy — binary test vs reference standard")
message("   version: 1.0, author: Joep Rous")
message("   ======================================================")
message(sprintf("   Data file      : %s", basename(csv_file)))
message(sprintf("   Subjects       : %d evaluable%s", n_total,
                if (n_dropped > 0)
                  sprintf("  (%d row(s) dropped: missing data)", n_dropped)
                else ""))
message(sprintf("   CI method      : %s, %g%% two-sided",
                ci_label, conf * 100))
message("   ------------------------------------------------------")
message("   2x2 table (reference standard in columns):")
message("                       ref +     ref -     total")
message(sprintf("      test +       %6d    %6d    %6d", tp, fp, tp + fp))
message(sprintf("      test -       %6d    %6d    %6d", fn, tn, fn + tn))
message(sprintf("      total        %6d    %6d    %6d", n1, n0, n_total))
message("   ------------------------------------------------------")
message("   Measure          estimate  (lower,  upper)")
message(sprintf("   Sensitivity    : %s   [%d/%d]", fmt_ci(sens, sens_ci), tp, n1))
message(sprintf("   Specificity    : %s   [%d/%d]", fmt_ci(spec, spec_ci), tn, n0))
message(sprintf("   Accuracy       : %s   [%d/%d]", fmt_ci(acc, acc_ci),
                tp + tn, n_total))
message(sprintf("   LR+            : %s", fmt_lr(lr_pos, lr_pos_ci)))
message(sprintf("   LR-            : %s", fmt_lr(lr_neg, lr_neg_ci)))
message("   ------------------------------------------------------")
message(sprintf("   PPV/NPV at the study prevalence (%.4f):", study_prev))
message(sprintf("   PPV            : %s   [%d/%d]", fmt_ci(ppv, ppv_ci),
                tp, tp + fp))
message(sprintf("   NPV            : %s   [%d/%d]", fmt_ci(npv, npv_ci),
                tn, tn + fn))

if (!is.na(prevalence)) {
  # Bayes-adjusted PPV/NPV at a fixed population prevalence. Both are monotone
  # increasing in sens and in spec, so propagating the (lower, lower) and
  # (upper, upper) sens/spec bounds gives the interval at that prevalence.
  bayes_ppv <- function(se, sp) se * prevalence /
    (se * prevalence + (1 - sp) * (1 - prevalence))
  bayes_npv <- function(se, sp) sp * (1 - prevalence) /
    (sp * (1 - prevalence) + (1 - se) * prevalence)

  ppv_adj    <- bayes_ppv(sens, spec)
  npv_adj    <- bayes_npv(sens, spec)
  ppv_adj_ci <- c(bayes_ppv(sens_ci[1], spec_ci[1]),
                  bayes_ppv(sens_ci[2], spec_ci[2]))
  npv_adj_ci <- c(bayes_npv(sens_ci[1], spec_ci[1]),
                  bayes_npv(sens_ci[2], spec_ci[2]))

  message("   ------------------------------------------------------")
  message(sprintf("   PPV/NPV Bayes-adjusted to prevalence %.4f:", prevalence))
  message(sprintf("   PPV (adj)      : %s", fmt_ci(ppv_adj, ppv_adj_ci)))
  message(sprintf("   NPV (adj)      : %s", fmt_ci(npv_adj, npv_adj_ci)))
  message("   The interval propagates the sens/spec bounds at a FIXED")
  message("   prevalence; it carries no uncertainty in the prevalence itself.")
}

message("   ------------------------------------------------------")
if (is.na(prevalence)) {
  message(sprintf("   NOTE: PPV/NPV above use the study prevalence (%.4f).",
                  study_prev))
  message("   They are valid ONLY if that reflects the intended-use")
  message("   population. For a case-control or enriched design, pass")
  message("   --prevalence P for Bayes-adjusted PPV/NPV.")
}
message(sprintf("   Method: 2x2 operating characteristics; %s", ci_label))
message("   intervals for proportions; LR+/LR- by the log (Simel 1991)")
message("   interval. Per FDA (2007), Statistical Guidance on Reporting")
message("   Results from Studies Evaluating Diagnostic Tests, report")
message("   sensitivity and specificity with CIs as the primary measures —")
message("   overall accuracy alone can mask poor performance in the")
message("   smaller reference group.")
message(" ")
