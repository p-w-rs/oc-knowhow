---
name: ml-metrics
description: Compute and interpret evaluation metrics correctly — classification (precision, recall, F1/Fβ, ROC-AUC vs PR-AUC, thresholds, calibration/ECE), object detection (IoU, AP/AR, COCO mAP@[.5:.95], AP50/AP75, AP/AR small/medium/large, maxDets, per-class, LVIS/Open Images variants, LRP), TIDE error analysis to decide what to fix next (classification, localization, duplicate, background, missed; FP vs FN), instance/semantic/panoptic segmentation (mIoU, Dice, Boundary IoU, PQ), keypoints (OKS), tracking (HOTA, MOTA, IDF1), 3D/autonomous driving (NDS), regression and forecasting, ranking/retrieval (nDCG, MRR, recall@k), generation (FID/KID, BLEU/chrF, BERTScore, CLIPScore, pass@k), with tools (pycocotools, faster-coco-eval, torchmetrics, tidecv) and how to report them (intervals, per-group, choosing the metric for the decision). Load before evaluating a model, choosing a metric, or explaining why a score changed.
---

# Metrics: compute them right, pick the one that matches the decision

Ground truth: Metrics Reloaded (2206.01653) and its pitfalls paper (2302.01790) for choosing metrics; COCO
(1405.0312) and the `pycocotools` code for detection definitions; TIDE (2008.08115) for detection errors. Cite via
`library_search`. Report every metric with a confidence interval (bootstrap over images/samples, see
stats-inference) and compare models at equal settings (experiment-design).

## 0. Before computing anything

1. **What decision does the number support?** (ship/no-ship at an operating point, rank models, find what to fix).
   That picks the metric; one headline metric, a few diagnostic ones.
2. **The unit of evaluation**: per image, per object, per pixel, per patient/site? Aggregate the way the decision
   needs (macro over classes vs micro over instances; per-image then mean vs pooled).
3. **Use the reference implementation** for published benchmarks (pycocotools, official devkits); reimplementations
   differ in tie-breaking, crowd handling, area definitions and interpolation. Write the exact settings in the report.
4. **Sanity-check the evaluator**: GT evaluated as predictions (score 1.0) must give AP = 1.0; empty predictions 0;
   shuffled labels ≈ chance.

## 1. Classification

- Precision = TP/(TP+FP), recall (sensitivity) = TP/(TP+FN), specificity = TN/(TN+FP); F1 = harmonic mean; Fβ
  weights recall β times as much. **State the threshold**; tune it on validation, never on test.
- **ROC-AUC** is insensitive to class imbalance in a way that hides poor precision; with rare positives report
  **PR-AUC / average precision** (and its baseline = positive rate). Balanced accuracy or MCC for imbalanced
  single-number summaries; per-class recall for multi-class (confusion matrix).
- Multi-class/multi-label: say **macro** (mean over classes; rare classes count equally) vs **micro** (pooled) vs
  weighted. Top-k accuracy for large label sets.
- **Calibration** (1706.04599): reliability diagram, ECE (state bin count and equal-width vs equal-mass bins; prefer
  adaptive bins), Brier score, NLL. Fix with temperature scaling on a validation split. Tools: `torchmetrics`
  `MulticlassCalibrationError(num_classes, n_bins=15, norm="l1")` (top-label ECE, equal-width bins);
  `sklearn.calibration.calibration_curve(y, p, n_bins=…, strategy="quantile")` for equal-mass bins (binary);
  `CalibratedClassifierCV` / `brier_score_loss` for sklearn models.
- Operating point metrics: recall at fixed precision (or FPR), cost-weighted error when costs are known.

## 2. Object detection (COCO conventions)

**Matching**: per image and class, detections sorted by score; each greedily matched to the unmatched GT with the
highest IoU ≥ threshold; a GT matches at most one detection (others are FPs); crowd GT (`iscrowd`) absorbs
detections without counting as FN; ignored GT (outside the area range) don't count either way.

**AP**: area under the interpolated precision–recall curve. COCO: precision made monotone (max to the right),
sampled at **101 recall points** (0:0.01:1), averaged. **mAP** = mean over classes (COCO calls it AP). VOC2007 used
11 points, VOC2010+ all points: AP values are not comparable across these definitions.

**The 12 COCO numbers** (`COCOeval.summarize()`; IoU thresholds **0.50:0.05:0.95**, maxDets **1, 10, 100**):

| stat | name | meaning |
|---|---|---|
| 0 | AP | mean over 10 IoU thresholds, all areas, maxDets 100 (the headline) |
| 1, 2 | AP50, AP75 | at IoU 0.50 (loose localization) and 0.75 (strict) |
| 3–5 | AP_S, AP_M, AP_L | objects with area < 32², 32²–96², > 96² pixels |
| 6–8 | AR1, AR10, AR100 | average recall (over IoU .5:.95) with at most 1/10/100 detections per image (per class, see below) |
| 9–11 | AR_S, AR_M, AR_L | AR100 by object size |

Facts people get wrong:
- **Area** is the GT annotation's `area` field (the **mask** area for COCO instances, not the box area); for your own
  data compute it consistently and say which. Size buckets are absolute pixels at the evaluated resolution.
- AR is the max recall over the PR curve, averaged over IoU thresholds (and classes); it measures how many objects
  are found at all, independent of score calibration. AR1 vs AR100 shows whether the top detection per image is right.
- In `pycocotools`, maxDets = 100 keeps the top-100 detections **per image and per category** (`evaluateImg` slices
  each image–class pair), not 100 across classes; other evaluators (LVIS: 300 per image across classes) differ, and
  models that emit thousands of boxes gain AP from long low-score tails. Dense scenes need a higher cap (say so).
- Categories (or size buckets) without GT get precision −1 and are excluded from the mean; mask `-1` before
  averaging `E.eval['precision']` yourself, or an empty class silently drags AP down.
- AP50 high but AP75 low → localization problem; AP_S far below AP_L → resolution/stride/anchor problem; AR100 high
  but AP low → ranking/score/duplicate problem.
- Class imbalance: report per-class AP (`class_metrics=True` / `eval.eval['precision'][T,R,K,A,M]`) and the worst
  classes; mean AP hides them. LVIS (1908.03195) splits AP into rare/common/frequent (APr/APc/APf), uses federated
  labels (unlabeled classes in an image are not penalized) and 300 detections per image; **AP-fixed** (Dave et al.
  2102.01066) instead caps 10,000 detections per class over the whole set, removing the cross-class ranking
  dependence — state which. Open Images (1811.00982) uses hierarchy and verified negative labels. Use the
  benchmark's own evaluator.
- **Open-vocabulary detection** (OVR-CNN 2011.10678, GLIP 2112.03857): report AP on **novel** (unseen) classes
  separately from base classes (e.g. COCO 48/17 split AP50_novel, LVIS APr); the text prompts/vocabulary used at
  test time are part of the setting.
- **Detection confusion matrix**: match at a fixed IoU (0.5) and score threshold, add a "background" row/column for
  unmatched predictions (FP) and missed GT (FN); counts depend on both thresholds, so state them. Useful for
  confusable classes; TIDE (below) weights the same errors by their effect on AP.
- LRP (1807.01696) combines localization quality, FP and FN into one error and gives an optimal threshold per class;
  useful when you need an operating point, not just ranking quality.

**Tools**:

```python
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval
gt = COCO("instances_val.json"); dt = gt.loadRes("detections.json")   # [{image_id, category_id, bbox:[x,y,w,h], score}]
E = COCOeval(gt, dt, iouType="bbox")   # "segm" for masks, "keypoints" for OKS
E.evaluate(); E.accumulate(); E.summarize(); stats = E.stats           # the 12 numbers above
# E.params.maxDets = [1, 10, 300]; E.params.catIds = [...]; E.params.areaRng / areaRngLbl to change buckets
```
Gotcha: `summarize()` computes stats[0] with a hard-coded maxDets = 100 (the others use `maxDets[2]`), so with
`maxDets=[1, 10, 300]` the headline AP prints −1; read AP from `E.eval['precision']` (mask −1) or keep 100 in the list.

`faster-coco-eval` is a faster drop-in (`from faster_coco_eval import COCO, COCOeval_faster`; PyPI only, not on
conda-forge); `torchmetrics` `MeanAveragePrecision(iou_type="bbox", class_metrics=True, backend="faster_coco_eval")`
for in-training evaluation (`from torchmetrics.detection import MeanAveragePrecision` needs `torchvision`
installed; boxes default to `xyxy`, COCO JSON is `xywh`: set `box_format`; `max_detection_thresholds` changes
maxDets). Validate any custom evaluator against pycocotools on the same predictions.

**Small test sets**: AP is not a mean over independent items, so get its CI by a **bootstrap over images**
(resample image ids with replacement, re-run the evaluator on the resampled set; 1,000 resamples; duplicate ids need
new unique ids) or, for comparing two models, a paired bootstrap on the same resampled images. With < ~50 instances
of a class its per-class AP is very noisy; report counts next to it.

## 3. TIDE: which error to fix next (2008.08115; `pip`/pixi package `tidecv`)

TIDE splits detection error into six types, using a foreground IoU threshold t_f (0.5) and background t_b (0.1),
where IoU_max is a detection's best IoU with any GT:

| Error | Condition | Usually points at |
|---|---|---|
| **Cls** | IoU_max ≥ t_f with GT of the **wrong class** | classifier head, confusable classes, label noise |
| **Loc** | t_b ≤ IoU_max < t_f with GT of the **right class** | box regression, resolution, stride |
| **Both** | t_b ≤ IoU_max < t_f with GT of the wrong class | both of the above |
| **Dupe** | IoU_max ≥ t_f with the right class, but the GT was already matched by a higher-scoring detection | NMS threshold, one-to-one assignment |
| **Bkg** | IoU_max < t_b for all GT (detected background) | hard negatives, false-positive suppression, missing labels in GT |
| **Miss** | GT not detected and not covered by Cls/Loc | recall: small/occluded objects, proposals, input size |

Each error's **ΔAP** is the AP gain from an oracle that fixes only that error, **each computed from the original
AP, not progressively** (progressive fixing, as in COCO's `analyze`, over-weights whatever is fixed last). Applying
all six oracles **together** gives 100 AP, but the individual ΔAPs do **not** add up to 100 − AP (interactions).
Two extra oracles split errors into **FP** (suppress all false positives) and **FN** (set N_GT to the true
positives); together they also reach 100 AP (e.g. Mask R-CNN in the paper: AP50 61.7, ΔAP_FP 16.6, ΔAP_FN 15.3).
At stricter t_f, Loc and FN errors dominate (paper Tab. 3). Fix the largest ΔAP first; re-run TIDE after each change.

```python
from tidecv import TIDE, datasets
tide = TIDE()
tide.evaluate(datasets.COCO("instances_val.json"), datasets.COCOResult("detections.json"), mode=TIDE.BOX)  # TIDE.MASK for masks
tide.summarize(); tide.plot("tide_out/")
```

`tidecv`'s COCO loader needs `file_name` on every image and `segmentation` on every annotation, even for boxes
(use the box as a 4-point polygon). TIDE reports at AP50 by default (`TIDE(pos_threshold=0.5,
background_threshold=0.1)`; `tide.evaluate_range(...)` runs 0.50:0.95); also look at the COCO AP75 vs AP50 gap for
localization. Using TIDE to size the
model: if Miss dominates on small objects, raise input resolution or stride-8 features before adding depth; if Cls
dominates, a stronger backbone/classifier or more data for confusable classes; if Bkg dominates, check GT
completeness before training harder.

## 4. Segmentation, keypoints, tracking, 3D

- **Semantic**: per-class IoU and **mIoU** (from one confusion matrix accumulated over the whole set, not mean of
  per-image IoUs unless stated), pixel accuracy is misleading with imbalance. **Dice/F1** for medical (equals
  2·IoU/(1+IoU) for the same item, but mean Dice ≠ 2·mIoU/(1+mIoU) after averaging); report per-structure and say
  how empty masks (both empty: 1, NaN or skipped?) are scored. Boundary quality: **Boundary IoU** (2103.16562), Hausdorff (HD95)
  and surface distances in mm for medical.
- **Instance**: COCO `segm` AP (mask IoU). **Panoptic**: **PQ = SQ × RQ** (1801.00868), report PQ for things and stuff.
- **Keypoints**: COCO OKS-based AP (`iouType="keypoints"`): OKS = mean over labeled keypoints of
  exp(−d²/(2·s²·k²)), s² = object area, k = 2σ per keypoint (COCO's 17 σ in `E.params.kpt_oks_sigmas`, 0.025 eyes …
  0.107 hips; set your own for other skeletons). Different summary: **10 numbers, maxDets 20, area buckets medium
  and large only** (no small). PCK/PCKh with the normalization stated.
- **Tracking**: **HOTA** (2009.07736) balances detection and association (DetA, AssA); MOTA is dominated by
  detection; IDF1 for identity. Use TrackEval.
- **3D / driving**: nuScenes **NDS** (1903.11027) combines mAP (center-distance matching) with true-positive errors
  (translation, scale, orientation, velocity, attribute); KITTI AP uses easy/moderate/hard difficulty levels,
  class-specific IoU (0.7 car, 0.5 pedestrian/cyclist) and **40 recall points (AP|R40)** since 2019 (the old 11-point
  AP|R11 included recall 0 and inflated scores; Simonelli et al. 1905.12365): state which.

## 5. Other targets

| Target | Primary metrics | Notes |
|---|---|---|
| Regression | MAE, RMSE (in units), R² | report residual plots; MAPE breaks near zero (use sMAPE/MASE) |
| Forecasting | MASE, sMAPE, CRPS / pinball loss for probabilistic | compare against seasonal-naive; rolling-origin evaluation |
| Ranking / retrieval / recsys | nDCG@k, MRR, recall@k, MAP | state k and how ties/unjudged items are handled |
| Metric learning / re-ID | recall@k, MAP@R (2003.08505), CMC/mAP | fixed train/test protocol; no tuning on test |
| Image generation | FID (1706.08500), KID (1801.01401), precision/recall for generative models; CLIPScore (2104.08718) for text alignment | FID depends on sample count, resize and feature extractor: fix and report them |
| Image quality / restoration | PSNR, SSIM, LPIPS | PSNR/SSIM on Y channel vs RGB must be stated |
| Text generation | chrF, BLEU (sacreBLEU signature), BERTScore (1904.09675), human/LLM judgment with agreement | reference-based metrics correlate weakly with quality for open-ended text |
| Code | pass@k = E[1 − C(n−c, k)/C(n, k)] (unbiased, 2107.03374; n samples, c correct, k ≤ n) | not 1 − (1 − p̂)ᵏ (biased low); use the paper's stable product form; sandboxed tests |
| Speech | WER/CER (normalization stated) | |
| Medical / clinical | sensitivity/specificity at a clinically chosen point, PPV/NPV at the real prevalence, calibration | Metrics Reloaded decision tree; TRIPOD+AI (field-methods) |

## 6. Reporting

- One table: headline metric with 95% CI, the diagnostic breakdown (AP50/AP75/S/M/L/AR, per class or group), and
  the exact settings (evaluator and version, thresholds, maxDets, resolution, NMS, test-time augmentation).
- Per-group results (sites, sensors, lighting, object size, rare classes) for anything that will be deployed.
- When comparing models, paired differences per image or per seed with intervals, not two point estimates.
- Evaluate the deployed artifact (quantized engine, see ml-qat/ml-deploy) with the same evaluator.
