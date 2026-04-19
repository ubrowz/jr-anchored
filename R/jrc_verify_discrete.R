#!/usr/bin/env Rscript
#
# jrc_verify_discrete.R
#
# Discrete (pass/fail) verification assessment using the exact Clopper-Pearson
# one-sided binomial confidence interval.
#
# Given N units tested, f failures observed, and a pre-specified requirement
# (proportion P at confidence C), computes the upper one-sided CI bound on
# the true failure rate and reports PASS/FAIL with margin.
#
# Author: Joep Rous
# Version: 1.0

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"),
                      r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_verify_discrete.R <N> <f> <proportion> <confidence>",
    "Example:",
    "  Rscript jrc_verify_discrete.R 125 2 0.95 0.95",
    sep = "\n"
  ))
}

N_val      <- suppressWarnings(as.integer(args[1]))
f_val      <- suppressWarnings(as.integer(args[2]))
proportion <- suppressWarnings(as.double(args[3]))
confidence <- suppressWarnings(as.double(args[4]))

if (is.na(N_val) || N_val <= 0) {
  stop(paste("'N' must be a positive integer. Got:", args[1]))
}
if (is.na(f_val) || f_val < 0) {
  stop(paste("'f' must be a non-negative integer. Got:", args[2]))
}
if (f_val > N_val) {
  stop(paste0("'f' (failures) cannot exceed 'N' (units tested). Got f = ",
              f_val, ", N = ", N_val))
}
if (f_val == N_val) {
  stop(paste0("All ", N_val, " units failed. Cannot compute a meaningful confidence ",
              "bound — review your test data."))
}
if (is.na(proportion) || proportion <= 0 || proportion >= 1) {
  stop(paste("'proportion' must be strictly between 0 and 1. Got:", args[3]))
}
if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be strictly between 0 and 1. Got:", args[4]))
}

# ---------------------------------------------------------------------------
# Clopper-Pearson upper one-sided CI on the failure rate
# Upper bound: qbeta(C, f+1, N-f)
# ---------------------------------------------------------------------------

allowable_failure_rate <- 1 - proportion
upper_bound            <- qbeta(confidence, f_val + 1, N_val - f_val)
observed_failure_rate  <- f_val / N_val
margin                 <- allowable_failure_rate - upper_bound
passed                 <- upper_bound < allowable_failure_rate

pct <- function(x) sprintf("%.2f%%", x * 100)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

message(" ")
message("=================================================================")
message("  Discrete Verification \u2014 Pass/Fail Assessment")
message("=================================================================")
message(" ")
message(sprintf("  units tested (N):              %d", N_val))
message(sprintf("  failures observed (f):         %d", f_val))
message(sprintf("  required proportion (P):       %.4g", proportion))
message(sprintf("  confidence level (C):          %.4g", confidence))
message(" ")
message(sprintf("  Observed failure rate:         %s  (%d/%d)",
                pct(observed_failure_rate), f_val, N_val))
message(sprintf("  Upper %s CI bound:         %s",
                pct(confidence), pct(upper_bound)))
message(sprintf("  Allowable failure rate:        %s  (= 1 \u2212 P)",
                pct(allowable_failure_rate)))
message(sprintf("  Margin:                        %.4g percentage points",
                margin * 100))
message(" ")

if (passed) {
  message("\u2705 VERIFICATION PASSED")
  message(sprintf("   Upper confidence bound (%s) is within the", pct(upper_bound)))
  message(sprintf("   allowable failure rate (%s).", pct(allowable_failure_rate)))
} else {
  message("\u274c VERIFICATION FAILED")
  message(sprintf("   Upper confidence bound (%s) exceeds the", pct(upper_bound)))
  message(sprintf("   allowable failure rate (%s).", pct(allowable_failure_rate)))
  message("   Consider increasing sample size or investigating")
  message("   the root cause of failures.")
}

if (f_val == 0) {
  message(" ")
  message("   \u2139\ufe0f  Note: f = 0 (zero failures observed).")
  message("   For zero-failure studies, jrc_ss_discrete_ci is the canonical tool.")
  message("   It reports the proportion achieved given N and f = 0.")
}

message(" ")
