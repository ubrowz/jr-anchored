"""
JR Anchored — Graphical Interface (Proof of Concept)

A Streamlit UI that calls validated JR scripts via jrrun.
The GUI is a convenience layer — all scripts run through the same
integrity-checked, validated path as the CLI.

Launch:  streamlit run app/jr_app.py
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

import streamlit as st

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

APP_DIR      = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(APP_DIR)
JRRUN        = os.path.join(PROJECT_ROOT, "bin", "jrrun")
DOWNLOADS    = os.path.expanduser("~/Downloads")

SPC_DATA  = os.path.join(PROJECT_ROOT, "repos", "spc",  "oq", "data")
MSA_DATA  = os.path.join(PROJECT_ROOT, "repos", "msa",  "oq", "data")
AS_DATA   = os.path.join(PROJECT_ROOT, "repos", "as",   "oq", "data")
CORR_DATA = os.path.join(PROJECT_ROOT, "repos", "corr", "oq", "data")
COMM_DATA = os.path.join(PROJECT_ROOT, "oq", "data")

BASH_PREFIX = ["bash"] if sys.platform == "win32" else []

# ---------------------------------------------------------------------------
# Script catalogue
# ---------------------------------------------------------------------------
# param_type controls which parameter widgets are shown.
# needs_file=False → skip the data upload section; Run button is always enabled.
# png_pattern  → glob in ~/Downloads for the most-recent matching PNG.
# png_from_output → parse "saved to: <path>" from terminal output instead.

CATALOGUE = {

    # -----------------------------------------------------------------------
    "Correlation": {
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
        "Linear Regression": {
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
        "Bland-Altman Analysis": {
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
    },

    # -----------------------------------------------------------------------
    "Statistics": {
        "Descriptive Statistics": {
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
        "Normality Tests": {
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
        "Outlier Detection": {
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
        "Capability Analysis": {
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
        "Weibull Analysis": {
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
    },

    # -----------------------------------------------------------------------
    "Sample Size": {
        "Discrete Pass/Fail": {
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
        "Discrete — Achieved CI": {
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
        "Continuous — Paired Test": {
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
        "Continuous — Equivalence": {
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
        "Continuous — Tolerance Interval": {
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
        "Continuous — Check Planned N": {
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
        "Continuous — Achieved CI": {
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
        "Verify Continuous Result": {
            "script": "jrc_verify_attr.R",
            "description": (
                "Statistical tolerance interval verification for continuous data. "
                "Tests whether the dataset establishes that at least `proportion` of the "
                "population lies within the specification at the stated confidence. "
                "Saves a histogram to the input file directory."
            ),
            "param_type": "ss_attr",
            "sample_data_dir": COMM_DATA,
            "sample_prefix": "normal_",
            "png_pattern": None,
            "png_from_output": True,
        },
        "Sigma Estimation": {
            "script": "jrc_ss_sigma.R",
            "description": (
                "Minimum number of pilot samples needed to estimate the process standard "
                "deviation with sufficient precision before a tolerance interval study."
            ),
            "param_type": "ss_sigma",
            "sample_data_dir": None,
            "png_pattern": None,
        },
        "Fatigue / Lifetime": {
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
        "Gauge R&R Study Design": {
            "script": "jrc_ss_gauge_rr.R",
            "description": (
                "Gauge R&R study design guidance. Given a target %GRR and the process "
                "tolerance or standard deviation, reports the required gauge precision "
                "and number of distinct categories (ndc)."
            ),
            "param_type": "ss_gauge_rr",
            "sample_data_dir": None,
            "png_pattern": None,
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
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "xbar_s_stable",
            "png_pattern": "*_jrc_spc_xbar_s.png",
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
        "P-chart": {
            "script": "jrc_spc_p.R",
            "description": (
                "P-chart for proportion nonconforming. Supports variable subgroup sizes. "
                "Applies all 8 Western Electric rules via standardised values. "
                "Saves a single-panel PNG to `~/Downloads/`."
            ),
            "param_type": "fileonly",
            "sample_data_dir": SPC_DATA,
            "sample_prefix": "p_stable",
            "png_pattern": "*_jrc_spc_p.png",
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
            "sample_data_dir": MSA_DATA,
            "sample_prefix": "gauge_rr_balanced",
            "png_pattern": "*_jrc_msa_gauge_rr.png",
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
    "Acceptance Sampling": {
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
    "Data Generators": {
        "Normal Distribution": {
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
        "Log-Normal Distribution": {
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
        "Uniform Distribution": {
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
        "Right-Skewed (sqrt)": {
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
        "Right-Skewed (Box-Cox)": {
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
    },
}

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------

st.set_page_config(
    page_title="JR Anchored",
    page_icon="⚓",
    layout="wide",
)

# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------

st.sidebar.title("⚓ JR Anchored")
st.sidebar.caption("Validated R & Python analytics")
st.sidebar.markdown("---")

module_choice = st.sidebar.selectbox("Module", list(CATALOGUE.keys()))
scripts_in_module = CATALOGUE[module_choice]
script_choice = st.sidebar.selectbox("Script", list(scripts_in_module.keys()))
cfg = scripts_in_module[script_choice]
param_type = cfg["param_type"]

NO_FILE_TYPES = {
    "as_design", "as_variables", "as_oc_curve",
    "ss_discrete", "ss_discrete_ci", "ss_power",
    "ss_sigma", "ss_fatigue", "ss_gauge_rr",
    "gen_2param",
}
needs_file = param_type not in NO_FILE_TYPES

st.sidebar.markdown("---")
st.sidebar.markdown(
    "<small style='color:#888'>GUI is outside the validated boundary.<br>"
    "Scripts run through <code>jrrun</code> with full integrity checking.</small>",
    unsafe_allow_html=True,
)
st.sidebar.markdown("---")
if st.sidebar.button("⏹  Stop JR App", use_container_width=True):
    os._exit(0)
st.sidebar.caption(
    "After stopping, close the browser tab. "
    "If a \"Connection Error\" pop-up appears, ignore it "
    "and close the tab.\n\n"
    "Closing the tab without stopping leaves the server running — "
    "press Ctrl+C in the terminal to stop it."
)

# ---------------------------------------------------------------------------
# Main panel
# ---------------------------------------------------------------------------

st.title(script_choice)
st.markdown(f"<p style='font-size:1.2rem;color:#555;margin-top:-12px'>Script: <code>{cfg['script']}</code></p>", unsafe_allow_html=True)
st.markdown(cfg["description"])

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
            t = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            t.write(up1.getvalue()); t.close()
            data_path = t.name; tmp_path = t.name
        elif sc1 != "(none)":
            data_path = os.path.join(sdir, sc1)

        if up2:
            t = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            t.write(up2.getvalue()); t.close()
            data_path2 = t.name; tmp_path2 = t.name
        elif sc2 != "(none)":
            data_path2 = os.path.join(sdir, sc2)

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
            sample_choice_val = st.selectbox(
                "Or use sample data", sample_names,
                key=f"sample_{module_choice}_{script_choice}",
            )

        if uploaded_file is not None:
            tmp = tempfile.NamedTemporaryFile(
                delete=False, suffix=".csv", dir=tempfile.gettempdir()
            )
            tmp.write(uploaded_file.getvalue()); tmp.close()
            data_path = tmp.name; tmp_path = tmp.name
            st.success(f"Using uploaded file: **{uploaded_file.name}**")
        elif sample_choice_val != "(none)":
            data_path = os.path.join(sample_dir, sample_choice_val)
            st.info(f"Using sample data: **{sample_choice_val}**")

    # Preview
    preview_path = data_path
    if preview_path:
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

if param_type == "fileonly":
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

# ---------------------------------------------------------------------------
# Run button
# ---------------------------------------------------------------------------

st.markdown("---")
run_disabled = needs_file and (data_path is None)

if param_type == "bland_altman":
    run_disabled = (data_path is None) or (data_path2 is None)

if st.button(f"▶  Run {script_choice}", type="primary", disabled=run_disabled):

    if param_type == "fileonly":
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

    else:
        st.error("Script failed.")
        st.code(output, language="text")

elif run_disabled:
    if param_type == "bland_altman":
        st.warning("Upload or select both CSV files to enable the Run button.")
    else:
        st.warning("Upload a CSV file or select sample data to enable the Run button.")
