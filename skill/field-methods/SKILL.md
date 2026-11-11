---
name: field-methods
description: What changes in data analysis from field to field — clinical trials and epidemiology (estimands, target trial emulation, prediction models), psychology and social science (measurement, crossed random effects, surveys), ecology and biology, physics/engineering measurement and quality, economics and policy causal inference (DiD, RD, IV, synthetic control), business A/B testing, forecasting, ML/NLP/vision evaluation, genomics/omics — each with its standard designs, methods, Python tools, pitfalls and current reporting guideline. Load when working with data from a specific discipline, together with stats-inference and experiment-design.
---

# Field-specific methods

Rule: **when a field has an established standard (reporting guideline, preferred estimator, regulatory requirement),
follow it and cite it.** `library_search` with `field=` for exact checklist wording; EQUATOR (equator-network.org)
lists health guidelines and their newest versions. General methods and verified APIs: stats-inference. Python only,
via Pixi; PyPI-only packages (`rdrobust`, `csdid`, `dcurves`, `samplics`, `semopy`, `pydeseq2`, …):
`pixi add --script f.py --pypi <pkg>`.

## Clinical research and epidemiology
- RCTs: concealed randomization, blinding, intention-to-treat; cluster/stepped-wedge trials analysed at cluster level
  or with mixed models/GEE. Define the **estimand (ICH E9(R1))**, including the strategy for intercurrent events
  (treatment-policy, hypothetical, composite, while-on-treatment, principal stratum).
- Adjust for prespecified prognostic baseline covariates (ANCOVA; adjusted logistic standardized to a marginal effect).
  Group-sequential boundaries for interim looks. Missing outcomes: multiple imputation + sensitivity analyses.
- Report risk difference and ratio, NNT; hazard ratios with care (non-proportional → RMST); competing risks →
  cumulative incidence.
- Observational causal questions: **target trial emulation** (`what-if`): align time zero, eligibility and treatment
  start (avoids immortal-time and prevalent-user bias; new-user designs); DAG-based adjustment; IP weighting,
  g-formula, doubly robust; E-values, negative controls.
- Prediction models: calibration (plot, slope, O:E) not only AUC; decision curves (`dcurves`); bootstrap internal
  and external validation; subgroup performance; minimum n (Riley 2020, `pmsampsize`); no dichotomizing, no stepwise.
- Guidelines (current): **CONSORT 2025** (trials; supersedes 2010), **SPIRIT 2025** (protocols), STROBE
  (observational), **TARGET 2025** (target trial emulation), **TRIPOD+AI 2024** (prediction; supersedes TRIPOD 2015),
  **PROBAST+AI 2025** (risk of bias of prediction models), STARD 2015 / **STARD-AI 2025** (diagnostic accuracy), PRISMA
  2020 + Cochrane Handbook (reviews), RoB 2, ROBINS-I V2 (still a draft: cite the dated version), GRADE.
- Python: `lifelines`, `scikit-survival`, `statsmodels`, `tableone`, `dcurves`, `pmsampsize`, DoWhy, DoubleML.

## Psychology and social science
- Measurement: reliability (McDonald's ω over α alone; test–retest ICC), validity, **measurement invariance**
  (configural → metric → scalar; `semopy`) before comparing groups.
- **Crossed random effects** for participants × items (Bambi/PyMC); averaging over items inflates false positives.
- Pre-registration / registered reports; power from realistic (bias-corrected) effect sizes; multiverse or
  specification-curve analyses for robustness.
- Surveys: weights, strata and clusters in design-based SEs (`samplics`, `svy`); nonresponse adjustment; Likert as ordinal.
- Reporting: APA JARS (Quant, Qual, Mixed; 2018).

## Ecology and biology
- Nested/spatial/temporal structure: mixed models, residual spatial autocorrelation (Moran's I, `esda`), blocked CV
  (Roberts et al. 2017). Phylogenetic non-independence across species.
- Imperfect detection: occupancy (MacKenzie et al. 2002), N-mixture, capture–recapture, distance sampling (PyMC models).
- Overdispersed / zero-inflated counts (`statsmodels.discrete.count_model`). Compositional data (microbiome): log-ratios
  (`skbio.stats.composition.clr`, `ancombc`), never raw proportions.
- Only biological replicates count as n; model or average technical ones. Animal studies: ARRIVE 2.0.

## Physics, engineering, metrology, quality
- GUM (JCGM 100 + Amendment 1:2026 for nonlinear models; JCGM 101 Monte Carlo): uncertainty budget, Type A/B,
  correlations, expanded U with k (`uncertainties`).
- Fits with known errors: `scipy.optimize.curve_fit(..., sigma=s, absolute_sigma=True)`, reduced χ², pull plots;
  errors in x and y → ODR (`odrpack`; `scipy.odr` is removed in SciPy 1.19). Systematics listed separately.
- Particle/astro: blind analysis, look-elsewhere effect (local vs global significance), 5σ discovery convention.
- Engineering/quality: designed experiments (factorial, fractional, response surface; `pyDOE3`), gauge R&R
  (variance components), control charts, censored life data (Weibull; `reliability`, `lifelines`).

## Economics and policy (causal inference)
- **DiD**: with staggered adoption or heterogeneous effects, two-way fixed effects is biased — use Callaway–Sant'Anna,
  Sun–Abraham or imputation estimators (`csdid`, `diff-diff`, `pyfixest`), event-study plots, and honest pre-trend
  sensitivity (Rambachan & Roth 2023) rather than a pre-trend test alone.
- **RD**: local polynomial, robust bias-corrected CIs, data-driven bandwidth, manipulation test (`rdrobust`,
  `rddensity`). **IV**: report first-stage strength, weak-IV-robust inference, argue exclusion (`linearmodels.iv`).
  **Synthetic control** (`pysyncon`); double/debiased ML (`DoubleML`).
- Cluster SEs at the treatment-assignment level; few clusters → wild cluster bootstrap. Panels: `pyfixest`,
  `linearmodels`. Pre-analysis plans (AEA RCT Registry); economic magnitude, not just significance.

## Business analytics and A/B testing
- Pre-registered primary metric, guardrails, MDE; sample size and duration (whole weeks) fixed up front.
- **No peeking** with fixed-horizon tests; monitor only with group-sequential or always-valid (mSPRT, confidence
  sequence) methods.
- **Sample-ratio mismatch** check (χ² on assignment counts) before analysis; A/A tests; analysis unit = randomization
  unit (ratio metrics: delta method or user-level bootstrap).
- CUPED (Deng et al. 2013; regression on pre-period metric) for variance reduction; heavy tails → pre-registered
  capping; novelty effects; interference → cluster or switchback designs; many metrics → hierarchy or correction.
- Reference: Kohavi, Tang & Xu, *Trustworthy Online Controlled Experiments* (2020).

## Forecasting and time series
- Rolling-origin evaluation; benchmarks (naive, seasonal naive, ETS, ARIMA) that ML and foundation models must beat;
  MASE/RMSSE; interval coverage; CRPS / pinball loss (`scoringrules`); reconcile hierarchical forecasts.
- Reference: Hyndman et al., *Forecasting: Principles and Practice, the Pythonic Way* (OTexts, 2025 online, 2026
  print; `statsforecast`); `statsmodels.tsa` for ARIMA/ETS/state space.

## Machine learning, NLP and vision research
- experiment-design for seeds, budgets, ablations, leakage; REFORMS for ML-based science; ml-metrics for metrics.
- Evals with grouped items (questions per passage, translations): cluster-robust SEs and paired model differences
  (Miller 2024, arXiv:2411.00640).
- Contamination checks for pretrained models; no test-set reuse; annotation agreement (κ, Krippendorff's α) and
  documentation (datasets skill); subgroup and robustness sets. Medical AI: TRIPOD+AI, STARD-AI, CONSORT-AI/SPIRIT-AI.

## Genomics and high-dimensional data
- FDR (BH, q-values); effect sizes (shrunken log fold changes), not only p-values.
- Sequencing counts: negative binomial with shrinkage (`pydeseq2`); single-cell: **pseudobulk** per sample (cells are
  not replicates; `scanpy` for processing).
- Batch effects: balance batches across conditions by design; correct with care (ComBat), never using the outcome;
  no double dipping (cluster then test on the same data). GWAS: 5 × 10⁻⁸, population-structure correction.
