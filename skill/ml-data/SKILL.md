---
name: ml-data
description: Store, organize and load training data so the GPU never waits — choosing formats (WebDataset tar shards, MDS/LitData, Parquet/Arrow, Lance, Zarr/HDF5, raw arrays, FFCV), sharding and shuffling, exact resume (StatefulDataLoader), multi-GPU splitting, decoding on CPU vs GPU (TorchCodec, DALI, nvJPEG/NVDEC), DataLoader tuning (workers, worker seeding, pinned memory, prefetch, persistent workers, torchdata.nodes, free-threaded Python), the three setups CPU-only / GPU-heavy / CPU+GPU, local vs network vs object storage, and measuring whether data loading is the bottleneck (loader-only benchmark). Load before designing a dataset layout, a data pipeline, or when GPU utilization is low.
---

# Data that keeps the GPU busy

## 0. Measure first (always)

A pipeline is fast enough when the GPU never waits. Check before changing anything:

- **Loader-only vs model-only throughput** (run both on the training machine, same batch size):
  ```python
  import time, torch
  def loader_rate(loader, warmup=20, n=200):              # data only: no model, but include the H2D copy
      it = (b for _ in iter(int, 1) for b in loader)      # cycles epochs: no StopIteration if warmup+n > len(loader)
      for _ in range(warmup): next(it)
      torch.cuda.synchronize(); t = time.perf_counter()
      for _ in range(n): b = next(it); x = b[0].cuda(non_blocking=True)   # adapt to the batch structure
      torch.cuda.synchronize(); return n * loader.batch_size / (time.perf_counter() - t)
  def model_rate(step, batch, warmup=20, n=100):         # synthetic batch kept on the GPU, no loader
      for _ in range(warmup): step(batch)
      torch.cuda.synchronize(); t = time.perf_counter()
      for _ in range(n): step(batch)
      torch.cuda.synchronize(); return n * batch[0].shape[0] / (time.perf_counter() - t)
  ```
  If loader samples/s < ~1.2 × model samples/s, data is (or will become) the bottleneck. Measure the second epoch
  too (page cache) and on a cold cache if the dataset is larger than RAM. Log both numbers to MLflow (ml-training).
- **GPU utilization over time** (MLflow system metrics, `nvidia-smi dmon`, `rocm-smi`): sawtooth or gaps between steps
  mean starving. `torch.profiler` / `nsys`: look for idle GPU stretches at `next(iter)` / `DataLoader` and before H2D copies.
- **Which stage**: storage read (`iostat -x 1`, network), decode/augment (CPU% per worker, `py-spy top --pid`),
  collate, or host-to-device copy (`pin_memory`, non-blocking). Time one stage at a time (dataset `__getitem__` alone,
  then with collate, then with workers); fix the slowest; re-measure.

## 1. Pick the format by data type and access pattern

| Data | Store as | Why |
|---|---|---|
| Images/audio/video, large (≥ ~100k files or ≥ ~100 GB) | **Shards of 100 MB–1 GB**: WebDataset tar, MDS (Mosaic `streaming`), or LitData chunks; keep media **compressed** (JPEG/WebP/FLAC/mp4) | Large sequential reads instead of millions of small random ones; works from local disk, NFS and object storage |
| Same, fixed preprocessing, max throughput on one node | **FFCV** (`.beton`, pre-resized; RAW for small images) | Page-aligned, pre-decoded or pre-resized; fewest CPU cycles per sample. Check it still installs with your Python/CUDA (little recent development) |
| Tabular, text tokens, metadata, embeddings | **Parquet** (Arrow; zstd; row groups 64–256 MB) or Hugging Face `datasets` (Arrow, memory-mapped) | Columnar, column projection, filters; zero-copy mmap |
| Pre-tokenized LM corpora | **flat `uint16`/`uint32` binary + offsets (`np.memmap`)**, or MDS/LitData token chunks | A sample is a slice; no parsing at all |
| Dense arrays (scientific, satellite, volumes, features) | **Zarr v3** (chunked, compressed, cloud-friendly) or **HDF5** (single file, local) | Chunk shape = access pattern; read only needed chunks |
| Multimodal with random access, versioning, vector search | **Lance** (`pylance`) | Columnar with fast random access; appends/versions |
| Small (fits in RAM, < ~10 GB) | Anything; **load once into RAM** (or a GPU tensor) | The format no longer matters |
| Many small raw files (one per sample) | Only for small datasets or inspection | Metadata storms on network/parallel filesystems and object stores |

Rules that matter more than the format:
- **Do the expensive, fixed work once, offline**: resize to the largest training resolution, transcode video to a
  decodable codec and keyframe interval, tokenize, compute features. Keep random augmentation online.
- **Sample size on disk sets the I/O budget**: samples/s × bytes/sample must fit the storage bandwidth with headroom.
  Compressed media trades disk/network for CPU (or GPU) decode; raw trades the other way.
- **Shard count ≥ 10 × (nodes × GPUs × workers)** so every worker gets distinct shards each epoch.
- Store labels/metadata in the same shard as the sample (WebDataset `.json`/`.cls` alongside `.jpg`), not in a
  separate lookup that needs random access.
- Write an index/manifest (sample count, shard list, checksums, dataset revision) and version it; splits, dedup and
  leakage: the **datasets** skill.

## 2. Shuffling, determinism, resume, multi-GPU

- Two-level shuffle: shuffle the **shard order** per epoch (seeded by epoch), then a **sample buffer** within each
  worker (WebDataset `.shuffle(1000–10000)`). Buffer size × sample size must fit RAM.
- Pre-shuffle the data globally once when writing shards, so neighbors in a shard are not correlated (e.g. not all
  one class or one recording session).
- **Seed workers**: random augmentations in workers need per-worker seeds. Pass `generator=torch.Generator().manual_seed(s)`
  and `worker_init_fn` that seeds NumPy/`random` from `torch.initial_seed() % 2**32` (PyTorch "Reproducibility"
  notes), or every worker (and every epoch with non-persistent workers) repeats the same NumPy "random" crops.
- **Mid-epoch resume**: MDS and LitData resume exactly (`state_dict()` on their loader/dataset). With the PyTorch
  DataLoader use `from torchdata.stateful_dataloader import StatefulDataLoader` (drop-in replacement; save
  `loader.state_dict()` in the checkpoint, `load_state_dict` on resume), or `torchdata.nodes` (`Loader` is stateful).
- **Multi-GPU**: each rank must get distinct data and **the same number of batches**, or DDP/FSDP hangs at the end of an
  epoch. Map-style: `DistributedSampler(ds, shuffle=True, drop_last=True)` and call `sampler.set_epoch(epoch)` every
  epoch (else the same order every epoch). Iterable/WebDataset: split shards by node and worker
  (`wds.split_by_node`, `wds.split_by_worker`, or `resampled=True` + `.with_epoch(n)` for a fixed per-rank length);
  MDS/LitData split by rank automatically.

## 3. The three setups

### CPU-only (no GPU, or CPU inference/training of small models)
- The bottleneck is usually compute, not I/O: keep data **in RAM** (NumPy/Arrow, memory-mapped Parquet/`.npy`),
  avoid Python per-sample loops (vectorize the batch: index arrays, `torch.from_numpy` once per batch; a
  `BatchSampler` as the sampler with `batch_size=None` fetches whole batches in one `__getitem__`).
- `num_workers=0` or small: worker processes compete with the model's intra-op threads. Set `torch.set_num_threads`
  to physical cores minus worker count; benchmark both.
- Prefer formats that decode cheaply (raw arrays, pre-resized uint8) over JPEG/video decode on the same CPU.

### GPU-heavy, CPU-light (many GPUs, few cores per GPU; decode-bound images/video)
- Move **decode and augmentation onto the GPU**: TorchCodec (`torchcodec.decoders.decode_jpeg(list_of_bytes,
  device="cuda")` batches nvJPEG; `VideoDecoder(path, device="cuda")` uses NVDEC), NVIDIA **DALI** (decode + augment
  pipelines with their own prefetching; `nvidia-dali-cuda130`), or decode-free formats (FFCV RAW, pre-decoded uint8
  arrays). Then augment in batches on the GPU (`torchvision.transforms.v2` works on CUDA tensors).
- Workers then only read bytes; decode in the main process (CUDA in forked workers fails) or use DALI.
- Verified Nov 2026 on Blackwell sm_120 (conda-forge `torchcodec` 0.17): `decode_jpeg(list, device="cuda")` returns a
  list of CUDA uint8 tensors matching CPU decode. `VideoDecoder(device="cuda")` failed with "the provided PTX was
  compiled with an unsupported toolchain" when the build's CUDA (`cuda134`) was newer than the driver (13.0); it
  worked with `cuda-version = "13.0.*"`. The error is sticky: later CUDA calls in that process fail too.
- Transfer **uint8** to the GPU and normalize/convert there (`x.cuda(non_blocking=True).float().div_(255)`): 4× less
  host→device traffic than float32.
- Costs GPU time and memory; worth it only when the GPU would otherwise wait. Re-measure after.

### CPU + GPU (the common case)
- CPU workers read + decode + augment, the GPU trains. Size workers so loader throughput ≥ 1.2 × model throughput:
  start at `num_workers = physical_cores / GPUs` (minus 1–2), then measure; more workers beyond that add RAM and
  contention, not speed. Limit per-worker threads (OpenCV `cv2.setNumThreads(0)`, `OMP_NUM_THREADS`) to avoid
  oversubscription.
- `pin_memory=True` + `.to(device, non_blocking=True)`; `persistent_workers=True` (no respawn per epoch);
  `prefetch_factor=2–4` (batches per worker in flight); `drop_last=True` for stable shapes (`torch.compile`, CUDA
  graphs); `in_order=False` lets a slow sample not stall the batch order (non-deterministic order).
- Worker RAM: keep Python lists of millions of objects out of the dataset (copy-on-access refcounts duplicate them
  per worker); use NumPy/Arrow arrays or memory-mapped files.
- Collate cheaply: return tensors, not lists of dicts of Python objects; for variable sizes, bucket by length
  (sequences) or aspect ratio (images) to limit padding.
- CUDA streams prefetcher (copy batch N+1 while computing N) when the copy shows up in the profile.
- `torchdata.nodes` composes `Mapper`/`ParallelMapper` (threads or processes), `Batcher`, `PinMemory`, `Prefetcher`
  and `Loader` (checkpointable). With free-threaded Python (3.13t/3.14t) thread workers avoid process overhead and
  pickling for CPU-heavy pipelines; check that every library in the pipeline supports it.

## 4. Storage tiers

| Where | Typical bandwidth | Do |
|---|---|---|
| RAM / page cache | 10+ GB/s | Small datasets; second epoch onwards if it fits |
| Local NVMe | 2–7 GB/s per drive (PCIe 4/5) | **Stage hot data here** before training (rsync, `s5cmd`, LitData/MDS local cache) |
| NFS / Lustre / GPFS | varies; small files are the killer | Large shards only; never millions of tiny files |
| Object storage (S3, GCS, Azure Blob) | high aggregate, high latency per request | Streaming formats (MDS, LitData, WebDataset over HTTP) with local cache; many parallel requests; same region as the GPUs |

Copy the dataset to the GPU machine's local disk when it fits; streaming is for when it doesn't, or for many nodes.
On RunPod/Azure, put it on the instance's local NVMe (or a network volume in the same region) before starting.

## 5. Library notes (as of Nov 2026; verify versions)

- **TorchCodec** (0.17) is the PyTorch way to decode/encode images, video and audio on CPU and CUDA (`decode_image`,
  `decode_jpeg`, `VideoDecoder`, `AudioDecoder`); TorchVision's image decode/encode is deprecated since torchvision
  0.29 in its favor. TorchVision/TorchAudio remain for transforms.
- **torchdata** (0.11): DataPipes and DataLoader2 were removed (0.10, 2024); use `torch.utils.data.DataLoader`,
  `StatefulDataLoader`, or `torchdata.nodes`.
- **WebDataset** (1.0): simple tar shards, any storage; `wids` (same repo, separate PyPI package) for indexed
  random access over shards. **Mosaic `streaming`**
  (`mosaicml-streaming` 0.13, MDS): deterministic, elastic resume, cloud cache. **LitData** (0.2.x): `optimize()` +
  `StreamingDataset`/`StreamingDataLoader`. **FFCV**: fastest for fixed image pipelines on one node. **DALI** (2.x):
  GPU decode/augment. Benchmarks between them depend strongly on hardware and settings: measure on yours.

## 6. Checklist for a new training project

1. Size: bytes on disk, sample count, bytes/sample; required samples/s = model throughput × 1.2.
2. Can it live in RAM or on local NVMe? Then do that.
3. Offline preprocessing done (resize/transcode/tokenize)? Shards written with a manifest and version?
4. Loader-only benchmark ≥ target? GPU utilization flat near 100% during training?
5. Determinism: seeded shard/sample shuffle per epoch, seeded workers, `set_epoch`; exact resume; distinct data per
   rank, equal batch counts.

Related: **ml-training** (profiling, checkpoints, distributed), **datasets** (collection, splits, documentation),
**ml-tuning** (augmentation as regularization, batch size).
