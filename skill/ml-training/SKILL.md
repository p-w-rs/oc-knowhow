---
name: ml-training
description: Train and evaluate models reproducibly on NVIDIA and AMD GPUs — Pixi environments for CUDA and ROCm PyTorch, MLflow 3 experiment tracking (runs, params, metrics, system metrics, LoggedModels, comparing runs), long runs on remote GPU machines, checkpoints and exact resume, determinism, mixed precision and TF32, torch.compile (modes, graph breaks, recompiles), gradient accumulation, activation checkpointing, OOM debugging, profiling, DDP/FSDP2 with DCP checkpoints and NCCL debugging, and planning for deployment from the start. Load before setting up training, running experiments or comparing results.
---

# Training and experiments

## Environment

- One Pixi workspace per project, committed with `pixi.lock`. NVIDIA and AMD in **separate environments**:
  - `cuda`: conda-forge `pytorch-gpu` + `cuda-version = "13.*"` on a platform that declares CUDA
    (`platforms = [{ platform = "linux-64", cuda = "13.0" }]`; `[system-requirements]` is the deprecated form).
    conda-forge can lag PyPI by a minor (Nov 2026: 2.14.1 vs 2.15.0); else use the `whl/cu13x` index as below.
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
      info = mlflow.pytorch.log_model(model, name="model", step=step)   # MLflow 3: LoggedModel, load via info.model_uri
  ```
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
  `torch.backends.cuda.matmul.fp32_precision`); the old `allow_tf32` flags are being deprecated; don't mix them.
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

## Distributed (multi-GPU / multi-node)

- Launch with `torchrun --nproc-per-node=N train.py` (multi-node: `--nnodes`, `--rdzv-backend=c10d
  --rdzv-endpoint=host:port`); in the script `torch.cuda.set_device(local_rank)` and
  `dist.init_process_group("nccl", device_id=torch.device("cuda", local_rank))` (RCCL on AMD uses the same "nccl").
- **DDP** first when the model + optimizer fit on one GPU. **FSDP2** (`torch.distributed.fsdp.fully_shard`) when they
  don't: apply `fully_shard(block, mp_policy=MixedPrecisionPolicy(param_dtype=torch.bfloat16, reduce_dtype=torch.float32))`
  to each transformer block, then to the root model; create the optimizer after sharding. FSDP1
  (`FullyShardedDataParallel`) is legacy.
- **Checkpoints with DCP** for sharded models: `from torch.distributed.checkpoint.state_dict import get_state_dict,
  set_state_dict`; `model_sd, optim_sd = get_state_dict(model, opt)`; `dcp.save({"model": model_sd, "optim": optim_sd},
  checkpoint_id=dir)` (`dcp.async_save` overlaps with training); `dcp.load` then `set_state_dict`. Reshards on load.
- Every rank must see different data and the same number of steps (ml-data §2), or collectives hang.
- **Hangs/timeouts**: `NCCL_DEBUG=INFO`, `TORCH_DISTRIBUTED_DEBUG=DETAIL` (collective mismatch checks),
  `TORCH_NCCL_DUMP_ON_TIMEOUT=1` + `TORCH_NCCL_TRACE_BUFFER_SIZE=2000` (flight recorder dump), wrong NIC →
  `NCCL_SOCKET_IFNAME`. Usual causes: a rank skipping a collective (conditional code, uneven data), DDP unused params.

## Plan for deployment while training

If the model will run on an edge device (see ml-deploy): pick ops that TensorRT supports and fuses, keep shapes static
or bounded, avoid data-dependent control flow, use sizes that are multiples of 8/16, export to ONNX early and often
(a CI check), and consider QAT/sparsity-aware fine-tuning if INT8/FP8 PTQ loses accuracy (ml-qat). Evaluate the
exported/quantized model's accuracy, not only the PyTorch model's.

Related: **ml-data**, **ml-tuning** (LR, batch, optimizers, regularization, EMA/SWA), **ml-qat**, **ml-metrics**,
**experiment-design**, **gpu-kernels**, **ml-deploy**.
