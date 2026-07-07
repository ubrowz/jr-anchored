"""
clinical_design.py — Clinical Study Design module (Module 1) GUI.

A guided workflow layered over the validated sample-size scripts. This module
is pure orchestration: it collects the design decisions in the order the guide
teaches, resolves them to a script + flags, and dispatches through jrrun. It
computes NOTHING itself — every sample-size figure comes from the validated R
layer (same rule as the web calculators). Dropout inflation and sensitivity are
script features (--dropout / --sensitivity), never GUI arithmetic.

Two entry paths, both first-class:
  • Guided wizard (default) — stepwise, with the guide inlined at each decision.
  • Expert fast-track      — every parameter on one panel, no funnel.

------------------------------------------------------------------------------
SCRIPT CLI CONTRACT  (single source of truth — the R scripts MUST honour this)
------------------------------------------------------------------------------
Three scripts, one per endpoint; framework selected by flag. α and sidedness are
set by the wizard from the framework (superiority → two-sided 0.05; non-
inferiority → one-sided 0.025; equivalence → TOST, two one-sided 0.05) but are
passed explicitly so a run is fully reproducible from its command line.

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
------------------------------------------------------------------------------
"""

import os
import subprocess
import streamlit as st

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
    return cmd


def _dispatch(cmd, script_path, project_root):
    """Run the assembled command, or — until the validated script exists —
    show exactly what will run so the contract is visible and testable."""
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
        st.markdown("### Result")
        st.code(output, language="text")
    else:
        st.error(f"Script failed (exit {result.returncode}).")
        st.code(output, language="text")


def render_clinical_design(*, JRRUN, BASH_PREFIX, PROJECT_ROOT):
    """Entry point called from jr_app.py when the Clinical Design nav page is active."""
    st.markdown("## Clinical Study Design")
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
