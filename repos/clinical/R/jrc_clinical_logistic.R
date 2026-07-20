#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_logistic.R <data.csv> --predictors p1,p2,...
#                 [--conf C] [--event LABEL]
#
# Logistic regression for a BINARY outcome. Reports the odds ratio for each
# predictor (with a confidence interval, z and p), the global likelihood-ratio
# test against the null model, the model's AIC, and the in-sample AUC of the
# fitted probabilities (how well the model separates the two outcomes).
#
# <data.csv>       CSV with columns: id, outcome, and one column per predictor
#                  named in --predictors.
#                    id       subject identifier (unique)
#                    outcome  the binary outcome. 1 = event, 0 = non-event;
#                             also accepts yes/no, true/false, event/nonevent,
#                             positive/negative, +/-.
#                    <predictors>  numeric (used as-is) or categorical
#                             (treated as a factor; first level = reference).
# --predictors p1,p2,...
#                  REQUIRED. Comma-separated predictor column names.
# --conf C         two-sided confidence level in (0, 1) for the OR CIs; default
#                  0.95.
# --event LABEL    the outcome level modelled as the event (= 1). Auto-detected
#                  from common schemes if omitted.
#
# Method: logistic regression via base R glm(family = binomial). Odds ratios
# are exp(coefficient) with Wald confidence intervals; the global test is the
# likelihood-ratio chi-square against the intercept-only model. The model AUC
# uses the same tie-aware Mann-Whitney kernel validated for jrc_clinical_dx_roc.
# No external packages.
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
  "  jrc_clinical_logistic <data.csv> --predictors p1,p2,... [--conf C]",
  "                        [--event LABEL]",
  "Example:",
  "  jrc_clinical_logistic trial.csv --predictors age,lwt,smoke --conf 0.95",
  sep = "\n"
)

csv_file <- NULL; predictors <- NULL; conf <- 0.95; event_label <- NULL

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0("❌ ", flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--predictors" && i < length(args)) {
    predictors <- tolower(trimws(strsplit(args[i + 1], ",")[[1]]))
    predictors <- predictors[predictors != ""]
    i <- i + 2
  } else if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--event" && i < length(args)) {
    event_label <- tolower(trimws(args[i + 1])); i <- i + 2
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
if (is.null(predictors) || length(predictors) == 0) {
  stop(paste("❌ --predictors is required (comma-separated column names).\n", usage))
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

required_cols <- c("id", "outcome", predictors)
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, outcome, and every --predictors column."))
}

dat$id      <- as.character(trimws(dat$id))
dat$outcome <- tolower(as.character(trimws(dat$outcome)))

is_blank <- function(x) is.na(x) | x == "" | tolower(as.character(x)) == "na"
keep <- !(is_blank(dat$id) | is_blank(dat$outcome))
for (pv in predictors) keep <- keep & !is_blank(dat[[pv]])
n_dropped <- sum(!keep)
dat <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) stop("❌ No complete rows after dropping missing values.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}

# Map outcome -> 0/1.
lv <- sort(unique(dat$outcome))
if (length(lv) != 2) {
  stop(paste0("❌ 'outcome' must have exactly two levels. Got: ",
              paste(lv, collapse = ", ")))
}
if (is.null(event_label)) {
  for (s in EVENT_SCHEMES) if (all(lv %in% c(s$pos, s$neg))) { event_label <- s$pos; break }
  if (is.null(event_label)) {
    stop(paste0("❌ Could not auto-detect the event level from: ",
                paste(lv, collapse = ", "), "\n   Name it with --event LABEL."))
  }
}
if (!(event_label %in% lv)) {
  stop(paste0("❌ --event '", event_label, "' is not an outcome level. Present: ",
              paste(lv, collapse = ", ")))
}
y <- as.integer(dat$outcome == event_label)
if (sum(y) < 2 || sum(y == 0) < 2) {
  stop("❌ Each outcome level needs at least 2 observations to fit a model.")
}

# Coerce predictors.
for (pv in predictors) {
  num <- suppressWarnings(as.numeric(dat[[pv]]))
  if (all(!is.na(num))) {
    dat[[pv]] <- num
  } else {
    dat[[pv]] <- factor(trimws(as.character(dat[[pv]])))
    if (nlevels(dat[[pv]]) < 2) stop(paste0("❌ Predictor '", pv, "' has one level."))
  }
}
dat$.y <- y

conf_pct <- conf * 100
z_crit   <- qnorm(1 - (1 - conf) / 2)

# ---------------------------------------------------------------------------
# Fit and report
# ---------------------------------------------------------------------------

form <- as.formula(paste(".y ~", paste(predictors, collapse = " + ")))
fit  <- tryCatch(glm(form, data = dat, family = binomial),
                 error = function(e) stop(paste("❌ Model failed to fit:", e$message)))

cat("Logistic regression for a binary outcome\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d   Events (%s): %d\n", nrow(dat), event_label, sum(y)))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
cat(sprintf("Predictors    : %s\n", paste(predictors, collapse = ", ")))
cat(sprintf("Confidence    : %g%%\n", conf_pct))
cat("\n")

cat("Odds ratios\n")
cat("──────────────────────────────────────────────\n")
co <- summary(fit)$coefficients
cat(sprintf("%-22s %8s %8s %8s %8s %10s\n", "term", "OR", "lower", "upper", "z", "p"))
for (r in rownames(co)) {
  est <- co[r, 1]; se <- co[r, 2]
  or  <- exp(est); lo <- exp(est - z_crit * se); hi <- exp(est + z_crit * se)
  cat(sprintf("%-22s %8.4f %8.4f %8.4f %8.4f %10.4g\n",
              r, or, lo, hi, co[r, 3], co[r, 4]))
}
cat("Odds ratio > 1 raises the odds of the event per unit of the predictor;\n")
cat("< 1 lowers them. The intercept is the baseline log-odds, not a predictor.\n")
cat("\n")

cat("Model fit\n")
cat("──────────────────────────────────────────────\n")
null_fit <- glm(.y ~ 1, data = dat, family = binomial)
lr_chisq <- null_fit$deviance - fit$deviance
lr_df    <- null_fit$df.residual - fit$df.residual
lr_p     <- pchisq(lr_chisq, lr_df, lower.tail = FALSE)
cat(sprintf("Likelihood-ratio test (vs null) : chisq = %.4f  df = %d  p = %.4g\n",
            lr_chisq, lr_df, lr_p))
cat(sprintf("AIC                             : %.2f\n", AIC(fit)))

# In-sample AUC via the tie-aware Mann-Whitney kernel (as in dx_roc).
pr <- predict(fit, type = "response")
x1 <- pr[y == 1]; x0 <- pr[y == 0]
mm <- length(x1); nn <- length(x0)
tz <- rank(c(x1, x0), ties.method = "average")
auc <- (sum(tz[1:mm]) - mm * (mm + 1) / 2) / (mm * nn)
cat(sprintf("Model AUC (in-sample)           : %.4f\n", auc))
cat("The in-sample AUC is optimistic — it is measured on the same data the\n")
cat("model was fitted to. Validate on an independent sample before claiming it.\n")
cat("\n")

cat("✅ Done.\n")
