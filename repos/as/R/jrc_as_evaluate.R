# =============================================================================
# jrc_as_evaluate.R
# JR Validated Environment — Acceptance Sampling module
#
# Apply a sampling plan to actual lot inspection data and produce an
# ACCEPT/REJECT verdict.
#
# Usage (attributes):
#   jrc_as_evaluate <data.csv> --type attributes --c <int>
#
# Usage (variables):
#   jrc_as_evaluate <data.csv> --type variables --k <value> [--lsl value] [--usl value]
#
# Arguments:
#   data.csv            CSV file (see format below)
#   --type              "attributes" or "variables"
#   --c <int>           Attributes mode: acceptance number
#   --k <value>         Variables mode: acceptability constant
#   --lsl <value>       Variables mode: lower specification limit
#   --usl <value>       Variables mode: upper specification limit
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop(paste("Usage: jrc_as_evaluate <data.csv> --type attributes --c <int>",
             "\n       jrc_as_evaluate <data.csv> --type variables --k <value> [--lsl value] [--usl value]"))
}

if (length(args) < 1) {
  stop("Usage: jrc_as_evaluate <data.csv> --type <attributes|variables> ...")
}

csv_file  <- args[1]
eval_type <- NA_character_
c_acc     <- NA_integer_
k_val     <- NA_real_
lsl_val   <- NA_real_
usl_val   <- NA_real_

i <- 2
while (i <= length(args)) {
  if (args[i] == "--type" && i < length(args)) {
    eval_type <- args[i + 1]
    if (!(eval_type %in% c("attributes", "variables"))) {
      stop("--type must be 'attributes' or 'variables'.")
    }
    i <- i + 2
  } else if (args[i] == "--c" && i < length(args)) {
    c_acc <- suppressWarnings(as.integer(args[i + 1]))
    if (is.na(c_acc) || c_acc < 0) stop("--c must be a non-negative integer.")
    i <- i + 2
  } else if (args[i] == "--k" && i < length(args)) {
    k_val <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(k_val)) stop("--k must be numeric.")
    i <- i + 2
  } else if (args[i] == "--lsl" && i < length(args)) {
    lsl_val <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(lsl_val)) stop("--lsl must be numeric.")
    i <- i + 2
  } else if (args[i] == "--usl" && i < length(args)) {
    usl_val <- suppressWarnings(as.numeric(args[i + 1]))
    if (is.na(usl_val)) stop("--usl must be numeric.")
    i <- i + 2
  } else {
    i <- i + 1
  }
}

if (is.na(eval_type)) {
  stop("--type is required. Use --type attributes or --type variables.")
}

if (eval_type == "attributes" && is.na(c_acc)) {
  stop("--c (acceptance number) is required for attributes mode.")
}

if (eval_type == "variables") {
  if (is.na(k_val)) stop("--k (acceptability constant) is required for variables mode.")
  if (is.na(lsl_val) && is.na(usl_val)) {
    stop("At least one of --lsl or --usl must be provided for variables mode.")
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
}))

# ---------------------------------------------------------------------------
# Read data
# ---------------------------------------------------------------------------

if (!file.exists(csv_file)) {
  stop(paste("\u274c File not found:", csv_file))
}

dat <- tryCatch(
  read.csv(csv_file, stringsAsFactors = FALSE),
  error = function(e) stop(paste("\u274c Could not read CSV:", e$message))
)

names(dat) <- tolower(trimws(names(dat)))

# ---------------------------------------------------------------------------
# Attributes mode
# ---------------------------------------------------------------------------

if (eval_type == "attributes") {
  if (!("result" %in% names(dat))) {
    stop("\u274c Missing column: result\n   Required columns: id, result (0=conforming, 1=defective)")
  }
  dat$result <- suppressWarnings(as.integer(dat$result))
  if (any(is.na(dat$result))) {
    stop("\u274c Non-integer or NA values found in the 'result' column.")
  }

  n_lot    <- nrow(dat)
  n_defect <- sum(dat$result)
  verdict  <- if (n_defect <= c_acc) "ACCEPT" else "REJECT"

  cat("\n")
  cat("=================================================================\n")
  cat("  Acceptance Sampling Evaluation \u2014 Attributes\n")
  cat(sprintf("  File: %s\n", basename(csv_file)))
  cat("=================================================================\n")
  cat(sprintf("  Lot inspected (n):   %d\n", n_lot))
  cat(sprintf("  Defectives found:    %d\n", n_defect))
  cat(sprintf("  Acceptance number:   %d\n\n", c_acc))

  if (verdict == "ACCEPT") {
    cat(sprintf("  Verdict: ACCEPT   (d = %d \u2264 c = %d)\n", n_defect, c_acc))
  } else {
    cat(sprintf("  Verdict: REJECT   (d = %d > c = %d)\n", n_defect, c_acc))
  }
  cat("=================================================================\n\n")

  # Plot — bar chart
  COL_ACCEPT <- "#2E5BBA"
  COL_REJECT <- "#C0392B"
  BG         <- "#FFFFFF"
  GRID_COL   <- "#EEEEEE"
  bar_color  <- if (verdict == "ACCEPT") COL_ACCEPT else COL_REJECT

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

  bar_df <- data.frame(label = "Defectives", value = n_defect)
  p_bar <- ggplot(bar_df, aes(x = label, y = value)) +
    geom_col(fill = bar_color, width = 0.4) +
    geom_hline(yintercept = c_acc, linetype = "dashed",
               color = "#555555", linewidth = 0.8) +
    annotate("text", x = 1.35, y = c_acc, label = sprintf("c = %d", c_acc),
             vjust = -0.5, size = 3.5, color = "#555555") +
    annotate("text", x = 1, y = n_defect / 2,
             label = sprintf("%s\nd = %d", verdict, n_defect),
             size = 5, fontface = "bold", color = "white") +
    labs(title = sprintf("Attributes Evaluation  |  %s  |  d=%d  c=%d",
                         basename(csv_file), n_defect, c_acc),
         x = NULL, y = "Number of Defectives") +
    theme_jr

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_file <- file.path(path.expand("~/Downloads"),
                        paste0(datetime_pfx, "_jrc_as_evaluate.png"))

  cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

  png(out_file, width = 2400, height = 1600, res = 180, bg = BG)
  grid.newpage()
  pushViewport(viewport(layout = grid.layout(
    nrow = 2, ncol = 1, heights = unit(c(0.06, 0.94), "npc")
  )))
  pushViewport(viewport(layout.pos.row = 1))
  grid.rect(gp = gpar(fill = if (verdict == "ACCEPT") "#2E5BBA" else "#C0392B", col = NA))
  grid.text(
    sprintf("Attributes Evaluation  |  %s  |  %s  (d=%d, c=%d)",
            basename(csv_file), verdict, n_defect, c_acc),
    gp = gpar(col = "white", fontsize = 10, fontface = "bold")
  )
  popViewport()
  pushViewport(viewport(layout.pos.row = 2))
  print(p_bar, vp = viewport())
  popViewport()
  dev.off()

  cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
  jr_log_output_hashes(c(out_file))
}

# ---------------------------------------------------------------------------
# Variables mode
# ---------------------------------------------------------------------------

if (eval_type == "variables") {
  if (!("value" %in% names(dat))) {
    stop("\u274c Missing column: value\n   Required columns: id, value")
  }
  dat$value <- suppressWarnings(as.numeric(dat$value))
  if (any(is.na(dat$value))) {
    stop("\u274c Non-numeric or NA values found in the 'value' column.")
  }

  n_samp  <- nrow(dat)
  x_bar   <- mean(dat$value)
  s_val   <- sd(dat$value)

  q_l <- NA_real_
  q_u <- NA_real_
  accept <- TRUE

  if (!is.na(lsl_val)) {
    q_l <- (x_bar - lsl_val) / s_val
    if (q_l < k_val) accept <- FALSE
  }
  if (!is.na(usl_val)) {
    q_u <- (usl_val - x_bar) / s_val
    if (q_u < k_val) accept <- FALSE
  }

  verdict <- if (accept) "ACCEPT" else "REJECT"

  cat("\n")
  cat("=================================================================\n")
  cat("  Acceptance Sampling Evaluation \u2014 Variables (k-method)\n")
  cat(sprintf("  File: %s\n", basename(csv_file)))
  cat("=================================================================\n")
  cat(sprintf("  Sample size (n):   %d\n", n_samp))
  cat(sprintf("  Sample mean (x\u0305):  %.4f\n", x_bar))
  cat(sprintf("  Sample SD  (s):    %.4f\n\n", s_val))

  if (!is.na(lsl_val)) {
    status <- if (q_l >= k_val) "\u2705" else "\u274c"
    cat(sprintf("  LSL = %.4f   Q_L = (%.4f - %.4f) / %.4f = %.3f %s k = %.4f %s\n",
                lsl_val, x_bar, lsl_val, s_val, q_l,
                if (q_l >= k_val) "\u2265" else "<", k_val, status))
  }
  if (!is.na(usl_val)) {
    status <- if (q_u >= k_val) "\u2705" else "\u274c"
    cat(sprintf("  USL = %.4f   Q_U = (%.4f - %.4f) / %.4f = %.3f %s k = %.4f %s\n",
                usl_val, usl_val, x_bar, s_val, q_u,
                if (q_u >= k_val) "\u2265" else "<", k_val, status))
  }

  cat(sprintf("\n  Verdict: %s\n", verdict))
  cat("=================================================================\n\n")

  # Plot — histogram with spec lines
  BG       <- "#FFFFFF"
  GRID_COL <- "#EEEEEE"
  COL_CL   <- "#2E5BBA"
  COL_OOC  <- "#C0392B"
  verdict_color <- if (accept) "#2E5BBA" else "#C0392B"

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

  p_hist <- ggplot(dat, aes(x = value)) +
    geom_histogram(bins = max(5L, as.integer(sqrt(n_samp))),
                   fill = COL_CL, color = "white", alpha = 0.8) +
    geom_vline(xintercept = x_bar, color = "#1A1A2E",
               linewidth = 1, linetype = "solid") +
    labs(title = sprintf("Variables Evaluation  |  %s  |  %s",
                         basename(csv_file), verdict),
         x = "Value", y = "Count") +
    theme_jr

  if (!is.na(lsl_val)) {
    p_hist <- p_hist +
      geom_vline(xintercept = lsl_val, color = COL_OOC,
                 linewidth = 0.8, linetype = "dashed") +
      annotate("text", x = lsl_val, y = Inf,
               label = sprintf("LSL\n%.4f", lsl_val),
               vjust = 1.5, hjust = 1.1, size = 3, color = COL_OOC)
  }
  if (!is.na(usl_val)) {
    p_hist <- p_hist +
      geom_vline(xintercept = usl_val, color = COL_OOC,
                 linewidth = 0.8, linetype = "dashed") +
      annotate("text", x = usl_val, y = Inf,
               label = sprintf("USL\n%.4f", usl_val),
               vjust = 1.5, hjust = -0.1, size = 3, color = COL_OOC)
  }

  # Annotation text box
  ann_lines <- c(sprintf("n = %d", n_samp),
                 sprintf("x\u0305 = %.4f", x_bar),
                 sprintf("s = %.4f", s_val),
                 sprintf("k = %.4f", k_val))
  if (!is.na(q_l)) ann_lines <- c(ann_lines, sprintf("Q_L = %.3f", q_l))
  if (!is.na(q_u)) ann_lines <- c(ann_lines, sprintf("Q_U = %.3f", q_u))
  ann_lines <- c(ann_lines, sprintf("Verdict: %s", verdict))
  ann_text  <- paste(ann_lines, collapse = "\n")

  p_hist <- p_hist +
    annotate("label", x = Inf, y = Inf, label = ann_text,
             hjust = 1.05, vjust = 1.05, size = 3,
             color = verdict_color, fill = "#FFFFFF",
             label.size = 0.3, fontface = "bold")

  datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_file <- file.path(path.expand("~/Downloads"),
                        paste0(datetime_pfx, "_jrc_as_evaluate.png"))

  cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

  png(out_file, width = 2400, height = 1600, res = 180, bg = BG)
  grid.newpage()
  pushViewport(viewport(layout = grid.layout(
    nrow = 2, ncol = 1, heights = unit(c(0.06, 0.94), "npc")
  )))
  pushViewport(viewport(layout.pos.row = 1))
  grid.rect(gp = gpar(fill = verdict_color, col = NA))
  grid.text(
    sprintf("Variables Evaluation  |  %s  |  %s  (k=%.4f)",
            basename(csv_file), verdict, k_val),
    gp = gpar(col = "white", fontsize = 10, fontface = "bold")
  )
  popViewport()
  pushViewport(viewport(layout.pos.row = 2))
  print(p_hist, vp = viewport())
  popViewport()
  dev.off()

  cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
  jr_log_output_hashes(c(out_file))
}
