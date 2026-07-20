#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_compare_means.R <data.csv> [--test welch|student]
#                 [--conf C]
#
# Compare a continuous outcome between groups. For TWO groups: a two-sample
# t-test (Welch by default; Student with --test student), the mean difference
# with a confidence interval, a standardised effect size (Cohen's d and the
# small-sample-corrected Hedges' g), and the Mann-Whitney / Wilcoxon rank-sum
# test as a nonparametric alternative. For MORE than two groups: one-way ANOVA
# (F test) plus per-group summaries. A normality note (Shapiro-Wilk per group)
# flags when the rank test should be preferred over the t-test.
#
# <data.csv>       CSV with columns: id, group, value.
#                    id     subject identifier (unique)
#                    group  the grouping label (2 or more distinct values)
#                    value  the continuous outcome (numeric)
# --test           welch   Welch two-sample t-test (default; does NOT assume
#                          equal variances — the safer default)
#                  student Student's t-test (assumes equal variances)
#                  Applies to the two-group case only.
# --conf           two-sided confidence level in (0, 1); default 0.95.
#
# Method: Welch (1947) / Student (1908) two-sample t-test; Mann-Whitney (1947)
# / Wilcoxon (1945) rank-sum test; Cohen's d with Hedges' (1981) small-sample
# correction; one-way ANOVA F test. All from base R (stats): t.test,
# wilcox.test, lm/anova, shapiro.test. No external packages.
#
# Author: Joep Rous
# Version: 1.0

# ---------------------------------------------------------------------------
# Load from validated renv library (base R only, but keep the guard uniform)
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
# Argument parsing
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_compare_means <data.csv> [--test welch|student] [--conf C]",
  "Example:",
  "  jrc_clinical_compare_means trial.csv --test welch --conf 0.95",
  sep = "\n"
)

csv_file <- NULL; test <- "welch"; conf <- 0.95

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0("❌ ", flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--test" && i < length(args)) {
    test <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
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
if (!(test %in% c("welch", "student"))) stop("❌ --test must be 'welch' or 'student'.")
if (conf <= 0 || conf >= 1) stop("❌ --conf must be strictly between 0 and 1 (e.g. 0.95).")

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) stop(paste("❌ File not found:", csv_file))

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV:", e$message))
)
names(dat) <- tolower(trimws(names(dat)))

missing_cols <- setdiff(c("id", "group", "value"), names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, group, value"))
}

dat$id    <- as.character(trimws(dat$id))
dat$group <- as.character(trimws(dat$group))
dat$value <- suppressWarnings(as.numeric(dat$value))

is_blank <- function(x) is.na(x) | x == "" | tolower(x) == "na"
keep <- !(is_blank(dat$id) | is_blank(dat$group) | is.na(dat$value))
n_dropped <- sum(!keep)
dat <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) stop("❌ No complete rows after dropping missing values.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}
if (!all(is.finite(dat$value))) stop("❌ Column 'value' must be finite numeric.")

groups <- sort(unique(dat$group))
k <- length(groups)
if (k < 2) stop("❌ At least two groups are required in the 'group' column.")
for (g in groups) {
  if (sum(dat$group == g) < 2) {
    stop(paste0("❌ Group '", g, "' has fewer than 2 observations."))
  }
}

conf_pct <- conf * 100

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

cat("Comparison of a continuous outcome between groups\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d   Groups: %d\n", nrow(dat), k))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
cat(sprintf("Confidence    : %g%%\n", conf_pct))
cat("\n")

cat("Per-group summary\n")
cat("──────────────────────────────────────────────\n")
for (g in groups) {
  v <- dat$value[dat$group == g]
  sw <- if (length(v) >= 3 && length(v) <= 5000) shapiro.test(v)$p.value else NA_real_
  cat(sprintf("%-16s n = %-4d mean = %8.4f  sd = %8.4f%s\n",
              g, length(v), mean(v), sd(v),
              if (!is.na(sw)) sprintf("  (Shapiro p = %.3f)", sw) else ""))
}
cat("\n")

if (k == 2) {
  g1 <- dat$value[dat$group == groups[1]]
  g2 <- dat$value[dat$group == groups[2]]
  n1 <- length(g1); n2 <- length(g2)

  tt <- t.test(g1, g2, var.equal = (test == "student"), conf.level = conf)
  md <- mean(g1) - mean(g2)
  test_nm <- if (test == "student") "Student's t-test (equal variance)" else
                                    "Welch two-sample t-test (unequal variance)"

  cat(sprintf("%s\n", test_nm))
  cat("──────────────────────────────────────────────\n")
  cat(sprintf("Mean difference (%s - %s) : %+.4f  (%g%% CI %+.4f, %+.4f)\n",
              groups[1], groups[2], md, conf_pct,
              tt$conf.int[1], tt$conf.int[2]))
  cat(sprintf("t = %.4f   df = %.4f   p = %.4g\n",
              tt$statistic, tt$parameter, tt$p.value))
  cat("\n")

  # Effect size: Cohen's d (pooled sd) + Hedges' g correction.
  sp <- sqrt(((n1 - 1) * var(g1) + (n2 - 1) * var(g2)) / (n1 + n2 - 2))
  cohen_d <- md / sp
  J <- 1 - 3 / (4 * (n1 + n2) - 9)          # Hedges small-sample correction
  hedges_g <- cohen_d * J
  cat("Effect size\n")
  cat("──────────────────────────────────────────────\n")
  cat(sprintf("Cohen's d  : %+.4f   Hedges' g : %+.4f  (|0.2| small, |0.5| medium, |0.8| large)\n",
              cohen_d, hedges_g))
  cat("\n")

  mw <- suppressWarnings(wilcox.test(g1, g2, conf.int = FALSE))
  cat("Mann-Whitney / Wilcoxon rank-sum (nonparametric)\n")
  cat("──────────────────────────────────────────────\n")
  cat(sprintf("W = %.1f   p = %.4g\n", mw$statistic, mw$p.value))
  cat("Prefer this test over the t-test when a group's Shapiro p is small\n")
  cat("(non-normal) or the sample is small.\n")
  cat("\n")
} else {
  fit <- lm(value ~ group, data = dat)
  av  <- anova(fit)
  cat(sprintf("One-way ANOVA (%d groups)\n", k))
  cat("──────────────────────────────────────────────\n")
  cat(sprintf("F = %.4f   df = %d, %d   p = %.4g\n",
              av$`F value`[1], av$Df[1], av$Df[2], av$`Pr(>F)`[1]))
  cat("A significant F says the group means are not all equal; it does NOT say\n")
  cat("which pairs differ. Follow up with pairwise comparisons using a\n")
  cat("multiplicity correction (e.g. Tukey), or jrc_clinical_ancova to adjust\n")
  cat("for covariates.\n")
  cat("\n")
}

cat("✅ Done.\n")
