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
| ✅ | `jrc_ss_attr` | Minimum sample size for continuous (attribute) verification using statistical tolerance intervals. Normal and Box-Cox. |
| ✅ | `jrc_ss_attr_check` | Fast check: does a planned N meet the tolerance interval requirement? Single k-factor comparison, no search loop. Run before `jrc_ss_attr`. |
| 🚧 | `jrc_ss_discrete_ci` | Inverse of `jrc_ss_discrete`: given a test result (n tested, f failures), what confidence level does this achieve for a given proportion? Exact binomial method. Useful for post-test analysis and test report documentation. |
| 💡 | `jrc_ss_attr_ci` | Inverse of `jrc_ss_attr`: given a dataset and a planned N, what proportion and confidence level does the resulting tolerance interval actually achieve? Useful for post-test reporting when the test was run with a fixed N. |
| 💡 | `jrc_ss_equivalence` | Sample size for equivalence testing (TOST). Given a maximum allowable difference (delta) and a measurement SD, returns the N needed to demonstrate equivalence at a given alpha and power. Common in 510(k) comparative testing. |
| 💡 | `jrc_ss_gauge_rr` | Sample size for Gauge R&R / MSA studies. Returns the number of parts, operators, and replicates needed to achieve a target precision-to-tolerance ratio. Ensures the measurement system study is adequately powered before a verification study begins. |
| 💡 | `jrc_ss_fatigue` | Sample size for fatigue and lifetime testing. Weibull-based: given a target B-life (e.g. B10) and confidence level, returns the minimum N and number of allowed failures. Relevant for implants and reusable devices. |
| 💡 | `jrc_ss_paired` | Sample size for paired comparison studies (before/after, device A vs B). t-test based: given expected difference, SD of differences, and desired power, returns N. Common in usability and bench testing. |

---

## Statistical

| Status | Script | Description |
|---|---|---|
| 💡 | `calc_tolerance_interval` | Statistical tolerance intervals (normal and non-parametric) |
| 💡 | `calc_process_capability` | Cp, Cpk, Pp, Ppk with confidence intervals and control charts |
| 💡 | `calc_gauge_rr` | Gauge R&R (measurement system analysis) — ANOVA and range methods |
| 💡 | `calc_normality` | Normality testing — Shapiro-Wilk, Anderson-Darling, Q-Q plots |
| 💡 | `calc_descriptive_stats` | Descriptive statistics summary — mean, SD, CI, percentiles, clean output table |
| 💡 | `calc_outliers` | Outlier detection — Grubbs test and IQR-based method |

---

## Design Verification

| Status | Script | Description |
|---|---|---|
| 💡 | `calc_equivalence` | Equivalence testing (TOST) — showing two methods or designs perform the same |
| 💡 | `calc_weibull` | Reliability and survival analysis — Weibull fitting for fatigue and lifetime testing |
| 💡 | `calc_bland_altman` | Bland-Altman analysis — comparing two measurement methods |

---

## Data Generation

| Status | Script | Description |
|---|---|---|
| 💡 | `jrc_gen_normal` | Generate a synthetic normally distributed dataset with specified mean, SD, and N. Output folder passed as argument. Filename auto-generated from parameters (e.g. `normal_n30_mean0_sd1.csv`). Useful for OQ evidence and script testing. |
| 💡 | `jrc_gen_lognormal` | Generate a synthetic log-normally distributed dataset. Same interface as `jrc_gen_normal`. |
| 💡 | `jrc_gen_uniform` | Generate a synthetic uniformly distributed dataset. Same interface as `jrc_gen_normal`. |

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

*Last updated: 2026-03-13 — jrc_ss_discrete_ci marked in progress; jrc_ss_attr_ci, jrc_ss_equivalence, jrc_ss_gauge_rr, jrc_ss_fatigue, jrc_ss_paired added*
