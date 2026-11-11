---
name: ml-training
description: Train and evaluate models reproducibly on NVIDIA and AMD GPUs — Pixi environments for CUDA and ROCm PyTorch, MLflow 3 experiment tracking (runs, params, metrics, system metrics, LoggedModels, comparing runs), long runs on remote GPU machines, checkpoints and exact resume, determinism, mixed precision and TF32, torch.compile (modes, graph breaks, recompiles), gradient accumulation, activation checkpointing, OOM debugging, profiling, estimating compute, memory, time and the right parallelism before scaling (rooflines, 6·N·tokens, communication bounds), DDP/FSDP2 with DCP checkpoints and NCCL debugging, and planning for deployment from the start. Load before setting up training, running experiments or comparing results.
---

# Training and experiments

## Environment

- One Pixi workspace per project, committed with `pixi.lock`. NVIDIA and AMD in **separate environments**:
  - `cuda`: conda-forge `pytorch-gpu` + `cuda-version = "13.*"` on a platform that declares CUDA
    (`platforms = [{ platform = "linux-64", cuda = "13.0" }]`; `[system-requirements]` is the deprecated form).
    conda-forge can lag PyPI by a minor (Nov 2026: 2.14.1 vs 2.15.0); else use the `whl/cu13x` index as below.
    For `torch.compile` on GPU also add `cuda-cudart-dev` (Triton compiles a helper against `cuda.h`; without it:
    `fatal error: cuda.h: No such file or directory`) and a C compiler (system `gcc`, or conda-forge `c-compiler`).
    Blackwell (sm_100/sm_120) is in the conda-forge builds (`torch.cuda.get_arch_list()`). Builds for a newer CUDA
    minor than the driver (e.g. `cuda134` on a 13.0 driver) run PyTorch fine, but code that JIT-compiles PTX can fail
    with "the provided PTX was compiled with an unsupported toolchain" (seen with TorchCodec NVDEC); then pin
    `cuda-version` to the driver's minor (older PyTorch) or update the driver.
  - `rocm`: PyTorch ROCm wheels via PyPI (`torch = { version = "…", index = "https://download.pytorch.org/whl/rocm<ver>" }`);
    conda-forge has no ROCm PyTorch. Check https://pytorch.org/get-started for the current index names.
- Verify on the machine before blaming code: `pixi run -e cuda python -c "import torch; print(torch.__version__,
  torch.version.cuda, torch.cuda.is_available(), torch.cuda.get_device_name())"` (ROCm: `torch.version.hip`; AMD GPUs
  still use the `torch.cuda` API). Driver vs toolkit: `nvidia-smi` / `rocm-smi`.
- Code stays device-agnostic (`device = "cuda"`, no CUDA-only libraries without a fallback); test ROCm when it matters.

## MLflow (default experiment tracker)

Use MLflow for every training, evaluation, export and benchmark run (MLflow 3.x; check `mlflow --version`).

- Add `mlflow` (conda-forge) to the project. Local server: `pixi run mlflow server` (UI and API at
  http://127.0.0.1:5000; default backend `sqlite:///mlflow.db`, or an existing `./mlruns` store if present; artifacts
  in `./mlartifacts`). A shared server: set `MLFLOW_TRACKING_URI` (and `MLFLOW_TRACKING_TOKEN` or username/password if
  it needs auth; never hard-code them). Remote access needs `--host 0.0.0.0 --allowed-hosts …`.
- Logging:
  ```python
  import mlflow
  mlflow.set_experiment("detector-v2")                 # or MLFLOW_EXPERIMENT_NAME
  with mlflow.start_run(run_name="r50-640px-bf16", log_system_metrics=True):   # GPU util/memory every 10 s
      mlflow.log_params({"lr": lr, "batch": bs, "precision": "bf16", "git_sha": sha, "data_rev": data_rev})
      for step, metrics in train():
          mlflow.log_metrics(metrics, step=step)
      mlflow.log_artifact("config.yaml")
      info = mlflow.pytorch.log_model(model, name="model", step=step,  # MLflow 3: LoggedModel, load via info.model_uri
                                      input_example=x_example.cpu().numpy())   # needed for the default "pt2" format
  ```
  MLflow 3.18 (outside Databricks) saves PyTorch models as `serialization_format="pt2"` (torch.export) by default: it needs
  `input_example` (a NumPy array works; a CUDA tensor fails the signature check) and loads back as a `GraphModule`.
  For models that don't export, or when you need the `nn.Module` back, pass `serialization_format="pickle"`.
  System metrics need `psutil` + `nvidia-ml-py` (NVIDIA) or `pyrsmi` (AMD). `mlflow.pytorch.autolog()` targets
  Lightning; plain loops log manually. MLflow 3: `name=` (`artifact_path=` deprecated), load via `info.model_uri`
  (`models:/<model_id>`). Log only from rank 0.
- Tag every run with what makes it reproducible: git commit (and dirty flag), Pixi lock hash, dataset revision
  (e.g. Hugging Face dataset sha), seed, hardware (GPU, driver, CUDA/ROCm version).
- Compare instead of eyeballing logs: `mlflow.search_runs(experiment_names=["detector-v2"], filter_string="metrics.val_map
  > 0.5 and params.precision = 'bf16'", order_by=["metrics.val_map DESC"])` (a DataFrame); report the table. Seeds and
  fair comparisons: **experiment-design**; metrics: **ml-metrics**.
- Deployment runs (ml-deploy) go in the same or a linked experiment, tagged with the parent training run id.

## Long runs, checkpoints, resume, seeds

- Run on the remote machine (oc-machine aliases, RunPod, Azure) in `tmux new -d -s train '…'` or `nohup … >
  train.log 2>&1 &`; check with `tail`, `nvidia-smi`/`rocm-smi`, MLflow. rsync results back; stop paid machines.
- Checkpoint regularly: model, optimizer, LR scheduler, GradScaler, EMA model (ml-tuning), step/epoch, RNG states
  (`torch.get_rng_state()`, `torch.cuda.get_rng_state_all()`, NumPy, `random`) and data-loader position
  (`StatefulDataLoader.state_dict()`, see ml-data). Write to a temp file then `os.replace` (atomic), keep the last N,
  log paths. Test resume once: a resumed run must continue the same loss curve.

- **Seeds/determinism**: seed `torch`, NumPy, `random`; DataLoader `generator=` + `worker_init_fn` seeding from
  `torch.initial_seed()` (PyTorch "Reproducibility" notes). Bitwise debugging only (slower):
  `torch.use_deterministic_algorithms(True)`, `cudnn.benchmark = False`, `CUBLAS_WORKSPACE_CONFIG=:4096:8`. Variance
  across runs: several seeds (experiment-design).

## Training performance

- **Measure first**: data vs GPU (system metrics, loader-only benchmark in ml-data). Profile a few steps with
  `torch.profiler.profile(activities=[CPU, CUDA], schedule=schedule(wait=1, warmup=2, active=3))` calling `p.step()`
  each step, then `p.key_averages().table(sort_by="cuda_time_total", row_limit=20)` (or `export_chrome_trace`).
  System-wide: `nsys profile -t cuda,nvtx,osrt --capture-range=cudaProfilerApi …` with `torch.cuda.profiler.start()/stop()`
  around a few steps and `torch.cuda.nvtx.range("fwd")` markers. Kernel-level work: **gpu-kernels**.
- **Mixed precision**: `torch.autocast("cuda", dtype=torch.bfloat16)` on Ampere+/MI200+ (no scaler); FP16 with
  `torch.amp.GradScaler("cuda")` (`scale(loss).backward()`, `unscale_(opt)` before clipping, `step`, `update`).
- **TF32** on NVIDIA: `torch.backends.fp32_precision = "tf32"` (≥ 2.9 API; per backend e.g.
  `torch.backends.cuda.matmul.fp32_precision`); the old `allow_tf32` flags are being deprecated; don't mix them:
  even *reading* `torch.backends.cuda.matmul.allow_tf32` after setting the new API raises a RuntimeError (2.14).
- **torch.compile** (`model.compile(mode=…)`): `default`, `reduce-overhead` (CUDA graphs; static shapes),
  `max-autotune` (slow compile, GEMM autotuning). Diagnose with `TORCH_LOGS=graph_breaks,recompiles,guards`; after
  `recompile_limit` (default 8) a frame falls back to eager. Avoid recompiles: `drop_last=True`, bucketed shapes,
  `torch._dynamo.mark_dynamic` for truly varying dims, tensors instead of changing Python scalars. Time after warm-up.
- Also: channels-last for convnets, fused optimizers (`AdamW(..., fused=True)`), `pin_memory=True` +
  `non_blocking=True`, no `.item()`/`print(tensor)` in the hot loop (each syncs the GPU; log every N steps).
- **Gradient accumulation**: divide the loss by the number of micro-batches (or normalize by total tokens for LMs:
  sum losses and divide by tokens in the whole accumulated batch), step and zero once per accumulation cycle, clip
  after accumulation. Skip gradient sync on non-final micro-batches: DDP `with model.no_sync():`, FSDP2
  `model.set_requires_gradient_sync(False)`. BatchNorm still sees only the micro-batch. LR/batch scaling: ml-tuning.
- **Activation checkpointing** (recompute a block's forward in backward; less memory, more compute):
  `torch.utils.checkpoint.checkpoint(block, x, use_reentrant=False)` per transformer/residual block.
- **OOM**: find what holds memory before shrinking the batch: `torch.cuda.memory._record_memory_history(max_entries=100_000)`
  → run a few steps → `torch.cuda.memory._dump_snapshot("snap.pickle")`, open at https://pytorch.org/memory_viz;
  `PYTORCH_ALLOC_CONF=expandable_segments:True` (alias `PYTORCH_CUDA_ALLOC_CONF`) for fragmentation with varying
  shapes. Then: bf16, activation checkpointing, smaller micro-batch + accumulation, FSDP2.

## Estimate before you scale

Back-of-envelope numbers before renting GPUs or picking a parallelism scheme. Source: Austin et al., *How to Scale
Your Model* (library: `scaling-book-*`; Ch. 1 rooflines, Ch. 4 Transformer math, Ch. 5 training, Ch. 12 GPUs). It
is written for TPUs/JAX; the reasoning carries over, but take GPU numbers from Ch. 12 or your own measurements.

- **Time bounds**: `T_math = FLOPs / FLOP/s`, `T_comms = bytes / bandwidth` (HBM or interconnect); the step takes
  between `max(T_math, T_comms)` (perfect overlap) and their sum. Compute-bound when the operation's arithmetic
  intensity (FLOPs per byte moved) exceeds the hardware's (peak FLOP/s ÷ bandwidth) (Ch. 1).
- **Training compute**: ≈ `6 · params · tokens` FLOPs for Transformers at ordinary context lengths (Ch. 4 takeaways).
  Wall time ≈ that ÷ (GPUs × peak bf16 FLOP/s × MFU); H100/B200 usually reach only ~80–85% of peak even in matmuls
  (Ch. 1), and whole-model MFU is lower; measure yours (tokens/s × 6 · params ÷ peak) and use it for the estimate.
- **Memory**: parameters + optimizer state are ≈ 10 bytes per parameter with Adam (Ch. 5 takeaways), plus
  activations (activation checkpointing trades them for recompute). That is why plain DDP stops at a few billion
  parameters per GPU and FSDP2 shards them. KV cache for inference ≈ `2 · S · L · K · H` elements per sequence
  (S tokens, L layers, K KV heads, H head dim; Ch. 4).
- **Matmuls** are compute-bound only when the per-GPU **token** batch is large: intensity ≈ B tokens, critical value
  ~240 on TPU v5e and ~300 on GPUs (Ch. 1). Small per-GPU batches waste the tensor cores regardless of code quality.
- **Which parallelism** (Ch. 5, Ch. 12 "TLDR of LLM scaling on GPUs"):
  - DDP/FSDP become communication-bound when tokens per GPU < `C / W` (FLOP/s ÷ collective bandwidth): ≈ 2,200–2,500
    tokens per GPU on H100/B200 with NVLink/InfiniBand; for MoE multiply by E/k; with only 2-way data parallelism the
    requirement roughly halves. Small dense models: FSDP if the batch allows.
  - Tensor parallelism stays compute-bound to about 8-way and only inside one NVLink domain; larger dense models: TP
    within 1–2 nodes + pipeline across nodes + data parallel. Never use TP over PCIe-only GPUs.
- **Plug in your own interconnect.** Gradient all-reduce time ≈ `grad_bytes · 2(n−1)/n ÷ busbw` (NCCL's bus
  bandwidth); compare it with the backward-pass compute time. Measure busbw with a 256 MiB `all_reduce` loop (or
  nccl-tests). Example: 2× RTX 4090 over PCIe without NVLink measured 8.3 GB/s (Nov 2026), so a 1B-parameter bf16
  model's 2 GB gradient all-reduce takes ≈ 0.24 s per step; small steps there are communication-bound, so use bigger
  per-GPU batches or gradient accumulation (`no_sync`) before adding GPUs.
- Check the estimate against a profile (step time, MFU, NCCL time in `torch.profiler`); a large gap means overheads,
  poor overlap or a data-loading bottleneck (ml-data), not a wrong formula.

## Distributed (multi-GPU / multi-node)

- Launch with `torchrun --nproc-per-node=N train.py` (multi-node: `--nnodes`, `--rdzv-backend=c10d
  --rdzv-endpoint=host:port`); in the script `torch.cuda.set_device(local_rank)` and
  `dist.init_process_group("cpu:gloo,cuda:nccl", device_id=torch.device("cuda", local_rank))` (RCCL on AMD uses the
  same "nccl"; plain `"nccl"` works too, but `dcp.async_save` then fails with "A CPU backend must be enabled").
- **DDP** first when the model + optimizer fit on one GPU. **FSDP2** (`torch.distributed.fsdp.fully_shard`) when they
  don't: apply `fully_shard(block, mp_policy=MixedPrecisionPolicy(param_dtype=torch.bfloat16, reduce_dtype=torch.float32))`
  to each transformer block, then to the root model; create the optimizer after sharding. FSDP1
  (`FullyShardedDataParallel`) is legacy.
- **Checkpoints with DCP** for sharded models: `from torch.distributed.checkpoint.state_dict import get_state_dict,
  set_state_dict`; `model_sd, optim_sd = get_state_dict(model, opt)`; `dcp.save({"model": model_sd, "optim": optim_sd},
  checkpoint_id=dir)` (`dcp.async_save` overlaps with training); `dcp.load` then `set_state_dict`. Reshards on load.
- Every rank must see different data and the same number of steps (ml-data §2), or collectives hang.
- **Hangs/timeouts**: `NCCL_DEBUG=INFO`, `TORCH_DISTRIBUTED_DEBUG=DETAIL` (collective mismatch checks),
  flight recorder: `TORCH_FR_BUFFER_SIZE=2000` (older name `TORCH_NCCL_TRACE_BUFFER_SIZE`, now deprecated) +
  `TORCH_NCCL_DUMP_ON_TIMEOUT=1` + `TORCH_FR_DUMP_TEMP_FILE=/path/fr/rank_` (one file per rank), then
  `python -m torch.distributed.flight_recorder.fr_trace /path/fr -p rank_`, which names the collective and the missing
  ranks. Lower `init_process_group(timeout=timedelta(...))` to make a hang fail fast while debugging. Wrong NIC →
  `NCCL_SOCKET_IFNAME`. Usual causes: a rank skipping a collective (conditional code, uneven data), DDP unused params.
  Verified Nov 2026 on 2× RTX 4090 (PyTorch 2.14.1, NCCL 2.32): DDP, FSDP2 (+compile), DCP save/async/load/reshard.

## Plan for deployment while training

If the model will run on an edge device (see ml-deploy): pick ops that TensorRT supports and fuses, keep shapes static
or bounded, avoid data-dependent control flow, use sizes that are multiples of 8/16, export to ONNX early and often
(a CI check), and consider QAT/sparsity-aware fine-tuning if INT8/FP8 PTQ loses accuracy (ml-qat). Evaluate the
exported/quantized model's accuracy, not only the PyTorch model's.

Related: **ml-data**, **ml-tuning** (LR, batch, optimizers, regularization, EMA/SWA), **ml-qat**, **ml-metrics**,
**experiment-design**, **gpu-kernels**, **ml-deploy**.
