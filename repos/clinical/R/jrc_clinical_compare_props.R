#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_compare_props.R <data.csv> [--event LABEL]
#                 [--reference GROUP] [--conf C] [--no-correction]
#
# Compare a categorical outcome between groups. For a 2x2 table (two groups,
# two outcomes): the chi-square test (Yates-corrected by default) and Fisher's
# exact test, plus the three effect measures a clinician wants — risk
# difference, risk ratio, and odds ratio — each with a confidence interval.
# For a larger R x C table: the chi-square test of association and Fisher's
# exact test (the 2x2 effect measures are undefined and are omitted).
#
# <data.csv>       CSV with columns: id, group, outcome.
#                    id       subject identifier (unique)
#                    group    the grouping label (2 or more distinct values)
#                    outcome  the categorical outcome (2 or more distinct values)
# --event LABEL    the outcome level counted as the "event" (numerator of the
#                  risks). If omitted, common schemes are auto-detected
#                  (1/0, yes/no, event/nonevent, positive/negative, true/false,
#                  +/-); the positive label becomes the event.
# --reference GROUP
#                  the group used as the reference (denominator) in the risk
#                  ratio and odds ratio. The other group is the index
#                  (numerator). Default: the alphabetically first group.
# --conf C         two-sided confidence level in (0, 1); default 0.95.
# --no-correction  use the uncorrected (no Yates continuity correction)
#                  chi-square. Default applies the Yates correction, matching
#                  R's chisq.test default for a 2x2 table.
#
# Method: Pearson chi-square (Yates 1934 continuity correction) and Fisher's
# exact test; risk difference (Wald interval), risk ratio and odds ratio (Woolf
# log intervals). All from base R (stats): chisq.test, fisher.test. No external
# packages.
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

EVENT_SCHEMES <- list(
  list(pos = "1",        neg = "0"),
  list(pos = "yes",      neg = "no"),
  list(pos = "y",        neg = "n"),
  list(pos = "event",    neg = "nonevent"),
  list(pos = "positive", neg = "negative"),
  list(pos = "pos",      neg = "neg"),
  list(pos = "true",     neg = "false"),
  list(pos = "+",        neg = "-")
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_compare_props <data.csv> [--event LABEL] [--reference GROUP]",
  "                             [--conf C] [--no-correction]",
  "Example:",
  "  jrc_clinical_compare_props trial.csv --event yes --reference control",
  sep = "\n"
)

csv_file <- NULL; event_label <- NULL; ref_group <- NULL
conf <- 0.95; correction <- TRUE

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0("❌ ", flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--event" && i < length(args)) {
    event_label <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--reference" && i < length(args)) {
    ref_group <- trimws(args[i + 1]); i <- i + 2
  } else if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--no-correction") {
    correction <- FALSE; i <- i + 1
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

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) stop(paste("❌ File not found:", csv_file))

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV:", e$message))
)
names(dat) <- tolower(trimws(names(dat)))

missing_cols <- setdiff(c("id", "group", "outcome"), names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, group, outcome"))
}

dat$id      <- as.character(trimws(dat$id))
dat$group   <- as.character(trimws(dat$group))
dat$outcome <- tolower(as.character(trimws(dat$outcome)))

is_blank <- function(x) is.na(x) | x == "" | x == "na"
keep <- !(is_blank(dat$id) | is_blank(dat$group) | is_blank(dat$outcome))
n_dropped <- sum(!keep)
dat <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) stop("❌ No complete rows after dropping missing values.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}

groups   <- sort(unique(dat$group))
outcomes <- sort(unique(dat$outcome))
if (length(groups) < 2)   stop("❌ At least two groups are required in 'group'.")
if (length(outcomes) < 2) stop("❌ At least two outcome levels are required in 'outcome'.")

conf_pct <- conf * 100
z_crit   <- qnorm(1 - (1 - conf) / 2)

# Contingency table: rows = group, cols = outcome.
tab <- table(group = dat$group, outcome = dat$outcome)

cat("Comparison of a categorical outcome between groups\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d   Groups: %d   Outcomes: %d\n",
            nrow(dat), length(groups), length(outcomes)))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
cat(sprintf("Confidence    : %g%%\n", conf_pct))
cat("\n")

cat("Contingency table (group x outcome)\n")
cat("──────────────────────────────────────────────\n")
print(tab)
cat("\n")

# Tests of association (valid for any R x C).
ch <- suppressWarnings(chisq.test(tab, correct = correction))
cat("Tests of association\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Chi-square%s : X2 = %.4f   df = %d   p = %.4g\n",
            if (correction && all(dim(tab) == 2)) " (Yates)" else "        ",
            ch$statistic, ch$parameter, ch$p.value))
fi <- fisher.test(tab)
cat(sprintf("Fisher's exact test              p = %.4g\n", fi$p.value))
if (any(ch$expected < 5)) {
  cat("⚠️  Some expected cell counts are below 5 — prefer Fisher's exact test\n")
  cat("   over the chi-square approximation here.\n")
}
cat("\n")

# 2x2 effect measures.
if (length(groups) == 2 && length(outcomes) == 2) {
  # event level
  if (is.null(event_label)) {
    ev <- NULL
    for (s in EVENT_SCHEMES) {
      if (all(outcomes %in% c(s$pos, s$neg))) { ev <- s$pos; break }
    }
    if (is.null(ev)) {
      stop(paste0("❌ Could not auto-detect the event outcome from levels: ",
                  paste(outcomes, collapse = ", "),
                  "\n   Name it with --event LABEL."))
    }
    event_label <- ev
  }
  if (!(event_label %in% outcomes)) {
    stop(paste0("❌ --event '", event_label, "' is not an outcome level. Present: ",
                paste(outcomes, collapse = ", ")))
  }
  # reference / index group
  if (is.null(ref_group)) ref_group <- groups[1]
  if (!(ref_group %in% groups)) {
    stop(paste0("❌ --reference '", ref_group, "' is not a group. Present: ",
                paste(groups, collapse = ", ")))
  }
  index_group <- setdiff(groups, ref_group)[1]

  ev_col <- event_label
  a <- tab[index_group, ev_col]; b <- sum(tab[index_group, ]) - a
  c <- tab[ref_group,   ev_col]; d <- sum(tab[ref_group,   ]) - c

  p_i <- a / (a + b); p_r <- c / (c + d)
  rd  <- p_i - p_r
  rr  <- p_i / p_r
  or  <- (a * d) / (b * c)

  se_rd  <- sqrt(p_i * (1 - p_i) / (a + b) + p_r * (1 - p_r) / (c + d))
  rd_ci  <- rd + c(-1, 1) * z_crit * se_rd
  se_lrr <- sqrt(1/a - 1/(a + b) + 1/c - 1/(c + d))
  rr_ci  <- exp(log(rr) + c(-1, 1) * z_crit * se_lrr)
  se_lor <- sqrt(1/a + 1/b + 1/c + 1/d)
  or_ci  <- exp(log(or) + c(-1, 1) * z_crit * se_lor)

  cat(sprintf("Effect measures — event = '%s',  %s (index) vs %s (reference)\n",
              event_label, index_group, ref_group))
  cat("──────────────────────────────────────────────\n")
  cat(sprintf("Risk (%s)   : %.4f   Risk (%s) : %.4f\n",
              index_group, p_i, ref_group, p_r))
  cat(sprintf("Risk difference : %+.4f  (%g%% CI %+.4f, %+.4f)\n",
              rd, conf_pct, rd_ci[1], rd_ci[2]))
  cat(sprintf("Risk ratio      : %.4f  (%g%% CI %.4f, %.4f)\n",
              rr, conf_pct, rr_ci[1], rr_ci[2]))
  cat(sprintf("Odds ratio      : %.4f  (%g%% CI %.4f, %.4f)\n",
              or, conf_pct, or_ci[1], or_ci[2]))
  cat("\n")
} else {
  cat("Effect measures (risk difference / ratio, odds ratio) are only defined\n")
  cat("for a 2x2 table; with more than two groups or outcomes only the tests of\n")
  cat("association above are reported.\n\n")
}

cat("✅ Done.\n")
