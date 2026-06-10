"""
OQ test suite — Curve module: jrc_curve_properties

Maps to validation plan JR-VP-CURVE-001 as follows:

  TC-CURVE-V-001  No arguments -> exit 0, usage printed (help mode)
  TC-CURVE-V-002  Config file not found -> non-zero exit
  TC-CURVE-V-003  Data file not found (referenced in config) -> non-zero exit
  TC-CURVE-V-004  Unknown section in config -> non-zero exit, "Unknown section" in output
  TC-CURVE-V-005  Unknown key in [global] -> non-zero exit, "Unknown key" in output
  TC-CURVE-V-006  Non-numeric value in [transform] -> non-zero exit
  TC-CURVE-V-007  [debug] d2y=yes without d2y.phase -> non-zero exit

  TC-CURVE-G-001  global max_y -> exit 0, "max Y" in output
  TC-CURVE-G-002  global min_y -> "min Y" in output
  TC-CURVE-G-003  global max_x and min_x -> "max X" and "min X" in output
  TC-CURVE-G-004  global AUC on linear data -> "AUC" in output, value 400 present
  TC-CURVE-G-005  global hysteresis -> exit 0, "Hysteresis" in output

  TC-CURVE-P-001  per-phase max_y -> "max Y [loading]" in output
  TC-CURVE-P-002  per-phase AUC -> "AUC [loading]" in output
  TC-CURVE-P-003  multiple phases in one run -> both phase names in output

  TC-CURVE-S-001  overall slope on linear data -> "slope overall" in output
  TC-CURVE-S-002  secant slope -> "slope secant" in output
  TC-CURVE-S-003  instantaneous slope -> "slope at x=" in output

  TC-CURVE-Q-001  y_at_x query -> "Y at x=" in output
  TC-CURVE-Q-002  x_at_y query -> "X at y=" in output
  TC-CURVE-Q-003  y_at_rel_x query -> "Y at" and "%" in output
  TC-CURVE-Q-004  width_at_y on triangle data -> width = 5/9 ± 0.001
  TC-CURVE-Q-005  x_at_y at triangle apex -> "tangency" annotation in output
  TC-CURVE-Q-006  x_at_y.show / width_at_y.show with plot=yes -> plot PDF created

  TC-CURVE-T-001  y_scale transform -> exit 0, "Y scale" in output
  TC-CURVE-T-002  y_offset_x transform -> "Y offset" in output
  TC-CURVE-T-003  x_scale/x_offset transforms -> labels in output, slope = 1.000

  TC-CURVE-R-001  resample=yes on non-uniform sine -> inflection at pi ± 0.1,
                  no non-uniform spacing warning

  TC-CURVE-I-001  inflections on sine data -> "inflection" in output
  TC-CURVE-I-002  yield point on sine data -> "yield point" in output

  TC-CURVE-O-001  results .txt file created after successful run
  TC-CURVE-O-002  plot PDF created when plot=yes and plot_file specified
  TC-CURVE-O-003  debug d2y CSV created when [debug] d2y=yes

Numeric correctness assertions (TC-CURVE-N-001 to TC-CURVE-N-003):

  Dataset: linear.csv — 21 pts, x=0..20, y=2x (exact linear relationship)
  Independent computation:
    AUC (trapezoid) = sum of trapezoids = 20 * (0+40)/2 = 400.0 (exact)
    slope (OLS)     = Sxy / Sxx = 2.000 (exact for y=2x)
    Y at x=5        = 2*5 = 10.0 (exact from the data)

  TC-CURVE-N-001  AUC for linear data     = 400.0 ± 0.5  (trapezoid rule, exact linear)
  TC-CURVE-N-002  overall slope           = 2.000 ± 0.001 (OLS on y=2x)
  TC-CURVE-N-003  Y at x=5 (y_at_x query) = 10.0  ± 0.01 (exact point on y=2x)
"""

import math
import os

import re

from conftest import DATA_DIR, run, combined, data, extract_float


class TestCurveValidation:

    def test_tc_curve_v_001_no_arguments(self):
        """
        TC-CURVE-V-001:
        Calling with no arguments must exit 0 and print usage (help mode).
        The script treats missing args the same as --help.
        """
        r = run("jrc_curve_properties.py")
        assert r.returncode == 0, \
            f"Expected exit 0 (help mode) with no arguments:\n{combined(r)}"
        out = combined(r)
        assert "USAGE" in out or "Usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_curve_v_002_config_not_found(self):
        """
        TC-CURVE-V-002:
        Non-existent config file must exit non-zero.
        """
        r = run("jrc_curve_properties.py", "nonexistent_config_xyz.cfg")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing config:\n{combined(r)}"

    def test_tc_curve_v_003_data_file_not_found(self):
        """
        TC-CURVE-V-003:
        Config referencing a non-existent data file must exit non-zero.
        """
        r = run("jrc_curve_properties.py", data("err_no_datafile.cfg"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing data file:\n{combined(r)}"

    def test_tc_curve_v_004_unknown_section(self):
        """
        TC-CURVE-V-004:
        Config with an unknown section must exit non-zero and report it.
        """
        r = run("jrc_curve_properties.py", data("err_unknown_section.cfg"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for unknown section:\n{combined(r)}"
        out = combined(r)
        assert "Unknown section" in out, \
            f"Expected 'Unknown section' in output:\n{out}"

    def test_tc_curve_v_005_unknown_key(self):
        """
        TC-CURVE-V-005:
        Config with an unknown key in [global] must exit non-zero and report it.
        """
        r = run("jrc_curve_properties.py", data("err_unknown_key.cfg"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for unknown key:\n{combined(r)}"
        out = combined(r)
        assert "Unknown key" in out, \
            f"Expected 'Unknown key' in output:\n{out}"

    def test_tc_curve_v_006_nonnumeric_value(self):
        """
        TC-CURVE-V-006:
        Non-numeric value in [transform] y_scale must exit non-zero.
        """
        r = run("jrc_curve_properties.py", data("err_nonnumeric.cfg"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for non-numeric value:\n{combined(r)}"

    def test_tc_curve_v_007_d2y_without_phase(self):
        """
        TC-CURVE-V-007:
        [debug] d2y=yes without d2y.phase must exit non-zero.
        """
        r = run("jrc_curve_properties.py", data("err_d2y_no_phase.cfg"))
        assert r.returncode != 0, \
            f"Expected non-zero exit when d2y=yes but d2y.phase absent:\n{combined(r)}"


class TestCurveGlobal:

    def test_tc_curve_g_001_max_y(self):
        """
        TC-CURVE-G-001:
        global max_y=yes must exit 0 and report "max Y" in output.
        """
        r = run("jrc_curve_properties.py", data("test_global.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "max Y" in combined(r), \
            f"Expected 'max Y' in output:\n{combined(r)}"

    def test_tc_curve_g_002_min_y(self):
        """
        TC-CURVE-G-002:
        global min_y=yes must report "min Y" in output.
        """
        r = run("jrc_curve_properties.py", data("test_global.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "min Y" in combined(r), \
            f"Expected 'min Y' in output:\n{combined(r)}"

    def test_tc_curve_g_003_max_x_and_min_x(self):
        """
        TC-CURVE-G-003:
        global max_x=yes and min_x=yes must report both labels in output.
        """
        r = run("jrc_curve_properties.py", data("test_global.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "max X" in out, f"Expected 'max X' in output:\n{out}"
        assert "min X" in out, f"Expected 'min X' in output:\n{out}"

    def test_tc_curve_g_004_auc_value(self):
        """
        TC-CURVE-G-004:
        global auc=yes on linear data (y=2x, x=0..20) must report AUC = 400.
        Trapezoid rule on exact linear data yields 400 exactly.
        """
        r = run("jrc_curve_properties.py", data("test_global.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "AUC" in out, f"Expected 'AUC' in output:\n{out}"
        assert "400" in out, \
            f"Expected value '400' for AUC of linear data (y=2x, x=0..20):\n{out}"

    def test_tc_curve_g_005_hysteresis(self):
        """
        TC-CURVE-G-005:
        hysteresis=yes with two-armed triangle data must exit 0
        and report "Hysteresis" in output.
        """
        r = run("jrc_curve_properties.py", data("test_hysteresis.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Hysteresis" in combined(r), \
            f"Expected 'Hysteresis' in output:\n{combined(r)}"


class TestCurvePhase:

    def test_tc_curve_p_001_phase_max_y(self):
        """
        TC-CURVE-P-001:
        per-phase max_y in [phase.loading] must report "max Y [loading]" in output.
        """
        r = run("jrc_curve_properties.py", data("test_phase.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "max Y [loading]" in combined(r), \
            f"Expected 'max Y [loading]' in output:\n{combined(r)}"

    def test_tc_curve_p_002_phase_auc(self):
        """
        TC-CURVE-P-002:
        per-phase auc in [phase.loading] must report "AUC [loading]" in output.
        """
        r = run("jrc_curve_properties.py", data("test_phase.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "AUC [loading]" in combined(r), \
            f"Expected 'AUC [loading]' in output:\n{combined(r)}"

    def test_tc_curve_p_003_multiple_phases(self):
        """
        TC-CURVE-P-003:
        Multiple [phase.NAME] sections in one run must reference
        all declared phase names in the output.
        """
        r = run("jrc_curve_properties.py", data("test_phase.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "loading" in out, f"Expected 'loading' in output:\n{out}"
        assert "unloading" in out, f"Expected 'unloading' in output:\n{out}"


class TestCurveSlope:

    def test_tc_curve_s_001_overall_slope(self):
        """
        TC-CURVE-S-001:
        overall=yes must report "slope overall" in output.
        """
        r = run("jrc_curve_properties.py", data("test_slope.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "slope overall" in combined(r), \
            f"Expected 'slope overall' in output:\n{combined(r)}"

    def test_tc_curve_s_002_secant_slope(self):
        """
        TC-CURVE-S-002:
        secant=yes must report "slope secant" in output.
        """
        r = run("jrc_curve_properties.py", data("test_slope.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "slope secant" in combined(r), \
            f"Expected 'slope secant' in output:\n{combined(r)}"

    def test_tc_curve_s_003_at_x_slope(self):
        """
        TC-CURVE-S-003:
        at_x_N key must report "slope at x=" in output.
        """
        r = run("jrc_curve_properties.py", data("test_slope.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "slope at x=" in combined(r), \
            f"Expected 'slope at x=' in output:\n{combined(r)}"


class TestCurveQuery:

    def test_tc_curve_q_001_y_at_x(self):
        """
        TC-CURVE-Q-001:
        y_at_x_N query must report "Y at x=" in output.
        """
        r = run("jrc_curve_properties.py", data("test_query.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Y at x=" in combined(r), \
            f"Expected 'Y at x=' in output:\n{combined(r)}"

    def test_tc_curve_q_002_x_at_y(self):
        """
        TC-CURVE-Q-002:
        x_at_y_N query must report "X at y=" in output.
        """
        r = run("jrc_curve_properties.py", data("test_query.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "X at y=" in combined(r), \
            f"Expected 'X at y=' in output:\n{combined(r)}"

    def test_tc_curve_q_003_y_at_rel_x(self):
        """
        TC-CURVE-Q-003:
        y_at_rel_x_N query must report a label containing "Y at" and "%" in output.
        The label format is "Y at x=<ref><+pct>%" (e.g. "Y at x=10+10%").
        """
        r = run("jrc_curve_properties.py", data("test_query.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Y at " in out and "%" in out, \
            f"Expected 'Y at ...' with '%' in output for y_at_rel_x:\n{out}"

    def test_tc_curve_q_004_width_at_y(self):
        """
        TC-CURVE-Q-004:
        width_at_y query on triangle data (y=10x ascending, y=9x descending)
        at y=50. Analytical derivation:
          ascending crossing  x = 50/10 = 5
          descending crossing x = 50/9  = 5.5556
          width = 50/9 - 5 = 5/9 = 0.5556 (exact)
        """
        r = run("jrc_curve_properties.py", data("test_width.cfg"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"width at y=50\.0\s*:\s*([\d.]+)", combined(r))
        assert m, f"width at y=50.0 not found in output:\n{combined(r)}"
        width = float(m.group(1))
        print(f"  width: expected 0.5556 ± 0.001, got {width}")
        assert abs(width - 5.0 / 9.0) < 0.001, \
            f"Expected width = 5/9 ± 0.001, got {width}"

    def test_tc_curve_q_005_tangency_annotation(self):
        """
        TC-CURVE-Q-005:
        x_at_y with mode=all at the triangle apex (y=100) must report the
        touch point once, annotated 'tangency' (the curve reaches y=100
        without crossing it).
        """
        r = run("jrc_curve_properties.py", data("test_tangency.cfg"))
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "X at y=100.0" in out, \
            f"Expected 'X at y=100.0' in output:\n{out}"
        assert "tangency" in out, \
            f"Expected 'tangency' annotation for apex touch point:\n{out}"

    def test_tc_curve_q_006_show_markers_plot(self):
        """
        TC-CURVE-Q-006:
        x_at_y_N.show and width_at_y_N.show with plot=yes must exercise the
        marker/segment drawing paths and create the plot PDF.
        """
        expected = os.path.join(DATA_DIR, "width_plot.pdf")
        if os.path.exists(expected):
            os.remove(expected)
        r = run("jrc_curve_properties.py", data("test_width.cfg"))
        assert r.returncode == 0, combined(r)
        assert os.path.isfile(expected), \
            f"Expected plot PDF not found: {expected}"


class TestCurveTransform:

    def test_tc_curve_t_001_y_scale(self):
        """
        TC-CURVE-T-001:
        y_scale in [transform] must exit 0 and report "Y scale" in output.
        """
        r = run("jrc_curve_properties.py", data("test_transform.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Y scale" in combined(r), \
            f"Expected 'Y scale' in output:\n{combined(r)}"

    def test_tc_curve_t_002_y_offset_x(self):
        """
        TC-CURVE-T-002:
        y_offset_x in [transform] must report "Y offset" in output.
        """
        r = run("jrc_curve_properties.py", data("test_transform.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Y offset" in combined(r), \
            f"Expected 'Y offset' in output:\n{combined(r)}"

    def test_tc_curve_t_003_x_transforms(self):
        """
        TC-CURVE-T-003:
        x_scale=2 and x_offset=10 on linear data (y=2x).
        Analytical derivation: x' = 2x - 10, so y = x' + 10 and the
        overall OLS slope on the transformed axis = 1.000 (exact).
        """
        r = run("jrc_curve_properties.py", data("test_xtransform.cfg"))
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "X scale" in out, f"Expected 'X scale' in output:\n{out}"
        assert "X offset" in out, f"Expected 'X offset' in output:\n{out}"
        m = re.search(r"slope overall\s*:\s*([-\d.]+)", out)
        assert m, f"slope overall not found in output:\n{out}"
        slope = float(m.group(1))
        print(f"  slope on transformed X: expected 1.000 ± 0.001, got {slope}")
        assert abs(slope - 1.000) < 0.001, \
            f"Expected slope = 1.000 ± 0.001 after x_scale=2, got {slope}"


class TestCurveResample:

    def test_tc_curve_r_001_resample_inflection(self):
        """
        TC-CURVE-R-001:
        resample=yes on non-uniformly sampled sine data (x = 0..2pi,
        spacing 0.05–0.25). The sine inflection lies at x = pi exactly;
        with uniform-grid resampling the reported inflection must be at
        pi ± 0.1 and no non-uniform spacing warning may be issued.
        """
        r = run("jrc_curve_properties.py", data("test_resample.cfg"))
        assert r.returncode == 0, combined(r)
        out = combined(r)
        m = re.search(r"inflection 1\s*:\s*x = ([-\d.]+)", out)
        assert m, f"inflection 1 not found in output:\n{out}"
        xi = float(m.group(1))
        print(f"  inflection: expected pi ± 0.1 ({math.pi:.4f}), got {xi}")
        assert abs(xi - math.pi) < 0.1, \
            f"Expected inflection at pi ± 0.1, got {xi}"
        assert "non-uniform" not in out, \
            f"Non-uniform spacing warning should be suppressed by resample:\n{out}"


class TestCurveTransitions:

    def test_tc_curve_i_001_inflections(self):
        """
        TC-CURVE-I-001:
        inflections detection on sine data must report "inflection" in output.
        The sine curve has an inflection at x = pi (sign change of second derivative).
        """
        r = run("jrc_curve_properties.py", data("test_transitions.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "inflection" in combined(r), \
            f"Expected 'inflection' in output:\n{combined(r)}"

    def test_tc_curve_i_002_yield_point(self):
        """
        TC-CURVE-I-002:
        yield point detection on sine data (threshold = 0.5 x max slope) must
        report "yield point" in output. The yield occurs at x = pi/3 where
        cos(x) = 0.5 x max_slope(=1.0).
        """
        r = run("jrc_curve_properties.py", data("test_transitions.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "yield point" in combined(r), \
            f"Expected 'yield point' in output:\n{combined(r)}"


class TestCurveOutputFiles:

    def test_tc_curve_o_001_results_file_created(self):
        """
        TC-CURVE-O-001:
        After a successful run with results_file specified, a results .txt
        file must be created at the given path.
        """
        expected = os.path.join(DATA_DIR, "oq_test_results.txt")
        if os.path.exists(expected):
            os.remove(expected)
        r = run("jrc_curve_properties.py", data("test_plot.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert os.path.isfile(expected), \
            f"Expected results file not found: {expected}"

    def test_tc_curve_o_002_plot_pdf_created(self):
        """
        TC-CURVE-O-002:
        With plot=yes and plot_file set, a PDF must be created at the
        specified path in the config directory.
        """
        expected = os.path.join(DATA_DIR, "oq_test_plot.pdf")
        if os.path.exists(expected):
            os.remove(expected)
        r = run("jrc_curve_properties.py", data("test_plot.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert os.path.isfile(expected), \
            f"Expected plot PDF not found: {expected}"

    def test_tc_curve_o_003_debug_d2y_csv_created(self):
        """
        TC-CURVE-O-003:
        With [debug] d2y=yes and d2y.phase=full, a debug CSV named
        <cfg_stem>_debug_d2y_full.csv must be created in the config directory.
        """
        expected = os.path.join(DATA_DIR, "test_debug_debug_d2y_full.csv")
        if os.path.exists(expected):
            os.remove(expected)
        r = run("jrc_curve_properties.py", data("test_debug.cfg"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert os.path.isfile(expected), \
            f"Expected debug d2y CSV not found: {expected}"


class TestCurveNumeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_curve_n_001_auc_exact(self):
        """
        TC-CURVE-N-001:
        AUC for linear.csv (y=2x, x=0..20) = 400.0 ± 0.5.
        Analytical derivation (trapezoid rule on exact linear data):
          AUC = integral(2x, 0, 20) = [x²]_0^20 = 400 exactly.
        """
        r = run("jrc_curve_properties.py", data("test_global.cfg"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"AUC\s*:\s*([\d.]+)", combined(r))
        assert m, f"AUC not found in output:\n{combined(r)}"
        auc = float(m.group(1))
        print(f"  AUC: expected 400.0 ± 0.5, got {auc}")
        assert abs(auc - 400.0) < 0.5, \
            f"Expected AUC = 400.0 ± 0.5, got {auc}"

    def test_tc_curve_n_002_overall_slope_exact(self):
        """
        TC-CURVE-N-002:
        Overall OLS slope for linear.csv (y=2x) = 2.000 ± 0.001.
        Analytical derivation: b1 = Sxy/Sxx = 2.000 for y=2x.
        """
        r = run("jrc_curve_properties.py", data("test_slope.cfg"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"slope overall\s*:\s*([-\d.]+)", combined(r))
        assert m, f"slope overall not found in output:\n{combined(r)}"
        slope = float(m.group(1))
        print(f"  slope overall: expected 2.000 ± 0.001, got {slope}")
        assert abs(slope - 2.000) < 0.001, \
            f"Expected slope overall = 2.000 ± 0.001, got {slope}"

    def test_tc_curve_n_003_y_at_x_exact(self):
        """
        TC-CURVE-N-003:
        Y at x=5.0 for linear.csv (y=2x) = 10.0 ± 0.01.
        Analytical derivation: y = 2*5 = 10.0 (exact point in data).
        """
        r = run("jrc_curve_properties.py", data("test_query.cfg"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"Y at x=5\.0\s*:\s*([-\d.]+)", combined(r))
        assert m, f"Y at x=5.0 not found in output:\n{combined(r)}"
        y_val = float(m.group(1))
        print(f"  y_at_x (x=5.0): expected 10.0 ± 0.01, got {y_val}")
        assert abs(y_val - 10.0) < 0.01, \
            f"Expected Y at x=5.0 = 10.0 ± 0.01, got {y_val}"
