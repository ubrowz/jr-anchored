# =============================================================================
# jrc_spc_p.R
# JR Validated Environment — SPC module
#
# P-chart (proportion defective / nonconforming).
# Supports variable subgroup sizes.
# Reads a CSV with columns: subgroup, n, defectives.
# Computes per-subgroup control limits, applies all 8 Western Electric rules
# to standardised values, and saves a single-panel PNG to ~/Downloads/.
#
# Usage: jrc_spc_p <data.csv>
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrc_spc_p <data.csv>")
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
lib_path <- file.path(renv_lib, "renv", "library", "macos", r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
}))

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

required_cols <- c("subgroup", "n", "defectives")
missing_cols  <- setdiff(required_cols, names(dat))
if (length(missing_cols) > 0) {
  stop(paste("\u274c Missing column(s):", paste(missing_cols, collapse = ", "),
             "\n   Required: subgroup, n, defectives"))
}

dat$subgroup   <- as.character(dat$subgroup)
dat$n          <- suppressWarnings(as.integer(dat$n))
dat$defectives <- suppressWarnings(as.integer(dat$defectives))

if (any(is.na(dat$n))) {
  stop("\u274c Non-integer values found in the 'n' column.")
}
if (any(is.na(dat$defectives))) {
  stop("\u274c Non-integer values found in the 'defectives' column.")
}
if (any(dat$n < 1)) {
  stop("\u274c All subgroup sizes n must be >= 1.")
}
if (any(dat$defectives < 0)) {
  stop("\u274c 'defectives' must be non-negative.")
}
if (any(dat$defectives > dat$n)) {
  bad <- dat$subgroup[dat$defectives > dat$n]
  stop(paste("\u274c defectives > n in subgroup(s):", paste(bad, collapse = ", ")))
}
if (nrow(dat) < 2) {
  stop("\u274c At least 2 subgroups are required.")
}

# ---------------------------------------------------------------------------
# P-chart calculations
# ---------------------------------------------------------------------------
p_bar <- sum(dat$defectives) / sum(dat$n)
p_i   <- dat$defectives / dat$n

se_i    <- sqrt(p_bar * (1 - p_bar) / dat$n)
UCL_i   <- p_bar + 3 * se_i
LCL_i   <- pmax(0, p_bar - 3 * se_i)
UCL2_i  <- p_bar + 2 * se_i    # 2-sigma warning line
LCL2_i  <- pmax(0, p_bar - 2 * se_i)
UCL1_i  <- p_bar + 1 * se_i    # 1-sigma zone line
LCL1_i  <- pmax(0, p_bar - 1 * se_i)

n_varies <- length(unique(dat$n)) > 1

# Standardised values for WE rules
z_i <- (p_i - p_bar) / se_i

# ---------------------------------------------------------------------------
# Western Electric rules helper (operates on standardised values)
# ---------------------------------------------------------------------------
apply_we_rules <- function(x, cl, sigma) {
  n   <- length(x)
  ooc <- logical(n)
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

  # Rule 8: 8 consecutive points on both sides with none within 1 sigma
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

# Apply WE rules to standardised values (cl=0, sigma=1)
we <- apply_we_rules(z_i, cl = 0, sigma = 1)
ooc_labels <- dat$subgroup[we$ooc]

# ---------------------------------------------------------------------------
# Terminal output
# ---------------------------------------------------------------------------
verdict <- if (length(ooc_labels) == 0) "IN CONTROL" else "OUT OF CONTROL"

cat("\n")
cat("=================================================================\n")
cat("  P-Chart (Proportion Nonconforming)\n")
cat(sprintf("  File: %s\n", basename(csv_file)))
cat("=================================================================\n\n")

cat(sprintf("  Subgroups:       %d\n", nrow(dat)))
cat(sprintf("  Total inspected: %d\n", sum(dat$n)))
cat(sprintf("  Total defective: %d\n", sum(dat$defectives)))
cat(sprintf("  p-bar:           %.6f\n", p_bar))
if (n_varies) {
  cat(sprintf("  Subgroup sizes:  variable (%d to %d)\n",
              min(dat$n), max(dat$n)))
  cat("  Note: per-subgroup limits vary with n.\n")
} else {
  cat(sprintf("  Subgroup size:   %d (constant)\n", dat$n[1]))
  cat(sprintf("  UCL:             %.6f\n", UCL_i[1]))
  cat(sprintf("  LCL:             %.6f\n", LCL_i[1]))
}
cat("\n")

cat("--- WE Rules ----------------------------------------------------\n")
cat(sprintf("  Rules fired:  %s\n",
            if (length(we$rules) == 0) "none" else paste(we$rules, collapse = ", ")))
if (length(ooc_labels) > 0) {
  cat(sprintf("  OOC subgroups: %s\n", paste(ooc_labels, collapse = ", ")))
} else {
  cat("  OOC subgroups: none\n")
}
cat("\n")
cat("--- Verdict -----------------------------------------------------\n")
cat(sprintf("  %s\n", verdict))
cat("=================================================================\n\n")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
COL_IC   <- "#1F3A6E"
COL_OOC  <- "#CC2222"
COL_CL   <- "#444444"
COL_LIM  <- "#CC2222"
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

idx <- seq_len(nrow(dat))

df_plot <- data.frame(
  idx        = idx,
  label      = dat$subgroup,
  p_i        = p_i,
  UCL_i      = UCL_i,
  LCL_i      = LCL_i,
  ooc        = we$ooc,
  stringsAsFactors = FALSE
)

p1 <- ggplot(df_plot, aes(x = idx)) +
  # Per-point limit lines as step-function connecting limits
  geom_line(aes(y = UCL_i), color = COL_LIM, linewidth = 0.6, linetype = "dashed") +
  geom_line(aes(y = LCL_i), color = COL_LIM, linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = p_bar, color = COL_CL, linewidth = 0.8) +
  geom_line(aes(y = p_i), color = COL_IC, linewidth = 0.6) +
  geom_point(aes(y = p_i, color = ooc), size = 2.5, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = COL_IC, "TRUE" = COL_OOC)) +
  scale_x_continuous(breaks = idx, labels = dat$subgroup) +
  scale_y_continuous(labels = function(x) sprintf("%.3f", x)) +
  labs(title = "P-Chart (Proportion Nonconforming)",
       x = "Subgroup", y = "Proportion Defective (p)") +
  theme_jr +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

p1 <- p1 +
  annotate("text", x = max(idx), y = p_bar,
           label = sprintf("p-bar=%.4f", p_bar),
           hjust = 1.05, vjust = -0.4, size = 2.8, color = COL_CL)

# ---------------------------------------------------------------------------
# Save PNG
# ---------------------------------------------------------------------------
datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(path.expand("~/Downloads"),
                      paste0(datetime_pfx, "_jrc_spc_p.png"))

cat(sprintf("\u2728 Saving plot to: %s\n\n", out_file))

png(out_file, width = 2400, height = 1200, res = 180, bg = BG)

grid.newpage()

pushViewport(viewport(layout = grid.layout(
  nrow    = 2,
  ncol    = 1,
  heights = unit(c(0.08, 0.92), "npc")
)))

pushViewport(viewport(layout.pos.row = 1))
grid.rect(gp = gpar(fill = "#2E5BBA", col = NA))
grid.text(
  sprintf("P-Chart  |  %s  |  p-bar=%.4f  |  Subgroups=%d  |  %s",
          basename(csv_file), p_bar, nrow(dat), verdict),
  gp = gpar(col = "white", fontsize = 10, fontface = "bold")
)
popViewport()

pushViewport(viewport(layout.pos.row = 2))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
popViewport()

dev.off()

cat(sprintf("\u2705 Done. Open %s to view your report.\n", basename(out_file)))
