---
name: ml-tuning
description: Set training hyper-parameters well and fast — Leslie N. Smith's disciplined approach (LR range test, cyclical learning rates, 1cycle and super-convergence, batch size, cyclical momentum, weight decay, balancing regularization), learning-rate schedules (warmup, cosine, WSD, schedule-free), batch size vs learning rate, optimizers (AdamW, SGD, Muon, SOAP/Shampoo, Lion, LAMB; what the 2025–26 benchmarks really show), normalization (BatchNorm, LayerNorm, RMSNorm, GroupNorm, pre-/post-norm, normalizer-free), regularization in and out of the model (weight decay, dropout, stochastic depth, label smoothing, mixup/CutMix, augmentation, SAM, early stopping), EMA/SWA weight averaging, self-normalizing networks (SELU) and implicit self-regularization, and µP. Load before choosing or tuning optimizer, learning rate, batch size, schedule, normalization or regularization.
---

# Tuning training: learning rate, batch size, optimizer, regularization

Cite the papers through the reference library (`library_search`, e.g. "1cycle momentum", "Muon speedup scale") when
you state their numbers. Compare settings with the experiment-design skill (same budget, several seeds).

## 1. Leslie N. Smith's disciplined approach (use as the default recipe)

Sources: *Cyclical Learning Rates* (arXiv 1506.01186), *Super-Convergence* (1708.07120, with Topin), *A disciplined
approach to neural network hyper-parameters, Part 1* (1803.09820), *General Cyclical Training* (2202.08835),
*Best Practices for Applying Deep Learning to Novel Applications* (1704.01568).

- **Read the validation loss, not only accuracy.** Underfitting: val loss still falling; overfitting: val loss rising
  (sometimes only early, or only at small learning rates). The goal is the flat bottom between them; clues appear in
  the first few hundred to few thousand iterations, so tune with short runs.
- **LR range test**: one short run with the learning rate increasing linearly (or exponentially) from tiny to large;
  plot loss vs LR. The LR where loss stops improving / starts rising is the **maximum** for cyclical schedules (a
  constant LR must be smaller). Repeat it when the architecture, data, batch size or regularization changes.
- **Cyclical LR (CLR)**: LR moves linearly between min and max (triangular); stepsize (half cycle) **2–10 epochs'
  worth of iterations**; stop at the end of a cycle. Min LR: max/3–4 for several cycles, **max/10–20 for one cycle**.
- **1cycle** (for super-convergence): a single cycle that ends before training ends, then the LR decays **several
  orders of magnitude below the starting LR** for the remaining iterations. In PyTorch: `OneCycleLR(max_lr=…,
  total_steps=…, pct_start≈0.25–0.3, div_factor≈10–25, final_div_factor≈1e3–1e4, cycle_momentum=True,
  base_momentum=0.85, max_momentum=0.95)` (for Adam it cycles `beta1`).
- **Cyclical momentum**: momentum **decreases while the LR increases** (e.g. 0.95 → 0.85) and rises again as the LR
  falls; with a constant LR use a large constant momentum (0.9–0.99). A momentum range test does not find an optimum;
  try 0.99, 0.97, 0.95, 0.9 in short runs.
- **Batch size**: use a large batch that fits in GPU memory so a larger LR can be used; compare batch sizes at **equal
  wall-clock time**, not equal epochs (Remark 4). Smaller batches regularize more.
- **Weight decay**: grid by bisecting the exponent (e.g. 3×10⁻⁵, 10⁻⁴, 3×10⁻⁴); one significant figure is enough.
  Complex data/deep nets need less (10⁻⁴…0), shallow nets more (10⁻²…10⁻⁴). Search WD together with the LR range
  test; restarting from a mid-training snapshot with different WD values saves time.
- **Balance regularization (Remark 3)**: large learning rates regularize, so when you use them **reduce other
  regularization** (weight decay, dropout, augmentation strength). In Smith's CIFAR experiments, weight decay 10⁻³
  prevented super-convergence that worked at smaller values.
- **General cyclical training** (2202.08835): start and end training "easy", keep the hard part in the middle (cyclical
  weight decay, softmax temperature, gradient clipping, augmentation, batch size). A position paper; treat individual
  techniques as things to test, not defaults.
- Caveat: these experiments are mostly SGD+momentum on CNNs (CIFAR, ImageNet). The principles (range test, warmup then
  decay, regularization balance, equal-time comparisons) transfer; exact numbers do not, especially to Adam-family
  optimizers and transformers.

## 2. Schedules and batch size (current practice)

- **Warmup** (linear, 1–5% of steps or a few hundred–thousand steps) for Adam-family and large batches; it is the
  "increasing" half of 1cycle.
- Decay: **cosine to ~0–10% of peak**, linear decay, or **WSD** (warmup–stable–decay: constant LR, then a short
  linear/cosine decay at the end; lets you branch off checkpoints for different budgets). **Schedule-Free**
  AdamW/SGD (2405.15682) removes the schedule (needs `optimizer.train()/eval()` switching); competitive in some
  benchmarks, worse in others: test it.
- Compare runs only at the end of their schedules: curves cross during decay (2509.02046).
- **Batch size vs LR**: with SGD the linear scaling rule (LR ∝ batch, with warmup) holds up to a critical batch size
  (1706.02677); beyond it, more batch buys little (1811.03600, 1812.06162 gradient noise scale). Adam-family: scale
  LR roughly with √batch as a starting point, then tune. Increasing batch size instead of decaying LR is equivalent
  in SGD's noise scale (1711.00489).
- **µP** (Maximal Update Parametrization, 2203.03466): tune on a small width, transfer LR and init to the large model.
  Worth it when you train a family of sizes.
- Gradient clipping (global norm 1.0) is standard for transformers; log the pre-clip norm.

## 3. Optimizers: what to use (evidence as of late 2026)

| Optimizer | Use when | Notes |
|---|---|---|
| **AdamW** (1711.05101) | Default for transformers, most new work | Decoupled WD (not L2 in the gradient); typical β=(0.9, 0.95–0.999), WD 0.01–0.1; `fused=True` |
| **SGD + Nesterov momentum** | CNNs on vision, with 1cycle/cosine | Often generalizes as well or better than Adam for CNNs; needs a good LR range test |
| **Muon** (`torch.optim.Muon`, PyTorch ≥ 2.9; 2502.16982) | 2-D hidden weight matrices of transformers, MLPs, ConvNets (flattened) | Orthogonalizes the momentum update (Newton–Schulz). **Only hidden 2-D weights**: embeddings, output head, norms, biases (and usually the first conv) stay on AdamW. `adjust_lr_fn="match_rms_adamw"` lets it reuse AdamW-tuned LR and WD |
| **SOAP / Shampoo / Kron** (2409.11321) | Longer training (high data-to-model ratio) | Matrix preconditioners; more memory and compute per step |
| **Lion** (2302.06675) | Memory-limited | Sign updates; needs ~3–10× smaller LR and larger WD than AdamW |
| **LAMB / LARS** (1904.00962) | Very large batches | Layer-wise trust ratio |

What the careful benchmarks show:
- With **equally tuned baselines**, gains over AdamW are modest: matrix-based optimizers (Muon, SOAP, Kron) give
  ~1.3–1.4× fewer steps for ~0.1–0.5B-parameter LMs, shrinking to ~1.1× at 1.2B; Muon is best at 1–4× Chinchilla
  data, SOAP/Kron at 8×+ (Wen et al., 2509.02046). Many claimed 2× speedups come from weak baselines.
- **Per step vs wall clock**: Muon's Newton–Schulz costs time; on one GPU with reference kernels it lost to AdamW in
  wall-clock for small LMs but won clearly for small ViTs (2610.21555). Measure time-to-target, not steps.
- **Fine-tuning**: beyond a large pretraining data budget, AdamW-pretrained models fine-tune better than Muon-pretrained
  ones (2611.03633). Tabular MLPs: Muon was the most consistent improvement over AdamW; EMA also helped (2604.15297).
  Diffusion: no single winner; AdamW tuned is a strong default (2609.23055).
- Each optimizer needs its own LR/WD sweep; never transfer AdamW's hyper-parameters to Lion or (without
  `match_rms_adamw`) to Muon.

```python
hidden = [p for n, p in model.named_parameters() if p.ndim == 2 and "embed" not in n and "head" not in n]
others = [p for n, p in model.named_parameters() if not (p.ndim == 2 and "embed" not in n and "head" not in n)]
opt_muon = torch.optim.Muon(hidden, lr=adamw_lr, weight_decay=0.1, adjust_lr_fn="match_rms_adamw")
opt_adam = torch.optim.AdamW(others, lr=adamw_lr, betas=(0.9, 0.95), weight_decay=0.1, fused=True)
# step both every iteration; give each its own LR scheduler; save/load both states
```

## 4. Normalization (in the model)

- **BatchNorm** (1502.03167): CNNs with batch ≥ 16–32 per device; use `SyncBatchNorm` for small per-GPU batches;
  `model.eval()` at inference; fuse into conv for deployment. Bad for tiny batches and sequence models.
- **LayerNorm** (1607.06450) / **RMSNorm** (1910.07467): transformers; RMSNorm is cheaper and now standard in LLMs.
  **Pre-norm** (norm before attention/MLP, 2002.04745) trains stably without long warmup; post-norm can reach better
  quality but is harder to train deep. Final norm before the output head.
- **GroupNorm** (1803.08494): CNNs with small batches (detection, segmentation).
- **Weight normalization** (1602.07868), **normalizer-free** nets with adaptive gradient clipping (NFNets,
  2102.06171): when batch statistics are a problem.
- Do **not** apply weight decay to norm gains/biases and other 1-D parameters (separate param group with WD 0).
- **Out of the model**: normalize inputs (per-channel mean/std from the **training split only**; standardize tabular
  features; log-transform heavy-tailed targets) and fix them with the model; it is part of the deployed pipeline.

## 5. Regularization (in and out of the model)

In the model / loss: weight decay (decoupled), dropout (lower or zero for large pretraining; higher for small data),
**stochastic depth / DropPath** (1603.09382) for deep residual nets and ViTs, **label smoothing** 0.05–0.1
(1512.00567), **SAM** (2010.01412; ~2× compute per step), gradient clipping, smaller batch, larger LR (Smith).

Out of the model: data augmentation (RandAugment 1909.13719, **mixup** 1710.09412, **CutMix** 1905.04899; strength
tuned), more/cleaner data, early stopping on a validation set, weight averaging (below).

Balance them (Smith's Remark 3): adding a regularizer usually means reducing another. Change one at a time and judge
on validation loss at equal compute.

## 6. Weight averaging: EMA and SWA

- **EMA of weights**: keep a shadow copy updated every step, evaluate and ship the EMA weights. Decay 0.999–0.9999
  (higher for longer runs; or a warmup like `min(decay, (1+step)/(10+step))`). Standard in diffusion and many vision
  models; also helped tabular MLPs (2604.15297). Karras et al. (2312.02696) choose the EMA length post hoc.
- **SWA** (1803.05407): average checkpoints from the end of training with a constant or cyclical LR; recompute
  BatchNorm statistics afterwards (`torch.optim.swa_utils.update_bn`).
- PyTorch: `torch.optim.swa_utils.AveragedModel(model, multi_avg_fn=get_ema_multi_avg_fn(0.999))`, call
  `.update_parameters(model)` after each optimizer step; keep it in FP32; save it in checkpoints.
- EMA and schedule-free methods are related (both average iterates); EMA on top of a well-decayed schedule helps less.

## 7. Self-normalizing networks and implicit self-regularization

- **Self-normalizing networks** (SELU, Klambauer et al. 1706.02515): with SELU activations, LeCun-normal init
  (`nn.init.kaiming_normal_(w, nonlinearity="linear")`) and **AlphaDropout**, activations converge to zero mean and
  unit variance without normalization layers. Mostly useful for deep fully connected nets (tabular); in CNNs and
  transformers normalization layers remain the norm. Breaks if you add ordinary dropout, BatchNorm or a different
  init.
- **Implicit regularization of SGD**: SGD with a finite learning rate implicitly penalizes the gradient norm (implicit
  gradient regularization, 2009.11162; S. L. Smith et al. 2101.12176); this is why larger LR / smaller batch
  regularize and why the LR/batch ratio matters. Large-batch training without adjustments tends to sharper minima
  (1609.04836).
- **Heavy-tailed self-regularization** (Martin & Mahoney, 1810.01075, JMLR 2021): the spectra of trained weight
  matrices show regularization emerging from training itself; the power-law exponent α of each layer's eigenvalue
  distribution tracks training quality and can be checked without test data (the `weightwatcher` package). Useful
  as a diagnostic, not a training method.
- **Self-regularized learning methods** (2603.17160) formalize the same idea for learning theory. Don't confuse these
  with self-supervised or self-distillation methods.

## 8. A tuning order that works

1. Data pipeline fast and correct (ml-data skill); overfit a tiny subset to check the model can learn.
2. Optimizer default (AdamW, or SGD+Nesterov for CNNs), WD 0.01–0.1 (AdamW) / 10⁻⁴…5×10⁻⁴ (SGD).
3. Largest batch that fits; LR range test; 1cycle or warmup+cosine with the max LR from the test.
4. Momentum/β short runs; WD exponent grid; then regularization balance (augmentation, dropout, label smoothing).
5. EMA on; final comparison at equal wall-clock with ≥ 3 seeds (experiment-design skill).
6. Only then try another optimizer (Muon/SOAP), each with its own LR/WD sweep, judged on time-to-target.
