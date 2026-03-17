#!/usr/bin/env python3
"""
Generate all OQ test data files for the JR Validated Environment OQ suite.

Run this script once to create / refresh all files in oq/data/.
Uses only stdlib + numpy (available in the project venv).

Usage:
    ~/.venvs/MyProject/bin/python oq/generate_test_data.py
"""

import os
import csv
import numpy as np

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(DATA_DIR, exist_ok=True)


def write_csv(filename, rows, header=("id", "value")):
    path = os.path.join(DATA_DIR, filename)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  wrote {filename}  ({len(rows)} rows)")


# ---------------------------------------------------------------------------
# 1. normal_n30_mean10_sd1_seed42.csv
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
vals = rng.normal(10.0, 1.0, 30)
write_csv(
    "normal_n30_mean10_sd1_seed42.csv",
    [(i + 1, round(v, 6)) for i, v in enumerate(vals)],
)

# ---------------------------------------------------------------------------
# 2. skewed_n30_lognormal_seed42.csv
# sdlog=1.2 ensures e1071 skewness > 1.0 in R, reliably triggering non-normal path
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
vals_ln = rng.lognormal(mean=2.0, sigma=1.2, size=30)
write_csv(
    "skewed_n30_lognormal_seed42.csv",
    [(i + 1, round(v, 6)) for i, v in enumerate(vals_ln)],
)

# ---------------------------------------------------------------------------
# 3. outlier_n30_seed42.csv  — same as normal but row 15 (1-indexed) = 15.0
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
vals_out = rng.normal(10.0, 1.0, 30)
vals_out[14] = 15.0  # inject 5-sigma outlier at position 15 (0-indexed: 14)
write_csv(
    "outlier_n30_seed42.csv",
    [(i + 1, round(v, 6)) for i, v in enumerate(vals_out)],
)

# ---------------------------------------------------------------------------
# 4. bland_altman_method1_seed42.csv
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
m1 = rng.normal(10.0, 1.0, 25)
write_csv(
    "bland_altman_method1_seed42.csv",
    [(i + 1, round(v, 6)) for i, v in enumerate(m1)],
)

# ---------------------------------------------------------------------------
# 5. bland_altman_method2_seed42.csv  — method1 + N(0, 0.2) noise, seed 99
# ---------------------------------------------------------------------------
# method1 values (same seed=42 → same draws)
rng = np.random.default_rng(42)
m1_base = rng.normal(10.0, 1.0, 25)
# add bias noise with seed 99
rng99 = np.random.default_rng(99)
noise = rng99.normal(0.0, 0.2, 25)
m2 = m1_base + noise
write_csv(
    "bland_altman_method2_seed42.csv",
    [(i + 1, round(v, 6)) for i, v in enumerate(m2)],
)

# ---------------------------------------------------------------------------
# 6. method1_short.csv  — first 10 rows of method1 (for TC-BA-003)
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
m1_full = rng.normal(10.0, 1.0, 25)
write_csv(
    "method1_short.csv",
    [(i + 1, round(v, 6)) for i, v in enumerate(m1_full[:10])],
)

# ---------------------------------------------------------------------------
# 7. weibull_n20_seed42.csv  — Weibull(shape=2, scale=1000), 15 failures + 5 censored
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
# numpy Weibull: rng.weibull(shape) * scale
times_w = rng.weibull(2.0, 20) * 1000.0
status_w = [1] * 15 + [0] * 5  # first 15 failures, last 5 censored
rows_w = [(i + 1, round(t, 2), s) for i, (t, s) in enumerate(zip(times_w, status_w))]
path_w = os.path.join(DATA_DIR, "weibull_n20_seed42.csv")
with open(path_w, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "cycles", "status"])
    w.writerows(rows_w)
print(f"  wrote weibull_n20_seed42.csv  (20 rows, 3 cols)")

# ---------------------------------------------------------------------------
# 8. all_censored.csv  — all status=0, same times (for TC-WEIB-002)
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
times_ac = rng.weibull(2.0, 20) * 1000.0
rows_ac = [(i + 1, round(t, 2), 0) for i, t in enumerate(times_ac)]
path_ac = os.path.join(DATA_DIR, "all_censored.csv")
with open(path_ac, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "cycles", "status"])
    w.writerows(rows_ac)
print("  wrote all_censored.csv  (20 rows, all status=0)")

# ---------------------------------------------------------------------------
# 9. neg_times.csv  — one negative time value (for TC-WEIB-003)
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
times_neg = rng.weibull(2.0, 20) * 1000.0
times_neg[0] = -50.0  # inject negative time in first row
rows_neg = [(i + 1, round(t, 2), 1) for i, t in enumerate(times_neg)]
path_neg = os.path.join(DATA_DIR, "neg_times.csv")
with open(path_neg, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "cycles", "status"])
    w.writerows(rows_neg)
print("  wrote neg_times.csv  (20 rows, row 1 negative time)")

# ---------------------------------------------------------------------------
# 10. bad_status.csv  — status values in {0, 1, 2} (for TC-WEIB-004)
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
times_bs = rng.weibull(2.0, 20) * 1000.0
status_bs = [1, 0, 2, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1]
rows_bs = [(i + 1, round(t, 2), s) for i, (t, s) in enumerate(zip(times_bs, status_bs))]
path_bs = os.path.join(DATA_DIR, "bad_status.csv")
with open(path_bs, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "cycles", "status"])
    w.writerows(rows_bs)
print("  wrote bad_status.csv  (20 rows, status includes 2)")

# ---------------------------------------------------------------------------
# 11. convert_multicolumn.txt  — tab-delimited, 3 header lines, cols id/ForceN/Temp
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
force_vals = rng.normal(100.0, 5.0, 20)
temp_vals = rng.normal(23.0, 0.5, 20)
path_mc = os.path.join(DATA_DIR, "convert_multicolumn.txt")
with open(path_mc, "w") as f:
    f.write("Test Equipment: JR Force Gauge v1.0\n")
    f.write("Date: 2026-03-15\n")
    f.write("Operator: Joep Rous\n")
    f.write("id\tForceN\tTemp\n")
    for i, (fv, tv) in enumerate(zip(force_vals, temp_vals)):
        f.write(f"{i+1}\t{fv:.4f}\t{tv:.4f}\n")
print("  wrote convert_multicolumn.txt  (3 header + 20 data rows, tab-delimited)")

# ---------------------------------------------------------------------------
# 12. convert_singlecolumn.txt  — 200 numeric values, one per line
# ---------------------------------------------------------------------------
rng = np.random.default_rng(42)
single_vals = rng.normal(50.0, 10.0, 200)
path_sc = os.path.join(DATA_DIR, "convert_singlecolumn.txt")
with open(path_sc, "w") as f:
    for v in single_vals:
        f.write(f"{v:.6f}\n")
print("  wrote convert_singlecolumn.txt  (200 lines)")

print("\nAll test data files generated successfully.")

# ---------------------------------------------------------------------------
# 13. doe_factors_3f_2level.csv  — 3 factors, 2 levels (full2 design input)
# ---------------------------------------------------------------------------
path = os.path.join(DATA_DIR, "doe_factors_3f_2level.csv")
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["name", "low", "high"])
    w.writerows([
        ["Temperature", 160, 200],
        ["Pressure",    2,   5],
        ["DwellTime",   3,   8],
    ])
print("  wrote doe_factors_3f_2level.csv  (3 rows)")

# ---------------------------------------------------------------------------
# 14. doe_factors_1f.csv  — 1 factor only (error test: too few factors)
# ---------------------------------------------------------------------------
path = os.path.join(DATA_DIR, "doe_factors_1f.csv")
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["name", "low", "high"])
    w.writerows([
        ["Temperature", 160, 200],
    ])
print("  wrote doe_factors_1f.csv  (1 row — error test)")

# ---------------------------------------------------------------------------
# 15. doe_factors_2f_3level.csv  — 2 factors, 3 levels (full3 design input)
# ---------------------------------------------------------------------------
path = os.path.join(DATA_DIR, "doe_factors_2f_3level.csv")
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["name", "low", "mid", "high"])
    w.writerows([
        ["Temperature", 160, 180, 200],
        ["Pressure",    2,   3.5, 5],
    ])
print("  wrote doe_factors_2f_3level.csv  (2 rows)")

# ---------------------------------------------------------------------------
# 16. doe_factors_4f_2level.csv  — 4 factors, 2 levels (fractional / full2)
# ---------------------------------------------------------------------------
path = os.path.join(DATA_DIR, "doe_factors_4f_2level.csv")
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["name", "low", "high"])
    w.writerows([
        ["Temperature", 160, 200],
        ["Pressure",    2,   5],
        ["DwellTime",   3,   8],
        ["FlowRate",    10,  30],
    ])
print("  wrote doe_factors_4f_2level.csv  (4 rows)")

# ---------------------------------------------------------------------------
# 17. doe_factors_6f.csv  — 6 factors (Plackett-Burman design input)
# ---------------------------------------------------------------------------
path = os.path.join(DATA_DIR, "doe_factors_6f.csv")
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["name", "low", "high"])
    w.writerows([
        ["A", 0, 1],
        ["B", 0, 1],
        ["C", 0, 1],
        ["D", 0, 1],
        ["E", 0, 1],
        ["F", 0, 1],
    ])
print("  wrote doe_factors_6f.csv  (6 rows)")

# ---------------------------------------------------------------------------
# 18. doe_results_full2_3f.csv  — completed 2^3 full factorial results
#     Model: SealStrength_N = 20 + 5*T + 3*P + 1*D + 2*T*P + noise
# ---------------------------------------------------------------------------
lines = [
    "# jrc_doe_design: type=full2, response=SealStrength_N",
    "run,std_order,is_centre,Temperature,Pressure,DwellTime,SealStrength_N",
    "1,1,FALSE,160,2,3,13.3",
    "2,2,FALSE,200,2,3,18.8",
    "3,3,FALSE,160,5,3,15.4",
    "4,4,FALSE,200,5,3,29.1",
    "5,5,FALSE,160,2,8,14.7",
    "6,6,FALSE,200,2,8,21.2",
    "7,7,FALSE,160,5,8,16.9",
    "8,8,FALSE,200,5,8,31.3",
]
path = os.path.join(DATA_DIR, "doe_results_full2_3f.csv")
with open(path, "w") as f:
    f.write("\n".join(lines) + "\n")
print("  wrote doe_results_full2_3f.csv  (8 rows)")

# ---------------------------------------------------------------------------
# 19. doe_results_full2_3f_cp.csv  — same as above + 3 centre point rows
# ---------------------------------------------------------------------------
lines_cp = [
    "# jrc_doe_design: type=full2, response=SealStrength_N",
    "run,std_order,is_centre,Temperature,Pressure,DwellTime,SealStrength_N",
    "1,1,FALSE,160,2,3,13.3",
    "2,2,FALSE,200,2,3,18.8",
    "3,3,FALSE,160,5,3,15.4",
    "4,4,FALSE,200,5,3,29.1",
    "5,5,FALSE,160,2,8,14.7",
    "6,6,FALSE,200,2,8,21.2",
    "7,7,FALSE,160,5,8,16.9",
    "8,8,FALSE,200,5,8,31.3",
    "9,,TRUE,180,3.5,5.5,21.1",
    "10,,TRUE,180,3.5,5.5,20.8",
    "11,,TRUE,180,3.5,5.5,21.4",
]
path = os.path.join(DATA_DIR, "doe_results_full2_3f_cp.csv")
with open(path, "w") as f:
    f.write("\n".join(lines_cp) + "\n")
print("  wrote doe_results_full2_3f_cp.csv  (8 factorial + 3 centre point rows)")

# ---------------------------------------------------------------------------
# 20. doe_results_full3_2f.csv  — completed 3^2 full factorial results
#     Model: SealStrength_N = 20 + 5*T_coded + 3*P_coded + 1*T_coded^2 + noise
# ---------------------------------------------------------------------------
lines_f3 = [
    "# jrc_doe_design: type=full3, response=SealStrength_N",
    "run,std_order,is_centre,Temperature,Pressure,SealStrength_N",
    "1,1,FALSE,160,2,13.2",
    "2,2,FALSE,180,2,16.9",
    "3,3,FALSE,200,2,23.3",
    "4,4,FALSE,160,3.5,15.8",
    "5,5,FALSE,180,3.5,20.1",
    "6,6,FALSE,200,3.5,26.2",
    "7,7,FALSE,160,5,18.7",
    "8,8,FALSE,180,5,23.1",
    "9,9,FALSE,200,5,28.9",
]
path = os.path.join(DATA_DIR, "doe_results_full3_2f.csv")
with open(path, "w") as f:
    f.write("\n".join(lines_f3) + "\n")
print("  wrote doe_results_full3_2f.csv  (9 rows)")

# ---------------------------------------------------------------------------
# 21. doe_results_pb_6f.csv  — completed Plackett-Burman 8-run results
#     PB8 matrix (7 cols), 6 factors used (A-F). Strength = 10 + 3*A + 1*B + noise
# ---------------------------------------------------------------------------
lines_pb = [
    "# jrc_doe_design: type=pb, response=Strength",
    "run,std_order,is_centre,A,B,C,D,E,F,Strength",
    "1,1,FALSE,1,1,1,0,1,0,14.1",
    "2,2,FALSE,0,1,1,1,0,1,7.9",
    "3,3,FALSE,0,0,1,1,1,0,6.2",
    "4,4,FALSE,1,0,0,1,1,1,11.9",
    "5,5,FALSE,0,1,0,0,1,1,8.1",
    "6,6,FALSE,1,0,1,0,0,1,12.2",
    "7,7,FALSE,1,1,0,1,0,0,13.9",
    "8,8,FALSE,0,0,0,0,0,0,6.1",
]
path = os.path.join(DATA_DIR, "doe_results_pb_6f.csv")
with open(path, "w") as f:
    f.write("\n".join(lines_pb) + "\n")
print("  wrote doe_results_pb_6f.csv  (8 rows)")

# ---------------------------------------------------------------------------
# 22. doe_results_missing_response.csv  — rows 3, 5, 7 have empty response
# ---------------------------------------------------------------------------
lines_miss = [
    "# jrc_doe_design: type=full2, response=SealStrength_N",
    "run,std_order,is_centre,Temperature,Pressure,DwellTime,SealStrength_N",
    "1,1,FALSE,160,2,3,13.3",
    "2,2,FALSE,200,2,3,18.8",
    "3,3,FALSE,160,5,3,",
    "4,4,FALSE,200,5,3,29.1",
    "5,5,FALSE,160,2,8,",
    "6,6,FALSE,200,2,8,21.2",
    "7,7,FALSE,160,5,8,",
    "8,8,FALSE,200,5,8,31.3",
]
path = os.path.join(DATA_DIR, "doe_results_missing_response.csv")
with open(path, "w") as f:
    f.write("\n".join(lines_miss) + "\n")
print("  wrote doe_results_missing_response.csv  (8 rows, 3 empty response values)")

print("\nAll DoE test data files generated successfully.")
