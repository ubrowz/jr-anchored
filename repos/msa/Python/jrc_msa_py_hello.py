#!/usr/bin/env python3
# =============================================================================
# jrc_msa_py_hello.py
# JR Validated Environment — MSA module example Python script
#
# Displays a greeting string as an animated starfield graphic.
# Demonstrates that the validated Python environment is working correctly
# for the MSA module.
#
# Usage: jrc_msa_py_hello "Your message here"
# =============================================================================

import sys
import os
import math
import random

sys.path.insert(0, os.path.join(os.environ.get("JR_PROJECT_ROOT", ""), "bin"))
from jr_helpers import jr_log_output_hashes

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if len(sys.argv) < 2:
    print("Usage: jrc_msa_py_hello <message>")
    sys.exit(1)

message = " ".join(sys.argv[1:])

# ---------------------------------------------------------------------------
# Imports from validated environment
# ---------------------------------------------------------------------------
try:
    import matplotlib
    matplotlib.use("TkAgg")   # use TkAgg backend for interactive display
    import matplotlib.pyplot as plt
    import matplotlib.patches as patches
    import matplotlib.patheffects as pe
    from matplotlib.animation import FuncAnimation
    from matplotlib.colors import LinearSegmentedColormap
    import numpy as np
except ImportError as e:
    print(f"❌ Required package not available: {e}")
    print("   Ensure the JR environment is correctly installed.")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Visual design
# ---------------------------------------------------------------------------
BG_COLOR      = "#0A0A1A"
STAR_COLORS   = ["#FFD700", "#FF6B6B", "#4ECDC4", "#45B7D1",
                 "#96CEB4", "#FFEAA7", "#DDA0DD", "#98FB98"]
TEXT_COLOR    = "#FFFFFF"
ACCENT_COLOR  = "#FFD700"
SUBTITLE      = "JR Validated Environment — MSA"

N_STARS       = 180
N_PARTICLES   = 60
FRAMES        = 120
INTERVAL      = 40   # ms per frame

# ---------------------------------------------------------------------------
# Initialise figure
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(12, 7), facecolor=BG_COLOR)
ax.set_facecolor(BG_COLOR)
ax.set_xlim(0, 12)
ax.set_ylim(0, 7)
ax.axis("off")
fig.tight_layout(pad=0)

# ---------------------------------------------------------------------------
# Background stars (static twinkle layer)
# ---------------------------------------------------------------------------
star_x = np.random.uniform(0, 12, N_STARS)
star_y = np.random.uniform(0, 7, N_STARS)
star_s = np.random.uniform(0.5, 4.0, N_STARS)
star_c = np.random.choice(STAR_COLORS, N_STARS)
star_alpha = np.random.uniform(0.2, 0.9, N_STARS)

bg_stars = ax.scatter(star_x, star_y, s=star_s,
                      c=star_c, alpha=0.5, zorder=1)

# ---------------------------------------------------------------------------
# Orbiting particles
# ---------------------------------------------------------------------------
class Particle:
    def __init__(self, cx, cy, index, total):
        self.cx     = cx
        self.cy     = cy
        self.angle  = (2 * math.pi / total) * index
        self.radius = random.uniform(0.3, 1.8)
        self.speed  = random.uniform(0.02, 0.06) * random.choice([-1, 1])
        self.size   = random.uniform(8, 40)
        self.color  = random.choice(STAR_COLORS)
        self.trail  = []

    def position(self, t):
        a = self.angle + self.speed * t
        x = self.cx + self.radius * math.cos(a)
        y = self.cy + self.radius * math.sin(a) * 0.5
        return x, y

cx, cy = 6.0, 3.8
particles = [Particle(cx, cy, i, N_PARTICLES) for i in range(N_PARTICLES)]

particle_scatters = []
for p in particles:
    sc = ax.scatter([], [], s=p.size, color=p.color,
                    alpha=0.8, zorder=4,
                    edgecolors="white", linewidths=0.3)
    particle_scatters.append(sc)

# ---------------------------------------------------------------------------
# Central glowing orb
# ---------------------------------------------------------------------------
for r, a in [(0.55, 0.08), (0.38, 0.12), (0.22, 0.18), (0.10, 0.35)]:
    circle = plt.Circle((cx, cy), r, color=ACCENT_COLOR,
                         alpha=a, zorder=2)
    ax.add_patch(circle)

orb = plt.Circle((cx, cy), 0.06, color=ACCENT_COLOR,
                  alpha=0.9, zorder=5)
ax.add_patch(orb)

# ---------------------------------------------------------------------------
# Main message text
# ---------------------------------------------------------------------------
msg_text = ax.text(
    cx, cy - 1.5, message,
    fontsize=28, fontweight="bold",
    color=TEXT_COLOR, ha="center", va="center",
    zorder=6, wrap=True,
    path_effects=[
        pe.withStroke(linewidth=6, foreground=BG_COLOR),
        pe.Normal()
    ]
)

# Adjust font size for long strings
if len(message) > 20:
    msg_text.set_fontsize(max(14, 28 - (len(message) - 20) * 0.5))

# ---------------------------------------------------------------------------
# Subtitle and version
# ---------------------------------------------------------------------------
ax.text(cx, 0.35, SUBTITLE,
        fontsize=10, color=ACCENT_COLOR,
        ha="center", va="center", zorder=6,
        alpha=0.8, style="italic",
        path_effects=[
            pe.withStroke(linewidth=3, foreground=BG_COLOR),
            pe.Normal()
        ])

ax.text(11.7, 0.25, f"Python {sys.version_info.major}.{sys.version_info.minor}",
        fontsize=7, color="#555577",
        ha="right", va="center", zorder=6)

# ---------------------------------------------------------------------------
# Decorative horizontal lines
# ---------------------------------------------------------------------------
for y_pos, alpha in [(2.05, 0.4), (2.0, 0.2)]:
    ax.axhline(y=y_pos, xmin=0.1, xmax=0.9,
               color=ACCENT_COLOR, alpha=alpha,
               linewidth=0.8, zorder=3)

# ---------------------------------------------------------------------------
# Twinkle counter for background stars
# ---------------------------------------------------------------------------
twinkle_counter = [0]

# ---------------------------------------------------------------------------
# Animation update function
# ---------------------------------------------------------------------------
def update(frame):
    # Animate particles
    for i, (p, sc) in enumerate(zip(particles, particle_scatters)):
        x, y = p.position(frame)
        sc.set_offsets([[x, y]])
        # Pulse opacity
        pulse = 0.5 + 0.4 * math.sin(frame * 0.15 + i * 0.3)
        sc.set_alpha(pulse)

    # Twinkle background stars every 5 frames
    twinkle_counter[0] += 1
    if twinkle_counter[0] % 5 == 0:
        new_alpha = np.random.uniform(0.1, 0.9, N_STARS)
        bg_stars.set_alpha(new_alpha.mean())

    # Pulse the central orb
    orb_pulse = 0.06 + 0.02 * math.sin(frame * 0.2)
    orb.set_radius(orb_pulse)

    # Pulse message text opacity
    text_alpha = 0.85 + 0.15 * math.sin(frame * 0.08)
    msg_text.set_alpha(text_alpha)

    return particle_scatters + [orb, msg_text, bg_stars]

# ---------------------------------------------------------------------------
# Run animation
# ---------------------------------------------------------------------------
print(f"\n✨ {message}")
print(f"   Displaying graphic — close the window to exit.\n")

anim = FuncAnimation(fig, update, frames=FRAMES,
                     interval=INTERVAL, blit=True, repeat=True)

plt.title("")
fig.canvas.manager.set_window_title("JR Validated Environment — MSA")

try:
    plt.show()
except Exception:
    # Fallback: save to file if display is not available
    output_file = os.path.join(os.path.expanduser("~/Downloads"),
                               "jrc_msa_py_hello_output.png")
    fig.savefig(output_file, dpi=150, bbox_inches="tight",
                facecolor=BG_COLOR)
    print(f"   Display not available — saved to: {output_file}")
    jr_log_output_hashes([output_file])

sys.exit(0)
