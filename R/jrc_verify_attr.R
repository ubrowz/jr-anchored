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
# Saves a histogram PNG to the output directory (JR_OUT_DIR, default ~/Downloads), showing:
#   - Data histogram with the fitted model density (original scale): normal,
#     or the Box-Cox model mapped back when a transformation was used
#   - Tolerance interval limits (blue dashed lines)
#   - Spec limit(s) (red dashed lines)
#   - Green/red shading between TI and spec to indicate pass/fail
#
# Use after jrc_ss_attr or jrc_ss_attr_check to confirm the verification
# result and produce a plot for the test report.
#
# Author: Joep Rous
# Version: 2.1

# ---------------------------------------------------------------------------
# Validated environment: pinned renv library + shared helpers (bin/)
# ---------------------------------------------------------------------------
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT")) || !nzchar(Sys.getenv("JR_PROJECT_ROOT"))) {
  stop("\u274c RENV_PATHS_ROOT / JR_PROJECT_ROOT not set. Run this script via jrrun or its wrapper.")
}
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))
jr_use_renv_library()

SCRIPT_VERSION <- "2.1"   # single source for banner, report and JSON

suppressPackageStartupMessages({
  library(tolerance)
  library(MASS)      # For boxcox()
  library(e1071)     # For skewness()
  library(ggplot2)   # For histogram plot
  library(base64enc) # For PNG embedding in HTML report
})

# Format a number to a fixed number of significant figures for output
fmt <- function(x, digits = 4) signif(x, digits)

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

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
n_bad <- sum(!is.finite(x_raw))
if (n_bad > 0) {
  warning(paste(n_bad, "NA or non-finite value(s) removed from column before analysis."))
}
x <- x_raw[is.finite(x_raw)]

if (length(x) < 3) {
  stop(paste(
    "Fewer than 3 valid (finite) observations remain after removing NA/Inf.",
    "Cannot compute tolerance intervals."
  ))
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

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

  k1 <- jr_kfactor(N, proportion, confidence, 1)
  k2 <- jr_kfactor(N, proportion, confidence, 2)

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
#' @param lambda       Box-Cox lambda used for the tolerance interval, or NA.
save_histogram <- function(x_orig, tl_data, backtransform,
                           has_spec1, has_spec2,
                           spec1, spec2, col_name, proportion, confidence,
                           transformation_label, lambda = NA) {

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
    
  # --- Fitted model density on the original scale ---
  # The curve shows the model the tolerance interval was computed from: a
  # normal on the original scale, or, after Box-Cox, the normal fitted to the
  # transformed data mapped back by change of variables,
  #   f(x) = dnorm(g(x); mu_t, sd_t) * |g'(x)|,  g'(x) = x^(lambda - 1)
  # (code review 2026-10, COR-26). Mean/SD in the subtitle stay descriptive.
  fit_mean <- mean(x_orig)
  fit_sd   <- sd(x_orig)
  if (is.na(lambda)) {
    model_density <- function(v) stats::dnorm(v, mean = fit_mean, sd = fit_sd)
  } else {
    x_t  <- jr_boxcox_transform(x_orig, lambda)
    mu_t <- mean(x_t)
    sd_t <- sd(x_t)
    model_density <- function(v) {
      out <- numeric(length(v))
      ok  <- v > 0
      out[ok] <- stats::dnorm(jr_boxcox_transform(v[ok], lambda), mu_t, sd_t) *
                 v[ok]^(lambda - 1)
      out
    }
  }

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

    # Fitted model density on original scale (see model_density above)
    stat_function(fun      = model_density,
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
  # Filename: <datetime>_<column_name>_tolerance.png, in the output directory
  datetime_prefix <- format(Sys.time(), "%Y%m%d_%H%M%S")
  safe_col        <- gsub("[^A-Za-z0-9_.-]", "_", col_name)
  out_file        <- file.path(jr_out_dir(),
                               paste0(datetime_prefix, "_", safe_col, "_tolerance.png"))
  ggsave(out_file, plot = p, width = 6.5, height = 4.5, dpi = 150, bg = "white")
  jr_say(paste("✅ Histogram saved to:", out_file))
  invisible(out_file)
}

#' Build and save an HTML verification report template.
#' Auto-fills all analysis results and embeds the chart. User completes
#' Purpose, Conclusion, and Approvals sections before use.
#'
#' @param x           Original numeric data vector (NA/Inf removed).
#' @param result      Output of jr_auto_transform_normal().
#' @param tl_data     Output of spin_tolerance().
#' @param proportion  Coverage proportion.
#' @param confidence  Confidence level.
#' @param input_col   Column name (display label).
#' @param file_path   Path to input CSV (used to derive output directory).
#' @param png_path    Path to the histogram PNG to embed (or NULL).
#' @param has_spec1, has_spec2  Logicals.
#' @param spec1_raw, spec2_raw  Numeric spec limits (may be NA).
#' @param two_sided, lower_only  Logicals describing interval type.
#' @param verdict     Logical: TRUE = PASS.
save_report <- function(x, result, tl_data,
                        proportion, confidence,
                        input_col, file_path, png_path,
                        has_spec1, has_spec2, spec1_raw, spec2_raw,
                        two_sided, lower_only, verdict) {

  # ── HTML escaping helper ──────────────────────────────────────────────
  he <- jr_html_escape

  # ── Display values ────────────────────────────────────────────────────
  n_val      <- length(x)
  upper_only <- !has_spec1 && has_spec2

  if (result$transformation == "normal") {
    mean_val  <- fmt(mean(x))
    sd_val    <- fmt(sd(x))
    mean_note <- ""
  } else {
    mean_val  <- "\u2014"
    sd_val    <- "\u2014"
    mean_note <- "omitted after Box-Cox transformation"
  }

  if (two_sided) {
    tl_lo_val <- fmt(result$backtransform(tl_data$LTL2))
    tl_hi_val <- fmt(result$backtransform(tl_data$UTL2))
    k_val     <- fmt(tl_data$K2)
    ti_type   <- "2-sided"
  } else if (lower_only) {
    tl_lo_val <- fmt(result$backtransform(tl_data$LTL1))
    tl_hi_val <- "\u2014"
    k_val     <- fmt(tl_data$K1)
    ti_type   <- "1-sided (lower bound)"
  } else {
    tl_lo_val <- "\u2014"
    tl_hi_val <- fmt(result$backtransform(tl_data$UTL1))
    k_val     <- fmt(tl_data$K1)
    ti_type   <- "1-sided (upper bound)"
  }

  spec1_disp <- if (has_spec1) he(as.character(spec1_raw)) else "\u2014"
  spec2_disp <- if (has_spec2) he(as.character(spec2_raw)) else "\u2014"

  v_text  <- if (verdict) "PASS" else "FAIL"
  v_icon  <- if (verdict) "\u2705" else "\u274c"
  v_color <- if (verdict) "#155724" else "#721c24"
  v_bg    <- if (verdict) "#d4edda"  else "#f8d7da"
  v_bdr   <- if (verdict) "#c3e6cb"  else "#f5c6cb"

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  # ── Embed PNG as base64 ───────────────────────────────────────────────
  if (!is.null(png_path) && file.exists(png_path)) {
    b64     <- base64enc::base64encode(png_path)
    img_tag <- paste0(
      '<img src="data:image/png;base64,', b64, '" ',
      'alt="Tolerance interval chart" width="100%" ',
      'style="width:100%;height:auto;display:block;margin:0 auto;border:1px solid #ccc;">'
    )
  } else {
    img_tag <- "<p><em>(Chart not available.)</em></p>"
  }

  # ── CSS ───────────────────────────────────────────────────────────────
  css <- paste(c(
    "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}",
    "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1a1a1a;",
    "     background:#fff;padding:24px}",
    ".report{background:#fff;max-width:820px;margin:0 auto;padding:40px 48px;",
    "        border:1px solid #ccc;box-shadow:0 2px 10px rgba(0,0,0,.10)}",
    ".rpt-hdr{border-bottom:3px solid #1a3a6b;padding-bottom:14px;margin-bottom:24px}",
    ".rpt-hdr h1{font-size:1.45em;color:#1a3a6b;margin-bottom:2px}",
    ".rpt-hdr h2{font-size:1em;font-weight:normal;color:#555;margin-bottom:14px}",
    "table.meta{border-collapse:collapse}",
    "table.meta td{padding:3px 14px 3px 0;vertical-align:top;font-size:.91em}",
    "table.meta td.k{font-weight:600;color:#333;min-width:130px}",
    ".draft{color:#a00;font-weight:bold}",
    ".section{margin-top:26px}",
    ".sec-ttl{font-weight:700;color:#1a3a6b;border-bottom:1.5px solid #1a3a6b;",
    "         padding-bottom:4px;margin-bottom:10px;font-size:.95em;",
    "         text-transform:uppercase;letter-spacing:.04em}",
    "table.dt{width:100%;border-collapse:collapse;font-size:.93em}",
    "table.dt td{padding:5px 10px;border:1px solid #ddd;vertical-align:top}",
    "table.dt td.l{width:210px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    paste0(".verdict{margin-top:12px;padding:11px 16px;border-radius:4px;",
           "font-size:1.05em;font-weight:bold;text-align:center;",
           "background:", v_bg, ";color:", v_color, ";border:2px solid ", v_bdr, "}"),
    ".chart-wrap{text-align:center;margin-top:8px}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;",
    "              text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;",
    "           text-align:center;margin-bottom:24px;color:#999;font-size:.9em;",
    "           min-height:72px;display:flex;align-items:center;justify-content:center}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;",
    "            font-size:.79em;color:#999;text-align:center}",
    "@media print{",
    "  body{background:#fff;padding:0}",
    "  .report{border:none;box-shadow:none;padding:16px;max-width:100%}",
    "  .verdict,table.dt td.f{-webkit-print-color-adjust:exact;print-color-adjust:exact}",
    "}"
  ), collapse = "\n")

  # ── HTML assembly ─────────────────────────────────────────────────────
  mean_td <- if (nchar(mean_note) > 0)
    paste0(he(mean_val),
           ' <em style="font-size:.85em;color:#888;">(', he(mean_note), ')</em>')
  else
    he(mean_val)

  out <- c(
    '<!DOCTYPE html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="UTF-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    paste0('<title>Verification Report \u2014 ', he(input_col), '</title>'),
    '<style>', css, '</style>',
    '</head>',
    '<body>',
    '<div class="report">',

    # Logo placeholder
    '<div class="logo-wrap">[Insert company logo here &mdash; replace this box with your logo in Word]</div>',

    # Header
    '<div class="rpt-hdr">',
    '<h1>Design Verification Report</h1>',
    '<h2>Statistical Tolerance Interval Analysis</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    paste0('<tr><td class="k">Script</td><td>jrc_verify_attr v', SCRIPT_VERSION, ' &mdash; JR Anchored</td></tr>'),
    '<tr><td class="k">Status</td>',
    '<td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table>',
    '</div>',

    # 1. Purpose and Scope
    '<div class="section">',
    '<div class="sec-ttl">1. Purpose and Scope</div>',
    '<table class="dt">',
    '<tr><td class="l">Requirement Reference</td>',
    '<td class="f">[enter design input or design output requirement ID and description]</td></tr>',
    '<tr><td class="l">Design Input / Output</td>',
    '<td class="f">[state whether this verifies a Design Input (DI) or Design Output (DO)]</td></tr>',
    '<tr><td class="l">Purpose of Verification</td>',
    '<td class="f">[describe what is being verified and why the tolerance interval method was selected]</td></tr>',
    '<tr><td class="l">Acceptance Criterion</td>',
    '<td class="f">[restate the acceptance criterion, e.g.: at least 95% of the population lies within spec, with 95% confidence]</td></tr>',
    '</table>',
    '</div>',

    # 2. Test Setup
    '<div class="section">',
    '<div class="sec-ttl">2. Test Setup</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">Data File</td><td>', he(file_path), '</td></tr>'),
    paste0('<tr><td class="l">Column / Characteristic</td><td>', he(input_col), '</td></tr>'),
    paste0('<tr><td class="l">Sample Size (N)</td><td>', he(n_val), '</td></tr>'),
    paste0('<tr><td class="l">Proportion (P)</td><td>', he(proportion), '</td></tr>'),
    paste0('<tr><td class="l">Confidence (C)</td><td>', he(confidence), '</td></tr>'),
    paste0('<tr><td class="l">Spec Limit 1 (LSL)</td><td>', spec1_disp, '</td></tr>'),
    paste0('<tr><td class="l">Spec Limit 2 (USL)</td><td>', spec2_disp, '</td></tr>'),
    '<tr><td class="l">Test Conditions</td>',
    '<td class="f">[describe measurement conditions, equipment, operator, and date of measurements]</td></tr>',
    '</table>',
    '</div>',

    # 3. Statistical Method
    '<div class="section">',
    '<div class="sec-ttl">3. Statistical Method</div>',
    '<table class="dt">',
    '<tr><td class="l">Method</td>',
    '<td>Normal-theory statistical tolerance interval (K-factor method, EXACT)</td></tr>',
    paste0('<tr><td class="l">Interval Type</td><td>', he(ti_type), '</td></tr>'),
    paste0('<tr><td class="l">Transformation</td><td>', he(result$transformation), '</td></tr>'),
    '<tr><td class="l">Reference</td>',
    '<td>Krishnamoorthy &amp; Mathew (2009). <em>Statistical Tolerance Regions</em>. Wiley.</td></tr>',
    '</table>',
    '</div>',

    # 4. Results
    '<div class="section">',
    '<div class="sec-ttl">4. Results</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">N (valid observations)</td><td>', he(n_val), '</td></tr>'),
    paste0('<tr><td class="l">Mean</td><td>', mean_td, '</td></tr>'),
    paste0('<tr><td class="l">SD</td><td>', he(sd_val), '</td></tr>'),
    paste0('<tr><td class="l">K-factor</td><td>', he(k_val), '</td></tr>'),
    paste0('<tr><td class="l">TI Lower Limit</td><td>', he(tl_lo_val), '</td></tr>'),
    paste0('<tr><td class="l">TI Upper Limit</td><td>', he(tl_hi_val), '</td></tr>'),
    paste0('<tr><td class="l">Spec Limit 1 (LSL)</td><td>', spec1_disp, '</td></tr>'),
    paste0('<tr><td class="l">Spec Limit 2 (USL)</td><td>', spec2_disp, '</td></tr>'),
    '</table>',
    paste0('<div class="verdict">', v_icon, ' Verification outcome: ', v_text, '</div>'),
    '</div>',

    # 5. Chart
    '<div class="section">',
    '<div class="sec-ttl">5. Verification Chart</div>',
    '<div class="chart-wrap">',
    img_tag,
    '</div>',
    '</div>',

    # 6. Conclusion
    '<div class="section">',
    '<div class="sec-ttl">6. Conclusion</div>',
    '<table class="dt">',
    paste0('<tr><td class="l">Outcome</td>',
           '<td style="font-weight:bold;color:', v_color, '">', v_icon, ' ', v_text, '</td></tr>'),
    '<tr><td class="l">Conclusion</td>',
    '<td class="f">[state whether the design requirement is verified; summarise the statistical evidence]</td></tr>',
    '<tr><td class="l">Deviations / Observations</td>',
    '<td class="f">[NONE &mdash; or describe any deviations from the planned test method]</td></tr>',
    '</table>',
    '</div>',

    # 7. Approvals
    '<div class="section">',
    '<div class="sec-ttl">7. Approvals</div>',
    '<table class="appr">',
    '<tr><th style="width:22%">Role</th><th style="width:28%">Name</th>',
    '<th style="width:28%">Signature</th><th style="width:22%">Date</th></tr>',
    '<tr><td>Performed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</table>',
    '</div>',

    paste0(paste0('<div class="rpt-footer">Generated by jrc_verify_attr v', SCRIPT_VERSION, ' &mdash; JR Anchored &mdash; '),
           he(dt_str), '</div>'),
    '</div>',  # /report
    '</body>',
    '</html>'
  )

  # ── Write file ────────────────────────────────────────────────────────
  dt_prefix <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_file  <- file.path(jr_out_dir(),
                         paste0(dt_prefix, "_jrc_verify_attr_report.html"))
  writeLines(out, out_file, useBytes = TRUE)
  jr_say(paste("\u2705 Verification report saved to:", out_file))

  # ── JSON sidecar ─────────────────────────────────────────────────────────
  jvs <- jr_json_str   # shared escaper (bin/jr_helpers.R)
  jvn <- function(x, fmt = "%.6g") jr_json_num(x, fmt)
  jvb <- jr_json_bool

  method_rows <- paste0(
    '{"k":"Method","v":"Statistical Tolerance Interval (K-factor, exact)"},',
    '{"k":"Reference","v":"Krishnamoorthy & Mathew (2009). Statistical Tolerance Regions. Wiley."},',
    '{"k":"Proportion (P)","v":', jvn(proportion, "%.4g"), '},',
    '{"k":"Confidence (C)","v":', jvn(confidence, "%.4g"), '},',
    '{"k":"Interval type","v":', jvs(ti_type), '},',
    '{"k":"Transformation","v":', jvs(result$transformation), '},',
    '{"k":"Column / Characteristic","v":', jvs(input_col), '}'
  )

  results_rows <- paste0(
    '{"k":"n (valid observations)","v":', jvn(n_val, "%.0f"), '},',
    '{"k":"Mean","v":', jvs(mean_val), '},',
    '{"k":"SD","v":', jvs(sd_val), '},',
    '{"k":"K-factor","v":', jvs(k_val), '},',
    '{"k":"TI Lower Limit","v":', jvs(tl_lo_val), '},',
    '{"k":"TI Upper Limit","v":', jvs(tl_hi_val), '},',
    '{"k":"Spec Limit 1 (LSL)","v":', if (has_spec1) jvs(as.character(spec1_raw)) else '"\u2014"', '},',
    '{"k":"Spec Limit 2 (USL)","v":', if (has_spec2) jvs(as.character(spec2_raw)) else '"\u2014"', '},',
    '{"k":"Verdict","v":', jvs(v_text), '}'
  )

  png_json <- if (!is.null(png_path) && file.exists(png_path)) jvs(gsub("\\\\", "/", png_path)) else "null"

  input_sha256 <- jr_sha256_file(file_path)

  json_str <- paste0(
    '{"report_type":"dv",',
    '"script":"jrc_verify_attr",',
    '"version":"', SCRIPT_VERSION, '",',
    '"report_id":', jvs(report_id), ',',
    '"generated":', jvs(dt_str), ',',
    '"verdict_pass":', jvb(verdict), ',',
    '"png_path":', png_json, ',',
    '"input_file":', jvs(basename(file_path)), ',',
    '"input_sha256":', jvs(input_sha256), ',',
    '"method":[', method_rows, '],',
    '"results":[', results_rows, ']}'
  )

  json_path <- sub("\\.html$", "_data.json", out_file)
  writeLines(json_str, json_path)
  jr_say(sprintf("  JSON sidecar: %s", json_path))

  jr_run_pack(json_path, "dv-report", out_file, log_files = png_path)

  invisible(out_file)
}

# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

# Print header before running auto_transform_normal so it appears at the top
jr_say(" ")
jr_say("✅ Statistical Tolerance Interval Verification")
jr_say(paste0("   version: ", SCRIPT_VERSION, ", author: Joep Rous"))
jr_say("   ================================================")
jr_say(paste("   for proportion:                ", proportion))
jr_say(paste("   for confidence:                ", confidence))
jr_say(paste("   file:                          ", file_path))
jr_say(paste("   column:                        ", input_col))
jr_say(paste("   spec limit 1 (lower):          ", if (has_spec1) spec1_raw else "-"))
jr_say(paste("   spec limit 2 (upper):          ", if (has_spec2) spec2_raw else "-"))
jr_say(" ")

result <- jr_auto_transform_normal(x, alpha = JR_BOXCOX_ALPHA)

if (result$transformation != "none") {

  ltl_bs_data <- spin_tolerance(result$transformed, proportion, confidence)

  jr_say(paste("   #samples:                      ", ltl_bs_data$L))
  jr_say(paste("   transformation applied:        ", result$transformation))
  jr_say(" ")
  jr_say("✅ Results:")

  if (result$transformation != "normal") {
    # Mean and SD on the transformed scale do not back-transform to meaningful
    # location/dispersion measures on the original scale, so we skip them.
    jr_say("   Note: Mean and SD are omitted after Box-Cox transformation.")
    jr_say("         The tolerance limits below are back-transformed to the original scale.")
  } else {
    jr_say(paste("   Mean:                          ", fmt(ltl_bs_data$Mean)))
    jr_say(paste("   SD:                            ", fmt(ltl_bs_data$SD)))
  }

  if (lower_only) {
    jr_say(paste("   1-sided lower tolerance limit: ", fmt(result$backtransform(ltl_bs_data$LTL1))))
    jr_say(paste("   K-factor 1-sided:              ", fmt(ltl_bs_data$K1)))
    if (result$backtransform(ltl_bs_data$LTL1) < spec1_raw) {
    	jr_say("   ❌ Lower Tolerance Limit less than Lower Spec Limit")
    } else {
    	jr_say("   ✅ Lower Tolerance Limit greater than Lower Spec Limit")
    }
  }
  if (upper_only) {
    jr_say(paste("   1-sided upper tolerance limit: ", fmt(result$backtransform(ltl_bs_data$UTL1))))
    jr_say(paste("   K-factor 1-sided:              ", fmt(ltl_bs_data$K1)))
    if (result$backtransform(ltl_bs_data$UTL1) > spec2_raw) {
    	jr_say("   ❌ Upper Tolerance Limit greater than Upper Spec Limit")
    } else {
    	jr_say("   ✅ Upper Tolerance Limit less than Upper Spec Limit")
    }

  }
  if (two_sided) {
    jr_say(paste("   2-sided lower tolerance limit: ", fmt(result$backtransform(ltl_bs_data$LTL2))))
    jr_say(paste("   2-sided upper tolerance limit: ", fmt(result$backtransform(ltl_bs_data$UTL2))))
    jr_say(paste("   K-factor 2-sided:              ", fmt(ltl_bs_data$K2)))
    if ((result$backtransform(ltl_bs_data$LTL2) < spec1_raw) | (result$backtransform(ltl_bs_data$UTL2) > spec2_raw)) {
    	jr_say("   ❌ Tolerance Interval not inside Spec Interval")
    } else {
    	jr_say("   ✅ Tolerance Interval inside Spec Interval")    	
    }

  }
  jr_say(" ")

  # ── Verdict (PASS / FAIL) ──────────────────────────────────────────────
  verdict <- if (lower_only) {
    result$backtransform(ltl_bs_data$LTL1) >= spec1_raw
  } else if (upper_only) {
    result$backtransform(ltl_bs_data$UTL1) <= spec2_raw
  } else {
    (result$backtransform(ltl_bs_data$LTL2) >= spec1_raw) &&
    (result$backtransform(ltl_bs_data$UTL2) <= spec2_raw)
  }

  # --- Generate and save histogram ---

  png_path <- save_histogram(
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
    lambda               = result$lambda
  )

  # --- Generate Word report (if requested) ---

  if (want_report) {
    jr_require_report_template("verify_attr_report_template.html", log_files = png_path)
    save_report(
      x          = x,
      result     = result,
      tl_data    = ltl_bs_data,
      proportion = proportion,
      confidence = confidence,
      input_col  = input_col,
      file_path  = file_path,
      png_path   = png_path,
      has_spec1  = has_spec1,
      has_spec2  = has_spec2,
      spec1_raw  = spec1_raw,
      spec2_raw  = spec2_raw,
      two_sided  = two_sided,
      lower_only = lower_only,
      verdict    = verdict
    )
  }
  jr_log_output_hashes(c(png_path))
  jr_say(" ")
} else {

  jr_say("\u274c Result: Could not compute tolerance intervals.")
  jr_say("")
  jr_say("   The data do not appear to follow a normal distribution, and Box-Cox")
  jr_say("   transformation did not achieve sufficient normality.")
  jr_say("   (Note: square-root transformation is not attempted separately as it is")
  jr_say("    a special case of Box-Cox with lambda = 0.5 and is covered by that search.)")
  jr_say("")
  jr_say("   Suggestions:")
  jr_say("     - If data are heavily rounded, try using more decimal places.")
  jr_say("     - Plot your data and inspect for multimodality or outliers.")
  jr_say("     - Consider whether the process may have shifted over time (non-stationarity).")
  jr_say("     - A non-parametric tolerance interval may be appropriate for this dataset.")
  jr_say(" ")

}
