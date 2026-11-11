---
name: experiment-design
description: Design and evaluate experiments that support real conclusions — ablation studies, deciding whether one model or architecture is actually better than another (fair tuning and compute budgets, seeds, paired comparisons, intervals, aggregate metrics across tasks), cross-validation for dependent data, baselines, pre-registration, reproducibility (seeds, versions, MLflow), and reporting standards (REFORMS, CONSORT, TRIPOD+AI, PRISMA, JARS). Load before planning experiments, comparing methods, or writing up results.
---

# Experiment design and model comparison

## The questions to answer before running anything

1. **Claim**: the exact sentence you want to be able to write ("Adding X improves Y by Z on W, at equal compute").
2. **Comparison**: against what baseline(s)? Strong, well-tuned, current baselines; including the simplest one that
   could work (linear model, smaller model, previous version, majority class, persistence forecast).
3. **Metric and test distribution**: what is measured, on which data, and is that data independent of everything used
   for development? Pick the primary metric and the decision rule in advance (e.g. "accept if the 95% CI of the mean
   paired improvement over 5 seeds excludes 0 and the point estimate ≥ 0.5 pt").
4. **Sources of variance**: seeds (initialization, data order, dropout, augmentation), data splits, hyperparameter
   search, hardware nondeterminism. Decide which to randomize and how many repeats.
5. **Budget parity**: same tuning budget (number of trials), same compute (GPU-hours, FLOPs or wall-clock), same
   data, same training length or a justified difference. An advantage that disappears at equal tuning budget is not
   an advantage of the method.

Write this plan into the repo (e.g. `experiments/<name>/PLAN.md`) and log it as an MLflow artifact.

## Is A really better than B?

- **Repeat runs**: at least 3–5 seeds per configuration for cheap models, more when differences are small relative to
  seed variance; for very expensive runs, say how few you had and widen the uncertainty accordingly.
- **Pair** whenever possible: same seeds, same splits/folds, same evaluation examples for A and B; analyze the
  per-seed/per-fold/per-example *differences*. Paired bootstrap over test examples for one trained model pair; over
  seeds for training variance (they answer different questions; the seed-level one is usually what "A is better"
  means).
- **Report** mean difference with a 95% CI (bootstrap) and the spread across seeds; show all runs (strip plot), not
  only the best. The "best of N seeds" is not a result.
- **Across many tasks/datasets**: don't average raw scores of different scales; use normalized scores with interquartile
  mean (IQM) and stratified bootstrap CIs, performance profiles, and probability of improvement (rliable, Agarwal et
  al. 2021). For classifiers over many datasets, Bayesian signed-rank / hierarchical tests with a ROPE (Benavoli et al.
  2017) instead of only Friedman–Nemenyi critical-difference diagrams.
- **Hyperparameters**: tune both methods with the same search space size/strategy and budget; report expected
  validation performance vs budget curves (Dodge et al. 2019) when budgets differ; never tune on the test set.
- **Practical significance**: compare the improvement to seed noise and to the cost (latency, memory, params, FLOPs,
  energy). Report those costs.

## Ablation studies

- Purpose: show which components are responsible for the gain. Start from the full model and remove or replace one
  component at a time (leave-one-out ablation); also add components to the baseline one at a time when interactions are
  suspected (build-up ablation). Factorial designs (2^k, or fractional) when components may interact and runs are cheap.
- Replace with a sensible alternative, not just deletion (e.g. learned positional encoding → fixed), and keep
  parameter count/compute comparable when the claim is about the idea, not capacity; add a capacity-matched control.
- Same seeds, same budget, same data for every row; report each row with seed spread/CI, not a single number.
- Check that the full model actually reproduces the headline result in the ablation setting.
- Present as a table with the delta to the full model and its CI; flag deltas within seed noise as "no detectable
  effect" rather than ranking them.

## Splits and validation

- Train / validation (model selection) / test (final, touched once). Report if the test set was used more than once.
- **Dependent data needs blocked splits**: time (forward-chaining / rolling origin; gap between train and test),
  groups (patients, users, sites, sessions, scenes: group k-fold), space (spatial blocks), phylogeny/families
  (cluster by similarity). Random splits on such data inflate scores (Roberts et al. 2017).
- Nested cross-validation when hyperparameters are tuned and data are small. Report the spread across folds.
- **Leakage checks** (Kapoor & Narayanan): preprocessing fit on all data (scalers, imputers, feature selection,
  tokenizers trained on test), duplicates/near-duplicates across splits, features unavailable at prediction time,
  temporal leakage, test data used for early stopping or model selection, label leakage through IDs/filenames.

## Reproducibility

- Fixed seeds per run (and recorded), deterministic flags where affordable (`torch.use_deterministic_algorithms`),
  pinned environments (Pixi lock), data versions (dataset revision/hash), code commit, hardware.
- Log every run to MLflow (see ml-training): params, metrics per step, final metrics, artifacts (config, plan, plots).
  Use `mlflow.search_runs` to build the comparison table; generate tables/figures from logged runs with a script, never
  by hand.
- Keep a results log: failed and negative runs too.

## Reporting

- Follow the standard for the field: ML-based science → REFORMS checklist; clinical prediction → TRIPOD+AI; trials →
  CONSORT; observational → STROBE; systematic reviews → PRISMA 2020 and the Cochrane Handbook; psychology → APA JARS;
  ML venues → their reproducibility checklist; artifacts → ACM artifact badges (available, functional, reproduced).
- Include: what was compared, budgets, number of seeds/folds, the variance, the statistical procedure, all ablations,
  failure cases and limitations, compute used. Use `library_search` for the checklist items of the relevant guideline.

## Common pitfalls to check for (Lones; Kapoor & Narayanan)

Comparing against untuned or outdated baselines; reporting the best seed; selecting the test metric after seeing
results; test-set reuse; leakage; ignoring class imbalance (ml-metrics skill; use metrics that fit: balanced accuracy, PR-AUC, calibration);
claiming generality from one dataset; mistaking statistical for practical significance; not reporting compute.
