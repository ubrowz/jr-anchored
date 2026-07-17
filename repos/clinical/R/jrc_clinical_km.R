#!/usr/bin/env Rscript
#
# use as: Rscript jrc_clinical_km.R <data.csv> [--group COL] [--time-point T]
#                 [--conf C] [--rho RHO] [--event-positive LABEL]
#
# Kaplan-Meier analysis of right-censored time-to-event data. Reports the
# product-limit survival estimate: number at risk / events, median survival
# with a confidence interval, and the survival probability S(t) at a requested
# time. When a grouping column is given, per-group curves plus the log-rank
# test comparing them. Saves a two-panel PNG (survival curves + number-at-risk
# table) to the output directory (~/Downloads by default).
#
# <data.csv>       CSV with columns: id, time, event (and optionally a group
#                  column named by --group).
#                    id     subject identifier (unique)
#                    time   observed time, > 0 (event time, or censoring time
#                           for a subject who did not have the event)
#                    event  1 = event observed, 0 = right-censored.
#                           Also accepts yes/no, true/false, event/censored, +/-.
# --group COL      name of a column defining groups to compare. When present,
#                  per-group KM curves are reported and the LOG-RANK TEST is
#                  computed. Any number of groups is allowed.
# --time-point T   report S(T) — the estimated survival probability at time T —
#                  with its confidence interval, per group when grouped.
# --conf C         two-sided confidence level in (0, 1); default 0.95. Applies
#                  to the median CI, S(t) CI, and the curve confidence bands.
# --rho RHO        log-rank weighting (survdiff rho): 0 = standard log-rank
#                  (default), 1 = Peto-Peto / Gehan-Wilcoxon (weights early
#                  events more). Only used when --group is given.
# --event-positive LABEL
#                  override the label treated as "event = 1", e.g.
#                  --event-positive death. Case-insensitive.
#
# Method: product-limit estimator (Kaplan & Meier 1958) with Greenwood-variance
# pointwise CIs; median read from the survival curve; log-rank test (Mantel
# 1966; rho-family, Harrington & Fleming 1982). Computed with the validated
# `survival` package (Therneau).
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
  list(pos = "1",        neg = "0"),
  list(pos = "yes",      neg = "no"),
  list(pos = "y",        neg = "n"),
  list(pos = "true",     neg = "false"),
  list(pos = "t",        neg = "f"),
  list(pos = "event",    neg = "censored"),
  list(pos = "+",        neg = "-")
)

BG        <- "#FFFFFF"
BANNER    <- "#2E5BBA"
GROUP_COL <- c("#2E5BBA", "#ED7D31", "#5DAD5D", "#B5497E",
               "#8064A2", "#4BACC6", "#9BBB59", "#C0504D")

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

usage <- paste(
  "Usage:",
  "  jrc_clinical_km <data.csv> [--group COL] [--time-point T] [--conf C]",
  "                  [--rho RHO] [--event-positive LABEL]",
  "Example:",
  "  jrc_clinical_km trial.csv --group arm --time-point 12 --conf 0.95",
  sep = "\n"
)

csv_file <- NULL; group_col <- NULL; time_point <- NA
conf <- 0.95; rho <- 0; event_positive <- NULL

num_flag <- function(raw, flag) {
  v <- suppressWarnings(as.numeric(raw))
  if (is.na(v)) stop(paste0("❌ ", flag, " must be a number. Got: ", raw))
  v
}

i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--group" && i < length(args)) {
    group_col <- tolower(trimws(args[i + 1])); i <- i + 2
  } else if (a == "--time-point" && i < length(args)) {
    time_point <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--conf" && i < length(args)) {
    conf <- num_flag(args[i + 1], a); i <- i + 2
  } else if (a == "--rho" && i < length(args)) {
    rho <- num_flag(args[i + 1], a); i <- i + 2
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
if (conf <= 0 || conf >= 1) stop("❌ --conf must be strictly between 0 and 1 (e.g. 0.95).")
if (!is.na(time_point) && time_point <= 0) stop("❌ --time-point must be > 0.")

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) stop(paste("❌ File not found:", csv_file))

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV:", e$message))
)
names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("id", "time", "event")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("❌ Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: id, time, event"))
}
if (!is.null(group_col) && !(group_col %in% names(dat))) {
  stop(paste0("❌ --group column '", group_col, "' not found. Columns present: ",
              paste(names(dat), collapse = ", ")))
}

dat$id    <- as.character(trimws(dat$id))
dat$time  <- suppressWarnings(as.numeric(dat$time))
dat$event <- tolower(as.character(trimws(dat$event)))

is_blank  <- function(x) is.na(x) | x == "" | x == "na"
keep      <- !(is_blank(dat$id) | is.na(dat$time) | is_blank(dat$event))
if (!is.null(group_col)) keep <- keep & !is_blank(tolower(trimws(dat[[group_col]])))
n_dropped <- sum(!keep)
dat       <- dat[keep, , drop = FALSE]

if (nrow(dat) == 0) stop("❌ No complete rows after dropping missing values.")
if (anyDuplicated(dat$id) > 0) {
  dups <- unique(dat$id[duplicated(dat$id)])
  stop(paste("❌ Duplicate id(s) found:", paste(head(dups, 5), collapse = ", "),
             "\n   Each subject must appear exactly once."))
}
if (any(!is.finite(dat$time)) || any(dat$time <= 0)) {
  stop("❌ Column 'time' must be finite and strictly positive.")
}

# Map the event column to 0/1.
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

if (sum(dat$event01) == 0) {
  stop("❌ No events observed (all rows censored): survival cannot be estimated.")
}

grouped <- !is.null(group_col)
if (grouped) {
  dat$grp <- as.character(trimws(dat[[group_col]]))
  if (length(unique(dat$grp)) < 2) {
    stop(paste0("❌ --group '", group_col, "' has only one distinct value; ",
                "at least two groups are needed to compare."))
  }
}

conf_pct <- conf * 100

# ---------------------------------------------------------------------------
# Fit Kaplan-Meier
# ---------------------------------------------------------------------------

if (grouped) {
  fit <- survfit(Surv(time, event01) ~ grp, data = dat, conf.int = conf)
} else {
  fit <- survfit(Surv(time, event01) ~ 1, data = dat, conf.int = conf)
}

# survfit's summary table: records, events, median, lower/upper CL.
tbl <- summary(fit)$table
if (is.null(dim(tbl))) tbl <- t(as.matrix(tbl))   # single-group -> vector
lcl_name <- grep("LCL$", colnames(tbl), value = TRUE)[1]
ucl_name <- grep("UCL$", colnames(tbl), value = TRUE)[1]

group_labels <- if (grouped) sub("^grp=", "", rownames(tbl)) else "Overall"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

fmt <- function(x) if (is.na(x)) "  NA  " else sprintf("%.4g", x)

cat("Kaplan-Meier survival analysis\n")
cat("──────────────────────────────────────────────\n")
cat(sprintf("Data          : %s\n", basename(csv_file)))
cat(sprintf("Subjects      : %d   Events: %d   Censored: %d\n",
            nrow(dat), sum(dat$event01), sum(dat$event01 == 0)))
if (n_dropped > 0) cat(sprintf("Dropped rows  : %d (missing values)\n", n_dropped))
if (grouped) cat(sprintf("Group column  : %s (%d groups)\n",
                         group_col, length(group_labels)))
cat(sprintf("Confidence    : %g%%\n", conf_pct))
cat("\n")

cat("Survival summary\n")
cat("──────────────────────────────────────────────\n")
for (g in seq_len(nrow(tbl))) {
  med <- tbl[g, "median"]
  lcl <- tbl[g, lcl_name]
  ucl <- tbl[g, ucl_name]
  cat(sprintf("%-16s n = %-4d events = %-4d\n",
              group_labels[g], tbl[g, "records"], tbl[g, "events"]))
  cat(sprintf("%-16s Median survival : %s  (%g%% CI %s, %s)\n",
              "", fmt(med), conf_pct, fmt(lcl), fmt(ucl)))
}
cat("\n")

# S(t) at the requested time point.
if (!is.na(time_point)) {
  st <- summary(fit, times = time_point, extend = TRUE)
  cat(sprintf("Survival at t = %g\n", time_point))
  cat("──────────────────────────────────────────────\n")
  st_groups <- if (grouped) sub("^grp=", "", as.character(st$strata)) else "Overall"
  for (k in seq_along(st$surv)) {
    cat(sprintf("%-16s S(%g) = %.4f  (%g%% CI %.4f, %.4f)\n",
                st_groups[k], time_point, st$surv[k], conf_pct,
                st$lower[k], st$upper[k]))
  }
  cat("\n")
}

# Log-rank test.
logrank <- NULL
if (grouped) {
  logrank <- survdiff(Surv(time, event01) ~ grp, data = dat, rho = rho)
  df      <- length(logrank$n) - 1
  p_val   <- pchisq(logrank$chisq, df, lower.tail = FALSE)
  test_nm <- if (rho == 0) "Log-rank" else sprintf("Rho=%g weighted (Peto/G-W)", rho)
  cat(sprintf("%s test (H0: survival identical across groups)\n", test_nm))
  cat("──────────────────────────────────────────────\n")
  cat(sprintf("Chi-square = %.4f   df = %d   p = %.4g\n",
              logrank$chisq, df, p_val))
  obs <- logrank$obs; exp_ <- logrank$exp
  for (g in seq_along(group_labels)) {
    cat(sprintf("%-16s observed = %-4g expected = %.2f\n",
                group_labels[g], obs[g], exp_[g]))
  }
  cat("\n")
}

# ---------------------------------------------------------------------------
# Two-panel PNG: survival curves + number-at-risk table
# ---------------------------------------------------------------------------

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(jr_out_dir(),
                      paste0(datetime_pfx, "_jrc_clinical_km.png"))
cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

# Risk-table time grid: a handful of evenly spaced points across the range.
t_max  <- max(dat$time)
grid_t <- pretty(c(0, t_max), n = 6)
grid_t <- grid_t[grid_t >= 0 & grid_t <= t_max]

n_grp   <- length(group_labels)
cols    <- GROUP_COL[((seq_len(n_grp) - 1) %% length(GROUP_COL)) + 1]

png(out_file, width = 2200, height = 1300, res = 180, bg = BG)
layout(matrix(c(1, 2, 3), nrow = 3, ncol = 1), heights = c(0.12, 0.62, 0.26))

# Banner.
par(mar = c(0, 0, 0, 0))
plot.new()
rect(0, 0, 1, 1, col = BANNER, border = NA)
banner_txt <- if (grouped && !is.null(logrank)) {
  sprintf("Kaplan-Meier  |  %s  |  %d subjects, %d events  |  log-rank p = %.4g",
          basename(csv_file), nrow(dat), sum(dat$event01),
          pchisq(logrank$chisq, length(logrank$n) - 1, lower.tail = FALSE))
} else {
  sprintf("Kaplan-Meier  |  %s  |  %d subjects, %d events",
          basename(csv_file), nrow(dat), sum(dat$event01))
}
text(0.5, 0.5, banner_txt, col = "white", font = 2, cex = 1.05)

# Survival curves.
par(mar = c(4.2, 4.5, 1.0, 1.0))
plot(fit, col = cols, lwd = 2.2, conf.int = TRUE,
     xlab = "Time", ylab = "Survival probability S(t)",
     xlim = c(0, t_max), ylim = c(0, 1), mark.time = TRUE)
grid(col = "#EEEEEE")
if (grouped) {
  legend("topright", legend = group_labels, col = cols, lwd = 2.2,
         bty = "n", cex = 0.95)
}
if (!is.na(time_point)) abline(v = time_point, col = "#999999", lty = 2)

# Number-at-risk table.
par(mar = c(2.0, 8.5, 1.2, 1.0))
plot.new()
plot.window(xlim = c(0, t_max), ylim = c(0, n_grp + 0.5))
title(main = "Number at risk", adj = 0, cex.main = 0.95, font.main = 2, line = 0.2)
axis(1, at = grid_t)
risk_summary <- summary(fit, times = grid_t, extend = TRUE)
risk_groups  <- if (grouped) sub("^grp=", "", as.character(risk_summary$strata)) else rep("Overall", length(risk_summary$time))
for (g in seq_len(n_grp)) {
  y <- n_grp - g + 1
  sel <- risk_groups == group_labels[g]
  gt  <- risk_summary$time[sel]; nr <- risk_summary$n.risk[sel]
  text(-0.02 * t_max, y, group_labels[g], adj = 1, xpd = TRUE,
       col = cols[g], font = 2, cex = 0.9)
  for (k in seq_along(gt)) text(gt[k], y, nr[k], cex = 0.9)
}

invisible(dev.off())

cat(sprintf("✅ Done. Open %s to view the survival curves.\n", basename(out_file)))
jr_log_output_hashes(c(out_file))
