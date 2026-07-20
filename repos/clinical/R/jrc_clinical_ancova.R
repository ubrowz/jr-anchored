#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_ancova.R <data.csv> --covariates c1,c2,...
#                 [--conf C]
#
# ANCOVA — compare a continuous outcome across groups while ADJUSTING for one
# or more baseline covariates (the canonical "outcome adjusted for baseline"
# analysis; ICH E9 expects covariate adjustment for many trial endpoints).
# Reports the Type III joint tests (is the group effect significant after
# adjustment?), the adjusted least-squares means per group with confidence
# intervals, the pairwise group contrasts (Tukey-adjusted for multiplicity),
# and each covariate's effect.
#
# <data.csv>       CSV with columns: id, group, value, and one column per
#                  covariate named in --covariates.
#                    id     subject identifier (unique)
#                    group  the grouping factor of interest (2+ levels)
#                    value  the continuous outcome (numeric)
#                  A covariate may be numeric (used as-is) or categorical
#                  (treated as a factor).
# --covariates c1,c2,...
#                  REQUIRED. Comma-separated covariate column names to adjust
#                  for (e.g. --covariates baseline,age).
# --conf C         two-sided confidence level in (0, 1); default 0.95.
#
# Method: linear model (base R lm). Adjusted (least-squares) means, pairwise
# contrasts and Type III joint tests are computed with the validated `emmeans`
# package (Lenth) — emmeans::emmeans, emmeans::joint_tests, emmeans::pairs.
# Type III joint tests are the standard covariate-adjusted group test.
#
# Needs the pinned `emmeans` package. On R 4.6.0 you may see a benign
# "package '...' was built under R version 4.6.1" warning — see
# docs/TROUBLESHOOTING.md entry 15.
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
  library(emmeans)
})

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_ancova <data.csv> --covariates c1,c2,... [--conf C]",
  "Example:",
  "  jrc_clinical_ancova trial.csv --covariates baseline --conf 0.95",
  sep = "\n"
)

csv_file <- NULL; covariates <- NULL; conf <- 0.95

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0("❌ ", flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--covariates" && i < length(args)) {
    covariates <- tolower(trimws(strsplit(args[i + 1], ",")[[1]]))
    covariates <- covariates[covariates != ""]
    i <- i + 2
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
if (is.null(covariates) || length(covariates) == 0) {
  stop(paste("❌ --covariates is required (comma-separated column names).\n", usage))
}
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

required_cols <- c("id", "group", "value", covariates)
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, group, value, and every --covariates column."))
}

dat$id    <- as.character(trimws(dat$id))
dat$group <- as.character(trimws(dat$group))
dat$value <- suppressWarnings(as.numeric(dat$value))

is_blank <- function(x) is.na(x) | x == "" | tolower(as.character(x)) == "na"
keep <- !(is_blank(dat$id) | is_blank(dat$group) | is.na(dat$value))
for (cv in covariates) keep <- keep & !is_blank(dat[[cv]])
n_dropped <- sum(!keep)
dat <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) stop("❌ No complete rows after dropping missing values.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}
if (!all(is.finite(dat$value))) stop("❌ Column 'value' must be finite numeric.")

dat$group <- factor(dat$group)
if (nlevels(dat$group) < 2) stop("❌ 'group' must have at least two levels.")

# Coerce covariates: numeric stays numeric, else factor.
for (cv in covariates) {
  num <- suppressWarnings(as.numeric(dat[[cv]]))
  if (all(!is.na(num))) {
    dat[[cv]] <- num
  } else {
    dat[[cv]] <- factor(trimws(as.character(dat[[cv]])))
    if (nlevels(dat[[cv]]) < 2) {
      stop(paste0("❌ Covariate '", cv, "' has only one distinct value."))
    }
  }
}

conf_pct <- conf * 100

# ---------------------------------------------------------------------------
# Fit and report
# ---------------------------------------------------------------------------

form <- as.formula(paste("value ~ group +", paste(covariates, collapse = " + ")))
fit  <- tryCatch(lm(form, data = dat),
                 error = function(e) stop(paste("❌ Model failed to fit:", e$message)))

cat("ANCOVA — outcome by group, adjusted for covariates\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d   Groups: %d\n", nrow(dat), nlevels(dat$group)))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
cat(sprintf("Covariates    : %s\n", paste(covariates, collapse = ", ")))
cat(sprintf("Confidence    : %g%%\n", conf_pct))
cat("\n")

cat("Type III joint tests (emmeans::joint_tests)\n")
cat("──────────────────────────────────────────────\n")
jt <- as.data.frame(joint_tests(fit))
for (r in seq_len(nrow(jt))) {
  cat(sprintf("%-16s F = %8.4f   df = %g, %g   p = %.4g\n",
              trimws(jt$`model term`[r]), jt$F.ratio[r], jt$df1[r], jt$df2[r],
              jt$p.value[r]))
}
cat("The 'group' row is the covariate-adjusted test of whether the group means\n")
cat("differ; a small p means they do, after adjustment.\n")
cat("\n")

cat("Adjusted (least-squares) means by group\n")
cat("──────────────────────────────────────────────\n")
em  <- emmeans(fit, ~ group, level = conf)
ems <- as.data.frame(summary(em))
for (r in seq_len(nrow(ems))) {
  cat(sprintf("%-16s adj. mean = %8.4f  (SE %.4f;  %g%% CI %.4f, %.4f)\n",
              as.character(ems$group[r]), ems$emmean[r], ems$SE[r], conf_pct,
              ems$lower.CL[r], ems$upper.CL[r]))
}
cat("\n")

if (nlevels(dat$group) >= 2) {
  cat("Pairwise group contrasts (Tukey-adjusted)\n")
  cat("──────────────────────────────────────────────\n")
  pr <- as.data.frame(summary(pairs(em), infer = c(TRUE, TRUE)))
  lcl <- grep("lower", names(pr), value = TRUE)[1]
  ucl <- grep("upper", names(pr), value = TRUE)[1]
  for (r in seq_len(nrow(pr))) {
    cat(sprintf("%-20s diff = %+8.4f  (%g%% CI %+.4f, %+.4f)  p = %.4g\n",
                as.character(pr$contrast[r]), pr$estimate[r], conf_pct,
                pr[[lcl]][r], pr[[ucl]][r], pr$p.value[r]))
  }
  cat("\n")
}

cat("Covariate effects (per unit of the covariate)\n")
cat("──────────────────────────────────────────────\n")
co <- summary(fit)$coefficients
for (cv in covariates) {
  rn <- grep(paste0("^", cv), rownames(co), value = TRUE)
  for (r in rn) {
    cat(sprintf("%-20s coef = %+8.4f  (SE %.4f)  t = %.4f  p = %.4g\n",
                r, co[r, 1], co[r, 2], co[r, 3], co[r, 4]))
  }
}
cat("\n")

cat("✅ Done.\n")
