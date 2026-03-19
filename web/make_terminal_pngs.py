#!/usr/bin/env python3
"""
Generate terminal-screenshot PNGs for jrscripts community script examples.
Outputs to: web/examples/jrc_<name>.png
"""

import os
from PIL import Image, ImageDraw, ImageFont

# ── colour palette ────────────────────────────────────────────────────────────
BG        = (22, 25, 37)       # dark navy
CHROME    = (30, 34, 50)       # slightly lighter for title bar
TEXT      = (204, 212, 230)    # default text
DIM       = (100, 110, 140)    # dimmed / decorative
GREEN     = (80,  200, 120)    # ✅ lines
RED       = (230, 80,  80)     # ❌ lines
YELLOW    = (230, 185, 60)     # ⚠️ lines
CYAN      = (100, 200, 220)    # table headers / dashes
WHITE     = (235, 240, 255)    # bold emphasis

DOT_RED   = (255, 95,  86)
DOT_YLW   = (255, 189, 46)
DOT_GRN   = (39,  201, 63)

FONT_PATH  = "/System/Library/Fonts/Menlo.ttc"
FONT_SIZE  = 14
LEADING    = 20          # px between lines
PAD_X      = 24         # left / right padding inside text area
PAD_TOP    = 10
PAD_BOT    = 20
CHROME_H   = 36
WIDTH      = 820


def make_font(size=FONT_SIZE):
    return ImageFont.truetype(FONT_PATH, size)


def line_colour(line: str) -> tuple:
    s = line.strip()
    if s.startswith("✅"):       return GREEN
    if s.startswith("❌"):       return RED
    if s.startswith("⚠"):        return YELLOW
    if set(s) <= set("-─ ") and len(s) > 4:
        return DIM
    if s.startswith("←") or s.startswith("⚠"):
        return YELLOW
    return TEXT


def render(script_id: str, lines: list[str], out_dir: str):
    font   = make_font(FONT_SIZE)
    small  = make_font(12)

    n      = len(lines)
    height = CHROME_H + PAD_TOP + n * LEADING + PAD_BOT

    img  = Image.new("RGB", (WIDTH, height), BG)
    draw = ImageDraw.Draw(img)

    # ── chrome bar ────────────────────────────────────────────────────────────
    draw.rectangle([0, 0, WIDTH, CHROME_H], fill=CHROME)
    r, cx, cy = 7, 16, CHROME_H // 2
    for colour, offset in [(DOT_RED, 0), (DOT_YLW, 24), (DOT_GRN, 48)]:
        draw.ellipse([cx + offset - r, cy - r, cx + offset + r, cy + r], fill=colour)
    title = script_id
    tw = draw.textlength(title, font=small)
    draw.text(((WIDTH - tw) / 2, (CHROME_H - 12) / 2), title, font=small, fill=DIM)

    # ── text body ─────────────────────────────────────────────────────────────
    y = CHROME_H + PAD_TOP
    for line in lines:
        colour = line_colour(line)
        draw.text((PAD_X, y), line, font=font, fill=colour)
        y += LEADING

    out = os.path.join(out_dir, f"{script_id}.png")
    img.save(out, "PNG")
    print(f"  saved → {out}")


# ── script content definitions ────────────────────────────────────────────────

SCRIPTS = {}

SCRIPTS["jrc_ss_discrete"] = [
    "✅ Sample Size for Discrete (Pass/Fail) Design Verification",
    "   version: 1.0, author: Joep Rous",
    "   ==========================================================",
    "   proportion (minimum conforming fraction):   0.95",
    "   confidence:                                 0.95",
    " ",
    "   Minimum sample sizes by number of allowed failures:",
    " ",
    "   -----------------------------------------------",
    "    failures (f)   min sample size (n)   note",
    "   -----------------------------------------------",
    "    f =  0         n =   60                ← recommended (zero-failure)",
    "    f =  1         n =   95                ⚠  requires justification",
    "    f =  2         n =  126                ⚠  requires justification",
    "    f =  3         n =  156                ⚠  requires strong justification",
    "    f =  4         n =  184                ⚠  requires strong justification",
    "    f =  5         n =  211                ⚠  requires strong justification",
    "    f =  6         n =  237                ⚠  requires strong justification",
    "    f =  7         n =  263                ⚠  requires strong justification",
    "    f =  8         n =  289                ⚠  requires strong justification",
    "    f =  9         n =  315                ⚠  requires strong justification",
    "    f = 10         n =  340                ⚠  requires strong justification",
    "   -----------------------------------------------",
    " ",
    "   Note:",
    "   For FDA design verification, f = 0 (zero failures) is the standard",
    "   acceptance criterion. Allowing f > 0 requires a pre-specified",
    "   statistical justification and an AQL rationale documented in",
    "   the verification protocol before testing begins.",
]

SCRIPTS["jrc_ss_discrete_ci"] = [
    "✅ Proportion Achieved for Discrete (Pass/Fail) Design Verification",
    "   version: 2.0, author: Joep Rous",
    "   ===================================================================",
    "   confidence:                                0.95",
    "   units tested (n):                         30",
    "   failures observed (f):                    0",
    "   proportion achieved:                      0.9983",
    " ",
    "   Table 1: proportion achieved for 0 to f failures (fixed n)",
    " ",
    "   -------------------------------------------------------",
    "    failures (f)   proportion achieved   note",
    "   -------------------------------------------------------",
    "    f =  0         0.9983                  <- actual result",
    "   -------------------------------------------------------",
    " ",
    "   Table 2: proportion achieved for varying n (fixed f)",
    " ",
    "   -------------------------------------------------------",
    "    sample size (n)   proportion achieved   note",
    "   -------------------------------------------------------",
    "    n =   10        0.9949",
    "    n =   15        0.9959",
    "    n =   20        0.9974",
    "    n =   25        0.9979",
    "    n =   30        0.9983                  <- actual result",
    "   -------------------------------------------------------",
    " ",
    "   Zero failures observed — this is the standard outcome for FDA design",
    "   verification. The proportion above is achieved under the assumption",
    "   that zero failures was the pre-specified acceptance criterion.",
]

SCRIPTS["jrc_ss_attr"] = [
    "✅ Minimal Sample Size for Statistical Tolerance Interval",
    "   version: 1.0, author: Joep Rous",
    "   ======================================================",
    "   for proportion:                 0.95",
    "   for confidence:                 0.95",
    "   file:                           pilot_data.csv",
    "   column:                         value",
    "   spec limit 1 (lower):           7.5",
    "   spec limit 2 (upper):           12.5",
    "   number of observations:         30",
    " ",
    "✅ Analyzing data ...",
    "   Skewness value is: 0.5251",
    "   Data considered not normal. Trying Box-Cox transformation!",
    "   Optimal lambda = 2",
    "   Shapiro-Wilk p-value after transform: 0.6673",
    "   Box-Cox transformation accepted.",
    " ",
    "   transformation applied:  boxcox (lambda=2)",
    "   Mode: 2-sided tolerance interval",
    "   k-factor from initial sample:           2.9292",
    " ",
    "✅ Result:",
    "   required k-factor for verification:     2.9135",
    "   required sample size for verification:  16",
    " ",
    "✅ The current sample is sufficient for verification.",
    "   (required N = 16 <= available N = 30)",
]

SCRIPTS["jrc_ss_attr_ci"] = [
    "✅ Attribute Tolerance Interval — Proportion Achieved",
    "   version: 1.0, author: Joep Rous",
    "   =====================================================",
    "   confidence:                     0.95",
    "   file:                           verification_data.csv",
    "   column:                         value",
    "   spec limit 1 (lower):           7.5",
    "   spec limit 2 (upper):           12.5",
    "   sample size (N):                30",
    " ",
    "✅ Analyzing data ...",
    "   Skewness value is: 0.5251",
    "   Box-Cox transformation accepted (lambda=2).",
    " ",
    "   transformation applied:         boxcox (lambda=2)",
    "   Mode: 2-sided tolerance interval",
    " ",
    "✅ Result:",
    "   k-factor from sample:                   2.9292",
    "   proportion achieved at 0.95 confidence:  0.9754",
    " ",
    "   tolerance interval lower bound:         7.5 (original units)",
    "   spec limit 1 (lower):                   7.5",
    "✅ Lower bound: tolerance interval is at or above the spec limit.",
    " ",
    "   tolerance interval upper bound:         12.5 (original units)",
    "   spec limit 2 (upper):                   12.5",
    "✅ Upper bound: tolerance interval is at or below the spec limit.",
]

SCRIPTS["jrc_ss_attr_check"] = [
    "✅ Attribute Sample Size Check for Design Verification",
    "   version: 1.0, author: Joep Rous",
    "   =====================================================",
    "   proportion:                     0.95",
    "   confidence:                     0.95",
    "   file:                           pilot_data.csv",
    "   column:                         value",
    "   spec limit 1 (lower):           7.5",
    "   spec limit 2 (upper):           12.5",
    "   pilot sample size:              30",
    "   planned verification N:         45",
    " ",
    "✅ Analyzing data ...",
    "   Box-Cox transformation accepted (lambda=2).",
    " ",
    "   transformation applied:         boxcox (lambda=2)",
    "   Mode: 2-sided tolerance interval",
    " ",
    "✅ Result:",
    "   k-factor from pilot sample:     2.9292",
    "   k-factor required for N = 45 :   2.4116",
    "   margin (k_sample - k_required): 0.5176",
    " ",
    "✅ PASS: the planned sample size meets the tolerance interval requirement.",
    "   N = 45 is sufficient for verification.",
]

SCRIPTS["jrc_ss_sigma"] = [
    "✅ Minimum Pilot Sample Size for Sigma Estimation",
    "   version: 1.0, author: Joep Rous",
    "   =================================================",
    "   precision (detectable shift in sigma units):  1",
    "   spec limit 1 (lower):                        7.5",
    "   spec limit 2 (upper):                        12.5",
    "   interval type:                               2-sided",
    " ",
    "   Minimum pilot N (2-sided interval):",
    " ",
    "   -----------------------------------------------",
    "                    confidence",
    "   power      0.90      0.95      0.99",
    "   -----------------------------------------------",
    "   p = 0.90     10        12        16",
    "   p = 0.95     12        14        19",
    "   p = 0.99     17        20        26",
    "   -----------------------------------------------",
    " ",
    "   How to use this table:",
    "   Select the cell matching your protocol's power and confidence.",
    "   For FDA design verification (power = 0.95, confidence = 0.95): N >= 14.",
    " ",
    "   The FDA minimum of 10 samples applies as an absolute floor regardless",
    "   of the statistical result. If the table value is below 10, use N = 10.",
]

SCRIPTS["jrc_ss_gauge_rr"] = [
    "✅ Gauge R&R Study Design (AIAG MSA)",
    "   version: 1.0, author: Joep Rous",
    "   ======================================",
    "   target %GRR:                  10 %",
    "   %GRR expressed as % of:       process",
    "   process SD (sigma):           0.5",
    "   sigma_gauge (target):         0.05",
    "   ndc (distinct categories):    14",
    " ",
    "✅ ndc = 14 — measurement system is acceptable (ndc >= 5).",
    " ",
    "⚠️  %GRR = 10% — may be acceptable depending on application.",
    " ",
    "   Study design options (AIAG minimum: 10 parts):",
    " ",
    "   -----------------------------------------------------------------------",
    "    operators   replicates   total meas.   df_repeat   df_reprod   note",
    "   -----------------------------------------------------------------------",
    "    o = 2        r = 2           40            20           1 ⚠ low df",
    "    o = 2        r = 3           60            40           1 ⚠ low df",
    "    o = 3        r = 2           60            30           2  ← AIAG baseline",
    "    o = 3        r = 3           90            60           2",
    "   -----------------------------------------------------------------------",
    " ",
    "   Recommendation:",
    "   Use at least 10 parts, 3 operators, 2 replicates (AIAG baseline).",
]

SCRIPTS["jrc_ss_fatigue"] = [
    "✅ Sample Size for Fatigue / Lifetime Testing (Weibull)",
    "   version: 1.0, author: Joep Rous",
    "   ========================================================",
    "   target reliability (B-life):            0.9   (B10 life)",
    "   confidence:                             0.95",
    "   Weibull shape parameter (beta):         2",
    "   acceleration factor (AF):               1",
    " ",
    "   Minimum sample sizes by number of allowed failures:",
    " ",
    "   -----------------------------------------------",
    "    failures (f)   min sample size (n)   note",
    "   -----------------------------------------------",
    "    f = 0          n =   30                ← recommended (zero-failure)",
    "    f = 1          n =   48                ⚠  requires justification",
    "    f = 2          n =   63                ⚠  requires justification",
    "    f = 3          n =   78                ⚠  requires strong justification",
    "    f = 4          n =   92                ⚠  requires strong justification",
    "    f = 5          n =  106                ⚠  requires strong justification",
    "   -----------------------------------------------",
    " ",
    "   Sensitivity to Weibull shape parameter (f = 0):",
    " ",
    "   -----------------------------------------------",
    "    beta           min sample size (n, f=0)",
    "   -----------------------------------------------",
    "    1.5 (low)      n =   30",
    "    2.0 (assumed)  n =   30  ← your input",
    "    2.5 (high)     n =   30",
    "   -----------------------------------------------",
]

SCRIPTS["jrc_ss_equivalence"] = [
    "✅ Sample Size for Equivalence Testing (TOST)",
    "   version: 1.0, author: Joep Rous",
    "   ==============================================",
    "   delta (equivalence margin):             0.5",
    "   sd (of paired differences):             1",
    "   effect size (delta / sd):               0.5",
    "   equivalence type:                       2-sided (within +/- delta)",
    " ",
    "   Minimum number of pairs (2-sided):",
    " ",
    "   -----------------------------------------------",
    "                    confidence",
    "   power      0.90      0.95      0.99",
    "   -----------------------------------------------",
    "   p = 0.90     28        36        54",
    "   p = 0.95     36        45        65",
    "   p = 0.99     54        65        88",
    "   -----------------------------------------------",
    " ",
    "   For FDA submissions (power = 0.95, confidence = 0.95): N >= 45 pairs.",
    " ",
    "   For reference: a difference test (jrc_ss_paired) at 95/95 requires N >= 53.",
    "   Equivalence testing typically requires more samples than difference testing",
    "   for the same delta and SD.",
]

SCRIPTS["jrc_ss_paired"] = [
    "✅ Sample Size for Paired Comparison Study",
    "   version: 1.0, author: Joep Rous",
    "   ==========================================",
    "   delta (minimum detectable difference):  0.5",
    "   sd (of paired differences):             1",
    "   effect size (delta / sd):               0.5",
    "   test type:                              2-sided",
    " ",
    "   Minimum number of pairs (2-sided test):",
    " ",
    "   -----------------------------------------------",
    "                    confidence",
    "   power      0.90      0.95      0.99",
    "   -----------------------------------------------",
    "   p = 0.90     36        44        61",
    "   p = 0.95     45        53        73",
    "   p = 0.99     65        75        98",
    "   -----------------------------------------------",
    " ",
    "   For FDA submissions (power = 0.95, confidence = 0.95): N >= 53 pairs.",
    " ",
    "   Note: N is the number of pairs, not the total number of observations.",
    "   Each pair: one measurement per condition on the same unit or subject.",
]

SCRIPTS["jrc_descriptive"] = [
    "✅ Descriptive Statistics",
    "   version: 1.0, author: Joep Rous",
    "   ==========================",
    "   file:                      pilot_data.csv",
    "   column:                    value",
    " ",
    "   Sample size:",
    "   N (valid):                 30",
    " ",
    "   Central tendency:",
    "   mean:                      10.016814",
    "   median:                    10.096936",
    " ",
    "   Spread:",
    "   SD:                        0.776749",
    "   variance:                  0.603339",
    "   CV:                        7.75 %",
    " ",
    "   Range:",
    "   min:                       8.048965",
    "   max:                       11.222541",
    " ",
    "   Percentiles:",
    "   5th:                       8.815808",
    "   25th (Q1):                 9.59072",
    "   75th (Q3):                 10.516109",
    "   95th:                      11.043237",
    "   IQR (Q3 - Q1):             0.925389",
    " ",
    "   Distribution shape:",
    "   skewness:                  -0.5251   (left-skewed)",
    "   excess kurtosis:           -0.4413   (approximately normal)",
    " ",
    "   95% CI on the mean (t-distribution):",
    "   lower:                     9.726771",
    "   upper:                     10.306857",
    "   margin of error:           0.290043",
]

SCRIPTS["jrc_normality"] = [
    "✅ Normality Check",
    "   version: 1.0, author: Joep Rous",
    "   ==================================",
    "   file:                      pilot_data.csv",
    "   column:                    value",
    "   valid observations (N):    30",
    " ",
    "   Moment statistics:",
    "   skewness:                  -0.5251   (elevated)",
    "   excess kurtosis:           -0.4413   (acceptable)",
    " ",
    "   Shapiro-Wilk test:",
    "   W statistic:               0.9651",
    "   p-value:                   0.4161   (p > 0.05: consistent with normality)",
    " ",
    "   Anderson-Darling test:",
    "   A statistic:               0.3221",
    "   p-value:                   0.5129   (p > 0.05: consistent with normality)",
    " ",
    "   Overall verdict:",
    "⚠️  Data show departures from normality.",
    "   jrc_ss_attr will attempt a Box-Cox transformation.",
    " ",
    "   Box-Cox transformation attempt:",
    "   optimal lambda:            2",
    "   |skewness| after:          0.3693",
    "   Shapiro-Wilk p after:      0.6673",
    "✅ Box-Cox transformation accepted (lambda = 2).",
    "   jrc_ss_attr will apply this transformation automatically.",
]

SCRIPTS["jrc_outliers"] = [
    "✅ Outlier Detection",
    "   version: 1.0, author: Joep Rous",
    "   ====================================",
    "   file:                      measurement_data.csv",
    "   column:                    value",
    "   valid observations (N):    30",
    " ",
    "   Grubbs Test (iterative, alpha = 0.05):",
    "   Maximum outliers to flag:   3",
    " ",
    "   -----------------------------------------------",
    "    iteration   row ID         value    p-value",
    "   -----------------------------------------------",
    "     1          15              15.0000   0.0000  ← outlier",
    "     2          5                8.0490   0.1268  (not significant)",
    "   -----------------------------------------------",
    " ",
    "⚠️  Grubbs: 1 outlier(s) flagged: 15",
    " ",
    "   IQR Method (distribution-free):",
    "   mild outlier fence:       [ 7.9329 , 12.3537 ]",
    "   extreme outlier fence:    [ 6.2751 , 14.0115 ]",
    " ",
    "   -----------------------------------------------",
    "    row ID         value        classification",
    "   -----------------------------------------------",
    "    15              15.0000     extreme outlier",
    "   -----------------------------------------------",
    " ",
    "⚠️  IQR: 1 outlier(s) flagged (0 mild, 1 extreme).",
    " ",
    "   Flagged observations should be investigated for assignable causes",
    "   before any removal is considered. Removal requires documented justification.",
]

SCRIPTS["jrc_capability"] = [
    "✅ Process Capability Analysis",
    "   version: 1.0, author: Joep Rous",
    "   ================================",
    "   file:                           process_data.csv",
    "   column:                         value",
    "   spec limit 1 (lower):           7.5",
    "   spec limit 2 (upper):           12.5",
    "   valid observations (N):         30",
    " ",
    "   Process statistics:",
    "   mean:                           10.016814",
    "   standard deviation (overall):   0.776749",
    "   95% CI on sigma:               [ 0.618608 , 1.044196 ]",
    " ",
    "   Capability indices (overall SD):",
    " ",
    "   -------------------------------------------------------",
    "    index    value     95% CI              interpretation",
    "   -------------------------------------------------------",
    "    Cp/Pp    1.0728    [0.7981, 1.3471]    marginal",
    "    Cpk/Ppk  1.0656    [0.7850, 1.3463]    marginal",
    "    Cpl/Ppl   1.0801   (lower half)",
    "    Cpu/Ppu   1.0656   (upper half)",
    "   -------------------------------------------------------",
    " ",
    "⚠️  Process is marginally capable (1.00 <= Cpk < 1.33).",
    "   Consider process improvement before verification testing.",
]

SCRIPTS["jrc_gen_normal"] = [
    "✅ Normal Distribution Dataset Generated",
    "   version: 1.0, author: Joep Rous",
    "   ========================================",
    "   n:                   30",
    "   mean:                10",
    "   sd:                  1",
    "   seed:                42",
    "   output file:         ~/Downloads/normal_n30_mean10_sd1_seed42.csv",
    " ",
    "   Sample statistics (generated data):",
    "   sample mean:         10.068587",
    "   sample sd:           1.255028",
    "   min:                 7.343545",
    "   max:                 12.286645",
    " ",
    "   Column 'id' is used as row names when read by jrc_ss_attr",
    "   and related scripts. Use column name 'value' as the data column.",
]

SCRIPTS["jrc_gen_lognormal"] = [
    "✅ Log-Normal Distribution Dataset Generated",
    "   version: 1.0, author: Joep Rous",
    "   ========================================",
    "   n:                   30",
    "   meanlog:             2.3",
    "   sdlog:               0.4",
    "   seed:                42",
    "   output file:         ~/Downloads/lognormal_n30_meanlog2.3_sdlog0.4_seed42.csv",
    " ",
    "   Sample statistics (generated data):",
    "   sample mean:         11.502681",
    "   sample sd:           5.519574",
    "   min:                 3.446702",
    "   max:                 24.894780",
    " ",
    "   Column 'id' is used as row names when read by jrc_ss_attr",
    "   and related scripts. Use column name 'value' as the data column.",
]

SCRIPTS["jrc_gen_boxcox"] = [
    "✅ Box-Cox-Transformable Dataset Generated",
    "   version: 1.0, author: Joep Rous",
    "   ========================================",
    "   n:                   30",
    "   shape (Weibull):     1.5",
    "   scale (Weibull):     2",
    "   seed:                42",
    "   output file:         ~/Downloads/boxcox_n30_shape1.5_scale2_seed42.csv",
    " ",
    "   Sample statistics (generated data):",
    "   sample mean:         1.347047",
    "   sample sd:           1.023307",
    "   min:                 0.099941",
    "   max:                 3.679820",
    " ",
    "   Column 'id' is used as row names when read by jrc_ss_attr",
    "   and related scripts. Use column name 'value' as the data column.",
]

SCRIPTS["jrc_gen_lognormal"] = [
    "✅ Log-Normal Distribution Dataset Generated",
    "   version: 1.0, author: Joep Rous",
    "   ========================================",
    "   n:                   30",
    "   meanlog:             2.3",
    "   sdlog:               0.4",
    "   seed:                42",
    "   output file:         ~/Downloads/lognormal_n30_meanlog2.3_sdlog0.4_seed42.csv",
    " ",
    "   Sample statistics (generated data):",
    "   sample mean:         11.502681",
    "   sample sd:           5.519574",
    "   min:                 3.446702",
    "   max:                 24.894780",
    " ",
    "   Column 'id' is used as row names when read by jrc_ss_attr",
    "   and related scripts. Use column name 'value' as the data column.",
]

SCRIPTS["jrc_gen_uniform"] = [
    "✅ Uniform Distribution Dataset Generated",
    "   version: 1.0, author: Joep Rous",
    "   ==========================================",
    "   n:                   30",
    "   min:                 8",
    "   max:                 12",
    "   seed:                42",
    "   output file:         ~/Downloads/uniform_n30_min8_max12_seed42.csv",
    " ",
    "   Sample statistics (generated data):",
    "   sample mean:         10.455573",
    "   sample sd:           1.169166",
    "   min:                 8.329750",
    "   max:                 11.955567",
    " ",
    "   Column 'id' is used as row names when read by jrc_ss_attr",
    "   and related scripts. Use column name 'value' as the data column.",
]

SCRIPTS["jrc_gen_sqrt"] = [
    "✅ Square-Root-Transformable Dataset Generated",
    "   version: 1.0, author: Joep Rous",
    "   ========================================",
    "   n:                   30",
    "   df (chi-squared):    5",
    "   scale:               1",
    "   seed:                42",
    "   output file:         ~/Downloads/sqrt_n30_df5_scale1_seed42.csv",
    " ",
    "   Sample statistics (generated data):",
    "   sample mean:         4.822413",
    "   sample sd:           3.152379",
    "   min:                 0.567394",
    "   max:                 11.745982",
    " ",
    "   Column 'id' is used as row names when read by jrc_ss_attr",
    "   and related scripts. Use column name 'value' as the data column.",
]

SCRIPTS["jrc_convert_csv"] = [
    "✅ Delimited File Conversion",
    "   version: 1.0, author: Joep Rous",
    "   ==============================",
    "   input file:      instrument_output.txt",
    "   delimiter:       space (auto-detected)",
    "   lines skipped:   0",
    "   column:          2",
    "   values written:  20",
    "   rows skipped:    4  (non-numeric header rows)",
    "   output file:     instrument_output_col2_skip0.csv",
    " ",
    "   Output columns: 'id' (row names), 'value' (data)",
    "   Use 'value' as the column name argument in jrc_* scripts.",
]

SCRIPTS["jrc_convert_txt"] = [
    "✅ Text File Conversion",
    "   version: 1.0, author: Joep Rous",
    "   ========================",
    "   input file:      raw_measurements.txt",
    "   lines selected:  1 to 200 (200 lines)",
    "   values written:  200",
    "   lines skipped:   0",
    "   output file:     raw_measurements_converted.csv",
    " ",
    "   Output columns: 'id' (row names), 'value' (data)",
    "   Use 'value' as the column name argument in jrc_* scripts.",
]

SCRIPTS["jrc_doe_design"] = [
    "✅ Design generated: doe_design_full2_SealStrength_N_20260319.html",
    "   Type:         Full Factorial 2-level (2^3 = 8 runs)",
    "   Factors:      3",
    "   Total runs:   8",
    "   Replicates:   1",
    "   Seed:         1773910909",
    "   Saved to:     ~/Downloads/",
    "   Data entry:   doe_design_full2_SealStrength_N_20260319.csv",
    " ",
    "   The HTML file contains:",
    "   - Design summary (type, factors, runs, randomisation seed)",
    "   - Factor definitions table (name, low level, high level, units)",
    "   - Randomised run order table with blank Response column",
    "   - Print button for bench use",
    " ",
    "   Fill in the Response column during the experiment,",
    "   then run jrc_doe_analyse on the companion CSV file.",
]

SCRIPTS["jrc_doe_analyse"] = [
    "✅ Analysis complete: doe_analysis_SealStrength_N_20260319.html",
    "   Response:     SealStrength_N",
    "   Design type:  full2",
    "   Runs:         8  (8 factorial)",
    "   R²:           1.000",
    "   Significant:  Temperature, Pressure, DwellTime, Temperature:Pressure",
    "   Saved to:     ~/Downloads/",
    " ",
    "   The HTML report contains:",
    "   - Analysis summary (design, R², residual std error)",
    "   - ANOVA table with significance highlighting",
    "   - Pareto chart of standardised effects",
    "   - Main effects plot",
    "   - Two-factor interaction plot",
    "   - Plain-English significant factors summary",
    " ",
    "   Open the HTML file in any browser.",
    "   All charts are embedded — no internet connection required.",
]


SCRIPTS["jrc_as_attributes"] = [
    " ",
    "   =================================================================",
    "     Attributes Sampling Plan",
    "     Lot size N: 500   AQL: 0.010   RQL: 0.100",
    "     Producer's risk α: 0.05   Consumer's risk β: 0.10",
    "   =================================================================",
    " ",
    "   --- Single Sampling Plan -----------------------------------",
    "     Sample size (n):        51",
    "     Acceptance number (c):  2",
    "     Rejection number (r):   3",
    " ",
    "     Achieved producer's risk (α):  0.0471   [target ≤ 0.050]",
    "     Achieved consumer's risk  (β):  0.0980   [target ≤ 0.100]",
    " ",
    "   --- Double Sampling Plan -----------------------------------",
    "     Stage 1: sample n1 = 29   Accept if d1 ≤ 0   Reject if d1 > 2",
    "     Stage 2: sample n2 = 29   Accept if d1+d2 ≤ 2",
    " ",
    "     Achieved producer's risk (α):  0.0476   [target ≤ 0.050]",
    "     Achieved consumer's risk  (β):  0.0987   [target ≤ 0.100]",
    " ",
    "     ASN at AQL (p = 0.010):  36.2  (vs single: 51)",
    "     ASN at RQL (p = 0.100):  42.2  (vs single: 51)",
    " ",
    "   --- OC Curve (Single) -------------------------------------",
    "     p          Pa",
    "     0.001      0.9999",
    "     0.005      0.9984",
    "     0.010      0.9529",
    "     0.020      0.8111",
    "     0.050      0.3896",
    "     0.100      0.0980",
    "     0.150      0.0241",
    "     0.200      0.0051",
    "   =================================================================",
    " ",
    "✅ Done. Open 20260319_120000_jrc_as_attributes.png to view your report.",
]

SCRIPTS["jrc_as_variables"] = [
    " ",
    "   =================================================================",
    "     Variables Sampling Plan — k-method (unknown σ)",
    "     Lot size N: 500   AQL: 0.010   RQL: 0.100   Sides: 1",
    "     Producer's risk α: 0.05   Consumer's risk β: 0.10",
    "   =================================================================",
    " ",
    "   --- Variables Plan (k-method) --------------------------------",
    "     Sample size (n):              21",
    "     Acceptability constant (k):   1.7608",
    " ",
    "     Achieved producer's risk (α):  0.0500   [target ≤ 0.050]",
    "     Achieved consumer's risk  (β):  0.0956   [target ≤ 0.100]",
    " ",
    "   --- Comparison with Attributes Plan -------------------------",
    "     Variables plan:   n = 21",
    "     Attributes plan:  n = 51",
    "     Sample reduction: 30 units (58.8%)",
    " ",
    "     The variables plan requires fewer samples because it uses the",
    "     actual measurement values, not just pass/fail, giving more",
    "     information per unit inspected.",
    " ",
    "   --- OC Curve -------------------------------------------------",
    "     p          Pa",
    "     0.001      1.0000",
    "     0.005      0.9998",
    "     0.010      0.9500",
    "     0.020      0.7767",
    "     0.050      0.2536",
    "     0.100      0.0956",
    "     0.150      0.0202",
    "     0.200      0.0036",
    "   =================================================================",
    " ",
    "✅ Done. Open 20260319_120000_jrc_as_variables.png to view your report.",
]

SCRIPTS["jrc_as_oc_curve"] = [
    " ",
    "   =================================================================",
    "     OC Curve — Attributes Sampling Plan",
    "     Plan: n = 51   c = 2   r = 3",
    "     Lot size N: 500",
    "     AQL: 0.010   RQL: 0.100",
    "   =================================================================",
    " ",
    "     p          Pa        1-Pa",
    "     0.001      0.9999    0.0001",
    "     0.005      0.9984    0.0016",
    "     0.010      0.9529    0.0471",
    "     0.020      0.8111    0.1889",
    "     0.050      0.3896    0.6104",
    "     0.100      0.0980    0.9020",
    "     0.150      0.0241    0.9759",
    "     0.200      0.0051    0.9949",
    " ",
    "     Pa at AQL (p = 0.010):  0.9529  ← producer accepts 95.3% of good lots",
    "     Pa at RQL (p = 0.100):  0.0980  ← consumer accepts  9.8% of bad lots",
    " ",
    "   =================================================================",
    " ",
    "✅ Done. Open 20260319_120000_jrc_as_oc_curve.png to view your report.",
]

SCRIPTS["jrc_as_evaluate"] = [
    " ",
    "   =================================================================",
    "     Lot Evaluation — Attributes Mode",
    "     Plan:  n = 51   c = 2",
    "     Data:  lot_results.csv   (51 units inspected)",
    "   =================================================================",
    " ",
    "     Units inspected:    51",
    "     Defectives found:   1",
    "     Acceptance number:  2",
    " ",
    "     1 ≤ 2   →  ACCEPT",
    " ",
    "✅ LOT ACCEPTED",
    "   Defective count (1) does not exceed acceptance number (2).",
    " ",
    "   =================================================================",
    "     Lot Evaluation — Variables Mode",
    "     Plan:  n = 21   k = 1.7608   LSL = 9.500",
    "     Data:  measurements.csv   (21 units inspected)",
    "   =================================================================",
    " ",
    "     Sample mean (x̄):     10.4500",
    "     Sample SD  (s):       0.0510",
    "     Q_L = (x̄ − LSL)/s:   18.5294",
    "     Acceptability constant k: 1.7608",
    " ",
    "     18.5294 ≥ 1.7608   →  ACCEPT",
    " ",
    "✅ LOT ACCEPTED",
    "   Q-statistic (18.5294) meets or exceeds acceptability constant (1.7608).",
    " ",
    "✅ Done. Open 20260319_120000_jrc_as_evaluate.png to view your report.",
]


if __name__ == "__main__":
    import sys
    repo = "/Users/joeprous/Software/JR/jrscripts"
    out_dir = os.path.join(repo, "web", "examples")
    os.makedirs(out_dir, exist_ok=True)

    for script_id, lines in SCRIPTS.items():
        render(script_id, lines, out_dir)

    print(f"\nDone — {len(SCRIPTS)} terminal PNGs written to {out_dir}")
