---
name: ml-deploy
description: Deploy and optimize neural networks on NVIDIA edge and CUDA devices (Jetson Orin/Thor, discrete GPUs) with TensorRT 11 — export (torch.export/ONNX), strongly typed precision and ModelOpt quantization (INT8/FP8/FP4/INT4), custom TensorRT plugins for novel layers (IPluginV3, Python tensorrt.plugin, Torch-TensorRT converters), running independent branches in parallel, CUDA graphs, DLA, benchmarking and profiling, and a full training-to-device optimization checklist. Load before any export, TensorRT, Jetson or inference-optimization work.
---

# Edge deployment with TensorRT 11

## 0. Ground truth before code (always)

Your training data predates TensorRT 11 and recent JetPacks. **Do not write TensorRT code from memory.**

1. **Check what is installed where it will run** (the device, not your laptop):
   ```sh
   cat /etc/nv_tegra_release; dpkg -l | grep -E "nvidia-jetpack|tensorrt|libnvinfer|cuda-toolkit|cudnn" | awk '{print $2,$3}'   # Jetson
   python -c "import tensorrt as trt; print(trt.__version__)"; trtexec --help | head -3; nvcc --version; nvidia-smi
   ```
   (Run Python through the project's Pixi environment; on Jetson the TensorRT Python bindings come from the
   JetPack/SBSA packages, so check which interpreter actually sees them.)
2. **Read the docs for that exact version** before using an API, flag or sample:
   - Release notes and the **TRT 10 → 11 migration guide** (has separate trtexec, Python, C++ and Jetson pages):
     https://docs.nvidia.com/deeplearning/tensorrt/latest/getting-started/release-notes.html,
     https://docs.nvidia.com/deeplearning/tensorrt/latest/api/migration-guide.html
   - Python/C++ API: …/latest/api/python-api.html, …/latest/api/c-api.html; operators: …/latest/api/operators.html;
     ONNX opsets: …/latest/reference/onnx-opset-guide.html
   - Support matrix (platforms, CUDA, compute capability, precisions): …/latest/getting-started/support-matrix.html
   - Benchmarking and best practices: …/latest/performance/benchmarking.html, …/latest/performance/best-practices.html
   - Samples (the best reference code): https://github.com/NVIDIA/TensorRT/tree/main/samples (check out the tag
     matching the installed version, e.g. `v11.4`)
   - ModelOpt: https://nvidia.github.io/Model-Optimizer/ · Torch-TensorRT: https://docs.pytorch.org/TensorRT/
   - Jetson: https://developer.nvidia.com/embedded/jetpack/downloads, Jetson Linux developer guide for the L4T release
   Use `webfetch` on these; quote the version you relied on in comments or the PR.
3. When docs and memory disagree, docs win. When the installed version differs from the docs' `latest`, use the
   versioned docs (`/archive/<version>/`). When docs disagree with the tool's `--help` or source, the tool wins.

### Version facts as of November 2026 (verify; they move)

| Item | State |
|---|---|
| TensorRT | 11.x; latest 11.4.1 (docs of 28 Oct 2026); pip `tensorrt` 11.4.0 (CUDA 13). Min compute capability 7.5. 11.x drops CUDA 11. |
| JetPack 7.2.1 (on the downloads page on 11 Nov 2026) | Jetson Linux (L4T) 39.2.1, CUDA 13.2.2, **TensorRT 10.16.2**, Ubuntu 24.04; Thor and the Orin family |
| TensorRT 11 on Jetson | **11.4.1+ on JetPack 7.2.2+**, Jetson **AGX Orin and Thor** only, from the Linux **SBSA** package (TRT 11.0–11.4.0 did not support JetPack). JetPack 6.x stays on TRT 10.x. Orin NX/Nano are not listed for TRT 11: stay on the JetPack TRT unless the support matrix says otherwise. |
| DLA | Orin only (Thor has none). TRT 11: 11.4.1 + JetPack 7.2.2+, AGX Orin, strongly typed. **JetPack 7.2/7.2.1 with their TRT 10.16.2: DLA unavailable.** JetPack 6.x: works with its TRT 10.x (docs: 10.7 was the last 10.x with DLA). |
| Compute capability | Orin 8.7 (INT8, FP16; no FP8/FP4), Thor 11.0 (FP8, NVFP4, BF16, INT8) |
| Torch-TensorRT | 2.14.0 (PyTorch 2.14, built for TRT 11.1; wheels also for aarch64 SBSA/Jetson). PyTorch 2.15 is out; Torch-TRT for it not yet. |
| ModelOpt | 0.48.0 (`nvidia-modelopt`) |
| PyTorch → ONNX | `torch.onnx.export(..., dynamo=True)` is the default since 2.9; `dynamic_axes` is deprecated, use `dynamic_shapes` |

So: on a device with JetPack 7.2.1 you write **TensorRT 10.16** code (still allows weak typing and builder
precision flags, no DLA), and on TRT 11 you must use the strongly typed workflow below. Prefer writing 10.x code in
the strongly typed style anyway (explicit Q/DQ, `--stronglyTyped`, `IPluginV3`) so the upgrade is a rebuild. Say
which version your code targets.

## 1. TensorRT 11 essentials (what changed from 10)

- **Networks are always strongly typed.** Precision comes from tensor types in the model (casts, Q/DQ nodes), not
  from builder flags. Removed: `BuilderFlag.FP16/BF16/INT8/FP8/INT4/FP4`, `OBEY/PREFER_PRECISION_CONSTRAINTS`,
  `ILayer.precision`/`set_output_type`, `ITensor.set_type`/`dynamic_range`, `INormalizationLayer.compute_precision`,
  the `IInt8Calibrator` family and all calibration/quantization-flag APIs (implicit quantization is gone).
  `BuilderFlag.TF32` (and trtexec `--noTF32`) still exist: they control TF32 math for FP32 tensors.
- **trtexec**: removed (exit with an error): `--fp16 --bf16 --int8 --fp8 --int4 --best --calib --calibProfile
  --precisionConstraints --layerPrecisions --layerOutputTypes --restricted`. Deprecated no-ops (now default):
  `--stronglyTyped` (passing it twice errors in 11.0), `--useCudaGraph` (disable with `--noCudaGraph`),
  `--noDataTransfers` (include with `--includeDataTransfers`), `--useSpinWait` (`--noSpinWait`),
  `--separateProfileRun`. The type part of `--inputIOFormats/--outputIOFormats` is ignored (format only).
- **Renames** (Python): `device_memory_size` → `device_memory_size_v2`, `weight_streaming_budget` →
  `weight_streaming_budget_v2`, `create_execution_context_without_device_memory()` → `create_execution_context()`,
  `IExecutionContext.device_memory` → `device_memory_v2`, `get_profile_tensor_values` → `…_v2`,
  `plugin_creator_list` → `all_creators`, `get_plugin_creator` → `get_creator`, `add_normalization` →
  `add_normalization_v2`. Tactic sources cuBLAS/cuBLASLt/cuDNN removed; plugins that need cuDNN are unsupported;
  legacy built-in plugins removed (`BatchedNMS*`, `NMS*`, `EfficientNMS_ONNX_TRT`, `Proposal`, `Clip`, `LReLU`,
  `Normalize`, `Split`, `CropAndResize`, …; use `add_nms`, activations, `add_normalization_v2`, `add_slice`).
  Static libraries are gone (link the shared ones); tar/zip file names changed.
- `IPluginV2*`/`IPluginCreator`/`add_plugin_v2` are **deprecated, not removed**: V2 plugins still build and run
  with warnings. Write new plugins as `IPluginV3`.
- IEngineInspector JSON: `Bindings` → `I/O Tensors`; `Format/Datatype` split into `Format` and `Datatype`. Update
  scripts that parse `--exportLayerInfo` output.
- Third-party runtimes: ONNX Runtime's TensorRT EP needs ORT ≥ 1.27 for TRT 11.

### Precision workflow on TRT 11

```sh
# FP16 (or -t bf16) with sensitive nodes kept in FP32: ModelOpt AutoCast rewrites the ONNX types
python -m modelopt.onnx.autocast --onnx_path model.onnx --output_path model_fp16.onnx \
    --calibration_data calib.npz --keep_io_types
# INT8 / FP8 / INT4 PTQ: explicit Q/DQ from real calibration data
python -m modelopt.onnx.quantization --onnx_path model.onnx --quantize_mode int8 \
    --calibration_data_path calib.npz --calibration_method entropy --output_path model_int8.onnx
trtexec --onnx=model_int8.onnx --saveEngine=model.engine --timingCacheFile=timing.cache
```
- ONNX quantization CLI: `--quantize_mode fp8|int8|int4` (default int8); `--calibration_method` entropy (default)
  or max for int8/fp8, awq_clip (default) or rtn_dq for int4; `--high_precision_dtype` (default fp16: the
  non-quantized part becomes FP16); `--op_types_to_exclude`/`--nodes_to_exclude` for sensitive layers;
  `--calibration_shapes` for dynamic non-batch dims; `--autotune` for Q/DQ placement measured on TRT;
  `--target_dla` for INT8 on DLA (TRT 11.4+); `--simplify`. Python: `modelopt.onnx.quantization.quantize(...)`.
  (The TRT trtexec migration page writes `--calibration_data`; the real flag is `--calibration_data_path`.)
- AutoCast: `--low_precision_type/-t fp16|bf16`, `--op_types_to_exclude`, `--nodes_to_exclude` (regex),
  `--data_max` (default 512: nodes with larger outputs stay FP32), `--keep_io_types`; Python
  `modelopt.onnx.autocast.convert_to_mixed_precision(...)`. BF16 needs opset ≥ 22.
- **NVFP4/MXFP8 and LLM formats** come from PyTorch-side ModelOpt before export: `import modelopt.torch.quantization
  as mtq; model = mtq.quantize(model, mtq.NVFP4_DEFAULT_CFG, forward_loop)` (also `INT8_DEFAULT_CFG`,
  `FP8_DEFAULT_CFG`, `INT4_AWQ_CFG`, `INT8_SMOOTHQUANT_CFG`, `W4A8_AWQ_BETA_CFG`, `MXFP8_DEFAULT_CFG`;
  `mtq.auto_quantize` searches per-layer formats under a constraint), then export to ONNX. QAT: fine-tune the
  `mtq.quantize`d model (ml-qat skill).
- **Calibration data decides INT8 accuracy.** Without it ModelOpt calibrates on random data (useless). Use a few
  hundred real samples covering the deployment distribution (lighting, sensors, classes), preprocessed exactly like
  inference (resize, normalization, layout, dtype), saved as `np.savez("calib.npz", **{"<onnx input name>":
  stacked_array})` per input (don't save a dict object: that needs `--trust_calibration_data`/pickle).
- Choose by hardware: Orin → FP16 + INT8 (no FP8/FP4); Thor/Blackwell → FP8, NVFP4 also viable; INT4 AWQ for LLM
  weights. FP8 convs with kernels > 32 (e.g. 7×7) fall back to FP16/FP32 on SM 89/90/120/121: don't put FP8 Q/DQ
  before them. **Always measure accuracy** against the FP32 model on a real validation set (section 2,
  "Validate"), per output, before calling it done.
- Check the result: `--profilingVerbosity=detailed --exportLayerInfo=layers.json` and look at each layer's
  `Datatype`; unintended FP32 islands and `Reformat` layers between precisions cost time.

## 2. Export

- PyTorch: `torch.onnx.export(model, args, "m.onnx", dynamo=True, dynamic_shapes=..., opset_version=...,
  report=True)` (torch.export-based; `optimize=True` default; `verify=True` checks with ONNX Runtime). ModelOpt
  raises the opset as needed (≥ 19 for FP16 scales, 21 for INT4, 23 for NVFP4). Fix graph breaks and
  data-dependent control flow in the model rather than fighting the exporter. Large models: `external_data=True`
  (default) writes weights next to the `.onnx`; keep the files together.
- Clean up: `polygraphy surgeon sanitize m.onnx --fold-constants -o m_folded.onnx`; inspect with `polygraphy
  inspect model m.onnx`; lint with `polygraphy check lint m.onnx`.
- **Validate** (each step, real inputs): `polygraphy run m.onnx --trt --onnxrt --atol 1e-3 --rtol 1e-3
  --data-loader-script data.py` (or `--load-inputs inputs.json`; random inputs hide real errors). Find the first
  diverging layer with `--trt-outputs '*' --onnx-outputs '*'` (all tensors; one precision at a time); shrink a
  failing model with `polygraphy debug reduce`. Then task metrics (mAP, accuracy, …) on the validation set from
  the engine, with the deployment preprocessing.
- Alternative without ONNX: Torch-TensorRT 2.14 (`torch_tensorrt.dynamo.compile(exported_program, arg_inputs=...,
  enable_autocast=True, autocast_low_precision_type=torch.float16, optimization_level=..., timing_cache_path=...)`,
  `torch_tensorrt.save(trt_gm, "m.ep", output_format="exported_program"|"aot_inductor"|"executorch", ...)`). The
  dynamo compiler has no `enabled_precisions` any more (strong typing): use autocast, a half-precision model, or
  ModelOpt Q/DQ. Check its TRT version matches the device's.
- Dynamic shapes: give realistic `min/opt/max` (`--minShapes/--optShapes/--maxShapes`; static `--shapes`); `opt` =
  the size you benchmark and deploy. Several profiles if you serve very different sizes. Static shapes are faster
  and simpler when the deployment allows them.

## 3. Custom layers: TensorRT plugins (novel architectures)

When the ONNX parser or Torch-TensorRT rejects an op (check the parser's operator list for the installed version),
or a fused custom kernel beats TRT's tactics, write a **plugin**. Prefer, in order:

1. **Rewrite the op** in supported primitives (often enough and keeps TRT's fusions). Profile before and after.
2. **Python quickly deployable plugin** (`tensorrt.plugin`), with an **AOT** implementation (Triton or CUDA
   compiled to PTX/cubin) so the engine runs **without Python** on the device:
   ```python
   import tensorrt.plugin as trtp
   @trtp.register("myns::fused_op")                 # shapes/types: TensorDesc in → TensorDesc(s) out
   def fused_op_desc(x: trtp.TensorDesc, alpha: float) -> trtp.TensorDesc: return x.like()
   @trtp.aot_impl("myns::fused_op")                 # → (kernel name, PTX/cubin, trtp.KernelLaunchParams, trtp.SymExprs)
   def fused_op_aot(x: trtp.TensorDesc, alpha: float, outputs, tactic: int): ...
   @trtp.autotune("myns::fused_op")                 # dtype/format combinations TRT may choose from
   def fused_op_autotune(x, alpha, outputs): return [trtp.AutoTuneCombination("FP32|FP16, FP32|FP16", "LINEAR")]
   ```
   `@trtp.impl` gives a Python (JIT) implementation instead (needs Python at runtime). Launch grid via
   `trtp.KernelLaunchParams()` (`grid_x = trtp.cdiv(n, block)`), extra scalar args via `trtp.SymIntExprs` /
   `trtp.SymInt32`; data-dependent outputs via `trtp.size_tensor` and `trtp.from_shape_expr`. ONNX: a node with
   `op_type` = the plugin name, string attribute `plugin_namespace` = the namespace, and bool attribute `aot=True`
   to use the AOT implementation. Samples: `samples/python/quickly_deployable_plugins` (`qdp_defs.py`),
   `non_zero_plugin`, `aliased_io_plugin`, `cute_dsl_plugin`.
3. **C++ `IPluginV3`**: a class implementing `IPluginV3` (`getCapabilityInterface`, `clone`) +
   `IPluginV3OneCore` (name/version/namespace) + `IPluginV3OneBuild` (`getNbOutputs`, `getOutputDataTypes`,
   `getOutputShapes` with `IExprBuilder`, `supportsFormatCombination`, `configurePlugin`, `getWorkspaceSize`,
   optional `getValidTactics`) + `IPluginV3OneRuntime` (`onShapeChange`, `enqueue(..., cudaStream_t)` returning 0,
   `getFieldsToSerialize`, `attachToContext`), and an `IPluginCreatorV3One` registered with
   `REGISTER_TENSORRT_PLUGIN` or `registerCreator`, in a library loaded with `--dynamicPlugins` /
   `trt.get_plugin_registry().load_library`. Data-dependent output sizes: `IExprBuilder::declareSizeTensor`; size
   tensors must be **INT64** (INT32 fails to compile). Known 11.x pitfall: a `PluginField` with null data and
   length 0 can crash the creator; give every field a non-null buffer. Samples: `samples/sampleNonZeroPlugin`,
   `samples/python/sample_plugin_v2_to_v3_migration`, the plugins in `plugin/` of the TensorRT repo; guide
   "Migrating V2 Plugins to IPluginV3" in the TRT docs.
4. **Torch-TensorRT**: register the op with `torch.library.custom_op` + `register_fake`, then
   `torch_tensorrt.dynamo.conversion.plugins.custom_op("ns::op", supports_dynamic_shapes=True)` generates the plugin
   and converter (uses an `@trtp.aot_impl` if registered, `use_aot_if_available=True`); or
   `generate_plugin` + `generate_plugin_converter` separately; or write a converter with
   `@dynamo_tensorrt_converter(torch.ops.aten.X.default)`. Examples: `examples/dynamo/aot_plugin.py`,
   `nvrtc_aot_plugin.py`, `auto_generate_plugins.py` in pytorch/TensorRT.

Plugin rules: support FP16/FP32 (and INT8/FP8 if around quantized layers) and the formats TRT prefers; handle
dynamic shapes; never allocate in `enqueue` (use the workspace); never synchronize; launch on the given stream;
validate against the PyTorch reference op with random inputs at several shapes and dtypes; benchmark the plugin in
isolation (`nsys`) and in the engine (`--dumpProfile`). Plugins are native code: load only libraries you built.

## 4. Parallelism inside and across models

Agents usually miss these; check every model for them:
- **Independent branches in one graph** (multi-head, multi-scale, two-tower, sensor fusion): build with auxiliary
  streams (`config.max_aux_streams = N` / `--maxAuxStreams=N`) so TRT runs branches concurrently (the limit is per
  inference stream; 0 = least memory). Compare `device_memory_size_v2` and latency with and without, and confirm in
  Nsight Systems that kernels overlap.
- **Independent models or stages** (detector + tracker, encoder + decoder of different inputs): one execution
  context per engine/profile, each on its own CUDA stream, synchronized with CUDA events, not `cudaDeviceSynchronize`.
  `trtexec --infStreams=N` to measure.
- **Pipelining**: overlap host↔device copies (pinned memory, `cudaMemcpyAsync` on a copy stream) with compute of the
  previous frame; double-buffer inputs/outputs. Pre/post-processing on the GPU (CUDA kernels, CV-CUDA, NPP, VPI on
  Jetson) instead of NumPy on the CPU.
- **Batching**: batch frames/cameras when latency budget allows; profile throughput vs latency at several batch sizes.
- **CUDA graphs** for the steady-state loop (default in trtexec; in your code capture `enqueueV3` after the shapes are
  fixed). Never capture engines with data-dependent shapes (fails with CUDA error 900 and can corrupt the stream);
  not with loops or conditionals either.
- **DLA (Orin, where available, see the version table)**: offload a second, DLA-friendly model (or the backbone) to
  DLA cores (`--useDLACore=0 --allowGPUFallback`) to run concurrently with the GPU; INT8 via ModelOpt
  `--target_dla`; check which layers fell back (`--dumpLayerInfo`). Measured on TRT 11.4.1: mixed INT8/FP16 DLA
  networks can be slower than with TRT 10.3, so compare.
- **Multiple devices**: TRT 11 multi-device inference and collectives exist for large models; not typical on Jetson.

## 5. The optimization checklist (training → device)

Go through all of it; report what you checked, what you changed and the measured effect.

1. **Requirement**: target device + JetPack/TRT version, latency (p50/p99) or throughput target, batch size, input
   resolution, power mode, memory budget, accuracy budget. Ask if unknown.
2. **Architecture** (cheapest wins first): input resolution and crop, channel widths, depth; replace ops that are
   slow or unsupported on TRT (e.g. some attention variants, dynamic indexing, exotic activations) with fused-friendly
   ones; static shapes where possible; avoid data-dependent shapes and Python control flow in the forward pass;
   prefer channels and sizes that are multiples of 8/16/32 (tensor cores); fold BatchNorm into conv/linear at export.
3. **Training-aware** (ml-qat skill): QAT (`mtq.quantize` + fine-tune) if PTQ loses accuracy; 2:4 structured
   sparsity (prune with ModelOpt or `polygraphy surgeon prune`, fine-tune, build with `--sparsity=enable`;
   `--sparsity=force` is deprecated); distillation into a smaller student; pruning (ModelOpt).
4. **Export**: clean graph (constant folding, no redundant casts/reshapes, no unused outputs), verify numerics
   (Polygraphy, section 2).
5. **Precision**: FP16/BF16 everywhere it is accurate; INT8/FP8/NVFP4 where hardware supports it; mixed precision for
   sensitive layers; measure accuracy.
6. **Engine build**: `--builderOptimizationLevel` (default 3; 4–5 for production builds, longer build), a
   persistent timing cache (`--timingCacheFile`; valid only for the same GPU, CUDA, TRT and clocks; never share
   across devices), realistic `opt` shapes, `--memPoolSize=workspace:<size>` on small devices (default unit MiB),
   weight stripping/refit (`--stripWeights`, `--refit`) if weights must be updated in the field, weight streaming
   (`--allowWeightStreaming --weightStreamingBudget`) only when weights exceed memory.
7. **Portability**: engines are tied to GPU model and TRT version: build on the target device (or identical
   module + JetPack). `--versionCompatible` lets an engine run on later TRT runtimes of the same major (TRT 10 VC
   engines also load in 11.x), at some speed cost; hardware compatibility (`--hardwareCompatibilityLevel`) is not
   supported on JetPack. Cross-compiling: host and target TRT versions must match. Ship the engine with its TRT,
   JetPack and model versions in the file name or metadata.
8. **Security**: a serialized engine is executable code. Load only engines you built, transported with integrity
   checks (signatures/hashes); `getEngineValidity` is not tamper detection.
9. **Inspect**: `trtexec --profilingVerbosity=detailed --dumpLayerInfo --exportLayerInfo=layers.json --dumpProfile
   --exportProfile=prof.json` — look for unfused layers, `Reformat`/`Shuffle` layers, FP32 fallbacks, slow plugins;
   fix in the model and repeat. `polygraphy inspect model model.engine` for I/O and layer info.
10. **Runtime**: parallelism (section 4), CUDA graphs, pinned memory, zero-copy/unified memory on Jetson (integrated
    GPU shares DRAM with the CPU: count both in the memory budget), GPU pre/post-processing, no per-frame
    allocations, no host syncs in the loop. Size `device_memory_size_v2` per context; share it between contexts
    that never run concurrently (`create_execution_context(ExecutionContextAllocationStrategy.USER_MANAGED)`).
11. **System (Jetson)**: power mode `sudo nvpmodel -q` / `sudo nvpmodel -m <id>` (modes differ per module; MAXN is
    unconstrained), `sudo jetson_clocks` pins clocks at the current mode's maximum (`--show`, `--store` first,
    `--restore` after; `--fan` for max fan); after it the power mode cannot change until reboot, so set
    `nvpmodel` first — use it for reproducible benchmarks, then also measure at the deployment mode; watch
    thermals (throttling skews long runs); `tegrastats --interval 500` for GPU/EMC/DLA load, RAM and power rails.
    EMC (memory bandwidth) is often the real bottleneck.
12. **Measure honestly**: warm-up, many iterations, report p50/p90/p99 and throughput, power (tegrastats) and accuracy;
    same power mode and clocks for before/after; end-to-end (camera → result) as well as engine-only.

## 6. Benchmarking and profiling

```sh
trtexec --loadEngine=model.engine --warmUp=2000 --iterations=1000 --duration=0 --percentile=50,90,99  # warm-up ms; engine-only
trtexec --loadEngine=model.engine --infStreams=2 --duration=30                                        # concurrency
trtexec --loadEngine=model.engine --includeDataTransfers --noCudaGraph                                # closer to a naive app
nsys profile -t cuda,nvtx,osrt -o run python app.py && nsys stats -r cuda_gpu_kern_sum --format csv run.nsys-rep
ncu --set full -k regex:<kernel> -c 1 -o k python app.py && ncu -i k.ncu-rep --csv --page details
```
trtexec defaults: ≥ 200 ms warm-up and ≥ 10 iterations or ≥ 3 s; CUDA graphs on; transfers excluded. Feed real
inputs with `--loadInputs` when values matter (data-dependent shapes, NMS, sparsity). On Jetson run `nsys` on the
device (or Nsight Systems' remote target); Nsight Compute for one kernel at a time. Add NVTX ranges around
pre-process / inference / post-process in the application so timelines are readable.

## 7. LLMs/VLMs on the edge

Use **TensorRT Edge-LLM** (C++ runtime for Jetson; https://github.com/NVIDIA/TensorRT-Edge-LLM) or TensorRT-LLM on
larger GPUs rather than hand-building transformer engines; quantize weights (INT4 AWQ / FP8 / NVFP4 per hardware) with
ModelOpt; check its supported-model and JetPack list for the version you install.

## 8. Experiment hygiene

Log every export/build/benchmark as an MLflow run (see the ml-training skill): model revision, ONNX hash, TRT,
CUDA and JetPack versions, ModelOpt version and quantization config, calibration set ID, precision, builder flags,
power mode, latency percentiles, accuracy, and the engine/layer-info files as artifacts. Keep conversion and
benchmark scripts in the repo (Pixi tasks), not as one-off shell history.
