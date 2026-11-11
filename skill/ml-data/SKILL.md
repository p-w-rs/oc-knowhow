---
name: ml-data
description: Store, organize and load training data so the GPU never waits — choosing formats (WebDataset tar shards, MDS/LitData, Parquet/Arrow, Lance, Zarr/HDF5, raw arrays, FFCV), sharding and shuffling, decoding on CPU vs GPU (TorchCodec, DALI, nvJPEG/NVDEC), DataLoader tuning (workers, pinned memory, prefetch, persistent workers, torchdata.nodes, free-threaded Python), the three setups CPU-only / GPU-heavy / CPU+GPU, local vs network vs object storage, and measuring whether data loading is the bottleneck. Load before designing a dataset layout, a data pipeline, or when GPU utilization is low.
---

# Data that keeps the GPU busy

## 0. Measure first (always)

A pipeline is fast enough when the GPU never waits. Check before changing anything:

- **Loader-only throughput**: iterate the DataLoader with the model removed (`for batch in loader: pass`, after warm-up)
  and report samples/s. Compare with the model's training throughput on a **synthetic batch kept on the GPU**
  (same shape, no loader). If loader-only < model-only, data is the bottleneck.
- **GPU utilization over time** (MLflow system metrics, `nvidia-smi dmon`, `rocm-smi`): sawtooth or gaps between steps
  mean starving. `torch.profiler` / `nsys`: look for idle GPU stretches before `cudaMemcpy` / at `next(iter)`.
- **Which stage**: storage read (iostat, network), decode/augment (CPU% per worker, `py-spy top`), collate, or
  host-to-device copy (`pin_memory`, non-blocking). Fix the slowest one; re-measure.

## 1. Pick the format by data type and access pattern

| Data | Store as | Why |
|---|---|---|
| Images/audio/video, large (≥ ~100k files or ≥ ~100 GB) | **Shards of 100 MB–1 GB**: WebDataset tar, MDS (Mosaic `streaming`), or LitData chunks; keep media **compressed** (JPEG/WebP/FLAC/mp4) | Large sequential reads instead of millions of small random ones; works from local disk, NFS and object storage |
| Same, fixed preprocessing, max throughput on one node | **FFCV** (`.beton`, pre-resized; RAW for small images) | Page-aligned, pre-decoded or pre-resized; fewest CPU cycles per sample |
| Tabular, text tokens, metadata, embeddings | **Parquet** (Arrow; zstd; row groups 64–256 MB) or Hugging Face `datasets` (Arrow, memory-mapped) | Columnar, column projection, filters; zero-copy mmap |
| Pre-tokenized LM corpora | **flat `uint16`/`uint32` binary + offsets (`np.memmap`)**, or MDS/LitData token chunks | A sample is a slice; no parsing at all |
| Dense arrays (scientific, satellite, volumes, features) | **Zarr v3** (chunked, compressed, cloud-friendly) or **HDF5** (single file, local) | Chunk shape = access pattern; read only needed chunks |
| Multimodal with random access, versioning, vector search | **Lance** | Columnar with fast random access; appends/versions |
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
- Write an index/manifest (sample count, shard list, checksums, dataset revision) and version it (see the datasets
  skill).

## 2. Shuffling and determinism with shards

- Two-level shuffle: shuffle the **shard order** per epoch (seeded by epoch), then a **sample buffer** within each
  worker (WebDataset `.shuffle(1000–10000)`). Buffer size × sample size must fit RAM.
- Pre-shuffle the data globally once when writing shards, so neighbors in a shard are not correlated (e.g. not all
  one class or one recording session).
- Mid-epoch resume: MDS and LitData resume exactly; with plain DataLoader use `torchdata`'s `StatefulDataLoader`
  (state_dict / load_state_dict) or `torchdata.nodes`.
- Multi-GPU: each rank must get distinct data and **the same number of batches** (`DistributedSampler` for map-style;
  shard-splitting by rank and worker for iterable; drop or pad the remainder) or DDP hangs at the end of an epoch.

## 3. The three setups

### CPU-only (no GPU, or CPU inference/training of small models)
- The bottleneck is usually compute, not I/O: keep data **in RAM** (NumPy/Arrow, memory-mapped Parquet/`.npy`),
  avoid Python per-sample loops (vectorize the batch: index arrays, `torch.from_numpy` once per batch).
- `num_workers=0` or small: worker processes compete with the model's intra-op threads. Set `torch.set_num_threads`
  to physical cores minus worker count; benchmark both.
- Prefer formats that decode cheaply (raw arrays, pre-resized uint8) over JPEG/video decode on the same CPU.

### GPU-heavy, CPU-light (many GPUs, few cores per GPU; decode-bound images/video)
- Move **decode and augmentation onto the GPU**: TorchCodec (images: JPEG on CUDA via nvJPEG; video via NVDEC),
  NVIDIA **DALI** (decode + augment pipelines with its own prefetching), or decode-free formats (FFCV RAW, pre-decoded
  uint8 arrays). Then do augmentation in batches on the GPU (`torchvision.transforms.v2` works on CUDA tensors).
- Transfer **uint8** to the GPU and normalize/convert there (`x.cuda(non_blocking=True).float().div_(255)`): 4× less
  host→device traffic than float32.
- Costs GPU time and memory; worth it only when the GPU would otherwise wait. Re-measure after.

### CPU + GPU (the common case)
- CPU workers read + decode + augment, the GPU trains. Size workers so loader throughput ≥ 1.2 × model throughput:
  start at `num_workers = physical_cores / GPUs` (minus 1–2), then measure; more workers beyond that add RAM and
  contention, not speed.
- `pin_memory=True` + `.to(device, non_blocking=True)`; `persistent_workers=True` (no respawn per epoch);
  `prefetch_factor=2–4` (batches per worker in flight); `drop_last=True` for stable shapes (`torch.compile`, CUDA
  graphs).
- Collate cheaply: return tensors, not lists of dicts of Python objects; for variable sizes, bucket by length
  (sequences) or aspect ratio (images) to limit padding.
- CUDA streams prefetcher (copy batch N+1 while computing N) when the copy shows up in the profile.
- Free-threaded Python (3.13t/3.14t) with `torchdata.nodes` thread workers avoids process overhead and pickling for
  CPU-heavy pipelines; check library support first.

## 4. Storage tiers

| Where | Typical bandwidth | Do |
|---|---|---|
| RAM / page cache | 10+ GB/s | Small datasets; second epoch onwards if it fits |
| Local NVMe | 2–7 GB/s per drive | **Stage hot data here** before training (rsync, `s5cmd`, LitData/MDS local cache) |
| NFS / Lustre / GPFS | varies; small files are the killer | Large shards only; never millions of tiny files |
| Object storage (S3, GCS, Azure Blob) | high aggregate, high latency per request | Streaming formats (MDS, LitData, WebDataset over HTTP) with local cache; many parallel requests; same region as the GPUs |

Copy the dataset to the GPU machine's local disk when it fits; streaming is for when it doesn't, or for many nodes.

## 5. Library notes (as of late 2026; verify versions)

- **TorchCodec** is the PyTorch way to decode/encode images, video and audio on CPU and CUDA; TorchVision/TorchAudio
  decoders are deprecated in its favor. TorchVision/TorchAudio remain for transforms.
- **torchdata**: DataPipes and DataLoader2 were removed (0.10, 2024); use `torch.utils.data.DataLoader`,
  `StatefulDataLoader`, or `torchdata.nodes` (composable iterators, thread or process workers, checkpointable).
- **WebDataset**: simple tar shards, any storage; `wids` for indexed random access. **Mosaic `streaming` (MDS)**:
  deterministic, elastic resume, cloud cache. **LitData**: `optimize()` + `StreamingDataset`, fast conversion and
  streaming. **FFCV**: fastest for fixed image pipelines on one node. **DALI**: GPU decode/augment. Benchmarks
  between them depend strongly on hardware and settings: measure on yours.

## 6. Checklist for a new training project

1. Size: bytes on disk, sample count, bytes/sample; required samples/s = model throughput × 1.2.
2. Can it live in RAM or on local NVMe? Then do that.
3. Offline preprocessing done (resize/transcode/tokenize)? Shards written with a manifest and version?
4. Loader-only benchmark ≥ target? GPU utilization flat near 100% during training?
5. Determinism: seeded shard/sample shuffle per epoch; exact resume; distinct data per rank, equal batch counts.
