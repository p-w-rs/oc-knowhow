---
name: field-methods
description: What changes in data analysis from field to field — clinical and epidemiology, psychology and social science, ecology and biology, physics/engineering measurement, economics and causal inference, business and A/B testing, NLP and computer vision, forecasting and time series, genomics/omics — each with its standard designs, methods, pitfalls and reporting guideline. Load when working with data from a specific discipline, together with stats-inference and experiment-design.
---

# Field-specific methods

General rule: **when a field has an established standard (reporting guideline, preferred estimator, regulatory
requirement), follow it and cite it.** Use `library_search` with `field=` to find the relevant guidance. Below: what
typically differs.

## Clinical research and epidemiology
- Designs: RCT (randomization, allocation concealment, blinding, intention-to-treat), cohort, case-control,
  cross-sectional, target trial emulation for observational causal questions.
- Estimands (ICH E9(R1)): define how intercurrent events (dropout, rescue medication) are handled.
- Effects as risk difference and risk ratio (absolute and relative), hazard ratios with care (non-proportional hazards →
  restricted mean survival time), NNT. Confounding via DAGs; IP weighting, g-formula; E-values for sensitivity.
- Prediction models: TRIPOD+AI, calibration (calibration plots, slope, intercept) not only discrimination (AUC),
  decision curve analysis, external validation, minimum sample size (Riley).
- Reporting: CONSORT (trials), STROBE (observational), STARD (diagnostic accuracy), SPIRIT (protocols), PRISMA +
  Cochrane Handbook (reviews), GRADE (certainty of evidence).

## Psychology and social science
- Measurement: reliability (ω or α with caveats), validity, measurement invariance before comparing groups.
- Mixed models with crossed random effects (participants × items). Pre-registration, registered reports, power
  analyses with realistic (smaller) effect sizes; replication.
- Survey data: weights, design effects, nonresponse. Likert data as ordinal.
- Reporting: APA JARS (quantitative and qualitative), with the decision flowcharts for which modules apply.

## Ecology and biology
- Nested and spatial/temporal structure (plots within sites, repeated surveys): mixed models, spatial autocorrelation,
  blocked cross-validation.
- Imperfect detection: occupancy and N-mixture models (detection probability < 1); capture–recapture.
- Counts with overdispersion and zero inflation (negative binomial, zero-inflated/hurdle). Compositional data
  (microbiome: log-ratio methods).
- Biological replicates vs technical replicates: only the former count as n.

## Physics, engineering, metrology
- Uncertainty budgets per GUM (JCGM 100/101): Type A and B, propagation (Monte Carlo), expanded uncertainty with k.
- Calibration, traceability, systematic errors; fits with known measurement errors (weighted least squares, χ²,
  error-in-variables), residual and pull plots; report values with uncertainty and consistent significant digits.

## Economics and policy (causal inference)
- Identification strategies: randomized experiments, difference-in-differences (modern staggered-adoption estimators,
  event-study plots, parallel-trends checks), regression discontinuity (bandwidth choice, density test), instrumental
  variables (strength, exclusion), synthetic control. Cluster-robust standard errors at the level of treatment assignment.

## Business analytics and A/B testing
- Pre-registered primary metric and minimum detectable effect; sample size up front; no peeking without sequential
  methods (group sequential, always-valid inference); variance reduction (CUPED); sample-ratio-mismatch checks;
  novelty effects; network interference; guardrail metrics; multiple metrics → correction or hierarchy.

## Forecasting and time series
- Time-respecting evaluation (rolling origin), proper baselines (naive, seasonal naive), scale-free errors (MASE),
  prediction intervals and their coverage, probabilistic scores (CRPS). Hyndman's FPP is the reference.

## Machine learning research (general)
- See experiment-design: seeds, budgets, aggregate metrics, ablations, leakage. Benchmarks: report contamination checks
  for pretrained models; avoid test-set reuse; use REFORMS.
- Vision/NLP: dataset documentation (data statements), annotator agreement, subgroup evaluation, robustness sets.

## Genomics and high-dimensional data
- Massive multiple testing: FDR (BH, q-values); batch effects (design to balance batches; correct with care);
  count models for sequencing (negative binomial); avoid double dipping (select and test on the same data).
