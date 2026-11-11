---
name: gpu-kernels
description: Write, port and tune custom GPU kernels for NVIDIA and AMD — Triton (autotune, tensor descriptors/TMA, AMD wavefronts, debugging), CUDA C++ and HIP (hipify), CUTLASS/CuTe, PyTorch custom ops (torch.library.custom_op, triton_op/wrap_triton, opcheck) that work with torch.compile and export, correctness testing (torch.testing.assert_close) and benchmarking (triton.testing.do_bench), and profiling with Nsight Systems/Compute and rocprofv3. Load before writing or optimizing any kernel.
---

# Custom GPU kernels (NVIDIA and AMD)

## Ground truth first

- Check versions on the machine that will run the kernel: `nvidia-smi` / `nvcc --version` (CUDA), `rocminfo | grep
  gfx` / `hipcc --version` (ROCm), `pixi run python -c "import torch, triton; print(torch.__version__, torch.version.cuda,
  torch.version.hip, triton.__version__, torch.cuda.get_device_capability())"`. Shared-memory size, warp/wavefront
  width and tensor-core features depend on the architecture (sm_80/90/100/120, gfx942/950, RDNA gfx11/12).
- APIs move fast (Triton especially). Read the docs/tutorials for the installed version before writing code:
  https://triton-lang.org/main/ (tutorials and `python-api`; tutorials in the repo at the matching tag
  `python/tutorials/`), https://docs.nvidia.com/cuda/, https://rocm.docs.amd.com/ (HIP, HIPIFY, rocprofiler-sdk),
  https://docs.pytorch.org/docs/stable/library.html. As of November 2026: Triton 3.9 (NVIDIA cc 8.0+, AMD ROCm 6.2+),
  CUDA 13.5, ROCm 10.1, PyTorch 2.15, CUTLASS 4.8 (`nvidia-cutlass-dsl` for the Python DSL). Verify; don't trust these.
  conda-forge lags: `pytorch-gpu` 2.14.1 comes with `triton` 3.7.1 (Nov 2026); everything below was run with that on
  Blackwell sm_120 (RTX PRO 6000), including tensor descriptors.

## Which tool

1. **Don't write a kernel** if `torch.compile` (Inductor; `mode="max-autotune"`), a library (cuBLAS/hipBLASLt,
   cuDNN/MIOpen, FlashAttention, `scaled_dot_product_attention`, FlexAttention for custom attention masks/scores) or
   TensorRT fusion already does it. Profile first (ml-training); write kernels for the measured hot spots only.
2. **Triton** by default: one source for NVIDIA and AMD, autotuning, integrates with `torch.compile` and TensorRT
   (AOT plugins, ml-deploy). Good for fused element-wise/reduction/normalization/attention-like and custom GEMM epilogues.
3. **CUDA C++ / HIP** when you need warp-level control, inline PTX, specific tensor-core instructions, or a C++
   runtime without Python (TensorRT C++ plugins, embedded). Write HIP-portable CUDA where possible and port with
   `hipify-clang` (accurate; needs CUDA headers) or `hipify-perl` (quick regex).
4. **CUTLASS / CuTe (C++ or the CuTe Python DSL)** for high-performance GEMM/conv variants on NVIDIA (Hopper/Blackwell
   TMA, warp specialization). **Gluon** (`triton.experimental.gluon`) is Triton's lower-level, layout-explicit
   dialect for when plain Triton can't reach peak; experimental, the API changes between releases.

## Triton practices

```python
@triton.autotune(configs=[triton.Config({"BLOCK_M": 128, "BLOCK_N": 128, "BLOCK_K": 64}, num_warps=8, num_stages=3), ...],
                 key=["M", "N", "K"])
@triton.jit
def kernel(a_ptr, b_ptr, c_ptr, M, N, K, stride_am, ..., BLOCK_M: tl.constexpr, BLOCK_N: tl.constexpr, BLOCK_K: tl.constexpr): ...
```
- Autotune over block sizes, `num_warps` and `num_stages`; key on the shape dimensions that change (bucket them,
  e.g. next power of 2, or every new shape re-tunes). Prune with `prune_configs_by`; kernels that accumulate into an
  output need `reset_to_zero=[...]` (autotuning runs the kernel several times). `TRITON_PRINT_AUTOTUNING=1` prints the
  winner; `cache_results=True` (or `TRITON_CACHE_AUTOTUNING=1`) caches timings on disk.
- **AMD**: wavefront is 64 on CDNA (MI200/MI300/MI350, gfx9) and 32 on RDNA (gfx10+), so `num_warps` means different
  thread counts: tune separately. AMD-specific `triton.Config` kwargs: `waves_per_eu`, `matrix_instr_nonkdim`
  (`kpack` is deprecated from gfx950). Check the ROCm Triton optimization guide for the installed version.
- **Tensor descriptors** for block loads/stores: host `TensorDescriptor.from_tensor(t, block_shape)`
  (`triton.tools.tensor_descriptor`) or device `tl.make_tensor_descriptor(...)` (needs `triton.set_allocator(fn)` for
  its scratch memory, see tutorial 09). They map to TMA on Hopper/Blackwell. Constraints: rank 1–5, base and all
  strides except the last 16-byte aligned, last dim contiguous. Block pointers (`tl.make_block_ptr`) still work.
- Masks for boundaries, `tl.multiple_of`/`tl.max_contiguous` hints, accumulate in FP32, cast at the store. Fuse the
  epilogue (bias, activation, residual, quantization) instead of separate kernels. Use `tl.dot(..., input_precision=…)`
  deliberately for FP32 inputs (`ieee` vs `tf32`).
- Debug: `TRITON_INTERPRET=1` (CPU interpreter; `print`/`pdb` work; slow, use tiny shapes), `tl.device_print`,
  `tl.device_assert` (with `TRITON_DEBUG=1`), `TRITON_KERNEL_DUMP=1 TRITON_DUMP_DIR=…` to see IR/PTX/AMDGCN,
  `TRITON_ALWAYS_COMPILE=1` to bypass the cache. `compute-sanitizer` (NVIDIA) for out-of-bounds/race checks.

## PyTorch integration

- A plain `@triton.jit` kernel called from Python already works under `torch.compile`. Wrap it as an operator when it
  must behave like a PyTorch op (export/AOTInductor, tensor subclasses, autograd registration):
  ```python
  from torch.library import triton_op, wrap_triton
  @triton_op("mylib::add", mutates_args={})
  def add(x: torch.Tensor, y: torch.Tensor) -> torch.Tensor:
      out = torch.empty_like(x); n = out.numel()
      wrap_triton(add_kernel)[(triton.cdiv(n, 1024),)](x, y, out, n, BLOCK_SIZE=1024)
      return out
  ```
  `triton_op` lets compile/export see into the kernels; every Triton call inside, including in backward, goes
  through `wrap_triton`. Gradients: `add.register_autograd(backward, setup_context=...)`.
- Other kernels (CUDA/HIP extensions, opaque code): `@torch.library.custom_op("mylib::op", mutates_args=())` with type
  annotations, plus `.register_fake` (shape/dtype only, no data access; required for compile/export) and
  `.register_autograd`. Validate every op with `torch.library.opcheck(op, args)` on several inputs and devices.
  Build C++/CUDA extensions with `torch.utils.cpp_extension` (`load_inline` for prototypes) or CMake in Pixi.
- The same custom op can become a TensorRT plugin for deployment (see ml-deploy). Quantized kernels: ml-qat.

## Correctness and speed (every kernel)

```python
import torch, triton
for shape in [(1, 1), (127, 33), (4096, 4096), (3, 70001)]:                  # incl. non-multiples of the block
    for dtype in (torch.float32, torch.bfloat16, torch.float16):
        x = torch.randn(shape, device="cuda", dtype=dtype); y = torch.randn_like(x)
        ref = (x.double() + y.double()).to(dtype)                            # high-precision reference
        torch.testing.assert_close(add(x, y), ref)                           # default rtol/atol chosen per dtype
ms = triton.testing.do_bench(lambda: add(x, y), return_mode="median")       # ms (default "mean"); warm-up + reps
gbps = 3 * x.numel() * x.element_size() / (ms * 1e-3) / 1e9                 # bytes read + written / time
```
- Test against a reference (PyTorch eager in FP32/FP64) over random inputs, shapes (non-multiples of the block size,
  size 1, large), dtypes, non-contiguous/strided inputs (`x.t()`, slices), and the backward (`torch.autograd.gradcheck`
  in float64 for small inputs). Tighter tolerances need justification; looser ones need an explanation (e.g. bf16
  accumulation order). Test on NVIDIA and AMD when supporting both.
- Benchmark with `triton.testing.do_bench` (`quantiles=[0.5, 0.2, 0.8]` for spread; `do_bench_cudagraph` for tiny
  kernels where launch overhead dominates) or CUDA events with warm-up and `torch.cuda.synchronize()`. Report GB/s or
  TFLOP/s against the device's peak (roofline: is it memory- or compute-bound?), and compare to the baseline it
  replaces (eager and `torch.compile`), over the shapes that occur in the model. Log results to MLflow (ml-training).
- Roofline before tuning (Austin et al., *How to Scale Your Model* Ch. 1, library `scaling-book-roofline`; GPU
  specifics Ch. 12): arithmetic intensity = FLOPs ÷ bytes moved to/from HBM; the device's critical intensity = peak
  FLOP/s ÷ HBM bandwidth (hundreds of FLOPs/byte for bf16 tensor cores). Below it the kernel is memory-bound: judge it
  by GB/s vs peak bandwidth and win by moving fewer bytes (fusion, lower precision, reuse in shared memory). Above it,
  judge TFLOP/s vs peak. Elementwise/reductions (≈ 0.5 FLOP/byte for a bf16 dot product) are always memory-bound; a
  bf16 matmul's intensity ≈ the smaller dimension (tokens) when that is small, and with tiles bm×bn ≈ bm·bn/(bm+bn).
  Take peak numbers from the datasheet for the exact SKU and precision (dense, not "with sparsity").
- Profile: NVIDIA `nsys profile -t cuda,nvtx -o r …` → `nsys stats -r cuda_gpu_kern_sum --format csv r.nsys-rep`;
  per-kernel `ncu --set full -k regex:name -c 1 -o k …` → `ncu -i k.ncu-rep --csv --page details` (memory throughput,
  achieved occupancy, warp stall reasons, bank conflicts). AMD `rocprofv3 --kernel-trace --stats -d out -- python …`
  (default output is a rocpd SQLite database; `rocpd convert -i <file>_results.db --output-format csv`, or pass
  `--output-format csv` directly), deeper analysis with `rocprof-compute profile/analyze`. Read results as text; don't guess.
  `nsys`/`ncu` are not in conda-forge PyTorch envs; use the system CUDA install (`/usr/local/cuda/bin`). `ncu` fails
  with `ERR_NVGPUCTRPERM` unless the admin enabled counters for users (`NVreg_RestrictProfilingToAdminUsers=0`);
  `nsys` works without it. On a shared GPU, use medians/quantiles: means are skewed by other jobs.

## Environments (Pixi)

- NVIDIA: conda-forge `pytorch-gpu` with `cuda-version = "13.*"` and a CUDA-declaring platform
  (`platforms = [{ platform = "linux-64", cuda = "13.0" }]`), plus `triton`, `cuda-nvcc`, `cuda-cudart-dev` for
  extensions (and `cuda-version` matching what PyTorch was built with). AMD: PyTorch ROCm wheels from the PyPI index
  in a separate feature/environment (`torch = { version = "...", index = "https://download.pytorch.org/whl/rocm<ver>" }`,
  which bring a matching `triton`; conda-forge has no ROCm PyTorch). Keep CUDA and ROCm in separate Pixi environments
  (`pixi run -e cuda …`, `pixi run -e rocm …`). Details: ml-training "Environment".
- Select GPUs with `CUDA_VISIBLE_DEVICES` (NVIDIA) / `HIP_VISIBLE_DEVICES` (AMD; ROCm PyTorch also honors the CUDA one).
- Triton caches compiled kernels in `~/.triton/cache` (`TRITON_CACHE_DIR`); clear it when results look stale.
