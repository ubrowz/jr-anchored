"""
JR Anchored — Graphical Interface (Proof of Concept)

A Streamlit UI that calls validated JR scripts via jrrun.
The GUI is a convenience layer — all scripts run through the same
integrity-checked, validated path as the CLI.

Launch:  streamlit run app/jr_app.py
"""

from __future__ import annotations

import base64
import glob
import hashlib
import hmac
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

import streamlit as st

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

APP_DIR      = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(APP_DIR)
DOWNLOADS    = os.path.expanduser("~/Downloads")

SPC_DATA   = os.path.join(PROJECT_ROOT, "repos", "spc",        "oq", "data")
MSA_DATA   = os.path.join(PROJECT_ROOT, "repos", "msa",        "oq", "data")
AS_DATA    = os.path.join(PROJECT_ROOT, "repos", "as",         "oq", "data")
CORR_DATA  = os.path.join(PROJECT_ROOT, "repos", "corr",       "oq", "data")
CAP_DATA   = os.path.join(PROJECT_ROOT, "repos", "cap",        "oq", "data")
CURVE_DATA = os.path.join(PROJECT_ROOT, "repos", "curve",      "sample_data")
RDT_DATA   = os.path.join(PROJECT_ROOT, "repos", "rdt",        "oq", "data")
SHELF_DATA = os.path.join(PROJECT_ROOT, "repos", "shelf_life", "oq", "data")
COMM_DATA  = os.path.join(PROJECT_ROOT, "oq", "data")

PACK_DIR    = os.path.join(PROJECT_ROOT, "pack")
PACK_CONFIG = os.path.join(PACK_DIR, "jr_pack_config.json")
ADMIN_CONFIG = os.path.join(APP_DIR, ".admin_config.json")

# ---------------------------------------------------------------------------
# Windows: convert a Windows path to a POSIX path for bash (MSYS2).
# e.g. C:\Users\foo\bar  →  /c/Users/foo/bar
# bash receives backslash-paths as literal strings, breaking dirname/$0.
# ---------------------------------------------------------------------------
def _find_help_file(module_name: str, script_name: str) -> str | None:
    base = os.path.splitext(script_name)[0]
    module_folder = {
        "MSA": "msa", "SPC": "spc", "AS": "as", "Corr": "corr",
        "Cap": "cap", "Curve": "curve", "Shelf Life": "shelf_life", "RDT": "rdt",
    }.get(module_name)
    if module_folder:
        p = os.path.join(PROJECT_ROOT, "repos", module_folder, "help", f"{base}.txt")
        if os.path.exists(p):
            return p
    p = os.path.join(PROJECT_ROOT, "help", f"{base}.txt")
    return p if os.path.exists(p) else None


def _win_desktop() -> str:
    """Return the real Desktop path on Windows, handling OneDrive redirection."""
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders",
        )
        path, _ = winreg.QueryValueEx(key, "Desktop")
        winreg.CloseKey(key)
        return path
    except Exception:
        onedrive = os.path.expanduser(r"~\OneDrive\Desktop")
        return onedrive if os.path.isdir(onedrive) else os.path.expanduser("~/Desktop")


def _to_posix(p: str) -> str:
    p = p.replace("\\", "/")
    if len(p) >= 2 and p[1] == ":":          # C:/... → /c/...
        p = "/" + p[0].lower() + p[2:]
    return p

if sys.platform == "win32":
    _BASH = r"C:\Program Files\Git\bin\bash.exe"
    BASH_PREFIX = [_BASH, "--login"]
    JRRUN = _to_posix(os.path.join(PROJECT_ROOT, "bin", "jrrun"))
else:
    BASH_PREFIX = []
    JRRUN = os.path.join(PROJECT_ROOT, "bin", "jrrun")

# ---------------------------------------------------------------------------
# Script catalogue
# ---------------------------------------------------------------------------
# param_type controls which parameter widgets are shown.
# needs_file=False → skip the data upload section; Run button is always enabled.
# png_pattern  → glob in ~/Downloads for the most-recent matching PNG.
# png_from_output → parse "saved to: <path>" from terminal output instead.

CATALOGUE = {

    # -----------------------------------------------------------------------
    "Core": {

        # Sample Size Planning
        "Sample Size — Discrete Pass/Fail": {
            "script": "jrc_ss_discrete.R",
            "description": (
                "Minimum sample size for discrete (pass/fail) design verification. "
                "Uses the binomial tolerance interval method. Reports n for a range "
                "of power and confidence combinations."
            ),
            "param_type": "ss_discrete",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Sample Size — Discrete Achieved CI": {
            "script": "jrc_ss_discrete_ci.R",
            "description": (
                "Proportion achieved by a discrete (pass/fail) verification test at a "
                "fixed confidence level, given sample size n and observed failures f. "
                "The post-test companion to jrc_ss_discrete."
            ),
            "param_type": "ss_discrete_ci",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Sample Size — Continuous Paired": {
            "script": "jrc_ss_paired.R",
            "description": (
                "Minimum number of paired observations to detect a meaningful difference "
                "δ between two conditions. Reports n for a range of power and confidence "
                "combinations including the FDA-recommended (0.95, 0.95)."
            ),
            "param_type": "ss_power",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Sample Size — Continuous Equivalence": {
            "script": "jrc_ss_equivalence.R",
            "description": (
                "Minimum number of paired observations to demonstrate equivalence within "
                "margin δ. Reports n for a range of power and confidence combinations. "
                "Typically requires more samples than a difference test."
            ),
            "param_type": "ss_power",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Sample Size — Continuous Tolerance Interval": {
            "script": "jrc_ss_attr.R",
            "description": (
                "Minimum sample size to establish a statistical tolerance interval "
                "demonstrating that at least `proportion` of the population lies within "
                "the specification, at the stated confidence level."
            ),
            "param_type": "ss_attr",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
        },
        "Sample Size — Check Planned N": {
            "script": "jrc_ss_attr_check.R",
            "description": (
                "Checks whether a planned sample size N meets the tolerance interval "
                "requirement for the given proportion and confidence. Reports the "
                "achieved confidence for N."
            ),
            "param_type": "ss_attr_check",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
        },
        "Sample Size — Continuous Achieved CI": {
            "script": "jrc_ss_attr_ci.R",
            "description": (
                "Confidence level achieved by a completed continuous verification test "
                "for a given proportion and specification. The reverse calculation for "
                "jrc_ss_attr."
            ),
            "param_type": "ss_attr_ci",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
        },
        "Sample Size — Sigma Estimation": {
            "script": "jrc_ss_sigma.R",
            "description": (
                "Minimum number of pilot samples needed to estimate the process standard "
                "deviation with sufficient precision before a tolerance interval study."
            ),
            "param_type": "ss_sigma",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Sample Size — Fatigue / Lifetime": {
            "script": "jrc_ss_fatigue.R",
            "description": (
                "Minimum number of units for fatigue or lifetime testing to demonstrate "
                "a B-life reliability target (e.g. B10 = 90% survival). Uses the "
                "Weibull accelerated life model."
            ),
            "param_type": "ss_fatigue",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Sample Size — Gauge R&R Study Design": {
            "script": "jrc_msa_grr_design.R",
            "description": (
                "Gauge R&R study design guidance. Given a target %GRR and the process "
                "tolerance or standard deviation, reports the required gauge precision "
                "and number of distinct categories (ndc)."
            ),
            "param_type": "ss_gauge_rr",
            "sample_data_dir": None,
            "png_pattern": None,
        },

        # Data Analysis
        "Data Analysis — Descriptive Statistics": {
            "script": "jrc_descriptive.R",
            "description": (
                "Descriptive statistics summary for a single column. Reports mean, "
                "median, SD, CV, percentiles, skewness, kurtosis, and a 95% CI on the mean."
            ),
            "param_type": "univariate",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
        },
        "Data Analysis — Normality Tests": {
            "script": "jrc_normality.R",
            "description": (
                "Tests whether a dataset follows a normal distribution using three "
                "complementary methods: skewness/kurtosis, Shapiro-Wilk, and Anderson-Darling."
            ),
            "param_type": "univariate",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
        },
        "Data Analysis — Outlier Detection": {
            "script": "jrc_outliers.R",
            "description": (
                "Detects outliers using iterative Grubbs test and the IQR method. "
                "The Grubbs test is the standard method for small samples in medical "
                "device testing."
            ),
            "param_type": "univariate",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "outlier_",
            "png_pattern": None,
        },
        "Data Analysis — Capability Analysis": {
            "script": "jrc_capability.R",
            "description": (
                "Computes Cp/Pp (spread-only) and Cpk/Ppk (centring-aware) process "
                "capability indices. Accepts one or both specification limits."
            ),
            "param_type": "capability",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
        },
        "Data Analysis — Weibull Analysis": {
            "script": "jrc_weibull.R",
            "description": (
                "Fits a 2-parameter Weibull distribution to lifetime or fatigue data "
                "with right-censored observations. Reports shape (β) and scale (η), "
                "B10/B1 life estimates, and saves a Weibull probability plot."
            ),
            "param_type": "weibull",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "weibull_",
            "png_pattern": None,
            "png_from_output": True,
        },
        "Data Analysis — Bland-Altman Analysis": {
            "script": "jrc_bland_altman.R",
            "description": (
                "Bland-Altman method comparison analysis. Computes bias (mean difference), "
                "limits of agreement, and tests for proportional bias. "
                "Saves a Bland-Altman plot alongside the input file."
            ),
            "param_type": "bland_altman",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "bland_altman_method1",
            "png_pattern": None,
            "png_from_output": True,
        },
        "Data Analysis — Verify Continuous Result": {
            "script": "jrc_verify_attr.R",
            "description": (
                "Statistical tolerance interval verification for continuous data. "
                "Tests whether the dataset establishes that at least `proportion` of the "
                "population lies within the specification at the stated confidence. "
                "Saves a histogram to the input file directory."
            ),
            "param_type": "ss_attr",
            "has_report": True,
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
            "png_from_output": True,
        },
        "Data Analysis — Verify Pass/Fail Result": {
            "script": "jrc_verify_discrete.R",
            "description": (
                "Evaluates whether a pass/fail design verification test demonstrates the "
                "required proportion at the stated confidence level. Uses the exact "
                "Binomial (Clopper-Pearson) method. Reports the upper confidence bound "
                "on the failure rate and a PASS/FAIL verdict with margin."
            ),
            "param_type": "verify_discrete",
            "has_report": True,
            "sample_data_dir": None,
            "png_pattern": None,
        },

        # Generate Test Data
        "Generate Data — Normal Distribution": {
            "script": "jrc_gen_normal.R",
            "description": (
                "Generates a synthetic normally distributed dataset and writes it "
                "to a CSV file in `~/Downloads/`. Useful for testing analysis scripts "
                "before real data is available."
            ),
            "param_type": "gen_2param",
            "param1_label": "Mean", "param1_default": "10.0",
            "param2_label": "SD",   "param2_default": "1.0",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Generate Data — Log-Normal Distribution": {
            "script": "jrc_gen_lognormal.R",
            "description": (
                "Generates a synthetic log-normally distributed dataset. "
                "Parameters are on the log scale (meanlog, sdlog). "
                "Writes a CSV to `~/Downloads/`."
            ),
            "param_type": "gen_2param",
            "param1_label": "Mean (log scale)", "param1_default": "0.0",
            "param2_label": "SD (log scale)",   "param2_default": "0.5",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Generate Data — Uniform Distribution": {
            "script": "jrc_gen_uniform.R",
            "description": (
                "Generates a synthetic uniformly distributed dataset between min and "
                "max. Writes a CSV to `~/Downloads/`."
            ),
            "param_type": "gen_2param",
            "param1_label": "Min", "param1_default": "0.0",
            "param2_label": "Max", "param2_default": "1.0",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Generate Data — Right-Skewed (sqrt)": {
            "script": "jrc_gen_sqrt.R",
            "description": (
                "Generates a synthetic right-skewed dataset from a chi-squared "
                "distribution. Suitable for testing square-root transformation "
                "workflows. Writes a CSV to `~/Downloads/`."
            ),
            "param_type": "gen_2param",
            "param1_label": "Degrees of freedom (df)", "param1_default": "2",
            "param2_label": "Scale",                    "param2_default": "3.0",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Generate Data — Right-Skewed (Box-Cox)": {
            "script": "jrc_gen_boxcox.R",
            "description": (
                "Generates a right-skewed dataset from a Weibull distribution, "
                "suitable for testing Box-Cox transformation workflows. "
                "Writes a CSV to `~/Downloads/`."
            ),
            "param_type": "gen_2param",
            "param1_label": "Shape", "param1_default": "1.5",
            "param2_label": "Scale", "param2_default": "2.0",
            "sample_data_dir": None,
            "png_pattern": None,
        },

        # Prepare Data
        "Prepare Data — Convert CSV": {
            "script": "jrc_convert_csv.py",
            "description": (
                "Converts a multi-column delimited file to the standard two-column "
                "jrc CSV format (`id`, `value`). Supports column selection by name or "
                "1-based number, configurable skip lines for metadata headers at the top "
                "of the file, and auto-delimiter detection (tab / space / comma). "
                "Use this before any analysis script when your data file has multiple "
                "columns or non-standard headers."
            ),
            "param_type": "convert_csv",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "convert_multicolumn",
            "png_pattern": None,
        },
        "Prepare Data — Convert TXT": {
            "script": "jrc_convert_txt.py",
            "description": (
                "Converts a single-column plain-text file (one value per line, no header) "
                "to the standard two-column jrc CSV format (`id`, `value`). Supports an "
                "optional line range to exclude stabilisation periods or post-test noise."
            ),
            "param_type": "convert_txt",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "convert_singlecolumn",
            "png_pattern": None,
        },
    },

    # -----------------------------------------------------------------------
    "DoE": {
        "Design Experiment": {
            "script": "jrc_doe_design.R",
            "description": (
                "Generate a randomised DoE run matrix as a self-contained HTML file "
                "ready to print for the bench. Supports 2-level full factorial, "
                "3-level full factorial, fractional factorial, and Plackett-Burman."
            ),
            "param_type": "doe_design",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "doe_factors_",
            "png_pattern": None,
        },
        "Analyse Results": {
            "script": "jrc_doe_analyse.R",
            "description": (
                "Analyse a completed DoE run matrix. Fits a linear model in coded "
                "factor space and produces an HTML report with ANOVA table, Pareto "
                "chart of effects, main effects plot, and interaction plots."
            ),
            "param_type": "doe_analyse",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "doe_results_",
            "png_pattern": None,
        },
    },

    # -----------------------------------------------------------------------
    "MSA": {
        "Gauge R&R": {
            "script": "jrc_msa_gauge_rr.R",
            "description": (
                "Gauge R&R analysis using the two-way ANOVA method. Computes "
                "repeatability, reproducibility, part variation, and %GRR. "
                "Saves a four-panel PNG to `~/Downloads/`."
            ),
            "param_type": "msa_tolerance",
            "has_report": True,
            "sample_data_dir": MSA_DATA,
            "sample_prefix": "gauge_rr_balanced",
            "png_pattern": "*_jrc_msa_gauge_rr.png",
        },
        "Nested GRR": {
            "script": "jrc_msa_nested_grr.R",
            "description": (
                "Nested Gauge R&R for destructive or semi-destructive measurement "
                "systems where each operator measures a different set of parts. "
                "Saves a two-panel PNG to `~/Downloads/`."
            ),
            "param_type": "msa_tolerance",
            "sample_data_dir": MSA_DATA,
            "sample_prefix": "nested_grr_good",
            "png_pattern": "*_jrc_msa_nested_grr.png",
        },
        "Type 1 Study": {
            "script": "jrc_msa_type1.R",
            "description": (
                "Type 1 Gauge Study (AIAG/VDA method). One operator measures one "
                "reference part repeatedly. Computes Cg, Cgk, %Var (bias), and "
                "saves a run chart + histogram PNG to `~/Downloads/`."
            ),
            "param_type": "msa_type1",
            "sample_data_dir": MSA_DATA,
            "sample_prefix": "type1_",
            "png_pattern": "*_jrc_msa_type1.png",
        },
        "Linearity & Bias": {
            "script": "jrc_msa_linearity_bias.R",
            "description": (
                "Gauge linearity and bias analysis. Assesses whether gauge accuracy "
                "is consistent across the measurement range. Saves a two-panel PNG."
            ),
            "param_type": "msa_tolerance",
            "sample_data_dir": MSA_DATA,
            "sample_prefix": "linearity_bias_good",
            "png_pattern": "*_jrc_msa_linearity_bias.png",
        },
        "Attribute Agreement": {
            "script": "jrc_msa_attribute.R",
            "description": (
                "Attribute Agreement Analysis. Computes within-appraiser and "
                "between-appraiser agreement rates (Fleiss' kappa). Optionally "
                "compares to a reference standard. Saves a two-panel PNG."
            ),
            "param_type": "fileonly",
            "sample_data_dir": MSA_DATA,
            "sample_prefix": "attribute_with_ref",
            "png_pattern": "*_jrc_msa_attribute.png",
        },
    },

    # -----------------------------------------------------------------------
    "SPC": {
        "I-MR Chart": {
            "script": "jrc_spc_imr.R",
            "description": (
                "Individuals and Moving Range (I-MR) control chart for processes "
                "with one measurement per time point. Applies all 8 Western Electric "
                "rules to the I chart. Saves a two-panel PNG to `~/Downloads/`."
            ),
            "param_type": "spc_limits",
            "has_report": True,
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "imr_stable",
            "png_pattern": "*_jrc_spc_imr.png",
        },
        "X-bar / R Chart": {
            "script": "jrc_spc_xbar_r.R",
            "description": (
                "X-bar and Range control chart for subgrouped data (n = 2–10). "
                "Applies all 8 Western Electric rules to the X-bar chart. "
                "Saves a two-panel PNG to `~/Downloads/`."
            ),
            "param_type": "spc_limits",
            "has_report": True,
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "xbar_r_stable",
            "png_pattern": "*_jrc_spc_xbar_r.png",
        },
        "X-bar / S Chart": {
            "script": "jrc_spc_xbar_s.R",
            "description": (
                "X-bar and S (standard deviation) control chart for subgrouped data. "
                "More efficient than X-bar/R for larger subgroup sizes. "
                "Saves a two-panel PNG to `~/Downloads/`."
            ),
            "param_type": "spc_limits",
            "has_report": True,
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "xbar_s_stable",
            "png_pattern": "*_jrc_spc_xbar_s.png",
        },
        "P-chart": {
            "script": "jrc_spc_p.R",
            "description": (
                "P-chart for proportion nonconforming. Supports variable subgroup sizes. "
                "Applies all 8 Western Electric rules via standardised values. "
                "Saves a single-panel PNG to `~/Downloads/`."
            ),
            "param_type": "fileonly",
            "has_report": True,
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "p_stable",
            "png_pattern": "*_jrc_spc_p.png",
        },
        "C-chart": {
            "script": "jrc_spc_c.R",
            "description": (
                "C-chart for defect count per unit (constant inspection opportunity). "
                "Applies all 8 Western Electric rules. "
                "Saves a single-panel PNG to `~/Downloads/`."
            ),
            "param_type": "fileonly",
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "c_stable",
            "png_pattern": "*_jrc_spc_c.png",
        },
    },

    # -----------------------------------------------------------------------
    "AS": {
        "Attributes Plan": {
            "script": "jrc_as_attributes.R",
            "description": (
                "Design an attributes acceptance sampling plan. Computes single and "
                "double sampling plans for given lot size, AQL, and RQL. "
                "Saves an OC curve PNG to `~/Downloads/`."
            ),
            "param_type": "as_design",
            "sample_data_dir": None,
            "png_pattern": "*_jrc_as_attributes.png",
        },
        "Variables Plan": {
            "script": "jrc_as_variables.R",
            "description": (
                "Design a variables acceptance sampling plan (k-method). "
                "Reports n and acceptability constant k, compares with the equivalent "
                "attributes plan. Saves an OC curve PNG to `~/Downloads/`."
            ),
            "param_type": "as_variables",
            "sample_data_dir": None,
            "png_pattern": "*_jrc_as_variables.png",
        },
        "OC Curve": {
            "script": "jrc_as_oc_curve.R",
            "description": (
                "Plot the OC curve for a given attributes sampling plan (n, c). "
                "Optionally annotates AQL and RQL on the curve. "
                "Saves a PNG to `~/Downloads/`."
            ),
            "param_type": "as_oc_curve",
            "sample_data_dir": None,
            "png_pattern": "*_jrc_as_oc_curve.png",
        },
        "Evaluate Plan": {
            "script": "jrc_as_evaluate.R",
            "description": (
                "Apply an acceptance sampling plan to inspection data and produce an "
                "accept/reject decision. Supports attributes and variables modes. "
                "Saves a results PNG to `~/Downloads/`."
            ),
            "param_type": "as_evaluate",
            "sample_data_dir": AS_DATA,
            "sample_prefix": "attr_accept",
            "png_pattern": "*_jrc_as_evaluate.png",
        },
    },

    # -----------------------------------------------------------------------
    "Corr": {
        "Pearson Correlation": {
            "script": "jrc_corr_pearson.R",
            "description": (
                "Computes the Pearson product-moment correlation coefficient between "
                "two numeric variables. Reports **r**, a confidence interval (Fisher z), "
                "t-statistic, p-value, and saves a scatter plot to `~/Downloads/`."
            ),
            "param_type": "corr",
            "has_conf": True,
            "sample_data_dir": CORR_DATA,
            "sample_prefix": "corr_",
            "png_pattern": "*_jrc_corr_pearson.png",
        },
        "Spearman Correlation": {
            "script": "jrc_corr_spearman.R",
            "description": (
                "Computes Spearman's rank correlation coefficient (rho) — the "
                "non-parametric analogue of Pearson's r. Reports rho, S statistic, "
                "p-value, and saves a rank scatter plot to `~/Downloads/`."
            ),
            "param_type": "corr",
            "has_conf": False,
            "sample_data_dir": CORR_DATA,
            "sample_prefix": "corr_",
            "png_pattern": "*_jrc_corr_spearman.png",
        },
        "OLS Linear Regression": {
            "script": "jrc_corr_regression.R",
            "description": (
                "Fits a simple OLS linear regression model (y = b₀ + b₁x). Reports "
                "intercept and slope with CIs, R², adjusted R², residual standard "
                "error, F-statistic, and saves a scatter + residuals plot to `~/Downloads/`."
            ),
            "param_type": "corr",
            "has_conf": True,
            "sample_data_dir": CORR_DATA,
            "sample_prefix": "corr_",
            "png_pattern": "*_jrc_corr_regression.png",
        },
        "Passing-Bablok Regression": {
            "script": "jrc_corr_passing_bablok.R",
            "description": (
                "Passing-Bablok regression for method comparison. Unlike OLS, treats "
                "both variables symmetrically — appropriate when both methods carry "
                "measurement error. Reports slope and intercept with CIs and saves a "
                "plot to `~/Downloads/`."
            ),
            "param_type": "corr",
            "has_conf": True,
            "sample_data_dir": CORR_DATA,
            "sample_prefix": "corr_",
            "png_pattern": "*_jrc_corr_passing_bablok.png",
        },
    },

    # -----------------------------------------------------------------------
    "Cap": {
        "Normal Capability Analysis": {
            "script": "jrc_cap_normal.R",
            "description": (
                "Process capability analysis for normally distributed data. "
                "Computes **Cp**, **Cpk**, **Pp**, **Ppk**, and **Cpm** (Taguchi) using "
                "within-subgroup (MR-based) and overall sigma estimates. Reports sigma level, "
                "estimated PPM out-of-spec, and saves a histogram with normal curve and "
                "spec limits to `~/Downloads/`."
            ),
            "param_type": "capability",
            "has_report": True,
            "sample_data_dir": CAP_DATA,
            "sample_prefix": "cap_normal_",
            "png_pattern": "*_jrc_cap_normal.png",
        },
        "Non-Normal Capability Analysis": {
            "script": "jrc_cap_nonnormal.R",
            "description": (
                "Process capability analysis for non-normally distributed data using the "
                "**percentile method** (ISO 22514-2 / AIAG). Estimates process spread from "
                "the 0.135th and 99.865th sample percentiles — equivalent to ±3σ boundaries "
                "without assuming normality. Reports **Pp** and **Ppk**, observed non-conformance, "
                "and Shapiro-Wilk advisory. Saves a histogram with KDE to `~/Downloads/`."
            ),
            "param_type": "capability",
            "has_report": True,
            "sample_data_dir": CAP_DATA,
            "sample_prefix": "cap_nonnormal_",
            "png_pattern": "*_jrc_cap_nonnormal.png",
        },
        "Capability Sixpack": {
            "script": "jrc_cap_sixpack.R",
            "description": (
                "Six-panel capability report — the standard deliverable for a process "
                "validation package. Combines: **I-MR control chart** (with spec limits), "
                "**Moving Range chart**, **capability histogram** with normal curve, "
                "**normal probability plot** (Q-Q), **numerical summary** (Cp, Cpk, Cpm, Pp, Ppk, "
                "sigma level, PPM), and a colour-coded **verdict panel**. "
                "Saves a 3600×2400 px PNG to `~/Downloads/`."
            ),
            "param_type": "capability",
            "has_report": True,
            "sample_data_dir": CAP_DATA,
            "sample_prefix": "cap_normal_",
            "png_pattern": "*_jrc_cap_sixpack.png",
        },
    },

    # -----------------------------------------------------------------------
    "Curve": {
        "Curve Properties": {
            "script": "jrc_curve_properties.py",
            "description": (
                "Extracts engineering properties from an XY measurement series — "
                "force vs. displacement, torque vs. angle, pressure vs. volume, or "
                "any time-ordered (X, Y) dataset.\n\n"
                "Properties computed include: peak values (max Y, min Y, max X, min X), "
                "area under curve (AUC), hysteresis area between loading/unloading arms, "
                "overall and secant slope, instantaneous slope at specified X, "
                "interpolated Y at X and X at Y, inflection points, and yield-like "
                "points where slope drops to a specified fraction of its maximum.\n\n"
                "The script is **config-file driven** — all analysis options are "
                "specified in a `.cfg` file (INI format). Select a sample config below, "
                "or run `jrc_curve_properties path/to/config.cfg` from the terminal for "
                "custom data."
            ),
            "param_type": "curve_cfg",
            "sample_data_dir": CURVE_DATA,
            "png_pattern": None,
        },
    },

    # -----------------------------------------------------------------------
    "Shelf Life": {
        "Q10 Accelerated Aging": {
            "script": "jrc_shelf_life_q10.R",
            "description": (
                "Calculates real-time shelf life from accelerated aging data using the "
                "**Q10 method** (ASTM F1980). Given a Q10 factor, accelerated and real-time "
                "temperatures, and the accelerated aging duration, computes the equivalent "
                "real-time shelf life with confidence bounds."
            ),
            "param_type": "shelf_q10",
            "has_report": True,
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Arrhenius Accelerated Aging": {
            "script": "jrc_shelf_life_arrhenius.R",
            "description": (
                "Calculates real-time shelf life from accelerated aging data using the "
                "**Arrhenius model**. More physically rigorous than Q10 when the activation "
                "energy is known from prior studies. Reports the acceleration factor and "
                "equivalent real-time shelf life."
            ),
            "param_type": "shelf_arrhenius",
            "has_report": True,
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Linear Degradation Model": {
            "script": "jrc_shelf_life_linear.R",
            "description": (
                "Estimates shelf life by fitting a **linear degradation model** to "
                "time-series stability data. Determines the time at which the one-sided "
                "confidence bound on the predicted mean crosses the specification limit "
                "(ICH Q1E method). Supports Box-Cox and log transforms for non-linear "
                "degradation. Saves a PNG and a model CSV for use with Shelf Life Extrapolate."
            ),
            "param_type": "shelf_linear",
            "has_report": True,
            "sample_data_dir": SHELF_DATA,
            "sample_prefix": "shelf_life_linear_",
            "png_pattern": "*_jrc_shelf_life_linear.png",
        },
        "Multi-Batch Poolability": {
            "script": "jrc_shelf_life_poolability.R",
            "description": (
                "Tests whether multiple batches can be pooled into a single shelf life "
                "estimate (ICH Q1E guidance). Runs batch-level slope and intercept tests "
                "using ANCOVA. Reports pooling verdict and saves a multi-batch plot PNG."
            ),
            "param_type": "fileonly",
            "has_report": True,
            "sample_data_dir": SHELF_DATA,
            "sample_prefix": "shelf_life_pool_",
            "png_pattern": "*_jrc_shelf_life_poolability.png",
        },
        "Extrapolate Shelf Life": {
            "script": "jrc_shelf_life_extrapolate.R",
            "description": (
                "Projects a shelf life estimate to a new time point using the model CSV "
                "produced by **Linear Degradation Model**. Reports the predicted value, "
                "confidence bound, and PASS/FAIL verdict relative to the original spec limit. "
                "Warns if projection exceeds 50% beyond the last observation (ICH Q1E)."
            ),
            "param_type": "shelf_extrapolate",
            "has_report": True,
            "sample_data_dir": SHELF_DATA,
            "sample_prefix": "shelf_life_extrapolate_model",
            "png_pattern": None,
            "png_from_output": True,
        },
    },

    # -----------------------------------------------------------------------
    "RDT": {
        "Plan Test": {
            "script": "jrc_rdt_plan.R",
            "description": (
                "Plans a Reliability Demonstration Test (RDT). Given a reliability claim "
                "(R at target life, confidence C), outputs the required number of test "
                "units for k = 0 to 5 allowed failures.\n\n"
                "Supports **Bogey/Binomial** mode (no Weibull shape assumption — "
                "recommended for FDA design verification) and **Weibayes** mode "
                "(Weibull shape β provided — reduces n when an accelerated test is used).\n\n"
                "Saves a bar chart PNG to `~/Downloads/`. Use **Evaluate Results** after "
                "testing to obtain the statistical verdict."
            ),
            "param_type": "rdt_plan",
            "sample_data_dir": None,
            "png_pattern": "*_jrc_rdt_plan.png",
        },
        "Evaluate Results": {
            "script": "jrc_rdt_verify.R",
            "description": (
                "Evaluates whether a pre-specified reliability claim is demonstrated by "
                "actual RDT test results. Reads a CSV of unit test times and pass/fail "
                "statuses.\n\n"
                "Always reports the **Binomial (Clopper-Pearson)** verdict. When β is "
                "provided, also reports the **Weibayes** verdict — more powerful when "
                "units were tested beyond target life.\n\n"
                "CSV must contain `time` and `status` columns (status: 0 = survived, "
                "1 = failed). Saves a timeline + verdict PNG to `~/Downloads/`."
            ),
            "param_type": "rdt_verify",
            "has_report": True,
            "sample_data_dir": RDT_DATA,
            "sample_prefix": "rdt_verify_",
            "png_pattern": "*_jrc_rdt_verify.png",
        },
    },
}

# ---------------------------------------------------------------------------
# Environment pre-flight check (cached per session)
# ---------------------------------------------------------------------------

def _release_status() -> dict:
    """Verify this checkout's release signature via bin/jr_verify_release.

    Cached per session. Falls back to 'advisory' whenever verification cannot
    run here (e.g. an end-user machine without Git) — never a false green.
    """
    if "release_status" not in st.session_state:
        _script = os.path.join(PROJECT_ROOT, "bin", "jr_verify_release")
        state, tag = "advisory", ""
        try:
            _p = subprocess.run(
                ["bash", _script, "HEAD"],
                capture_output=True, text=True, timeout=15, cwd=PROJECT_ROOT,
            )
            _out = (_p.stdout or "").strip().split()
            _kw  = _out[0] if _out else ""
            if _kw == "VERIFIED":
                state, tag = "verified", (_out[1] if len(_out) > 1 else "")
            elif _kw == "INVALID":
                state, tag = "invalid", (_out[1] if len(_out) > 1 else "")
            elif _kw == "UNSIGNED":
                state = "unsigned"
        except Exception:
            state = "advisory"
        st.session_state["release_status"] = {"state": state, "tag": tag}
    return st.session_state["release_status"]


def _get_env_status() -> dict:
    if "env_status" not in st.session_state:
        _r_req_file  = os.path.join(PROJECT_ROOT, "admin", "r_version.txt")
        _py_req_file = os.path.join(PROJECT_ROOT, "admin", "python_version.txt")

        _r_required  = open(_r_req_file).read().strip()  if os.path.exists(_r_req_file)  else "?"
        _py_req_full = open(_py_req_file).read().strip() if os.path.exists(_py_req_file) else "?.?.?"
        _py_required = ".".join(_py_req_full.split(".")[:2])

        _v           = sys.version_info
        _py_inst     = f"{_v.major}.{_v.minor}.{_v.micro}"
        _py_ok       = f"{_v.major}.{_v.minor}" == _py_required

        _r_inst, _r_ok = "not found", False
        _rscript_candidates = [
            "Rscript",
            "/usr/local/bin/Rscript",
            "/opt/homebrew/bin/Rscript",
            "/Library/Frameworks/R.framework/Resources/bin/Rscript",
        ]
        if sys.platform == "win32":
            _win = sorted(glob.glob(r"C:\Program Files\R\R-*\bin\Rscript.exe"), reverse=True)
            _rscript_candidates = _win + _rscript_candidates
        for _rscript in _rscript_candidates:
            try:
                _rp = subprocess.run(
                    [_rscript, "--vanilla", "-e", "cat(format(getRversion(), nsmall=1))"],
                    capture_output=True, text=True, encoding="utf-8", timeout=10,
                )
                if _rp.returncode == 0:
                    _r_full = _rp.stdout.strip()
                    _r_inst = _r_full
                    _r_ok   = ".".join(_r_full.split(".")[:2]) == _r_required
                    break
            except Exception:
                continue

        st.session_state.env_status = {
            "r_ok": _r_ok,   "r_installed": _r_inst,  "r_required": _r_required,
            "py_ok": _py_ok, "py_installed": _py_inst, "py_required": _py_required,
            "all_ok": _r_ok and _py_ok,
        }
    return st.session_state.env_status

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------

st.set_page_config(
    page_title="JR Anchored",
    page_icon="⚓",
    layout="wide",
)

# ---------------------------------------------------------------------------
# Idle watchdog — shut the server down when the last browser tab disconnects.
#
# Streamlit never exits on its own when the browser goes away, so without
# this, closing the tab (instead of using the Close GUI button) leaves an
# orphaned server holding a port until the next reboot.
# ---------------------------------------------------------------------------

@st.cache_resource
def _start_idle_watchdog() -> bool:
    import threading
    import time

    GRACE_S = 120   # allow time for the browser to connect after launch
    IDLE_S  = 180   # exit after this long with no connected sessions
    POLL_S  = 10

    def _watch() -> None:
        time.sleep(GRACE_S)
        idle_since: float | None = None
        while True:
            try:
                from streamlit.runtime import get_instance
                n_sessions = len(get_instance()._session_mgr.list_active_sessions())
            except Exception:
                n_sessions = 1  # can't tell — assume active, never self-kill
            if n_sessions == 0:
                if idle_since is None:
                    idle_since = time.monotonic()
                elif time.monotonic() - idle_since >= IDLE_S:
                    os._exit(0)
            else:
                idle_since = None
            time.sleep(POLL_S)

    threading.Thread(target=_watch, daemon=True, name="jr-idle-watchdog").start()
    return True

_start_idle_watchdog()

# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------

st.sidebar.title("⚓ JR Anchored")
st.sidebar.caption("Validated R & Python analytics")
st.sidebar.markdown("---")

_env = _get_env_status()
_r_line  = (f"✅ R {_env['r_installed']}" if _env["r_ok"]
            else f"❌ R {_env['r_installed']} *(need {_env['r_required']})*")
_py_line = (f"✅ Python {_env['py_installed']}" if _env["py_ok"]
            else f"❌ Python {_env['py_installed']} *(need {_env['py_required']})*")
st.sidebar.markdown(f"**Environment**  \n{_r_line}  \n{_py_line}")

_rel = _release_status()
if _rel["state"] == "invalid":
    st.sidebar.error(f"⛔ Signature INVALID {_rel['tag']} — do not use this copy")
else:
    _rel_line = {
        "verified": f"✅ Verified release {_rel['tag']}",
        "unsigned": "🧪 Development checkout (unsigned)",
        "advisory": "🔒 Verified by your administrator on update",
    }[_rel["state"]]
    st.sidebar.markdown(_rel_line)
st.sidebar.markdown("---")

page = st.sidebar.radio("Navigation", ["Scripts", "⚙  Settings", "🔧  Admin"], label_visibility="collapsed")
st.sidebar.markdown("---")

if page == "Scripts":
    module_choice = st.sidebar.selectbox("Module", list(CATALOGUE.keys()))
    scripts_in_module = CATALOGUE[module_choice]
    script_choice = st.sidebar.selectbox("Script", list(scripts_in_module.keys()))
    cfg = scripts_in_module[script_choice]
    param_type = cfg["param_type"]
else:
    module_choice = ""
    script_choice = ""
    cfg = {}
    param_type = ""

NO_FILE_TYPES = {
    "as_design", "as_variables", "as_oc_curve",
    "ss_discrete", "ss_discrete_ci", "ss_power",
    "ss_sigma", "ss_fatigue", "ss_gauge_rr",
    "gen_2param",
    "rdt_plan",
    "verify_discrete",
    "shelf_q10", "shelf_arrhenius",
}
needs_file = param_type not in NO_FILE_TYPES

st.sidebar.markdown("---")
if st.sidebar.button("⏹  Close GUI", use_container_width=True):
    import threading
    # Hide Streamlit's "Connection error" modal before the server dies.
    # The CSS lands in the browser's CSSOM in this render batch; the modal
    # is created by React after the WebSocket drops but display:none keeps
    # it invisible.  data-baseweb="modal" is the BaseWeb Modal root element.
    st.markdown(
        "<style>[data-baseweb='modal']{display:none!important}</style>",
        unsafe_allow_html=True,
    )
    def _shutdown() -> None:
        import time
        time.sleep(1.0)
        os._exit(0)
    threading.Thread(target=_shutdown, daemon=True).start()
    st.stop()
st.sidebar.caption("After closing, you can also close this browser tab.")

# ---------------------------------------------------------------------------
# Main panel
# ---------------------------------------------------------------------------

# Streamlit version drift banner. The GUI was tested against the pinned version
# (admin/streamlit_version.txt); a mismatch can affect the GUI only — e.g. the
# idle watchdog uses a private Streamlit API. Analysis results run through jrrun
# and are unaffected. Shown in-app because Dock launches have no visible
# terminal, so the launcher's stdout warning never reaches the user.
_st_pin_file = os.path.join(PROJECT_ROOT, "admin", "streamlit_version.txt")
try:
    with open(_st_pin_file, encoding="utf-8") as _f:
        _st_pin = _f.read().strip()
except OSError:
    _st_pin = ""
if _st_pin and st.__version__.replace("-", ".") != _st_pin.replace("-", "."):
    st.warning(
        f"**Streamlit {st.__version__} is installed; this GUI was tested with "
        f"{_st_pin}.** Your analysis results are unaffected — every calculation "
        f"runs through the validated `jrrun` path. If the interface looks or "
        f"behaves oddly, install the tested version with "
        f"`python -m pip install streamlit=={_st_pin}`.",
        icon="⚠️",
    )

# ---------------------------------------------------------------------------
# Settings page (renders and stops; Scripts page continues below)
# ---------------------------------------------------------------------------

if page == "⚙  Settings":
    st.title("⚙  Settings")

    st.markdown("### Validation Pack")
    pack_available = os.path.isfile(PACK_CONFIG)

    if not pack_available:
        st.info(
            "The **Validation Pack** is not installed on this machine.  \n"
            "It is a paid add-on that enables Word report generation for design "
            "verification and process validation. If you have purchased it, ask "
            "your administrator to install it. If you are not a Validation Pack "
            "user, no action is needed here."
        )
    else:
        with open(PACK_CONFIG, encoding="utf-8") as _f:
            _config = json.load(_f)

        with st.form("pack_settings_form"):
            st.markdown("### Report configuration")
            s_company = st.text_input(
                "Company name",
                value=_config.get("company_name", ""),
                help="Appears on the cover page of every generated report.",
            )
            _current_logo = _config.get("logo_path", "")
            _logo_display = _current_logo if _current_logo else "(none)"
            st.markdown(f"**Company logo** — current: `{_logo_display}`")
            s_logo_file = st.file_uploader(
                "Upload new logo (PNG or JPG)",
                type=["png", "jpg", "jpeg"],
                help="Leave empty to keep the current logo.",
            )
            s_prefix = st.text_input(
                "Document number prefix",
                value=_config.get("doc_number_prefix", ""),
                placeholder="e.g. ACME-",
                help="Prepended to the document number field (e.g. ACME- → ACME-PV-2026-001).",
            )
            submitted = st.form_submit_button("💾  Save", type="primary")

        if submitted:
            _config["company_name"]      = s_company
            _config["doc_number_prefix"] = s_prefix

            if s_logo_file is not None:
                _shared_dir = os.path.join(PACK_DIR, "shared")
                os.makedirs(_shared_dir, exist_ok=True)
                _dst = os.path.join(_shared_dir, s_logo_file.name)
                with open(_dst, "wb") as _f:
                    _f.write(s_logo_file.getbuffer())
                _config["logo_path"] = os.path.join("shared", s_logo_file.name)

            with open(PACK_CONFIG, "w", encoding="utf-8") as _f:
                json.dump(_config, _f, indent=2, ensure_ascii=False)
            st.success("Configuration saved.")

        st.markdown("---")
        st.caption(f"Config file: `{PACK_CONFIG}`")

    # --- Terminal Access (optional) ----------------------------------------
    st.markdown("---")
    st.markdown("### Terminal Access *(optional)*")
    st.caption(
        "Only needed if you want to run JR scripts from a Terminal window. "
        "The GUI works without this."
    )

    _home = os.path.expanduser("~")
    _rc_file = os.path.join(_home, ".zprofile" if sys.platform == "darwin" else ".bashrc")
    _marker  = "# JR Validated Environment — begin"
    _configured = (
        os.path.exists(_rc_file)
        and _marker in open(_rc_file, encoding="utf-8").read()
    )

    if _configured:
        st.success(f"PATH is configured — JR scripts are available in every Terminal window.")
    else:
        st.info("Not configured yet. Click below to add JR scripts to your shell PATH.")

    _setup_script = os.path.join(PROJECT_ROOT, "setup_jr_path.sh")
    if st.button("▶  Run setup_jr_path.sh", key="btn_path_setup"):
        _result = subprocess.run(
            BASH_PREFIX + [_setup_script],
            capture_output=True, text=True, cwd=PROJECT_ROOT,
        )
        _out = (_result.stdout or "") + (_result.stderr or "")
        st.code(_out, language="text")
        if _result.returncode == 0:
            st.success("Done. **Open a new Terminal window** before using JR scripts from the command line.")
        else:
            st.error("Setup failed — see output above.")

    # --- Install App (optional) --------------------------------------------
    st.markdown("---")
    st.markdown("### Install App *(optional)*")
    st.caption("Convenience only — the GUI works without this.")
    st.markdown(
        "After installing, you can launch JR Anchored directly from **Launchpad** — "
        "no need to locate the app file each time."
    )

    if sys.platform == "darwin":
        _app_src = os.path.join(PROJECT_ROOT, "JR Anchored.app")
        _app_dst = os.path.expanduser("~/Applications/JR Anchored.app")
        if os.path.exists(_app_dst):
            st.success("JR Anchored is installed in ~/Applications.")
        else:
            st.info("Installs to ~/Applications so you can open JR Anchored from Launchpad, Spotlight, or the Dock.")
        if st.button("📲  Install to ~/Applications", key="btn_install_app"):
            if os.path.exists(_app_dst):
                shutil.rmtree(_app_dst)
            _inst = subprocess.run(["ditto", _app_src, _app_dst],
                                   capture_output=True, text=True)
            if _inst.returncode == 0:
                st.success("Installed. Find JR Anchored in ~/Applications, Launchpad, or Spotlight.")
                st.info("Drag it from ~/Applications to your Dock to pin it.")
            else:
                st.error(f"Install failed: {_inst.stderr}")

    elif sys.platform == "win32":
        _ps1 = os.path.join(PROJECT_ROOT, "Create JR Anchored Shortcut.ps1")
        st.info("Create a Desktop shortcut with the anchor icon, then pin it to the taskbar.")
        if st.button("📲  Create Desktop Shortcut", key="btn_shortcut"):
            _sc = subprocess.run(
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", _ps1],
                capture_output=True, text=True, encoding="utf-8", cwd=PROJECT_ROOT,
            )
            st.code((_sc.stdout or "") + (_sc.stderr or ""), language="text")
            if _sc.returncode == 0:
                st.success("Shortcut created on your Desktop.")
            else:
                st.error("Failed — see output above.")

    if sys.platform == "darwin":
        st.markdown("---")
        st.caption(
            f"App log (if something goes wrong): `{os.path.expanduser('~/.jrscript/jr_app.log')}`"
        )

    st.stop()

# ---------------------------------------------------------------------------
# Admin page
# ---------------------------------------------------------------------------

if page == "🔧  Admin":

    # Admin password is a salted, iterated PBKDF2-HMAC-SHA256 hash. It gates the
    # GUI Admin tab as a convenience control only — it is NOT the validated
    # security boundary (anyone with terminal/file access to this machine can run
    # the admin scripts directly). See docs/VERIFYING.md / SECURITY.md.
    _PBKDF2_ITERS = 200_000

    def _hash_pw(pw: str, salt: bytes | None = None, iters: int = _PBKDF2_ITERS) -> str:
        salt = salt or os.urandom(16)
        dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, iters)
        return f"pbkdf2_sha256${iters}${salt.hex()}${dk.hex()}"

    def _verify_pw(pw: str, stored: str | None) -> tuple[bool, bool]:
        """Return (ok, needs_upgrade). Verifies against the PBKDF2 format, and
        falls back to the legacy unsalted SHA-256 so existing passwords keep
        working — flagging them for transparent upgrade on next success."""
        if not stored:
            return False, False
        if stored.startswith("pbkdf2_sha256$"):
            try:
                _, iters_s, salt_hex, hash_hex = stored.split("$")
                calc = hashlib.pbkdf2_hmac(
                    "sha256", pw.encode(), bytes.fromhex(salt_hex), int(iters_s))
                return hmac.compare_digest(calc.hex(), hash_hex), False
            except Exception:
                return False, False
        # Legacy: unsalted single-round SHA-256 — verify, then upgrade if it matches.
        legacy = hashlib.sha256(pw.encode()).hexdigest()
        ok = hmac.compare_digest(legacy, stored)
        return ok, ok

    def _stored_hash() -> str | None:
        if os.path.exists(ADMIN_CONFIG):
            try:
                with open(ADMIN_CONFIG) as _f:
                    return json.load(_f).get("password_hash")
            except Exception:
                return None      # unreadable/corrupt config → fail closed
        return None

    def _save_admin_pw(pw: str):
        with open(ADMIN_CONFIG, "w") as _f:
            json.dump({"password_hash": _hash_pw(pw)}, _f)
        try:
            os.chmod(ADMIN_CONFIG, 0o600)   # owner-only (best effort on Windows)
        except OSError:
            pass

    st.title("🔧  Admin")

    _stored = _stored_hash()

    if not st.session_state.get("admin_unlocked"):
        if _stored is None:
            st.info("No admin password set. Create one to continue.")
            with st.form("admin_set_pw"):
                _pw1 = st.text_input("New password",     type="password", key="adm_pw1")
                _pw2 = st.text_input("Confirm password", type="password", key="adm_pw2")
                if st.form_submit_button("Set password", type="primary"):
                    if not _pw1:
                        st.error("Password cannot be empty.")
                    elif _pw1 != _pw2:
                        st.error("Passwords do not match.")
                    else:
                        _save_admin_pw(_pw1)
                        st.session_state.admin_unlocked = True
                        st.rerun()
        else:
            with st.form("admin_login"):
                _pw = st.text_input("Admin password", type="password", key="adm_pw")
                if st.form_submit_button("Unlock", type="primary"):
                    _ok, _upgrade = _verify_pw(_pw, _stored)
                    if _ok:
                        if _upgrade:
                            _save_admin_pw(_pw)   # migrate legacy hash to PBKDF2
                        st.session_state.admin_unlocked = True
                        st.rerun()
                    else:
                        st.error("Incorrect password.")
        st.caption(
            "This password gates the GUI Admin tab — a convenience control, not "
            "the validated security boundary. Anyone with terminal or file access "
            "to this machine can run the admin scripts directly."
        )
        st.stop()

    # Authenticated -------------------------------------------------------

    _col_lock, _col_clear, _ = st.columns([1, 1, 4])
    if _col_lock.button("🔒  Lock admin"):
        st.session_state.admin_unlocked = False
        st.rerun()
    _col_clear.button("🗑  Clear output")

    with st.expander("🔑  Change admin password"):
        with st.form("admin_change_pw"):
            _old_pw  = st.text_input("Current password",     type="password", key="adm_old")
            _new_pw1 = st.text_input("New password",         type="password", key="adm_new1")
            _new_pw2 = st.text_input("Confirm new password", type="password", key="adm_new2")
            if st.form_submit_button("Change password"):
                _old_ok, _ = _verify_pw(_old_pw, _stored_hash())
                if not _old_ok:
                    st.error("Current password is incorrect.")
                elif not _new_pw1:
                    st.error("New password cannot be empty.")
                elif _new_pw1 != _new_pw2:
                    st.error("New passwords do not match.")
                else:
                    _save_admin_pw(_new_pw1)
                    st.success("Password changed.")

    st.markdown("---")

    ADMIN_DIR = os.path.join(PROJECT_ROOT, "admin")

    def _run_admin_cmd(label: str, cmd: list):
        out_area = st.empty()
        lines = []
        proc = subprocess.Popen(
            BASH_PREFIX + cmd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True, encoding="utf-8", cwd=PROJECT_ROOT,
        )
        for line in proc.stdout:
            lines.append(line)
            out_area.code("".join(lines), language="text")
        proc.wait()
        if not lines:
            out_area.code("(no output)", language="text")
        if proc.returncode == 0:
            st.success(f"{label} completed successfully.")
        else:
            st.error(f"{label} failed (exit {proc.returncode}).")

    def _run_oq_cmd(label: str, cmd: list):
        _status = st.empty()
        _status.info(f"⏳ {label} running… (may take several minutes)")
        _live = st.empty()
        proc = subprocess.Popen(
            BASH_PREFIX + cmd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True, encoding="utf-8", cwd=PROJECT_ROOT,
        )
        lines = []
        for line in proc.stdout:
            lines.append(line)
            # Stream live tail every 10 lines — keeps WebSocket alive and shows progress.
            if len(lines) % 10 == 0:
                _live.code("".join(lines[-80:]), language="text")
        proc.wait()
        _status.empty()
        _live.empty()

        # Find admin_oq_all summary block ("OQ ALL — SUMMARY") — search from end.
        oq_all_idx = next(
            (len(lines) - 1 - i for i, ln in enumerate(reversed(lines))
             if "OQ ALL" in ln),
            None,
        )
        # Find "short test summary info" section (present when any pytest run has failures).
        summary_idx = next(
            (i for i, ln in enumerate(lines) if "short test summary info" in ln),
            None,
        )
        # Find final pytest count line  ===  N passed … ===
        final_idx = next(
            (len(lines) - 1 - i
             for i, ln in enumerate(reversed(lines))
             if re.search(r"={5,}.+passed", ln) or re.search(r"={5,}.+failed", ln)),
            None,
        )

        if oq_all_idx is not None:
            start = oq_all_idx
        elif summary_idx is not None:
            start = summary_idx
        elif final_idx is not None:
            start = final_idx
        else:
            start = max(0, len(lines) - 10)

        display = "".join(lines[start:]).strip() or "(no output)"
        st.code(display, language="text")

        if proc.returncode == 0:
            st.success(f"{label} completed — all tests passed.")
        else:
            st.error(f"{label} failed (exit {proc.returncode}).")
            with st.expander("Full output"):
                st.code("".join(lines), language="text")

    def _run_admin_long(label: str, cmd: list):
        """For multi-minute commands (setup, env rebuilds): stream a live tail to
        keep the connection alive, then show the result and full output."""
        _status = st.empty()
        _status.info(f"⏳ {label} running… this can take several minutes. Keep this tab open.")
        _live = st.empty()
        proc = subprocess.Popen(
            BASH_PREFIX + cmd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True, encoding="utf-8", cwd=PROJECT_ROOT,
        )
        lines = []
        for line in proc.stdout:
            lines.append(line)
            if len(lines) % 5 == 0:
                _live.code("".join(lines[-60:]), language="text")
        proc.wait()
        _status.empty()
        _live.code("".join(lines[-60:]) or "(no output)", language="text")
        if proc.returncode == 0:
            st.success(f"{label} completed successfully.")
        else:
            st.error(f"{label} failed (exit {proc.returncode}).")
        with st.expander("Full output"):
            st.code("".join(lines) or "(no output)", language="text")
        return proc.returncode

    def _run_confirmed_cmd(label: str, cmd: list, stdin_text: str):
        """For commands that prompt on stdin (e.g. admin_uninstall): feed the
        confirmation automatically — the GUI has already gated the action."""
        proc = subprocess.Popen(
            BASH_PREFIX + cmd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.PIPE,
            text=True, encoding="utf-8", cwd=PROJECT_ROOT,
        )
        out, _ = proc.communicate(input=stdin_text)
        st.code(out or "(no output)", language="text")
        if proc.returncode == 0:
            st.success(f"{label} completed successfully.")
        else:
            st.error(f"{label} failed (exit {proc.returncode}).")

    # --- Setup & Environments --------------------------------------------
    st.markdown("### Setup & Environments")
    st.caption(
        "First-time setup and package environment management. Build/rebuild steps "
        "download from the internet and can take 10–30 minutes."
    )

    st.markdown("**First-time setup**")
    st.caption(
        "Downloads all packages, installs the R and Python environments, generates "
        "the integrity file, runs IQ validation, and adds scripts to PATH. Run once "
        "on a new machine."
    )
    if st.button("▶  admin_setup --rebuild", key="btn_setup_rebuild", use_container_width=True):
        _run_admin_long("admin_setup --rebuild", [os.path.join(ADMIN_DIR, "admin_setup"), "--rebuild"])

    st.markdown("**Rebuild a single environment**")
    _e1, _e2 = st.columns(2)
    with _e1:
        if st.button("▶  admin_install_R --rebuild", key="btn_install_r", use_container_width=True):
            _run_admin_long("admin_install_R --rebuild", [os.path.join(ADMIN_DIR, "admin_install_R"), "--rebuild"])
    with _e2:
        if st.button("▶  admin_install_Python --rebuild", key="btn_install_py", use_container_width=True):
            _run_admin_long("admin_install_Python --rebuild", [os.path.join(ADMIN_DIR, "admin_install_Python"), "--rebuild"])

    st.markdown("**Add a package to the validated environment**")
    st.caption(
        "Pins one new package (and its dependencies) into the repository, then "
        "reinstalls. Format: `name==version`. After adding, run **admin_create_hash** "
        "and **admin_validate** below to update the integrity file and re-validate."
    )
    _p1, _p2 = st.columns(2)
    with _p1:
        _r_pkg = st.text_input("R package", key="add_r_pkg", placeholder="stringr==1.5.1", label_visibility="collapsed")
        if st.button("➕  Add R package", key="btn_add_r", use_container_width=True):
            if "==" in _r_pkg:
                _run_admin_long(f"admin_install_R --add {_r_pkg.strip()}",
                                [os.path.join(ADMIN_DIR, "admin_install_R"), "--add", _r_pkg.strip()])
            else:
                st.error("Enter the package as name==version (e.g. stringr==1.5.1).")
    with _p2:
        _py_pkg = st.text_input("Python package", key="add_py_pkg", placeholder="pandas==2.2.2", label_visibility="collapsed")
        if st.button("➕  Add Python package", key="btn_add_py", use_container_width=True):
            if "==" in _py_pkg:
                _run_admin_long(f"admin_install_Python --add {_py_pkg.strip()}",
                                [os.path.join(ADMIN_DIR, "admin_install_Python"), "--add", _py_pkg.strip()])
            else:
                st.error("Enter the package as name==version (e.g. pandas==2.2.2).")

    st.markdown("---")

    # --- Integrity & Validation ------------------------------------------
    st.markdown("### Integrity & Validation")
    _col_h, _col_v = st.columns(2)
    with _col_h:
        st.markdown("**Regenerate integrity file**")
        st.caption("Run after adding or changing any script. Regenerates `project_integrity.sha256`.")
        _run_hash = st.button("▶  admin_create_hash", key="btn_hash", use_container_width=True)
    with _col_v:
        st.markdown("**Generate IQ validation evidence**")
        st.caption("Runs R and Python env validation scripts, produces timestamped audit file.")
        _run_validate = st.button("▶  admin_validate", key="btn_validate", use_container_width=True)

    if _run_hash:
        _run_admin_cmd("admin_create_hash", [os.path.join(ADMIN_DIR, "admin_create_hash")])
    if _run_validate:
        _run_admin_cmd("admin_validate", [os.path.join(ADMIN_DIR, "admin_validate")])

    st.markdown("---")

    # --- Verification ----------------------------------------------------
    st.markdown("### Verification")
    st.caption(
        "Confirm this copy is a genuine, signed release. End users see this "
        "automatically in the sidebar — these buttons let an administrator or "
        "auditor check on demand, no Terminal needed."
    )

    _PUBLISHED_FINGERPRINT = "SHA256:YYBTzXiKRJfcbWWzGH4DD6RifOfLlBA88BVUg2hnGTA"

    def _signing_key_fingerprint():
        """SHA256 fingerprint of the pinned signing key, computed in pure Python
        (the way OpenSSH does) — no ssh-keygen subprocess, so it works anywhere."""
        p = os.path.join(PROJECT_ROOT, "admin", "allowed_signers")
        if not os.path.exists(p):
            return None
        try:
            for line in open(p):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                for i, tok in enumerate(parts):
                    if tok.startswith("ssh-") and i + 1 < len(parts):
                        raw = base64.b64decode(parts[i + 1])
                        return "SHA256:" + base64.b64encode(
                            hashlib.sha256(raw).digest()).decode().rstrip("=")
        except Exception:
            return None
        return None

    _cv1, _cv2 = st.columns(2)
    _do_verify = _cv1.button("🔏  Verify release signature", key="btn_verify_rel",
                             use_container_width=True)
    _do_fpr    = _cv2.button("🔑  Check signing-key fingerprint", key="btn_verify_fpr",
                             use_container_width=True)

    if _do_verify:
        _vr = subprocess.run(
            BASH_PREFIX + [os.path.join(PROJECT_ROOT, "bin", "jr_verify_release"), "HEAD"],
            capture_output=True, text=True, encoding="utf-8", cwd=PROJECT_ROOT,
        )
        _out = (_vr.stdout or "").strip().split()
        _kw  = _out[0] if _out else ""
        _tag = _out[1] if len(_out) > 1 else ""
        if _kw == "VERIFIED":
            st.success(f"✅  Verified release **{_tag}** — genuine, signed release.")
        elif _kw == "INVALID":
            st.error(f"⛔  Signature INVALID for **{_tag}** — do not use this copy. "
                     "Re-clone from the official source.")
        elif _kw == "UNSIGNED":
            st.warning("🧪  This checkout is not on a signed release tag (development build).")
        else:
            st.info("ℹ️  Signature could not be verified here (Git unavailable, or signing "
                    "not configured on this copy).")

    if _do_fpr:
        _local = _signing_key_fingerprint()
        if _local and _local == _PUBLISHED_FINGERPRINT:
            st.success("✅  Signing key matches the fingerprint published on dwylup.com.\n\n"
                       f"`{_local}`")
        elif _local:
            st.error("⛔  The signing-key fingerprint does NOT match the published value — "
                     "do not trust this copy.\n\n"
                     f"This copy : `{_local}`\n\nPublished : `{_PUBLISHED_FINGERPRINT}`")
        else:
            st.info("ℹ️  No signing key is configured in `admin/allowed_signers` on this copy.")
        st.caption("Published fingerprint: dwylup.com → Verifying Authenticity.")

    st.markdown("---")

    # --- Update ----------------------------------------------------------
    st.markdown("### Update")
    st.caption(
        "Pre-flight conflict checks (uncommitted changes, R version mismatch, local commits), "
        "then git pull → re-hash → reinstall environments as needed."
    )
    _run_update = st.button("▶  admin_update", key="btn_update")
    if _run_update:
        _run_admin_cmd("admin_update", [os.path.join(ADMIN_DIR, "admin_update")])

    st.markdown("---")

    # --- OQ Testing ------------------------------------------------------
    st.markdown("### OQ Testing")
    _oq1, _oq2, _oq3 = st.columns(3)
    with _oq1:
        st.markdown("**Pre-flight**")
        st.caption("Verify the OQ test environment is ready before running.")
        _run_oq_pre = st.button("▶  admin_oq_validate", key="btn_oq_validate", use_container_width=True)
    with _oq2:
        st.markdown("**Core suite**")
        st.caption("Core / community scripts only.")
        _run_oq_core = st.button("▶  admin_oq", key="btn_oq_core", use_container_width=True)
    with _oq3:
        st.markdown("**Full suite**")
        st.caption("Core / community plus all module suites (repos/*/).")
        _run_oq_all = st.button("▶  admin_oq_all", key="btn_oq_all", use_container_width=True)

    if _run_oq_pre:
        _run_admin_cmd("admin_oq_validate", [os.path.join(ADMIN_DIR, "admin_oq_validate")])
    if _run_oq_core:
        _run_oq_cmd("admin_oq", [os.path.join(ADMIN_DIR, "admin_oq")])
    if _run_oq_all:
        _run_oq_cmd("admin_oq_all", [os.path.join(ADMIN_DIR, "admin_oq_all")])

    st.markdown("---")

    # --- Validation Pack -------------------------------------------------
    st.markdown("### Validation Pack")
    _pack_installed = os.path.isfile(PACK_CONFIG)
    _pack_zips      = sorted(glob.glob(os.path.join(PROJECT_ROOT, "jr-anchored-pack-*.zip")))
    _pack_installer = os.path.join(PROJECT_ROOT, "install_pack.sh")

    if _pack_installed:
        st.success(
            "Validation Pack is installed — Word report generation is available on "
            "supported scripts."
        )

    if _pack_zips and os.path.isfile(_pack_installer):
        _zip_name = os.path.basename(_pack_zips[-1])
        st.markdown(
            f"Detected **{_zip_name}** in the project root. Installing verifies the "
            "download, unpacks it, and installs the report templates — no Terminal needed."
            + ("  \n_Re-running will overwrite the existing pack with this version._"
               if _pack_installed else "")
        )
        if st.button("▶  Install Validation Pack", key="btn_install_pack", use_container_width=True):
            _run_admin_cmd("Install Validation Pack", [_pack_installer])
            if os.path.isfile(PACK_CONFIG):
                st.success(
                    "Pack installed. Open the **Scripts** page to use the "
                    "**📄 Generate Word report** option — it is detected automatically. "
                    "Set your company name and logo on the **⚙ Settings** page."
                )
    elif not _pack_installed:
        st.info(
            "To install the Validation Pack, place the three files you received "
            "(`jr-anchored-pack-<date>.zip`, its `.sha256`, and `install_pack.sh`) in the "
            "JR Anchored root folder, then return to this page — an install button will appear."
        )

    st.markdown("---")

    # --- Export Configured App -------------------------------------------
    st.markdown("### Export Configured App")
    st.markdown(
        "Create a distributable zip with the shared project folder path baked in. "
        "Share via Slack or Mail — users unzip and double-click to launch."
    )
    _export_root = st.text_input(
        "Shared project folder path",
        value=PROJECT_ROOT,
        key="export_root",
        help="The path that end users' machines use to reach the shared project folder. "
             "For a network share use the UNC path (e.g. \\\\server\\JR Anchored). "
             "For Dropbox/OneDrive use %%USERPROFILE%%\\Dropbox\\JR Anchored — "
             "Windows expands %%USERPROFILE%% to each user's home folder at launch time.",
    )

    if sys.platform == "darwin":
        st.caption(
            "💡 Dropbox path? Use `~/Dropbox/JR Anchored` — "
            "the launcher expands `~` to each user's home folder at launch time."
        )

    if sys.platform == "win32":
        st.caption(
            "💡 Dropbox / OneDrive path? Replace your username with `%USERPROFILE%` "
            r"(e.g. `%USERPROFILE%\Dropbox\JR Anchored`) — "
            "Windows fills it in per user at launch time."
        )

    if sys.platform == "darwin":
        st.caption(
            "Produces `JR Anchored.zip` on your Desktop.  "
            "Users: download → unzip → right-click → **Open** once (Gatekeeper bypass) → done."
        )
        if st.button("📦  Create shareable zip (macOS)", key="btn_export_mac"):
            _app_src = os.path.join(PROJECT_ROOT, "JR Anchored.app")
            _zip_dst = os.path.expanduser("~/Desktop/JR Anchored.zip")
            if os.path.exists(_zip_dst):
                os.remove(_zip_dst)
            with tempfile.TemporaryDirectory() as _etmp:
                _app_copy = os.path.join(_etmp, "JR Anchored.app")
                _cp = subprocess.run(["ditto", _app_src, _app_copy],
                                     capture_output=True, text=True)
                if _cp.returncode != 0:
                    st.error(f"Copy failed: {_cp.stderr}")
                else:
                    _cfg = os.path.join(_app_copy, "Contents", "Resources",
                                        "jr_project_root.txt")
                    with open(_cfg, "w") as _f:
                        _f.write(_export_root.strip())
                    _zp = subprocess.run(
                        ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                         _app_copy, _zip_dst],
                        capture_output=True, text=True,
                    )
                    if _zp.returncode == 0:
                        st.success("Ready: `~/Desktop/JR Anchored.zip`")
                        st.info(
                            "**User instructions:**\n"
                            "1. Download and double-click the zip to extract\n"
                            "2. Right-click `JR Anchored.app` → **Open** (one-time Gatekeeper step)\n"
                            "3. Drag to Dock to pin for future use"
                        )
                    else:
                        st.error(f"Zip failed: {_zp.stderr}")

    elif sys.platform == "win32":
        st.caption(
            "Produces `JR Anchored Windows.zip` on your Desktop containing a "
            "configured .bat, the icon, and the shortcut creator."
        )
        if st.button("📦  Create shareable zip (Windows)", key="btn_export_win"):
            _bat_src = os.path.join(PROJECT_ROOT, "JR Anchored.bat")
            _ico_src = os.path.join(PROJECT_ROOT, "JR Anchored.ico")
            _ps1_src = os.path.join(PROJECT_ROOT, "Create JR Anchored Shortcut.ps1")
            _zip_dst = os.path.join(_win_desktop(), "JR Anchored Windows.zip")
            try:
                _bat_text       = open(_bat_src, encoding="utf-8").read()
                _bat_configured = _bat_text.replace(
                    'set "JRROOT="', f'set "JRROOT={_export_root.strip()}"'
                )
                with zipfile.ZipFile(_zip_dst, "w", zipfile.ZIP_DEFLATED) as _z:
                    _z.writestr("JR Anchored.bat", _bat_configured)
                    for _extra_file in [_ico_src, _ps1_src]:
                        if os.path.exists(_extra_file):
                            _z.write(_extra_file, os.path.basename(_extra_file))
                st.success(f"Ready: `{_zip_dst}`")
                st.info(
                    "**User instructions:**\n"
                    "1. Download and unzip\n"
                    "2. Right-click `Create JR Anchored Shortcut.ps1` → **Run with PowerShell**\n"
                    "3. Pin the Desktop shortcut to the taskbar"
                )
            except Exception as _ex:
                st.error(f"Export failed: {_ex}")

    st.caption(
        "ℹ️ Each zip is platform-specific. "
        "Export from a macOS admin machine for macOS users; "
        "export from a Windows admin machine for Windows users."
    )

    st.markdown("---")

    # --- Danger zone -----------------------------------------------------
    with st.expander("⚠️  Danger zone — Uninstall"):
        st.warning(
            "**admin_uninstall** removes this machine's local R library, Python "
            "venv, run log, and PATH entry. It does **not** delete the project "
            "folder or the shared package repository. After uninstalling, the "
            "environment must be rebuilt (**admin_setup**) before scripts can run again."
        )
        _uninstall_confirm = st.text_input(
            "Type UNINSTALL to confirm", key="uninstall_confirm",
            placeholder="UNINSTALL",
        )
        if st.button("🗑️  Run admin_uninstall", key="btn_uninstall"):
            if _uninstall_confirm.strip() == "UNINSTALL":
                _run_confirmed_cmd(
                    "admin_uninstall",
                    [os.path.join(ADMIN_DIR, "admin_uninstall")],
                    stdin_text="yes\n",
                )
            else:
                st.error("Type UNINSTALL (capitals) in the box above to confirm.")

    st.stop()

# ---------------------------------------------------------------------------
# Scripts page — title and description
# ---------------------------------------------------------------------------

if not _env["all_ok"]:
    _mismatch_parts = []
    if not _env["r_ok"]:
        _mismatch_parts.append(f"R {_env['r_installed']} installed — R {_env['r_required']} required")
    if not _env["py_ok"]:
        _mismatch_parts.append(f"Python {_env['py_installed']} installed — Python {_env['py_required']} required")
    st.error(
        "⚠️  Version mismatch — scripts will not run correctly.  \n"
        + "  \n".join(_mismatch_parts)
        + "  \nPlease install the correct version(s) and restart the app."
    )

st.title(script_choice)
st.markdown(f"<p style='font-size:1.2rem;color:#555;margin-top:-12px'>Script: <code>{cfg['script']}</code></p>", unsafe_allow_html=True)
st.markdown(cfg["description"])

help_path = _find_help_file(module_choice, cfg["script"])
if help_path:
    with st.expander("📖  Script help (--help)"):
        with open(help_path, encoding="utf-8") as _hf:
            st.code(_hf.read(), language="text")

if param_type == "curve_cfg":
    sample_cfg_path = os.path.join(CURVE_DATA, "sample.cfg")
    if os.path.exists(sample_cfg_path):
        with st.expander("📋  Sample config (sample.cfg)"):
            with open(sample_cfg_path, encoding="utf-8") as _sf:
                st.code(_sf.read(), language="text")

# ---------------------------------------------------------------------------
# Data section (file-based scripts)
# ---------------------------------------------------------------------------

data_path  = None
data_path2 = None
tmp_path   = None
tmp_path2  = None

if needs_file:
    st.markdown("### Data")

    if param_type == "bland_altman":
        col_a, col_b = st.columns(2)
        with col_a:
            st.markdown("**Method 1 / Device A**")
            up1 = st.file_uploader("Upload CSV (method 1)", type=["csv"],
                                   key=f"up1_{script_choice}")
            sdir = cfg["sample_data_dir"]
            sf1 = sorted(glob.glob(os.path.join(sdir, f"{cfg['sample_prefix']}*.csv")))
            sn1 = ["(none)"] + [os.path.basename(f) for f in sf1]
            sc1 = st.selectbox("Or sample data (method 1)", sn1,
                               key=f"sc1_{script_choice}")
        with col_b:
            st.markdown("**Method 2 / Device B**")
            up2 = st.file_uploader("Upload CSV (method 2)", type=["csv"],
                                   key=f"up2_{script_choice}")
            sf2 = sorted(glob.glob(os.path.join(sdir, "bland_altman_method2*.csv")))
            sn2 = ["(none)"] + [os.path.basename(f) for f in sf2]
            sc2 = st.selectbox("Or sample data (method 2)", sn2,
                               key=f"sc2_{script_choice}")

        if up1:
            _td1 = tempfile.mkdtemp()
            data_path = os.path.join(_td1, up1.name)
            with open(data_path, "wb") as _tf: _tf.write(up1.getvalue())
            tmp_path = data_path
        elif sc1 != "(none)":
            data_path = os.path.join(sdir, sc1)

        if up2:
            _td2 = tempfile.mkdtemp()
            data_path2 = os.path.join(_td2, up2.name)
            with open(data_path2, "wb") as _tf: _tf.write(up2.getvalue())
            tmp_path2 = data_path2
        elif sc2 != "(none)":
            data_path2 = os.path.join(sdir, sc2)

    elif param_type == "curve_cfg":
        cfg_files = sorted(glob.glob(os.path.join(cfg["sample_data_dir"], "*.cfg")))
        cfg_names = ["(none)"] + [os.path.basename(f) for f in cfg_files]
        cfg_choice = st.selectbox(
            "Sample config (.cfg)",
            cfg_names,
            key=f"cfg_{module_choice}_{script_choice}",
        )
        if cfg_choice != "(none)":
            data_path = os.path.join(cfg["sample_data_dir"], cfg_choice)
            st.info(f"Using sample config: **{cfg_choice}**")

        st.markdown("**Or upload your own:**")
        col_cfg, col_csv = st.columns(2)
        uploaded_cfg = col_cfg.file_uploader(
            "Config file (.cfg)", type=["cfg"],
            key=f"cfgup_{script_choice}",
        )
        uploaded_csv = col_csv.file_uploader(
            "Data CSV", type=["csv"],
            key=f"csvup_{script_choice}",
        )
        if uploaded_cfg:
            cfg_text = uploaded_cfg.getvalue().decode("utf-8")
            if uploaded_csv:
                csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
                csv_tmp.write(uploaded_csv.getvalue()); csv_tmp.close()
                tmp_path2 = csv_tmp.name
                cfg_text = re.sub(
                    r"(?m)^(\s*file\s*=\s*).*$", r"\g<1>" + csv_tmp.name, cfg_text
                )
            else:
                st.warning("Upload the matching data CSV so the config can find it.")
            cfg_dest = os.path.join(DOWNLOADS, uploaded_cfg.name)
            with open(cfg_dest, "w", encoding="utf-8") as _cf:
                _cf.write(cfg_text)
            data_path = cfg_dest
            tmp_path = cfg_dest
            st.success(f"Using uploaded config: **{uploaded_cfg.name}**")

        st.caption(
            "For complex setups with multiple data files, use the terminal: "
            "`jrc_curve_properties path/to/config.cfg`"
        )

    elif param_type in ("convert_csv", "convert_txt"):
        col_upload, col_sample = st.columns(2)
        with col_upload:
            uploaded_file = st.file_uploader(
                "Upload a data file", type=["csv", "txt", "tsv"],
                help="Plain-text or delimited file to convert.",
                key=f"upload_{module_choice}_{script_choice}",
            )
        with col_sample:
            sample_dir = cfg.get("sample_data_dir")
            prefix = cfg.get("sample_prefix") or ""
            if sample_dir:
                sample_files = sorted(
                    glob.glob(os.path.join(sample_dir, f"{prefix}*.txt")) +
                    glob.glob(os.path.join(sample_dir, f"{prefix}*.csv"))
                )
                sample_names = ["(none)"] + [os.path.basename(f) for f in sample_files]
            else:
                sample_names = ["(none)"]
            _n_samples = len(sample_names) - 1
            _sample_label = (f"Or use sample data ({_n_samples} "
                             f"file{'s' if _n_samples != 1 else ''} available)"
                             if _n_samples else "Or use sample data")
            sample_choice_val = st.selectbox(
                _sample_label, sample_names,
                key=f"sample_{module_choice}_{script_choice}",
            )

        if uploaded_file is not None:
            _td = tempfile.mkdtemp()
            data_path = os.path.join(_td, uploaded_file.name)
            with open(data_path, "wb") as _tf: _tf.write(uploaded_file.getvalue())
            tmp_path = data_path
            st.success(f"Using uploaded file: **{uploaded_file.name}**")
        elif sample_choice_val != "(none)":
            data_path = os.path.join(sample_dir, sample_choice_val)
            st.info(f"Using sample data: **{sample_choice_val}**")

    else:
        col_upload, col_sample = st.columns(2)
        with col_upload:
            uploaded_file = st.file_uploader(
                "Upload a CSV file", type=["csv"],
                help="CSV with column names on the first row.",
                key=f"upload_{module_choice}_{script_choice}",
            )
        with col_sample:
            sample_dir = cfg.get("sample_data_dir")
            prefix = cfg.get("sample_prefix") or ""
            if sample_dir:
                sample_files = sorted(
                    glob.glob(os.path.join(sample_dir, f"{prefix}*.csv"))
                )
                sample_names = ["(none)"] + [os.path.basename(f) for f in sample_files]
            else:
                sample_names = ["(none)"]
            _n_samples = len(sample_names) - 1
            _sample_label = (f"Or use sample data ({_n_samples} "
                             f"file{'s' if _n_samples != 1 else ''} available)"
                             if _n_samples else "Or use sample data")
            sample_choice_val = st.selectbox(
                _sample_label, sample_names,
                key=f"sample_{module_choice}_{script_choice}",
            )

        if uploaded_file is not None:
            _td = tempfile.mkdtemp()
            data_path = os.path.join(_td, uploaded_file.name)
            with open(data_path, "wb") as _tf: _tf.write(uploaded_file.getvalue())
            tmp_path = data_path
            st.success(f"Using uploaded file: **{uploaded_file.name}**")
        elif sample_choice_val != "(none)":
            data_path = os.path.join(sample_dir, sample_choice_val)
            st.info(f"Using sample data: **{sample_choice_val}**")

    # Preview (CSV files only)
    preview_path = data_path
    if preview_path and param_type not in ("convert_csv", "convert_txt", "curve_cfg"):
        try:
            import csv as csvmod
            with open(preview_path, "r") as f:
                reader = csvmod.reader(f)
                headers = next(reader)
                rows = list(reader)
            st.markdown(
                f"**Preview** — {len(rows)} rows, columns: `{', '.join(headers)}`"
            )
            preview_data = [dict(zip(headers, row)) for row in rows[:8]]
            st.dataframe(preview_data, use_container_width=True, hide_index=True)
        except Exception:
            pass

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

st.markdown("### Parameters")

sk = script_choice  # short key prefix

if param_type == "curve_cfg":
    st.caption("All analysis options are specified in the config file — no additional parameters.")

elif param_type == "fileonly":
    st.caption("No additional parameters required for this script.")

elif param_type == "corr":
    cols = st.columns(3) if cfg["has_conf"] else st.columns(2)
    xcol = cols[0].text_input("X column name", value="x", key=f"xcol_{sk}")
    ycol = cols[1].text_input("Y column name", value="y", key=f"ycol_{sk}")
    if cfg["has_conf"]:
        conf = cols[2].number_input("Confidence level", min_value=0.50,
            max_value=0.9999, value=0.95, step=0.01, format="%.2f", key=f"conf_{sk}")

elif param_type == "bland_altman":
    col1, col2 = st.columns(2)
    ba_col1 = col1.text_input("Column name (method 1)", value="value", key=f"col1_{sk}")
    ba_col2 = col2.text_input("Column name (method 2)", value="value", key=f"col2_{sk}")

elif param_type == "univariate":
    col1, _ = st.columns([1, 2])
    colname = col1.text_input("Column name", value="value", key=f"col_{sk}")

elif param_type == "capability":
    c1, c2, c3 = st.columns(3)
    colname = c1.text_input("Column name", value="value", key=f"col_{sk}")
    lsl     = c2.text_input("LSL (or - to omit)", value="-", key=f"lsl_{sk}")
    usl     = c3.text_input("USL (or - to omit)", value="-", key=f"usl_{sk}")

elif param_type == "weibull":
    c1, c2 = st.columns(2)
    time_col   = c1.text_input("Time column", value="time",   key=f"time_{sk}")
    status_col = c2.text_input("Status column (1=failed, 0=censored)", value="status",
                               key=f"status_{sk}")

elif param_type == "spc_limits":
    st.caption("Control limits are computed from the data by default. Supply historical limits to override.")
    c1, c2 = st.columns(2)
    ucl_val = c1.text_input("UCL (optional)", value="", placeholder="leave blank", key=f"ucl_{sk}")
    lcl_val = c2.text_input("LCL (optional)", value="", placeholder="leave blank", key=f"lcl_{sk}")

elif param_type == "msa_tolerance":
    c1, _ = st.columns([1, 2])
    tolerance = c1.text_input("Tolerance USL−LSL (optional)", value="",
                              placeholder="leave blank to omit", key=f"tol_{sk}")

elif param_type == "msa_type1":
    c1, c2 = st.columns(2)
    reference = c1.text_input("Reference value (required)",
                              help="Known true value of the reference part.", key=f"ref_{sk}")
    tolerance = c2.text_input("Tolerance USL−LSL (required)",
                              help="Process tolerance used to compute Cg and Cgk.", key=f"tol_{sk}")

elif param_type == "ss_discrete":
    c1, c2 = st.columns(2)
    proportion = c1.text_input("Proportion (e.g. 0.99)", value="0.99", key=f"prop_{sk}")
    confidence = c2.text_input("Confidence (e.g. 0.95)", value="0.95", key=f"conf_{sk}")

elif param_type == "ss_discrete_ci":
    c1, c2, c3 = st.columns(3)
    confidence = c1.text_input("Confidence (e.g. 0.95)", value="0.95", key=f"conf_{sk}")
    ss_n       = c2.text_input("Sample size n", value="30",            key=f"n_{sk}")
    ss_f       = c3.text_input("Failures f",    value="0",             key=f"f_{sk}")

elif param_type == "ss_power":
    c1, c2, c3 = st.columns(3)
    delta = c1.text_input("Equivalence / difference margin δ", value="0.5", key=f"delta_{sk}")
    sd    = c2.text_input("Expected SD of paired differences", value="0.5", key=f"sd_{sk}")
    sides = c3.selectbox("Sides", ["1 (one-sided)", "2 (two-sided)"],             key=f"sides_{sk}")

elif param_type == "ss_attr":
    c1, c2 = st.columns(2)
    proportion = c1.text_input("Proportion (e.g. 0.95)", value="0.95", key=f"prop_{sk}")
    confidence = c2.text_input("Confidence (e.g. 0.95)", value="0.95", key=f"conf_{sk}")
    c3, c4, c5 = st.columns(3)
    colname = c3.text_input("Column name",        value="value", key=f"col_{sk}")
    lsl     = c4.text_input("LSL (or - to omit)", value="-",     key=f"lsl_{sk}")
    usl     = c5.text_input("USL (or - to omit)", value="-",     key=f"usl_{sk}")

elif param_type == "ss_attr_check":
    c1, c2, c3 = st.columns(3)
    proportion = c1.text_input("Proportion (e.g. 0.95)", value="0.95", key=f"prop_{sk}")
    confidence = c2.text_input("Confidence (e.g. 0.95)", value="0.95", key=f"conf_{sk}")
    planned_n  = c3.text_input("Planned N",               value="30",   key=f"pn_{sk}")
    c4, c5, c6 = st.columns(3)
    colname = c4.text_input("Column name",        value="value", key=f"col_{sk}")
    lsl     = c5.text_input("LSL (or - to omit)", value="-",     key=f"lsl_{sk}")
    usl     = c6.text_input("USL (or - to omit)", value="-",     key=f"usl_{sk}")

elif param_type == "ss_attr_ci":
    c1, _ = st.columns([1, 2])
    confidence = c1.text_input("Confidence (e.g. 0.95)", value="0.95", key=f"conf_{sk}")
    c2, c3, c4 = st.columns(3)
    colname = c2.text_input("Column name",        value="value", key=f"col_{sk}")
    lsl     = c3.text_input("LSL (or - to omit)", value="-",     key=f"lsl_{sk}")
    usl     = c4.text_input("USL (or - to omit)", value="-",     key=f"usl_{sk}")

elif param_type == "ss_sigma":
    c1, c2, c3 = st.columns(3)
    precision = c1.text_input("Precision (sigma multiples, e.g. 1.5)", value="1.5", key=f"prec_{sk}")
    lsl       = c2.text_input("LSL (or - to omit)", value="-",         key=f"lsl_{sk}")
    usl       = c3.text_input("USL (or - to omit)", value="-",         key=f"usl_{sk}")

elif param_type == "ss_fatigue":
    c1, c2, c3, c4 = st.columns(4)
    reliability = c1.text_input("Reliability (e.g. 0.90 = B10)", value="0.90", key=f"rel_{sk}")
    confidence  = c2.text_input("Confidence (e.g. 0.95)",          value="0.95", key=f"conf_{sk}")
    shape       = c3.text_input("Weibull shape β",                  value="2.0",  key=f"shp_{sk}")
    af          = c4.text_input("Acceleration factor (≥ 1)",        value="1.0",  key=f"af_{sk}")

elif param_type == "ss_gauge_rr":
    c1, c2, c3 = st.columns(3)
    grr       = c1.text_input("Target %GRR (e.g. 10)",                        value="10", key=f"grr_{sk}")
    grr_type  = c2.selectbox("Type", ["process", "tolerance"],                            key=f"type_{sk}")
    sigma_tol = c3.text_input("Process σ (if process) or tolerance (if tolerance)",
                               value="1.0", key=f"st_{sk}")

elif param_type == "as_design":
    c1, c2, c3 = st.columns(3)
    lot_size = c1.text_input("Lot size", value="1000", key=f"lot_{sk}")
    aql      = c2.text_input("AQL (e.g. 0.01 = 1%)", value="0.01", key=f"aql_{sk}")
    rql      = c3.text_input("RQL (e.g. 0.10 = 10%)", value="0.10", key=f"rql_{sk}")
    c4, c5 = st.columns(2)
    alpha = c4.text_input("Producer's risk α (default 0.05)", value="", placeholder="0.05", key=f"alpha_{sk}")
    beta  = c5.text_input("Consumer's risk β (default 0.10)", value="", placeholder="0.10", key=f"beta_{sk}")

elif param_type == "as_variables":
    c1, c2, c3 = st.columns(3)
    lot_size = c1.text_input("Lot size", value="1000", key=f"lot_{sk}")
    aql      = c2.text_input("AQL (e.g. 0.01 = 1%)", value="0.01", key=f"aql_{sk}")
    rql      = c3.text_input("RQL (e.g. 0.10 = 10%)", value="0.10", key=f"rql_{sk}")
    c4, c5, c6 = st.columns(3)
    alpha = c4.text_input("Producer's risk α", value="", placeholder="0.05", key=f"alpha_{sk}")
    beta  = c5.text_input("Consumer's risk β", value="", placeholder="0.10", key=f"beta_{sk}")
    sides = c6.selectbox("Sides", ["1 (one-sided)", "2 (two-sided)"],          key=f"sides_{sk}")

elif param_type == "as_oc_curve":
    c1, c2, c3 = st.columns(3)
    oc_n   = c1.text_input("Sample size n",              value="32",  key=f"n_{sk}")
    oc_c   = c2.text_input("Acceptance number c",        value="0",   key=f"c_{sk}")
    oc_lot = c3.text_input("Lot size (optional)",        value="",    placeholder="leave blank", key=f"lot_{sk}")
    c4, c5 = st.columns(2)
    oc_aql = c4.text_input("AQL to annotate (optional)", value="",    placeholder="e.g. 0.01", key=f"aql_{sk}")
    oc_rql = c5.text_input("RQL to annotate (optional)", value="",    placeholder="e.g. 0.10", key=f"rql_{sk}")

elif param_type == "as_evaluate":
    c1, _ = st.columns([1, 2])
    eval_type = c1.selectbox("Inspection type", ["attributes", "variables"], key=f"type_{sk}")
    if eval_type == "attributes":
        c2, _ = st.columns([1, 2])
        eval_c = c2.text_input("Acceptance number c",
                               help="From jrc_as_attributes plan.", key=f"c_{sk}")
    else:
        c2, c3, c4 = st.columns(3)
        eval_k   = c2.text_input("Acceptability constant k",
                                 help="From jrc_as_variables plan.", key=f"k_{sk}")
        eval_lsl = c3.text_input("LSL (optional)", value="", placeholder="leave blank", key=f"lsl_{sk}")
        eval_usl = c4.text_input("USL (optional)", value="", placeholder="leave blank", key=f"usl_{sk}")

elif param_type == "doe_design":
    c1, c2 = st.columns(2)
    doe_type     = c1.selectbox("Design type",
                                ["full2", "full3", "fractional", "pb"],
                                key=f"dtype_{sk}")
    response_name = c2.text_input("Response variable name", value="Response",
                                  key=f"resp_{sk}")
    c3, c4 = st.columns(2)
    centre_pts = c3.text_input("Centre points (optional)", value="0",
                               help="Applies to full2 and fractional only.",
                               key=f"cp_{sk}")
    replicates = c4.text_input("Replicates (optional)", value="1",
                               key=f"rep_{sk}")

elif param_type == "doe_analyse":
    st.caption("Upload or select the companion CSV file produced by the Design Experiment script with responses filled in.")

elif param_type == "gen_2param":
    c1, c2, c3, c4 = st.columns(4)
    gen_n    = c1.text_input("n (observations)", value="30", key=f"n_{sk}")
    gen_p1   = c2.text_input(cfg["param1_label"], value=cfg["param1_default"], key=f"p1_{sk}")
    gen_p2   = c3.text_input(cfg["param2_label"], value=cfg["param2_default"], key=f"p2_{sk}")
    gen_seed = c4.text_input("Seed (optional)", value="", placeholder="leave blank",
                             key=f"seed_{sk}")

elif param_type == "rdt_plan":
    c1, c2, c3 = st.columns(3)
    rdt_rel  = c1.text_input("Reliability R (e.g. 0.95)", value="0.95",  key=f"rel_{sk}")
    rdt_conf = c2.text_input("Confidence C (e.g. 0.90)",  value="0.90",  key=f"conf_{sk}")
    rdt_tl   = c3.text_input("Target life T",             value="5000",  key=f"tl_{sk}")
    c4, c5, c6 = st.columns(3)
    rdt_beta = c4.text_input("Weibull β (leave blank = Bogey mode)", value="", placeholder="e.g. 2.0",
                             key=f"beta_{sk}")
    rdt_af   = c5.text_input("Accel factor (default 1.0)",           value="", placeholder="e.g. 2.0",
                             key=f"af_{sk}")
    rdt_k    = c6.text_input("k allowed failures (default 0)",       value="", placeholder="e.g. 1",
                             key=f"k_{sk}")

elif param_type == "rdt_verify":
    c1, c2, c3 = st.columns(3)
    rdt_rel  = c1.text_input("Reliability R (e.g. 0.95)", value="0.95",  key=f"rel_{sk}")
    rdt_conf = c2.text_input("Confidence C (e.g. 0.90)",  value="0.90",  key=f"conf_{sk}")
    rdt_tl   = c3.text_input("Target life T",             value="5000",  key=f"tl_{sk}")
    c4, _ = st.columns([1, 2])
    rdt_beta = c4.text_input("Weibull β (leave blank = Binomial only)", value="", placeholder="e.g. 2.0",
                             key=f"beta_{sk}")

elif param_type == "verify_discrete":
    c1, c2, c3, c4 = st.columns(4)
    vd_n    = c1.text_input("Units tested N",           value="125",  key=f"n_{sk}")
    vd_f    = c2.text_input("Failures f",               value="0",    key=f"f_{sk}")
    vd_prop = c3.text_input("Proportion P (e.g. 0.95)", value="0.95", key=f"prop_{sk}")
    vd_conf = c4.text_input("Confidence C (e.g. 0.95)", value="0.95", key=f"conf_{sk}")

elif param_type == "shelf_q10":
    c1, c2, c3, c4 = st.columns(4)
    sq_q10    = c1.text_input("Q10 factor",              value="2.0",  key=f"q10_{sk}")
    sq_taccel = c2.text_input("Accelerated temp (°C)",   value="60",   key=f"taccel_{sk}")
    sq_treal  = c3.text_input("Real-time temp (°C)",     value="25",   key=f"treal_{sk}")
    sq_time   = c4.text_input("Accelerated duration (e.g. months)", value="26", key=f"time_{sk}")

elif param_type == "shelf_arrhenius":
    c1, c2, c3, c4 = st.columns(4)
    sa_taccel = c1.text_input("Accelerated temp (°C)",       value="60",    key=f"taccel_{sk}")
    sa_treal  = c2.text_input("Real-time temp (°C)",         value="25",    key=f"treal_{sk}")
    sa_ea     = c3.text_input("Activation energy Ea (kJ/mol)", value="83.0", key=f"ea_{sk}")
    sa_time   = c4.text_input("Accelerated duration (e.g. months)", value="26",  key=f"time_{sk}")

elif param_type == "shelf_linear":
    c1, c2, c3 = st.columns(3)
    sl_spec  = c1.text_input("Spec limit",              value="90",   key=f"spec_{sk}")
    sl_conf  = c2.text_input("Confidence (e.g. 0.95)",  value="0.95", key=f"conf_{sk}")
    sl_dir   = c3.selectbox("Direction", ["low (value must stay above spec)", "high (value must stay below spec)"],
                            key=f"dir_{sk}")
    sl_transform = st.selectbox("Transform (optional)", ["none", "log"], key=f"xform_{sk}")

elif param_type == "shelf_extrapolate":
    c1, _ = st.columns([1, 2])
    se_time = c1.text_input("Target time to extrapolate to", value="36", key=f"time_{sk}")

elif param_type == "convert_csv":
    c1, c2, c3 = st.columns(3)
    conv_col   = c1.text_input("Column name or number (1-based)", value="1",
                               help="Column name (if header present) or 1-based column number.",
                               key=f"col_{sk}")
    conv_skip  = c2.number_input("Header lines to skip", min_value=0, value=0, step=1,
                                 help="Lines of metadata at the top of the file before column headers or data.",
                                 key=f"skip_{sk}")
    conv_delim = c3.selectbox("Delimiter", ["auto-detect", "tab", "space", "comma"],
                              key=f"delim_{sk}")

elif param_type == "convert_txt":
    st.caption("Optionally specify a line range to extract (e.g. to skip a stabilisation period).")
    c1, c2 = st.columns(2)
    conv_start = c1.text_input("First line to include (optional)", value="",
                               placeholder="e.g. 50", key=f"start_{sk}")
    conv_end   = c2.text_input("Last line to include (optional)",  value="",
                               placeholder="e.g. 200", key=f"end_{sk}")

# ---------------------------------------------------------------------------
# Report flag (Validation Pack)
# ---------------------------------------------------------------------------

want_report = False
if cfg.get("has_report"):
    st.markdown("---")
    _pack_installed = os.path.isfile(os.path.join(PROJECT_ROOT, "pack", "jr_pack.py"))
    if _pack_installed:
        want_report = st.checkbox(
            "📄  Generate Word report (--report)",
            key=f"report_{sk}",
        )
    else:
        st.checkbox(
            "📄  Generate Word report (--report)",
            value=False, disabled=True,
            key=f"report_{sk}",
        )
        st.caption(
            "Validation Pack not installed — Word reports are unavailable. "
            "Visit [dwylup.com](https://www.dwylup.com) for details."
        )

# ---------------------------------------------------------------------------
# Run button
# ---------------------------------------------------------------------------

st.markdown("---")
run_disabled = needs_file and (data_path is None)

if param_type == "bland_altman":
    run_disabled = (data_path is None) or (data_path2 is None)

if st.button(f"▶  Run {script_choice}", type="primary", disabled=run_disabled):

    if param_type == "curve_cfg":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path]

    elif param_type == "fileonly":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path]

    elif param_type == "corr":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, "--xcol", xcol, "--ycol", ycol]
        if cfg["has_conf"]:
            cmd += ["--conf", str(conf)]

    elif param_type == "bland_altman":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, ba_col1, data_path2, ba_col2]

    elif param_type == "univariate":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, colname]

    elif param_type == "capability":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, colname, lsl, usl]

    elif param_type == "weibull":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, time_col, status_col]

    elif param_type == "spc_limits":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path]
        if ucl_val.strip(): cmd += ["--ucl", ucl_val.strip()]
        if lcl_val.strip(): cmd += ["--lcl", lcl_val.strip()]

    elif param_type == "msa_tolerance":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path]
        if tolerance.strip(): cmd += ["--tolerance", tolerance.strip()]

    elif param_type == "msa_type1":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path,
                             "--reference", reference.strip(),
                             "--tolerance", tolerance.strip()]

    elif param_type == "ss_discrete":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], proportion, confidence]

    elif param_type == "ss_discrete_ci":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], confidence, ss_n, ss_f]

    elif param_type == "ss_power":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], delta, sd, sides.split()[0]]

    elif param_type == "ss_attr":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             proportion, confidence, data_path, colname, lsl, usl]

    elif param_type == "ss_attr_check":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             proportion, confidence, data_path, colname, lsl, usl, planned_n]

    elif param_type == "ss_attr_ci":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             confidence, data_path, colname, lsl, usl]

    elif param_type == "ss_sigma":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], precision, lsl, usl]

    elif param_type == "ss_fatigue":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], reliability, confidence, shape, af]

    elif param_type == "ss_gauge_rr":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], grr, grr_type, sigma_tol]

    elif param_type == "as_design":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], lot_size, aql, rql]
        if alpha.strip(): cmd += ["--alpha", alpha.strip()]
        if beta.strip():  cmd += ["--beta",  beta.strip()]

    elif param_type == "as_variables":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], lot_size, aql, rql,
                             "--sides", sides.split()[0]]
        if alpha.strip(): cmd += ["--alpha", alpha.strip()]
        if beta.strip():  cmd += ["--beta",  beta.strip()]

    elif param_type == "as_oc_curve":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], oc_n, oc_c]
        if oc_lot.strip(): cmd += ["--lot-size", oc_lot.strip()]
        if oc_aql.strip(): cmd += ["--aql",      oc_aql.strip()]
        if oc_rql.strip(): cmd += ["--rql",      oc_rql.strip()]

    elif param_type == "as_evaluate":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, "--type", eval_type]
        if eval_type == "attributes":
            cmd += ["--c", eval_c.strip()]
        else:
            cmd += ["--k", eval_k.strip()]
            if eval_lsl.strip(): cmd += ["--lsl", eval_lsl.strip()]
            if eval_usl.strip(): cmd += ["--usl", eval_usl.strip()]

    elif param_type == "doe_design":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             doe_type, data_path, response_name, DOWNLOADS,
                             centre_pts, replicates]

    elif param_type == "doe_analyse":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, DOWNLOADS]

    elif param_type == "gen_2param":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], gen_n, gen_p1, gen_p2, DOWNLOADS]
        if gen_seed.strip(): cmd += [gen_seed.strip()]

    elif param_type == "rdt_plan":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             "--reliability", rdt_rel.strip(),
                             "--confidence",  rdt_conf.strip(),
                             "--target_life", rdt_tl.strip()]
        if rdt_beta.strip(): cmd += ["--beta",         rdt_beta.strip()]
        if rdt_af.strip():   cmd += ["--accel_factor", rdt_af.strip()]
        if rdt_k.strip():    cmd += ["--k_allowed",    rdt_k.strip()]

    elif param_type == "rdt_verify":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path,
                             "--reliability", rdt_rel.strip(),
                             "--confidence",  rdt_conf.strip(),
                             "--target_life", rdt_tl.strip()]
        if rdt_beta.strip(): cmd += ["--beta", rdt_beta.strip()]

    elif param_type == "verify_discrete":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             vd_n.strip(), vd_f.strip(), vd_prop.strip(), vd_conf.strip()]

    elif param_type == "shelf_q10":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             sq_q10.strip(), sq_taccel.strip(), sq_treal.strip(), sq_time.strip()]

    elif param_type == "shelf_arrhenius":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"],
                             sa_taccel.strip(), sa_treal.strip(), sa_ea.strip(), sa_time.strip()]

    elif param_type == "shelf_linear":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path,
                             sl_spec.strip(), sl_conf.strip(),
                             "--direction", sl_dir.split()[0]]
        if sl_transform != "none":
            cmd += ["--transform", sl_transform]

    elif param_type == "shelf_extrapolate":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, se_time.strip()]

    elif param_type == "convert_csv":
        delim_arg = conv_delim if conv_delim != "auto-detect" else ""
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path, conv_col, str(int(conv_skip))]
        if delim_arg:
            cmd += [delim_arg]

    elif param_type == "convert_txt":
        cmd = BASH_PREFIX + [JRRUN, cfg["script"], data_path]
        if conv_start.strip():
            cmd += [conv_start.strip()]
            if conv_end.strip():
                cmd += [conv_end.strip()]

    if want_report:
        cmd += ["--report"]

    with st.spinner(f"Running {cfg['script']} via jrrun..."):
        result = subprocess.run(
            cmd, capture_output=True, encoding="utf-8", cwd=PROJECT_ROOT,
        )

    # Clean up temp files
    for tp in [tmp_path, tmp_path2]:
        if tp and os.path.exists(tp):
            os.unlink(tp)

    output = (result.stdout or "") + (result.stderr or "")

    if result.returncode == 0:
        st.success("Script completed successfully.")
        st.markdown("### Results")
        st.code(output, language="text")

        # --- Show PNG
        png_shown = False

        # Scripts that save PNG in ~/Downloads with a known pattern
        if cfg.get("png_pattern"):
            pngs = sorted(
                glob.glob(os.path.join(DOWNLOADS, cfg["png_pattern"])),
                key=os.path.getmtime, reverse=True,
            )
            if pngs:
                st.markdown("### Plot")
                st.image(pngs[0], use_container_width=True)
                st.markdown(f"<p style='font-size:1.2rem;color:#555'><code>{os.path.basename(pngs[0])}</code></p>", unsafe_allow_html=True)
                png_shown = True

        # Scripts that save PNG alongside the input file — parse path from output
        if not png_shown and cfg.get("png_from_output"):
            match = re.search(r"saved to:\s+(.+\.png)", output)
            if match:
                png_path = match.group(1).strip()
                if os.path.exists(png_path):
                    st.markdown("### Plot")
                    st.image(png_path, use_container_width=True)
                    st.markdown(f"<p style='font-size:1.2rem;color:#555'><code>{os.path.basename(png_path)}</code></p>", unsafe_allow_html=True)

        # Curve Properties — show PDF plot inline via base64 iframe
        if param_type == "curve_cfg":
            match = re.search(r"Plot file\s*:\s+(.+\.pdf)", output)
            if match:
                pdf_path = match.group(1).strip()
                if os.path.exists(pdf_path):
                    st.markdown("### Plot")
                    with open(pdf_path, "rb") as _pf:
                        pdf_bytes = _pf.read()
                    b64 = base64.b64encode(pdf_bytes).decode()
                    st.markdown(
                        f'<iframe src="data:application/pdf;base64,{b64}" '
                        f'width="100%" height="650px" style="border:none;"></iframe>',
                        unsafe_allow_html=True,
                    )
                    st.download_button(
                        "⬇️  Download PDF",
                        data=pdf_bytes,
                        file_name=os.path.basename(pdf_path),
                        mime="application/pdf",
                    )

    else:
        st.error("Script failed.")
        st.code(output, language="text")

elif run_disabled:
    if param_type == "bland_altman":
        st.warning("Upload or select both CSV files to enable the Run button.")
    elif param_type == "curve_cfg":
        st.warning("Select a sample config file to enable the Run button.")
    elif param_type in ("convert_csv", "convert_txt"):
        st.warning("Upload a file or select sample data to enable the Run button.")
    else:
        st.warning("Upload a CSV file or select sample data to enable the Run button.")
