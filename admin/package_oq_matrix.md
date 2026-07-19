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

| Package | ver | core:core | core:diag | core:doe | core:ss | core:stat | as | cap | clinical | corr | msa | rdt | shelf_life | spc |
|---------|-----|:---------:|:---------:|:--------:|:-------:|:---------:|:--:|:---:|:--------:|:----:|:---:|:---:|:----------:|:---:|
| ggplot2 | 4.0.3 | test_core | — | test_doe_suite | — | test_statistical_suite | ✓ | ✓ | dx_roc,dx_compare | ✓ | ✓ | ✓ | ✓ | ✓ |
| base64enc | 0.1-6 | — | — | test_doe_suite | — | test_statistical_suite | — | ✓ | — | — | test_msa_gauge_rr | test_rdt_verify | ✓ | imr,p,xbar_r,xbar_s |
| e1071 | 1.7-17 | — | ✓ | — | ✓ | test_statistical_suite | — | — | — | — | — | — | — | — |
| MASS | 7.3-65 | — | ✓ | — | ✓ | test_statistical_suite | — | — | — | — | — | — | — | — |
| tolerance | 3.0.0 | — | — | — | ✓ | test_statistical_suite | — | — | — | — | — | — | — | — |
| nortest | 1.0-4 | — | ✓ | — | — | — | — | — | — | — | — | — | — | — |
| outliers | 0.15 | — | ✓ | — | — | — | — | — | — | — | — | — | — | — |
| FrF2 | 2.3-5 | — | — | test_doe_suite | — | — | — | — | — | — | — | — | — | — |
| DoE.base | 1.2-5 | — | — | test_doe_suite | — | — | — | — | — | — | — | — | — | — |
| survival | 3.8-9 | — | — | — | — | test_statistical_suite | — | — | km,coxph | — | — | — | — | — |

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
| ggplot2 | clinical | `test_clinical_dx_roc.py test_clinical_dx_compare.py` |
| survival | clinical | `test_clinical_km.py test_clinical_coxph.py` |

---

## Scripts using only base R (no retesting needed for any package update)

`jrc_capability`, `jrc_gen_normal`, `jrc_gen_lognormal`, `jrc_gen_sqrt`, `jrc_gen_boxcox`,
`jrc_gen_uniform`, `jrc_msa_grr_design`, `jrc_ss_discrete`, `jrc_ss_discrete_ci`,
`jrc_ss_equivalence`, `jrc_ss_fatigue`, `jrc_ss_paired`, `jrc_ss_sigma`,
`jrc_verify_discrete`, `jrc_shelf_life_arrhenius`, `jrc_shelf_life_extrapolate`,
`jrc_shelf_life_q10`

In the **clinical module**, the sample-size and 2x2 scripts are base R only:
`jrc_clinical_ss_means`, `jrc_clinical_ss_props`, `jrc_clinical_ss_survival`,
`jrc_clinical_dx_ss` and `jrc_clinical_dx_accuracy` import nothing pinned, so no
package bump triggers them. They run in every full `admin_oq_all`
(auto-discovered via `repos/clinical/admin_clinical_oq`). `jrc_clinical_dx_roc`
imports **ggplot2**; `jrc_clinical_km` and `jrc_clinical_coxph` (Module 3) import
**survival** — see those package rows.

`jrc_clinical_dx_roc` (added v4.5.0) imports **ggplot2** for its two-panel PNG
and is the module's only pinned-package dependant — hence the `clinical` column
above, and the `clinical:test_clinical_dx_roc.py` entry in `get_affected()`.
Its AUC/DeLong statistics are base R; ggplot2 is used only to draw the plot.
If any other clinical script gains a package import, add the package rows here
AND to `get_affected()`/`resolve_alias()` in `admin_oq_all_smart` in the same
commit.

`stats` and `grid` ship with base R — only need retesting if R itself is
version-bumped (run `admin_oq_all` in that case).

`survival` (3.8-9) **was** in that recommended-and-unpinned group, but is now
**explicitly pinned** (added 2026-07-17, Phase 0 of Clinical Module 3). It is a
recommended package, so R bundles a copy, and `jrc_weibull` previously loaded
that unvalidated system copy via `library(survival)`. It is now in
`R_requirements.txt`, `renv.lock` and `r_package_hashes.sha256` like every other
dependency, and scripts load it from the validated renv library. Its current
dependant is `jrc_weibull` (core `test_statistical_suite.py`); Clinical Module 3
(`jrc_clinical_km`, `jrc_clinical_coxph`) will add clinical rows here when those
scripts land. A `survival` version bump therefore triggers the core statistical
suite today — see `get_affected()`.

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
