---
name: datasets
description: Build, curate, organize and document datasets — scoping and sampling, collection, consent, privacy and licenses, labeling guidelines and inter-annotator agreement (κ, Krippendorff's α, ICC), label-error detection (cleanlab), cleaning and validation, deduplication and near-duplicate detection (hashes, MinHash LSH, embeddings), leakage-safe splits, distribution shift and bias audits, documentation (datasheets, data cards, data statements, Croissant 1.1 with RAI), versioning and storage layout, and publishing on Hugging Face. Load before creating, cleaning, splitting, labeling or publishing data.
---

# Datasets: making, curating and using them

Related: experiment-design (splits, leakage, evaluation), ml-data (formats and loaders for training speed),
stats-inference (agreement statistics, CIs), huggingface (Hub mechanics). Python via Pixi only.

## 1. Scope

- Write down the task, deployment population/conditions, the **sample unit** (image, sentence, visit, sensor window)
  and the **independent unit** (patient, user, scene, site). Collected ≠ deployed distribution is the most common
  silent failure. Fix per-sample metadata up front: id, source, time, site/device, annotator, license, consent, group id.

## 2. Collection, consent, licenses

- Documented sampling (stratified by site, device, demographic, condition) over convenience sampling; log exclusions
  with reasons and counts.
- Per source: license/terms of use (SPDX id), provenance, retrieval date. Web data: honor robots/opt-outs and terms;
  mixed licenses → the most restrictive governs redistribution. Don't redistribute what you may only use.
- Personal data: legal basis/consent, IRB/ethics approval where required, PII/PHI removal (de-identify faces, names,
  ids, EXIF/GPS, free text), data minimization; record it for the card.

## 3. Labeling

- Guidelines with definitions, decision rules, edge cases and positive/negative examples; pilot on ~50–200 items,
  measure agreement, revise, repeat. Version the guidelines; record which version each label used.
- Double-annotate a random subset (≥ 10–20%, more for hard tasks). Agreement (stats-inference skill):
  - 2 raters nominal: Cohen's κ (`sklearn.metrics.cohen_kappa_score`; `weights="quadratic"` for ordinal).
  - Fixed set of ≥ 3 raters: Fleiss' κ (`statsmodels.stats.inter_rater.aggregate_raters` → `fleiss_kappa`).
  - Missing ratings, any number of raters, any scale: Krippendorff's α (`krippendorff.alpha(reliability_data=raters×items,
    level_of_measurement="nominal"|"ordinal"|"interval"|"ratio")` — PyPI package; default is **interval**, set it).
  - Continuous: ICC (`pingouin.intraclass_corr`; choose the form, e.g. ICC2/ICC2k); Bland–Altman for bias.
  - Report with a bootstrap CI over items; κ depends on prevalence, so also give raw % agreement and per-class
    confusion between annotators.
- Adjudicate; keep **all raw labels** + annotator id + timestamp. Track drift/fatigue with gold questions.
- Label errors: `cleanlab.filter.find_label_issues(labels, pred_probs)` with **out-of-sample** `pred_probs`
  (`cross_val_predict`); multiple annotators → `cleanlab.multiannotator.get_label_quality_multiannotator` (CROWDLAB);
  `cleanlab.Datalab` (needs `datasets`) also flags outliers, near-duplicates, non-IID. Review flagged items by hand;
  never auto-drop test labels. Ambiguous items: keep soft labels/disagreement as signal.

## 4. Cleaning and validation

- Schema/range checks as code (`pandera` or Great Expectations), run on every rebuild. Missing values explicit, with
  reason; never silent fills. Decode every media file once to catch corruption. Flag outliers/errors in a column
  naming the rule; drop only by a logged, counted rule. Count per class × stratum to find rare-but-important strata.

## 5. Deduplication (before splitting; then again across splits)

- Exact: sha256 of normalized content (bytes for media; normalized text: Unicode NFC, whitespace, case as appropriate).
- Near-duplicate text: MinHash + LSH over word/char n-gram shingles (`datasketch.MinHash(num_perm=128)`,
  `MinHashLSH(threshold=0.8, num_perm=128)`); Lee et al. 2022 (ACL, "Deduplicating Training Data Makes LMs Better")
  found train–test overlap and showed dedup lowers memorization.
- Images: perceptual hashes (`imagehash.phash`, `imagededup`); semantic duplicates: embedding cosine similarity
  (CLIP/DINOv2/sentence embeddings + FAISS), e.g. SemDeDup (Abbas et al. 2023). Sensors: windowed signal similarity.
- Set thresholds by inspecting pairs near them; store a duplicate-cluster id so splits can group by it. For eval
  sets, also check overlap with public pretraining corpora/benchmarks (contamination).

## 6. Splits

- Split by the independent unit (and by duplicate cluster), never by rows when rows are correlated: `GroupShuffleSplit`,
  `StratifiedGroupKFold`; time-ordered tasks: train on past, test on future, with a gap ≥ label horizon.
- Freeze splits as id lists (`splits/*.txt` or a `split` column) versioned with the data; never re-split ad hoc.
- One test set touched once; add OOD tests (new site/device/period) when deployment will shift.
- Verify after splitting: zero shared groups/duplicate clusters across splits; label and stratum distributions per split.

## 7. Audits

- Shift between splits and vs deployment: per-feature statistics (KS / PSI / χ²), a domain classifier (AUC ≫ 0.5 means
  separable splits), embedding-space checks for media.
- Performance by subgroup/stratum with CIs (fairness and robustness slices; ml-metrics).
- Sanity baselines (majority class, metadata-only model, linear model): if metadata alone predicts the label, you
  have a shortcut or leak.

## 8. Documentation

- Every dataset gets a card (`README.md`): answer the Datasheets for Datasets questions (Gebru et al.; motivation,
  composition, collection process, preprocessing/cleaning/labeling, uses, distribution, maintenance); use the Data
  Cards structure (Pushkarna et al. 2022) for audience-oriented summaries; Data Statements (Bender & Friedman 2018) for
  language data (speakers, varieties, annotators). Include counts per split × stratum, agreement stats, known issues,
  license, citation, contact, version history.
- Machine-readable: **Croissant** (MLCommons). Current spec 1.1 (Jan 2026; adds PROV-O provenance, DUO/ODRL usage
  policies, external vocabularies); **Croissant RAI 1.0** adds `rai:` fields (`dataCollection`, `dataAnnotationProtocol`,
  `dataBiases`, `dataLimitations`, `dataUseCases`, `personalSensitiveInformation`, …). Hugging Face auto-serves core
  Croissant at `https://huggingface.co/api/datasets/<id>/croissant` (Croissant 1.0, no RAI as of Nov 2026); add RAI
  yourself. NeurIPS 2026 Evaluations & Datasets track requires a validated Croissant file with core + minimal RAI.
- Validate and load: `mlcroissant validate --jsonld metadata.json`; `mlcroissant.Dataset(jsonld=…).records(record_set=…)`
  (`pixi exec --spec python=3.12 --spec mlcroissant …`). `library_search` the datasheet/data-card questions.

## 9. Organization and versioning

```
data/
  raw/          # immutable, as received (read-only); provenance.json per source (url, license, date, sha256)
  interim/      # reproducible from raw by scripts
  processed/    # model inputs (Parquet; WebDataset/MDS shards for media — see ml-data)
  splits/       # frozen id lists
  README.md     # the card; croissant.json
scripts/        # every transformation, run as Pixi tasks (`pixi run prepare`)
```
- Raw is never edited; every step is a deterministic, seeded script; a manifest (path, sha256, size) per release.
- Version with content hashes: HF dataset repo (pin `revision=<commit sha>` in `load_dataset`; tag releases with
  `hf repos tag create <id> v1.0 --repo-type dataset`), DVC, or object storage + manifests; bump the major version when
  splits/labels change. Log the data version in every MLflow run (`mlflow.log_input`). Keep labels in a table keyed
  by sample id, separate from media.

## 10. Publishing (Hugging Face; see the huggingface skill)

- Only data you have the right to share; check every source license and consent scope.
- Card YAML: `license`, `pretty_name`, `task_categories`, `size_categories`, `configs` (data_files per split). Parquet
  files; `Dataset.push_to_hub(repo_id, config_name=…, private=True)` or `hf upload <id> <dir> --repo-type dataset`.
- Gate when terms must be accepted: `hf repos settings <id> --gated manual|auto --repo-type dataset`. Start private, check
  the dataset viewer and Croissant, then make public; tag the release; get a DOI if it must be cited.

## Tools (all via Pixi; conda-forge unless noted)

pandas/polars, pyarrow, `datasets`, `huggingface_hub` (`hf` CLI), `cleanlab`, `datasketch`, `imagehash`, `imagededup`,
`krippendorff` (PyPI), `pingouin`, `statsmodels`, `pandera`/`great-expectations`, `scikit-learn` splitters,
`mlcroissant`, `fiftyone` (visual dataset review), `mlflow`.
