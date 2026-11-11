---
name: stats-inference
description: Statistical analysis done the current way, for any field — choosing a test or model for the data and design (paired, nested, repeated, counts, proportions, survival, time series), effect sizes with confidence intervals first, p-values as continuous evidence, bootstrap and permutation tests, multiple-comparison control, mixed-effects and GLMs, equivalence testing, power and sample size, Bayesian alternatives, measurement uncertainty, and which textbook practices are outdated. Python only (scipy, statsmodels, pingouin, PyMC) through Pixi. Load before any statistical test, comparison, interval or claim of "significant".
---

# Statistical inference (current practice)

## Before computing anything

1. **State the question as an estimand**: what quantity, in which population, compared to what (e.g. "mean
   difference in top-1 accuracy between A and B over seeds, on this test distribution"). The estimand chooses the
   method; the method never chooses the question.
2. **Know the design**: what is the unit of analysis (patient, image, seed, dataset, site)? Which observations are
   paired, repeated or nested? What was randomized? Pseudo-replication (treating repeated measures or windows of one
   subject as independent) is the most common serious error; fix it before anything else.
3. **Plot the data** (distribution per group, pairing lines, outliers) before testing. Look at it yourself (render a
   PNG and read it).
4. **Decide the analysis before seeing outcomes** when it matters (pre-registration, or at least write the plan into
   the project before running). Record deviations.
5. Use the **library**: `library_search` the method (e.g. "Welch t-test unequal variances", "mixed model random slopes",
   "Benjamini-Hochberg") and cite what you rely on. Check a source's status: some textbooks are flagged `dated`.

## Report effect sizes with intervals, not verdicts

- Always report the estimate, its uncertainty (95% CI or credible interval) and the units; p-values are secondary.
- Effect sizes: raw difference in natural units first (ms, accuracy points, mmHg); standardized ones (Cohen's d /
  Hedges' g, odds/risk ratio, risk difference, r, η², Cliff's δ / rank-biserial) when units don't compare.
- **p-values are continuous evidence**, not pass/fail (ASA 2016 and 2019 statements). Don't write "significant"/"not
  significant" as conclusions; don't treat p > 0.05 as "no effect" (use an equivalence test or the CI to say what
  sizes are ruled out). Report exact p-values (p = 0.031, p < 0.001).
- Distinguish statistical from practical importance: decide the smallest effect that matters (SESOI) in advance.

## Choosing the method

| Data / design | Default now | Notes |
|---|---|---|
| Two independent groups, numeric | **Welch's t-test** (`scipy.stats.ttest_ind(equal_var=False)`) + CI of the difference; or bootstrap CI | Don't pre-test normality/variance to choose; Welch is the default. Heavy tails/outliers: bootstrap, permutation, or Hodges–Lehmann with Mann–Whitney. |
| Two paired measurements | Paired t-test on differences, or bootstrap/permutation of differences; Wilcoxon signed-rank for ordinal-ish data | Pairing (same seeds, same subjects, same datasets) is usually much more powerful; use it. |
| > 2 groups, numeric | Welch's ANOVA (`pingouin.welch_anova`) or a linear model; post-hoc Games–Howell; better: estimate the contrasts you care about with CIs | Prefer planned contrasts over all-pairs testing. |
| Repeated / nested / clustered (subjects, sites, seeds within configs) | **Mixed-effects model** (`statsmodels.formula.api.mixedlm`, or Bayesian with Bambi/PyMC); or cluster-robust SEs; or aggregate to the unit | Random intercepts at minimum; random slopes for within-unit effects when data allow. |
| Proportions / 2×2 | Risk difference and risk ratio with CIs (Newcombe/Wilson; `statsmodels.stats.proportion`); Fisher exact for small counts; logistic regression with covariates | Chi-square/G for larger tables; report the table. |
| Counts | Poisson or negative-binomial GLM (check overdispersion); offsets for exposure | |
| Binary outcome with predictors | Logistic regression; report odds ratios *and* predicted probabilities/marginal effects | |
| Ordinal (Likert) | Ordinal (proportional-odds) regression (`statsmodels OrderedModel`) | Don't average Likert items as if interval without saying so. |
| Time to event | Kaplan–Meier, Cox model (`lifelines`), check proportional hazards; competing risks if present | |
| Correlation | Pearson with CI (Fisher z) or Spearman; show the scatter plot; correlation is not agreement — use Bland–Altman for method comparison | |
| Agreement / reliability | ICC (choose the right form), Cohen's/Fleiss' κ or Krippendorff's α for raters | |
| Time series | Account for autocorrelation (block bootstrap, HAC/Newey–West SEs, ARIMA/state-space); never treat consecutive points as independent | |
| Many features / prediction | Regularized regression, cross-validation (see experiment-design); report out-of-sample performance | |
| Causal question from observational data | DAG first, then adjustment set; regression/matching/IP weighting; DiD, RD, IV designs; sensitivity analysis (E-value) | "Adjusting for everything" can introduce bias (colliders, mediators). |

**Resampling is a general tool**: `scipy.stats.bootstrap` (BCa intervals) for any statistic; `scipy.stats.permutation_test`
for exact-ish tests under exchangeability; resample at the level of the independent unit (cluster bootstrap).

## Multiple comparisons

- Many tests → control error: Holm (FWER) when any false positive is costly; Benjamini–Hochberg (FDR) for screening
  many hypotheses (`statsmodels.stats.multitest.multipletests`). Bonferroni is valid but needlessly conservative vs Holm.
- Count *all* comparisons you looked at (forking paths), not only the ones you report. Better: fewer, pre-planned
  comparisons, or a single model with all conditions (hierarchical/partial pooling).

## Power, sample size, precision

- Plan sample size for the precision you need (CI width) or for power at the SESOI, before collecting
  (`statsmodels.stats.power`, simulation for complex designs — simulation is usually the honest choice).
- Never compute "observed power" after the fact. With small samples, expect exaggerated significant effects (Type M
  error) and possibly wrong signs (Type S).
- Prediction models: minimum sample size criteria (Riley et al. 2020, `pmsampsize`-style calculation).

## Equivalence and "no difference"

To claim two methods are equivalent, test against bounds: TOST (`statsmodels.stats.weightstats.ttost_ind` /
`ttost_paired`) with a pre-specified margin, or show the CI lies within ±SESOI. Bayesian: posterior mass inside a
region of practical equivalence (ROPE).

## Bayesian when it fits

Use it for hierarchical data, small samples with prior knowledge, decisions with costs, or direct probability
statements ("P(A better than B) = 0.93"). PyMC or Bambi (formula interface) + ArviZ. Always: prior predictive check,
convergence (R̂ ≈ 1.00, ESS, no divergences), posterior predictive check, sensitivity to the prior. Report posterior
medians with credible intervals. Bayes factors only with well-justified priors.

## Measurement uncertainty (physical measurements)

Follow the GUM (JCGM 100): list uncertainty sources, Type A (statistical) and Type B (other knowledge), propagate
(analytically or Monte Carlo, JCGM 101), report combined standard uncertainty and expanded uncertainty with coverage
factor; significant digits follow the uncertainty.

## Outdated practices — do not use

- Testing normality (Shapiro–Wilk) or equal variances (Levene) to *choose* between tests (two-stage procedures distort
  error rates). Use Welch/robust/resampling methods by default; inspect residual plots for model checking.
- Student's equal-variance t-test as the default; Fisher's LSD; running all pairwise t-tests without adjustment.
- A fixed p < 0.05 bright line, "trending towards significance", stars as the main result, "marginally significant".
- Interpreting a non-significant result as evidence of no effect.
- Stepwise variable selection (forward/backward by p-values) for inference; univariable screening before multivariable
  models; dichotomizing continuous variables (median splits).
- Post-hoc ("observed") power. Treating repeated measures as independent. Reporting SD vs SE ambiguously ("±" without
  saying which).
- Comparing correlations or "significant in A but not in B" as evidence of a difference: test the interaction/difference.
- Spreadsheets or SAS-only workflows: use scripted, versioned Python analyses (Pixi script or project).

## How to run it (Python through Pixi)

```sh
pixi init --script analysis.py && pixi add --script analysis.py scipy statsmodels pandas pingouin   # + pymc bambi arviz lifelines as needed
pixi run --script analysis.py
```

Write analysis code as a script that reads the raw data, does every step (cleaning, exclusions with counts, models),
prints a results table and saves figures. Set seeds for resampling. Log analyses that belong to ML experiments to
MLflow (params, metrics, the script as an artifact).

## Reporting checklist

Design and unit of analysis; n per group (and exclusions with reasons); the exact model/test and software versions;
estimates with CIs in natural units; standardized effects where useful; exact p-values if reported; all comparisons
made and the correction; assumptions checked and how; deviations from plan; data/code availability. Use the field's
reporting guideline when one exists (EQUATOR: CONSORT, STROBE, TRIPOD+AI, PRISMA; APA JARS in psychology).
