---
name: stats-inference
description: Statistical analysis done the current way, for any field — estimand and design first, choosing a test or model for the data (paired, nested/clustered, repeated, counts, proportions, ordinal, survival, time series), effect sizes with confidence intervals, p-values as continuous evidence, bootstrap and permutation tests, multiple-comparison control, mixed-effects models, GLMs and robust/cluster-robust errors, missing data, equivalence testing, power by simulation, meta-analysis, Bayesian models (PyMC, Bambi, ArviZ 1.x), measurement uncertainty, and which textbook practices are outdated. Python only (scipy, statsmodels, pingouin, PyMC) through Pixi. Load before any statistical test, comparison, interval or claim of "significant".
---

# Statistical inference (current practice)

Related: **experiment-design** (ML comparisons, seeds, splits), **ml-metrics**, **field-methods** (per discipline).

## Before computing anything

1. **State the estimand**: what quantity, in which population, compared to what (e.g. "mean difference in top-1
   accuracy between A and B over seeds, on this test distribution"). The estimand chooses the method, not vice versa.
2. **Know the design**: unit of analysis (patient, image, seed, dataset, site); what is paired, repeated, nested or
   crossed; what was randomized, at which level. n = independent units at the level of the comparison.
   Pseudo-replication (repeated measures, windows, questions of one unit treated as independent) is the most common
   serious error: fix it first.
3. **Plot the data** (per-group distributions, pairing lines, outliers, missingness); render a PNG and look at it.
4. **Fix the analysis before seeing outcomes** when it matters (pre-registration or a dated plan: estimand, outcome,
   model, covariates, exclusions, SESOI, multiplicity). Record deviations.
5. **Library**: `library_search` the method and cite it. Key sources: `asa-pvalue-2016`, `asa-beyond-005-pdf`,
   `greenland-2016-misinterpretations`, `ros`, `bda3`, `what-if`, `riley-2020-pdf`. `biostat-handbook` is `dated`.

## Report effect sizes with intervals, not verdicts

- Always: estimate, 95% CI (or credible interval), units, n (units and clusters). The p-value is secondary.
- Raw effect in natural units first; standardized (Hedges' g — say which SD, OR/RR, r, partial η², Cliff's δ,
  probability of superiority) when units don't compare. Binary outcomes: absolute *and* relative (RD and RR).
- **p-values are continuous evidence**: ASA statement 2016 (six principles); the 2019 TAS editorial (Wasserstein,
  Schirm & Lazar; an editorial, not ASA policy) urges dropping "statistically significant"; the ASA President's Task
  Force (2021, Ann. Appl. Stat. 15:1084) adds that properly used tests remain valid and thresholds must be justified
  by error consequences. So: exact p (p = 0.031; p < 0.001), no "trending", never p > 0.05 ⇒ "no effect"; say which
  effect sizes the CI rules out.
- Decide the smallest effect size of interest (SESOI) in advance; separate statistical from practical importance.
- CI (for a parameter) ≠ prediction interval (for a new observation). SD = spread, SE = precision: label every "±".

## Choosing the method (verified against scipy 1.18, statsmodels 0.15, pingouin 0.7)

| Data / design | Default now | Notes |
|---|---|---|
| Two independent groups, numeric | **Welch t** `scipy.stats.ttest_ind(a, b, equal_var=False)`; `.confidence_interval()` = CI of the difference | No normality/variance pre-tests. Heavy tails: bootstrap CI, Yuen trimmed t (`trim=0.2`), permutation (`method=scipy.stats.PermutationMethod()`), Brunner–Munzel (`brunnermunzel`). Mann–Whitney tests stochastic superiority, not medians: report P(X>Y) with CI (`statsmodels.stats.nonparametric.rank_compare_2indep`). |
| Two paired measurements | Paired t / CI of differences (`ttest_rel`), `bootstrap(..., paired=True)`, `permutation_test(..., permutation_type="samples")` | Pair whenever possible (same seeds, subjects, examples). Wilcoxon signed-rank assumes symmetric interval-scale differences; ordinal pairs: sign test (`binomtest`). |
| > 2 groups, numeric | Linear model + the contrasts you care about with CIs; Welch ANOVA (`pingouin.welch_anova`, `statsmodels.stats.oneway.anova_oneway`) | All pairs: Games–Howell (`pingouin.pairwise_gameshowell`); vs control: `scipy.stats.dunnett`; equal variances: `tukey_hsd`. |
| Repeated / nested / clustered | **Mixed model** `smf.mixedlm("y ~ x", d, groups="subject", re_formula="~x")`; GEE (`smf.gee`, population-averaged); cluster-robust SEs `.fit(cov_type="cluster", cov_kwds={"groups": g})`; or aggregate to the unit | Random intercepts at minimum, random slopes for within-unit predictors when estimable. MixedLM gives Wald z only and handles crossed effects poorly: crossed (subjects × items), non-Gaussian GLMMs, few groups → Bambi/PyMC. Few clusters (< ~30–50): wild cluster bootstrap (`pyfixest`, `wildboottest`). |
| Pre/post with baseline | **ANCOVA** `post ~ treatment + baseline` | More efficient than change scores; no baseline significance tests in RCTs. |
| Proportions / 2×2 | RD, RR, OR with CIs: `statsmodels.stats.proportion.confint_proportions_2indep(..., compare="diff"/"ratio"/"odds-ratio")` (Newcombe / log-adjusted defaults); one proportion: `proportion_confint(method="wilson")` | Small counts: `fisher_exact` or the more powerful `barnard_exact` / `boschloo_exact`. Paired: McNemar (`statsmodels.stats.contingency_tables.mcnemar`). Report the table. |
| Counts / rates | Poisson GLM with `offset=np.log(exposure)`; overdispersion (Pearson χ²/df) → `smf.negativebinomial` (estimates α); zero-inflated/hurdle for structural zeros | GLM `sm.families.NegativeBinomial()` *fixes* α = 1 unless set. Two rates: `statsmodels.stats.rates.confint_poisson_2indep`. |
| Binary outcome with predictors | Logistic regression; ORs *and* predicted probabilities / average marginal effects (`res.get_margeff()`, `marginaleffects`) | ORs are non-collapsible (adjusted ≠ unadjusted without confounding). Separation: Firth (`firthmodels`) or weakly-informative Bayesian priors. |
| Ordinal (Likert) | Proportional odds: `statsmodels.miscmodels.ordinal_model.OrderedModel`, Bambi `family="cumulative"` | Check proportional odds; say so if you average items. |
| Bounded (0–1) continuous | Beta regression (`statsmodels.othermod.betareg.BetaModel`) or fractional logit (binomial GLM + robust SE) | |
| Time to event | Kaplan–Meier, Cox (`lifelines.CoxPHFitter`, `.check_assumptions`); non-proportional hazards → RMST (`lifelines.utils.restricted_mean_survival_time`); competing risks → `AalenJohansenFitter`, not 1−KM | Non-informative censoring; numbers at risk; HRs are hard to read causally. |
| Correlation / agreement | Pearson CI `pearsonr(x, y).confidence_interval()`; Spearman + bootstrap CI; repeated measures `pingouin.rm_corr` | Correlation ≠ agreement: Bland–Altman (`statsmodels.graphics.agreement.mean_diff_plot`) with LoA CIs. |
| Rater reliability | ICC `pingouin.intraclass_corr` (name the form, e.g. ICC(2,1) absolute agreement); `statsmodels.stats.inter_rater.cohens_kappa` / `fleiss_kappa`; Krippendorff's α (`krippendorff`) | CIs; κ depends on prevalence. |
| Time series | ARIMA/state-space (`statsmodels.tsa`), HAC SEs (`cov_type="HAC"`), block bootstrap; residual check `acorr_ljungbox` | Consecutive points are not independent; beware spurious regression of trends. |
| Heteroscedasticity, tails | Robust SEs `cov_type="HC3"`; WLS with known variances; `smf.quantreg` | |
| Prediction, many predictors | Regularization + CV (experiment-design); out-of-sample performance and calibration | Inference after selection is invalid unless on held-out data. |
| Combining studies | Random effects `statsmodels.stats.meta_analysis.combine_effects(eff, var, method_re="iterated")`; HKSJ CIs (`sd_eff_w_re_hksj`) with few studies | Report τ², prediction interval; I² is not absolute heterogeneity. |
| Causal, observational | DAG → adjustment set; regression, matching, IP weighting, g-formula, doubly robust (DoWhy, DoubleML, EconML); DiD/RD/IV (field-methods); E-value (VanderWeele & Ding 2017) | Adjusting for colliders/mediators adds bias; don't read covariate coefficients causally (Table 2 fallacy). |

**Resampling**: `scipy.stats.bootstrap((x,), stat, method="BCa", rng=seed)` for any statistic (with n < ~20 every
bootstrap undercovers: say so); `scipy.stats.permutation_test` with `permutation_type="independent"`, `"samples"`
(paired) or `"pairings"` (correlation). Resample the independent unit (cluster bootstrap over subjects/passages/sites).

## Missing data

Report missingness per variable and group. Complete-case analysis is unbiased only under restrictive conditions;
otherwise multiple imputation (`statsmodels.imputation.mice.MICE`; include the outcome in the imputation model; number
of imputations ≳ % incomplete cases; Rubin's rules) or a likelihood/Bayesian model (mixed models use all observations
under MAR). Add a missing-not-at-random sensitivity analysis (e.g. δ-adjustment). No LOCF or mean imputation.

## Multiple comparisons

- Confirmatory, any false positive costly (FWER): Holm (`statsmodels.stats.multitest.multipletests(p, method="holm")`);
  Bonferroni is valid but never more powerful than Holm. Structured: Dunnett, Tukey, gatekeeping of a pre-ordered list.
- Screening (FDR): Benjamini–Hochberg `scipy.stats.false_discovery_control(p)` (adjusted p; `method="by"` under
  arbitrary dependence) or `multipletests(method="fdr_bh")`.
- Count *all* comparisons looked at (forking paths). Prefer few planned contrasts or one hierarchical model. Label
  exploratory results as such, with the number of tests.

## Power, sample size, precision

- Plan n before collecting, for a CI half-width or for power at the SESOI. Closed form: `statsmodels.stats.power`
  (`TTestIndPower().solve_power`, `FTestAnovaPower`), `statsmodels.stats.proportion.power_proportions_2indep`,
  `pingouin.power_ttest`. Clustered, repeated, Bayesian or unusual designs: **simulate** the planned analysis on fake
  data (`scipy.stats.power` for scipy tests); this also tests the code. Cluster designs: design effect 1 + (m − 1)·ICC.
- No "observed"/post-hoc power. Underpowered "significant" results exaggerate effects (Type M) and may flip sign (Type S).
- Prediction models: minimum sample size criteria (Riley et al. 2020, BMJ; `pmsampsize`).

## Equivalence, non-inferiority and "no difference"

Pre-specify the margin (SESOI). TOST: `statsmodels.stats.weightstats.ttost_ind(x1, x2, low, upp, usevar="unequal")`
(the default `usevar="pooled"` is Student, not Welch), `ttost_paired`, `tost_proportions_2indep`; `pingouin.tost` uses
Student (`correction=False`) by default. Equivalent formulation: the 90% CI lies inside (−margin, +margin).
Non-inferiority: one-sided, the CI lower bound above −margin. Bayesian: posterior mass inside a region of practical
equivalence (ROPE, `arviz.ci_in_rope`).

## Bayesian when it fits

For hierarchical data, small samples with real prior knowledge, decisions with costs, or direct probability statements
("P(A better than B) = 0.93"). PyMC, or Bambi for formulas/GLMMs/crossed effects
(`bmb.Model("y ~ x + (1|subject) + (1|item)", d)`); nutpie sampler for speed.

Workflow: weakly-informative priors on the data scale → prior predictive check (`pm.sample_prior_predictive`) → fit →
**R̂ < 1.01, bulk and tail ESS > 400, no divergences** (Vehtari et al. 2021; `az.summary`, `az.plot_rank`) → posterior
predictive check → prior sensitivity (`az.psense_summary`) → PSIS-LOO comparison (`pm.compute_log_likelihood`,
`az.loo`, `az.compare`; Pareto k̂ < 0.7). Report posterior summaries with credible intervals (state the level). Bayes
factors are prior-sensitive: only with justified priors (`pingouin.bayesfactor_ttest` uses JZS r = 0.707).

**ArviZ 1.x renamed the API** (old tutorials and model memory use 0.x): `plot_ppc_dist` (was `plot_ppc`), `plot_dist`
(was `plot_posterior`), `plot_trace_dist`, `plot_ppc_pit`; no WAIC (use LOO); data are xarray DataTrees. Check
`help()` before writing plotting code.

## Measurement uncertainty (physical measurements)

GUM (JCGM 100:2008, plus **Amendment 1:2026 on nonlinear models**, `jcgm-100-amd1-2026`): list sources, Type A
(statistical) and Type B (other knowledge), propagate (linearization; Monte Carlo per JCGM 101 when nonlinear or
asymmetric), report u_c and U = k·u_c with k and coverage; 1–2 significant digits on the uncertainty, value to match.
Python: `uncertainties` (linear propagation with correlations), NumPy Monte Carlo.

## Outdated practices — do not use

- Normality (Shapiro–Wilk) or variance (Levene) pre-tests to *choose* a test (distorts error rates); checking the raw
  outcome's normality instead of model residuals.
- Student's t as default; Fisher's LSD beyond three groups; unadjusted all-pairs t-tests.
- A p < 0.05 bright line, "trending"/"marginally significant", stars as the result; non-significant ⇒ "no effect";
  "significant in A, not in B" ⇒ "A ≠ B" (test the difference).
- Stepwise selection by p-values; univariable screening; dichotomizing continuous variables; change scores instead of
  ANCOVA; baseline significance tests in RCTs.
- Post-hoc power; one-sided tests chosen after the fact; pseudo-replication; ignoring clustering; LOCF/mean imputation;
  mean ± SD for very skewed data.
- `scipy.odr` (deprecated in SciPy 1.17, removed in 1.19): use `odrpack`. Spreadsheet/point-and-click analyses.

## How to run it (Python through Pixi)

```sh
pixi init --script analysis.py
pixi add --script analysis.py scipy statsmodels pandas pingouin matplotlib   # + lifelines pymc bambi arviz as needed
pixi run --script analysis.py
# quick one-off check of an API:
pixi exec --spec python=3.12 --spec scipy --spec statsmodels python -c "import scipy.stats as s; help(s.bootstrap)"
```

PyPI-only packages (`pmsampsize`, `marginaleffects`, `krippendorff`, `wildboottest`, `firthmodels`):
`pixi add --script analysis.py --pypi <pkg>`. Never use R or rpy2-based wrappers (e.g. pymer4).

One script from raw data to results (exclusions with counts, models, checks, a table of estimates with CIs, figures,
package versions); seeds for resampling and MCMC; check unfamiliar APIs with `help()` rather than memory; log ML
experiments to MLflow (ml-training).

## Reporting checklist

Design, estimand, unit of analysis; n per group (units and clusters, exclusions with reasons); missing data and
handling; exact model/test, software versions; estimates with CIs in natural units; exact p if reported; all
comparisons and the multiplicity method; diagnostics; deviations from plan; sensitivity analyses; data/code. Plus the
field's guideline (field-methods: CONSORT 2025, STROBE, TRIPOD+AI, PRISMA 2020, APA JARS, REFORMS).
