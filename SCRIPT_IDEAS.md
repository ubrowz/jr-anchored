# JR Validated Environment — Community Script Ideas

This file tracks candidate scripts for future releases. Anyone can propose
a new script by adding it to the appropriate category. Scripts that are
adopted into a release are moved to the relevant section of CHANGELOG.md.

---

## Status legend

| Symbol | Meaning |
|---|---|
| 💡 | Idea — not yet started |
| 🚧 | In progress |
| ✅ | Completed and released |

---

## Sample Size

| Status | Script | Description |
|---|---|---|
| ✅ | `jrc_ss_discrete` | Minimum sample size for pass/fail (binomial) verification. Table for f=0..10 allowed failures. Zero-failure rule based on ASTM F3172. |
| ✅ | `jrc_ss_discrete_ci` | Given confidence, n, f → proportion achieved. Exact Clopper-Pearson method. Tables over f and n. |
| ✅ | `jrc_ss_attr` | Minimum sample size for continuous (attribute) verification using statistical tolerance intervals. Normal and Box-Cox. |
| ✅ | `jrc_ss_attr_check` | Fast check: does a planned N meet the tolerance interval requirement? Single k-factor comparison, no search loop. Run before `jrc_ss_attr`. |
| ✅ | `jrc_ss_attr_ci` | Given dataset and confidence, what proportion does the tolerance interval achieve? Bisection search. Back-transforms to original units. |
| ✅ | `jrc_ss_sigma` | Minimum pilot sample size to trust the sigma estimate. t-test power based. Table over power/confidence combinations. |
| ✅ | `jrc_ss_paired` | Sample size for paired comparison studies (before/after, device A vs B). Given delta, SD of differences, and sides (1 or 2). Table over power/confidence combinations. |
| ✅ | `jrc_ss_equivalence` | Sample size for equivalence testing (TOST). Given delta, SD, and sides. Table over power/confidence combinations. Explains TOST concept in output. |
| ✅ | `jrc_ss_fatigue` | Sample size for fatigue and lifetime testing. Weibull-based: given B-life reliability, confidence, shape, and acceleration factor. Table for f=0..5. Sensitivity to shape parameter shown. |
| ✅ | `jrc_ss_gauge_rr` | Gauge R&R study design guidance (AIAG MSA). Given target %GRR and reference (process SD or tolerance), shows table over operators × replicates with ndc, df, and AIAG verdict. |

---

## Diagnostic

| Status | Script | Description |
|---|---|---|
| ✅ | `jrc_normality` | Normality testing: skewness, Shapiro-Wilk, Anderson-Darling, Box-Cox attempt. Verdict and transformation recommendation for jrc_ss_attr. |
| ✅ | `jrc_outliers` | Outlier detection: Grubbs test (iterative, up to 10% of N) and IQR method. Reports row IDs of flagged observations. |
| ✅ | `jrc_capability` | Process capability: Cp, Cpk, Pp, Ppk with 95% CIs. Overall SD used for all indices. Verdict against Cpk thresholds (1.00, 1.33, 1.67). |

---

## Statistical

| Status | Script | Description |
|---|---|---|
| 💡 | `calc_tolerance_interval` | Statistical tolerance intervals (normal and non-parametric) |
| ✅ | `jrc_descriptive` | Descriptive statistics summary — mean, SD, CI, percentiles, skewness, kurtosis |
| ✅ | `jrc_bland_altman` | Bland-Altman analysis — bias, LoA, proportional bias test, Bland-Altman plot |
| ✅ | `jrc_weibull` | Weibull reliability analysis — MLE fit with censoring, B-life estimates, probability plot |
| ✅ | `jrc_verify_attr` | Statistical tolerance interval verification against spec limits. Normal and Box-Cox. Histogram plot. |

---

## Data Generation

| Status | Script | Description |
|---|---|---|
| ✅ | `jrc_gen_normal` | Normal: n, mean, sd, folder, [seed]. Filename auto-generated from parameters. |
| ✅ | `jrc_gen_lognormal` | Log-normal: n, meanlog, sdlog, folder, [seed]. Always strictly positive. |
| ✅ | `jrc_gen_sqrt` | Chi-squared scaled: n, df, scale, folder, [seed]. Right-skewed, non-negative. |
| ✅ | `jrc_gen_boxcox` | Weibull: n, shape, scale, folder, [seed]. Right-skewed, strictly positive. |
| ✅ | `jrc_gen_uniform` | Uniform: n, min, max, folder, [seed]. |

All generators output CSV with columns `id` (row names) and `value`.

---

## Data Input / Conversion

| Status | Script | Description |
|---|---|---|
| ✅ | `jrc_convert_csv` | Convert a multi-column delimited file to jrc CSV format. Supports column name or number selection, configurable skip lines, and auto-delimiter detection. |
| ✅ | `jrc_convert_txt` | Convert a single-column text file (one value per line) to jrc CSV format. Supports optional line range selection. |

---

## Signal / Time Series

| Status | Script | Description |
|---|---|---|
| 💡 | `calc_moving_average` | Moving average and smoothing with configurable window |
| 💡 | `calc_fft` | Basic FFT and frequency analysis with amplitude spectrum plot |

---

## Notes

- All scripts should work with both R and Python where practical
- Each script submission requires: the script, a help file, synthetic test
  data, and a reference validation summary (see CONTRIBUTING.md)
- Scripts requiring new packages must list them — adding packages to the
  core requirements triggers a new release and requires revalidation

---

*Last updated: 2026-03-15 — Statistical and data conversion scripts added and marked ✅*
