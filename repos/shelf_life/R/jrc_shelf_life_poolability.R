#!/usr/bin/env Rscript
#
# use as: Rscript jrc_shelf_life_poolability.R <data.csv>
#
# data.csv     CSV with three columns: batch, time, value.
#              'batch'  — batch identifier (any string or number).
#              'time'   — time point of measurement (numeric; same unit throughout).
#              'value'  — measured property value (numeric).
#              Minimum: 2 batches, 3 time points per batch.
#
# Needs only base R and ggplot2.
#
# Performs the ICH Q1E batch poolability analysis to determine whether
# stability data from multiple batches can be combined for a single shelf
# life estimate.
#
# Two-step ANCOVA approach (ICH Q1E Section 4.5):
#   Step 1 — Test batch-by-time interaction (H0: equal slopes).
#             alpha = 0.25 per ICH Q1E (conservative test to avoid pooling
#             when slopes differ).
#   Step 2 — If Step 1 not significant, test batch main effect (H0: equal
#             intercepts). alpha = 0.25.
#
# Decision:
#   Interaction significant  (p < 0.25)  -> DO NOT POOL. Batches have
#                                            different degradation rates.
#                                            Estimate shelf life per batch.
#   Intercept difference     (p < 0.25)  -> PARTIAL POOL. Same slope, use
#                                            the batch with the lowest (or
#                                            highest, per direction) projection.
#   Both not significant                 -> FULL POOL. Combine all batches
#                                            into a single regression.
#
# Saves a multi-panel PNG to ~/Downloads/ showing per-batch scatter and
# regression lines.
#
# Author: Joep Rous
# Version: 1.1

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]

if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
  cat("\nUsage: jrc_shelf_life_poolability <data.csv> [--report]\n\n")
  cat("  data.csv  CSV with columns: batch, time, value\n")
  cat("  --report  Generate HTML report (requires JR Anchored Validation Pack)\n\n")
  cat("Example: jrc_shelf_life_poolability stability_batches.csv\n\n")
  quit(status = 0)
}

csv_file <- args[1]

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------

renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library",
                      Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(base64enc)
}))

# ---------------------------------------------------------------------------
# Load and validate data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) {
  stop(paste("\u274c File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("batch", "time", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: batch, time, value"))
}

dat$batch <- as.factor(as.character(dat$batch))
dat$time  <- suppressWarnings(as.numeric(dat$time))
dat$value <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$time)))  stop("\u274c Non-numeric values in 'time' column.")
if (any(is.na(dat$value))) stop("\u274c Non-numeric values in 'value' column.")

n_batches <- nlevels(dat$batch)
if (n_batches < 2) {
  stop("\u274c At least 2 batches are required for poolability analysis.")
}

# Check minimum time points per batch
tp_per_batch <- tapply(dat$time, dat$batch, function(x) length(unique(x)))
if (any(tp_per_batch < 3)) {
  bad <- names(tp_per_batch)[tp_per_batch < 3]
  stop(paste("\u274c At least 3 time points per batch required. Insufficient data for batch(es):",
             paste(bad, collapse = ", ")))
}

n_total <- nrow(dat)

# ---------------------------------------------------------------------------
# ICH Q1E poolability analysis — two-step ANCOVA
# ---------------------------------------------------------------------------

ICH_ALPHA <- 0.25

# Step 1: full model with batch:time interaction
fit_interaction <- lm(value ~ batch * time, data = dat)
fit_parallel    <- lm(value ~ batch + time, data = dat)
fit_pooled      <- lm(value ~ time,         data = dat)

# Test interaction (batch slopes differ?)
anova_interaction <- anova(fit_parallel, fit_interaction)
p_interaction     <- anova_interaction$`Pr(>F)`[2]

# Test batch main effect (batch intercepts differ?) — only meaningful if interaction ns
anova_batch <- anova(fit_pooled, fit_parallel)
p_batch     <- anova_batch$`Pr(>F)`[2]

# Per-batch regressions for reporting
batch_fits <- lapply(levels(dat$batch), function(b) {
  sub_dat <- dat[dat$batch == b, ]
  fit     <- lm(value ~ time, data = sub_dat)
  cf      <- coef(fit)
  sm      <- summary(fit)
  list(
    batch     = b,
    n         = nrow(sub_dat),
    intercept = cf[1],
    slope     = cf[2],
    r2        = sm$r.squared,
    p_slope   = coef(sm)[2, "Pr(>|t|)"]
  )
})

# Poolability decision
if (p_interaction < ICH_ALPHA) {
  decision     <- "DO NOT POOL"
  decision_sym <- "\u274c"
  rationale    <- sprintf(
    "Batch-by-time interaction is significant (p = %.4f < %.2f).\n   Batches have different degradation rates. Estimate shelf life\n   separately for each batch and use the most conservative result.",
    p_interaction, ICH_ALPHA
  )
} else if (p_batch < ICH_ALPHA) {
  decision     <- "PARTIAL POOL"
  decision_sym <- "\u26a0\ufe0f"
  rationale    <- sprintf(
    "Slopes are similar (interaction p = %.4f >= %.2f) but intercepts\n   differ (batch p = %.4f < %.2f). Use the common slope with the batch\n   that has the lowest/worst projected value at the spec limit.",
    p_interaction, ICH_ALPHA, p_batch, ICH_ALPHA
  )
} else {
  decision     <- "FULL POOL"
  decision_sym <- "\u2705"
  rationale    <- sprintf(
    "Neither interaction (p = %.4f) nor batch main effect (p = %.4f)\n   is significant at alpha = %.2f. Combine all batches into a single\n   regression for shelf life estimation.",
    p_interaction, p_batch, ICH_ALPHA
  )
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat("\n")
cat("=================================================================\n")
cat("  Batch Poolability Analysis  (ICH Q1E Section 4.5)\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Batches:      %d\n", n_batches))
cat(sprintf("  Total obs:    %d\n", n_total))
cat(sprintf("  ICH Q1E alpha: %.2f  (conservative threshold for poolability)\n\n", ICH_ALPHA))

cat("--- Per-Batch Regressions ---------------------------------------\n")
cat(sprintf("  %-10s %6s %12s %12s %8s %10s\n",
            "Batch", "n", "Intercept", "Slope", "R\u00b2", "p (slope)"))
for (bf in batch_fits) {
  cat(sprintf("  %-10s %6d %12.4f %12.4f %8.4f %10.4f\n",
              bf$batch, bf$n, bf$intercept, bf$slope, bf$r2, bf$p_slope))
}
cat("\n")

cat("--- ANCOVA Summary ----------------------------------------------\n")
cat(sprintf("  Step 1 — Batch:time interaction:  F = %.3f,  p = %.4f  %s\n",
            anova_interaction$F[2],
            p_interaction,
            if (p_interaction < ICH_ALPHA) "  * significant" else "  ns"))
cat(sprintf("  Step 2 — Batch main effect:       F = %.3f,  p = %.4f  %s\n",
            anova_batch$F[2],
            p_batch,
            if (p_batch < ICH_ALPHA) "  * significant" else "  ns"))
cat("\n")

cat("--- Decision ----------------------------------------------------\n")
cat(sprintf("  %s  %s\n\n", decision_sym, decision))
cat(sprintf("  %s\n", rationale))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

BG       <- "#FFFFFF"
GRID_COL <- "#EEEEEE"

theme_jr <- theme_minimal(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = BG, color = NA),
    panel.background = element_rect(fill = BG, color = NA),
    panel.grid.major = element_line(color = GRID_COL),
    panel.grid.minor = element_blank(),
    plot.title       = element_text(size = 10, face = "bold"),
    axis.text        = element_text(size = 8),
    axis.title       = element_text(size = 9),
    legend.position  = "bottom"
  )

p <- ggplot(dat, aes(x = time, y = value, colour = batch)) +
  geom_point(size = 2, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.8, alpha = 0.15) +
  labs(
    title    = sprintf("Batch Poolability  |  Decision: %s", decision),
    subtitle = sprintf("Interaction p = %.4f  |  Batch main effect p = %.4f  |  ICH Q1E alpha = %.2f",
                       p_interaction, p_batch, ICH_ALPHA),
    x        = "Time",
    y        = "Value",
    colour   = "Batch"
  ) +
  theme_jr

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_shelf_life_poolability.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))
ggsave(out_file, plot = p, width = 8, height = 5, dpi = 150, bg = BG)

# ---------------------------------------------------------------------------
# HTML report (--report flag, requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------

save_poolability_report <- function(csv_file, n_batches, n_total, batch_fits,
                                     p_interaction, p_batch, ICH_ALPHA,
                                     decision, decision_sym, rationale,
                                     png_path) {
  he <- function(s) {
    s <- gsub("&", "&amp;",  as.character(s), fixed = TRUE)
    s <- gsub("<", "&lt;",   s, fixed = TRUE)
    s <- gsub(">", "&gt;",   s, fixed = TRUE)
    s
  }
  f4 <- function(x) sprintf("%.4f", x)

  dt_str    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  report_id <- paste0("VR-SHELF-POOL-", format(Sys.time(), "%Y%m%d-%H%M%S"))

  d_color <- switch(decision,
    "FULL POOL"    = "#155724",
    "PARTIAL POOL" = "#856404",
    "#721c24"
  )
  d_bg <- switch(decision,
    "FULL POOL"    = "#d4edda",
    "PARTIAL POOL" = "#fff3cd",
    "#f8d7da"
  )
  d_bdr <- switch(decision,
    "FULL POOL"    = "#c3e6cb",
    "PARTIAL POOL" = "#ffeeba",
    "#f5c6cb"
  )

  if (file.exists(png_path)) {
    b64     <- base64encode(png_path)
    img_tag <- paste0('<img src="data:image/png;base64,', b64,
                      '" alt="Batch poolability chart" width="100%" ',
                      'style="width:100%;height:auto;display:block;border:1px solid #ccc;">')
  } else {
    img_tag <- "<p><em>(Chart not available.)</em></p>"
  }

  batch_rows <- paste(sapply(batch_fits, function(bf) {
    paste0('<tr><td>', he(bf$batch), '</td>',
           '<td class="r">', he(bf$n), '</td>',
           '<td class="r">', f4(bf$intercept), '</td>',
           '<td class="r">', f4(bf$slope), '</td>',
           '<td class="r">', f4(bf$r2), '</td>',
           '<td class="r">', f4(bf$p_slope), '</td></tr>')
  }), collapse = "\n")

  css <- paste(c(
    "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}",
    "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1a1a1a;background:#fff;padding:24px}",
    ".report{background:#fff;max-width:900px;margin:0 auto;padding:40px 48px;border:1px solid #ccc;box-shadow:0 2px 10px rgba(0,0,0,.10)}",
    ".rpt-hdr{border-bottom:3px solid #1a3a6b;padding-bottom:14px;margin-bottom:24px}",
    ".rpt-hdr h1{font-size:1.45em;color:#1a3a6b;margin-bottom:2px}",
    ".rpt-hdr h2{font-size:1em;font-weight:normal;color:#555;margin-bottom:14px}",
    "table.meta{border-collapse:collapse}",
    "table.meta td{padding:3px 14px 3px 0;vertical-align:top;font-size:.91em}",
    "table.meta td.k{font-weight:600;color:#333;min-width:160px}",
    ".draft{color:#a00;font-weight:bold}",
    ".section{margin-top:26px}",
    ".sec-ttl{font-weight:700;color:#1a3a6b;border-bottom:1.5px solid #1a3a6b;padding-bottom:4px;margin-bottom:10px;font-size:.95em;text-transform:uppercase;letter-spacing:.04em}",
    "table.dt{width:100%;border-collapse:collapse;font-size:.91em}",
    "table.dt th{padding:5px 10px;border:1px solid #ccc;background:#f0f4f8;font-weight:600;text-align:left;font-size:.88em}",
    "table.dt td{padding:5px 10px;border:1px solid #ddd;vertical-align:top}",
    "table.dt td.l{width:200px;font-weight:600;background:#f5f5f5;color:#333}",
    "table.dt td.f{background:#fffde7;color:#5d4e00;font-style:italic}",
    "table.dt td.r{text-align:right;font-family:monospace}",
    paste0(".verdict{margin-top:12px;padding:11px 16px;border-radius:4px;font-size:1.05em;font-weight:bold;text-align:center;background:", d_bg, ";color:", d_color, ";border:2px solid ", d_bdr, "}"),
    ".logo-wrap{border:2px dashed #bbb;border-radius:4px;padding:16px;text-align:center;margin-bottom:24px;color:#999;font-size:.9em;min-height:72px;display:flex;align-items:center;justify-content:center}",
    "table.appr{width:100%;border-collapse:collapse;font-size:.93em;margin-top:8px}",
    "table.appr th{background:#f0f4f8;padding:6px 10px;border:1px solid #ccc;text-align:left;font-size:.88em}",
    "table.appr td{padding:20px 10px 4px;border:1px solid #ccc}",
    ".rpt-footer{margin-top:28px;padding-top:10px;border-top:1px solid #ddd;font-size:.79em;color:#999;text-align:center}",
    "@media print{body{background:#fff;padding:0}.report{border:none;box-shadow:none;padding:16px;max-width:100%}.verdict{-webkit-print-color-adjust:exact;print-color-adjust:exact}}"
  ), collapse = "\n")

  out <- c(
    '<!DOCTYPE html><html lang="en"><head>',
    '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Batch Poolability Analysis Report</title>',
    paste0('<style>', css, '</style></head><body><div class="report">'),

    '<div class="logo-wrap">[Insert company logo here]</div>',

    '<div class="rpt-hdr">',
    '<h1>Batch Poolability Analysis Report</h1>',
    '<h2>ICH Q1E Section 4.5 &mdash; Two-Step ANCOVA</h2>',
    '<table class="meta">',
    '<tr><td class="k">Customer&nbsp;Doc&nbsp;ID</td><td class="draft">[enter customer document number]</td></tr>',
    paste0('<tr><td class="k">Report&nbsp;ID</td><td>', he(report_id), '</td></tr>'),
    paste0('<tr><td class="k">Generated</td><td>', he(dt_str), '</td></tr>'),
    '<tr><td class="k">Script</td><td>jrc_shelf_life_poolability v1.1 &mdash; JR Anchored</td></tr>',
    '<tr><td class="k">Status</td><td class="draft">DRAFT &mdash; complete all highlighted fields before use</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">1. Purpose and Scope</div><table class="dt">',
    '<tr><td class="l">Product / Study</td><td class="f">[describe the product and stability study]</td></tr>',
    '<tr><td class="l">Objective</td><td class="f">[state the objective, e.g.: determine whether stability data from multiple batches can be combined for a single shelf life estimate]</td></tr>',
    '<tr><td class="l">Standard</td><td>ICH Q1E \u2014 Evaluation for Stability Data, Section 4.5</td></tr>',
    '</table></div>',

    '<div class="section"><div class="sec-ttl">2. Data Summary</div><table class="dt">',
    paste0('<tr><td class="l">Data file</td><td>', he(basename(csv_file)), '</td></tr>'),
    paste0('<tr><td class="l">Batches</td><td class="r">', he(n_batches), '</td></tr>'),
    paste0('<tr><td class="l">Total observations</td><td class="r">', he(n_total), '</td></tr>'),
    paste0('<tr><td class="l">ICH Q1E alpha</td><td class="r">', he(ICH_ALPHA),
           ' (conservative threshold for poolability tests)</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">3. Per-Batch Regressions</div>',
    '<table class="dt"><thead><tr><th>Batch</th><th style="text-align:right">n</th>',
    '<th style="text-align:right">Intercept</th><th style="text-align:right">Slope</th>',
    '<th style="text-align:right">R&sup2;</th><th style="text-align:right">p (slope)</th></tr></thead><tbody>',
    batch_rows,
    '</tbody></table></div>',

    '<div class="section"><div class="sec-ttl">4. ANCOVA Summary</div><table class="dt">',
    '<tr><td class="l">Step 1 &mdash; Batch:time interaction</td>',
    paste0('<td class="r">p = ', f4(p_interaction), if (p_interaction < ICH_ALPHA) '&nbsp; <strong>* significant</strong>' else '&nbsp; ns', '</td></tr>'),
    '<tr><td class="l">Step 2 &mdash; Batch main effect</td>',
    paste0('<td class="r">p = ', f4(p_batch), if (p_batch < ICH_ALPHA) '&nbsp; <strong>* significant</strong>' else '&nbsp; ns', '</td></tr>'),
    '</table></div>',

    '<div class="section"><div class="sec-ttl">5. Decision</div><table class="dt">',
    paste0('<tr><td class="l">Poolability decision</td><td><strong>', he(decision), '</strong></td></tr>'),
    paste0('<tr><td class="l">Rationale</td><td>', he(rationale), '</td></tr>'),
    '</table>',
    paste0('<div class="verdict">', he(decision_sym), ' ', he(decision), '</div>'),
    '</div>',

    '<div class="section"><div class="sec-ttl">6. Chart</div>',
    img_tag,
    '</div>',

    '<div class="section"><div class="sec-ttl">7. Approvals</div>',
    '<table class="appr"><thead><tr><th>Role</th><th>Name</th><th>Signature</th><th>Date</th></tr></thead><tbody>',
    '<tr><td>Prepared by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Reviewed by</td><td></td><td></td><td></td></tr>',
    '<tr><td>Approved by</td><td></td><td></td><td></td></tr>',
    '</tbody></table></div>',

    paste0('<div class="rpt-footer">Generated by JR Anchored &mdash; jrc_shelf_life_poolability v1.1 &mdash; ', he(dt_str), '</div>'),
    '</div></body></html>'
  )

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(datetime_pfx, "_poolability_dv_report.html"))
  writeLines(out, out_path)
  message(sprintf("\U0001f4c4 Report saved to: %s", out_path))

  jvs <- function(x) if (is.null(x) || is.na(x)) "null" else paste0('"', gsub('"', '\\"', as.character(x)), '"')
  jvn <- function(x, fmt = "%.6g") if (is.null(x) || is.na(x)) "null" else sprintf(fmt, as.numeric(x))

  is_pass <- decision == "FULL POOL"

  method_rows <- paste0(
    '{"k":"Method","v":"ICH Q1E two-step ANCOVA (batch poolability)"},',
    '{"k":"Standard","v":"ICH Q1E Section 4.5 - Evaluation for Stability Data"},',
    '{"k":"ICH alpha","v":', jvn(ICH_ALPHA), '},',
    '{"k":"Batches","v":', jvn(n_batches, "%.0f"), '},',
    '{"k":"Total observations","v":', jvn(n_total, "%.0f"), '}'
  )

  results_rows <- paste0(
    '{"k":"Data file","v":', jvs(basename(csv_file)), '},',
    '{"k":"Step 1 interaction p-value","v":', jvn(p_interaction, "%.4f"), '},',
    '{"k":"Step 2 batch main effect p-value","v":', jvn(p_batch, "%.4f"), '},',
    '{"k":"Decision","v":', jvs(decision), '}'
  )

  batch_json <- paste0(
    "[",
    paste(sapply(batch_fits, function(bf) {
      paste0('{"batch":', jvs(bf$batch),
             ',"n":', jvn(bf$n, "%.0f"),
             ',"intercept":', jvn(bf$intercept, "%.4f"),
             ',"slope":', jvn(bf$slope, "%.4f"),
             ',"r2":', jvn(bf$r2, "%.4f"),
             ',"p_slope":', jvn(bf$p_slope, "%.4f"),
             '}')
    }), collapse = ","),
    "]"
  )

  json_str <- paste0(
    '{"report_type":"dv",',
    '"script":"jrc_shelf_life_poolability",',
    '"version":"1.1",',
    '"report_id":', jvs(report_id), ',',
    '"generated":', jvs(dt_str), ',',
    '"verdict_pass":', if (is_pass) "true" else "false", ',',
    '"lsl":null,"usl":null,',
    '"png_path":', jvs(png_path), ',',
    '"method":[', method_rows, '],',
    '"results":[', results_rows, '],',
    '"batch_fits":', batch_json, '}'
  )

  json_path <- sub("\\.html$", "_data.json", out_path)
  writeLines(json_str, json_path)
  message(sprintf("  JSON sidecar: %s", json_path))
  pack_py <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "pack", "jr_pack.py")
  if (file.exists(pack_py)) {
    ret       <- system2("python3",
                         args   = c(shQuote(pack_py), "deliverables", "dv-report",
                                    "--json", shQuote(json_path)),
                         stdout = TRUE, stderr = TRUE)
    exit_code <- attr(ret, "status")
    if (is.null(exit_code)) exit_code <- 0L
    message(paste(ret, collapse = "\n"))
    if (exit_code != 0L) {
      message(sprintf("   Retry manually: jr_pack deliverables dv-report --json %s", json_path))
    }
  } else {
    message(sprintf("   Run: jr_pack deliverables dv-report --json %s", json_path))
  }

  c(html = out_path, json = json_path)
}

report_path <- NULL

if (want_report) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates",
                        "dv_report_template.html")
  if (!file.exists(sentinel)) {
    message("\u274c  --report is not available.")
    message("")
    message("   This feature requires the JR Anchored Validation Pack.")
    message("   To enable it, install the Validation Pack and run install.sh.")
    message("   The installer copies dv_report_template.html into:")
    message(paste0("     ", file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates")))
    message("")
    message("   Contact dwylup.com to purchase the JR Anchored Validation Pack.")
    message("")
    quit(save = "no", status = 1)
  }
  report_path <- save_poolability_report(
    csv_file, n_batches, n_total, batch_fits,
    p_interaction, p_batch, ICH_ALPHA,
    decision, decision_sym, rationale,
    out_file
  )
}

cat(sprintf("\u2705 Done.\n"))
jr_log_output_hashes(c(out_file, if (!is.null(report_path)) report_path else character(0)))
