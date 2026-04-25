# =============================================================================
# jrc_cap_normal.R
# JR Validated Environment — Process Capability module
#
# Process Capability Analysis for normally distributed data.
# Computes Cp, Cpk, Pp, Ppk, Cpm (Taguchi) using within-subgroup (MR-based)
# and overall (sample SD) estimates of process spread.
#
# Usage: jrc_cap_normal <data.csv> <col> <lsl> <usl> [--report]
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
  stop("Usage: jrc_cap_normal <data.csv> <col> <lsl> <usl> [--report]\n  Use '-' for <lsl> or <usl> to analyse one-sided.")
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
save_cap_normal_report <- function(data_file, col_name, n, lsl, usl,
                                   x_bar, s_overall, sigma_w,
                                   Cp, Cpk, Pp, Ppk, Cpm,
                                   sigma_level, ppm_total,
                                   ppm_above, ppm_below,
                                   verdict, png_path) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates", "pv_report_template.html")
  if (!file.exists(sentinel)) {
    cat("⚠ --report requires the JR Anchored Validation Pack.\n")
    cat("  Install the pack and re-run to generate the Process Validation Report.\n")
    return(invisible(NULL))
  }

  ts         <- format(Sys.time(), "%Y%m%d_%H%M%S")
  report_id  <- paste0("VR-CAP-", ts)
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
  verdict_class <- if (is_pass) "verdict verdict-pass" else "verdict verdict-fail"
  verdict_symbol <- if (is_pass) "✅" else "❌"
  verdict_color  <- if (is_pass) "color:#155724" else "color:#721c24"

  # Acceptance criterion
  acceptance <- if (has_both) {
    "Cpk ≥ 1.33 (process capability index, within-subgroup sigma). Demonstrates the process consistently produces output within specification limits with at least a 1.33 safety margin."
  } else {
    "Cpk ≥ 1.33 (one-sided specification)."
  }

  # Spec rows
  spec_rows <- sprintf(
    "<tr><td class=\"l\">LSL</td><td>%s</td></tr>\n<tr><td class=\"l\">USL</td><td>%s</td></tr>",
    lsl_str, usl_str
  )

  # Method rows
  method_rows <- paste0(
    "<tr><td class=\"l\">Method</td>",
    "<td>Shewhart process capability analysis using the moving range (MR/d2) estimate of within-subgroup sigma for Cp and Cpk, ",
    "and the overall sample standard deviation for Pp and Ppk.</td></tr>\n",
    "<tr><td class=\"l\">Within-Sigma Estimator</td>",
    "<td>σ̂ = MR̅ / d2, where d2 = 1.128 for a moving range of n = 2.</td></tr>\n",
    "<tr><td class=\"l\">Capability Index Formula</td>",
    "<td>Cpk = min[(USL − X̅) / (3σ̂), (X̅ − LSL) / (3σ̂)]</td></tr>\n",
    "<tr><td class=\"l\">Pass Criterion</td>",
    "<td>Cpk ≥ 1.33</td></tr>"
  )

  # Results rows
  cp_row  <- if (!is.na(Cp))  sprintf("<tr><td class=\"l\">Cp</td><td>%.4f</td></tr>", Cp)  else ""
  cpm_row <- if (!is.na(Cpm)) sprintf("<tr><td class=\"l\">Cpm (Taguchi)</td><td>%.4f</td></tr>", Cpm) else ""
  pp_row  <- if (!is.na(Pp))  sprintf("<tr><td class=\"l\">Pp</td><td>%.4f</td></tr>", Pp)  else ""
  ppm_row <- if (!is.na(ppm_total)) {
    parts <- c()
    if (!is.na(ppm_above)) parts <- c(parts, sprintf("%.1f above USL", ppm_above))
    if (!is.na(ppm_below)) parts <- c(parts, sprintf("%.1f below LSL", ppm_below))
    sprintf("<tr><td class=\"l\">Est. PPM Out-of-Spec</td><td>%.1f total (%s)</td></tr>",
            ppm_total, paste(parts, collapse = "; "))
  } else ""

  results_rows <- paste(
    sprintf("<tr><td class=\"l\">Observations (n)</td><td>%d</td></tr>", n),
    sprintf("<tr><td class=\"l\">Mean (X̅)</td><td>%.4f</td></tr>", x_bar),
    sprintf("<tr><td class=\"l\">SD — Overall (s)</td><td>%.4f</td></tr>", s_overall),
    sprintf("<tr><td class=\"l\">SD — Within (σ̂, MR/d2)</td><td>%.4f</td></tr>", sigma_w),
    cp_row,
    sprintf("<tr><td class=\"l\">Cpk</td><td>%.4f</td></tr>", Cpk),
    cpm_row,
    pp_row,
    sprintf("<tr><td class=\"l\">Ppk</td><td>%.4f</td></tr>", Ppk),
    sprintf("<tr><td class=\"l\">Sigma Level</td><td>%.2fσ</td></tr>", sigma_level),
    ppm_row,
    sep = "\n"
  )

  verdict_html <- sprintf("%s Process validation outcome: %s",
                          verdict_symbol,
                          if (is_pass) "PASS" else "FAIL")

  script_ver <- "jrc_cap_normal v1.1 — JR Anchored"
  footer_txt <- sprintf("Generated by %s — %s", script_ver, generated)

  html <- readLines(sentinel, warn = FALSE)
  html <- paste(html, collapse = "\n")

  html <- gsub("{{subtitle}}",
               "Process Capability Analysis — Normal Data (Cp/Cpk/Pp/Ppk)", html, fixed = TRUE)
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
                        paste0(ts, "_cap_normal_pv_report.html"))
  writeLines(html, out_path)
  cat(sprintf("✨ PV Report (HTML) saved to: %s\n", out_path))

  # Write JSON sidecar for Word report generator
  json_path <- sub("\\.html$", "_data.json", out_path)

  jvs <- function(x) {          # JSON string (escape quotes and backslashes)
    x <- gsub("\\\\", "\\\\\\\\", as.character(x))
    x <- gsub('"',    '\\\\"',    x)
    paste0('"', x, '"')
  }
  jvn <- function(x, fmt = "%.4f") {   # JSON number or null
    if (is.null(x) || (length(x) == 1L && is.na(x))) "null"
    else sprintf(fmt, as.numeric(x))
  }
  jvb <- function(x) if (isTRUE(x)) "true" else "false"  # JSON boolean

  method_rows <- paste0(
    '    {"label": "Method",',
    ' "value": "Shewhart process capability analysis using the moving range (MR/d2) estimate',
    ' of within-subgroup sigma for Cp and Cpk, and the overall sample standard deviation for Pp and Ppk."},\n',
    '    {"label": "Within-Sigma Estimator",',
    ' "value": "sigma_w = MR_bar / d2, where d2 = 1.128 for a moving range of n = 2."},\n',
    '    {"label": "Capability Index Formula",',
    ' "value": "Cpk = min[(USL - X_bar) / (3*sigma_w), (X_bar - LSL) / (3*sigma_w)]"},\n',
    '    {"label": "Pass Criterion", "value": "Cpk >= 1.33"}'
  )

  res_parts <- c(
    sprintf('    {"label": "Observations (n)", "value": "%d"}', n),
    sprintf('    {"label": "Mean (X_bar)",     "value": "%.4f"}', x_bar),
    sprintf('    {"label": "SD - Overall (s)", "value": "%.4f"}', s_overall),
    sprintf('    {"label": "SD - Within (MR/d2)", "value": "%.4f"}', sigma_w)
  )
  if (!is.na(Cp))  res_parts <- c(res_parts, sprintf('    {"label": "Cp",  "value": "%.4f"}', Cp))
  res_parts <- c(res_parts,   sprintf('    {"label": "Cpk", "value": "%.4f"}', Cpk))
  if (!is.na(Cpm)) res_parts <- c(res_parts, sprintf('    {"label": "Cpm (Taguchi)", "value": "%.4f"}', Cpm))
  if (!is.na(Pp))  res_parts <- c(res_parts, sprintf('    {"label": "Pp",  "value": "%.4f"}', Pp))
  res_parts <- c(res_parts,   sprintf('    {"label": "Ppk", "value": "%.4f"}', Ppk))
  res_parts <- c(res_parts,   sprintf('    {"label": "Sigma Level", "value": "%.2f"}', sigma_level))
  if (!is.na(ppm_total)) {
    ppm_detail <- c()
    if (!is.na(ppm_above)) ppm_detail <- c(ppm_detail, sprintf("%.1f above USL", ppm_above))
    if (!is.na(ppm_below)) ppm_detail <- c(ppm_detail, sprintf("%.1f below LSL", ppm_below))
    res_parts <- c(res_parts,
      sprintf('    {"label": "Est. PPM Out-of-Spec", "value": "%.1f total (%s)"}',
              ppm_total, paste(ppm_detail, collapse = "; ")))
  }
  results_rows <- paste(res_parts, collapse = ",\n")

  json_lines <- c(
    "{",
    sprintf('  "report_type":         "pv",'),
    sprintf('  "script":              "jrc_cap_normal",'),
    sprintf('  "version":             "1.1",'),
    sprintf('  "report_id":           %s,',   jvs(report_id)),
    sprintf('  "generated":           %s,',   jvs(generated)),
    sprintf('  "subtitle":            %s,',   jvs("Process Capability Analysis - Normal Data (Cp/Cpk/Pp/Ppk)")),
    sprintf('  "data_file":           %s,',   jvs(basename(data_file))),
    sprintf('  "col_name":            %s,',   jvs(col_name)),
    sprintf('  "n":                   %d,',   n),
    sprintf('  "lsl":                 %s,',   jvn(lsl)),
    sprintf('  "usl":                 %s,',   jvn(usl)),
    sprintf('  "acceptance_criterion": %s,',  jvs(acceptance)),
    sprintf('  "method_rows": [\n%s\n  ],',   method_rows),
    sprintf('  "results_rows": [\n%s\n  ],',  results_rows),
    sprintf('  "verdict":             %s,',   jvs(verdict)),
    sprintf('  "verdict_pass":        %s,',   jvb(is_pass)),
    sprintf('  "png_path":            %s',    jvs(gsub("\\\\", "/", png_path))),
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

# Check spec limit violations
if (!is.na(lsl) && any(x < lsl)) {
  n_below <- sum(x < lsl)
  cat(sprintf("⚠ Warning: %d observation(s) below LSL.\n", n_below))
}
if (!is.na(usl) && any(x > usl)) {
  n_above <- sum(x > usl)
  cat(sprintf("⚠ Warning: %d observation(s) above USL.\n", n_above))
}

# ---------------------------------------------------------------------------
# Computation
# ---------------------------------------------------------------------------

# Basic descriptives
x_bar  <- mean(x)
s_overall <- sd(x)

# Within-subgroup sigma (moving range estimate for individual data)
MR       <- abs(diff(x))
MR_bar   <- mean(MR)
d2       <- 1.128          # d2 constant for n=2 (moving range of 2)
sigma_w  <- MR_bar / d2

# Spec width
has_both <- !is.na(lsl) && !is.na(usl)
spec_width <- if (has_both) usl - lsl else NA_real_

# --- Cp / Pp (require both limits) ---
Cp  <- if (has_both) spec_width / (6 * sigma_w)   else NA_real_
Pp  <- if (has_both) spec_width / (6 * s_overall)  else NA_real_

# --- Cpk ---
cpk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * sigma_w)   else NA_real_
cpk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * sigma_w)   else NA_real_
Cpk   <- min(c(cpk_u, cpk_l), na.rm = TRUE)

# --- Ppk ---
ppk_u <- if (!is.na(usl)) (usl - x_bar) / (3 * s_overall) else NA_real_
ppk_l <- if (!is.na(lsl)) (x_bar - lsl) / (3 * s_overall) else NA_real_
Ppk   <- min(c(ppk_u, ppk_l), na.rm = TRUE)

# --- Cpm (Taguchi — requires both limits; target = midpoint) ---
target <- if (has_both) (lsl + usl) / 2 else x_bar
Cpm    <- if (has_both) {
  spec_width / (6 * sqrt(s_overall^2 + (x_bar - target)^2))
} else NA_real_

# --- Sigma level ---
sigma_level <- Cpk * 3

# --- PPM estimate ---
if (!is.na(usl) && !is.na(lsl)) {
  ppm_above <- pnorm((usl - x_bar) / sigma_w, lower.tail = FALSE) * 1e6
  ppm_below <- pnorm((lsl - x_bar) / sigma_w, lower.tail = TRUE)  * 1e6
  ppm_total <- ppm_above + ppm_below
} else if (!is.na(usl)) {
  ppm_above <- pnorm((usl - x_bar) / sigma_w, lower.tail = FALSE) * 1e6
  ppm_below <- NA_real_
  ppm_total <- ppm_above
} else {
  ppm_below <- pnorm((lsl - x_bar) / sigma_w, lower.tail = TRUE) * 1e6
  ppm_above <- NA_real_
  ppm_total <- ppm_below
}

# --- Verdict ---
verdict <- if (Cpk >= 1.67) {
  "EXCELLENT  (Cpk ≥ 1.67)"
} else if (Cpk >= 1.33) {
  "CAPABLE    (Cpk ≥ 1.33)"
} else if (Cpk >= 1.00) {
  "MARGINAL   (1.00 ≤ Cpk < 1.33)"
} else {
  "NOT CAPABLE (Cpk < 1.00)"
}

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  Process Capability Analysis (Normal)\n")
cat(sprintf("  File: %s   Col: %s   n = %d\n",
            basename(data_file), col_name, n))
cat(sprintf("  LSL: %s   USL: %s\n",
            if (is.na(lsl)) "(none)" else sprintf("%.4f", lsl),
            if (is.na(usl)) "(none)" else sprintf("%.4f", usl)))
cat("=================================================================\n\n")

cat("  Descriptives:\n")
cat(sprintf("    Mean (X-bar):       %.4f\n",  x_bar))
cat(sprintf("    SD (overall, s):    %.4f\n",  s_overall))
cat(sprintf("    SD (within, MR/d2): %.4f\n",  sigma_w))
cat(sprintf("    Min:                %.4f\n",  min(x)))
cat(sprintf("    Max:                %.4f\n",  max(x)))
cat("\n")

cat("  Capability indices (within sigma):\n")
if (!is.na(Cp))  cat(sprintf("    Cp:                 %.4f\n", Cp))
cat(sprintf("    Cpk:                %.4f\n", Cpk))
if (!is.na(Cpm)) cat(sprintf("    Cpm (Taguchi):      %.4f\n", Cpm))
cat("\n")

cat("  Performance indices (overall sigma):\n")
if (!is.na(Pp))  cat(sprintf("    Pp:                 %.4f\n", Pp))
cat(sprintf("    Ppk:                %.4f\n", Ppk))
cat("\n")

cat(sprintf("  Sigma level:          %.2fσ\n", sigma_level))
if (!is.na(ppm_total)) {
  cat(sprintf("  Est. PPM out-of-spec: %.1f\n", ppm_total))
}
cat("\n")

cat("--- Verdict ---------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

cat("  Thresholds:\n")
cat("    Cpk ≥ 1.67  → excellent\n")
cat("    Cpk ≥ 1.33  → capable (typical FDA / ISO 13485 requirement)\n")
cat("    Cpk ≥ 1.00  → marginal (process meeting spec, but barely)\n")
cat("    Cpk < 1.00  → not capable\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
BG       <- "#FFFFFF"
COL_HIST <- "#AEC6E8"
COL_CURV <- "#2E5BBA"
COL_LSL  <- "#C0392B"
COL_USL  <- "#C0392B"
COL_MEAN <- "#1A1A2E"
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

plot_df  <- data.frame(value = x)
bw       <- max(diff(range(x)) / 30, s_overall / 5)

# Normal curve overlay (using within-sigma for Cpk line)
x_seq    <- seq(min(x) - 3 * s_overall, max(x) + 3 * s_overall, length.out = 400)
norm_df  <- data.frame(
  x = x_seq,
  y = dnorm(x_seq, mean = x_bar, sd = s_overall) * n * bw
)

cap_label <- if (!is.na(Cp)) {
  sprintf("Cp=%.2f  Cpk=%.2f  Pp=%.2f  Ppk=%.2f", Cp, Cpk, Pp, Ppk)
} else {
  sprintf("Cpk=%.2f  Ppk=%.2f", Cpk, Ppk)
}

p_hist <- ggplot(plot_df, aes(x = value)) +
  geom_histogram(binwidth = bw, fill = COL_HIST, color = "white", alpha = 0.9) +
  geom_line(data = norm_df, aes(x = x, y = y),
            color = COL_CURV, linewidth = 1) +
  geom_vline(xintercept = x_bar, linetype = "solid",
             color = COL_MEAN, linewidth = 0.8) +
  labs(
    title = sprintf("Process Capability (Normal)  |  %s", cap_label),
    x     = col_name,
    y     = "Count"
  ) +
  theme_jr

# Add spec limit lines
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

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_cap_normal.png"))

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
  sprintf("Cap Normal  |  %s  |  n=%d  X-bar=%.4f  s=%.4f  %s",
          basename(data_file), n, x_bar, s_overall, verdict),
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
report_paths <- character(0)
if (want_report) {
  report_paths <- save_cap_normal_report(
    data_file, col_name, n, lsl, usl,
    x_bar, s_overall, sigma_w,
    Cp, Cpk, Pp, Ppk, Cpm,
    sigma_level, ppm_total,
    ppm_above, ppm_below,
    verdict, out_file
  )
  if (is.null(report_paths)) report_paths <- character(0)
}

jr_log_output_hashes(c(out_file, report_paths))
