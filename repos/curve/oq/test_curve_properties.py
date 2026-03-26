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

  TC-CURVE-T-001  y_scale transform -> exit 0, "Y scale" in output
  TC-CURVE-T-002  y_offset_x transform -> "Y offset" in output

  TC-CURVE-I-001  inflections on sine data -> "inflection" in output
  TC-CURVE-I-002  yield point on sine data -> "yield point" in output

  TC-CURVE-O-001  results .txt file created after successful run
  TC-CURVE-O-002  plot PDF created when plot=yes and plot_file specified
  TC-CURVE-O-003  debug d2y CSV created when [debug] d2y=yes
"""

import os

from conftest import DATA_DIR, run, combined, data


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
