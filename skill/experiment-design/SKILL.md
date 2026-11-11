---
name: experiment-design
description: Design and evaluate experiments that support real conclusions — ablation studies, deciding whether one model or architecture is actually better than another (fair tuning and compute budgets, seeds, paired comparisons, intervals, P(A>B), aggregate metrics across tasks with rliable IQM, Bayesian ROPE tests), LLM/benchmark evals (clustered errors, contamination), cross-validation for dependent data, leakage checks, baselines, pre-registration, reproducibility (seeds, determinism, versions, MLflow), and reporting standards (REFORMS, NeurIPS checklist, CONSORT 2025, TRIPOD+AI/TRIPOD-LLM, STARD-AI, PRISMA, JARS). Load before planning experiments, comparing methods, or writing up results.
---

# Experiment design and model comparison

Related skills: stats-inference (tests, intervals, mixed models), ml-metrics (which metric), ml-tuning (what to tune),
ml-training (MLflow, environments), datasets (splits, dedup, documentation).

## Before running anything (write it to `experiments/<name>/PLAN.md`, log it to MLflow)

1. **Claim**: the exact sentence you want to write ("Adding X improves Y by Z on W, at equal compute").
2. **Baselines**: strong, current, *equally tuned*; plus the simplest thing that could work (linear/GBDT model, smaller
   model, previous version, majority class, persistence forecast, zero-shot prompt).
3. **Estimand, metric, test distribution**: primary metric and decision rule fixed in advance, e.g. "accept if the 95%
   CI of the mean paired improvement over 10 seeds excludes 0 and the estimate ≥ 0.5 pt (the smallest effect that
   matters)". Test data independent of everything used for development.
4. **Sources of variance**: data split/sampling, init, data order, augmentation, dropout, HPO randomness, hardware
   nondeterminism. Decide which to randomize and how many repeats (see below).
5. **Budget parity**: same HPO budget, compute (GPU-hours/FLOPs), data and training length, or a stated, justified
   difference. A gain that vanishes at equal tuning budget belongs to the tuning, not the method.
6. **Multiplicity**: list every comparison you will look at; fewer planned comparisons beat many corrected ones.

## Is A really better than B?

- **Repeat runs with independent seeds.** 3 seeds is a smoke test. Plan ≥ 5–10 when the effect is near seed noise;
  size N from a pilot's seed SD (stats-inference). Bouthillier et al. 2021 ("Accounting for Variance in ML
  Benchmarks"): randomize *all* variance sources (data splits too, not only init), pair runs, test P(A>B) against
  γ = 0.75 (≈ 29 paired runs for α = β = 0.05). Expensive runs: say how few you had and narrow the claim.
- **Pair**: same seeds, splits/folds and eval examples for A and B; analyze *differences*. Per-example paired
  bootstrap/McNemar answers "this trained A vs this trained B"; across seeds answers "method A vs B" (usually the claim).
- **Few runs**: with ≤ ~10 seeds use a t-interval on paired differences (or Bayesian); percentile bootstrap
  under-covers at tiny n. Show mean ± CI *and* all runs (strip plot with pairing lines). Best-of-N is not a result.
- **Cross-validation scores are correlated** (overlapping training sets): a plain t-test over folds is anticonservative.
  Use the Nadeau–Bengio corrected resampled t-test or the Bayesian correlated t-test (`baycomp.two_on_single(a, b,
  rope=…, runs=…)`, Benavoli et al. 2017 JMLR); prefer these to Dietterich's 5×2cv.
- **Many datasets/tasks**: don't average raw scores of different scales.
  - rliable (Agarwal et al. 2021, "Deep RL at the Edge of the Statistical Precipice"): normalized scores → IQM with
    stratified-bootstrap CIs, performance profiles, probability of improvement. Score arrays are `(runs, tasks)`.
  - Two classifiers over datasets: `baycomp.two_on_multiple(x, y, rope=…)` (Bayesian signed-rank / hierarchical) →
    (P(x better), P(practically equivalent), P(y better)). Friedman + Nemenyi CD diagrams (Demšar 2006) are dated:
    the Nemenyi result depends on which other methods are included; prefer pairwise effect sizes + ROPE.
- **HPO**: same search space size, strategy and trial count per method; expected-validation-performance vs budget
  curves (Dodge et al. 2019, "Show Your Work") when budgets differ; select on validation only; report search spaces.
- **Practical significance**: weigh the gain against seed noise and cost (params, FLOPs, latency, memory, energy);
  claim "no worse" only with an equivalence test/ROPE.

```python
# /// script
# requires-python = ">=3.11"
# dependencies = ["rliable"]          # PyPI only; its dep `arch` 7.x breaks on pandas 3
# [tool.pixi.dependencies]
# python = "3.12.*"
# arch-py = "<8"
# pandas = "<3"
# ///
import numpy as np
from rliable import library as rly, metrics
scores = {"A": np.load("A.npy"), "B": np.load("B.npy")}           # (runs, tasks), normalized
agg = lambda x: np.array([metrics.aggregate_iqm(x), metrics.aggregate_mean(x), metrics.aggregate_optimality_gap(x)])
pe, ci = rly.get_interval_estimates(scores, agg, reps=50_000)      # stratified bootstrap over runs per task
pi, pi_ci = rly.get_interval_estimates({"A,B": (scores["A"], scores["B"])}, metrics.probability_of_improvement)
```
Run with `pixi run --script compare.py`; plots: `rliable.plot_utils.plot_interval_estimates`, `plot_performance_profiles`,
`plot_probability_of_improvement`.

## LLM and benchmark evaluations

- Treat questions as a sample: report SE/CI; when questions come in groups (passages, translations of one item,
  multi-turn dialogues) cluster the SE by group — Miller 2024 (arXiv 2411.00640) found clustered SEs up to ~3× naive.
  Compare models on **question-level paired differences**; report n questions *and* n clusters.
- Fix and report prompt, few-shot examples, decoding settings, answer extraction, model version/date. Reduce variance by
  sampling several answers per question, not by lowering temperature (Miller); check sensitivity to prompt paraphrases.
- **Contamination**: check n-gram/embedding overlap of benchmark items with training data, or knowledge cut-off vs
  benchmark release; prefer private or post-cut-off items; report the check.
- LLM-as-judge: validate against human labels (agreement with CI), randomize answer order, hide model names, report the
  judge model and prompt.

## Ablation studies

- Leave-one-out from the full model (does removing X hurt?) and build-up from the baseline (does adding X help?); full or
  fractional factorial (2^k) when components may interact and runs are cheap; report interactions, not only main effects.
- Replace with a sensible alternative, not just deletion; keep params/compute comparable when the claim is about the
  idea, not capacity (add a capacity-matched control). Re-tune key hyperparameters (at least LR) per variant if the
  component changes optimization dynamics; state what was re-tuned.
- Same seeds, budget and data for every row; each row with seed spread/CI; confirm the full model reproduces the
  headline number in the ablation setting.
- Table of Δ vs full model with CI; deltas within seed noise are "no detectable effect", not a ranking.

## Splits and validation

- Train / validation (selection) / test (touched once; report every additional use). An extra OOD test set (new site,
  device, period) when deployment differs.
- **Dependent data needs blocked splits** (Roberts et al. 2017, Ecography): groups → `GroupKFold` (supports
  `shuffle=True, random_state` in scikit-learn ≥ 1.6), `StratifiedGroupKFold`, `GroupShuffleSplit`,
  `LeaveOneGroupOut`; time → `TimeSeriesSplit(n_splits, gap=…, test_size=…)` (gap ≥ label horizon/feature window);
  space → spatial blocks used as groups; sequences/molecules → cluster by similarity, split by cluster.
- Put every fitted preprocessing step inside a `sklearn.pipeline.Pipeline` so CV refits it per fold; nested CV
  (`GridSearchCV` inside `cross_val_score`) when tuning on small data. Report spread across folds.
- **Leakage** (Kapoor & Narayanan 2023, Patterns; 8 types): preprocessing/selection/imputation fit on all data;
  (near-)duplicates or the same subject across splits; features unavailable at prediction time; temporal leakage;
  test set used for early stopping, thresholds or selection; label proxies in IDs, filenames, acquisition metadata.
  If a trivial model does suspiciously well, look for leakage.

## Reproducibility

- Seed everything per run and record it (Python, NumPy, torch, CUDA, dataloader workers via `worker_init_fn`/generator).
  Bit-exact runs when affordable: `torch.use_deterministic_algorithms(True)` + env `CUBLAS_WORKSPACE_CONFIG=:4096:8`,
  `torch.backends.cudnn.benchmark = False`; otherwise state that runs are nondeterministic and rely on repeats.
- Pin everything: Pixi lock file, code commit (dirty-tree flag), data version (HF dataset revision sha or file hashes),
  hardware/driver/CUDA. Log all to MLflow (ml-training skill): params, configs, per-step and final metrics, the plan,
  `mlflow.log_input(mlflow.data.from_pandas(df, source=…, name=…), context="train")` for data lineage, tags for
  experiment/variant/seed. Build tables and figures with `mlflow.search_runs` in a script, never by hand.
- Keep a results log including failed, negative and abandoned runs; record deviations from the plan.

## Reporting

- Standards (check current versions on EQUATOR; `library_search` for items): ML-based science → **REFORMS** (32
  items, Kapoor et al. 2024); ML venues → NeurIPS paper checklist (mandatory, in the template) and venue equivalents;
  NeurIPS 2026 Evaluations & Datasets track requires Croissant with RAI fields for new datasets (datasets skill);
  clinical prediction → **TRIPOD+AI** (2024), LLM studies in health → **TRIPOD-LLM** (2025); AI diagnostic accuracy →
  **STARD-AI** (2025); trials → **CONSORT 2025** (30 items; supersedes 2010), protocols → SPIRIT 2025, AI trials →
  CONSORT-AI/SPIRIT-AI; medical imaging AI → CLAIM; observational → STROBE; reviews → PRISMA 2020; psychology →
  APA JARS; artifacts → ACM badges v1.1 (Artifacts Available; Evaluated – Functional/Reusable; Results Reproduced/
  Replicated).
- Always include: what was compared, budgets (HPO trials, GPU-hours), seeds/folds and pairing, CIs, the exact
  statistical procedure, all comparisons and ablations, failure cases, limitations, compute used.

## Pitfalls (Lones, "How to avoid ML pitfalls"; Kapoor & Narayanan)

Untuned or outdated baselines; best seed or cherry-picked runs; metric or test set chosen after seeing results; test
reuse; leakage; random splits of grouped/temporal data; t-tests over CV folds; averaging raw scores across tasks;
ignoring class imbalance (ml-metrics); one dataset → general claim; statistical vs practical significance; unequal
compute; unreported compute; unclustered errors on grouped eval items; benchmark contamination.
