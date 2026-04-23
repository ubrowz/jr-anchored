# =============================================================================
# jrc_spc_xbar_s.R
# JR Validated Environment — SPC module
# Version: 1.1
#
# X-bar and S (Standard Deviation) control chart.
# Reads a CSV with columns: subgroup, value (long format).
# Computes subgroup means and standard deviations, plots X-bar and S charts
# with all 8 Western Electric rules applied to the X-bar chart and Rule 1
# applied to the S chart. Saves a two-panel PNG to ~/Downloads/.
#
# Usage: jrc_spc_xbar_s <data.csv> [--ucl value] [--lcl value]
#
# Arguments:
#   data.csv        CSV file with columns: subgroup, value
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
  stop("Usage: jrc_spc_xbar_s <data.csv> [--ucl value] [--lcl value] [--report]")
}

csv_file    <- args[1]
user_ucl    <- NA_real_
user_lcl    <- NA_real_
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
save_xbar_s_report <- function(csv_file, k, n_sg, X_dbar, S_bar, sigma_x,
                                UCL_xbar, LCL_xbar, UCL_S, LCL_S,
                                c4_n, A3_n, B3_n, B4_n,
                                user_ucl, user_lcl,
                                ooc_xbar_labels, ooc_s_labels,
                                we_xbar_rules, we_s_rules,
                                verdict, total_obs, png_path) {
  sentinel <- file.path(Sys.getenv("JR_PROJECT_ROOT"), "docs", "templates",
                        "pv_report_template.html")
  if (!file.exists(sentinel)) {
    cat("⚠ --report requires the JR Anchored Validation Pack.\n")
    cat("  Install the pack and re-run to generate the Process Validation Report.\n")
    return(invisible(NULL))
  }

  ts        <- format(Sys.time(), "%Y%m%d_%H%M%S")
  report_id <- paste0("VR-XBS-", ts)
  generated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  chart_html <- ""
  if (!is.null(png_path) && file.exists(png_path)) {
    b64 <- base64enc::base64encode(png_path)
    chart_html <- sprintf(
      '<div class="chart-wrap"><img src="data:image/png;base64,%s" alt="X-bar S chart"/></div>', b64)
  }

  is_stable     <- verdict == "IN CONTROL"
  verdict_class  <- if (is_stable) "verdict verdict-pass" else "verdict verdict-fail"
  verdict_symbol <- if (is_stable) "✅" else "❌"
  verdict_color  <- if (is_stable) "color:#155724" else "color:#721c24"
  verdict_html   <- sprintf("%s Process stability: %s", verdict_symbol,
                            if (is_stable) "IN CONTROL — no Western Electric violations detected"
                            else sprintf("OUT OF CONTROL — OOC subgroups: %s",
                                         paste(unique(c(ooc_xbar_labels, ooc_s_labels)), collapse = ", ")))

  spec_rows <- paste(
    '<tr><td class="l">LSL / USL</td><td>Not applicable — SPC monitoring chart</td></tr>',
    sprintf('<tr><td class="l">Subgroups (k)</td><td>%d</td></tr>', k),
    sprintf('<tr><td class="l">Subgroup size (n)</td><td>%d</td></tr>', n_sg),
    sep = "\n"
  )

  method_rows <- paste(
    '<tr><td class="l">Chart type</td><td>X-bar and S (Standard Deviation) — Shewhart, AIAG SPC Reference Manual</td></tr>',
    sprintf('<tr><td class="l">Constants (n=%d)</td><td>c4 = %.6f, A3 = %.6f, B3 = %.6f, B4 = %.6f</td></tr>', n_sg, c4_n, A3_n, B3_n, B4_n),
    sprintf('<tr><td class="l">Within-sigma (&sigma;̂)</td><td>A3 &times; S&#772; / 3 = %.6f</td></tr>', sigma_x),
    '<tr><td class="l">WE rules — X-bar</td><td>All 8 Western Electric (Nelson) rules</td></tr>',
    '<tr><td class="l">WE rules — S chart</td><td>All 8 Western Electric rules</td></tr>',
    sep = "\n"
  )

  xbar_ooc_row <- if (length(ooc_xbar_labels) > 0)
    sprintf('<tr><td class="l">OOC — X-bar chart</td><td>%s (rules: %s)</td></tr>',
            paste(ooc_xbar_labels, collapse = ", "),
            if (length(we_xbar_rules) > 0) paste(we_xbar_rules, collapse = ", ") else "—")
  else
    '<tr><td class="l">OOC — X-bar chart</td><td>None</td></tr>'

  s_ooc_row <- if (length(ooc_s_labels) > 0)
    sprintf('<tr><td class="l">OOC — S chart</td><td>%s (rules: %s)</td></tr>',
            paste(ooc_s_labels, collapse = ", "),
            if (length(we_s_rules) > 0) paste(we_s_rules, collapse = ", ") else "—")
  else
    '<tr><td class="l">OOC — S chart</td><td>None</td></tr>'

  results_rows <- paste(
    sprintf('<tr><td class="l">Grand mean (X&#773;&#773;)</td><td>%.6f</td></tr>', X_dbar),
    sprintf('<tr><td class="l">S&#772; (mean std dev)</td><td>%.6f</td></tr>', S_bar),
    sprintf('<tr><td class="l">UCL (X-bar)</td><td>%.6f%s</td></tr>', UCL_xbar,
            if (!is.na(user_ucl)) " <em>(user-specified)</em>" else ""),
    sprintf('<tr><td class="l">LCL (X-bar)</td><td>%.6f%s</td></tr>', LCL_xbar,
            if (!is.na(user_lcl)) " <em>(user-specified)</em>" else ""),
    sprintf('<tr><td class="l">UCL (S)</td><td>%.6f &nbsp;(B4 = %.6f)</td></tr>', UCL_S, B4_n),
    sprintf('<tr><td class="l">LCL (S)</td><td>%.6f &nbsp;(B3 = %.6f)</td></tr>', LCL_S, B3_n),
    xbar_ooc_row,
    s_ooc_row,
    sep = "\n"
  )

  script_ver <- "jrc_spc_xbar_s v1.1 — JR Anchored"
  footer_txt <- sprintf("Generated by %s — %s", script_ver, generated)

  html <- readLines(sentinel, warn = FALSE)
  html <- paste(html, collapse = "\n")

  html <- gsub("{{subtitle}}",             "X-bar and S Control Chart — Shewhart", html, fixed = TRUE)
  html <- gsub("{{report_id}}",            report_id,           html, fixed = TRUE)
  html <- gsub("{{generated}}",            generated,           html, fixed = TRUE)
  html <- gsub("{{script_version}}",       script_ver,          html, fixed = TRUE)
  html <- gsub("{{acceptance_criterion}}", "No Western Electric rule violations on X-bar or S chart (IN CONTROL verdict).", html, fixed = TRUE)
  html <- gsub("{{data_file}}",            basename(csv_file),  html, fixed = TRUE)
  html <- gsub("{{col_name}}",             "value",             html, fixed = TRUE)
  html <- gsub("{{n}}",                    as.character(total_obs), html, fixed = TRUE)
  html <- gsub("{{spec_rows}}",            spec_rows,           html, fixed = TRUE)
  html <- gsub("{{method_rows}}",          method_rows,         html, fixed = TRUE)
  html <- gsub("{{results_rows}}",         results_rows,        html, fixed = TRUE)
  html <- gsub("{{verdict_class}}",        verdict_class,       html, fixed = TRUE)
  html <- gsub("{{verdict_html}}",         verdict_html,        html, fixed = TRUE)
  html <- gsub("{{chart_html}}",           chart_html,          html, fixed = TRUE)
  html <- gsub("{{verdict_color}}",        verdict_color,       html, fixed = TRUE)
  html <- gsub("{{verdict_short}}",
               if (is_stable) "✅ IN CONTROL" else "❌ OUT OF CONTROL", html, fixed = TRUE)
  html <- gsub("{{footer}}",              footer_txt,           html, fixed = TRUE)

  out_path <- file.path(path.expand("~/Downloads"),
                        paste0(ts, "_xbar_s_pv_report.html"))
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

dat$subgroup <- as.character(dat$subgroup)
dat$value    <- suppressWarnings(as.numeric(dat$value))

if (any(is.na(dat$value))) {
  stop("\u274c Non-numeric values found in the 'value' column.")
}

# Compute subgroup sizes and check balance
sg_labels  <- unique(dat$subgroup)
sg_counts  <- tapply(dat$value, dat$subgroup, length)
n_unique   <- unique(as.vector(sg_counts))

if (length(sg_labels) < 2) {
  stop("\u274c At least 2 subgroups are required.")
}
if (any(n_unique < 2)) {
  stop("\u274c All subgroups must have at least 2 observations.")
}
if (length(n_unique) > 1) {
  stop(paste("\u274c Unbalanced subgroups: sizes", paste(sort(n_unique), collapse = "/"),
             "found.\n   All subgroups must be the same size for X-bar/S chart."))
}

n_sg <- n_unique[1]   # common subgroup size

# ---------------------------------------------------------------------------
# Analytical control chart constants (no lookup table)
# ---------------------------------------------------------------------------
c4 <- function(n) sqrt(2 / (n - 1)) * gamma(n / 2) / gamma((n - 1) / 2)
A3 <- function(n) 3 / (c4(n) * sqrt(n))
B3 <- function(n) max(0, 1 - 3 * sqrt(1 - c4(n)^2) / c4(n))
B4 <- function(n) 1 + 3 * sqrt(1 - c4(n)^2) / c4(n)

c4_n <- c4(n_sg)
A3_n <- A3(n_sg)
B3_n <- B3(n_sg)
B4_n <- B4(n_sg)

# ---------------------------------------------------------------------------
# Subgroup statistics
# ---------------------------------------------------------------------------
x_bar_i <- tapply(dat$value, dat$subgroup, mean)[sg_labels]
s_i     <- tapply(dat$value, dat$subgroup, sd)[sg_labels]

X_dbar  <- mean(x_bar_i)
S_bar   <- mean(s_i)

# X-bar chart limits
UCL_xbar <- X_dbar + A3_n * S_bar
LCL_xbar <- X_dbar - A3_n * S_bar
sigma_x  <- A3_n * S_bar / 3

# Override with user-specified limits if provided
if (!is.na(user_ucl)) UCL_xbar <- user_ucl
if (!is.na(user_lcl)) LCL_xbar <- user_lcl

# S chart limits
UCL_S <- B4_n * S_bar
LCL_S <- B3_n * S_bar

# ---------------------------------------------------------------------------
# Western Electric rules helper
# ---------------------------------------------------------------------------
apply_we_rules <- function(x, cl, sigma) {
  n   <- length(x)
  ooc <- logical(n)   # TRUE = out-of-control
  rules_fired <- character(0)

  # Rule 1: beyond 3 sigma
  r1 <- abs(x - cl) > 3 * sigma
  if (any(r1)) { ooc <- ooc | r1; rules_fired <- c(rules_fired, "Rule 1") }

  # Rule 2: 9 consecutive points same side
  if (n >= 9) {
    side <- sign(x - cl)
    for (j in 9:n) {
      s9 <- side[(j - 8):j]
      if (all(s9 == 1) || all(s9 == -1)) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 2"))
      }
    }
  }

  # Rule 3: 6 points in a row steadily increasing or decreasing
  if (n >= 6) {
    for (j in 6:n) {
      seg <- x[(j - 5):j]
      if (all(diff(seg) > 0) || all(diff(seg) < 0)) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 3"))
      }
    }
  }

  # Rule 4: 14 points in a row alternating up and down
  if (n >= 14) {
    for (j in 14:n) {
      seg <- x[(j - 13):j]
      d   <- diff(seg)
      if (all(d[-length(d)] * d[-1] < 0)) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 4"))
      }
    }
  }

  # Rule 5: 2 out of 3 consecutive points beyond 2 sigma on same side
  if (n >= 3) {
    beyond2 <- (x - cl) / sigma
    for (j in 3:n) {
      seg <- beyond2[(j - 2):j]
      if (sum(seg > 2) >= 2 || sum(seg < -2) >= 2) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 5"))
      }
    }
  }

  # Rule 6: 4 out of 5 consecutive points beyond 1 sigma on same side
  if (n >= 5) {
    beyond1 <- (x - cl) / sigma
    for (j in 5:n) {
      seg <- beyond1[(j - 4):j]
      if (sum(seg > 1) >= 4 || sum(seg < -1) >= 4) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 6"))
      }
    }
  }

  # Rule 7: 15 consecutive points within 1 sigma of centreline
  if (n >= 15) {
    within1 <- abs(x - cl) < sigma
    for (j in 15:n) {
      if (all(within1[(j - 14):j])) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 7"))
      }
    }
  }

  # Rule 8: 8 consecutive points on both sides of centreline with none within 1 sigma
  if (n >= 8) {
    outside1 <- abs(x - cl) > sigma
    for (j in 8:n) {
      seg <- x[(j - 7):j]
      if (all(outside1[(j - 7):j]) &&
          (any(seg > cl) && any(seg < cl))) {
        ooc[j] <- TRUE
        rules_fired <- unique(c(rules_fired, "Rule 8"))
      }
    }
  }

  list(ooc = ooc, rules = rules_fired)
}

# ---------------------------------------------------------------------------
# Apply WE rules
# ---------------------------------------------------------------------------
we_xbar <- apply_we_rules(as.numeric(x_bar_i), cl = X_dbar,  sigma = sigma_x)
we_s    <- apply_we_rules(as.numeric(s_i),      cl = S_bar,   sigma = (UCL_S - S_bar) / 3)

ooc_xbar <- sg_labels[we_xbar$ooc]
ooc_s    <- sg_labels[we_s$ooc]

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
cat("\n")
cat("=================================================================\n")
cat("  X-bar and S Control Chart\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Subgroups:      %d\n", length(sg_labels)))
cat(sprintf("  Subgroup size:  %d\n", n_sg))
cat(sprintf("  Total obs:      %d\n\n", length(dat$value)))

cat("--- Chart Constants ---------------------------------------------\n")
cat(sprintf("  c4(n=%d):  %.6f\n", n_sg, c4_n))
cat(sprintf("  A3(n=%d):  %.6f\n", n_sg, A3_n))
cat(sprintf("  B3(n=%d):  %.6f\n", n_sg, B3_n))
cat(sprintf("  B4(n=%d):  %.6f\n", n_sg, B4_n))
cat("\n")

cat("--- X-bar Chart -------------------------------------------------\n")
cat(sprintf("  Grand mean (X-dbar): %.6f\n", X_dbar))
cat(sprintf("  S-bar:               %.6f\n", S_bar))
if (!is.na(user_ucl) || !is.na(user_lcl)) {
  cat("  Limits: user-specified\n")
}
cat(sprintf("  UCL:                 %.6f\n", UCL_xbar))
cat(sprintf("  LCL:                 %.6f\n", LCL_xbar))
cat(sprintf("  WE rules fired:      %s\n",
            if (length(we_xbar$rules) == 0) "none" else paste(we_xbar$rules, collapse = ", ")))
if (length(ooc_xbar) > 0) {
  cat(sprintf("  OOC subgroups:       %s\n", paste(ooc_xbar, collapse = ", ")))
} else {
  cat("  OOC subgroups:       none\n")
}
cat("\n")

cat("--- S Chart -----------------------------------------------------\n")
cat(sprintf("  S-bar:               %.6f\n", S_bar))
cat(sprintf("  UCL:                 %.6f\n", UCL_S))
cat(sprintf("  LCL:                 %.6f\n", LCL_S))
cat(sprintf("  WE rules fired:      %s\n",
            if (length(we_s$rules) == 0) "none" else paste(we_s$rules, collapse = ", ")))
if (length(ooc_s) > 0) {
  cat(sprintf("  OOC subgroups:       %s\n", paste(ooc_s, collapse = ", ")))
} else {
  cat("  OOC subgroups:       none\n")
}

total_ooc <- unique(c(ooc_xbar, ooc_s))
verdict   <- if (length(total_ooc) == 0) "IN CONTROL" else "OUT OF CONTROL"
cat("\n")
cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
COL_IC   <- "#1F3A6E"   # navy — in control
COL_OOC  <- "#CC2222"   # red   — out of control
COL_CL   <- "#444444"
COL_WARN <- "#E8891A"
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

idx <- seq_along(sg_labels)

# --- X-bar panel ---
df_xbar <- data.frame(
  idx      = idx,
  label    = sg_labels,
  value    = as.numeric(x_bar_i),
  ooc      = we_xbar$ooc,
  stringsAsFactors = FALSE
)

p_xbar <- ggplot(df_xbar, aes(x = idx, y = value)) +
  geom_hline(yintercept = X_dbar,  color = COL_CL,   linewidth = 0.8) +
  geom_hline(yintercept = UCL_xbar, color = COL_OOC,  linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = LCL_xbar, color = COL_OOC,  linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = X_dbar + 2 * sigma_x, color = COL_WARN, linewidth = 0.4, linetype = "dotted") +
  geom_hline(yintercept = X_dbar - 2 * sigma_x, color = COL_WARN, linewidth = 0.4, linetype = "dotted") +
  geom_hline(yintercept = X_dbar +     sigma_x, color = COL_WARN, linewidth = 0.3, linetype = "dotted") +
  geom_hline(yintercept = X_dbar -     sigma_x, color = COL_WARN, linewidth = 0.3, linetype = "dotted") +
  geom_line(color = COL_IC, linewidth = 0.6) +
  geom_point(aes(color = ooc), size = 2.5, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  scale_x_continuous(breaks = idx, labels = sg_labels) +
  labs(title = "X-bar Chart", x = "Subgroup", y = "Subgroup Mean") +
  theme_jr +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

# Add limit labels
p_xbar <- p_xbar +
  annotate("text", x = max(idx), y = UCL_xbar,  label = sprintf("UCL=%.4f", UCL_xbar),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_OOC) +
  annotate("text", x = max(idx), y = LCL_xbar,  label = sprintf("LCL=%.4f", LCL_xbar),
           hjust = 1.05, vjust =  1.2, size = 2.8, color = COL_OOC) +
  annotate("text", x = max(idx), y = X_dbar,    label = sprintf("CL=%.4f",  X_dbar),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_CL)

# --- S panel ---
sigma_s <- (UCL_S - S_bar) / 3
df_s <- data.frame(
  idx   = idx,
  label = sg_labels,
  value = as.numeric(s_i),
  ooc   = we_s$ooc,
  stringsAsFactors = FALSE
)

p_s <- ggplot(df_s, aes(x = idx, y = value)) +
  geom_hline(yintercept = S_bar,  color = COL_CL,  linewidth = 0.8) +
  geom_hline(yintercept = UCL_S,  color = COL_OOC, linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = LCL_S,  color = COL_OOC, linewidth = 0.6, linetype = "dashed") +
  geom_line(color = COL_IC, linewidth = 0.6) +
  geom_point(aes(color = ooc), size = 2.5, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  scale_x_continuous(breaks = idx, labels = sg_labels) +
  labs(title = "S Chart", x = "Subgroup", y = "Subgroup Std Dev") +
  theme_jr +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

p_s <- p_s +
  annotate("text", x = max(idx), y = UCL_S,  label = sprintf("UCL=%.4f", UCL_S),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_OOC) +
  annotate("text", x = max(idx), y = LCL_S,  label = sprintf("LCL=%.4f", LCL_S),
           hjust = 1.05, vjust =  1.2, size = 2.8, color = COL_OOC) +
  annotate("text", x = max(idx), y = S_bar,  label = sprintf("CL=%.4f",  S_bar),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_CL)

# ---------------------------------------------------------------------------
# Combine panels and save
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_spc_xbar_s.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1800, res = 180, bg = BG)

grid.newpage()

pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.06, 0.94), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("X-bar / S Chart  |  %s  |  n=%d  |  Subgroups=%d  |  %s",
          basename(csv_file), n_sg, length(sg_labels), verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2,
                      layout = grid.layout(nrow = 2, ncol = 1)))
print(p_xbar, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p_s,    vp = viewport(layout.pos.row = 2, layout.pos.col = 1))
popViewport()

dev.off()

report_path <- NULL
if (want_report) {
  report_path <- save_xbar_s_report(
    csv_file, length(sg_labels), n_sg, X_dbar, S_bar, sigma_x,
    UCL_xbar, LCL_xbar, UCL_S, LCL_S,
    c4_n, A3_n, B3_n, B4_n,
    user_ucl, user_lcl,
    ooc_xbar, ooc_s,
    we_xbar$rules, we_s$rules,
    verdict, length(dat$value), out_file
  )
}

cat(sprintf("\u2705 Done. Open %s to view your chart.\n", basename(out_file)))
jr_log_output_hashes(c(out_file, if (!is.null(report_path)) report_path else character(0)))
