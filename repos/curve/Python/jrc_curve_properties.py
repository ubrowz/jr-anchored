#!/usr/bin/env python3
"""
jrc_curve_properties — Extract engineering properties from an XY measurement curve.

Config-file driven. Single CLI argument: path to .cfg file.
Usage: jrrun jrc_curve_properties.py path/to/config.cfg
       jrrun jrc_curve_properties.py --help

Author: Joep Rous
Version: 1.0
"""

import sys
import os
import configparser
import csv as csvmod

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.signal import savgol_filter


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

def die(msg):
    print(msg)
    sys.exit(1)


_warnings = []


def warn(msg):
    print(msg)
    _warnings.append(msg)


def resolve_path(cfg_dir, p):
    if os.path.isabs(p):
        return p
    return os.path.normpath(os.path.join(cfg_dir, p))


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def parse_config(cfg_path):
    cfg = configparser.ConfigParser(inline_comment_prefixes=("#",),
                                    strict=False)   # duplicates handled in validate_config
    cfg.optionxform = str          # preserve key case
    cfg.read(cfg_path, encoding="utf-8")
    return cfg


# ---------------------------------------------------------------------------
# Config validation
# ---------------------------------------------------------------------------

def validate_config(cfg, cfg_path):
    """Pre-flight check of the config file.

    Collects all errors and warnings in one pass so the user can fix
    everything in a single edit cycle. Exits if any errors are found.
    Prints nothing when the config is clean.
    """
    import re

    KNOWN_SECTIONS  = {"data", "output", "smoothing", "global",
                       "slope", "query", "transform", "debug", "transitions"}
    VALID_METHODS   = {"savgol", "moving_avg", "none"}
    VALID_DELIMITERS = {"comma", "tab", "semicolon", "whitespace", "auto"}
    VALID_SEARCH    = {"ascending", "descending", ""}
    VALID_MODES     = {"first", "last", "all"}

    errors   = []
    warnings = []

    def err(msg):  errors.append(f"  ❌ {msg}")
    def warn(msg): warnings.append(f"  ⚠️  {msg}")

    def check_numeric(val, context):
        try:
            float(val)
        except (ValueError, TypeError):
            err(f"{context} must be a number, got: '{val}'")

    def check_phase_ref(name, context):
        if name and name not in known_phases:
            warn(f"{context} references phase '{name}' which is not defined")

    def unknown_keys(section_name, sec_dict, known):
        for k in sec_dict:
            if k not in known:
                err(f"Unknown key '{k}' in [{section_name}] — "
                    f"check spelling (modifier keys use dots, e.g. secant.x1)")

    # Step 0 — scan raw file for duplicate sections and duplicate keys
    sec_counts = {}
    key_counts  = {}   # {section: {key: count}}
    cur_sec = None
    with open(cfg_path, encoding="utf-8") as _f:
        for _line in _f:
            _line = _line.strip()
            if not _line or _line.startswith("#") or _line.startswith(";"):
                continue
            if _line.startswith("[") and "]" in _line:
                cur_sec = _line[1:_line.index("]")].strip()
                sec_counts[cur_sec] = sec_counts.get(cur_sec, 0) + 1
                if sec_counts[cur_sec] == 2:
                    err(f"Duplicate section [{cur_sec}] — each section must appear only once")
                if cur_sec not in key_counts:
                    key_counts[cur_sec] = {}
            elif "=" in _line and cur_sec is not None:
                _key = _line.split("=", 1)[0].strip()
                if _key:
                    key_counts[cur_sec][_key] = key_counts[cur_sec].get(_key, 0) + 1
                    if key_counts[cur_sec][_key] == 2:
                        err(f"Duplicate key '{_key}' in [{cur_sec}] — "
                            f"each key must appear only once in a section")

    # Step 1 — collect defined phase names
    known_phases = set()
    for s in cfg.sections():
        if s.startswith("phase."):
            known_phases.add(s[len("phase."):])

    # Step 2 — unknown sections
    for s in cfg.sections():
        if not s.startswith("phase.") and s not in KNOWN_SECTIONS:
            err(f"Unknown section [{s}] — check spelling")

    # Step 3 — [data] (required)
    if not cfg.has_section("data"):
        err("Missing required section [data]")
    else:
        sec = dict(cfg["data"])
        for req in ("file", "x_col", "y_col"):
            if req not in sec:
                err(f"[data] missing required key: {req}")
        delim = sec.get("delimiter", "auto").strip().lower()
        if delim not in VALID_DELIMITERS:
            err(f"[data] delimiter '{delim}' not recognised — "
                f"use: {', '.join(sorted(VALID_DELIMITERS))}")
        unknown_keys("data", sec, {"file", "x_col", "y_col", "delimiter"})

    # Step 4 — [phase.NAME] sections
    PHASE_KNOWN = {"x_start", "x_end", "after_phase", "search",
                   "smooth_method", "smooth_span",
                   "max_y", "min_y", "max_x", "min_x", "auc"}
    seen_phases = []
    for s in cfg.sections():
        if not s.startswith("phase."):
            continue
        name = s[len("phase."):]
        sec  = dict(cfg[s])
        for req in ("x_start", "x_end"):
            if req not in sec:
                err(f"[{s}] missing required key: {req}")
            else:
                check_numeric(sec[req], f"[{s}] {req}")
        ap = sec.get("after_phase", "").strip()
        if ap and ap not in seen_phases:
            err(f"[{s}] after_phase = '{ap}' not yet defined — "
                f"declare [{s}] after [phase.{ap}] in the config")
        srch = sec.get("search", "").strip().lower()
        if srch not in VALID_SEARCH:
            err(f"[{s}] search = '{srch}' not recognised — "
                f"use: ascending, descending, or omit")
        sm = sec.get("smooth_method", "").strip().lower()
        if sm and sm not in VALID_METHODS:
            warn(f"[{s}] smooth_method = '{sm}' not recognised — "
                 f"use: {', '.join(sorted(VALID_METHODS))}")
        ss = sec.get("smooth_span", "").strip()
        if ss:
            check_numeric(ss, f"[{s}] smooth_span")
        unknown_keys(s, sec, PHASE_KNOWN)
        seen_phases.append(name)

    # Step 5 — [smoothing]
    if cfg.has_section("smoothing"):
        sec = dict(cfg["smoothing"])
        m = sec.get("method", "").strip().lower()
        if m and m not in VALID_METHODS:
            warn(f"[smoothing] method = '{m}' not recognised — "
                 f"use: {', '.join(sorted(VALID_METHODS))}")
        sp = sec.get("span", "").strip()
        if sp:
            check_numeric(sp, "[smoothing] span")
        unknown_keys("smoothing", sec, {"method", "span", "apply_to_plot"})

    # Step 6 — [global]
    if cfg.has_section("global"):
        sec = dict(cfg["global"])
        check_phase_ref(sec.get("auc.phase", "").strip(), "[global] auc.phase")
        check_phase_ref(sec.get("hysteresis_loading.phase",  "").strip(),
                        "[global] hysteresis_loading.phase")
        check_phase_ref(sec.get("hysteresis_unloading.phase", "").strip(),
                        "[global] hysteresis_unloading.phase")
        unknown_keys("global", sec,
                     {"max_y", "min_y", "max_x", "min_x",
                      "auc", "auc.phase",
                      "hysteresis", "hysteresis_loading.phase",
                      "hysteresis_unloading.phase"})

    # Step 7 — [slope]
    AT_X      = re.compile(r"^at_x_\d+$")
    AT_X_MOD  = re.compile(r"^at_x_\d+\.(phase|plot)$")
    SLOPE_KNOWN = {"overall", "overall.phase", "overall.plot",
                   "secant", "secant.phase", "secant.x1", "secant.x2", "secant.plot"}
    if cfg.has_section("slope"):
        sec = dict(cfg["slope"])
        check_phase_ref(sec.get("overall.phase", "").strip(), "[slope] overall.phase")
        check_phase_ref(sec.get("secant.phase",  "").strip(), "[slope] secant.phase")
        if sec.get("secant", "").lower() == "yes":
            if "secant.x1" not in sec:
                warn("[slope] secant = yes but secant.x1 is missing")
            if "secant.x2" not in sec:
                warn("[slope] secant = yes but secant.x2 is missing")
        for k in ("secant.x1", "secant.x2"):
            if k in sec:
                check_numeric(sec[k], f"[slope] {k}")
        for k, v in sec.items():
            if AT_X.match(k):
                check_numeric(v, f"[slope] {k}")
            elif AT_X_MOD.match(k):
                if k.endswith(".phase"):
                    check_phase_ref(v.strip(), f"[slope] {k}")
            elif k not in SLOPE_KNOWN:
                err(f"Unknown key '{k}' in [slope] — "
                    f"check spelling (modifier keys use dots, e.g. secant.x1)")

    # Step 8 — [query]
    Y_AT_X     = re.compile(r"^y_at_x_\d+$")
    Y_AT_X_MOD = re.compile(r"^y_at_x_\d+\.(phase|show)$")
    X_AT_Y     = re.compile(r"^x_at_y_\d+$")
    X_AT_Y_MOD = re.compile(r"^x_at_y_\d+\.(phase|mode)$")
    Y_REL      = re.compile(r"^y_at_rel_x_\d+$")
    Y_REL_MOD  = re.compile(r"^y_at_rel_x_\d+\.(phase|show|frac)$")
    if cfg.has_section("query"):
        sec = dict(cfg["query"])
        for k, v in sec.items():
            if Y_AT_X.match(k):
                check_numeric(v, f"[query] {k}")
            elif Y_AT_X_MOD.match(k):
                if k.endswith(".phase"):
                    check_phase_ref(v.strip(), f"[query] {k}")
            elif X_AT_Y.match(k):
                check_numeric(v, f"[query] {k}")
            elif X_AT_Y_MOD.match(k):
                if k.endswith(".phase"):
                    check_phase_ref(v.strip(), f"[query] {k}")
                elif k.endswith(".mode") and v.strip().lower() not in VALID_MODES:
                    err(f"[query] {k} = '{v.strip()}' not recognised — "
                        f"use: {', '.join(sorted(VALID_MODES))}")
            elif Y_REL.match(k):
                check_numeric(v, f"[query] {k}")
            elif Y_REL_MOD.match(k):
                if k.endswith(".phase"):
                    check_phase_ref(v.strip(), f"[query] {k}")
                elif k.endswith(".frac"):
                    check_numeric(v, f"[query] {k}")
            else:
                err(f"Unknown key '{k}' in [query] — check spelling")

    # Step 9 — [transform]
    if cfg.has_section("transform"):
        sec = dict(cfg["transform"])
        if "y_scale" in sec:
            check_numeric(sec["y_scale"], "[transform] y_scale")
        if "y_offset_x" in sec:
            check_numeric(sec["y_offset_x"], "[transform] y_offset_x")
        unknown_keys("transform", sec, {"y_scale", "y_offset_x"})

    # Step 10 — [debug]
    if cfg.has_section("debug"):
        sec = dict(cfg["debug"])
        if sec.get("d2y", "").lower() == "yes":
            ph = sec.get("d2y.phase", "").strip()
            if not ph:
                err("[debug] d2y = yes requires d2y.phase to be set")
            else:
                check_phase_ref(ph, "[debug] d2y.phase")
        unknown_keys("debug", sec, {"d2y", "d2y.phase"})

    # Step 11 — [transitions]
    INF_N      = re.compile(r"^inflections_\d+$")
    INF_N_MOD  = re.compile(r"^inflections_\d+\.(phase|plot_slope|min_gap)$")
    YIELD_N    = re.compile(r"^yield_\d+\.(slope|phase|show)$")
    TRANS_KNOWN = {"inflections", "inflections.phase", "inflections.plot_slope",
                   "inflections.min_gap",
                   "yield.slope", "yield.phase", "yield.show"}
    if cfg.has_section("transitions"):
        sec = dict(cfg["transitions"])
        for k in ("inflections.min_gap", "yield.slope"):
            if k in sec:
                check_numeric(sec[k], f"[transitions] {k}")
        check_phase_ref(sec.get("inflections.phase", "").strip(),
                        "[transitions] inflections.phase")
        check_phase_ref(sec.get("yield.phase", "").strip(),
                        "[transitions] yield.phase")
        for k, v in sec.items():
            if INF_N.match(k):
                pass  # bare inflections_N flag — value not constrained
            elif INF_N_MOD.match(k):
                if k.endswith(".phase"):
                    check_phase_ref(v.strip(), f"[transitions] {k}")
                elif k.endswith(".min_gap"):
                    check_numeric(v, f"[transitions] {k}")
            elif YIELD_N.match(k):
                suffix_part = k.split(".", 1)[1]
                if suffix_part == "slope":
                    check_numeric(v, f"[transitions] {k}")
                elif suffix_part == "phase":
                    check_phase_ref(v.strip(), f"[transitions] {k}")
            elif k not in TRANS_KNOWN:
                err(f"Unknown key '{k}' in [transitions] — check spelling")

    # Step 12 — [output]
    if cfg.has_section("output"):
        sec = dict(cfg["output"])
        unknown_keys("output", sec,
                     {"label_x", "label_y", "title", "plot",
                      "plot_file", "results_file"})

    # Report
    if warnings:
        print(f"\n⚠️  Config warnings ({len(warnings)}):")
        for w in warnings:
            print(w)

    if errors:
        print(f"\n❌ Config has {len(errors)} error(s) — fix before running:")
        for e in errors:
            print(e)
        print()
        sys.exit(1)


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_data(cfg, cfg_dir):
    if not cfg.has_section("data"):
        die("❌ Config is missing required [data] section.")

    sec = dict(cfg["data"])
    for key in ("file", "x_col", "y_col"):
        if key not in sec:
            die(f"❌ [data] section is missing required key: {key}")

    csv_path = resolve_path(cfg_dir, sec["file"])
    if not os.path.isfile(csv_path):
        die(f"❌ Data file not found: {csv_path}")

    x_col = sec["x_col"]
    y_col = sec["y_col"]
    delim_key = sec.get("delimiter", "auto").strip().lower()

    x_vals, y_vals = [], []
    with open(csv_path, newline="", encoding="utf-8") as f:
        raw = f.read()

    lines = raw.splitlines()
    if not lines:
        die(f"❌ Data file is empty: {csv_path}")

    # Resolve delimiter
    if delim_key == "whitespace":
        # Split each line on any whitespace run; handle as list-of-lists
        def split_line(line):
            return line.strip().split()
        headers = split_line(lines[0])
        if x_col not in headers:
            die(f"❌ X column '{x_col}' not found. Available: {headers}")
        if y_col not in headers:
            die(f"❌ Y column '{y_col}' not found. Available: {headers}")
        xi = headers.index(x_col)
        yi = headers.index(y_col)
        for i, line in enumerate(lines[1:], start=2):
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            try:
                x_vals.append(float(parts[xi]))
                y_vals.append(float(parts[yi]))
            except (ValueError, IndexError):
                warn(f"⚠️  Row {i}: could not parse '{x_col}' or '{y_col}' — skipped")
    else:
        # csv.DictReader path — resolve delimiter character
        if delim_key == "comma":
            delim_char = ","
        elif delim_key == "tab":
            delim_char = "\t"
        elif delim_key == "semicolon":
            delim_char = ";"
        elif delim_key == "auto":
            try:
                sample = "\n".join(lines[:min(10, len(lines))])
                delim_char = csvmod.Sniffer().sniff(sample, delimiters=",\t;|").delimiter
            except csvmod.Error:
                delim_char = ","   # fall back to comma
        else:
            die(f"❌ [data] delimiter '{delim_key}' not recognised. "
                f"Use: comma, tab, semicolon, whitespace, or auto.")

        import io
        reader = csvmod.DictReader(io.StringIO(raw), delimiter=delim_char)
        headers = reader.fieldnames or []
        if x_col not in headers:
            die(f"❌ X column '{x_col}' not found. Available: {list(headers)}")
        if y_col not in headers:
            die(f"❌ Y column '{y_col}' not found. Available: {list(headers)}")
        for i, row in enumerate(reader, start=2):
            try:
                x_vals.append(float(row[x_col]))
                y_vals.append(float(row[y_col]))
            except (ValueError, TypeError):
                warn(f"⚠️  Row {i}: non-numeric in '{x_col}' or '{y_col}' — skipped")

    delim_display = {"comma": "','", "tab": "tab", "semicolon": "';'",
                     "whitespace": "whitespace", "auto": "auto"}.get(delim_key, delim_key)
    print(f"   Delimiter    : {delim_display}")

    if len(x_vals) < 5:
        die(f"❌ Too few valid data rows ({len(x_vals)}). Minimum is 5.")

    return np.array(x_vals, dtype=float), np.array(y_vals, dtype=float)


# ---------------------------------------------------------------------------
# Phase extraction
# ---------------------------------------------------------------------------

def extract_phases(cfg, x, y):
    """
    Return ordered dict {name: (x_arr, y_arr, (i_start, i_end))}.
    Section [phase.NAME] → phase name is NAME.
    x_start matched as closest point in full series.
    x_end matched as closest point at or after i_start.
    """
    phases = {}

    for section in cfg.sections():
        if not section.startswith("phase."):
            continue
        name = section[len("phase."):]

        sec = dict(cfg[section])
        for key in ("x_start", "x_end"):
            if key not in sec:
                die(f"❌ [{section}] is missing required key: {key}")

        try:
            x_start = float(sec["x_start"])
            x_end   = float(sec["x_end"])
        except ValueError:
            die(f"❌ [{section}]: x_start and x_end must be numeric.")

        # after_phase: restrict x_start search to rows after a previously defined phase
        after_ph = sec.get("after_phase", "").strip()
        if after_ph:
            if after_ph not in phases:
                die(f"❌ [{section}]: after_phase = '{after_ph}' not yet defined. "
                    f"Declare [{section}] after [phase.{after_ph}] in the config.")
            search_from = phases[after_ph][2][1]  # i_end of the referenced phase
        else:
            search_from = 0

        # Determine the search zone: [search_from, zone_end)
        # 'search' key restricts matching to one arm of a peak/valley curve.
        search_dir = sec.get("search", "").strip().lower()
        zone_x = x[search_from:]
        if len(zone_x) < 2:
            die(f"❌ [{section}]: search zone has fewer than 2 rows — nothing to define a phase over.")

        if search_dir in ("ascending", "descending"):
            # Locate the x extremum within the zone to split arms.
            # Use argmax (for peak curves) — ascending arm is before it,
            # descending arm is after it.
            i_extrem_in_zone = int(np.argmax(zone_x))
            if search_dir == "ascending":
                if i_extrem_in_zone == 0:
                    warn(f"⚠️  [{section}] search=ascending: peak is at first row of zone — using full zone.")
                    zone_x = zone_x
                    zone_offset = search_from
                else:
                    zone_x = zone_x[:i_extrem_in_zone + 1]
                    zone_offset = search_from
            else:  # descending
                zone_x = zone_x[i_extrem_in_zone:]
                zone_offset = search_from + i_extrem_in_zone
        else:
            zone_offset = search_from

        i_start = zone_offset + int(np.argmin(np.abs(zone_x - x_start)))
        i_end   = zone_offset + int(np.argmin(np.abs(zone_x - x_end)))

        if i_end <= i_start:
            die(f"❌ [{section}]: x_end ({x_end}) resolves to row {i_end + 1} which is at or before "
                f"x_start ({x_start}) at row {i_start + 1}. "
                f"Check that x_end appears after x_start in the time series.")

        x_ph = x[i_start:i_end + 1]
        y_ph = y[i_start:i_end + 1]

        phases[name] = (x_ph, y_ph, (i_start, i_end))

        print(f"   Phase '{name}':  rows {i_start + 1}–{i_end + 1}  "
              f"(x: {x_ph[0]:.4g} → {x_ph[-1]:.4g},  {len(x_ph)} points)")

    return phases


# ---------------------------------------------------------------------------
# Smoothing
# ---------------------------------------------------------------------------

def smooth_array(cfg, y_arr, ph_name=None):
    """Return smoothed copy of y_arr.

    Phase-local keys smooth_method / smooth_span in [phase.ph_name] take
    priority over the global [smoothing] section. Raw data is unchanged
    for max/min/AUC calculations.
    """
    method = None
    span_val = None

    if ph_name:
        ph_sec_name = f"phase.{ph_name}"
        if cfg.has_section(ph_sec_name):
            ph_sec = dict(cfg[ph_sec_name])
            if "smooth_method" in ph_sec:
                method = ph_sec["smooth_method"].strip().lower()
            if "smooth_span" in ph_sec:
                try:
                    span_val = float(ph_sec["smooth_span"])
                except ValueError:
                    pass

    if method is None:
        if not cfg.has_section("smoothing"):
            return y_arr.copy()
        method = cfg.get("smoothing", "method", fallback="none").lower()

    if method == "none":
        return y_arr.copy()

    if span_val is None:
        span_val = float(cfg.get("smoothing", "span", fallback="0.15")
                         if cfg.has_section("smoothing") else "0.15")

    n = len(y_arr)

    if method == "savgol":
        window = max(5, int(span_val * n))
        if window % 2 == 0:
            window += 1
        window = min(window, n if n % 2 == 1 else n - 1)
        polyorder = min(3, window - 1)
        return savgol_filter(y_arr, window_length=window, polyorder=polyorder)

    if method == "moving_avg":
        window = max(3, int(span_val * n))
        if window % 2 == 0:
            window += 1
        kernel = np.ones(window) / window
        pad = window // 2
        padded = np.pad(y_arr, pad, mode="edge")
        smoothed = np.convolve(padded, kernel, mode="valid")
        return smoothed[:n]

    warn(f"⚠️  Unknown smoothing method '{method}'. No smoothing applied.")
    return y_arr.copy()


def smooth_half_window(cfg, n, ph_name=None):
    """Return the half-window size (in samples) for the smoothing applied to
    an array of length n.  Used to trim boundary regions from inflection search,
    where the smoothed curve is unreliable.  Returns 0 if smoothing is off."""
    method = None
    span_val = None

    if ph_name:
        ph_sec_name = f"phase.{ph_name}"
        if cfg.has_section(ph_sec_name):
            ph_sec = dict(cfg[ph_sec_name])
            if "smooth_method" in ph_sec:
                method = ph_sec["smooth_method"].strip().lower()
            if "smooth_span" in ph_sec:
                try:
                    span_val = float(ph_sec["smooth_span"])
                except ValueError:
                    pass

    if method is None:
        if not cfg.has_section("smoothing"):
            return 0
        method = cfg.get("smoothing", "method", fallback="none").lower()

    if method == "none":
        return 0

    if span_val is None:
        span_val = float(cfg.get("smoothing", "span", fallback="0.15")
                         if cfg.has_section("smoothing") else "0.15")

    window = max(5, int(span_val * n))
    if window % 2 == 0:
        window += 1
    window = min(window, n if n % 2 == 1 else n - 1)
    return window // 2


def smooth_d2y(cfg, xp, yp, ph_name=None):
    """Return the smoothed second derivative of yp with respect to xp.

    For savgol smoothing, uses savgol_filter(deriv=2) directly — one analytical
    pass over the raw data — instead of smoothing then computing gradient twice.
    This avoids the boundary-noise amplification of the double-gradient approach
    and gives a much cleaner second derivative near the phase edges.

    For moving_avg or no smoothing, falls back to smooth-then-double-gradient.
    """
    method = None
    span_val = None

    if ph_name:
        ph_sec_name = f"phase.{ph_name}"
        if cfg.has_section(ph_sec_name):
            ph_sec = dict(cfg[ph_sec_name])
            if "smooth_method" in ph_sec:
                method = ph_sec["smooth_method"].strip().lower()
            if "smooth_span" in ph_sec:
                try:
                    span_val = float(ph_sec["smooth_span"])
                except ValueError:
                    pass

    if method is None:
        method = cfg.get("smoothing", "method", fallback="none").lower() \
                 if cfg.has_section("smoothing") else "none"

    if span_val is None:
        span_val = float(cfg.get("smoothing", "span", fallback="0.15")
                         if cfg.has_section("smoothing") else "0.15")

    n = len(yp)

    if method == "savgol":
        window = max(5, int(span_val * n))
        if window % 2 == 0:
            window += 1
        window = min(window, n if n % 2 == 1 else n - 1)
        polyorder = min(3, window - 1)
        mean_dx = abs((xp[-1] - xp[0]) / (n - 1)) if n > 1 else 1.0
        return savgol_filter(yp, window, polyorder, deriv=2, delta=mean_dx)

    # moving_avg or none: smooth first, then double numerical gradient
    ys = smooth_array(cfg, yp, ph_name)
    dy = np.gradient(ys, xp)
    return np.gradient(dy, xp)


# ---------------------------------------------------------------------------
# Interpolation helpers
# ---------------------------------------------------------------------------

def interp_y_at_x(x_ph, y_ph, x_query):
    """Linear interpolation; returns (value, error_str)."""
    x_lo, x_hi = min(x_ph[0], x_ph[-1]), max(x_ph[0], x_ph[-1])
    if x_query < x_lo or x_query > x_hi:
        return None, f"x={x_query} outside range [{x_lo:.4g}, {x_hi:.4g}]"
    # np.interp requires ascending x; sort if needed
    if x_ph[-1] < x_ph[0]:
        order = x_ph.argsort()
        return float(np.interp(x_query, x_ph[order], y_ph[order])), None
    return float(np.interp(x_query, x_ph, y_ph)), None


def x_at_y_crossings(x_ph, y_ph, y_query, mode="first"):
    """Return list of x crossings where y == y_query (linear interp)."""
    crossings = []
    for i in range(len(y_ph) - 1):
        y0, y1 = y_ph[i], y_ph[i + 1]
        if y0 == y1:
            continue
        if (y0 - y_query) * (y1 - y_query) <= 0:
            t = (y_query - y0) / (y1 - y0)
            crossings.append(x_ph[i] + t * (x_ph[i + 1] - x_ph[i]))
    if not crossings:
        return []
    if mode == "first":
        return [crossings[0]]
    if mode == "last":
        return [crossings[-1]]
    return crossings


def slope_at_x(x_ph, y_smooth_ph, x_query):
    """Central (or edge) finite difference at x_query on smoothed data."""
    i = int(np.argmin(np.abs(x_ph - x_query)))
    n = len(x_ph)
    if n < 2:
        return None
    if i == 0:
        return (y_smooth_ph[1] - y_smooth_ph[0]) / (x_ph[1] - x_ph[0])
    if i == n - 1:
        return (y_smooth_ph[-1] - y_smooth_ph[-2]) / (x_ph[-1] - x_ph[-2])
    dx = x_ph[i + 1] - x_ph[i - 1]
    if dx == 0:
        return None
    return (y_smooth_ph[i + 1] - y_smooth_ph[i - 1]) / dx


# ---------------------------------------------------------------------------
# Computation — global
# ---------------------------------------------------------------------------

def compute_global(cfg, x, y, phases):
    if not cfg.has_section("global"):
        return []

    sec = dict(cfg["global"])
    results = []

    def _resolve(ph_key, default_label, scoped_label_fmt):
        ph = sec.get(ph_key, "").strip()
        if ph and ph in phases:
            return phases[ph][0], phases[ph][1], scoped_label_fmt.format(ph)
        if ph and ph not in phases:
            warn(f"⚠️  Phase '{ph}' not defined — using full dataset.")
        return x, y, default_label

    if sec.get("max_y", "").lower() == "yes":
        i = int(np.argmax(y))
        results.append({"section": "Global", "label": "max Y",
                        "value": f"{y[i]:.6g}  at x = {x[i]:.6g}"})

    if sec.get("min_y", "").lower() == "yes":
        i = int(np.argmin(y))
        results.append({"section": "Global", "label": "min Y",
                        "value": f"{y[i]:.6g}  at x = {x[i]:.6g}"})

    if sec.get("max_x", "").lower() == "yes":
        i = int(np.argmax(x))
        results.append({"section": "Global", "label": "max X",
                        "value": f"{x[i]:.6g}  at y = {y[i]:.6g}"})

    if sec.get("min_x", "").lower() == "yes":
        i = int(np.argmin(x))
        results.append({"section": "Global", "label": "min X",
                        "value": f"{x[i]:.6g}  at y = {y[i]:.6g}"})

    if sec.get("auc", "").lower() == "yes":
        xp, yp, lbl = _resolve("auc.phase", "AUC", "AUC [{}]")
        val = float(np.trapezoid(yp, xp))
        results.append({"section": "Global", "label": lbl,
                        "value": f"{val:.6g}",
                        "note": "trapezoid rule, raw data"})

    if sec.get("hysteresis", "").lower() == "yes":
        lp = sec.get("hysteresis_loading.phase", "loading").strip()
        up = sec.get("hysteresis_unloading.phase", "unloading").strip()
        if lp not in phases or up not in phases:
            warn(f"⚠️  Hysteresis requires phases '{lp}' and '{up}' — skipped.")
        else:
            xl, yl, _ = phases[lp]
            xu, yu, _ = phases[up]
            x_lo = max(xl.min(), xu.min())
            x_hi = min(xl.max(), xu.max())
            if x_hi <= x_lo:
                warn("⚠️  Hysteresis: phases have no overlapping X range — skipped.")
            else:
                xg = np.linspace(x_lo, x_hi, 500)
                sl = np.argsort(xl); su = np.argsort(xu)
                yl_i = np.interp(xg, xl[sl], yl[sl])
                yu_i = np.interp(xg, xu[su], yu[su])
                hyst = float(np.trapezoid(np.abs(yl_i - yu_i), xg))
                results.append({"section": "Global", "label": "Hysteresis",
                                "value": f"{hyst:.6g}",
                                "note": f"area between '{lp}' and '{up}', linear interp, raw data"})

    return results


# ---------------------------------------------------------------------------
# Computation — per-phase properties
# ---------------------------------------------------------------------------

def compute_phase_properties(cfg, phases):
    """Compute properties declared directly in [phase.NAME] sections (e.g. auc)."""
    results = []
    for section in cfg.sections():
        if not section.startswith("phase."):
            continue
        name = section[len("phase."):]
        if name not in phases:
            continue
        sec = dict(cfg[section])
        xp, yp, _ = phases[name]
        if sec.get("max_y", "").lower() == "yes":
            i = int(np.argmax(yp))
            results.append({"section": "Phase", "label": f"max Y [{name}]",
                            "value": f"{yp[i]:.6g}  at x = {xp[i]:.6g}"})
        if sec.get("min_y", "").lower() == "yes":
            i = int(np.argmin(yp))
            results.append({"section": "Phase", "label": f"min Y [{name}]",
                            "value": f"{yp[i]:.6g}  at x = {xp[i]:.6g}"})
        if sec.get("max_x", "").lower() == "yes":
            i = int(np.argmax(xp))
            results.append({"section": "Phase", "label": f"max X [{name}]",
                            "value": f"{xp[i]:.6g}  at y = {yp[i]:.6g}"})
        if sec.get("min_x", "").lower() == "yes":
            i = int(np.argmin(xp))
            results.append({"section": "Phase", "label": f"min X [{name}]",
                            "value": f"{xp[i]:.6g}  at y = {yp[i]:.6g}"})
        if sec.get("auc", "").lower() == "yes":
            val = float(np.trapezoid(yp, xp))
            results.append({"section": "Phase", "label": f"AUC [{name}]",
                            "value": f"{val:.6g}",
                            "note": "trapezoid rule, raw data"})
    return results


# ---------------------------------------------------------------------------
# Computation — slope
# ---------------------------------------------------------------------------

def compute_slope(cfg, x, y, phases):
    if not cfg.has_section("slope"):
        return []

    sec = dict(cfg["slope"])
    results = []

    def _ph(ph_key):
        ph = sec.get(ph_key, "").strip()
        if ph and ph in phases:
            return phases[ph][0], phases[ph][1], ph
        if ph and ph not in phases:
            warn(f"⚠️  Phase '{ph}' not defined — using full dataset.")
        return x, y, ""

    x_range = float(x.max() - x.min())

    # overall
    if sec.get("overall", "").lower() == "yes":
        xp, yp, ph = _ph("overall.phase")
        lbl = f"slope overall [{ph}]" if ph else "slope overall"
        coeffs = np.polyfit(xp, yp, 1)
        yp_fit = np.polyval(coeffs, xp)
        ss_res = np.sum((yp - yp_fit) ** 2)
        ss_tot = np.sum((yp - yp.mean()) ** 2)
        r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
        ann = None
        if sec.get("overall.plot", "").lower() == "yes":
            ann = {"type": "regression", "xp": xp, "coeffs": coeffs, "label": lbl}
        results.append({"section": "Slope", "label": lbl,
                        "value": f"{coeffs[0]:.6g}",
                        "note": f"R\u00b2 = {r2:.4f}, linear regression, raw data",
                        "plot": ann})

    # secant
    if sec.get("secant", "").lower() == "yes":
        xp, yp, ph = _ph("secant.phase")
        try:
            sx1 = float(sec["secant.x1"])
            sx2 = float(sec["secant.x2"])
        except (KeyError, ValueError):
            warn("⚠️  [slope] secant: secant.x1 and secant.x2 required — skipped.")
        else:
            lbl = f"slope secant x={sx1}\u2013{sx2} [{ph}]" if ph else f"slope secant x={sx1}\u2013{sx2}"
            sy1, e1 = interp_y_at_x(xp, yp, sx1)
            sy2, e2 = interp_y_at_x(xp, yp, sx2)
            if e1 or e2:
                warn(f"⚠️  Secant slope: {e1 or e2} — skipped.")
            elif sx1 == sx2:
                warn("⚠️  Secant slope: secant_x1 == secant_x2 — skipped.")
            else:
                val = (sy2 - sy1) / (sx2 - sx1)
                ann = None
                if sec.get("secant.plot", "").lower() == "yes":
                    ann = {"type": "segment",
                           "x0": sx1, "y0": sy1, "x1": sx2, "y1": sy2, "label": lbl}
                results.append({"section": "Slope", "label": lbl,
                                "value": f"{val:.6g}",
                                "note": f"y({sx1})={sy1:.4g}, y({sx2})={sy2:.4g}",
                                "plot": ann})

    # instantaneous slope at_x_N
    for key in sorted(sec):
        if not key.startswith("at_x_"):
            continue
        suffix = key[len("at_x_"):]
        if not suffix.isdigit():
            continue
        xp, yp, ph = _ph(f"at_x_{suffix}.phase")
        try:
            x_query = float(sec[key])
        except ValueError:
            warn(f"⚠️  [slope] at_x_{suffix} = '{sec[key]}' not numeric — skipped.")
            continue
        lbl = f"slope at x={x_query} [{ph}]" if ph else f"slope at x={x_query}"
        ys = smooth_array(cfg, yp, ph)
        s = slope_at_x(xp, ys, x_query)
        if s is None:
            warn(f"⚠️  slope at x={x_query}: too few points — skipped.")
        else:
            ann = None
            if sec.get(f"at_x_{suffix}.plot", "").lower() == "yes":
                yc, _ = interp_y_at_x(xp, yp, x_query)
                ann = {"type": "tangent", "xc": x_query, "yc": yc,
                       "slope": s, "x_range": x_range, "label": lbl}
            results.append({"section": "Slope", "label": lbl,
                            "value": f"{s:.6g}",
                            "note": "numerical derivative, smoothed data",
                            "plot": ann})

    return results


# ---------------------------------------------------------------------------
# Computation — query
# ---------------------------------------------------------------------------

def compute_query(cfg, x, y, phases):
    if not cfg.has_section("query"):
        return []

    sec = dict(cfg["query"])
    results = []

    def _ph(ph_key):
        ph = sec.get(ph_key, "").strip()
        if ph and ph in phases:
            return phases[ph][0], phases[ph][1], ph
        if ph and ph not in phases:
            warn(f"⚠️  Phase '{ph}' not defined — using full dataset.")
        return x, y, ""

    for key in sorted(sec):
        # y_at_x_N
        if key.startswith("y_at_x_"):
            suffix = key[len("y_at_x_"):]
            if not suffix.isdigit():
                continue
            xp, yp, ph = _ph(f"y_at_x_{suffix}.phase")
            try:
                xq = float(sec[key])
            except ValueError:
                warn(f"⚠️  [query] y_at_x_{suffix} not numeric — skipped.")
                continue
            lbl = f"Y at x={xq} [{ph}]" if ph else f"Y at x={xq}"
            val, err = interp_y_at_x(xp, yp, xq)
            if err:
                warn(f"⚠️  y_at_x_{suffix}: {err} — skipped.")
            else:
                show = sec.get(f"y_at_x_{suffix}.show", "").lower() == "yes"
                ann = {"type": "marker", "symbol": "+", "xc": xq,
                       "yc": val, "label": lbl} if show else None
                results.append({"section": "Query", "label": lbl,
                                "value": f"{val:.6g}", "note": "linear interpolation",
                                "plot": ann})

        # x_at_y_N
        elif key.startswith("x_at_y_"):
            suffix = key[len("x_at_y_"):]
            if not suffix.isdigit():
                continue
            mode = sec.get(f"x_at_y_{suffix}.mode", "first").strip().lower()
            xp, yp, ph = _ph(f"x_at_y_{suffix}.phase")
            try:
                yq = float(sec[key])
            except ValueError:
                warn(f"⚠️  [query] x_at_y_{suffix} not numeric — skipped.")
                continue
            lbl = f"X at y={yq} [{ph}]" if ph else f"X at y={yq}"
            crossings = x_at_y_crossings(xp, yp, yq, mode)
            if not crossings:
                warn(f"⚠️  x_at_y_{suffix}: no crossing at y={yq} — skipped.")
            else:
                for ci, xc in enumerate(crossings):
                    row_lbl = f"{lbl} [{ci + 1}]" if len(crossings) > 1 else lbl
                    results.append({"section": "Query", "label": row_lbl,
                                    "value": f"{xc:.6g}",
                                    "note": f"mode={mode}, linear interpolation"})

        # y_at_rel_x_N  — Y at x_ref * (1 + frac)
        elif key.startswith("y_at_rel_x_"):
            suffix = key[len("y_at_rel_x_"):]
            if not suffix.isdigit():
                continue
            xp, yp, ph = _ph(f"y_at_rel_x_{suffix}.phase")
            try:
                x_ref = float(sec[key])
                frac  = float(sec.get(f"y_at_rel_x_{suffix}.frac", "0"))
            except ValueError:
                warn(f"⚠️  [query] y_at_rel_x_{suffix}: x_ref and frac must be numeric — skipped.")
                continue
            x_query = x_ref * (1.0 + frac)
            pct = frac * 100
            lbl_ref = f"x={x_ref:g}{pct:+.4g}%"
            lbl = f"Y at {lbl_ref} [{ph}]" if ph else f"Y at {lbl_ref}"
            val, err = interp_y_at_x(xp, yp, x_query)
            if err:
                warn(f"⚠️  y_at_rel_x_{suffix}: {err} — skipped.")
            else:
                show = sec.get(f"y_at_rel_x_{suffix}.show", "").lower() == "yes"
                ann = {"type": "marker", "symbol": "+", "xc": x_query,
                       "yc": val, "label": lbl} if show else None
                results.append({"section": "Query", "label": lbl,
                                "value": f"{val:.6g}",
                                "note": f"x={x_ref:g}×(1{frac:+g})={x_query:.6g}, linear interpolation",
                                "plot": ann})

    return results


# ---------------------------------------------------------------------------
# Computation — transitions
# ---------------------------------------------------------------------------

def compute_transitions(cfg, x, y, phases):
    if not cfg.has_section("transitions"):
        return []

    sec = dict(cfg["transitions"])
    results = []

    def _ph(ph_key):
        ph = sec.get(ph_key, "").strip()
        if ph and ph in phases:
            return phases[ph][0], phases[ph][1], ph
        if ph and ph not in phases:
            warn(f"⚠️  Phase '{ph}' not defined — using full dataset.")
        return x, y, ""

    # inflections — supports bare keys (single block) and numbered suffixes
    # (inflections_1, inflections_2, ...) for multiple phases.
    # Bare keys: inflections, inflections.phase, inflections.plot_slope,
    #            inflections.min_gap
    # Numbered:  inflections_N, inflections_N.phase, inflections_N.plot_slope,
    #            inflections_N.min_gap   (N = 1, 2, 3, ...)
    # Both forms may coexist in the same [transitions] section.
    def _run_inflections(ph_key, plot_slope_key, min_gap_key):
        xp, yp, ph = _ph(ph_key)
        lbl_pfx = f"inflection [{ph}]" if ph else "inflection"
        ys = smooth_array(cfg, yp, ph)
        d2y = smooth_d2y(cfg, xp, yp, ph)
        x_span = float(xp.max() - xp.min())
        x_range = float(x.max() - x.min())
        try:
            min_gap = float(sec.get(min_gap_key, str(round(0.05 * x_span, 6))))
        except ValueError:
            min_gap = 0.05 * x_span
        trim = max(3, int(0.02 * len(yp)))
        raw = []
        for i in range(trim, len(d2y) - 1 - trim):
            if d2y[i] * d2y[i + 1] < 0 and (d2y[i + 1] - d2y[i]) != 0:
                t = -d2y[i] / (d2y[i + 1] - d2y[i])
                xi = xp[i] + t * (xp[i + 1] - xp[i])
                yi, _ = interp_y_at_x(xp, yp, xi)
                raw.append((xi, yi))
        # Enforce minimum gap using absolute X distance (works for both
        # ascending and descending phases)
        found = []
        for xi, yi in raw:
            if not found or abs(xi - found[-1][0]) >= min_gap:
                found.append((xi, yi))
        plot_slope = sec.get(plot_slope_key, "").lower() == "yes"
        if not found:
            results.append({"section": "Transitions", "label": lbl_pfx,
                            "value": "none found",
                            "note": "second derivative sign change, smoothed data"})
        else:
            note_gap = f"min gap = {min_gap:.4g}" if min_gap > 0 else ""
            note = "second derivative sign change, smoothed data"
            if note_gap:
                note += f"; {note_gap}"
            for k, (xi, yi) in enumerate(found):
                si = slope_at_x(xp, ys, xi)
                slope_str = f",  slope = {si:.6g}" if si is not None else ""
                ann = None
                if plot_slope and si is not None:
                    ann = {"type": "tangent", "xc": xi, "yc": yi,
                           "slope": si, "x_range": x_range, "hw_factor": 2.0,
                           "label": f"{lbl_pfx} {k + 1} slope"}
                results.append({"section": "Transitions",
                                "label": f"{lbl_pfx} {k + 1}",
                                "value": f"x = {xi:.6g},  y = {yi:.6g}{slope_str}",
                                "note": note,
                                "plot": ann})

    if sec.get("inflections", "").lower() == "yes":
        _run_inflections("inflections.phase", "inflections.plot_slope",
                         "inflections.min_gap")

    for key in sorted(sec):
        if not key.startswith("inflections_"):
            continue
        suffix = key[len("inflections_"):]
        if not suffix.isdigit():
            continue
        if sec[key].lower() != "yes":
            continue
        _run_inflections(f"inflections_{suffix}.phase",
                         f"inflections_{suffix}.plot_slope",
                         f"inflections_{suffix}.min_gap")

    # yield — supports bare keys (single block) and numbered suffixes
    # yield.slope, yield.phase  OR  yield_1.slope, yield_1.phase, yield_2.slope, ...
    def _run_yield(slope_key, phase_key, show_key):
        if slope_key not in sec:
            return
        xp, yp, ph = _ph(phase_key)
        lbl = f"yield point [{ph}]" if ph else "yield point"
        try:
            frac = float(sec[slope_key])
        except ValueError:
            warn(f"⚠️  [transitions] {slope_key} must be numeric — skipped.")
            return
        ys = smooth_array(cfg, yp, ph)
        dy = np.gradient(ys, xp)
        max_slope = np.max(np.abs(dy))
        if max_slope == 0:
            warn(f"⚠️  {slope_key}: max slope is zero — skipped.")
            return
        threshold = frac * max_slope
        i_max = int(np.argmax(np.abs(dy)))
        yield_x = yield_y = None
        for i in range(i_max, len(dy)):
            if np.abs(dy[i]) <= threshold:
                yield_x = float(xp[i])
                yield_y, _ = interp_y_at_x(xp, yp, yield_x)
                break
        if yield_x is None:
            results.append({"section": "Transitions", "label": lbl,
                            "value": "not reached",
                            "note": f"slope never drops to {frac:.3g} \u00d7 max slope"})
        else:
            show = sec.get(show_key, "").strip().lower() == "yes"
            ann = {"type": "marker", "symbol": "x", "xc": yield_x,
                   "yc": yield_y, "label": lbl} if show else None
            results.append({"section": "Transitions", "label": lbl,
                            "value": f"x = {yield_x:.6g},  y = {yield_y:.6g}",
                            "note": f"slope threshold = {frac:.3g} \u00d7 max ({max_slope:.4g}), smoothed",
                            "plot": ann})

    _run_yield("yield.slope", "yield.phase", "yield.show")

    for key in sorted(sec):
        if not key.startswith("yield_"):
            continue
        dot_pos = key.find(".")
        if dot_pos == -1:
            continue
        suffix = key[len("yield_"):dot_pos]
        modifier = key[dot_pos + 1:]
        if not suffix.isdigit() or modifier != "slope":
            continue
        _run_yield(f"yield_{suffix}.slope", f"yield_{suffix}.phase", f"yield_{suffix}.show")

    return results


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def _label_x(cfg):
    if cfg.has_section("output"):
        return cfg.get("output", "label_x", fallback=cfg.get("data", "x_col", fallback="x"))
    return cfg.get("data", "x_col", fallback="x")


def _label_y(cfg):
    if cfg.has_section("output"):
        return cfg.get("output", "label_y", fallback=cfg.get("data", "y_col", fallback="y"))
    return cfg.get("data", "y_col", fallback="y")


def _title(cfg):
    if cfg.has_section("output"):
        return cfg.get("output", "title", fallback="Curve Properties Analysis")
    return "Curve Properties Analysis"


def print_results(all_results, cfg, n_rows):
    title = _title(cfg)
    sep = "=" * max(46, len(title) + 2)
    print()
    print(f"✅ {title}")
    print(f"   version: 1.0, author: Joep Rous")
    print(f"   {sep}")
    print(f"   Rows loaded  : {n_rows}")
    print(f"   X column     : {cfg.get('data', 'x_col', fallback='?')}")
    print(f"   Y column     : {cfg.get('data', 'y_col', fallback='?')}")
    print()

    current_section = None
    for r in all_results:
        sec = r.get("section", "")
        if sec != current_section:
            if current_section is not None:
                print()
            print(f"   {sec}")
            print(f"   {'-' * 46}")
            current_section = sec
        label = r["label"]
        value = r["value"]
        note  = r.get("note", "")
        pad   = max(1, 38 - len(label))
        print(f"   {label}{' ' * pad}: {value}")
        if note:
            print(f"   {'':38}  ({note})")
    print()


def write_debug_d2y(cfg, cfg_dir, cfg_path, x, y, phases):
    """Write a debug CSV showing y_smooth and d2y for a phase.

    Triggered by a [debug] section in the config:
        [debug]
        d2y        = yes
        d2y.phase  = loading      # phase name (required)

    Output columns: x, y_raw, y_smooth, d2y, trimmed
      trimmed = 1 for rows excluded by the half-window boundary trim.
    """
    if not cfg.has_section("debug"):
        return
    sec = dict(cfg["debug"])
    if sec.get("d2y", "").lower() != "yes":
        return

    ph = sec.get("d2y.phase", "").strip()
    if not ph:
        warn("⚠️  [debug] d2y.phase is required — debug CSV skipped.")
        return
    if ph not in phases:
        warn(f"⚠️  [debug] d2y.phase '{ph}' not defined — debug CSV skipped.")
        return

    xp, yp, _ = phases[ph]
    ys = smooth_array(cfg, yp, ph)
    d2y = smooth_d2y(cfg, xp, yp, ph)
    trim = max(3, int(0.02 * len(yp)))

    stem = os.path.splitext(os.path.basename(cfg_path))[0]
    out_path = os.path.join(cfg_dir, f"{stem}_debug_d2y_{ph}.csv")

    with open(out_path, "w", newline="") as f:
        f.write("x,y_raw,y_smooth,d2y,trimmed\n")
        for i in range(len(xp)):
            trimmed = 1 if (i < trim or i >= len(xp) - trim) else 0
            f.write(f"{xp[i]:.8g},{yp[i]:.8g},{ys[i]:.8g},{d2y[i]:.8g},{trimmed}\n")

    print(f"   Debug d2y    : {out_path}  ({len(xp)} rows, trim={trim})")


def write_results_file(all_results, cfg, cfg_dir, cfg_path):
    if cfg.has_section("output"):
        rf = cfg.get("output", "results_file", fallback=None)
        results_path = resolve_path(cfg_dir, rf) if rf else None
    else:
        results_path = None

    if results_path is None:
        stem = os.path.splitext(os.path.basename(cfg_path))[0]
        results_path = os.path.join(cfg_dir, f"{stem}_results.txt")

    os.makedirs(os.path.dirname(results_path) if os.path.dirname(results_path) else ".", exist_ok=True)

    with open(results_path, "w", encoding="utf-8") as f:
        f.write("# jrc_curve_properties results\n")
        f.write(f"# config  : {cfg_path}\n")
        f.write(f"# data    : {cfg.get('data', 'file', fallback='?')}\n")
        f.write("#\n")
        header = f"{'section':<16}{'label':<42}{'value':<28}note\n"
        f.write(header)
        f.write("-" * 100 + "\n")
        for r in all_results:
            line = (f"{r.get('section', ''):<16}"
                    f"{r['label']:<42}"
                    f"{r['value']:<28}"
                    f"{r.get('note', '')}\n")
            f.write(line)

    print(f"   Results file : {results_path}")


# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

_PHASE_COLORS = ["#4878CF", "#D65F5F", "#6ACC65", "#B47CC7", "#C4AD66", "#77BEDB"]


_ANNOT_COLORS = ["#C0392B", "#8E44AD", "#2980B9", "#27AE60", "#E67E22", "#16A085",
                 "#D35400", "#2C3E50", "#7D3C98", "#1A5276"]


def generate_plot(cfg, cfg_dir, cfg_path, x, y, phases, all_results):
    if cfg.has_section("output"):
        pf = cfg.get("output", "plot_file", fallback=None)
        plot_path = resolve_path(cfg_dir, pf) if pf else None
    else:
        plot_path = None

    if plot_path is None:
        stem = os.path.splitext(os.path.basename(cfg_path))[0]
        plot_path = os.path.join(cfg_dir, f"{stem}_plot.pdf")

    os.makedirs(os.path.dirname(plot_path) if os.path.dirname(plot_path) else ".", exist_ok=True)

    fig, ax = plt.subplots(figsize=(10, 6))

    apply_smooth = (cfg.has_section("smoothing") and
                    cfg.get("smoothing", "apply_to_plot", fallback="no").lower() == "yes")

    # Collect which row indices are covered by at least one phase
    phase_index_sets = {}
    for ph_name, (x_ph, y_ph, (i0, i1)) in phases.items():
        phase_index_sets[ph_name] = set(range(i0, i1 + 1))
    covered = set().union(*phase_index_sets.values()) if phase_index_sets else set()

    # Plot uncovered rows in grey — split into contiguous segments so
    # matplotlib does not connect rows across phase gaps
    uncovered = [i for i in range(len(x)) if i not in covered]
    if uncovered:
        segments = []
        seg = [uncovered[0]]
        for i in uncovered[1:]:
            if i == seg[-1] + 1:
                seg.append(i)
            else:
                segments.append(seg)
                seg = [i]
        segments.append(seg)
        for k, seg in enumerate(segments):
            ax.plot(x[seg], y[seg], color="#BBBBBB", linewidth=0.8,
                    label="data (no phase)" if k == 0 else "_nolegend_",
                    zorder=1)

    # Plot each phase segment in its own colour
    for k, (ph_name, (x_ph, y_ph, (i0, i1))) in enumerate(phases.items()):
        color = _PHASE_COLORS[k % len(_PHASE_COLORS)]
        ax.plot(x_ph, y_ph, color=color, linewidth=1.5,
                label=f"phase: {ph_name}", zorder=2)

    # If no phases defined, plot all data
    if not phases:
        ax.plot(x, y, color="#555555", linewidth=1.0, label="raw data", zorder=1)

    # Smoothed overlay: draw per phase so each phase uses its own smoothing settings
    if apply_smooth:
        smooth_plotted = False
        for ph_name, (x_ph, y_ph, _) in phases.items():
            ys_ph = smooth_array(cfg, y_ph, ph_name)
            label = "smoothed" if not smooth_plotted else "_nolegend_"
            ax.plot(x_ph, ys_ph, color="#E87722", linewidth=0.9,
                    label=label, zorder=4)
            smooth_plotted = True
        if not phases:
            ys = smooth_array(cfg, y)
            ax.plot(x, ys, color="#E87722", linewidth=0.9,
                    label="smoothed", zorder=4)

    # Slope / inflection annotations
    annot_idx = 0
    for r in all_results:
        ann = r.get("plot")
        if ann is None:
            continue
        color = _ANNOT_COLORS[annot_idx % len(_ANNOT_COLORS)]
        annot_idx += 1
        lbl = ann.get("label", "")

        if ann["type"] == "regression":
            xp = ann["xp"]
            x0, x1 = float(xp.min()), float(xp.max())
            y0 = np.polyval(ann["coeffs"], x0)
            y1 = np.polyval(ann["coeffs"], x1)
            ax.plot([x0, x1], [y0, y1], color=color, linewidth=1.1,
                    linestyle="--", label=lbl, zorder=5)

        elif ann["type"] == "segment":
            ax.plot([ann["x0"], ann["x1"]], [ann["y0"], ann["y1"]],
                    color=color, linewidth=1.1, linestyle="--",
                    label=lbl, zorder=5)
            ax.plot([ann["x0"], ann["x1"]], [ann["y0"], ann["y1"]],
                    "o", color=color, markersize=5, zorder=6)

        elif ann["type"] == "tangent":
            # Normalise by sqrt(1+s²) so all tangent lines have the same
            # Euclidean length in data space regardless of slope.
            s = ann["slope"]
            length = 0.10 * ann["x_range"] * ann.get("hw_factor", 1.0)
            hw = length / np.sqrt(1.0 + s ** 2)
            xc, yc = ann["xc"], ann["yc"]
            ax.plot([xc - hw, xc + hw],
                    [yc - s * hw, yc + s * hw],
                    color=color, linewidth=1.1, linestyle="--",
                    label=lbl, zorder=5)
            ax.plot(xc, yc, "o", color=color, markersize=4, zorder=6)

        elif ann["type"] == "marker":
            sym = ann.get("symbol", "x")
            ms, mew = (10, 2) if sym == "+" else (10, 2)
            ax.plot(ann["xc"], ann["yc"], sym, color="white",
                    markersize=ms + 4, markeredgewidth=mew + 2, zorder=6)
            ax.plot(ann["xc"], ann["yc"], sym, color=color,
                    markersize=ms, markeredgewidth=mew,
                    label=lbl, zorder=7)

    ax.set_xlabel(_label_x(cfg))
    ax.set_ylabel(_label_y(cfg))
    ax.set_title(_title(cfg))
    ax.legend(fontsize=8, loc="best")
    ax.grid(True, linestyle=":", alpha=0.4)
    plt.tight_layout()
    plt.savefig(plot_path, format="pdf", dpi=150)
    plt.close()

    print(f"   Plot file    : {plot_path}")


# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

def print_help():
    print("""
jrc_curve_properties — XY Curve Properties Analysis
Version 1.0 | Author: Joep Rous

USAGE
    jrrun jrc_curve_properties.py path/to/config.cfg
    jrrun jrc_curve_properties.py --help

DESCRIPTION
    Extracts engineering properties from an XY time-ordered measurement
    curve (e.g. force vs. displacement, torque vs. angle). Input is a
    two-column CSV and a .cfg config file. Properties include peak values,
    area under curve, slopes, query values, inflection points, and
    hysteresis.

    All paths in the config are relative to the config file's own directory.
    Absent config key = skip that feature. No need to write 'no'.

    Smoothing (savgol or moving_avg) is applied ONLY to derivative-based
    calculations (slope at X, inflections, yield point). max/min/AUC/
    hysteresis are always computed on raw data.

CONFIG SECTIONS
    [data]         required — CSV path, x_col, y_col
    [output]       optional — label_x, label_y, title, plot (yes/no),
                              plot_file, results_file
    [smoothing]    optional — method (savgol|moving_avg|none), span (0–1),
                              apply_to_plot (yes/no)
    [phase.NAME]   optional, repeatable — x_start, x_end, max_y, min_y, max_x, min_x, auc
    [global]       optional — max_y, min_y, max_x, min_x, auc, hysteresis
    [slope]        optional — overall, secant, at_x_1, at_x_2, ...
    [query]        optional — y_at_x_1, x_at_y_1, x_at_y_1.mode, ...
    [transitions]  optional — inflections, yield.slope

EXAMPLE CONFIG
    [data]
    file   = data/force_compression.csv
    x_col  = displacement_mm
    y_col  = force_N

    [phase.loading]
    x_start = 5
    x_end   = 95

    [global]
    max_y     = yes
    auc       = yes
    auc.phase = loading

    [slope]
    secant       = yes
    secant.phase = loading
    secant.x1    = 10.0
    secant.x2    = 40.0

    [query]
    y_at_x_1       = 50.0
    y_at_x_1.phase = loading
    x_at_y_1       = 80.0
    x_at_y_1.phase = loading
    x_at_y_1.mode  = first
""")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print_help()
        sys.exit(0)
    if len(sys.argv) > 2:
        die("❌ Too many arguments. Usage: jrrun jrc_curve_properties.py path/to/config.cfg")

    cfg_path = sys.argv[1]
    if not os.path.isfile(cfg_path):
        die(f"❌ Config file not found: {cfg_path}")

    cfg_dir = os.path.dirname(os.path.abspath(cfg_path))

    print()

    cfg = parse_config(cfg_path)
    validate_config(cfg, cfg_path)
    x, y = load_data(cfg, cfg_dir)

    print(f"   Data loaded  : {len(x)} rows")

    # Y transforms — applied in order: scale first, then offset
    transform_results = []
    if cfg.has_section("transform"):
        scale_str = cfg.get("transform", "y_scale", fallback="").strip()
        if scale_str:
            try:
                scale = float(scale_str)
                y = y * scale
                print(f"   Y scale      : ×{scale}")
                transform_results.append({"section": "Transform", "label": "Y scale",
                                          "value": f"×{scale}"})
            except ValueError:
                warn("⚠️  [transform] y_scale must be numeric — scale not applied.")

        offset_x_str = cfg.get("transform", "y_offset_x", fallback="").strip()
        if offset_x_str:
            try:
                offset_x = float(offset_x_str)
                offset_y, err = interp_y_at_x(x, y, offset_x)
                if err:
                    warn(f"⚠️  [transform] y_offset_x: {err} — offset not applied.")
                else:
                    y = y - offset_y
                    print(f"   Y offset     : -{offset_y:.6g}  (Y at x={offset_x})")
                    transform_results.append({"section": "Transform", "label": "Y offset",
                                              "value": f"-{offset_y:.6g}",
                                              "note": f"Y at x = {offset_x} subtracted from all Y"})
            except ValueError:
                warn("⚠️  [transform] y_offset_x must be numeric — offset not applied.")

    phases = extract_phases(cfg, x, y)

    has_smooth = (cfg.has_section("smoothing") and
                  cfg.get("smoothing", "method", fallback="none").lower() != "none")
    if has_smooth:
        method = cfg.get("smoothing", "method", fallback="savgol")
        span   = cfg.get("smoothing", "span", fallback="0.15")
        print(f"   Smoothing    : {method}  span={span}  (global default)")
        print(f"                  (applied to derivatives only; max/min/AUC use raw data)")
    for ph_name in phases:
        ph_sec_name = f"phase.{ph_name}"
        if cfg.has_section(ph_sec_name):
            ph_sec = dict(cfg[ph_sec_name])
            if "smooth_method" in ph_sec:
                m = ph_sec["smooth_method"]
                s = ph_sec.get("smooth_span", cfg.get("smoothing", "span", fallback="0.15")
                               if cfg.has_section("smoothing") else "0.15")
                print(f"   Smoothing    : {m}  span={s}  (phase '{ph_name}' override)")

    print()

    all_results = []
    all_results.extend(transform_results)
    all_results.extend(compute_global(cfg, x, y, phases))
    all_results.extend(compute_phase_properties(cfg, phases))
    all_results.extend(compute_slope(cfg, x, y, phases))
    all_results.extend(compute_query(cfg, x, y, phases))
    all_results.extend(compute_transitions(cfg, x, y, phases))

    print_results(all_results, cfg, len(x))

    write_results_file(all_results, cfg, cfg_dir, cfg_path)

    write_debug_d2y(cfg, cfg_dir, cfg_path, x, y, phases)

    if cfg.has_section("output") and cfg.get("output", "plot", fallback="no").lower() == "yes":
        generate_plot(cfg, cfg_dir, cfg_path, x, y, phases, all_results)

    if _warnings:
        print(f"\n⚠️  {len(_warnings)} warning(s) issued during analysis.")

    print()


if __name__ == "__main__":
    main()
