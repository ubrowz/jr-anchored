#!/usr/bin/env Rscript
#
# use as: Rscript jrc_verify_attr.R <proportion> <confidence> <file_path> <column_name> <spec1> <spec2>
#
# "proportion"  is the minimum fraction of the population that must be within
#               the tolerance interval (e.g. 0.95)
# "confidence"  is the confidence level for that claim (e.g. 0.95)
# "file_path"   should point to a csv file with column names as the first row
# "column_name" should be one of the column names in the csv file
#               (NOT the name of the first column, which is used for row names)
# "spec1"       lower spec limit, or "-" if not applicable
# "spec2"       upper spec limit, or "-" if not applicable
#
# At least one of spec1 / spec2 must be numeric. Pass "-" for the one that
# does not apply:
#   1-sided lower:  spec1 = <value>  spec2 = -
#   1-sided upper:  spec1 = -        spec2 = <value>
#   2-sided:        spec1 = <value>  spec2 = <value>  (spec2 must be > spec1)
#
# IMPORTANT! The CSV file must have at least 2 columns: the first column is
# used for row names, the remaining columns contain data.
#
# Needs the <stats>, <tolerance>, <MASS>, <e1071>, and <ggplot2> libraries.
#
# Calculates the statistical tolerance interval for the verification dataset
# and compares it against the spec limits. Non-normal data are handled via
# Box-Cox transformation. Results are reported in original units.
#
# Saves a histogram PNG to the same directory as the input CSV, showing:
#   - Data histogram with fitted normal density curve (original scale)
#   - Tolerance interval limits (blue dashed lines)
#   - Spec limit(s) (red dashed lines)
#   - Green/red shading between TI and spec to indicate pass/fail
#
# Use after jrc_ss_attr or jrc_ss_attr_check to confirm the verification
# result and produce a plot for the test report.
#
# Author: Joep Rous
# Version: 2.0
# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", "macos", r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

suppressPackageStartupMessages({
  library(tolerance)
  library(stats)
  library(MASS)    # For boxcox()
  library(e1071)   # For skewness()
  library(ggplot2) # For histogram plot
})

# Format a number to a fixed number of significant figures for output
fmt <- function(x, digits = 4) signif(x, digits)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Significance level for Box-Cox acceptance test (Shapiro-Wilk).
# 0.01 is stricter than default 0.05: Box-Cox is only accepted when the
# transformed data clearly passes normality. Must match jrc_ss_attr.
BOXCOX_ALPHA <- 0.01

# Lambda threshold below which Box-Cox collapses to a log transformation.
# Must be identical everywhere lambda is evaluated.
LAMBDA_EPS <- 1e-6

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 6) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_verify_attr.R <proportion> <confidence> <file_path> <column_name> <spec1> <spec2>",
    "Example (1-sided lower):",
    "  Rscript jrc_verify_attr.R 0.95 0.95 mydata.csv ForceN 10.0 -",
    "Example (1-sided upper):",
    "  Rscript jrc_verify_attr.R 0.95 0.95 mydata.csv ForceN - 10.0",
    "Example (2-sided):",
    "  Rscript jrc_verify_attr.R 0.95 0.95 mydata.csv ForceN 8.0 12.0",
    sep = "\n"
  ))
}

proportion <- suppressWarnings(as.double(args[1]))
confidence <- suppressWarnings(as.double(args[2]))
file_path  <- args[3]
input_col  <- args[4]
col        <- make.names(input_col)

if (is.na(proportion) || proportion <= 0 || proportion >= 1) {
  stop(paste("'proportion' must be a number strictly between 0 and 1. Got:", args[1]))
}
if (is.na(confidence) || confidence <= 0 || confidence >= 1) {
  stop(paste("'confidence' must be a number strictly between 0 and 1. Got:", args[2]))
}
if (!file.exists(file_path)) {
  stop(paste("File not found:", file_path))
}

spec1_raw <- suppressWarnings(as.double(args[5]))
spec2_raw <- suppressWarnings(as.double(args[6]))

has_spec1 <- !is.na(spec1_raw)   # FALSE when user passed "-"
has_spec2 <- !is.na(spec2_raw)

if (!has_spec1 && !has_spec2) {
  stop("Both spec1 and spec2 are '-'. At least one numeric spec limit must be provided.")
}
if (args[5] != "-" && !has_spec1) {
  stop(paste("'spec1' must be a numeric value or '-'. Got:", args[5]))
}
if (args[6] != "-" && !has_spec2) {
  stop(paste("'spec2' must be a numeric value or '-'. Got:", args[6]))
}
if (has_spec1 && has_spec2 && spec2_raw <= spec1_raw) {
  stop(paste("'spec2' must be greater than 'spec1'. Got spec1 =", spec1_raw,
             "and spec2 =", spec2_raw))
}

# Determines which interval side(s) to show on the plot
two_sided   <- has_spec1 && has_spec2
lower_only  <- has_spec1 && !has_spec2   # spec1 = LSL, show lower TI
upper_only  <- !has_spec1 && has_spec2   # spec2 = USL, show upper TI

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

myforces <- tryCatch(
  read.table(file_path, header = TRUE, sep = ",", dec = ".", row.names = 1),
  error = function(e) stop(paste("Failed to read CSV file:", e$message))
)

if (ncol(myforces) < 1) {
  stop(paste(
    "The CSV file must have at least 2 columns: one for row names and at",
    "least one data column. The file appears to have only 1 column."
  ))
}

if (!col %in% names(myforces)) {
  stop(paste0(
    "Column '", col, "' not found in file. ",
    "Available columns: ", paste(names(myforces), collapse = ", ")
  ))
}

x_raw <- myforces[[col]]

# Remove NA / non-finite values with a warning
n_bad <- sum(is.na(x_raw) | !is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed from column before analysis."))
}
x <- x_raw[is.finite(x_raw) & !is.na(x_raw)]

if (length(x) < 3) {
  stop(paste(
    "Fewer than 3 valid (finite) observations remain after removing NA/Inf.",
    "Cannot compute tolerance intervals."
  ))
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

#' Test whether a numeric vector is approximately normally distributed.
#' Uses skewness as the primary criterion (robust for small N).
#'
#' @param data            Numeric vector to test (must not contain NA/Inf).
#' @param skew_threshold  Maximum absolute skewness considered acceptable (default 0.5).
is_normal <- function(data, skew_threshold = 0.5) {
  if (length(data) < 3 || length(unique(data)) < 3) return(FALSE)
  if (any(is.na(data) | is.infinite(data))) return(FALSE)
  skew <- abs(e1071::skewness(data))
  message(paste("   Skewness value is:", round(skew, 4)))
  skew < skew_threshold
}

#' Attempt Box-Cox transformation and evaluate whether it improves normality.
#'
#' @param x      Strictly positive numeric vector.
#' @param alpha  Significance level for Shapiro-Wilk test (default 0.05).
#' @return A list with fields: transformation, lambda, transformed, backtransform;
#'         or NULL if transformation is not accepted.
try_boxcox <- function(x, alpha = BOXCOX_ALPHA) {

  message("✅ Trying Box-Cox transformation (MLE-based)...")

  lm_model    <- stats::lm(x ~ 1)
  bc_result   <- MASS::boxcox(lm_model, plotit = FALSE)
  best_lambda <- bc_result$x[which.max(bc_result$y)]

  message(paste("   Optimal lambda =", round(best_lambda, 4)))

  if (abs(best_lambda) < LAMBDA_EPS) {
    x_bc <- log(x)
  } else {
    x_bc <- (x^best_lambda - 1) / best_lambda
  }

  skew_before <- abs(e1071::skewness(x))
  skew_after  <- abs(e1071::skewness(x_bc))

  # Guard: shapiro.test() only accepts 3 <= N <= 5000
  if (length(x_bc) >= 3 && length(x_bc) <= 5000) {
    p_val <- shapiro.test(x_bc)$p.value
    message(paste("   Shapiro-Wilk p-value after transform:", round(p_val, 4)))
  } else {
    p_val <- NA
    message(paste("   Shapiro-Wilk test skipped (N =", length(x_bc),
                  "is outside the valid range 3-5000); using skewness only."))
  }

  message(paste("   |Skew| before:", round(skew_before, 4),
                " |Skew| after:", round(skew_after, 4)))

  if (skew_after < skew_before || (!is.na(p_val) && p_val > alpha)) {

    message("   Box-Cox transformation accepted.\n")

    lam <- best_lambda  # capture by value
    if (abs(lam) < LAMBDA_EPS) {
      backtransform_fn <- function(val) exp(val)
    } else {
      backtransform_fn <- function(val) (lam * val + 1)^(1 / lam)
    }

    return(list(
      transformation = paste0("boxcox (lambda=", round(lam, 4), ")"),
      lambda         = lam,
      transformed    = x_bc,
      backtransform  = backtransform_fn
    ))
  }

  message("   Box-Cox did not sufficiently improve normality.")
  return(NULL)
}

#' Determine appropriate transformation for x and return transformed data + metadata.
#'
#' @param x      Numeric vector (NA/Inf already removed).
#' @param alpha  Significance level passed to try_boxcox().
auto_transform_normal <- function(x, alpha = BOXCOX_ALPHA) {

  results <- list(
    original       = x,
    transformation = "none",
    lambda         = NA,
    transformed    = x,
    backtransform  = function(val) val
  )

  message("✅ Analyzing data ...")

  if (is_normal(x)) {
    message("   Data is approximately normal.\n")
    results$transformation <- "normal"
    return(results)
  }

  message("   Data considered not normal. Trying Box-Cox transformation!\n")

  if (all(x > 0)) {
    bc <- try_boxcox(x, alpha)
    if (!is.null(bc)) {
      results$transformation <- bc$transformation
      results$lambda         <- bc$lambda
      results$transformed    <- bc$transformed
      results$backtransform  <- bc$backtransform
      return(results)
    }
  } else {
    message("   Box-Cox requires strictly positive data; skipping (data contains zeros or negatives).")
  }

  return(results)
}

#' Compute normal-theory tolerance interval statistics on (possibly transformed) data.
#'
#' @param x  Numeric vector (already transformed if applicable).
#' @param p  Proportion (coverage), passed as character or double.
#' @param c  Confidence level, passed as character or double.
spin_tolerance <- function(x, p, c) {

  proportion <- as.double(p)
  confidence <- as.double(c)

  s <- sd(x)
  m <- mean(x)
  N <- length(x)

  k1 <- K.factor(N, f = NULL, alpha = (1 - confidence), P = proportion,
                 side = 1, method = "EXACT", m = 100)
  k2 <- K.factor(N, f = NULL, alpha = (1 - confidence), P = proportion,
                 side = 2, method = "EXACT", m = 100)

  ltl1 <- m - k1 * s;  utl1 <- m + k1 * s
  ltl2 <- m - k2 * s;  utl2 <- m + k2 * s

  data.frame(
    SD   = s,    Mean = m,    L    = N,
    K1   = k1,   K2   = k2,
    LTL1 = ltl1, UTL1 = utl1,
    LTL2 = ltl2, UTL2 = utl2
  )
}

#' Build and save a histogram PNG showing the data distribution, fitted normal
#' density curve, tolerance interval limits, and spec limit(s).
#'
#' All values are shown on the original (back-transformed) scale so the plot
#' is directly interpretable against the engineering spec limits.
#'
#' @param x_orig       Numeric vector of original (untransformed) observations.
#' @param tl_data      data.frame returned by spin_tolerance() (transformed scale).
#' @param backtransform Function that converts transformed values to the original scale.
#' @param two_sided    Logical: TRUE = show 2-sided TI limits; FALSE = 1-sided.
#' @param spec1        First spec limit (original scale).
#' @param spec2        Second spec limit (original scale), or NA for 1-sided.
#' @param col_name     Column name used for axis label and file name.
#' @param proportion   Coverage proportion, used in subtitle.
#' @param confidence   Confidence level, used in subtitle.
#' @param transformation_label  String describing the transformation applied.
#' @param out_dir      Directory where the PNG will be saved.
save_histogram <- function(x_orig, tl_data, backtransform,
                           has_spec1, has_spec2,
                           spec1, spec2, col_name, proportion, confidence,
                           transformation_label, out_dir) {

  two_sided  <- has_spec1 && has_spec2
  lower_only <- has_spec1 && !has_spec2
  # upper_only is the remaining case: !has_spec1 && has_spec2

  if (two_sided) {
    tl_lo    <- backtransform(tl_data$LTL2)
    tl_hi    <- backtransform(tl_data$UTL2)
    ti_label <- sprintf("2-sided TI (P=%.2f, C=%.2f)", proportion, confidence)
  } else if (lower_only) {
    tl_lo    <- backtransform(tl_data$LTL1)
    tl_hi    <- NULL
    ti_label <- sprintf("1-sided lower TI (P=%.2f, C=%.2f)", proportion, confidence)
  } else {
    tl_lo    <- NULL
    tl_hi    <- backtransform(tl_data$UTL1)
    ti_label <- sprintf("1-sided upper TI (P=%.2f, C=%.2f)", proportion, confidence)
  }
  
  # --- Out-of-spec shading: red if TI violates spec, green if TI is within spec ---
  shade_df <- data.frame(xmin = numeric(0), xmax = numeric(0), fill_col = character(0),
                         stringsAsFactors = FALSE)
  if (has_spec1 && !is.null(tl_lo)) {
    if (tl_lo < spec1)
      shade_df <- rbind(shade_df, data.frame(xmin = tl_lo, xmax = spec1,
                                             fill_col = "#D6302A", stringsAsFactors = FALSE))
    else
      shade_df <- rbind(shade_df, data.frame(xmin = spec1, xmax = tl_lo,
                                             fill_col = "#2CA02C", stringsAsFactors = FALSE))
  }
  if (has_spec2 && !is.null(tl_hi)) {
    if (tl_hi > spec2)
      shade_df <- rbind(shade_df, data.frame(xmin = spec2, xmax = tl_hi,
                                             fill_col = "#D6302A", stringsAsFactors = FALSE))
    else
      shade_df <- rbind(shade_df, data.frame(xmin = tl_hi, xmax = spec2,
                                             fill_col = "#2CA02C", stringsAsFactors = FALSE))
  }
    
  # --- Fitted normal parameters on original scale ---
  fit_mean <- mean(x_orig)
  fit_sd   <- sd(x_orig)

  # --- X-axis range: accommodate data, TI limits, and spec limits ---
  all_x_vals <- c(x_orig,
                  if (!is.null(tl_lo)) tl_lo,
                  if (!is.null(tl_hi)) tl_hi,
                  if (has_spec1) spec1,
                  if (has_spec2) spec2)
  x_range  <- range(all_x_vals, na.rm = TRUE)
  x_margin <- diff(x_range) * 0.15
  x_lo     <- x_range[1] - x_margin
  x_hi     <- x_range[2] + x_margin  
  
  # --- Subtitle lines ---
  subtitle_line1 <- sprintf("N = %d  |  Mean = %.4g  |  SD = %.4g  |  Transform: %s",
                             length(x_orig), fit_mean, fit_sd, transformation_label)
  subtitle_parts <- c(
    if (!is.null(tl_lo)) sprintf("TI lower = %.4g", tl_lo),
    if (!is.null(tl_hi)) sprintf("TI upper = %.4g", tl_hi),
    if (has_spec1)        sprintf("Spec1 (LSL) = %.4g", spec1),
    if (has_spec2)        sprintf("Spec2 (USL) = %.4g", spec2)
  )
  subtitle_line2 <- paste(subtitle_parts, collapse = "  |  ")
  
  # --- Vertical line definitions (built as a data frame for a clean legend) ---
  vline_df <- data.frame(
    xval      = numeric(0),
    ltype     = character(0),
    vjust_val = numeric(0),
    stringsAsFactors = FALSE
  )
  if (!is.null(tl_lo))
    vline_df <- rbind(vline_df, data.frame(xval = tl_lo, ltype = "TI",   vjust_val = -1.5,
                                           stringsAsFactors = FALSE))
  if (!is.null(tl_hi))
    vline_df <- rbind(vline_df, data.frame(xval = tl_hi, ltype = "TI",   vjust_val = -1.5,
                                           stringsAsFactors = FALSE))
  if (has_spec1)
    vline_df <- rbind(vline_df, data.frame(xval = spec1, ltype = "Spec", vjust_val = -50.0,
                                           stringsAsFactors = FALSE))
  if (has_spec2)
    vline_df <- rbind(vline_df, data.frame(xval = spec2, ltype = "Spec", vjust_val = -50.0,
                                           stringsAsFactors = FALSE))

   # Colour and linetype mappings — kept outside aes() to avoid scale conflicts
  line_colours   <- c("TI" = "#2166AC", "Spec" = "#D6302A")  # blue / red
  line_linetypes <- c("TI" = "dashed",  "Spec" = "dashed")

  # --- Build plot ---
  df <- data.frame(value = x_orig)

  p <- ggplot(df, aes(x = value)) +
  
    # Out-of-spec violation zones (drawn first so they appear behind everything)

    geom_rect(data = shade_df,
              aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = fill_col),
              inherit.aes = FALSE,
              alpha       = 0.15) +
    scale_fill_identity() +

    # Histogram (counts scaled to density for overlay with density curve)
    geom_histogram(aes(y = after_stat(density)),
                   bins     = max(10, min(50, round(sqrt(length(x_orig)) * 2))),
                   fill     = "#AECDE8",
                   colour   = "#5A8FAF",
                   linewidth = 0.3,
                   alpha    = 0.85) +

    # Fitted normal density curve on original scale
    stat_function(fun      = dnorm,
                  args     = list(mean = fit_mean, sd = fit_sd),
                  colour   = "#1A1A2E",
                  linewidth = 0.8,
                  linetype = "solid") +

    # Vertical lines for TI limits and spec limits
    geom_vline(data     = vline_df,
               aes(xintercept = xval, colour = ltype, linetype = ltype),
               linewidth = 0.9) +

    # Annotate each vertical line with its numeric value just above the x-axis
    geom_text(data   = vline_df,
              aes(x = xval, label = sprintf("%.4g", xval), colour = ltype, vjust = vjust_val),
              y          = -Inf,
              hjust      = 0.5,
              size       = 2.8,
              fontface   = "bold",
              show.legend = FALSE) +

    # Manual colour and linetype scales to produce a clean legend
    scale_colour_manual(
      name   = NULL,
      values = line_colours,
      labels = c("TI" = ti_label, "Spec" = "Spec limit")
    ) +
    scale_linetype_manual(
      name   = NULL,
      values = line_linetypes,
      labels = c("TI" = ti_label, "Spec" = "Spec limit")
    ) +

    # Expand x axis to show all elements
    coord_cartesian(xlim = c(x_lo, x_hi)) +

    labs(
      title    = paste("Tolerance Interval Analysis:", col_name),
      subtitle = paste0(subtitle_line1, "\n", subtitle_line2),
      x        = col_name,
      y        = "Density"
    ) +

    theme_bw(base_size = 11) +
    theme(
      plot.title       = element_text(face = "bold", size = 13),
      plot.subtitle    = element_text(size = 8.5, colour = "grey30"),
      legend.position  = "bottom",
      legend.key.width = unit(1.8, "cm"),
      panel.grid.minor = element_blank()
    )

  # --- Save PNG ---
  # Filename: <datetime>_<column_name>_tolerance.png, saved alongside the CSV
  datetime_prefix <- format(Sys.time(), "%Y%m%d_%H%M%S")
  safe_col        <- gsub("[^A-Za-z0-9_.-]", "_", col_name)
  out_file        <- file.path(dirname(normalizePath(out_dir)),
                               paste0(datetime_prefix, "_", safe_col, "_tolerance.png"))
  ggsave(out_file, plot = p, width = 9, height = 6, dpi = 150, bg = "white")
  message(paste("✅ Histogram saved to:", out_file))
  invisible(out_file)
}

# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

# Print header before running auto_transform_normal so it appears at the top
message(" ")
message("✅ Statistical Tolerance Interval Verification")
message("   version: 2.0, author: Joep Rous")
message("   ================================================")
message(paste("   for proportion:                ", proportion))
message(paste("   for confidence:                ", confidence))
message(paste("   file:                          ", file_path))
message(paste("   column:                        ", input_col))
message(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
message(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
message(" ")

result <- auto_transform_normal(x, alpha = BOXCOX_ALPHA)

if (result$transformation != "none") {

  ltl_bs_data <- spin_tolerance(result$transformed, proportion, confidence)

  message(paste("   #samples:                      ", ltl_bs_data$L))
  message(paste("   transformation applied:        ", result$transformation))
  message(" ")
  message("✅ Results:")

  if (result$transformation != "normal") {
    # Mean and SD on the transformed scale do not back-transform to meaningful
    # location/dispersion measures on the original scale, so we skip them.
    message("   Note: Mean and SD are omitted after Box-Cox transformation.")
    message("         The tolerance limits below are back-transformed to the original scale.")
  } else {
    message(paste("   Mean:                          ", fmt(ltl_bs_data$Mean)))
    message(paste("   SD:                            ", fmt(ltl_bs_data$SD)))
  }

  if (lower_only) {
    message(paste("   1-sided lower tolerance limit: ", fmt(result$backtransform(ltl_bs_data$LTL1))))
    message(paste("   K-factor 1-sided:              ", fmt(ltl_bs_data$K1)))
    if (result$backtransform(ltl_bs_data$LTL1) < spec1_raw) {
    	message("   ❌ Lower Tolerance Limit less than Lower Spec Limit")
    } else {
    	message("   ✅ Lower Tolerance Limit greater than Lower Spec Limit")
    }
  }
  if (upper_only) {
    message(paste("   1-sided upper tolerance limit: ", fmt(result$backtransform(ltl_bs_data$UTL1))))
    message(paste("   K-factor 1-sided:              ", fmt(ltl_bs_data$K1)))
    if (result$backtransform(ltl_bs_data$UTL1) > spec2_raw) {
    	message("   ❌ Upper Tolerance Limit greater than Upper Spec Limit")
    } else {
    	message("   ✅ Upper Tolerance Limit less than Upper Spec Limit")
    }

  }
  if (two_sided) {
    message(paste("   2-sided lower tolerance limit: ", fmt(result$backtransform(ltl_bs_data$LTL2))))
    message(paste("   2-sided upper tolerance limit: ", fmt(result$backtransform(ltl_bs_data$UTL2))))
    message(paste("   K-factor 2-sided:              ", fmt(ltl_bs_data$K2)))
    if ((result$backtransform(ltl_bs_data$LTL2) < spec1_raw) | (result$backtransform(ltl_bs_data$UTL2) > spec2_raw)) {
    	message("   ❌ Tolerance Interval not inside Spec Interval")
    } else {
    	message("   ✅ Tolerance Interval inside Spec Interval")    	
    }

  }
  message(" ")

  # --- Generate and save histogram ---

  save_histogram(
    x_orig               = x,
    tl_data              = ltl_bs_data,
    backtransform        = result$backtransform,
    has_spec1            = has_spec1,
    has_spec2            = has_spec2,
    spec1                = spec1_raw,
    spec2                = spec2_raw,
    col_name             = input_col,
    proportion           = proportion,
    confidence           = confidence,
    transformation_label = result$transformation,
    out_dir              = file_path
  )
  message(" ")
} else {

  message("\u274c Result: Could not compute tolerance intervals.")
  message("")
  message("   The data do not appear to follow a normal distribution, and Box-Cox")
  message("   transformation did not achieve sufficient normality.")
  message("   (Note: square-root transformation is not attempted separately as it is")
  message("    a special case of Box-Cox with lambda = 0.5 and is covered by that search.)")
  message("")
  message("   Suggestions:")
  message("     - If data are heavily rounded, try using more decimal places.")
  message("     - Plot your data and inspect for multimodality or outliers.")
  message("     - Consider whether the process may have shifted over time (non-stationarity).")
  message("     - A non-parametric tolerance interval may be appropriate for this dataset.")
  message(" ")

}
