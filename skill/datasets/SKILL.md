---
name: datasets
description: Build, curate, organize and document datasets — scoping and sampling, collection and consent, labeling guidelines and inter-annotator agreement, cleaning, deduplication and near-duplicate detection, leakage-safe splits, distribution shift and bias audits, data documentation (datasheets, data cards, Croissant, data statements), versioning and storage layout, licenses, and publishing (Hugging Face). Load before creating, cleaning, splitting, labeling or publishing data.
---

# Datasets: making, curating and using them

## 1. Scope

- Write down the task, the target population/distribution the model will face, and what a sample unit is (image,
  sentence, patient visit, sensor window). Mismatch between collected data and deployment conditions is the most common
  silent failure.
- Decide what metadata every sample needs (source, time, location/site, device/sensor, collector, license, consent,
  subject/group id for grouped splits).

## 2. Collection and sampling

- Prefer a documented sampling procedure (stratified by known factors: site, device, demographic, condition) over
  convenience sampling; record what was excluded and why.
- Legal and ethical: licenses and terms of use per source, consent and privacy (PII/PHI removal, de-identification),
  institutional approval where required. Keep provenance per sample.

## 3. Labeling

- Write labeling guidelines with definitions, edge cases and examples; pilot on a small set, measure agreement, revise.
- Multiple annotators on a subset; report agreement (Cohen's κ for 2, Fleiss' κ or Krippendorff's α for more, ICC for
  continuous); adjudicate disagreements; keep raw labels, not only the final ones.
- Track annotator id and time; check for drift and fatigue. For noisy labels, estimate noise (confident learning,
  disagreement) and consider soft labels.

## 4. Cleaning and curation

- Validate schema and ranges; handle missing values explicitly (record why they are missing).
- **Deduplicate**: exact hashes, then near-duplicates (perceptual hashes for images, MinHash/embeddings for text,
  signal similarity for sensors). Deduplicate *before* splitting and also across splits.
- Remove or flag corrupted files, label errors, outliers (document the rule; never silently drop).
- Balance and coverage: count per class and per metadata stratum; look for rare but important strata.

## 5. Splits

- Split by the independent unit (patient, user, scene, recording session, site, time period) — never by rows when rows
  are correlated. Time-ordered tasks: train on the past, test on the future.
- Freeze splits in files (lists of ids) committed or versioned with the data; never re-split ad hoc.
- Hold out a test set touched once; consider an out-of-distribution test set (new site/device/time) to measure robustness.
- Check for leakage: duplicates across splits, shared subjects, features derived from the label or the future.

## 6. Audits

- Distribution shift between splits and vs deployment data (per-feature statistics, domain classifier test).
- Performance by subgroup/stratum (fairness and robustness slices), with CIs.
- Sanity baselines (majority class, simple models) to detect trivially solvable or broken data.

## 7. Documentation

Every dataset gets a card (README) answering the Datasheets for Datasets questions: motivation, composition, collection,
preprocessing/cleaning/labeling, uses (and uses to avoid), distribution, maintenance. Use the Data Cards structure for
audiences; Croissant JSON-LD for machine-readable metadata (Hugging Face and others read it); data statements for language
data. Include counts per split and stratum, known issues, and the license.

## 8. Organization and versioning

```
data/
  raw/            # immutable, as received (read-only); provenance.json per source
  interim/        # intermediate, reproducible from raw by scripts
  processed/      # final model inputs (e.g. Parquet/Arrow, WebDataset shards)
  splits/         # train.txt / val.txt / test.txt (ids), frozen
  README.md       # the data card
scripts/          # every transformation, run through Pixi tasks
```
- Raw data is never edited; every step is a script (`pixi run prepare`), deterministic, with seeds.
- Version data with content hashes: Hugging Face dataset repos (pin the revision sha), DVC, or object storage with
  manifests (sha256 per file). Record the data version in every MLflow run.
- Formats: Parquet for tables, Arrow/`datasets` for mixed, WebDataset/TFRecord-like shards for large media; keep
  metadata in a table keyed by sample id.

## 9. Publishing

Hugging Face (see the huggingface skill): dataset repo with the card, splits as configurations, license, and Croissant
metadata; gated access when terms must be accepted. Don't publish data you don't have the rights to share.

## Tools (Python through Pixi)

pandas/polars, pyarrow, `datasets`, `cleanlab` (label issues), `imagededup` or perceptual hashing, `datasketch` (MinHash),
`great-expectations` or `pandera` (schema validation), `scikit-learn` (`GroupKFold`, `StratifiedGroupKFold`,
`TimeSeriesSplit`). Look up methods and checklists with `library_search` (datasheets, data cards, leakage).
