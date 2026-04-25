# =============================================================================
# jrc_cap_nonnormal.R
# JR Validated Environment — Process Capability module
#
# Process Capability Analysis for non-normally distributed data.
# Uses the percentile method (ISO 22514-2 / AIAG): process spread is
# estimated from the 0.135th and 99.865th sample percentiles (equivalent
# to ±3σ for a normal distribution) rather than from the standard deviation.
# Also performs a Shapiro-Wilk normality test and warns if data appear normal.
#
# Usage: jrc_cap_nonnormal <data.csv> <col> <lsl> <usl> [--report]
#
# <lsl> and <usl> may each be "-" to omit one-sided. At least one must be a number.
# =============================================================================

# ---------------------------------------------------------------------------
# Argument parsing — strip --report before positional parsing
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) < 4) {
  stop("Usage: jrc_cap_nonnormal <data.csv> <col> <lsl> <usl> [--report]\n  Use '-' for <lsl> or <usl> to analyse one-sided.")
}

data_file <- args[1]
col_name  <- args[2]
lsl_arg   <- args[3]
usl_arg   <- args[4]

lsl <- if (lsl_arg == "-") NA_real_ else suppressWarnings(as.numeric(lsl_arg))
usl <- if (usl_arg == "-") NA_real_ else suppressWarnings(as.numeric(usl_arg))

if (is.na(lsl) && lsl_arg != "-") stop("LSL must be a number or '-'.")
if (is.na(usl) && usl_arg != "-") stop("USL must be a number or '-'.")
if (is.na(lsl) && is.na(usl))     stop("At least one of LSL or USL must be provided.")
if (!is.na(lsl) && !is.na(usl) && lsl >= usl) stop("LSL must be less than USL.")

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------
renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("❌ RENV_PATHS_ROOT is not set. Run this script from the provided wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("❌ renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(base64enc)
}))

# ---------------------------------------------------------------------------
# Report generator — defined before any early exit
# ---------------------------------------------------------------------------
save_cap_nonnormal_report <- function(data_file, col_name, n, lsl, usl,
                                      x_bar, x_med, s,
                                      p_lo, p_med, p_hi,
                                      Pp_pct, Ppk_pct,
                                      pct_above, pct_below,
                                      sw_stat, sw_p, normal_flag,
                                      verdict, png_path) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates", "pv_report_template.html")
  if (!file.exists(sentinel)) {
    cat("⚠ --report requires the JR Anchored Validation Pack.\n")
    cat("  Install the pack and re-run to generate the Process Validation Report.\n")
    return(invisible(NULL))
  }

  ts         <- format(Sys.time(), "%Y%m%d_%H%M%S")
  report_id  <- paste0("VR-CAP-NN-", ts)
  generated  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Embed chart as base64
  chart_html <- ""
  if (!is.null(png_path) && file.exists(png_path)) {
    b64 <- base64enc::base64encode(png_path)
    chart_html <- sprintf(
      '<div class="chart-wrap"><img src="data:image/png;base64,%s" alt="Capability chart"/></div>',
      b64
    )
  }

  lsl_str <- if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl)
  usl_str <- if (is.na(usl)) "(none)" else sprintf("%.4f", usl)
  has_both <- !is.na(lsl) && !is.na(usl)

  # Verdict class / colour
  is_pass <- grepl("EXCELLENT|CAPABLE", verdict) && !grepl("NOT", verdict)
  verdict_class  <- if (is_pass) "verdict verdict-pass" else "verdict verdict-fail"
  verdict_symbol <- if (is_pass) "✅" else "❌"
  verdict_color  <- if (is_pass) "color:#155724" else "color:#721c24"

  acceptance <- "Ppk (percentile method) ≥ 1.33. Process spread estimated from the 0.135th and 99.865th sample percentiles (ISO 22514-2 / AIAG), equivalent to ±3σ boundaries for a normal distribution."

  spec_rows <- sprintf(
    "<tr><td class=\"l\">LSL</td><td>%s</td></tr>\n<tr><td class=\"l\">USL</td><td>%s</td></tr>",
    lsl_str, usl_str
  )

  normality_note <- if (normal_flag) {
    sprintf("Shapiro-Wilk W = %.4f, p = %.4f (≥ 0.05) — data may be approximately normal. Consider jrc_cap_normal.", sw_stat, sw_p)
  } else {
    sprintf("Shapiro-Wilk W = %.4f, p = %.4f (< 0.05) — non-normal distribution confirmed.", sw_stat, sw_p)
  }

  method_rows <- paste0(
    "<tr><td class=\"l\">Method</td>",
    "<td>Percentile method (ISO 22514-2 / AIAG). Process spread estimated from sample P0.135 and P99.865 percentiles, ",
    "which correspond to the ±3σ boundaries of a normal distribution.</td></tr>\n",
    "<tr><td class=\"l\">Key Percentiles</td>",
    "<td>P0.135 (low tail), P50 (median), P99.865 (high tail)</td></tr>\n",
    "<tr><td class=\"l\">Ppk Formula</td>",
    "<td>Ppk = min[(USL − P50) / (P99.865 − P50), (P50 − LSL) / (P50 − P0.135)]</td></tr>\n",
    "<tr><td class=\"l\">Normality Test</td>",
    sprintf("<td>%s</td></tr>", normality_note),
    "<tr><td class=\"l\">Pass Criterion</td>",
    "<td>Ppk (percentile) ≥ 1.33</td></tr>"
  )

  pp_row    <- if (!is.na(Pp_pct)) sprintf("<tr><td class=\"l\">Pp (percentile)</td><td>%.4f</td></tr>", Pp_pct) else ""
  below_row <- if (!is.na(pct_below)) sprintf("<tr><td class=\"l\">Observed %% Below LSL</td><td>%.2f%%</td></tr>", pct_below) else ""
  above_row <- if (!is.na(pct_above)) sprintf("<tr><td class=\"l\">Observed %% Above USL</td><td>%.2f%%</td></tr>", pct_above) else ""

  results_rows <- paste(
    sprintf("<tr><td class=\"l\">Observations (n)</td><td>%d</td></tr>", n),
    sprintf("<tr><td class=\"l\">Mean</td><td>%.4f</td></tr>", x_bar),
    sprintf("<tr><td class=\"l\">Median (P50)</td><td>%.4f</td></tr>", x_med),
    sprintf("<tr><td class=\"l\">SD</td><td>%.4f</td></tr>", s),
    sprintf("<tr><td class=\"l\">P0.135 (low tail)</td><td>%.4f</td></tr>", as.numeric(p_lo)),
    sprintf("<tr><td class=\"l\">P99.865 (high tail)</td><td>%.4f</td></tr>", as.numeric(p_hi)),
    sprintf("<tr><td class=\"l\">Estimated Spread (P99.865 − P0.135)</td><td>%.4f</td></tr>",
            as.numeric(p_hi) - as.numeric(p_lo)),
    pp_row,
    sprintf("<tr><td class=\"l\">Ppk (percentile)</td><td>%.4f</td></tr>", Ppk_pct),
    below_row,
    above_row,
    sep = "\n"
  )

  verdict_html <- sprintf("%s Process validation outcome: %s",
                          verdict_symbol,
                          if (is_pass) "PASS" else "FAIL")

  script_ver <- "jrc_cap_nonnormal v1.1 — JR Anchored"
  footer_txt <- sprintf("Generated by %s — %s", script_ver, generated)

  html <- readLines(sentinel, warn = FALSE)
  html <- paste(html, collapse = "\n")

  html <- gsub("{{subtitle}}",
               "Process Capability Analysis — Non-Normal Data (Percentile Method)", html, fixed = TRUE)
  html <- gsub("{{report_id}}",        report_id,        html, fixed = TRUE)
  html <- gsub("{{generated}}",        generated,        html, fixed = TRUE)
  html <- gsub("{{script_version}}",   script_ver,       html, fixed = TRUE)
  html <- gsub("{{acceptance_criterion}}", acceptance,    html, fixed = TRUE)
  html <- gsub("{{data_file}}",        basename(data_file), html, fixed = TRUE)
  html <- gsub("{{col_name}}",         col_name,         html, fixed = TRUE)
  html <- gsub("{{n}}",                as.character(n),  html, fixed = TRUE)
  html <- gsub("{{spec_rows}}",        spec_rows,        html, fixed = TRUE)
  html <- gsub("{{method_rows}}",      method_rows,      html, fixed = TRUE)
  html <- gsub("{{results_rows}}",     results_rows,     html, fixed = TRUE)
  html <- gsub("{{verdict_class}}",    verdict_class,    html, fixed = TRUE)
  html <- gsub("{{verdict_html}}",     verdict_html,     html, fixed = TRUE)
  html <- gsub("{{chart_html}}",       chart_html,       html, fixed = TRUE)
  html <- gsub("{{verdict_color}}",    verdict_color,    html, fixed = TRUE)
  html <- gsub("{{verdict_short}}",
               if (is_pass) "✅ PASS" else "❌ FAIL", html, fixed = TRUE)
  html <- gsub("{{footer}}",           footer_txt,       html, fixed = TRUE)

  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(ts, "_cap_nonnormal_pv_report.html"))
  writeLines(html, out_path)
  cat(sprintf("✨ PV Report saved to: %s\n", out_path))

  # Write JSON sidecar for Word report generator
  json_path <- sub("\\.html$", "_data.json", out_path)

  jvs <- function(x) {
    x <- gsub("\\\\", "\\\\\\\\", as.character(x))
    x <- gsub('"',    '\\\\"',    x)
    paste0('"', x, '"')
  }
  jvn <- function(x, fmt = "%.4f") {
    if (is.null(x) || (length(x) == 1L && is.na(x))) "null"
    else sprintf(fmt, as.numeric(x))
  }
  jvb <- function(x) if (isTRUE(x)) "true" else "false"

  norm_note_json <- if (normal_flag) {
    sprintf("Shapiro-Wilk W = %.4f, p = %.4f (>= 0.05) - data may be approximately normal. Consider jrc_cap_normal.", sw_stat, sw_p)
  } else {
    sprintf("Shapiro-Wilk W = %.4f, p = %.4f (< 0.05) - non-normal distribution confirmed.", sw_stat, sw_p)
  }

  method_rows <- paste0(
    '    {"label": "Method",',
    ' "value": "Percentile method (ISO 22514-2 / AIAG). Process spread estimated from sample P0.135 and P99.865',
    ' percentiles, equivalent to +/-3 sigma boundaries for a normal distribution."},\n',
    '    {"label": "Key Percentiles", "value": "P0.135 (low tail), P50 (median), P99.865 (high tail)"},\n',
    '    {"label": "Ppk Formula", "value": "Ppk = min[(USL - P50) / (P99.865 - P50), (P50 - LSL) / (P50 - P0.135)]"},\n',
    sprintf('    {"label": "Normality Test", "value": %s},\n', jvs(norm_note_json)),
    '    {"label": "Pass Criterion", "value": "Ppk (percentile) >= 1.33"}'
  )

  res_parts <- c(
    sprintf('    {"label": "Observations (n)",              "value": "%d"}', n),
    sprintf('    {"label": "Mean",                          "value": "%.4f"}', x_bar),
    sprintf('    {"label": "Median (P50)",                  "value": "%.4f"}', x_med),
    sprintf('    {"label": "SD",                            "value": "%.4f"}', s),
    sprintf('    {"label": "P0.135 (low tail)",             "value": "%.4f"}', as.numeric(p_lo)),
    sprintf('    {"label": "P99.865 (high tail)",           "value": "%.4f"}', as.numeric(p_hi)),
    sprintf('    {"label": "Estimated Spread (P99.865 - P0.135)", "value": "%.4f"}',
            as.numeric(p_hi) - as.numeric(p_lo))
  )
  if (!is.na(Pp_pct)) res_parts <- c(res_parts, sprintf('    {"label": "Pp (percentile)", "value": "%.4f"}', Pp_pct))
  res_parts <- c(res_parts, sprintf('    {"label": "Ppk (percentile)", "value": "%.4f"}', Ppk_pct))
  if (!is.na(pct_below)) res_parts <- c(res_parts, sprintf('    {"label": "Observed %% Below LSL", "value": "%.2f%%"}', pct_below))
  if (!is.na(pct_above)) res_parts <- c(res_parts, sprintf('    {"label": "Observed %% Above USL", "value": "%.2f%%"}', pct_above))
  results_rows <- paste(res_parts, collapse = ",\n")

  json_lines <- c(
    "{",
    sprintf('  "report_type":          "pv",'),
    sprintf('  "script":               "jrc_cap_nonnormal",'),
    sprintf('  "version":              "1.1",'),
    sprintf('  "report_id":            %s,', jvs(report_id)),
    sprintf('  "generated":            %s,', jvs(generated)),
    sprintf('  "subtitle":             %s,', jvs("Process Capability Analysis - Non-Normal Data (Percentile Method)")),
    sprintf('  "data_file":            %s,', jvs(basename(data_file))),
    sprintf('  "col_name":             %s,', jvs(col_name)),
    sprintf('  "n":                    %d,', n),
    sprintf('  "lsl":                  %s,', jvn(lsl)),
    sprintf('  "usl":                  %s,', jvn(usl)),
    sprintf('  "acceptance_criterion": %s,', jvs(acceptance)),
    sprintf('  "method_rows": [\n%s\n  ],', method_rows),
    sprintf('  "results_rows": [\n%s\n  ],', results_rows),
    sprintf('  "verdict":              %s,', jvs(verdict)),
    sprintf('  "verdict_pass":         %s,', jvb(is_pass)),
    sprintf('  "png_path":             %s',  jvs(gsub("\\\\", "/", png_path))),
    "}"
  )

  con <- file(json_path, encoding = "UTF-8")
  writeLines(json_lines, con)
  close(con)
  cat(sprintf("📄 Report data saved to: %s\n", json_path))
  pack_py <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "pack", "jr_pack.py")
  if (file.exists(pack_py)) {
    ret       <- system2("python3",
                         args   = c(shQuote(pack_py), "deliverables", "pv-report",
                                    "--json", shQuote(json_path)),
                         stdout = TRUE, stderr = TRUE)
    exit_code <- attr(ret, "status")
    if (is.null(exit_code)) exit_code <- 0L
    cat(paste(ret, collapse = "\n"), "\n")
    if (exit_code != 0L) {
      cat(sprintf("   Retry manually: jr_pack deliverables pv-report --json %s\n", json_path))
    } else {
      docx_line <- grep("saved to:", ret, value = TRUE)
      if (length(docx_line) > 0L)
        jr_log_report(trimws(sub(".*saved to:\\s*", "", docx_line[1L])))
      if (file.exists(out_path))  file.remove(out_path)
      if (file.exists(json_path)) file.remove(json_path)
    }
  } else {
    cat(sprintf("   Run: jr_pack deliverables pv-report --json %s\n", json_path))
  }

  invisible(c(html = out_path, json = json_path))
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
if (!file.exists(data_file)) {
  stop(paste("❌ File not found:", data_file))
}

df <- tryCatch(
  read.csv(data_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("❌ Could not read CSV file:", e$message))
)

if (!col_name %in% names(df)) {
  stop(paste("❌ Column not found in CSV:", col_name))
}

x_raw <- suppressWarnings(as.numeric(df[[col_name]]))
if (all(is.na(x_raw))) stop(paste("❌ Column", col_name, "is not numeric."))

x <- x_raw[!is.na(x_raw)]
n <- length(x)

if (n < 5) {
  stop(paste("❌ Need at least 5 observations. Found:", n))
}

# ---------------------------------------------------------------------------
# Normality check (advisory only — does not block execution)
# ---------------------------------------------------------------------------
sw_result <- shapiro.test(x)
sw_p      <- sw_result$p.value
normal_flag <- sw_p >= 0.05

if (normal_flag) {
  cat(sprintf("⚠ Note: Shapiro-Wilk p = %.4f (≥ 0.05). Data may be approximately normal.\n", sw_p))
  cat("   Consider jrc_cap_normal for a within-sigma Cpk analysis.\n\n")
} else {
  cat(sprintf("  Shapiro-Wilk: W = %.4f, p = %.4f (< 0.05) — non-normal distribution confirmed.\n\n",
              sw_result$statistic, sw_p))
}

# ---------------------------------------------------------------------------
# Computation — percentile method
# ---------------------------------------------------------------------------

x_bar   <- mean(x)
x_med   <- median(x)
s       <- sd(x)

# Key percentiles: 0.135% and 99.865% correspond to ±3σ for normal
p_lo    <- quantile(x, probs = 0.00135, type = 7)   # 0.135th percentile
p_hi    <- quantile(x, probs = 0.99865, type = 7)   # 99.865th percentile
p_med   <- quantile(x, probs = 0.50,   type = 7)

has_both   <- !is.na(lsl) && !is.na(usl)
spec_width <- if (has_both) usl - lsl else NA_real_

# Pp (percentile method — requires both limits)
Pp_pct <- if (has_both) spec_width / (p_hi - p_lo) else NA_real_

# Ppk components (percentile method)
ppk_u <- if (!is.na(usl)) (usl - p_med) / (p_hi - p_med) else NA_real_
ppk_l <- if (!is.na(lsl)) (p_med - lsl) / (p_med - p_lo) else NA_real_
Ppk_pct <- min(c(ppk_u, ppk_l), na.rm = TRUE)

# Observed % out of spec
pct_above <- if (!is.na(usl)) mean(x > usl) * 100 else NA_real_
pct_below <- if (!is.na(lsl)) mean(x < lsl) * 100 else NA_real_

# Verdict
verdict <- if (Ppk_pct >= 1.67) {
  "EXCELLENT  (Ppk ≥ 1.67)"
} else if (Ppk_pct >= 1.33) {
  "CAPABLE    (Ppk ≥ 1.33)"
} else if (Ppk_pct >= 1.00) {
  "MARGINAL   (1.00 ≤ Ppk < 1.33)"
} else {
  "NOT CAPABLE (Ppk < 1.00)"
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Process Capability Analysis (Non-Normal, Percentile Method)\n")
cat(sprintf("  File: %s   Col: %s   n = %d\n",
            basename(data_file), col_name, n))
cat(sprintf("  LSL: %s   USL: %s\n",
            if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl),
            if (is.na(usl)) "(none)" else sprintf("%.4f", usl)))
cat("=================================================================\n\n")

cat("  Descriptives:\n")
cat(sprintf("    Mean:               %.4f\n",  x_bar))
cat(sprintf("    Median (P50):       %.4f\n",  x_med))
cat(sprintf("    SD:                 %.4f\n",  s))
cat(sprintf("    Min:                %.4f\n",  min(x)))
cat(sprintf("    Max:                %.4f\n",  max(x)))
cat("\n")

cat("  Distribution percentiles (equivalent to ±3σ boundaries):\n")
cat(sprintf("    P0.135  (low tail):  %.4f\n",  as.numeric(p_lo)))
cat(sprintf("    P50     (median):    %.4f\n",  as.numeric(p_med)))
cat(sprintf("    P99.865 (high tail): %.4f\n",  as.numeric(p_hi)))
cat(sprintf("    Estimated spread:    %.4f  (P99.865 − P0.135)\n\n",
            as.numeric(p_hi) - as.numeric(p_lo)))

cat("  Performance indices (percentile method):\n")
if (!is.na(Pp_pct))  cat(sprintf("    Pp  (percentile):   %.4f\n", Pp_pct))
cat(sprintf("    Ppk (percentile):   %.4f\n", Ppk_pct))
cat("\n")

cat("  Observed non-conformance:\n")
if (!is.na(pct_below)) cat(sprintf("    Below LSL:          %.2f%%\n", pct_below))
if (!is.na(pct_above)) cat(sprintf("    Above USL:          %.2f%%\n", pct_above))
cat("\n")

cat(sprintf("  Normality (Shapiro-Wilk): W = %.4f, p = %.4f\n\n",
            sw_result$statistic, sw_p))

cat("--- Verdict ---------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

cat("  Note: Percentile method uses sample quantiles to estimate process\n")
cat("  spread without assuming normality. Ppk ≥ 1.33 is a common\n")
cat("  acceptance criterion for non-normal process validation.\n\n")

# ---------------------------------------------------------------------------
# Plot — histogram with KDE and spec limits
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_HIST <- "#F5C8A0"
COL_KDE  <- "#C0392B"
COL_LSL  <- "#C0392B"
COL_USL  <- "#C0392B"
COL_MEAN <- "#1A1A2E"
COL_P    <- "#2E5BBA"
GRID_COL <- "#EEEEEE"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9)
  )

plot_df <- data.frame(value = x)
bw      <- max(diff(range(x)) / 30, s / 5)

# KDE scaled to histogram counts
kde       <- density(x, adjust = 1.0)
kde_scale <- n * bw
kde_df    <- data.frame(x = kde$x, y = kde$y * kde_scale)

cap_label <- if (!is.na(Pp_pct)) {
  sprintf("Pp=%.2f  Ppk=%.2f  (percentile)", Pp_pct, Ppk_pct)
} else {
  sprintf("Ppk=%.2f  (percentile)", Ppk_pct)
}

p_hist <- ggplot(plot_df, aes(x = value)) +
  geom_histogram(binwidth = bw, fill = COL_HIST, color = "white", alpha = 0.9) +
  geom_line(data = kde_df, aes(x = x, y = y),
            color = COL_KDE, linewidth = 1) +
  geom_vline(xintercept = x_bar, linetype = "solid",
             color = COL_MEAN, linewidth = 0.8) +
  labs(
    title = sprintf("Process Capability (Non-Normal)  |  %s", cap_label),
    x     = col_name,
    y     = "Count"
  ) +
  theme_jr

if (!is.na(lsl)) {
  p_hist <- p_hist +
    geom_vline(xintercept = lsl, linetype = "dashed",
               color = COL_LSL, linewidth = 1) +
    annotate("text", x = lsl, y = Inf,
             label = sprintf("LSL\n%.4g", lsl),
             hjust = 1.1, vjust = 1.5, color = COL_LSL, size = 3, fontface = "bold")
}
if (!is.na(usl)) {
  p_hist <- p_hist +
    geom_vline(xintercept = usl, linetype = "dashed",
               color = COL_USL, linewidth = 1) +
    annotate("text", x = usl, y = Inf,
             label = sprintf("USL\n%.4g", usl),
             hjust = -0.1, vjust = 1.5, color = COL_USL, size = 3, fontface = "bold")
}
# P0.135 and P99.865 markers
p_hist <- p_hist +
  geom_vline(xintercept = as.numeric(p_lo), linetype = "dotted",
             color = COL_P, linewidth = 0.7) +
  geom_vline(xintercept = as.numeric(p_hi), linetype = "dotted",
             color = COL_P, linewidth = 0.7)

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_cap_nonnormal.png"))

cat(sprintf("✨ Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1600, res = 180, bg = BG)

grid.newpage()
pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("Cap Non-Normal  |  %s  |  n=%d  Ppk=%.4f  %s",
          basename(data_file), n, Ppk_pct, verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p_hist, vp = viewport())
popViewport()

dev.off()

cat("✅ Done.\n")

# ---------------------------------------------------------------------------
# Report and output hashes
# ---------------------------------------------------------------------------
report_path <- NULL
if (want_report) {
  report_path <- save_cap_nonnormal_report(
    data_file, col_name, n, lsl, usl,
    x_bar, x_med, s,
    p_lo, p_med, p_hi,
    Pp_pct, Ppk_pct,
    pct_above, pct_below,
    sw_result$statistic, sw_p, normal_flag,
    verdict, out_file
  )
}

jr_log_output_hashes(c(out_file))
