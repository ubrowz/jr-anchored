#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_coxph.R <data.csv> --covariates c1,c2,...
#                 [--conf C] [--ties efron|breslow] [--event-positive LABEL]
#
# Cox proportional-hazards regression of right-censored time-to-event data.
# Reports the hazard ratio (with CI, z and p) for each covariate, the global
# likelihood-ratio and Wald tests, Harrell's concordance, and a test of the
# PROPORTIONAL-HAZARDS ASSUMPTION (scaled Schoenfeld residuals, cox.zph) per
# covariate and globally. Saves a Schoenfeld-residual diagnostic PNG to the
# output directory (~/Downloads by default).
#
# <data.csv>       CSV with columns: id, time, event, and one column per
#                  covariate named in --covariates.
#                    id     subject identifier (unique)
#                    time   observed time, > 0
#                    event  1 = event observed, 0 = right-censored.
#                           Also accepts yes/no, true/false, event/censored, +/-.
#                  A covariate column may be numeric (used as-is) or
#                  categorical (treated as a factor; the first level is the
#                  reference and each other level gets its own hazard ratio).
# --covariates c1,c2,...
#                  REQUIRED. Comma-separated covariate column names.
# --conf C         two-sided confidence level in (0, 1) for the HR CIs;
#                  default 0.95.
# --ties efron|breslow
#                  tie-handling for the partial likelihood. Default efron
#                  (more accurate); breslow is the simpler classical method.
# --event-positive LABEL
#                  override the label treated as "event = 1". Case-insensitive.
#
# Method: Cox (1972) partial-likelihood proportional-hazards model, fit with
# the validated `survival` package (Therneau). The PH assumption is tested by
# the scaled-Schoenfeld-residual method of Grambsch & Therneau (1994) via
# cox.zph. A significant result (small p) means the hazard ratio is NOT
# constant over time and the reported HR should not be interpreted as a single
# summary — stratify, add a time interaction, or report time-specific effects.
#
# Needs the pinned `survival` package. On R 4.6.0 you may see a benign
# "package 'survival' was built under R version 4.6.1" warning — see
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
  library(survival)
})

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EVENT_SCHEMES <- list(
  list(pos = "1",     neg = "0"),
  list(pos = "yes",   neg = "no"),
  list(pos = "y",     neg = "n"),
  list(pos = "true",  neg = "false"),
  list(pos = "t",     neg = "f"),
  list(pos = "event", neg = "censored"),
  list(pos = "+",     neg = "-")
)

BG     <- "#FFFFFF"
BANNER <- "#2E5BBA"
PH_ALPHA <- 0.05     # threshold below which a PH violation is flagged

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_coxph <data.csv> --covariates c1,c2,... [--conf C]",
  "                     [--ties efron|breslow] [--event-positive LABEL]",
  "Example:",
  "  jrc_clinical_coxph trial.csv --covariates age,arm --conf 0.95",
  sep = "\n"
)

csv_file <- NULL; covariates <- NULL; conf <- 0.95
ties <- "efron"; event_positive <- NULL

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
  } else if (a == "--ties" && i < length(args)) {
    ties <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--event-positive" && i < length(args)) {
    event_positive <- tolower(trimws(args[i + 1])); i <- i + 2
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
if (!(ties %in% c("efron", "breslow"))) stop("❌ --ties must be 'efron' or 'breslow'.")

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) stop(paste("❌ File not found:", csv_file))

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV:", e$message))
)
names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("id", "time", "event", covariates)
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, time, event, and every --covariates column."))
}

dat$id    <- as.character(trimws(dat$id))
dat$time  <- suppressWarnings(as.numeric(dat$time))
dat$event <- tolower(as.character(trimws(dat$event)))

is_blank <- function(x) is.na(x) | x == "" | tolower(x) == "na"
keep <- !(is_blank(dat$id) | is.na(dat$time) | is_blank(dat$event))
for (cv in covariates) keep <- keep & !is_blank(as.character(dat[[cv]]))
n_dropped <- sum(!keep)
dat <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) stop("❌ No complete rows after dropping missing values.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}
if (any(!is.finite(dat$time)) || any(dat$time <= 0)) {
  stop("❌ Column 'time' must be finite and strictly positive.")
}

map_event <- function(x) {
  lv <- sort(unique(x))
  if (length(lv) > 2) {
    stop(paste0("❌ Column 'event' must have at most 2 distinct values. Got: ",
                paste(lv, collapse = ", ")))
  }
  if (!is.null(event_positive)) {
    if (!(event_positive %in% lv)) {
      stop(paste0("❌ --event-positive '", event_positive, "' does not appear ",
                  "in the event column. Values present: ",
                  paste(lv, collapse = ", ")))
    }
    return(as.integer(x == event_positive))
  }
  for (s in EVENT_SCHEMES) {
    if (all(lv %in% c(s$pos, s$neg))) return(as.integer(x == s$pos))
  }
  stop(paste0("❌ Column 'event' uses labels this script does not recognise: ",
              paste(lv, collapse = ", "),
              "\n   Use 1/0, yes/no, true/false, event/censored, +/-",
              "\n   or name the event label with --event-positive."))
}
dat$event01 <- map_event(dat$event)

if (sum(dat$event01) < 2) {
  stop("❌ Fewer than 2 events observed: a Cox model cannot be fit reliably.")
}

# Coerce each covariate: numeric stays numeric; anything else becomes a factor.
for (cv in covariates) {
  col <- dat[[cv]]
  num <- suppressWarnings(as.numeric(col))
  if (all(!is.na(num))) {
    dat[[cv]] <- num
  } else {
    dat[[cv]] <- factor(trimws(as.character(col)))
    if (nlevels(dat[[cv]]) < 2) {
      stop(paste0("❌ Covariate '", cv, "' has only one distinct value; ",
                  "it carries no information."))
    }
  }
}

conf_pct <- conf * 100
z_crit   <- qnorm(1 - (1 - conf) / 2)

# ---------------------------------------------------------------------------
# Fit the Cox model
# ---------------------------------------------------------------------------

form <- as.formula(paste("Surv(time, event01) ~",
                         paste(covariates, collapse = " + ")))
fit <- tryCatch(
  coxph(form, data = dat, ties = ties),
  error = function(e) stop(paste("❌ Cox model failed to fit:", e$message))
)
sfit <- summary(fit, conf.int = conf)

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

cat("Cox proportional-hazards regression\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d   Events: %d\n", sfit$n, sfit$nevent))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
cat(sprintf("Covariates    : %s\n", paste(covariates, collapse = ", ")))
cat(sprintf("Ties          : %s\n", ties))
cat(sprintf("Confidence    : %g%%\n", conf_pct))
cat("\n")

cat("Hazard ratios\n")
cat("──────────────────────────────────────────────\n")
cm  <- sfit$coefficients          # coef, exp(coef), se(coef), z, Pr(>|z|)
ci  <- sfit$conf.int              # exp(coef), exp(-coef), lower, upper
terms_ <- rownames(cm)
cat(sprintf("%-22s %8s %8s %8s %10s\n", "term", "HR", "lower", "upper", "p"))
for (k in seq_along(terms_)) {
  cat(sprintf("%-22s %8.4f %8.4f %8.4f %10.4g\n",
              terms_[k], ci[k, "exp(coef)"], ci[k, 3], ci[k, 4],
              cm[k, "Pr(>|z|)"]))
}
cat("\n")

cat("Global tests\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Likelihood ratio : chisq = %.4f  df = %d  p = %.4g\n",
            sfit$logtest["test"], sfit$logtest["df"], sfit$logtest["pvalue"]))
cat(sprintf("Wald             : chisq = %.4f  df = %d  p = %.4g\n",
            sfit$waldtest["test"], sfit$waldtest["df"], sfit$waldtest["pvalue"]))
cat(sprintf("Concordance (C)  : %.4f  (SE %.4f)\n",
            sfit$concordance["C"], sfit$concordance["se(C)"]))
cat("\n")

# Proportional-hazards assumption.
zph <- cox.zph(fit)
cat("Proportional-hazards assumption (scaled Schoenfeld residuals)\n")
cat("──────────────────────────────────────────────\n")
zt <- zph$table
for (k in seq_len(nrow(zt))) {
  cat(sprintf("%-22s chisq = %8.4f  df = %g  p = %.4g\n",
              rownames(zt)[k], zt[k, "chisq"], zt[k, "df"], zt[k, "p"]))
}
global_p <- zt["GLOBAL", "p"]
cat("\n")
if (global_p < PH_ALPHA) {
  cat(sprintf("⚠️  PH assumption VIOLATED (global p = %.4g < %.2f): the hazard\n",
              global_p, PH_ALPHA))
  cat("   ratio is not constant over time. Do not report a single HR as the\n")
  cat("   whole story — stratify, add a time interaction, or report time-\n")
  cat("   specific effects.\n")
} else {
  cat(sprintf("✅ PH assumption OK (global p = %.4g ≥ %.2f): no evidence the\n",
              global_p, PH_ALPHA))
  cat("   hazard ratios change over time.\n")
}
cat("\n")

# ---------------------------------------------------------------------------
# Schoenfeld-residual diagnostic PNG
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_clinical_coxph.png"))
cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

n_panel <- nrow(zt) - 1                       # one per covariate term, excl GLOBAL
ncol_p  <- min(n_panel, 3)
nrow_p  <- ceiling(n_panel / ncol_p)

png(out_file, width = 2200, height = 500 + 500 * nrow_p, res = 180, bg = BG)
layout(matrix(c(rep(1, ncol_p),
                seq_len(nrow_p * ncol_p) + 1),
              nrow = nrow_p + 1, ncol = ncol_p, byrow = TRUE),
       heights = c(0.7, rep(2, nrow_p)))

# Banner.
par(mar = c(0, 0, 0, 0))
plot.new()
rect(0, 0, 1, 1, col = BANNER, border = NA)
text(0.5, 0.5,
     sprintf("Cox PH  |  %s  |  %d subjects, %d events  |  PH global p = %.4g%s",
             basename(csv_file), sfit$n, sfit$nevent, global_p,
             if (global_p < PH_ALPHA) "  (VIOLATED)" else ""),
     col = "white", font = 2, cex = 1.05)

# One scaled-Schoenfeld panel per covariate term.
par(mar = c(4.0, 4.2, 2.2, 1.0))
plot(zph)                                     # draws one panel per term, with LOESS

invisible(dev.off())

cat(sprintf("✅ Done. Open %s to view the Schoenfeld residual plots.\n",
            basename(out_file)))
jr_log_output_hashes(c(out_file))
