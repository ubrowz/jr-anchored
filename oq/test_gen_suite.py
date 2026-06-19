"""
OQ test suite — Data generation scripts.

Covers: jrc_gen_normal, jrc_gen_lognormal, jrc_gen_sqrt,
        jrc_gen_boxcox, jrc_gen_uniform
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import os
import csv
from conftest import run, combined, DATA_DIR


# ===========================================================================
# jrc_gen_normal (TC-GEN-N-001 .. 005)
# ===========================================================================

class TestGenNormal:

    def test_tc_gen_n_001_reproducible_with_seed(self, tmp_path):
        """TC-GEN-N-001: n=50, mean=10, sd=1, seed=42 → correct filename, 51 lines"""
        r = run("jrc_gen_normal.R", "50", "10.0", "1.0", str(tmp_path), "42")
        assert r.returncode == 0
        expected = tmp_path / "normal_n50_mean10_sd1_seed42.csv"
        assert expected.exists(), f"Expected output file not found: {expected}"
        lines = expected.read_text().splitlines()
        assert len(lines) == 51  # header + 50 data rows

    def test_tc_gen_n_002_correct_column_names(self, tmp_path):
        """TC-GEN-N-002: CSV header is id,value"""
        run("jrc_gen_normal.R", "50", "10.0", "1.0", str(tmp_path), "42")
        f = tmp_path / "normal_n50_mean10_sd1_seed42.csv"
        if f.exists():
            header = f.read_text().splitlines()[0]
            assert header.startswith("id") and "value" in header

    def test_tc_gen_n_003_nonexistent_output_dir(self):
        """TC-GEN-N-003: nonexistent output path → non-zero exit"""
        r = run("jrc_gen_normal.R", "50", "10.0", "1.0", "/nonexistent/path/xyz", "42")
        assert r.returncode != 0

    def test_tc_gen_n_004_sd_le_zero(self, tmp_path):
        """TC-GEN-N-004: sd=0 → non-zero exit"""
        r = run("jrc_gen_normal.R", "50", "10.0", "0", str(tmp_path), "42")
        assert r.returncode != 0

    def test_tc_gen_n_005_missing_arguments(self):
        """TC-GEN-N-005: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_gen_normal.R", "50", "10.0")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_gen_lognormal (TC-GEN-LN-001 .. 004)
# ===========================================================================

class TestGenLognormal:

    def test_tc_gen_ln_001_reproducible_with_seed(self, tmp_path):
        """TC-GEN-LN-001: n=50, seed=42 → file created, all values > 0"""
        r = run("jrc_gen_lognormal.R", "50", "2.0", "0.5", str(tmp_path), "42")
        assert r.returncode == 0
        # Find the output file
        files = list(tmp_path.glob("*.csv"))
        assert len(files) == 1
        with open(files[0]) as f:
            reader = csv.DictReader(f)
            for row in reader:
                assert float(row["value"]) > 0, "Log-normal values must be strictly positive"

    def test_tc_gen_ln_002_correct_column_names(self, tmp_path):
        """TC-GEN-LN-002: CSV header is id,value"""
        run("jrc_gen_lognormal.R", "50", "2.0", "0.5", str(tmp_path), "42")
        files = list(tmp_path.glob("*.csv"))
        if files:
            header = files[0].read_text().splitlines()[0]
            assert "id" in header and "value" in header

    def test_tc_gen_ln_003_sdlog_le_zero(self, tmp_path):
        """TC-GEN-LN-003: sdlog=0 → non-zero exit"""
        r = run("jrc_gen_lognormal.R", "50", "2.0", "0", str(tmp_path), "42")
        assert r.returncode != 0

    def test_tc_gen_ln_004_missing_arguments(self):
        """TC-GEN-LN-004: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_gen_lognormal.R", "50", "2.0")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_gen_sqrt (TC-GEN-SQ-001 .. 004)
# ===========================================================================

class TestGenSqrt:

    def test_tc_gen_sq_001_reproducible_with_seed(self, tmp_path):
        """TC-GEN-SQ-001: n=50, df=3, scale=1, seed=42 → file created, all values ≥ 0"""
        r = run("jrc_gen_sqrt.R", "50", "3", "1.0", str(tmp_path), "42")
        assert r.returncode == 0
        files = list(tmp_path.glob("*.csv"))
        assert len(files) == 1
        with open(files[0]) as f:
            reader = csv.DictReader(f)
            for row in reader:
                assert float(row["value"]) >= 0, "Chi-squared scaled values must be non-negative"

    def test_tc_gen_sq_002_correct_column_names(self, tmp_path):
        """TC-GEN-SQ-002: CSV header is id,value"""
        run("jrc_gen_sqrt.R", "50", "3", "1.0", str(tmp_path), "42")
        files = list(tmp_path.glob("*.csv"))
        if files:
            header = files[0].read_text().splitlines()[0]
            assert "id" in header and "value" in header

    def test_tc_gen_sq_003_df_le_zero(self, tmp_path):
        """TC-GEN-SQ-003: df=0 → non-zero exit"""
        r = run("jrc_gen_sqrt.R", "50", "0", "1.0", str(tmp_path), "42")
        assert r.returncode != 0

    def test_tc_gen_sq_004_missing_arguments(self):
        """TC-GEN-SQ-004: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_gen_sqrt.R", "50", "3")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_gen_boxcox (TC-GEN-BC-001 .. 004)
# ===========================================================================

class TestGenBoxcox:

    def test_tc_gen_bc_001_reproducible_with_seed(self, tmp_path):
        """TC-GEN-BC-001: Weibull n=50, shape=2, scale=1000, seed=42 → file, all values > 0"""
        r = run("jrc_gen_boxcox.R", "50", "2.0", "1000.0", str(tmp_path), "42")
        assert r.returncode == 0
        files = list(tmp_path.glob("*.csv"))
        assert len(files) == 1
        with open(files[0]) as f:
            reader = csv.DictReader(f)
            for row in reader:
                assert float(row["value"]) > 0, "Weibull values must be strictly positive"

    def test_tc_gen_bc_002_correct_column_names(self, tmp_path):
        """TC-GEN-BC-002: CSV header is id,value"""
        run("jrc_gen_boxcox.R", "50", "2.0", "1000.0", str(tmp_path), "42")
        files = list(tmp_path.glob("*.csv"))
        if files:
            header = files[0].read_text().splitlines()[0]
            assert "id" in header and "value" in header

    def test_tc_gen_bc_003_shape_le_zero(self, tmp_path):
        """TC-GEN-BC-003: shape=0 → non-zero exit"""
        r = run("jrc_gen_boxcox.R", "50", "0", "1000.0", str(tmp_path), "42")
        assert r.returncode != 0

    def test_tc_gen_bc_004_missing_arguments(self):
        """TC-GEN-BC-004: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_gen_boxcox.R", "50", "2.0")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_gen_uniform (TC-GEN-U-001 .. 004)
# ===========================================================================

class TestGenUniform:

    def test_tc_gen_u_001_reproducible_with_seed(self, tmp_path):
        """TC-GEN-U-001: n=50, min=0, max=10, seed=42 → file, all values in [0, 10]"""
        r = run("jrc_gen_uniform.R", "50", "0.0", "10.0", str(tmp_path), "42")
        assert r.returncode == 0
        files = list(tmp_path.glob("*.csv"))
        assert len(files) == 1
        with open(files[0]) as f:
            reader = csv.DictReader(f)
            for row in reader:
                v = float(row["value"])
                assert 0.0 <= v <= 10.0, f"Uniform value {v} out of [0, 10]"

    def test_tc_gen_u_002_correct_column_names(self, tmp_path):
        """TC-GEN-U-002: CSV header is id,value"""
        run("jrc_gen_uniform.R", "50", "0.0", "10.0", str(tmp_path), "42")
        files = list(tmp_path.glob("*.csv"))
        if files:
            header = files[0].read_text().splitlines()[0]
            assert "id" in header and "value" in header

    def test_tc_gen_u_003_max_le_min(self, tmp_path):
        """TC-GEN-U-003: max=5 < min=10 → non-zero exit"""
        r = run("jrc_gen_uniform.R", "50", "10.0", "5.0", str(tmp_path), "42")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "max" in out or "min" in out

    def test_tc_gen_u_004_missing_arguments(self):
        """TC-GEN-U-004: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_gen_uniform.R", "50", "0.0")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()
