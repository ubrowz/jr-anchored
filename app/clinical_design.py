"""
clinical_design.py — Clinical Study Design GUI (Modules 1 and 2).

A guided workflow layered over the validated sample-size scripts. This module
is pure orchestration: it collects the design decisions in the order the guide
teaches, resolves them to a script + flags, and dispatches through jrrun. It
computes NOTHING itself — every sample-size figure comes from the validated R
layer (same rule as the web calculators). Dropout inflation and sensitivity are
script features (--dropout / --sensitivity), never GUI arithmetic.

Two STUDY TYPES, each with its own design vocabulary:

  • Two-arm comparative trial (Module 1) — endpoint × framework. Randomised,
    two arms, an effect size, an allocation ratio.
  • Diagnostic accuracy study (Module 2) — method × sens/spec targets. One
    cohort, no arms and no allocation ratio; the "groups" are the reference-
    positive and reference-negative subjects, and their split is set by the
    prevalence rather than chosen by the designer.

These two do not share a parameter model, so they do not share a code path:
a diagnostic study has no framework, no ratio and no treatment arm, and
forcing it through the two-arm widgets would misrepresent the design. Each
study type has its own _param_inputs / _build_cmd / _headline_metrics.

Within the two-arm type, two entry paths, both first-class:
  • Guided wizard (default) — stepwise, with the guide inlined at each decision.
  • Expert fast-track      — every parameter on one panel, no funnel.

------------------------------------------------------------------------------
SCRIPT CLI CONTRACT  (single source of truth — the R scripts MUST honour this)
------------------------------------------------------------------------------
Two-arm: three scripts, one per endpoint; framework selected by flag. α and
sidedness are set by the wizard from the framework (superiority → two-sided
0.05; non-inferiority → one-sided 0.025; equivalence → TOST, two one-sided
0.05) but are passed explicitly so a run is fully reproducible from its
command line.

  jrc_clinical_ss_means.R
      --framework {superiority|non_inferiority|equivalence}
      --power P --alpha A --sides {1|2}
      --sd SD                       expected SD of the outcome
      --delta D                     meaningful difference   (superiority)
      --margin M                    non-inferiority / equivalence margin
      --ratio R                     allocation treatment:control (default 1)
      [--dropout d]                 fraction lost; script returns enrolled N
      [--sensitivity]              return an n-vs-SD scenario table

  jrc_clinical_ss_props.R
      --framework {superiority|non_inferiority|equivalence}
      --power P --alpha A --sides {1|2}
      --p-control PC                control event rate
      --p-treat PT                  expected treatment rate (superiority)
      --margin M                    NI / equivalence margin (risk difference)
      --ratio R  [--dropout d] [--sensitivity]

  jrc_clinical_ss_survival.R
      --framework {superiority|non_inferiority}
      --power P --alpha A --sides {1|2}
      --hr HR                       target hazard ratio
      --margin M                    NI margin (on HR)         (non_inferiority)
      --event-prob PE               P(event) over follow-up; converts events→N
      --ratio R  [--dropout d] [--sensitivity]

Diagnostic accuracy: one script, method selected by flag. No --framework and
no --ratio — the design has no arms to allocate between.

  jrc_clinical_dx_ss.R
      --method {precision|hypothesis}
      --sens-expected SE            anticipated sensitivity (planning value)
      --spec-expected SP            anticipated specificity (planning value)
      --prevalence P                converts per-arm n → total enrolment
      --halfwidth W                 target CI half-width      (precision)
      --sens-goal G0                sensitivity goal          (hypothesis)
      --spec-goal G1                specificity goal          (hypothesis)
      [--power PW] [--alpha A] [--sides {1|2}]
      [--dropout d] [--sensitivity]
------------------------------------------------------------------------------
"""

import os
import subprocess
import streamlit as st

STUDY_TYPES = ["Two-arm comparative trial", "Diagnostic accuracy study"]

DX_SCRIPT = "jrc_clinical_dx_ss.R"

DX_METHOD_LABELS = {
    "precision":  "Precision — pin sens/spec to a target CI width",
    "hypothesis": "Hypothesis — beat a performance goal with power",
}

# Method → (alpha, sides, human note). The diagnostic counterpart of
# FRAMEWORK_STATS: the GUI makes the α decision, the script does the maths, and
# both are passed explicitly so the printed command reproduces the run exactly.
#
# The script's own CLI defaults are one-sided α = 0.05 for the hypothesis
# method. The GUI deliberately chooses the stricter one-sided α = 0.025 to match
# the convention used for non-inferiority elsewhere on this page, and the way an
# IVD performance claim is normally supported: the lower bound of the two-sided
# 95% CI must clear the goal. Because both flags are always sent, the GUI's
# choice is visible in the reproduce-command rather than hidden in a default.
DX_METHOD_STATS = {
    "precision":  (0.05,  2, "two-sided α = 0.05 — a CI half-width is "
                             "inherently two-sided"),
    "hypothesis": (0.025, 1, "one-sided α = 0.025 — the lower bound of the "
                             "two-sided 95% CI must clear the goal"),
}

# Endpoint → (script filename, allowed frameworks)
ENDPOINTS = {
    "Continuous (means)":      ("jrc_clinical_ss_means.R",
                                ["superiority", "non_inferiority", "equivalence"]),
    "Binary (proportions)":    ("jrc_clinical_ss_props.R",
                                ["superiority", "non_inferiority", "equivalence"]),
    "Time-to-event (survival)": ("jrc_clinical_ss_survival.R",
                                ["superiority", "non_inferiority"]),
}

FRAMEWORK_LABELS = {
    "superiority":     "Superiority — is the device better?",
    "non_inferiority": "Non-inferiority — no worse than by margin M",
    "equivalence":     "Equivalence — the same within ±M",
}

# Framework → (alpha, sides, human note). The wizard's key safeguard: sidedness
# is derived from the framework, removing the guide's #1 pitfall.
FRAMEWORK_STATS = {
    "superiority":     (0.05,  2, "two-sided α = 0.05"),
    "non_inferiority": (0.025, 1, "one-sided α = 0.025"),
    "equivalence":     (0.05,  1, "TOST — two one-sided at α = 0.05"),
}

GUIDE = {
    "endpoint": (
        "**Choose the primary endpoint's data type.** It determines the whole "
        "calculation: a measured value → means; a success/failure → proportions; "
        "a time-until-event → survival. Power the study on exactly one primary "
        "endpoint."
    ),
    "framework": (
        "**Choose the hypothesis framework.** Superiority asks if the device is "
        "*better*; non-inferiority asks if it is *no worse* by more than a margin "
        "M; equivalence asks if it is the *same* within ±M. For devices, "
        "non-inferiority against a predicate is very common. This choice fixes the "
        "significance level and its sidedness automatically."
    ),
    "params": (
        "**Fix the parameters.** Power is usually 0.80–0.90 (pivotal studies "
        "often 0.90). Power for the *clinically meaningful* effect, not the one "
        "you hope for. Treat variability / control rate as uncertain — check the "
        "sensitivity table. Inflate for dropout last."
    ),
    "margin": (
        "The **margin M** is the largest acceptable loss of efficacy. Justify it "
        "on clinical grounds, never to make the study feasible — a margin set for "
        "convenience is the fastest route to a rejected submission."
    ),
}

GUIDE_DX = {
    "method": (
        "**Choose how the study is sized.** *Precision* sizes so the confidence "
        "interval on sensitivity and specificity is no wider than ±W — use it "
        "when the goal is to characterise performance. *Hypothesis* sizes to "
        "demonstrate, with power, that performance exceeds a stated goal — use "
        "it when the submission makes a performance claim."
    ),
    "params": (
        "**Fix the planning values.** Expected sensitivity and specificity are "
        "assumptions, not results — if you are wrong the study is mis-sized, so "
        "check the sensitivity table. Sensitivity is estimated only from "
        "reference-positive subjects and specificity only from reference-"
        "negative ones, so the two arms are sized separately."
    ),
    "prevalence": (
        "**Prevalence is what drives enrolment.** You do not choose the split "
        "between reference-positive and reference-negative subjects — the "
        "population does. At 10% prevalence, collecting ~139 positives means "
        "enrolling ~1383 subjects. This is the single biggest surprise in "
        "diagnostic study planning: a rare condition makes an otherwise modest "
        "study very large."
    ),
}


def _dx_param_inputs(method, key_prefix):
    """Widgets for the diagnostic-accuracy design. No computation here."""
    p = {}
    k = key_prefix
    c1, c2 = st.columns(2)
    p["sens_expected"] = c1.text_input(
        "Expected sensitivity", value="0.90", key=f"{k}_dx_se",
        help="Planning assumption for the anticipated sensitivity.",
    )
    p["spec_expected"] = c2.text_input(
        "Expected specificity", value="0.95", key=f"{k}_dx_sp",
        help="Planning assumption for the anticipated specificity.",
    )

    if method == "precision":
        c3, c4 = st.columns(2)
        p["halfwidth"] = c3.text_input(
            "Target CI half-width (±W)", value="0.05", key=f"{k}_dx_w",
        )
        p["prevalence"] = c4.text_input(
            "Prevalence in the intended-use population", value="0.10",
            key=f"{k}_dx_prev",
        )
    else:
        c3, c4 = st.columns(2)
        p["sens_goal"] = c3.text_input(
            "Sensitivity performance goal", value="0.80", key=f"{k}_dx_g0",
            help="Must be below the expected sensitivity.",
        )
        p["spec_goal"] = c4.text_input(
            "Specificity performance goal", value="0.90", key=f"{k}_dx_g1",
            help="Must be below the expected specificity.",
        )
        c5, c6 = st.columns(2)
        p["power"] = c5.text_input("Power (1 − β)", value="0.80", key=f"{k}_dx_pw")
        p["prevalence"] = c6.text_input(
            "Prevalence in the intended-use population", value="0.10",
            key=f"{k}_dx_prev",
        )

    p["dropout"] = st.text_input(
        "Expected unevaluable fraction (0 = none)", value="0.0",
        key=f"{k}_dx_dropout",
        help="Subjects with no valid reference or index result. The script "
             "inflates the evaluable N to an enrolled N; not computed here.",
    )
    p["sensitivity"] = st.checkbox(
        "Include sensitivity scenario table", key=f"{k}_dx_sens",
        help="The script recomputes total N across a range of prevalence "
             "(0.5x to 2x the assumed value).",
    )
    return p


def _build_dx_cmd(jrrun, bash_prefix, method, params):
    """Assemble the jrrun argument list for jrc_clinical_dx_ss. Pure string
    plumbing — the arithmetic lives in the script. Note there is no
    --framework and no --ratio: a diagnostic study has no arms to allocate.
    α and sidedness come from DX_METHOD_STATS and are always sent explicitly,
    never left to the script's CLI defaults, so the printed command reproduces
    the run exactly."""
    alpha, sides, _ = DX_METHOD_STATS[method]
    cmd = bash_prefix + [
        jrrun, DX_SCRIPT,
        "--method", method,
        "--sens-expected", params["sens_expected"].strip(),
        "--spec-expected", params["spec_expected"].strip(),
        "--alpha", str(alpha),
        "--sides", str(sides),
        "--prevalence", params["prevalence"].strip(),
    ]
    for flag, key in (("--halfwidth", "halfwidth"),
                      ("--sens-goal", "sens_goal"),
                      ("--spec-goal", "spec_goal"),
                      ("--power", "power")):
        if params.get(key) and params[key].strip():
            cmd += [flag, params[key].strip()]
    if params.get("dropout") and params["dropout"].strip() not in ("", "0", "0.0"):
        cmd += ["--dropout", params["dropout"].strip()]
    if params.get("sensitivity"):
        cmd += ["--sensitivity"]
    return cmd


def _dx_headline_metrics(output):
    """Lift the headline figures out of the validated dx report into tiles.
    Pure text extraction — every number is read from the script output."""
    import re

    def grab(label):
        m = re.search(rf"{re.escape(label)}\s*:\s*(\d+)", output)
        return m.group(1) if m else None

    m_enroll = re.search(r"ENROLL (\d+) subjects", output)
    tiles = [(label, val) for label, val in (
        ("n reference +", grab("n reference +")),
        ("n reference −", grab("n reference -")),
        ("N total (evaluable)", grab("N TOTAL")),
        ("Enroll (after dropout)", m_enroll.group(1) if m_enroll else None),
    ) if val is not None]
    if tiles:
        cols = st.columns(len(tiles))
        for col, (label, val) in zip(cols, tiles):
            col.metric(label, val)


def _resolve_script_path(project_root, script_name):
    """Best-effort location of the (future) clinical script, for an existence
    check before dispatch. jrrun resolves the bare name at run time regardless."""
    for cand in (
        os.path.join(project_root, "repos", "clinical", "R", script_name),
        os.path.join(project_root, "R", script_name),
    ):
        if os.path.isfile(cand):
            return cand
    return None


def _param_inputs(endpoint, framework, key_prefix):
    """Render the parameter widgets for the endpoint/framework and return a dict
    of raw string values. No computation happens here."""
    p = {}
    k = key_prefix
    c1, c2 = st.columns(2)
    p["power"] = c1.text_input("Power (1 − β)", value="0.90", key=f"{k}_power")
    p["ratio"] = c2.text_input("Allocation ratio (treatment : control)",
                               value="1", key=f"{k}_ratio")

    if endpoint == "Continuous (means)":
        c3, c4 = st.columns(2)
        p["sd"] = c3.text_input("Expected SD of the outcome", value="1.0", key=f"{k}_sd")
        if framework == "superiority":
            p["delta"] = c4.text_input("Meaningful difference δ", value="0.5", key=f"{k}_delta")
        else:
            p["margin"] = c4.text_input("Margin M", value="0.5", key=f"{k}_margin")

    elif endpoint == "Binary (proportions)":
        c3, c4 = st.columns(2)
        p["p_control"] = c3.text_input("Control event rate", value="0.70", key=f"{k}_pc")
        if framework == "superiority":
            p["p_treat"] = c4.text_input("Expected treatment rate", value="0.85", key=f"{k}_pt")
        else:
            p["margin"] = c4.text_input("Margin M (risk difference)", value="0.10", key=f"{k}_margin")

    elif endpoint == "Time-to-event (survival)":
        c3, c4 = st.columns(2)
        p["hr"] = c3.text_input("Target hazard ratio (HR)", value="0.75", key=f"{k}_hr")
        p["event_prob"] = c4.text_input("P(event) over follow-up", value="0.50", key=f"{k}_pe")
        if framework == "non_inferiority":
            p["margin"] = st.text_input("NI margin M (on HR)", value="1.30", key=f"{k}_margin")

    p["dropout"] = st.text_input(
        "Expected dropout fraction (0 = none)", value="0.0", key=f"{k}_dropout",
        help="The script inflates the analysable N to an enrolled N; not computed here.",
    )
    p["sensitivity"] = st.checkbox(
        "Include sensitivity scenario table", key=f"{k}_sens",
        help="The script recomputes n across a ±20% range of the most "
             "uncertain assumption (SD / control rate / event probability).",
    )
    return p


def _build_cmd(jrrun, bash_prefix, script_name, framework, params):
    """Assemble the jrrun argument list from the collected parameters. Pure
    string plumbing — the arithmetic lives in the script."""
    alpha, sides, _ = FRAMEWORK_STATS[framework]
    cmd = bash_prefix + [
        jrrun, script_name,
        "--framework", framework,
        "--power", params["power"].strip(),
        "--alpha", str(alpha),
        "--sides", str(sides),
        "--ratio", params["ratio"].strip(),
    ]
    for flag, key in (("--sd", "sd"), ("--delta", "delta"), ("--margin", "margin"),
                      ("--p-control", "p_control"), ("--p-treat", "p_treat"),
                      ("--hr", "hr"), ("--event-prob", "event_prob")):
        if params.get(key) and params[key].strip():
            cmd += [flag, params[key].strip()]
    if params.get("dropout") and params["dropout"].strip() not in ("", "0", "0.0"):
        cmd += ["--dropout", params["dropout"].strip()]
    if params.get("sensitivity"):
        cmd += ["--sensitivity"]
    return cmd


def _dispatch(cmd, script_path, project_root, metrics_fn=None):
    """Run the assembled command, or — until the validated script exists —
    show exactly what will run so the contract is visible and testable.

    metrics_fn renders the headline tiles for whichever study type produced
    the report; defaults to the two-arm reader."""
    if script_path is None:
        st.info(
            "🚧 **Validated script in development (Phase 1).** The Clinical Study "
            "Design calculators are being built. This is the exact command the GUI "
            "will run through `jrrun` once the script lands — the design you entered "
            "already resolves to a reproducible invocation:"
        )
        st.code(" ".join(cmd), language="bash")
        return
    with st.spinner(f"Running {os.path.basename(script_path)} via jrrun…"):
        result = subprocess.run(cmd, capture_output=True, encoding="utf-8", cwd=project_root)
    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode == 0:
        st.success("Sample size computed.")
        (metrics_fn or _headline_metrics)(output)
        st.markdown("### Full report")
        st.code(output, language="text")
        with st.expander("Reproduce this result from the command line"):
            st.code(" ".join(cmd), language="bash")
        st.caption(
            "Computed by the validated R layer through jrrun — nothing is "
            "calculated in this interface."
        )
    else:
        st.error(f"Script failed (exit {result.returncode}).")
        st.code(output, language="text")


def _headline_metrics(output):
    """Lift the headline figures out of the validated report into metric tiles.
    Pure text extraction — every number is read from the script output,
    never recomputed here."""
    import re

    def grab(label):
        m = re.search(rf"{re.escape(label)}\s*:\s*(\d+)", output)
        return m.group(1) if m else None

    n_t, n_c, n_tot = grab("n treatment"), grab("n control"), grab("n TOTAL")
    events = grab("Events required")
    m_enroll = re.search(r"ENROLL \d+ \+ \d+ = (\d+)", output)

    tiles = [(label, val) for label, val in (
        ("n treatment", n_t),
        ("n control", n_c),
        ("n total (evaluable)", n_tot),
        ("Events required", events),
        ("Enroll (after dropout)", m_enroll.group(1) if m_enroll else None),
    ) if val is not None]
    if tiles:
        cols = st.columns(len(tiles))
        for col, (label, val) in zip(cols, tiles):
            col.metric(label, val)


def _render_dx_ss(*, JRRUN, BASH_PREFIX, PROJECT_ROOT):
    """Diagnostic accuracy study design (Module 2). Separate from the two-arm
    path: no framework, no allocation ratio, no treatment arm."""
    st.caption(
        "Plan the enrolment for a diagnostic accuracy study. Parameters only — "
        "no data file; this is design, before any subject is enrolled."
    )

    # ---- Step 1: method ---------------------------------------------------
    st.markdown("#### Step 1 · Sizing method")
    with st.expander("What is this?"):
        st.caption(GUIDE_DX["method"])
    method = st.radio(
        "Method", list(DX_METHOD_LABELS.keys()),
        format_func=lambda m: DX_METHOD_LABELS[m], key="dx_method",
    )
    _, _, dx_note = DX_METHOD_STATS[method]
    st.caption(f"Significance level set automatically: **{dx_note}**.")

    # ---- Step 2: parameters -----------------------------------------------
    st.markdown("#### Step 2 · Planning values")
    with st.expander("What is this?"):
        st.caption(GUIDE_DX["params"])
        st.caption(GUIDE_DX["prevalence"])
    params = _dx_param_inputs(method, "dx")

    # ---- Step 3: compute --------------------------------------------------
    st.markdown("#### Step 3 · Compute")
    if st.button("▶  Compute enrolment", type="primary", key="dx_run"):
        cmd = _build_dx_cmd(JRRUN, BASH_PREFIX, method, params)
        _dispatch(cmd, _resolve_script_path(PROJECT_ROOT, DX_SCRIPT),
                  PROJECT_ROOT, metrics_fn=_dx_headline_metrics)


def render_clinical_design(*, JRRUN, BASH_PREFIX, PROJECT_ROOT):
    """Entry point called from jr_app.py when the Clinical Design nav page is active."""
    st.markdown("## Clinical Study Design")

    study_type = st.radio(
        "Study type", STUDY_TYPES, horizontal=True, key="study_type",
        help="A two-arm trial compares treatments; a diagnostic accuracy "
             "study characterises a test against a reference standard. They "
             "have different parameters, so they are sized differently.",
    )
    st.markdown("---")

    if study_type == "Diagnostic accuracy study":
        _render_dx_ss(JRRUN=JRRUN, BASH_PREFIX=BASH_PREFIX,
                      PROJECT_ROOT=PROJECT_ROOT)
        return

    st.caption(
        "Plan the sample size for a two-arm clinical investigation. Parameters "
        "only — no data file; this is design, before any subject is enrolled."
    )

    mode = st.radio(
        "Mode", ["Guided workflow", "Expert (all parameters)"],
        horizontal=True, label_visibility="collapsed",
    )
    st.markdown("---")

    if mode.startswith("Guided"):
        # ---- Step 1: endpoint -------------------------------------------------
        st.markdown("#### Step 1 · Primary endpoint")
        with st.expander("What is this?"):
            st.caption(GUIDE["endpoint"])
        endpoint = st.radio("Endpoint type", list(ENDPOINTS.keys()), key="g_endpoint")
        script_name, frameworks = ENDPOINTS[endpoint]

        # ---- Step 2: framework -----------------------------------------------
        st.markdown("#### Step 2 · Hypothesis framework")
        with st.expander("What is this?"):
            st.caption(GUIDE["framework"])
        framework = st.radio(
            "Framework", frameworks,
            format_func=lambda f: FRAMEWORK_LABELS[f], key="g_framework",
        )
        _, _, note = FRAMEWORK_STATS[framework]
        st.caption(f"Significance level set automatically: **{note}**.")

        # ---- Step 3: parameters ----------------------------------------------
        st.markdown("#### Step 3 · Parameters")
        with st.expander("What is this?"):
            st.caption(GUIDE["params"])
            if framework in ("non_inferiority", "equivalence"):
                st.caption(GUIDE["margin"])
        params = _param_inputs(endpoint, framework, "g")

        # ---- Step 4: compute -------------------------------------------------
        st.markdown("#### Step 4 · Compute")
        if st.button("▶  Compute sample size", type="primary", key="g_run"):
            cmd = _build_cmd(JRRUN, BASH_PREFIX, script_name, framework, params)
            _dispatch(cmd, _resolve_script_path(PROJECT_ROOT, script_name), PROJECT_ROOT)

    else:
        # ---- Expert fast-track: everything on one panel ----------------------
        st.markdown("#### Expert fast-track")
        st.caption("Every parameter on one panel — no funnel.")
        c1, c2 = st.columns(2)
        endpoint = c1.selectbox("Endpoint", list(ENDPOINTS.keys()), key="x_endpoint")
        script_name, frameworks = ENDPOINTS[endpoint]
        framework = c2.selectbox(
            "Framework", frameworks,
            format_func=lambda f: FRAMEWORK_LABELS[f], key="x_framework",
        )
        _, _, note = FRAMEWORK_STATS[framework]
        st.caption(f"α / sidedness: **{note}** (from framework).")
        params = _param_inputs(endpoint, framework, "x")
        if st.button("▶  Compute sample size", type="primary", key="x_run"):
            cmd = _build_cmd(JRRUN, BASH_PREFIX, script_name, framework, params)
            _dispatch(cmd, _resolve_script_path(PROJECT_ROOT, script_name), PROJECT_ROOT)
