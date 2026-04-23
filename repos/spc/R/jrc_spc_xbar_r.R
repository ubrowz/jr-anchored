# =============================================================================
# jrc_spc_xbar_r.R
# JR Validated Environment — SPC module
# Version: 1.1
#
# X-bar and R (Range) control chart for subgroup sizes 2 <= n <= 10.
# Reads a CSV with columns: subgroup, value (long format — multiple rows
# per subgroup). Computes control limits using Shewhart constants, applies
# all 8 Western Electric rules to the X-bar chart, applies Rule 1 only to
# the R chart, and saves a two-panel PNG to ~/Downloads/.
#
# Usage: jrc_spc_xbar_r <data.csv> [--ucl <value>] [--lcl <value>]
#
# Arguments:
#   data.csv        CSV file with columns: subgroup, value (long format)
#   --ucl <value>   Optional: user-specified UCL for the X-bar chart
#   --lcl <value>   Optional: user-specified LCL for the X-bar chart
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args        <- commandArgs(trailingOnly = TRUE)
want_report <- "--report" %in% args
args        <- args[args != "--report"]
if (length(args) == 0) {
  stop("Usage: jrc_spc_xbar_r <data.csv> [--ucl <value>] [--lcl <value>] [--report]")
}

csv_file  <- args[1]
user_ucl  <- NA_real_
user_lcl  <- NA_real_
i <- 2
while (i <= length(args)) {
  if (args[i] == "--ucl" && i < length(args)) {
    user_ucl <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(user_ucl)) stop("--ucl must be a numeric value.")
    i <- i + 2
  } else if (args[i] == "--lcl" && i < length(args)) {
    user_lcl <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(user_lcl)) stop("--lcl must be a numeric value.")
    i <- i + 2
  } else {
    i <- i + 1
  }
}

# ---------------------------------------------------------------------------
# Load from validated renv library
# ---------------------------------------------------------------------------
renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".", sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", Sys.getenv("JR_R_PLATFORM_DIR", unset = "macos"), r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))
source(file.path(Sys.getenv("JR_PROJECT_ROOT"), "bin", "jr_helpers.R"))

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(base64enc)
}))

# ---------------------------------------------------------------------------
# Report generator (requires JR Anchored Validation Pack)
# ---------------------------------------------------------------------------
save_xbar_r_report <- function(csv_file, k, n, X_dbar, R_bar, sigma_xbar,
                                UCL_xbar, LCL_xbar, UCL_R, LCL_R,
                                A2, D3, D4, user_ucl, user_lcl,
                                n_ooc_xbar, n_ooc_r, verdict,
                                subgroup_labels, sg_means, sg_ranges,
                                ooc_xbar, rules_xbar, png_path) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates",
                        "pv_report_template.html")
  if (!file.exists(sentinel)) {
    cat("⚠ --report requires the JR Anchored Validation Pack.\n")
    cat("  Install the pack and re-run to generate the Process Validation Report.\n")
    return(invisible(NULL))
  }

  ts        <- format(Sys.time(), "%Y%m%d_%H%M%S")
  report_id <- paste0("VR-XBR-", ts)
  generated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  chart_html <- ""
  if (!is.null(png_path) && file.exists(png_path)) {
    b64 <- base64enc::base64encode(png_path)
    chart_html <- sprintf(
      '<div class="chart-wrap"><img src="data:image/png;base64,%s" alt="X-bar R chart"/></div>', b64)
  }

  is_stable     <- verdict == "STABLE"
  verdict_class  <- if (is_stable) "verdict verdict-pass" else "verdict verdict-fail"
  verdict_symbol <- if (is_stable) "✅" else "❌"
  verdict_color  <- if (is_stable) "color:#155724" else "color:#721c24"
  verdict_html   <- sprintf("%s Process stability: %s", verdict_symbol,
                            if (is_stable) "STABLE — no Western Electric violations detected"
                            else sprintf("SIGNALS DETECTED — %d OOC subgroup(s)", n_ooc_xbar + n_ooc_r))

  spec_rows <- paste(
    '<tr><td class="l">LSL / USL</td><td>Not applicable — SPC monitoring chart</td></tr>',
    sprintf('<tr><td class="l">Subgroups (k)</td><td>%d</td></tr>', k),
    sprintf('<tr><td class="l">Subgroup size (n)</td><td>%d</td></tr>', n),
    sep = "\n"
  )

  method_rows <- paste(
    '<tr><td class="l">Chart type</td><td>X-bar and R (Range) — Shewhart control chart, AIAG SPC Reference Manual</td></tr>',
    sprintf('<tr><td class="l">Constants (n=%d)</td><td>A2 = %.3f, D3 = %.3f, D4 = %.3f</td></tr>', n, A2, D3, D4),
    sprintf('<tr><td class="l">Within-sigma (&sigma;̂)</td><td>A2 &times; R&#772; / 3 = %.6f</td></tr>', sigma_xbar),
    '<tr><td class="l">WE rules — X-bar</td><td>All 8 Western Electric (Nelson) rules</td></tr>',
    '<tr><td class="l">WE rules — R chart</td><td>Rule 1 only (point beyond 3&sigma;)</td></tr>',
    sep = "\n"
  )

  if (n_ooc_xbar > 0) {
    ooc_rows_html <- paste(sapply(seq_len(k), function(idx) {
      if (!ooc_xbar[idx]) return(NULL)
      rule_str <- paste(rules_xbar[[idx]], collapse = ", ")
      sprintf('<tr><td>%s</td><td style="font-family:monospace">%.6f</td><td style="font-family:monospace">%.6f</td><td>%s</td></tr>',
              as.character(subgroup_labels[idx]), sg_means[idx], sg_ranges[idx], rule_str)
    }), collapse = "\n")
    ooc_block <- sprintf(
      '<tr><td class="l">WE violations (X-bar)</td><td><table style="width:100%%;border-collapse:collapse;font-size:.88em"><tr><th style="text-align:left;padding:2px 6px">Subgroup</th><th style="text-align:left;padding:2px 6px">X-bar</th><th style="text-align:left;padding:2px 6px">Range</th><th style="text-align:left;padding:2px 6px">Rules</th></tr>%s</table></td></tr>',
      ooc_rows_html)
  } else {
    ooc_block <- '<tr><td class="l">WE violations (X-bar)</td><td>None</td></tr>'
  }

  results_rows <- paste(
    sprintf('<tr><td class="l">Grand mean (X&#773;&#773;)</td><td>%.6f</td></tr>', X_dbar),
    sprintf('<tr><td class="l">R&#772; (mean range)</td><td>%.6f</td></tr>', R_bar),
    sprintf('<tr><td class="l">UCL (X-bar)</td><td>%.6f%s</td></tr>', UCL_xbar,
            if (!is.na(user_ucl)) " <em>(user-specified)</em>" else ""),
    sprintf('<tr><td class="l">LCL (X-bar)</td><td>%.6f%s</td></tr>', LCL_xbar,
            if (!is.na(user_lcl)) " <em>(user-specified)</em>" else ""),
    sprintf('<tr><td class="l">UCL (R)</td><td>%.6f &nbsp;(D4 = %.3f)</td></tr>', UCL_R, D4),
    sprintf('<tr><td class="l">LCL (R)</td><td>%.6f &nbsp;(D3 = %.3f)</td></tr>', LCL_R, D3),
    sprintf('<tr><td class="l">OOC — X-bar chart</td><td>%d subgroup(s)</td></tr>', n_ooc_xbar),
    sprintf('<tr><td class="l">OOC — R chart</td><td>%d subgroup(s)</td></tr>', n_ooc_r),
    ooc_block,
    sep = "\n"
  )

  script_ver <- "jrc_spc_xbar_r v1.1 — JR Anchored"
  footer_txt <- sprintf("Generated by %s — %s", script_ver, generated)

  html <- readLines(sentinel, warn = FALSE)
  html <- paste(html, collapse = "\n")

  html <- gsub("{{subtitle}}",             "X-bar and R Control Chart — Shewhart", html, fixed = TRUE)
  html <- gsub("{{report_id}}",            report_id,          html, fixed = TRUE)
  html <- gsub("{{generated}}",            generated,          html, fixed = TRUE)
  html <- gsub("{{script_version}}",       script_ver,         html, fixed = TRUE)
  html <- gsub("{{acceptance_criterion}}", "No Western Electric rule violations on X-bar or R chart (STABLE verdict).", html, fixed = TRUE)
  html <- gsub("{{data_file}}",            basename(csv_file), html, fixed = TRUE)
  html <- gsub("{{col_name}}",             "value",            html, fixed = TRUE)
  html <- gsub("{{n}}",                    as.character(k * n),html, fixed = TRUE)
  html <- gsub("{{spec_rows}}",            spec_rows,          html, fixed = TRUE)
  html <- gsub("{{method_rows}}",          method_rows,        html, fixed = TRUE)
  html <- gsub("{{results_rows}}",         results_rows,       html, fixed = TRUE)
  html <- gsub("{{verdict_class}}",        verdict_class,      html, fixed = TRUE)
  html <- gsub("{{verdict_html}}",         verdict_html,       html, fixed = TRUE)
  html <- gsub("{{chart_html}}",           chart_html,         html, fixed = TRUE)
  html <- gsub("{{verdict_color}}",        verdict_color,      html, fixed = TRUE)
  html <- gsub("{{verdict_short}}",
               if (is_stable) "✅ STABLE" else "❌ SIGNALS DETECTED", html, fixed = TRUE)
  html <- gsub("{{footer}}",              footer_txt,          html, fixed = TRUE)

  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(ts, "_xbar_r_pv_report.html"))
  writeLines(html, out_path)
  cat(sprintf("✨ PV Report saved to: %s\n", out_path))
  invisible(out_path)
}

# ---------------------------------------------------------------------------
# Read and validate data
# ---------------------------------------------------------------------------
if (!file.exists(csv_file)) {
  stop(paste("\u274c File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

required_cols <- c("subgroup", "value")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: subgroup, value"))
}

dat$value <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$value))) {
  stop("\u274c Non-numeric or NA values found in the 'value' column.")
}

# Determine subgroup structure
subgroup_labels <- unique(dat$subgroup)
k               <- length(subgroup_labels)    # number of subgroups

if (k < 2) {
  stop("\u274c At least 2 subgroups are required.")
}

counts <- table(dat$subgroup)
subgroup_sizes <- as.integer(counts[as.character(subgroup_labels)])
n <- subgroup_sizes[1]

if (length(unique(subgroup_sizes)) > 1) {
  stop(paste("\u274c Unbalanced subgroups: sizes vary across subgroups.",
             "\n   All subgroups must have the same number of observations."))
}

if (n < 2 || n > 10) {
  stop(sprintf("\u274c Subgroup size n = %d is outside the supported range [2, 10].", n))
}

# ---------------------------------------------------------------------------
# Shewhart constants table  (A2, D3, D4)
# ---------------------------------------------------------------------------
const_tbl <- data.frame(
  n  = 2:10,
  A2 = c(1.880, 1.023, 0.729, 0.577, 0.483, 0.419, 0.373, 0.337, 0.308),
  D3 = c(0.000, 0.000, 0.000, 0.000, 0.000, 0.076, 0.136, 0.184, 0.223),
  D4 = c(3.267, 2.574, 2.282, 2.114, 2.004, 1.924, 1.864, 1.816, 1.777)
)

row_idx <- which(const_tbl$n == n)
A2      <- const_tbl$A2[row_idx]
D3      <- const_tbl$D3[row_idx]
D4      <- const_tbl$D4[row_idx]

# ---------------------------------------------------------------------------
# Subgroup statistics
# ---------------------------------------------------------------------------
sg_means <- numeric(k)
sg_ranges <- numeric(k)

for (idx in seq_len(k)) {
  vals          <- dat$value[dat$subgroup == subgroup_labels[idx]]
  sg_means[idx]  <- mean(vals)
  sg_ranges[idx] <- max(vals) - min(vals)
}

X_dbar <- mean(sg_means)
R_bar  <- mean(sg_ranges)

# Control limits
UCL_xbar  <- if (!is.na(user_ucl)) user_ucl else X_dbar + A2 * R_bar
LCL_xbar  <- if (!is.na(user_lcl)) user_lcl else X_dbar - A2 * R_bar
UCL_R     <- D4 * R_bar
LCL_R     <- D3 * R_bar

# Sigma for Western Electric rules on X-bar chart
sigma_xbar <- A2 * R_bar / 3

# ---------------------------------------------------------------------------
# Western Electric rules
# ---------------------------------------------------------------------------
apply_we_rules <- function(x, cl, sigma) {
  n     <- length(x)
  ooc   <- rep(FALSE, n)
  rules <- vector("list", n)
  for (idx in seq_len(n)) rules[[idx]] <- character(0)

  # Rule 1: 1 point beyond 3 sigma
  for (idx in seq_len(n)) {
    if (abs(x[idx] - cl) > 3 * sigma) {
      ooc[idx]   <- TRUE
      rules[[idx]] <- c(rules[[idx]], "1")
    }
  }

  # Rule 2: 9 consecutive points same side of centerline
  if (n >= 9) {
    side <- sign(x - cl)
    for (idx in 9:n) {
      window <- side[(idx - 8):idx]
      if (all(window == 1) || all(window == -1)) {
        for (j in (idx - 8):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "2")
        }
      }
    }
  }

  # Rule 3: 6 consecutive points steadily increasing or decreasing
  if (n >= 6) {
    for (idx in 6:n) {
      window <- x[(idx - 5):idx]
      diffs  <- diff(window)
      if (all(diffs > 0) || all(diffs < 0)) {
        for (j in (idx - 5):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "3")
        }
      }
    }
  }

  # Rule 4: 14 points alternating up and down
  if (n >= 14) {
    for (idx in 14:n) {
      window <- x[(idx - 13):idx]
      diffs  <- diff(window)
      alternating <- all(diffs[-length(diffs)] * diffs[-1] < 0)
      if (alternating) {
        for (j in (idx - 13):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "4")
        }
      }
    }
  }

  # Rule 5: 2 of 3 consecutive points beyond 2 sigma, same side
  if (n >= 3) {
    beyond2 <- (x - cl) / sigma
    for (idx in 3:n) {
      window <- beyond2[(idx - 2):idx]
      if (sum(window > 2) >= 2 || sum(window < -2) >= 2) {
        for (j in (idx - 2):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "5")
        }
      }
    }
  }

  # Rule 6: 4 of 5 consecutive points beyond 1 sigma, same side
  if (n >= 5) {
    beyond1 <- (x - cl) / sigma
    for (idx in 5:n) {
      window <- beyond1[(idx - 4):idx]
      if (sum(window > 1) >= 4 || sum(window < -1) >= 4) {
        for (j in (idx - 4):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "6")
        }
      }
    }
  }

  # Rule 7: 15 consecutive points within 1 sigma of centerline
  if (n >= 15) {
    within1 <- abs(x - cl) < sigma
    for (idx in 15:n) {
      if (all(within1[(idx - 14):idx])) {
        for (j in (idx - 14):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "7")
        }
      }
    }
  }

  # Rule 8: 8 consecutive points more than 1 sigma from centerline, either side
  if (n >= 8) {
    beyond1_either <- abs(x - cl) > sigma
    for (idx in 8:n) {
      if (all(beyond1_either[(idx - 7):idx])) {
        for (j in (idx - 7):idx) {
          ooc[j]   <- TRUE
          rules[[j]] <- c(rules[[j]], "8")
        }
      }
    }
  }

  # Deduplicate rule labels per point
  for (idx in seq_len(n)) {
    rules[[idx]] <- unique(rules[[idx]])
  }

  list(ooc = ooc, rules = rules)
}

we_xbar   <- apply_we_rules(sg_means, X_dbar, sigma_xbar)
ooc_xbar  <- we_xbar$ooc
rules_xbar <- we_xbar$rules

# Rule 1 only for R chart
ooc_r     <- abs(sg_ranges - R_bar) > 3 * (R_bar / 1.128)

n_ooc_xbar <- sum(ooc_xbar)
n_ooc_r    <- sum(ooc_r)

verdict <- if (n_ooc_xbar == 0 && n_ooc_r == 0) "STABLE" else "SIGNALS DETECTED"

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  X-bar and R Control Chart\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Subgroups (k): %d\n", k))
cat(sprintf("  Subgroup size (n): %d\n\n", n))

cat("--- Shewhart Constants ------------------------------------------\n")
cat(sprintf("  n = %d  |  A2 = %.3f  |  D3 = %.3f  |  D4 = %.3f\n\n",
            n, A2, D3, D4))

cat("--- Control Limits (X-bar) --------------------------------------\n")
cat(sprintf("  Grand mean (X-dbar): %s\n", sprintf("%.6f", X_dbar)))
cat(sprintf("  R-bar:               %s\n", sprintf("%.6f", R_bar)))
cat(sprintf("  Sigma (X-bar):       %s\n", sprintf("%.6f", sigma_xbar)))
if (!is.na(user_ucl)) {
  cat(sprintf("  UCL:                 %s  (user-specified)\n", sprintf("%.6f", UCL_xbar)))
} else {
  cat(sprintf("  UCL:                 %s\n", sprintf("%.6f", UCL_xbar)))
}
if (!is.na(user_lcl)) {
  cat(sprintf("  LCL:                 %s  (user-specified)\n", sprintf("%.6f", LCL_xbar)))
} else {
  cat(sprintf("  LCL:                 %s\n", sprintf("%.6f", LCL_xbar)))
}
cat("\n")

cat("--- Control Limits (R) ------------------------------------------\n")
cat(sprintf("  R-bar:  %s\n", sprintf("%.6f", R_bar)))
cat(sprintf("  UCL_R:  %s  (D4 = %.3f)\n", sprintf("%.6f", UCL_R), D4))
cat(sprintf("  LCL_R:  %s  (D3 = %.3f)\n", sprintf("%.6f", LCL_R), D3))
cat("\n")

cat("--- Process Stability -------------------------------------------\n")
if (n_ooc_xbar == 0) {
  cat("  IN CONTROL \u2014 no Western Electric violations detected\n")
} else {
  cat(sprintf("  OUT OF CONTROL \u2014 %d subgroup(s) flagged\n\n", n_ooc_xbar))
  cat(sprintf("  %-20s %12s %12s  %s\n", "Subgroup", "X-bar", "Range", "Rules"))
  for (idx in seq_len(k)) {
    if (ooc_xbar[idx]) {
      rule_str <- paste(rules_xbar[[idx]], collapse = ", ")
      cat(sprintf("  %-20s %12s %12s  [%s]\n",
                  as.character(subgroup_labels[idx]),
                  sprintf("%.6f", sg_means[idx]),
                  sprintf("%.6f", sg_ranges[idx]),
                  rule_str))
    }
  }
}
if (n_ooc_r > 0) {
  cat(sprintf("\n  R chart: %d subgroup(s) beyond UCL_R\n", n_ooc_r))
}
cat("\n")

cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_IC   <- "#1A1A2E"   # in-control points (navy)
COL_OOC  <- "#C0392B"   # out-of-control points (red)
COL_CL   <- "#2E5BBA"   # centerline
COL_UCL  <- "#C0392B"   # UCL/LCL lines
COL_2S   <- "#E67E22"   # 2-sigma zone lines
COL_1S   <- "#27AE60"   # 1-sigma zone lines
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
    axis.title       = element_text(size = 9)
  )

# Build X-bar chart data frame
xbar_df <- data.frame(
  idx      = seq_len(k),
  subgroup = as.character(subgroup_labels),
  value    = sg_means,
  ooc      = ooc_xbar,
  stringsAsFactors = FALSE
)

xbar_label_df <- xbar_df[xbar_df$ooc, ]

# Build R chart data frame
r_df <- data.frame(
  idx      = seq_len(k),
  subgroup = as.character(subgroup_labels),
  value    = sg_ranges,
  ooc      = ooc_r,
  stringsAsFactors = FALSE
)

r_label_df <- r_df[r_df$ooc, ]

# --- Panel 1: X-bar chart ---
p1 <- ggplot(xbar_df, aes(x = idx, y = value)) +
  # Zone lines
  geom_hline(yintercept = X_dbar + 2 * sigma_xbar, linetype = "dashed",
             color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = X_dbar - 2 * sigma_xbar, linetype = "dashed",
             color = COL_2S, linewidth = 0.5) +
  geom_hline(yintercept = X_dbar + sigma_xbar, linetype = "dashed",
             color = COL_1S, linewidth = 0.5) +
  geom_hline(yintercept = X_dbar - sigma_xbar, linetype = "dashed",
             color = COL_1S, linewidth = 0.5) +
  # UCL / LCL
  geom_hline(yintercept = UCL_xbar, linetype = "dashed",
             color = COL_UCL, linewidth = 0.7) +
  geom_hline(yintercept = LCL_xbar, linetype = "dashed",
             color = COL_UCL, linewidth = 0.7) +
  # Centerline
  geom_hline(yintercept = X_dbar, linetype = "solid",
             color = COL_CL, linewidth = 0.7) +
  # Data line and points
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 2, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  # OOC labels
  geom_text(data = xbar_label_df, aes(label = subgroup),
            nudge_y = 0.05 * diff(range(sg_means)), size = 2.8,
            color = COL_OOC) +
  scale_x_continuous(breaks = seq_len(k), labels = as.character(subgroup_labels)) +
  labs(title = "X-bar Chart", x = "Subgroup", y = "Subgroup Mean") +
  theme_jr +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

# --- Panel 2: R chart ---
p2 <- ggplot(r_df, aes(x = idx, y = value)) +
  # UCL
  geom_hline(yintercept = UCL_R, linetype = "dashed",
             color = COL_UCL, linewidth = 0.7) +
  # Centerline (R_bar)
  geom_hline(yintercept = R_bar, linetype = "solid",
             color = COL_CL, linewidth = 0.7) +
  # LCL (may be 0)
  geom_hline(yintercept = LCL_R, linetype = "dashed",
             color = COL_UCL, linewidth = 0.5, alpha = 0.5) +
  # Data line and points
  geom_line(color = "#555555", linewidth = 0.5) +
  geom_point(aes(color = ooc), size = 2, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  # OOC labels
  geom_text(data = r_label_df, aes(label = subgroup),
            nudge_y = 0.05 * diff(range(sg_ranges)), size = 2.8,
            color = COL_OOC) +
  scale_x_continuous(breaks = seq_len(k), labels = as.character(subgroup_labels)) +
  labs(title = "R Chart", x = "Subgroup", y = "Subgroup Range") +
  theme_jr +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_spc_xbar_r.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1800, res = 180, bg = BG)

grid.newpage()

pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

# Title strip
pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("X-bar & R Chart  |  %s  |  n = %d  |  k = %d  |  X-dbar = %.4f  |  %s",
          basename(csv_file), n, k, X_dbar, verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

# Two-panel vertical layout
pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 2, ncol = 1)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 2, layout.pos.col = 1))
popViewport()

dev.off()

report_path <- NULL
if (want_report) {
  report_path <- save_xbar_r_report(
    csv_file, k, n, X_dbar, R_bar, sigma_xbar,
    UCL_xbar, LCL_xbar, UCL_R, LCL_R,
    A2, D3, D4, user_ucl, user_lcl,
    n_ooc_xbar, n_ooc_r, verdict,
    subgroup_labels, sg_means, sg_ranges,
    ooc_xbar, rules_xbar, out_file
  )
}

cat(sprintf("\u2705 Done. Open %s to view your chart.\n", basename(out_file)))
jr_log_output_hashes(c(out_file, if (!is.null(report_path)) report_path else character(0)))
