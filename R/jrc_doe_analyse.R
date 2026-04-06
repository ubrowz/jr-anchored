#!/usr/bin/env Rscript
#
# use as: Rscript jrc_doe_analyse.R <results_file> <output_folder>
#
# "results_file"  path to a completed DoE companion CSV produced by
#                 jrc_doe_design (with the response column filled in by
#                 the engineer)
# "output_folder" folder path where the HTML analysis report is saved
#
# Reads the completed run matrix, fits a linear model in coded factor
# space, and produces a self-contained HTML report containing: an ANOVA
# table, a Pareto chart of standardised effects, a main effects plot,
# an optional two-factor interaction plot, an optional curvature test
# (when centre points are present), and a plain-English significant
# factors summary.
#
# Design types supported (read from the companion CSV comment line):
#   full2      — main effects + all 2-way interactions
#   full3      — main effects + quadratic terms per factor
#   fractional — main effects + all 2-way interactions
#   pb         — main effects only (PB does not support interactions)
#
# Needs the <ggplot2> library.
#
# Author: Joep Rous
# Version: 1.0

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
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressPackageStartupMessages({
  library(ggplot2)
  library(base64enc)
})

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

htmlEscape <- function(s) {
  s <- gsub("&",  "&amp;",  as.character(s), fixed = TRUE)
  s <- gsub("<",  "&lt;",   s, fixed = TRUE)
  s <- gsub(">",  "&gt;",   s, fixed = TRUE)
  s <- gsub('"',  "&quot;", s, fixed = TRUE)
  s
}

fmt_p <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) return("< 0.001")
  formatC(p, format = "f", digits = 4)
}

fmt_num <- function(x, digits = 4) {
  if (is.na(x)) return("NA")
  formatC(x, format = "f", digits = digits)
}

embed_png <- function(gg, width = 7, height = 4.5) {
  tmp <- tempfile(fileext = ".png")
  png(tmp, width = width * 96, height = height * 96, res = 96)
  print(gg)
  dev.off()
  b64 <- base64enc::base64encode(tmp)
  paste0('<img src="data:image/png;base64,', b64,
         '" style="max-width:100%;height:auto;display:block">')
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_doe_analyse.R <results_file> <output_folder>",
    "Example:",
    "  Rscript jrc_doe_analyse.R doe_design_full2_SealStrength_N_20260317_150000.csv ~/results",
    sep = "\n"
  ))
}

results_file  <- args[1]
output_folder <- args[2]

if (!file.exists(results_file)) {
  stop(paste("\u274c Results file not found:", results_file))
}

if (!dir.exists(output_folder)) {
  stop(paste("\u274c Output folder not found:", output_folder))
}

# ---------------------------------------------------------------------------
# Step 1 — Read and validate the CSV
# ---------------------------------------------------------------------------

# Read the first line to extract metadata
first_line <- readLines(results_file, n = 1)

# Parse design_type and response_name from comment
design_type   <- NA_character_
response_name <- NA_character_

if (grepl("^#", first_line)) {
  m_type <- regmatches(first_line, regexpr("type=([^,]+)", first_line))
  if (length(m_type) > 0) {
    design_type <- trimws(sub("type=", "", m_type))
  }
  m_resp <- regmatches(first_line, regexpr("response=(.+)$", first_line))
  if (length(m_resp) > 0) {
    response_name <- trimws(sub("response=", "", m_resp))
  }
}

if (is.na(design_type) || nchar(design_type) == 0) {
  stop(paste0(
    "\u274c Could not parse design type from CSV comment line. ",
    "Expected format: # jrc_doe_design: type=<type>, response=<name>"
  ))
}
if (is.na(response_name) || nchar(response_name) == 0) {
  stop(paste0(
    "\u274c Could not parse response name from CSV comment line. ",
    "Expected format: # jrc_doe_design: type=<type>, response=<name>"
  ))
}

valid_types <- c("full2", "full3", "fractional", "pb")
if (!design_type %in% valid_types) {
  stop(paste0(
    "\u274c Unrecognised design type '", design_type, "' from CSV comment. ",
    "Must be one of: ", paste(valid_types, collapse = ", "), "."
  ))
}

# Read the CSV data
doe_data <- tryCatch(
  read.csv(results_file, comment.char = "#", stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Failed to read results CSV:", e$message))
)

# Validate required structural columns
required_cols <- c("run", "std_order", "is_centre")
missing_req   <- setdiff(required_cols, names(doe_data))
if (length(missing_req) > 0) {
  stop(paste0(
    "\u274c Results CSV is missing required column(s): ",
    paste(missing_req, collapse = ", "), "."
  ))
}

if (!response_name %in% names(doe_data)) {
  stop(paste0(
    "\u274c Response column '", response_name, "' not found in CSV. ",
    "Available columns: ", paste(names(doe_data), collapse = ", "), "."
  ))
}

# Identify factor columns
non_factor_cols <- c("run", "std_order", "is_centre", response_name)
factor_names    <- setdiff(names(doe_data), non_factor_cols)

if (length(factor_names) < 2) {
  stop(paste0(
    "\u274c At least 2 factor columns are required. Found: ",
    length(factor_names), ". ",
    if (length(factor_names) == 1) paste0("Factor found: ", factor_names[1]) else
      "No factor columns found after excluding run, std_order, is_centre, and response."
  ))
}

k <- length(factor_names)

# Coerce is_centre to logical
doe_data$is_centre <- as.logical(doe_data$is_centre)

# Coerce response to numeric
doe_data[[response_name]] <- suppressWarnings(as.numeric(doe_data[[response_name]]))

# Split factorial vs centre point rows
factorial_rows  <- doe_data[!doe_data$is_centre, , drop = FALSE]
centre_rows     <- doe_data[ doe_data$is_centre,  , drop = FALSE]

n_factorial <- nrow(factorial_rows)
n_centre    <- nrow(centre_rows)

# Check for missing response values in factorial runs
missing_resp_fact <- is.na(factorial_rows[[response_name]])
if (any(missing_resp_fact)) {
  bad_runs <- factorial_rows$run[missing_resp_fact]
  stop(paste0(
    "\u274c Response column '", response_name, "' has missing values in ",
    sum(missing_resp_fact), " factorial run(s): ",
    paste(bad_runs, collapse = ", "), ". ",
    "Fill in all factorial responses before running analysis."
  ))
}

# Warn for missing centre point responses (do not stop)
if (n_centre > 0) {
  missing_resp_cp <- is.na(centre_rows[[response_name]])
  if (any(missing_resp_cp)) {
    warning(paste0(
      "\u26a0\ufe0f  ", sum(missing_resp_cp), " centre-point run(s) have missing response values. ",
      "These will be excluded from the curvature test."
    ))
    centre_rows <- centre_rows[!missing_resp_cp, , drop = FALSE]
    n_centre    <- nrow(centre_rows)
  }
}

# ---------------------------------------------------------------------------
# Step 2 — Prepare data: convert factor columns to coded values
# ---------------------------------------------------------------------------

# Work on factorial rows for coding reference
fact_coded <- factorial_rows

for (fn in factor_names) {
  fact_coded[[fn]] <- as.numeric(fact_coded[[fn]])
  unique_vals <- sort(unique(fact_coded[[fn]]))
  n_uniq <- length(unique_vals)
  if (n_uniq == 2) {
    fact_coded[[fn]] <- ifelse(fact_coded[[fn]] == unique_vals[1], -1, 1)
  } else if (n_uniq == 3) {
    fact_coded[[fn]] <- ifelse(
      fact_coded[[fn]] == unique_vals[1], -1,
      ifelse(fact_coded[[fn]] == unique_vals[2], 0, 1)
    )
  } else {
    # Rescale to [-1, 1] linearly
    mn <- min(fact_coded[[fn]])
    mx <- max(fact_coded[[fn]])
    fact_coded[[fn]] <- 2 * (fact_coded[[fn]] - mn) / (mx - mn) - 1
  }
}
fact_coded[[response_name]] <- as.numeric(factorial_rows[[response_name]])

# Build actual-level lookup for Main Effects plot axis labels
actual_levels <- list()
for (fn in factor_names) {
  actual_vals <- sort(unique(as.numeric(factorial_rows[[fn]])))
  coded_vals  <- sort(unique(fact_coded[[fn]]))
  actual_levels[[fn]] <- data.frame(
    coded  = coded_vals,
    actual = actual_vals,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Step 3 — Fit linear model
# ---------------------------------------------------------------------------

# Build formula string
factor_terms <- paste(paste0("`", factor_names, "`"), collapse = " + ")

formula_str <- switch(design_type,
  full2      = paste0("`", response_name, "` ~ (", factor_terms, ")^2"),
  fractional = paste0("`", response_name, "` ~ (", factor_terms, ")^2"),
  full3      = {
    quad_terms <- paste(paste0("I(`", factor_names, "`^2)"), collapse = " + ")
    paste0("`", response_name, "` ~ ", factor_terms, " + ", quad_terms)
  },
  pb         = paste0("`", response_name, "` ~ ", factor_terms)
)

fit <- tryCatch(
  lm(as.formula(formula_str), data = fact_coded),
  error = function(e) stop(paste0(
    "\u274c Model could not be fitted: ", e$message, ". ",
    "This may happen when there are not enough degrees of freedom for the chosen design type. ",
    "Consider using a simpler model (e.g. type 'pb' main effects only) or adding more runs."
  ))
)

anova_table <- tryCatch(
  anova(fit),
  error = function(e) stop(paste0("\u274c ANOVA could not be computed: ", e$message))
)

fit_summary <- summary(fit)
r_squared   <- fit_summary$r.squared
sigma_resid <- fit_summary$sigma

# Standardised effects (exclude intercept)
coefs       <- coef(fit)
coefs       <- coefs[names(coefs) != "(Intercept)"]
std_effects <- coefs / sigma_resid
std_effects_abs <- abs(std_effects)
std_effects_sorted <- sort(std_effects_abs, decreasing = FALSE)  # ascending for horizontal bar

# Significant terms from ANOVA (p < 0.05, excluding Residuals)
anova_df         <- as.data.frame(anova_table)
anova_terms      <- rownames(anova_df)
anova_p          <- anova_df[["Pr(>F)"]]
significant_terms <- anova_terms[!is.na(anova_p) & anova_p < 0.05 & anova_terms != "Residuals"]

# ---------------------------------------------------------------------------
# Step 4 — Curvature test
# ---------------------------------------------------------------------------

curvature_html <- ""

if (n_centre > 0) {
  ybar_f <- mean(fact_coded[[response_name]])
  ybar_c <- mean(as.numeric(centre_rows[[response_name]]))
  n_f    <- n_factorial
  n_c    <- n_centre

  ss_curvature <- (n_f * n_c * (ybar_f - ybar_c)^2) / (n_f + n_c)

  # Residual MS from the factorial model
  resid_row <- anova_df[anova_terms == "Residuals", , drop = FALSE]
  ms_resid  <- if (nrow(resid_row) > 0 && resid_row[["Df"]] > 0) {
    resid_row[["Mean Sq"]]
  } else {
    NA_real_
  }

  if (!is.na(ms_resid) && ms_resid > 0) {
    f_curv  <- ss_curvature / ms_resid
    df_resid <- resid_row[["Df"]]
    p_curv  <- pf(f_curv, df1 = 1, df2 = df_resid, lower.tail = FALSE)

    message(paste0("   Curvature:    ",
                   if (p_curv < 0.05) "significant" else "not significant",
                   " (p = ", fmt_p(p_curv), ")"))

    if (p_curv < 0.05) {
      curv_verdict <- paste0(
        '<p style="color:#B22222;font-weight:600">\u26a0\ufe0f Curvature detected ',
        '(p = ', fmt_p(p_curv), '). The response surface is not linear. ',
        'A higher-order design (e.g. full3 or response surface) may be needed.</p>'
      )
    } else {
      curv_verdict <- paste0(
        '<p style="color:#276227">\u2705 No significant curvature detected ',
        '(p = ', fmt_p(p_curv), ').</p>'
      )
    }

    curvature_html <- paste0(
      '<div class="card">',
      '<h2>Curvature Test</h2>',
      '<table><thead><tr>',
      '<th>SS Curvature</th><th>Residual MS</th><th>F value</th><th>Df resid</th><th>p-value</th>',
      '</tr></thead><tbody><tr>',
      '<td>', fmt_num(ss_curvature), '</td>',
      '<td>', fmt_num(ms_resid),     '</td>',
      '<td>', fmt_num(f_curv),       '</td>',
      '<td>', df_resid,              '</td>',
      '<td>', fmt_p(p_curv),         '</td>',
      '</tr></tbody></table>',
      curv_verdict,
      '<p style="font-size:0.88em;color:#555">',
      'Factorial mean = ', fmt_num(ybar_f, 4), ', ',
      'Centre-point mean = ', fmt_num(ybar_c, 4),
      ' (', n_centre, ' centre point', if (n_centre == 1) "" else "s", ').',
      '</p>',
      '</div>'
    )
  } else {
    curvature_html <- paste0(
      '<div class="card">',
      '<h2>Curvature Test</h2>',
      '<p>Curvature test could not be performed: no residual degrees of freedom in the factorial model.</p>',
      '</div>'
    )
  }
}

# ---------------------------------------------------------------------------
# Step 5 — Generate plots
# ---------------------------------------------------------------------------

jr_theme <- theme_minimal() +
  theme(
    plot.title   = element_text(face = "bold", colour = "#1A1A2E"),
    axis.title   = element_text(colour = "#1A1A2E"),
    strip.text   = element_text(face = "bold", colour = "#1A1A2E"),
    panel.grid.minor = element_blank()
  )

# --- Plot 1: Pareto chart of standardised effects ---

pareto_df <- data.frame(
  term   = names(std_effects_sorted),
  effect = as.numeric(std_effects_sorted),
  stringsAsFactors = FALSE
)
pareto_df$term       <- factor(pareto_df$term, levels = pareto_df$term)
pareto_df$significant <- pareto_df$effect > 2.0

p_pareto <- ggplot(pareto_df, aes(x = effect, y = term, fill = significant)) +
  geom_col(width = 0.6) +
  scale_fill_manual(values = c("TRUE" = "#2E5BBA", "FALSE" = "#A0B0D0"), guide = "none") +
  geom_vline(xintercept = 2.0, linetype = "dashed", colour = "red", linewidth = 0.8) +
  annotate("text", x = 2.0, y = Inf, label = "alpha = 0.05",
           colour = "red", hjust = -0.1, vjust = 1.4, size = 3.2) +
  labs(
    title = "Pareto Chart of Standardised Effects",
    x     = "Absolute Standardised Effect",
    y     = "Term"
  ) +
  jr_theme

svg_pareto <- embed_png(p_pareto, width = 7, height = max(3.5, 0.45 * nrow(pareto_df) + 1.5))

# --- Plot 2: Main effects plot ---

me_list <- list()
for (fn in factor_names) {
  # Compute mean response per coded level
  tmp <- aggregate(fact_coded[[response_name]],
                   by   = list(coded = fact_coded[[fn]]),
                   FUN  = mean)
  names(tmp)[2] <- "mean_response"
  tmp$factor    <- fn
  # Map coded back to actual
  lut <- actual_levels[[fn]]
  tmp$actual <- lut$actual[match(tmp$coded, lut$coded)]
  # If no match (e.g. rescaled), fall back to coded
  tmp$actual[is.na(tmp$actual)] <- tmp$coded[is.na(tmp$actual)]
  me_list[[fn]] <- tmp
}
me_df <- do.call(rbind, me_list)
me_df$factor <- factor(me_df$factor, levels = factor_names)
me_df$actual_label <- as.character(me_df$actual)

p_me <- ggplot(me_df, aes(x = actual_label, y = mean_response, group = 1)) +
  geom_line(colour = "#2E5BBA", linewidth = 0.9) +
  geom_point(colour = "#2E5BBA", size = 3) +
  facet_wrap(~ factor, scales = "free_x") +
  labs(
    title = "Main Effects Plot",
    x     = "Factor Level (actual)",
    y     = paste0("Mean ", htmlEscape(response_name))
  ) +
  jr_theme

svg_me <- embed_png(p_me, width = max(7, 3.2 * min(k, 4)), height = 4.5)

# --- Plot 3: Two-factor interaction plot ---

interaction_html <- ""
skip_interaction  <- FALSE
interaction_note  <- ""

if (design_type %in% c("full2", "fractional") && k >= 2) {
  if (k > 6) {
    skip_interaction <- TRUE
    interaction_note <- paste0(
      "Interaction plot omitted: ", k, " factors would produce ",
      k * (k - 1) / 2, " panels, which is too many to display clearly (limit: k \u2264 6)."
    )
    warning(paste0(
      "\u26a0\ufe0f  Interaction plot skipped: k = ", k, " > 6. ",
      "Too many panels to display."
    ))
  } else {
    # Build pairwise interaction data
    int_list <- list()
    factor_pairs <- combn(factor_names, 2, simplify = FALSE)
    for (fp in factor_pairs) {
      fn1 <- fp[1]; fn2 <- fp[2]
      tmp <- aggregate(fact_coded[[response_name]],
                       by  = list(f1 = fact_coded[[fn1]], f2 = fact_coded[[fn2]]),
                       FUN = mean)
      names(tmp)[3] <- "mean_response"
      tmp$Factor1   <- fn1
      tmp$Factor2   <- fn2
      tmp$panel     <- paste0(fn1, " \u00d7 ", fn2)
      # Actual labels for x-axis (fn1)
      lut1 <- actual_levels[[fn1]]
      tmp$actual1 <- lut1$actual[match(tmp$f1, lut1$coded)]
      tmp$actual1[is.na(tmp$actual1)] <- tmp$f1[is.na(tmp$actual1)]
      # Level labels for fn2 (line grouping)
      lut2 <- actual_levels[[fn2]]
      tmp$actual2 <- lut2$actual[match(tmp$f2, lut2$coded)]
      tmp$actual2[is.na(tmp$actual2)] <- tmp$f2[is.na(tmp$actual2)]
      tmp$f2_label <- as.character(tmp$actual2)
      int_list[[paste(fn1, fn2)]] <- tmp
    }
    int_df <- do.call(rbind, int_list)
    int_df$panel    <- factor(int_df$panel, levels = unique(int_df$panel))
    int_df$f2_label <- factor(int_df$f2_label)
    int_df$actual1_label <- as.character(int_df$actual1)

    p_int <- ggplot(int_df,
                    aes(x = actual1_label, y = mean_response,
                        group = f2_label, colour = f2_label)) +
      geom_line(linewidth = 0.9) +
      geom_point(size = 3) +
      facet_wrap(~ panel, scales = "free_x") +
      labs(
        title  = "Two-Factor Interaction Plot",
        x      = "Factor 1 level (actual)",
        y      = paste0("Mean ", htmlEscape(response_name)),
        colour = "Factor 2 level"
      ) +
      jr_theme +
      theme(legend.position = "bottom")

    n_pairs    <- length(factor_pairs)
    plot_ncols <- min(n_pairs, 3)
    plot_nrows <- ceiling(n_pairs / plot_ncols)
    svg_int    <- embed_png(p_int, width = 7, height = 3 + 3 * plot_nrows)

    interaction_html <- paste0(
      '<div class="card">',
      '<h2>Two-Factor Interaction Plot</h2>',
      svg_int,
      '</div>'
    )
  }

  if (skip_interaction) {
    interaction_html <- paste0(
      '<div class="card">',
      '<h2>Two-Factor Interaction Plot</h2>',
      '<p>', htmlEscape(interaction_note), '</p>',
      '</div>'
    )
  }
}

# ---------------------------------------------------------------------------
# Step 6 — Significant factors card content
# ---------------------------------------------------------------------------

# Collect all non-Residuals ANOVA terms and their p-values
sig_bullets <- character(0)
for (i in seq_along(anova_terms)) {
  trm <- anova_terms[i]
  if (trm == "Residuals") next
  pv  <- anova_p[i]
  if (is.na(pv)) next
  if (pv < 0.05) {
    sig_bullets <- c(sig_bullets, paste0(
      '<li>\u2705 <strong>', htmlEscape(trm), '</strong> (p = ', fmt_p(pv), '): significant.</li>'
    ))
  } else {
    sig_bullets <- c(sig_bullets, paste0(
      '<li>&mdash; ', htmlEscape(trm), ' (p = ', fmt_p(pv), '): not significant at \u03b1 = 0.05.</li>'
    ))
  }
}

# ---------------------------------------------------------------------------
# Assemble ANOVA table HTML
# ---------------------------------------------------------------------------

anova_rows_html <- paste(vapply(seq_along(anova_terms), function(i) {
  trm <- anova_terms[i]
  row <- anova_df[i, , drop = FALSE]
  pv  <- anova_p[i]
  row_bg <- if (!is.na(pv) && pv < 0.05) ' style="background-color:#EBF3FB"' else ""
  paste0(
    "<tr", row_bg, ">",
    "<td>", htmlEscape(trm), "</td>",
    "<td>", fmt_num(row[["Sum Sq"]]),  "</td>",
    "<td>", row[["Df"]],               "</td>",
    "<td>", if (is.na(row[["Mean Sq"]])) "—" else fmt_num(row[["Mean Sq"]]), "</td>",
    "<td>", if (is.na(row[["F value"]])) "—" else fmt_num(row[["F value"]]), "</td>",
    "<td>", if (is.na(pv)) "—" else fmt_p(pv), "</td>",
    "</tr>"
  )
}, character(1)), collapse = "\n")

# ---------------------------------------------------------------------------
# CSS block (matches jrc_doe_design style)
# ---------------------------------------------------------------------------

css_block <- '
  *, *::before, *::after { box-sizing: border-box; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                 Helvetica, Arial, sans-serif;
    font-size: 16px;
    line-height: 1.5;
    margin: 0;
    padding: 0;
    background: #F4F6F9;
    color: #222;
  }

  /* Header bar */
  .header-bar {
    background: #1A1A2E;
    color: #fff;
    padding: 20px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 12px;
  }
  .header-bar h1 {
    margin: 0;
    font-size: 1.4em;
    font-weight: 700;
    letter-spacing: 0.02em;
  }
  .header-bar .subtitle {
    margin: 2px 0 0;
    font-size: 0.92em;
    opacity: 0.82;
  }

  /* Page container */
  .container {
    max-width: 960px;
    margin: 0 auto;
    padding: 24px 16px 48px;
  }

  /* Cards */
  .card {
    background: #fff;
    border: 1px solid #2E5BBA;
    border-radius: 8px;
    padding: 20px 24px;
    margin-bottom: 24px;
    box-shadow: 0 2px 6px rgba(0,0,0,0.07);
  }
  .card h2 {
    margin: 0 0 16px;
    font-size: 1.05em;
    font-weight: 700;
    color: #1A1A2E;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    border-bottom: 2px solid #2E5BBA;
    padding-bottom: 6px;
  }
  .card p.note {
    margin: 10px 0 0;
    font-size: 0.88em;
    color: #555;
  }

  /* Summary grid */
  .summary-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px 24px;
  }
  .summary-item { font-size: 0.95em; }
  .summary-item .label {
    font-weight: 600;
    color: #1A1A2E;
    display: block;
    font-size: 0.82em;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    margin-bottom: 1px;
  }

  /* Tables */
  .table-wrap { overflow-x: auto; }
  table {
    border-collapse: collapse;
    width: 100%;
    min-width: 400px;
    font-size: 14px;
  }
  th {
    background: #2E5BBA;
    color: #fff;
    padding: 9px 12px;
    text-align: left;
    font-size: 0.88em;
    white-space: nowrap;
  }
  td {
    padding: 8px 12px;
    border-bottom: 1px solid #E8EDF3;
    vertical-align: middle;
    font-size: 14px;
  }
  tr:last-child td { border-bottom: none; }

  /* Bullet list */
  ul.sig-list {
    list-style: none;
    padding: 0;
    margin: 0;
  }
  ul.sig-list li {
    padding: 5px 0;
    border-bottom: 1px solid #E8EDF3;
    font-size: 0.96em;
  }
  ul.sig-list li:last-child { border-bottom: none; }

  /* Footer */
  .footer {
    text-align: center;
    font-size: 0.80em;
    color: #888;
    margin-top: 32px;
    margin-bottom: 16px;
  }

  /* SVG plots */
  .plot-wrap { overflow-x: auto; text-align: center; }
  .plot-wrap svg { max-width: 100%; height: auto; }

  /* Responsive */
  @media (max-width: 600px) {
    .summary-grid { grid-template-columns: 1fr; }
    .header-bar { flex-direction: column; align-items: flex-start; }
    .container { padding: 16px 16px 32px; }
  }

  /* Print */
  @media print {
    body { background: #fff; font-size: 12px; }
    .card {
      box-shadow: none;
      border: 1px solid #999;
      page-break-inside: avoid;
    }
    .header-bar {
      background: #1A1A2E !important;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    th {
      background: #2E5BBA !important;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    td { border-bottom: 1px solid #ccc; }
    table { min-width: unset; }
  }
'

# ---------------------------------------------------------------------------
# Assemble output filename and path
# ---------------------------------------------------------------------------

timestamp   <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
dt_suffix   <- format(Sys.time(), "%Y%m%d_%H%M%S")
safe_resp   <- gsub("[^A-Za-z0-9_.-]", "_", response_name)
html_fname  <- paste0("doe_analysis_", safe_resp, "_", dt_suffix, ".html")
html_path   <- file.path(normalizePath(output_folder), html_fname)

# Factor names for display
factor_list_html <- paste(vapply(factor_names, htmlEscape, character(1)), collapse = ", ")

# ---------------------------------------------------------------------------
# Assemble full HTML document
# ---------------------------------------------------------------------------

html_content <- paste0(
'<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>JR DoE Analysis Report &mdash; ', htmlEscape(response_name), '</title>
<style>', css_block, '</style>
</head>
<body>

<!-- Header bar -->
<div class="header-bar">
  <div>
    <h1>JR DoE Analysis Report</h1>
    <div class="subtitle">Response: ', htmlEscape(response_name),
    ' &mdash; Design: ', htmlEscape(design_type),
    ' &mdash; ', htmlEscape(timestamp), '</div>
  </div>
</div>

<div class="container">

  <!-- Analysis Summary -->
  <div class="card">
    <h2>Analysis Summary</h2>
    <div class="summary-grid">
      <div class="summary-item">
        <span class="label">Response</span>
        ', htmlEscape(response_name), '
      </div>
      <div class="summary-item">
        <span class="label">Design type</span>
        ', htmlEscape(design_type), '
      </div>
      <div class="summary-item">
        <span class="label">Total runs</span>
        ', nrow(doe_data), '
      </div>
      <div class="summary-item">
        <span class="label">Factorial runs</span>
        ', n_factorial, '
      </div>
      <div class="summary-item">
        <span class="label">Centre points</span>
        ', n_centre, '
      </div>
      <div class="summary-item">
        <span class="label">Factors (k)</span>
        ', k, '
      </div>
      <div class="summary-item">
        <span class="label">Factors</span>
        ', factor_list_html, '
      </div>
      <div class="summary-item">
        <span class="label">Model R&sup2;</span>
        ', fmt_num(r_squared, 4), '
      </div>
      <div class="summary-item">
        <span class="label">Residual std error</span>
        ', fmt_num(sigma_resid, 4), '
      </div>
    </div>
  </div>

  <!-- ANOVA Table -->
  <div class="card">
    <h2>ANOVA Table</h2>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Term</th>
            <th>Sum Sq</th>
            <th>Df</th>
            <th>Mean Sq</th>
            <th>F value</th>
            <th>Pr(&gt;F)</th>
          </tr>
        </thead>
        <tbody>
', anova_rows_html, '
        </tbody>
      </table>
    </div>
    <p class="note">Coded values (&minus;1, 0, +1) used for analysis. Effect sizes are comparable across factors.
    Rows highlighted in blue have p &lt; 0.05.</p>
  </div>

  <!-- Pareto Chart -->
  <div class="card">
    <h2>Pareto Chart of Standardised Effects</h2>
    <div class="plot-wrap">',
    svg_pareto,
    '</div>
    <p class="note">Bars to the right of the dashed red line (|effect| &gt; 2.0) are significant at approximately &alpha; = 0.05.</p>
  </div>

  <!-- Main Effects -->
  <div class="card">
    <h2>Main Effects Plot</h2>
    <div class="plot-wrap">',
    svg_me,
    '</div>
    <p class="note">Each panel shows the mean response at each level of that factor. Factorial runs only.</p>
  </div>

  ', interaction_html, '

  ', curvature_html, '

  <!-- Significant Factors Summary -->
  <div class="card">
    <h2>Significant Factors</h2>
    <ul class="sig-list">',
    paste(sig_bullets, collapse = "\n"),
    '
    </ul>
    <p class="note">\u03b1 = 0.05 throughout. Coded factor values used for fitting.</p>
  </div>

</div><!-- /container -->

<div class="footer">
  Generated by JR Validated Environment &middot; jrc_doe_analyse &middot; ', htmlEscape(timestamp), '
</div>

</body>
</html>
')

# ---------------------------------------------------------------------------
# Write HTML file
# ---------------------------------------------------------------------------

writeLines(html_content, con = html_path, useBytes = FALSE)

# ---------------------------------------------------------------------------
# Terminal summary
# ---------------------------------------------------------------------------

sig_display <- if (length(significant_terms) > 0) {
  paste(significant_terms, collapse = ", ")
} else {
  "none at \u03b1 = 0.05"
}

message(" ")
message(paste0("\u2705 Analysis complete: ", html_fname))
message(paste0("   Response:     ", response_name))
message(paste0("   Design type:  ", design_type))
message(paste0("   Runs:         ", nrow(doe_data),
               "  (", n_factorial, " factorial",
               if (n_centre > 0) paste0(" + ", n_centre, " centre point",
                                         if (n_centre == 1) "" else "s") else "",
               ")"))
message(paste0("   R\u00b2:           ", fmt_num(r_squared, 3)))
message(paste0("   Significant:  ", sig_display))
message(paste0("   Saved to:     ", normalizePath(output_folder)))
message(" ")
jr_log_output_hashes(c(html_path))
