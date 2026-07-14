# Package → OQ Suite Matrix

This file is the **single source of truth** for which OQ suites must be re-run when an
R package version changes. The machine-readable version of this mapping is embedded in
`admin/admin_oq_all_smart` (the `get_affected` and `resolve_alias` functions). Both must
be kept in sync.

**When to update:** any time an R script is added, removed, or has its `library()` calls
changed. Run `grep -rn "library(" R/ repos/*/R/` to audit current imports.

---

## Matrix: directly imported packages

`✓` = run that module's full suite. `file(s)` = run only those specific test files.
`—` = package not used in any script in this module.

| Package | ver | core:core | core:diag | core:doe | core:ss | core:stat | as | cap | corr | msa | rdt | shelf_life | spc |
|---------|-----|:---------:|:---------:|:--------:|:-------:|:---------:|:--:|:---:|:----:|:---:|:---:|:----------:|:---:|
| ggplot2 | 4.0.3 | test_core | — | test_doe_suite | — | test_statistical_suite | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| base64enc | 0.1-6 | — | — | test_doe_suite | — | test_statistical_suite | — | ✓ | — | test_msa_gauge_rr | test_rdt_verify | ✓ | imr,p,xbar_r,xbar_s |
| e1071 | 1.7-17 | — | ✓ | — | ✓ | test_statistical_suite | — | — | — | — | — | — | — |
| MASS | 7.3-65 | — | ✓ | — | ✓ | test_statistical_suite | — | — | — | — | — | — | — |
| tolerance | 3.0.0 | — | — | — | ✓ | test_statistical_suite | — | — | — | — | — | — | — |
| nortest | 1.0-4 | — | ✓ | — | — | — | — | — | — | — | — | — | — |
| outliers | 0.15 | — | ✓ | — | — | — | — | — | — | — | — | — | — |
| FrF2 | 2.3-5 | — | — | test_doe_suite | — | — | — | — | — | — | — | — | — |
| DoE.base | 1.2-5 | — | — | test_doe_suite | — | — | — | — | — | — | — | — | — |

**Column key:**
- `core:core` → `oq/test_core.py`
- `core:diag` → `oq/test_diagnostic_suite.py` (normality, outliers, capability, descriptive)
- `core:doe` → `oq/test_doe_suite.py` (doe_design, doe_analyse)
- `core:ss` → `oq/test_ss_suite.py` (ss_attr, ss_attr_check, ss_attr_ci; discrete+others are base R)
- `core:stat` → `oq/test_statistical_suite.py` (bland_altman, weibull, verify_attr, verify_discrete)

Note: `oq/test_gen_suite.py` and `oq/test_convert_suite.py` are never in the matrix — all
gen_* scripts and convert scripts use only base R.

### Partially-affected module tests

When a column shows specific filenames rather than `✓`, run only those test files:

| Package | Module | Test files |
|---------|--------|------------|
| base64enc | msa | `test_msa_gauge_rr.py` |
| base64enc | rdt | `test_rdt_verify.py` |
| base64enc | spc | `test_spc_imr.py test_spc_p.py test_spc_xbar_r.py test_spc_xbar_s.py` |
| ggplot2 | core | `test_core.py test_doe_suite.py test_statistical_suite.py` |

---

## Scripts using only base R (no retesting needed for any package update)

`jrc_capability`, `jrc_gen_normal`, `jrc_gen_lognormal`, `jrc_gen_sqrt`, `jrc_gen_boxcox`,
`jrc_gen_uniform`, `jrc_msa_grr_design`, `jrc_ss_discrete`, `jrc_ss_discrete_ci`,
`jrc_ss_equivalence`, `jrc_ss_fatigue`, `jrc_ss_paired`, `jrc_ss_sigma`,
`jrc_verify_discrete`, `jrc_shelf_life_arrhenius`, `jrc_shelf_life_extrapolate`,
`jrc_shelf_life_q10`

The entire **clinical module** (`jrc_clinical_ss_means`, `jrc_clinical_ss_props`,
`jrc_clinical_ss_survival`) is base R only: no pinned package maps to it, so no
package bump triggers its suite in `admin_oq_all_smart`. It runs in every full
`admin_oq_all` (auto-discovered via `repos/clinical/admin_clinical_oq`). If a
clinical script ever gains a package import, add the package rows here AND to
`get_affected()`/`resolve_alias()` in `admin_oq_all_smart` in the same commit.

`stats`, `grid`, `survival` ship with base/recommended R — only need retesting if R itself
is version-bumped (run `admin_oq_all` in that case).

---

## Dependency-only packages → parent mapping

These packages are in `R_requirements.txt` but never directly imported by any analysis script.
When one is updated, treat it as an update to its parent package and run the same suites.

| Dep-only package(s) | Parent | Suites to run |
|--------------------|--------|---------------|
| rlang, vctrs, glue, lifecycle, cli, colorspace, cpp11, magrittr, pkgconfig | ggplot2 | ggplot2 row |
| conf.design, numbers, combinat, sets, sfsmisc, scatterplot3d, vcd, igraph | DoE.base | core:doe only |
| partitions, gmp, polynom, lmtest, zoo | FrF2 | core:doe only |
| Matrix, lattice, Rdpack, rbibutils | MASS | core:diag + core:ss + core:stat |

---

## Quick reference for admin_oq_all_smart

```
admin_oq_all_smart e1071           → core:diag + core:ss + core:stat
admin_oq_all_smart MASS            → core:diag + core:ss + core:stat
admin_oq_all_smart tolerance       → core:ss + core:stat
admin_oq_all_smart nortest         → core:diag
admin_oq_all_smart outliers        → core:diag
admin_oq_all_smart FrF2            → core:doe
admin_oq_all_smart DoE.base        → core:doe
admin_oq_all_smart base64enc       → core:doe + core:stat + cap + msa(gauge_rr) + rdt(verify) + shelf_life + spc(imr/p/xbar_r/xbar_s)
admin_oq_all_smart ggplot2         → core:core + core:doe + core:stat + as + cap + corr + msa + rdt + shelf_life + spc
admin_oq_all_smart <dep-pkg>       → resolved to parent automatically
admin_oq_all_smart <unknown-pkg>   → safe fallback: all suites
```
