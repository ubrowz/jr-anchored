# jr_stats_helpers.R
# Statistical building blocks shared by several jrc_* scripts. Sourced by
# bin/jr_helpers.R, so every script that sources jr_helpers.R has them.
#
# Keeping one copy of each building block guarantees that companion scripts
# (e.g. jrc_ss_attr / _check / _ci / jrc_verify_attr, or the five SPC charts)
# compute exactly the same thing. Code review 2026-10, X-03.
#
# Contents
#   Tolerance intervals / Box-Cox   jr_boxcox_transform, jr_boxcox_backtransform,
#                                   jr_kfactor, jr_ksample_one_side,
#                                   jr_ksample_two_side, jr_auto_transform_normal
#   Normal-approximation sample size jr_min_n_normal
#   Exact binomial sample size      jr_binom_min_n
#   ICH Q1E batch poolability       jr_shelf_poolability
#   SPC run rules                   jr_spc_rules
#   Acceptance sampling             jr_as_pa_single, jr_as_find_single

# ===========================================================================
# Tolerance intervals and Box-Cox normalisation
# (jrc_ss_attr, jrc_ss_attr_check, jrc_ss_attr_ci, jrc_verify_attr)
# ===========================================================================

# Box-Cox is accepted only when the TRANSFORMED data are consistent with a
# normal distribution: Shapiro-Wilk p > JR_BOXCOX_ALPHA, or, when Shapiro-Wilk
# cannot be run (N > 5000), |skewness| below JR_SKEW_THRESHOLD. Merely reducing
# the skewness is not enough (code review 2026-10, COR-15).
# Note: acceptance on p > alpha means a SMALLER alpha is MORE lenient; 0.01
# accepts the transformation unless normality is still clearly rejected.
JR_BOXCOX_ALPHA <- 0.01

# |skewness| below this is treated as approximately normal (data used as-is).
JR_SKEW_THRESHOLD <- 0.5

# |lambda| below this threshold is treated as lambda = 0 (log transform).
# The same threshold is used for data, spec limits and back-transformation.
JR_LAMBDA_EPS <- 1e-6

# Integration points for the EXACT K-factor (tolerance::K.factor).
JR_KFACTOR_M <- 100

jr_boxcox_transform <- function(val, lambda) {
  if (abs(lambda) < JR_LAMBDA_EPS) log(val) else (val^lambda - 1) / lambda
}

jr_boxcox_backtransform <- function(val, lambda) {
  if (abs(lambda) < JR_LAMBDA_EPS) exp(val) else (lambda * val + 1)^(1 / lambda)
}

# K-factor for a normal tolerance interval (side = 1 or 2), exact method.
jr_kfactor <- function(N, p, c, side) {
  tolerance::K.factor(N, f = NULL, alpha = 1 - as.double(c), P = as.double(p),
                      side = side, method = "EXACT", m = JR_KFACTOR_M)
}

# Sample k-factor for a 1-sided interval: SIGNED distance from the mean to the
# spec in SD units, positive when the mean is on the conforming side (above a
# lower spec, below an upper spec). k <= 0: mean at or beyond the spec.
jr_ksample_one_side <- function(sample_mean, sample_sd, spec, side) {
  if (side == "lower") (sample_mean - spec) / sample_sd else (spec - sample_mean) / sample_sd
}

# Sample k-factor for a 2-sided interval: the smaller of the two signed
# distances, so both bounds must be inside the spec window.
jr_ksample_two_side <- function(sample_mean, sample_sd, s1, s2) {
  min((sample_mean - s1) / sample_sd, (s2 - sample_mean) / sample_sd)
}

# Normality screen used by the tolerance-interval scripts: |skewness| < threshold.
jr_is_normal_skew <- function(data, skew_threshold = JR_SKEW_THRESHOLD) {
  if (length(data) < 3 || length(unique(data)) < 3) return(FALSE)
  if (any(!is.finite(data))) return(FALSE)
  skew <- abs(e1071::skewness(data))
  jr_say(paste("   Skewness value is:", round(skew, 4)))
  skew < skew_threshold
}

# Shared Box-Cox acceptance rule (also used by jrc_normality). p_after is the
# Shapiro-Wilk p-value of the transformed data, NA when it could not be run.
jr_boxcox_accepted <- function(p_after, skew_after, alpha = JR_BOXCOX_ALPHA) {
  if (!is.na(p_after)) p_after > alpha else skew_after < JR_SKEW_THRESHOLD
}

# Box-Cox attempt; returns list(transformation, lambda, transformed,
# backtransform) or NULL when the transformation is not accepted.
jr_try_boxcox <- function(x, alpha = JR_BOXCOX_ALPHA) {
  jr_say("   Trying Box-Cox transformation (MLE-based)...")
  bc_result   <- MASS::boxcox(stats::lm(x ~ 1), plotit = FALSE)
  best_lambda <- bc_result$x[which.max(bc_result$y)]
  jr_say(paste("   Optimal lambda =", round(best_lambda, 4)))

  x_bc        <- jr_boxcox_transform(x, best_lambda)
  skew_before <- abs(e1071::skewness(x))
  skew_after  <- abs(e1071::skewness(x_bc))

  # shapiro.test() only accepts 3 <= N <= 5000
  if (length(x_bc) >= 3 && length(x_bc) <= 5000) {
    p_val <- stats::shapiro.test(x_bc)$p.value
    jr_say(paste("   Shapiro-Wilk p-value after transform:", round(p_val, 4)))
  } else {
    p_val <- NA
    jr_say(paste("   Shapiro-Wilk test skipped (N =", length(x_bc),
                 "is outside the valid range 3-5000); using skewness only."))
  }
  jr_say(paste("   |Skew| before:", round(skew_before, 4),
               " |Skew| after:", round(skew_after, 4)))

  if (jr_boxcox_accepted(p_val, skew_after, alpha)) {
    jr_say("   Box-Cox transformation accepted.\n")
    lam <- best_lambda
    return(list(
      transformation = paste0("boxcox (lambda=", round(lam, 4), ")"),
      lambda         = lam,
      transformed    = x_bc,
      backtransform  = function(val) jr_boxcox_backtransform(val, lam)
    ))
  }
  jr_say("   Box-Cox did not sufficiently improve normality.")
  NULL
}

# Decide the transformation for x. $transformation is "normal" (use as-is),
# "boxcox (lambda=...)" or "none" (no acceptable normalisation found).
jr_auto_transform_normal <- function(x, alpha = JR_BOXCOX_ALPHA) {
  results <- list(original = x, transformation = "none", lambda = NA,
                  transformed = x, backtransform = function(val) val)
  jr_say("✅ Analyzing data ...")
  if (jr_is_normal_skew(x)) {
    jr_say("   Data is approximately normal.")
    results$transformation <- "normal"
    return(results)
  }
  jr_say("   Data considered not normal. Trying Box-Cox transformation!")
  if (all(x > 0)) {
    bc <- jr_try_boxcox(x, alpha)
    if (!is.null(bc)) {
      results[c("transformation", "lambda", "transformed", "backtransform")] <-
        bc[c("transformation", "lambda", "transformed", "backtransform")]
      return(results)
    }
  } else {
    jr_say("   Box-Cox requires strictly positive data; skipping (data contains zeros or negatives).")
  }
  results
}

# ===========================================================================
# Normal-approximation sample size (jrc_ss_paired, jrc_ss_sigma,
# jrc_ss_equivalence reference difference test)
#   n = ceiling( ((z_alpha + z_beta) / effect)^2 ) + 1
# ===========================================================================
jr_min_n_normal <- function(effect, power, confidence, two_sided = FALSE) {
  z_alpha <- if (two_sided) stats::qnorm((1 + confidence) / 2) else stats::qnorm(confidence)
  ceiling(((z_alpha + stats::qnorm(power)) / effect)^2) + 1
}

# ===========================================================================
# Exact binomial sample size (jrc_ss_discrete, jrc_ss_fatigue, jrc_rdt_plan
# Bogey mode): the smallest n such that f or fewer failures demonstrate
# proportion p at confidence C, i.e. the exact Clopper-Pearson criterion
#     1 - qbeta(C, f + 1, n - f) >= p   <=>   pbinom(f, n, 1 - p) <= 1 - C
# the same criterion jrc_ss_discrete_ci, jrc_verify_discrete and
# jrc_rdt_verify use to evaluate a result. The chi-squared formula
# ceiling(qchisq(C, 2f + 2) / (2 (1 - p))) is the Poisson approximation and
# overestimates n by 0-3; it only bounds the search (code review 2026-10,
# COR-18, RDT-01).
# ===========================================================================
jr_binom_min_n <- function(p, C, f) {
  f  <- as.integer(f)
  ub <- ceiling(stats::qchisq(C, df = 2 * f + 2) / (2 * (1 - p))) + 10L
  repeat {
    n  <- seq.int(f + 1L, ub)
    ok <- 1 - stats::qbeta(C, f + 1, n - f) >= p
    if (any(ok)) return(n[which(ok)[1]])
    ub <- 2L * ub
  }
}

# ===========================================================================
# SPC run rules (Nelson 1984 eight rules) — jrc_spc_imr, _xbar_r, _xbar_s,
# _p, _c. One implementation so every chart applies the same definitions:
#   1  one point beyond 3 sigma
#   2  nine points in a row on the same side of the centre line
#   3  six points in a row steadily increasing or decreasing
#   4  fourteen points in a row alternating up and down
#   5  two of three points beyond 2 sigma, same side
#   6  four of five points beyond 1 sigma, same side
#   7  fifteen points in a row within 1 sigma
#   8  eight points in a row beyond 1 sigma, on both sides of the centre line
# A signal is attributed to the point that COMPLETES the pattern (as Minitab
# does); rule 1 flags the point itself. Zero or undefined sigma: no rule can
# be evaluated and no signal is returned.
#
# ucl / lcl: optional user-specified control limits (--ucl / --lcl). When
# given they replace cl +/- 3 sigma for Rule 1 only; the zone rules 2-8 keep
# using the computed sigma (code review 2026-10, SPC-05).
#
# Returns list(ooc = logical per point, rules = list of rule numbers per
# point, rules_fired = character vector "Rule k" of rules that fired).
# ===========================================================================
jr_spc_rules <- function(x, cl, sigma, ucl = NA_real_, lcl = NA_real_) {
  n     <- length(x)
  rules <- vector("list", n)
  for (i in seq_len(n)) rules[[i]] <- character(0)
  empty <- list(ooc = rep(FALSE, n), rules = rules, rules_fired = character(0))
  if (n == 0 || !is.finite(sigma) || sigma <= 0) return(empty)

  z <- (x - cl) / sigma
  add <- function(i, r) rules[[i]] <<- c(rules[[i]], r)
  win <- function(i, w) (i - w + 1):i

  for (i in seq_len(n)) {
    above <- if (is.na(ucl)) z[i] > 3  else x[i] > ucl
    below <- if (is.na(lcl)) z[i] < -3 else x[i] < lcl
    if (above || below) add(i, "1")
    if (i >= 9  && (all(z[win(i, 9)] > 0) || all(z[win(i, 9)] < 0))) add(i, "2")
    if (i >= 6) {
      d <- diff(x[win(i, 6)])
      if (all(d > 0) || all(d < 0)) add(i, "3")
    }
    if (i >= 14) {
      d <- diff(x[win(i, 14)])
      if (all(d[-length(d)] * d[-1] < 0)) add(i, "4")
    }
    if (i >= 3) {
      w <- z[win(i, 3)]
      if (sum(w > 2) >= 2 || sum(w < -2) >= 2) add(i, "5")
    }
    if (i >= 5) {
      w <- z[win(i, 5)]
      if (sum(w > 1) >= 4 || sum(w < -1) >= 4) add(i, "6")
    }
    if (i >= 15 && all(abs(z[win(i, 15)]) < 1)) add(i, "7")
    if (i >= 8) {
      w <- z[win(i, 8)]
      if (all(abs(w) > 1) && any(w > 0) && any(w < 0)) add(i, "8")
    }
  }
  rules <- lapply(rules, unique)
  ooc   <- vapply(rules, length, integer(1)) > 0
  fired <- sort(unique(unlist(rules)))
  list(ooc = ooc, rules = rules,
       rules_fired = if (length(fired)) paste("Rule", fired) else character(0))
}

# ===========================================================================
# Acceptance sampling — attributes (jrc_as_attributes, jrc_as_variables)
# Hypergeometric when the sample is more than 10 % of the lot, else binomial.
# ===========================================================================
jr_as_pa_single <- function(n, c_val, p, N_lot) {
  if (n / N_lot > 0.10) {
    D <- round(N_lot * p)
    stats::phyper(c_val, D, N_lot - D, n)
  } else {
    stats::pbinom(c_val, n, p)
  }
}

# Smallest single sampling plan (n, c) with producer's risk <= alpha at the
# AQL and consumer's risk <= beta at the RQL (n <= min(N_lot, 500)).
jr_as_find_single <- function(N_lot, aql, rql, alpha, beta) {
  for (n in 2L:max(2L, min(N_lot, 500L))) {
    for (c_val in 0L:n) {
      alpha_act <- 1 - jr_as_pa_single(n, c_val, aql, N_lot)
      if (alpha_act <= alpha) {
        beta_act <- jr_as_pa_single(n, c_val, rql, N_lot)
        if (beta_act <= beta) {
          return(list(n = n, c = c_val, alpha_act = alpha_act, beta_act = beta_act))
        }
        break  # larger c only worsens beta for this n
      }
    }
  }
  NULL
}

# ===========================================================================
# ICH Q1E batch poolability (jrc_shelf_life_poolability, jrc_shelf_life_linear)
# Two-step ANCOVA at alpha = 0.25 (ICH Q1E section 4.5):
#   batch x time interaction significant -> "none"    (DO NOT POOL)
#   else batch main effect significant   -> "partial" (common slope)
#   else                                 -> "full"    (FULL POOL)
# y is the response on the analysis scale (e.g. log(value) for a log model).
# ===========================================================================
JR_ICH_POOL_ALPHA <- 0.25

jr_shelf_poolability <- function(batch, time, y, alpha = JR_ICH_POOL_ALPHA) {
  d <- data.frame(batch = factor(batch), time = time, y = y)
  fit_interaction <- stats::lm(y ~ batch * time, data = d)
  fit_parallel    <- stats::lm(y ~ batch + time, data = d)
  fit_pooled      <- stats::lm(y ~ time,         data = d)
  a_int  <- stats::anova(fit_parallel, fit_interaction)
  a_bat  <- stats::anova(fit_pooled, fit_parallel)
  p_interaction <- a_int$`Pr(>F)`[2]
  p_batch       <- a_bat$`Pr(>F)`[2]
  model <- if (p_interaction < alpha) "none" else if (p_batch < alpha) "partial" else "full"
  list(model = model, alpha = alpha,
       p_interaction = p_interaction, F_interaction = a_int$F[2],
       p_batch = p_batch, F_batch = a_bat$F[2])
}
