#!/usr/bin/env Rscript
#
# use as: Rscript jrc_doe_design.R <type> <factors_file> <response_name> <output_folder>
#                                   [centre_points] [replicates]
#
# "type"           design type: full2 | full3 | fractional | pb
# "factors_file"   path to CSV with columns: name, low, high (optional: mid)
#                  One row per factor.
# "response_name"  name of the response variable (e.g. "SealStrength_N")
# "output_folder"  folder path where the HTML file is saved
# "centre_points"  integer >= 0 (optional, default 0). Only for full2 and
#                  fractional; ignored for full3 and pb.
# "replicates"     integer >= 1 (optional, default 1)
#
# Generates a Design of Experiments (DoE) matrix and writes an
# engineer-friendly self-contained HTML file containing the randomised run
# order, factor definitions, and a blank response column ready to fill in.
#
# Design types:
#   full2      — 2-level full factorial (2^k runs x replicates + centre points)
#   full3      — 3-level full factorial (3^k runs x replicates)
#   fractional — 2-level fractional factorial (minimum-resolution via FrF2)
#   pb         — Plackett-Burman screening design
#
# Needs the <FrF2> and <DoE.base> libraries.
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
  library(FrF2)
  library(DoE.base)
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

fmt_cell <- function(actual, coded) {
  # Format actual value (suppress unnecessary decimals) + coded in grey
  if (is.na(actual)) return("")
  actual_str <- if (actual == round(actual)) {
    formatC(actual, format = "f", digits = 0)
  } else {
    formatC(actual, format = "g", digits = 4)
  }
  coded_str <- as.character(coded)
  paste0(actual_str,
         ' <span style="color:#999;font-size:0.85em">(', coded_str, ")</span>")
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(paste(
    "Not enough arguments. Usage:",
    "  Rscript jrc_doe_design.R <type> <factors_file> <response_name> <output_folder> [centre_points] [replicates]",
    "Example:",
    "  Rscript jrc_doe_design.R full2 factors.csv SealStrength_N ~/results 3 1",
    sep = "\n"
  ))
}

valid_types   <- c("full2", "full3", "fractional", "pb")
design_type   <- args[1]
factors_file  <- args[2]
response_name <- args[3]
output_folder <- args[4]
centre_pts    <- if (length(args) >= 5) as.integer(args[5]) else 0L
replicates    <- if (length(args) >= 6) as.integer(args[6]) else 1L

if (!design_type %in% valid_types) {
  stop(paste0(
    "\u274c Invalid design type: '", design_type, "'. ",
    "Must be one of: ", paste(valid_types, collapse = ", "), "."
  ))
}

if (!file.exists(factors_file)) {
  stop(paste("\u274c Factors file not found:", factors_file))
}

if (!dir.exists(output_folder)) {
  stop(paste("\u274c Output folder not found:", output_folder))
}

if (is.na(centre_pts) || centre_pts < 0L) {
  stop("\u274c centre_points must be an integer >= 0.")
}

if (is.na(replicates) || replicates < 1L) {
  stop("\u274c replicates must be an integer >= 1.")
}

# ---------------------------------------------------------------------------
# Load and validate factors CSV
# ---------------------------------------------------------------------------

factors_raw <- tryCatch(
  read.csv(factors_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Failed to read factors file:", e$message))
)

# Case-insensitive column check
names(factors_raw) <- tolower(trimws(names(factors_raw)))

required_cols <- c("name", "low", "high")
missing_cols  <- setdiff(required_cols, names(factors_raw))
if (length(missing_cols) > 0) {
  stop(paste0(
    "\u274c Factors CSV is missing required column(s): ",
    paste(missing_cols, collapse = ", "),
    ". Required columns: name, low, high (optional: mid)."
  ))
}

# Compute mid if absent
if (!"mid" %in% names(factors_raw)) {
  factors_raw$mid <- (as.numeric(factors_raw$low) + as.numeric(factors_raw$high)) / 2
}

factors_df <- data.frame(
  name = as.character(factors_raw$name),
  low  = as.numeric(factors_raw$low),
  mid  = as.numeric(factors_raw$mid),
  high = as.numeric(factors_raw$high),
  stringsAsFactors = FALSE
)

k <- nrow(factors_df)

if (k < 2) {
  stop(paste("\u274c At least 2 factors are required. Got:", k))
}
if (k > 15) {
  stop(paste("\u274c At most 15 factors are supported. Got:", k))
}

# ---------------------------------------------------------------------------
# Design-type specific sanity checks
# ---------------------------------------------------------------------------

if (design_type == "full2") {
  n_base_check <- 2^k
  if (n_base_check > 256) {
    stop(paste0(
      "\u274c Full 2-level factorial with k = ", k, " factors would produce ",
      n_base_check, " runs (2^", k, "), which exceeds the 256-run sanity limit. ",
      "Consider using type 'fractional' instead."
    ))
  }
}

if (design_type == "full3") {
  n_base_check <- 3^k
  if (n_base_check > 243) {
    stop(paste0(
      "\u274c Full 3-level factorial with k = ", k, " factors would produce ",
      n_base_check, " runs (3^", k, "), which exceeds the 243-run limit. ",
      "Maximum 5 factors for 3-level full factorial designs."
    ))
  }
}

# Warn and suppress centre_points for unsupported types
if (centre_pts > 0L && design_type %in% c("full3", "pb")) {
  warning(paste0(
    "\u26a0\ufe0f  centre_points = ", centre_pts, " is not applicable for design type '",
    design_type, "'. Centre points will be set to 0."
  ))
  centre_pts <- 0L
}

# ---------------------------------------------------------------------------
# Generate base design in coded values (-1, 0, +1)
# ---------------------------------------------------------------------------

if (design_type == "full2") {
  lev_list <- lapply(seq_len(k), function(i) c(-1L, 1L))
  base_mat <- as.matrix(do.call(expand.grid, lev_list))
  base_mat <- base_mat[rep(seq_len(nrow(base_mat)), replicates), , drop = FALSE]
  std_ord  <- rep(seq_len(2^k), replicates)

} else if (design_type == "full3") {
  lev_list <- lapply(seq_len(k), function(i) c(-1L, 0L, 1L))
  base_mat <- as.matrix(do.call(expand.grid, lev_list))
  base_mat <- base_mat[rep(seq_len(nrow(base_mat)), replicates), , drop = FALSE]
  std_ord  <- rep(seq_len(3^k), replicates)

} else if (design_type == "fractional") {
  frf      <- FrF2::FrF2(nfactors = k, resolution = 3, replications = replicates, randomize = FALSE)
  base_mat <- matrix(as.integer(as.matrix(data.frame(lapply(data.frame(frf), as.numeric)))),
                     nrow = nrow(data.frame(frf)))
  std_ord  <- seq_len(nrow(base_mat))

} else if (design_type == "pb") {
  nruns    <- ceiling((k + 1) / 4) * 4
  pb_des   <- FrF2::pb(nruns, nfactors = k, randomize = FALSE)
  base_mat <- matrix(as.integer(sapply(data.frame(pb_des), function(x) as.numeric(as.character(x)))),
                     nrow = nrow(data.frame(pb_des)))
  std_ord  <- seq_len(nrow(base_mat))
}

storage.mode(base_mat) <- "integer"
colnames(base_mat)     <- paste0("F", seq_len(k))
n_base                 <- nrow(base_mat)

# ---------------------------------------------------------------------------
# Randomise base design
# ---------------------------------------------------------------------------

seed <- as.integer(Sys.time())
set.seed(seed)
rand_idx <- sample(seq_len(n_base))
base_mat <- base_mat[rand_idx, , drop = FALSE]
std_ord  <- std_ord[rand_idx]

# ---------------------------------------------------------------------------
# Add and intersperse centre points
# ---------------------------------------------------------------------------

if (centre_pts > 0L) {
  cp_mat           <- matrix(0L, nrow = centre_pts, ncol = k)
  colnames(cp_mat) <- paste0("F", seq_len(k))
  combined_mat     <- rbind(base_mat, cp_mat)
  combined_std     <- c(std_ord, rep(NA_integer_, centre_pts))
  is_centre        <- c(rep(FALSE, n_base), rep(TRUE, centre_pts))

  # Intersperse centre points throughout the run order
  set.seed(seed + 1L)
  final_idx    <- sample(seq_len(nrow(combined_mat)))
  design_mat   <- combined_mat[final_idx, , drop = FALSE]
  final_std    <- combined_std[final_idx]
  final_centre <- is_centre[final_idx]
} else {
  design_mat   <- base_mat
  final_std    <- std_ord
  final_centre <- rep(FALSE, n_base)
}

total_runs <- nrow(design_mat)

# ---------------------------------------------------------------------------
# Map coded values to actual factor levels
# ---------------------------------------------------------------------------

actual_mat <- matrix(NA_real_, nrow = total_runs, ncol = k)
colnames(actual_mat) <- factors_df$name

for (j in seq_len(k)) {
  coded <- design_mat[, j]
  actual_mat[, j] <- ifelse(
    coded == -1L, factors_df$low[j],
    ifelse(coded == 0L, factors_df$mid[j], factors_df$high[j])
  )
}

# ---------------------------------------------------------------------------
# Design type labels and display flags
# ---------------------------------------------------------------------------

type_labels <- list(
  full2      = paste0("Full Factorial 2-level (2^", k, " = ", 2^k, " runs)"),
  full3      = paste0("Full Factorial 3-level (3^", k, " = ", 3^k, " runs)"),
  fractional = paste0("Fractional Factorial 2-level (", n_base / max(replicates, 1L), " runs)"),
  pb         = paste0("Plackett-Burman Screening (", n_base, " runs)")
)
type_label <- type_labels[[design_type]]

# Determine whether to show a centre/mid column in the factor definitions table
show_mid_col <- (design_type == "full3") ||
                (design_type %in% c("full2", "fractional") && centre_pts > 0L)

# Display values for summary (pb and full3 don't use centre_pts or replicates the same way)
if (design_type == "pb") {
  rep_display <- "N/A"
  cp_display  <- "N/A"
} else {
  rep_display <- as.character(replicates)
  cp_display  <- as.character(centre_pts)
}

# ---------------------------------------------------------------------------
# Build HTML sections
# ---------------------------------------------------------------------------

# Factor definitions table header
factor_header_html <- if (show_mid_col) {
  if (design_type == "full3") {
    paste0(
      "<tr><th>Factor</th>",
      "<th>Low (\u22121)</th>",
      "<th>Centre (0)</th>",
      "<th>High (+1)</th></tr>"
    )
  } else {
    paste0(
      "<tr><th>Factor</th>",
      "<th>Low (\u22121)</th>",
      "<th>Centre (0)</th>",
      "<th>High (+1)</th></tr>"
    )
  }
} else {
  paste0(
    "<tr><th>Factor</th>",
    "<th>Low (\u22121)</th>",
    "<th>High (+1)</th></tr>"
  )
}

# Factor definitions table rows
factor_rows_html <- paste(vapply(seq_len(k), function(j) {
  mid_cell <- if (show_mid_col) paste0("<td>", factors_df$mid[j], "</td>") else ""
  paste0(
    "<tr>",
    "<td>", htmlEscape(factors_df$name[j]), "</td>",
    "<td>", factors_df$low[j],  "</td>",
    mid_cell,
    "<td>", factors_df$high[j], "</td>",
    "</tr>"
  )
}, character(1)), collapse = "\n")

# Run matrix column headers for factors
factor_col_headers <- paste(
  vapply(factors_df$name, function(nm) {
    paste0("<th>", htmlEscape(nm), "</th>")
  }, character(1)),
  collapse = ""
)

# Run matrix rows
run_rows_html <- paste(vapply(seq_len(total_runs), function(i) {
  is_cp  <- final_centre[i]
  row_bg <- if (is_cp) {
    ' style="background-color:#EBF3FB;font-style:italic"'
  } else if (i %% 2 == 0) {
    ' style="background-color:#F8F8F8"'
  } else {
    ""
  }
  std_cell <- if (is_cp) {
    '<td style="color:#2E5BBA;font-style:italic">CP</td>'
  } else {
    paste0("<td>", final_std[i], "</td>")
  }
  factor_cells <- paste(vapply(seq_len(k), function(j) {
    coded  <- design_mat[i, j]
    actual <- actual_mat[i, j]
    paste0('<td style="font-family:monospace">', fmt_cell(actual, coded), "</td>")
  }, character(1)), collapse = "")

  paste0(
    "<tr", row_bg, ">",
    "<td>", i, "</td>",
    std_cell,
    factor_cells,
    '<td style="min-width:100px">&nbsp;</td>',
    "</tr>"
  )
}, character(1)), collapse = "\n")

# ---------------------------------------------------------------------------
# Assemble full HTML document
# ---------------------------------------------------------------------------

timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
dt_suffix <- format(Sys.time(), "%Y%m%d_%H%M%S")
safe_resp <- gsub("[^A-Za-z0-9_.-]", "_", response_name)
html_fname <- paste0("doe_design_", design_type, "_", safe_resp, "_", dt_suffix, ".html")
html_path  <- file.path(normalizePath(output_folder), html_fname)

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
  .btn-print {
    background: #2E5BBA;
    color: #fff;
    border: none;
    border-radius: 5px;
    padding: 8px 18px;
    font-size: 0.95em;
    cursor: pointer;
    white-space: nowrap;
  }
  .btn-print:hover { background: #244da0; }

  /* Page container */
  .container {
    max-width: 900px;
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
  .card p.sub {
    margin: -8px 0 16px;
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

  /* Footer */
  .footer {
    text-align: center;
    font-size: 0.80em;
    color: #888;
    margin-top: 32px;
    margin-bottom: 16px;
  }

  /* Responsive */
  @media (max-width: 600px) {
    .summary-grid { grid-template-columns: 1fr; }
    .header-bar { flex-direction: column; align-items: flex-start; }
    .container { padding: 16px 16px 32px; }
  }

  /* Print */
  @media print {
    .no-print { display: none !important; }
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

html_content <- paste0(
'<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>JR DoE Design Sheet &mdash; ', htmlEscape(response_name), '</title>
<style>', css_block, '</style>
</head>
<body>

<!-- Header bar -->
<div class="header-bar">
  <div>
    <h1>JR DoE Design Sheet</h1>
    <div class="subtitle">', htmlEscape(type_label),
    ' &mdash; Response: ', htmlEscape(response_name), '</div>
  </div>
  <button class="btn-print no-print" onclick="window.print()">Print</button>
</div>

<div class="container">

  <!-- Design Summary -->
  <div class="card">
    <h2>Design Summary</h2>
    <div class="summary-grid">
      <div class="summary-item">
        <span class="label">Design type</span>
        ', htmlEscape(type_label), '
      </div>
      <div class="summary-item">
        <span class="label">Response</span>
        ', htmlEscape(response_name), '
      </div>
      <div class="summary-item">
        <span class="label">Factors (k)</span>
        ', k, '
      </div>
      <div class="summary-item">
        <span class="label">Base runs</span>
        ', n_base, '
      </div>
      <div class="summary-item">
        <span class="label">Centre points</span>
        ', cp_display, '
      </div>
      <div class="summary-item">
        <span class="label">Replicates</span>
        ', rep_display, '
      </div>
      <div class="summary-item">
        <span class="label">Total runs</span>
        ', total_runs, '
      </div>
      <div class="summary-item">
        <span class="label">Randomisation seed</span>
        ', seed, '
      </div>
      <div class="summary-item">
        <span class="label">Generated</span>
        ', timestamp, '
      </div>
    </div>
  </div>

  <!-- Factor Definitions -->
  <div class="card">
    <h2>Factor Definitions</h2>
    <div class="table-wrap">
      <table>
        <thead>', factor_header_html, '</thead>
        <tbody>
', factor_rows_html, '
        </tbody>
      </table>
    </div>
  </div>

  <!-- Run Matrix -->
  <div class="card">
    <h2>Randomised Run Order &mdash; ', htmlEscape(response_name), '</h2>
    <p class="sub">Fill in the Response column as you run each experiment. Run in the order shown.</p>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Run</th>
            <th>Std Order</th>
            ', factor_col_headers, '
            <th>', htmlEscape(response_name), '</th>
          </tr>
        </thead>
        <tbody>
', run_rows_html, '
        </tbody>
      </table>
    </div>
  </div>

</div><!-- /container -->

<div class="footer">
  Generated by JR Validated Environment &middot; jrc_doe_design &middot; Seed: ', seed, '
</div>

</body>
</html>
')

# ---------------------------------------------------------------------------
# Write HTML file
# ---------------------------------------------------------------------------

writeLines(html_content, con = html_path, useBytes = FALSE)

# ---------------------------------------------------------------------------
# Write companion CSV file
# ---------------------------------------------------------------------------

csv_fname <- sub("\\.html$", ".csv", html_fname)
csv_path  <- file.path(normalizePath(output_folder), csv_fname)
con <- file(csv_path, open = "w")
writeLines(paste0("# jrc_doe_design: type=", design_type, ", response=", response_name), con)
close(con)
csv_df <- data.frame(
  run       = seq_len(total_runs),
  std_order = ifelse(is.na(final_std), "", as.character(final_std)),
  is_centre = final_centre,
  stringsAsFactors = FALSE
)
for (j in seq_len(k)) {
  csv_df[[factors_df$name[j]]] <- actual_mat[, j]
}
csv_df[[response_name]] <- ""
write.table(csv_df, file = csv_path, sep = ",", row.names = FALSE,
            col.names = TRUE, quote = FALSE, append = TRUE, na = "")

# ---------------------------------------------------------------------------
# Terminal summary
# ---------------------------------------------------------------------------

message(" ")
message(paste0("\u2705 Design generated: ", html_fname))
message(paste0("   Type:         ", type_label))
message(paste0("   Factors:      ", k))
if (centre_pts > 0L) {
  message(paste0("   Total runs:   ", total_runs,
                 "  (", n_base, " base + ", centre_pts, " centre point",
                 if (centre_pts == 1L) "" else "s", ")"))
} else {
  message(paste0("   Total runs:   ", total_runs))
}
if (!design_type %in% "pb") {
  message(paste0("   Replicates:   ", replicates))
}
message(paste0("   Seed:         ", seed))
message(paste0("   Saved to:     ", normalizePath(output_folder)))
message(paste0("   Data entry:   ", csv_fname))
message(" ")
jr_log_output_hashes(c(html_path, csv_path))
