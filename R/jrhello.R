# =============================================================================
# jrhello.R
# JR Validated Environment — example R script
#
# Displays a greeting string as a stunning space nebula graphic.
# Demonstrates that the validated R environment is working correctly.
#
# Usage: called via jrhello_r zsh wrapper
#        jrhello_r "Your message here"
# =============================================================================

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: jrhello_r <message>")
}
message_text <- paste(args, collapse = " ")

# ---------------------------------------------------------------------------
# Load from validated renv library. This is the part that needs to be added
# to each user R script
# ---------------------------------------------------------------------------
renv_lib <- Sys.getenv("RENV_PATHS_ROOT")
if (renv_lib == "") {
  stop("\u274c RENV_PATHS_ROOT is not set. Run this script from the provided zsh wrapper.")
}
r_ver    <- paste0("R-", R.version$major, ".",
                   sub("\\..*", "", R.version$minor))
platform <- R.version$platform
lib_path <- file.path(renv_lib, "renv", "library", "macos", r_ver, platform)
if (!dir.exists(lib_path)) {
  stop(paste("\u274c renv library not found at:", lib_path))
}
.libPaths(c(lib_path, .libPaths()))

# wrap the library() calls iin suppres calls
suppressWarnings(suppressPackageStartupMessages({
  library(ggplot2)
}))

# ---------------------------------------------------------------------------
# Visual parameters
# ---------------------------------------------------------------------------
set.seed(42)

BG_COLOR      <- "#0A0A1A"
GOLD          <- "#FFD700"
WHITE         <- "#FFFFFF"
SUBTITLE      <- "JR Validated Environment"

STAR_COLORS   <- c("#FFD700", "#FF6B6B", "#4ECDC4", "#45B7D1",
                   "#96CEB4", "#FFEAA7", "#DDA0DD", "#98FB98",
                   "#FFFFFF", "#FFFFFF", "#FFFFFF")  # extra white for realism

# ---------------------------------------------------------------------------
# Background stars — three layers for depth
# ---------------------------------------------------------------------------

# Distant tiny stars
n_distant <- 600
distant_stars <- data.frame(
  x     = runif(n_distant, -1, 1),
  y     = runif(n_distant, -1, 1),
  size  = runif(n_distant, 0.01, 0.3),
  alpha = runif(n_distant, 0.1, 0.5),
  color = sample(c("#FFFFFF", "#AAAACC", "#CCCCFF"), n_distant, replace = TRUE)
)

# Mid stars
n_mid <- 200
mid_stars <- data.frame(
  x     = runif(n_mid, -1, 1),
  y     = runif(n_mid, -1, 1),
  size  = runif(n_mid, 0.3, 1.2),
  alpha = runif(n_mid, 0.3, 0.8),
  color = sample(STAR_COLORS, n_mid, replace = TRUE)
)

# Bright foreground stars with spike effect
n_bright <- 25
bright_stars <- data.frame(
  x     = runif(n_bright, -0.95, 0.95),
  y     = runif(n_bright, -0.85, 0.85),
  size  = runif(n_bright, 2, 5),
  alpha = runif(n_bright, 0.7, 1.0),
  color = sample(STAR_COLORS, n_bright, replace = TRUE)
)

# ---------------------------------------------------------------------------
# Nebula clouds — overlapping transparent ellipses
# ---------------------------------------------------------------------------
nebula_data <- data.frame(
  x      = c( 0.00, -0.25,  0.30, -0.10,  0.20, -0.30,  0.05),
  y      = c( 0.10,  0.20, -0.15,  0.30, -0.05,  0.00,  0.25),
  rx     = c( 0.55,  0.40,  0.45,  0.30,  0.35,  0.30,  0.25),
  ry     = c( 0.35,  0.28,  0.30,  0.20,  0.25,  0.22,  0.18),
  angle  = c( 15,    45,   -20,    70,    30,   -45,    10),
  color  = c("#1A0533", "#0D1A4D", "#001A33", "#1A0D33",
             "#0D2633", "#1A1A00", "#001A1A"),
  alpha  = c( 0.55,  0.45,  0.50,  0.40,  0.45,  0.40,  0.35)
)

# ---------------------------------------------------------------------------
# Orbiting particles around the central orb
# ---------------------------------------------------------------------------
n_particles <- 80
angles      <- seq(0, 2 * pi, length.out = n_particles)
radii       <- runif(n_particles, 0.08, 0.35)
# Flatten orbits for visual depth (elliptical projection)
particle_df <- data.frame(
  x     = radii * cos(angles),
  y     = radii * sin(angles) * 0.45,
  size  = runif(n_particles, 0.5, 4.0),
  alpha = runif(n_particles, 0.4, 1.0),
  color = sample(STAR_COLORS, n_particles, replace = TRUE)
)

# ---------------------------------------------------------------------------
# Central orb glow rings
# ---------------------------------------------------------------------------
make_circle <- function(cx, cy, r, n = 200) {
  theta <- seq(0, 2 * pi, length.out = n)
  data.frame(x = cx + r * cos(theta), y = cy + r * sin(theta))
}

orb_rings <- lapply(
  list(list(r = 0.18, a = 0.04), list(r = 0.13, a = 0.08),
       list(r = 0.09, a = 0.14), list(r = 0.05, a = 0.25),
       list(r = 0.02, a = 0.70)),
  function(p) { d <- make_circle(0, 0, p$r); d$alpha <- p$a; d }
)

# ---------------------------------------------------------------------------
# Comet streaks
# ---------------------------------------------------------------------------
n_comets <- 12
comet_df <- data.frame(
  x    = runif(n_comets, -0.95, 0.95),
  y    = runif(n_comets, -0.90, 0.90),
  xend = runif(n_comets, -0.95, 0.95),
  yend = runif(n_comets, -0.90, 0.90),
  size = runif(n_comets, 0.1, 0.5),
  alpha= runif(n_comets, 0.1, 0.4)
)
# Make streaks directional (short lines with consistent angle)
streak_angle <- runif(n_comets, -pi/8, pi/8)
streak_len   <- runif(n_comets, 0.02, 0.10)
comet_df$xend <- comet_df$x + streak_len * cos(streak_angle)
comet_df$yend <- comet_df$y + streak_len * sin(streak_angle)

# ---------------------------------------------------------------------------
# Text sizing
# ---------------------------------------------------------------------------
msg_size <- if (nchar(message_text) > 30) {
  max(5, 11 - (nchar(message_text) - 30) * 0.15)
} else if (nchar(message_text) > 15) {
  max(7, 11 - (nchar(message_text) - 15) * 0.1)
} else {
  11
}

# ---------------------------------------------------------------------------
# Build the plot
# ---------------------------------------------------------------------------
p <- ggplot() +

  # --- Dark space background
  annotate("rect",
           xmin = -1, xmax = 1, ymin = -1, ymax = 1,
           fill = BG_COLOR) +

  # --- Nebula clouds
  {
    layers <- list()
    for (i in seq_len(nrow(nebula_data))) {
      nd <- nebula_data[i, ]
      layers[[i]] <- annotate("point",
                               x = nd$x, y = nd$y,
                               size  = nd$rx * 280,
                               color = nd$color,
                               alpha = nd$alpha,
                               shape = 16)
    }
    layers
  } +

  # --- Distant stars
  geom_point(data = distant_stars,
             aes(x = x, y = y, size = size, alpha = alpha),
             color = "#CCCCFF", shape = 16, show.legend = FALSE) +

  # --- Comet streaks
  geom_segment(data = comet_df,
               aes(x = x, y = y, xend = xend, yend = yend,
                   linewidth = size, alpha = alpha),
               color = WHITE, show.legend = FALSE) +

  # --- Mid stars
  geom_point(data = mid_stars,
             aes(x = x, y = y, size = size, alpha = alpha, color = color),
             shape = 16, show.legend = FALSE) +
  scale_color_identity() +

  # --- Orb glow rings
  {
    glow_layers <- list()
    for (i in seq_along(orb_rings)) {
      ring <- orb_rings[[i]]
      glow_layers[[i]] <- geom_path(
        data  = ring,
        aes(x = x, y = y),
        color = GOLD,
        alpha = ring$alpha[1],
        linewidth = (6 - i) * 0.8
      )
    }
    glow_layers
  } +

  # --- Orbiting particles
  geom_point(data = particle_df,
             aes(x = x, y = y, size = size, alpha = alpha, color = color),
             shape = 16, show.legend = FALSE) +

  # --- Bright foreground stars
  geom_point(data = bright_stars,
             aes(x = x, y = y, size = size, alpha = alpha, color = color),
             shape = 8, show.legend = FALSE) +   # shape 8 = asterisk/spike

  # --- Central orb core
  annotate("point", x = 0, y = 0,
           size = 6, color = WHITE, alpha = 1.0, shape = 16) +
  annotate("point", x = 0, y = 0,
           size = 3, color = GOLD, alpha = 1.0, shape = 16) +

  # --- Message text shadow (depth effect)
  annotate("text",
           x = 0.008, y = -0.497,
           label = message_text,
           color  = "#000000",
           size   = msg_size,
           fontface = "bold",
           hjust  = 0.5,
           alpha  = 0.6) +

  # --- Main message text
  annotate("text",
           x = 0, y = -0.49,
           label = message_text,
           color    = WHITE,
           size     = msg_size,
           fontface = "bold",
           hjust    = 0.5) +

  # --- Decorative lines flanking the text
  annotate("segment",
           x = -0.72, xend = -0.12, y = -0.59, yend = -0.59,
           color = GOLD, alpha = 0.5, linewidth = 0.4) +
  annotate("segment",
           x =  0.12, xend =  0.72, y = -0.59, yend = -0.59,
           color = GOLD, alpha = 0.5, linewidth = 0.4) +
  annotate("point",
           x = c(-0.12, 0.12), y = c(-0.59, -0.59),
           size = 1.2, color = GOLD, alpha = 0.8) +

  # --- Subtitle
  annotate("text",
           x = 0, y = -0.72,
           label = SUBTITLE,
           color    = GOLD,
           size     = 3.2,
           fontface = "italic",
           hjust    = 0.5,
           alpha    = 0.85) +

  # --- R version watermark
  annotate("text",
           x = 0.96, y = -0.95,
           label = paste0("R ", R.version$major, ".",
                          sub("\\..*", "", R.version$minor)),
           color = "#333355", size = 2.2, hjust = 1) +

  # --- Scales and theme
  scale_size_identity() +
  scale_alpha_identity() +
  scale_linewidth_identity() +
  coord_fixed(xlim = c(-1, 1), ylim = c(-1, 1), expand = FALSE) +
  theme_void() +
  theme(
    plot.background  = element_rect(fill = BG_COLOR, color = NA),
    panel.background = element_rect(fill = BG_COLOR, color = NA),
    plot.margin      = margin(0, 0, 0, 0)
  )

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
# Build output filename with datetime prefix in same folder as script
script_path <- normalizePath(sub("--file=", "", 
                grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
script_dir  <- dirname(script_path)

datetime_pfx <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file     <- file.path(path.expand("~/Downloads"),
                          paste0(datetime_pfx, "_jrhello.png"))

cat(sprintf("\n\u2728 %s\n", message_text))
cat(sprintf("   Saving graphic to: %s\n\n", out_file))

ggsave(out_file,
       plot   = p,
       width  = 10,
       height = 10,
       dpi    = 180,
       bg     = BG_COLOR)

cat(sprintf("\u2705 Done. Open %s to view your graphic.\n", basename(out_file)))
