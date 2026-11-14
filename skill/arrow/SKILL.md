---
name: arrow
description: Apache Arrow done right — the columnar format and memory model (buffers, validity bitmaps, offsets, dictionary, run-end encoding, string_view/list_view, 64-byte alignment), schemas and types, Array/ChunkedArray/RecordBatch/Table, zero-copy to NumPy, pandas, Polars and PyTorch (DLPack, PyCapsule `__arrow_c_stream__`), IPC stream and file (Feather v2) with lz4/zstd, memory-mapping, Parquet (row groups, statistics, predicate pushdown, use_dictionary, sorting_columns, page index, bloom filters), `pyarrow.dataset` (hive partitions, write_dataset, filters), `pyarrow.compute`, Arrow Flight (Python server/client), the C Data and C Stream Interfaces (ArrowSchema/ArrowArray/ArrowArrayStream) with nanoarrow in C and by hand from Odin, arrow-rs, and Arrow IPC as a Zenoh/dora payload. Load before reading, writing or exchanging columnar data or Parquet.
---

# Apache Arrow

Arrow is a language-independent **in-memory** columnar format plus a toolbox (IPC, Parquet, compute, Flight, C ABI).
Dataframes on top of it: **polars**. Environments: **pixi** (Python only through Pixi). Robotics logs: **mcap**;
transport: **zenoh**, **zenoh-ros2**; training data layout: **ml-data**; plots: **gnuplot**.
Reference library (proposed ids): `arrow-format-source` (spec: `docs/source/format/*.rst`, `format/*.fbs`,
`Flight.proto`), `arrow-python-docs` (`docs/source/python/*.rst`), `nanoarrow-source` (headers + docs). Use
`library_search query="ArrowArrayViewSetArray" sources=["nanoarrow-source"]` for exact signatures. Online:
https://arrow.apache.org/docs/, https://arrow.apache.org/nanoarrow/, https://docs.rs/arrow.

## 0. Versions (13 Nov 2026, verify)

- **Arrow C++/pyarrow 26.0.1** (tag `apache-arrow-26.0.1`, PyPI 2026-11-03; conda-forge `pyarrow`/`libarrow`
  26.0.1). Major release about every 3 months; C++ and Python move together.
- **arrow-rs 60.1.0** (crates `arrow`, `parquet`, `arrow-flight`, 2026-10-28; own numbering, monthly).
- **nanoarrow 0.9.0** (tag `apache-arrow-nanoarrow-0.9.0`; conda-forge `libnanoarrow` (C) and `nanoarrow` (Python)).
- Pixi: `pixi add pyarrow` gives core + Parquet + dataset + compute but **not Flight**: add `libarrow-flight`
  (conda-forge also has `pyarrow-all` 26.0.1 with every component; not tried). Without it: `ImportError: The pyarrow installation is not built with support for
  'flight'`. `pyarrow.cffi` (for C Data tests from Python) needs `cffi`.

## 1. Memory model (spec: Columnar.rst)

- An **Array** = type + length + null_count + offset + **buffers** (+ children, + dictionary). Buffers are
  contiguous, recommended 64-byte aligned and padded; Arrow C++ allocates that way.
- **Validity bitmap** (buffer 0): 1 bit per slot, LSB numbering, 1 = valid. May be absent (NULL) when
  null_count == 0. A null slot still occupies its value slot (undefined contents).
- Primitive: `[validity, values]`. `int32 [1, null, 3]` → validity `0x05`, values 12 bytes (checked).
- Variable-size binary/utf8: `[validity, offsets (int32; int64 for large_*), data]`, offsets length n+1.
  `["ab", null, "cde"]` → offsets `[0, 2, 2, 5]`.
- **string_view / binary_view** (`vu`/`vz`): 16-byte views; strings ≤ 12 bytes inline, longer ones keep a 4-byte
  prefix + buffer index + offset into variadic data buffers. Fast comparisons and cheap slicing/filtering;
  Polars uses it internally.
- **list / large_list / list_view** (`+l`, `+L`, `+vl`): list_view has offsets **and** sizes, so lists can be
  out of order or overlap. `fixed_size_list` (`+w:N`) for vectors/embeddings (no offsets at all).
- **Dictionary**: integer indices + a dictionary array; `pa.array(...).dictionary_encode()`. Parquet keeps it
  (a dictionary column reads back as `dictionary<values=string, indices=int32>`).
- **Run-end encoded** (`+r`): children `run_ends` (int16/32/64) + `values`: `pc.run_end_encode([1,1,1,2,2,3])` →
  run_ends `[3,5,6]`, values `[1,2,3]`. Good for slowly changing columns (mode, frame_id).
- Struct (`+s`) = children of equal length; a **RecordBatch** is a struct array with a schema; a **Table** is a
  list of batches per column (**ChunkedArray**). `table.combine_chunks()` if a consumer wants one chunk.
- **Slicing is zero-copy**: `a.slice(1, 2)` sets `offset=1`, same buffer address. Every consumer must honour
  `offset` (C Data Interface consumers too; see §7).
- Timestamps: `timestamp("ns")` is int64 since the epoch; `.as_py()` of an ns scalar raises `ValueError ... not
  safely convertible to microseconds` unless pandas is installed: use `.value` (int) or cast to int64. The
  same error comes from Parquet `statistics.min/.max` of an ns column (they call `as_py`); read
  `statistics.min_raw` instead.

## 2. Zero-copy interop (all checked)

| From → to | Call | Zero-copy when |
|---|---|---|
| NumPy → Arrow | `pa.array(np_arr)` | numeric, no mask (same buffer address) |
| Arrow → NumPy | `arr.to_numpy(zero_copy_only=True)` | numeric, **no nulls**, single chunk; otherwise `ArrowInvalid` |
| Arrow ↔ Polars | `pl.from_arrow(t)`, `df.to_arrow()`, `pl.DataFrame(t)` | numeric buffers shared (checked both ways); strings convert |
| Any ↔ any (PyCapsule) | `pa.table(obj)`, `pl.DataFrame(obj)`, `pa.array(obj)` | objects with `__arrow_c_stream__` / `__arrow_c_array__` (pyarrow, Polars, nanoarrow, …) |
| Arrow → pandas | `t.to_pandas(types_mapper=pd.ArrowDtype)` | Arrow-backed pandas columns; the default path converts |
| Arrow → PyTorch | `torch.from_dlpack(chunk)` | primitive, no nulls (`ArrowTypeError: Can only use DLPack on arrays with no nulls`) |

- Polars exports `large_string` by default; `df.to_arrow(compat_level=pl.CompatLevel.newest())` gives
  `string_view` (no conversion on the Polars side). pyarrow handles both.
- `torch.from_dlpack(pa_array)` works but warns "Exporting an unversioned DLPack capsule is deprecated"
  (torch 2.14 / pyarrow 26); harmless for now.
- GPU: `__arrow_c_device_array__` exists (C Device Data Interface, `CDeviceDataInterface.rst`) for libraries
  that hand over CUDA buffers (cuDF).

## 3. IPC: stream and file (Feather v2)

```python
import pyarrow as pa, pyarrow.ipc as ipc
with ipc.new_file("log.arrow", t.schema) as w:          # file format = Feather v2 (random access footer)
    w.write_table(t, max_chunksize=1_000_000)
with pa.memory_map("log.arrow") as src:                  # zero-copy: buffers point into the page cache
    t = ipc.open_file(src).read_all()                    # open 0.000 s for 50M rows, pa.total_allocated_bytes() == 0
sink = pa.BufferOutputStream()                           # stream format: schema + batches, no footer (sockets, pubsub)
with ipc.new_stream(sink, t.schema, options=ipc.IpcWriteOptions(compression="zstd")) as w:
    w.write_table(t)
t2 = ipc.open_stream(sink.getvalue()).read_all()
```

- Memory-map only **uncompressed** files: compressed IPC (lz4/zstd) must decompress into new memory (50M rows:
  mmap 471 MB RSS vs zstd-IPC 3.0 GB, Parquet 3.5 GB, plain read 1.7 GB; see §9). Compression is per buffer;
  zstd shrank the random-walk float log only 1700 → 1290 MB, lz4 → 1547 MB.
- `pyarrow.feather.write_feather(t, p, compression="lz4"|"zstd"|"uncompressed")` = IPC file. Polars:
  `pl.read_ipc`/`scan_ipc` (Polars 2.x removed their `memory_map=` argument; `scan_ipc` maps on its own: summing one
  column over 50M rows peaked at 762 MB RSS).
- Use IPC for hot scratch data, inter-process exchange and caches; use Parquet for storage and interchange.
- Shared memory between processes: write the IPC file to `/dev/shm` (Linux) and mmap it in every reader.

## 4. Parquet

```python
import pyarrow.parquet as pq
pq.write_table(t, "log.parquet", compression="zstd", compression_level=3, row_group_size=1_000_000,
               use_dictionary=["topic", "quality"],      # NOT on high-cardinality floats (see below)
               write_statistics=True, write_page_index=True,
               sorting_columns=[pq.SortingColumn(0)])    # records that col 0 (ts) is sorted; does not sort
md = pq.ParquetFile("log.parquet").metadata              # row groups, per-column statistics, encodings
md.row_group(0).column(0).statistics.min / .max
pq.read_table("log.parquet", columns=["x"], filters=[("quality", ">", 90)])
```

- **Row groups** are the unit of skipping and parallelism: 128 MB–1 GB uncompressed or ~1M rows is a good default.
  On 50M rows (24 cores): 128k-row groups wrote **3–6× slower and 20–30 % larger** than 1M-row groups.
- **Dictionary trap**: `use_dictionary=True` (the default) tries dictionary pages for every column. On
  high-cardinality floats each column chunk builds a dictionary, overflows `dictionary_pagesize_limit`, and falls
  back to PLAIN, keeping the wasted dictionary page. Restricting it to low-cardinality columns
  (`use_dictionary=["topic","quality"]`) on 50M rows: 1287 MB in 3.1 s vs 1699 MB in 14.7 s (rg 128k), and it
  makes row-group size almost irrelevant for size (§9).
- Compression on noisy sensor floats is weak (random walk: none 1716 MB, lz4 1586, zstd-1 1339, zstd-3 1334,
  zstd-9 1334 MB). lz4/snappy: fastest write and read; zstd 1–3: smallest at little cost; zstd-9: 2× write time
  for nothing. Change the **encoding** instead: `use_byte_stream_split=["x","y","z"]` (floats) and
  `column_encoding={"ts": "DELTA_BINARY_PACKED"}` (sorted ints/timestamps). On 50M rows (zstd): 1287 MB →
  1106 MB with byte-stream-split, 1067 MB with both, and faster writes and reads. `column_encoding` raises
  `ValueError: To use 'column_encoding' set 'use_dictionary' to False` when `use_dictionary=True`; a list of
  other columns is fine. Quantizing (float32, fixed-point int) helps more than any codec level.
- **Statistics + sorted data = pushdown**: min/max per row group let readers skip groups. A 1 % time window on
  the ts-sorted file read 2 of 48 row groups (0.011 s); on a shuffled copy all 48 (0.21 s, see §9). Sort (or cluster) by the
  column you filter on most. `bloom_filter_options` and `write_page_index` help point lookups.
- Timestamps: write ns or µs explicitly; `coerce_timestamps="us"` for old readers. Don't use INT96.
- Other writer knobs (pyarrow 26): `max_rows_per_page`, `data_page_version="2.0"`, `store_schema`,
  `use_content_defined_chunking` (dedup-friendly pages for content-addressed storage, e.g. Hugging Face Xet).

## 5. Datasets (`pyarrow.dataset`)

```python
import pyarrow.dataset as ds
ds.write_dataset(t, "log_ds", format="parquet", partitioning=["topic"], partitioning_flavor="hive",
                 file_options=ds.ParquetFileFormat().make_write_options(compression="zstd"),
                 max_rows_per_file=20_000_000, min_rows_per_group=512_000, max_rows_per_group=1_048_576,
                 existing_data_behavior="overwrite_or_ignore")
d = ds.dataset("log_ds", format="parquet", partitioning="hive")
d.to_table(columns=["x"], filter=(ds.field("topic") == "/imu") & (ds.field("quality") > 95))
for frag in d.get_fragments(): frag.subset(filter=f).row_groups      # which row groups survive the filter
d.scanner(columns=[...], filter=f, batch_size=1 << 20).to_batches()   # streaming, bounded memory
```

- Hive directories are URL-encoded: `/imu` → `topic=%2Fimu`. Partition columns come back as `string`/`int32`
  (declare `partitioning=ds.partitioning(schema, flavor="hive")` to control types).
- Partition by low-cardinality keys you filter on (date, robot, topic); thousands of tiny files are slower than
  one file with good row groups. Aim for files ≥ 100 MB.
- Dataset filters prune partitions first, then row groups by statistics, then filter rows.

## 6. Compute (`pyarrow.compute`)

`pc.sum/mean/min_max/count_distinct`, `pc.filter`, `pc.take`, `pc.sort_indices`, `pc.cast`, `pc.if_else`,
`pc.is_in`, `pc.strftime`, `pc.run_end_encode`, string kernels (`pc.utf8_*`, `pc.match_substring_regex`);
expressions `pc.field("x") > 0.5` work in `Table.filter` and dataset filters; `t.group_by("topic").aggregate([("x",
"mean"), ("x", "count")])`; `t.join(other, keys="id")` (Acero). For anything beyond simple kernels use **polars**
on the same buffers.

## 7. C Data Interface, C Stream Interface, nanoarrow, Odin

The ABI (spec `CDataInterface.rst`, `CStreamInterface.rst`): `struct ArrowSchema` (72 bytes: format string, name,
metadata, flags, children, dictionary, release, private_data), `struct ArrowArray` (80 bytes: length,
null_count, offset, n_buffers, n_children, buffers, children, dictionary, release, private_data),
`struct ArrowArrayStream` (get_schema, get_next, get_last_error, release). Format strings: `l` int64, `g` float64,
`u` utf8, `U` large utf8, `vu` utf8 view, `tsn:` timestamp[ns] (no tz), `+s` struct, `+l` list, `+r` REE.

Rules that bite: the consumer calls the **base** `release` only (never children's); the producer's release
must release children and dictionary, free its own memory, and set `release = NULL`; structures may be
moved (memcpy) by the consumer, so release must not rely on their address; respect `offset` in every buffer.

**Python side** (checked with C and Odin producers):
```python
from pyarrow.cffi import ffi
c_arr, c_sch = ffi.new("struct ArrowArray*"), ffi.new("struct ArrowSchema*")
lib.export_batch(int(ffi.cast("uintptr_t", c_arr)), int(ffi.cast("uintptr_t", c_sch)), 10)  # ctypes lib
rb = pa.RecordBatch._import_from_c(int(ffi.cast("uintptr_t", c_arr)), int(ffi.cast("uintptr_t", c_sch)))
rdr = pa.RecordBatchReader._import_from_c(stream_ptr)            # C Stream Interface
arr._export_to_c(array_ptr, schema_ptr)                           # Python → C (consumer must release)
```
(The `_import_from_c`/`_export_to_c` names are pyarrow's documented low-level API; between Python libraries use
the PyCapsule protocol instead.)

**nanoarrow (C)** — builder + view API, no C++:
```c
ArrowSchemaInit(s); ArrowSchemaSetTypeStruct(s, 3);
ArrowSchemaSetTypeDateTime(s->children[0], NANOARROW_TYPE_TIMESTAMP, NANOARROW_TIME_UNIT_NANO, NULL);
ArrowSchemaSetName(s->children[0], "ts"); /* … */
ArrowArrayInitFromSchema(a, s, &err); ArrowArrayStartAppending(a);
ArrowArrayAppendInt(a->children[0], t); ArrowArrayAppendNull(a->children[1], 1);
ArrowArrayAppendString(a->children[2], ArrowCharView("/imu")); ArrowArrayFinishElement(a);
ArrowArrayFinishBuildingDefault(a, &err);              /* then hand a + s to the consumer */
ArrowBasicArrayStreamInit(stream, s, n); ArrowBasicArrayStreamSetArray(stream, i, a);   /* moves */
ArrowArrayViewInitFromSchema(&v, s, &err); ArrowArrayViewSetArray(&v, a, &err);        /* consume */
ArrowArrayViewIsNull(&v, i); ArrowArrayViewGetDoubleUnsafe(&v, i); ArrowArrayViewReset(&v);
ArrowIpcInputStreamInitBuffer(&in, &buf); ArrowIpcArrayStreamReaderInit(&stream, &in, NULL);  /* IPC bytes */
```
Link: `-lnanoarrow_ipc_shared -lnanoarrow_shared` (conda-forge `libnanoarrow`, headers
`include/nanoarrow/{nanoarrow.h,nanoarrow_ipc.h}`; no pkg-config or CMake files). Static:
`-lnanoarrow_ipc_static -lnanoarrow_static -lflatccrt -lzstd -llz4` (else undefined `flatcc_builder_*`). The
IPC reader decoded zstd-compressed pyarrow streams. Python wrapper: `nanoarrow` (`na.c_array`, `na.Array`).

**Odin**: there is no vendor package; the structs are plain C and easy to fill by hand. Validated: an Odin shared
library exported a 1M-row `{ts: tsn:, x: g with nulls, topic: u}` batch, pyarrow imported it,
`validate(full=True)` passed, Polars grouped it, and the release callbacks freed everything; an Odin consumer
summed a sliced pyarrow array (offset honoured).
```odin
ArrowArray :: struct {
	length, null_count, offset, n_buffers, n_children: i64,
	buffers: [^]rawptr, children: [^]^ArrowArray, dictionary: ^ArrowArray,
	release: proc "c" (a: ^ArrowArray), private_data: rawptr,
}
#assert(size_of(ArrowArray) == 80)          // ArrowSchema: format, name: cstring; metadata: [^]u8; flags,
                                            // n_children: i64; children; dictionary; release; private_data (72)
release_array :: proc "c" (a: ^ArrowArray) {
	context = runtime.default_context()
	for i in 0 ..< a.n_children { ch := a.children[i]; if ch.release != nil do ch.release(ch) }
	/* free buffers owned via a.private_data */
	a.release = nil
}
foreign import nanoarrow "system:nanoarrow_shared"    // only non-inline functions are exported:
@(default_calling_convention = "c")                    // ArrowArrayViewInitFromSchema/SetArray/Validate/Reset,
foreign nanoarrow {                                    // ArrowSchemaToString, ArrowArrayInitFromSchema, …
	ArrowArrayViewValidate :: proc(v: ^ArrowArrayView, level: c.int, e: ^ArrowError) -> c.int ---
}
```
Gotchas: nanoarrow's `ArrowArrayAppend*` and `ArrowArrayStartAppending` are `static inline` (not in the .so),
so from Odin fill buffers yourself (faster anyway) and use nanoarrow only to validate
(`NANOARROW_VALIDATION_LEVEL_FULL` = 3; `struct ArrowArrayView` is 200 bytes, `struct ArrowError` 1024 on 64-bit);
allocate buffers 64-byte aligned (`mem.alloc(n, 64)`); validity bit i = `bits[i/8] >> (i%8) & 1`; a struct
array has `n_buffers = 1` (validity, may be NULL). Build: `odin build dir -build-mode:shared
-extra-linker-flags:"-L$CONDA_PREFIX/lib -Wl,-rpath,$CONDA_PREFIX/lib"` inside `pixi run`. See odin, odin-performance.

## 8. Flight, Zenoh/dora, Rust

- **Flight** = gRPC streams of IPC record batches (`do_put`, `do_get`, `list_flights`, `get_flight_info`,
  `do_action`, `do_exchange`). Minimal server: subclass `pyarrow.flight.FlightServerBase(location)`, return
  `flight.RecordBatchStream(table)` from `do_get`, `reader.read_all()` in `do_put`; client
  `flight.connect("grpc://host:port")`, `writer, _ = c.do_put(FlightDescriptor.for_path("log"), schema)`,
  `c.do_get(flight.Ticket(b"log")).read_all()`. `grpc://127.0.0.1:0` picks a free port (`server.port`).
  Loopback, 50M rows/1.6 GB: put 1.7 GB/s, get 2.1 GB/s. Use `grpc+tls://` and auth middleware off-host.
  Flight SQL / ADBC are the database-facing layers on top.
- **Over Zenoh / dora**: send IPC *stream* bytes as the payload (schema + batch, or schema once and then
  `ipc.read_record_batch(buf, schema)` per message); decode with `pa.py_buffer(sample.payload.to_bytes())`. dora
  nodes already exchange Arrow arrays (`node.send_output("out", pa.array(x), metadata)`). nanoarrow_ipc decodes
  the same bytes in C/microcontroller-class code. See zenoh, zenoh-ros2.
- **Rust**: `arrow` 60.1 (`RecordBatch`, `arrow::ffi::{FFI_ArrowArray, FFI_ArrowSchema}`,
  `arrow::ffi_stream`), `parquet` 60.1 (`ArrowWriter`, `ParquetRecordBatchReaderBuilder`, `WriterProperties`),
  `arrow-flight`. Validated: `ArrowWriter` with `WriterProperties::builder().set_compression(Compression::ZSTD(
  ZstdLevel::try_new(3)?)).set_max_row_group_row_count(Some(250_000))` → 4 row groups, read back with
  `ParquetRecordBatchReaderBuilder::try_new(file)?.build()?`. `set_max_row_group_size` no longer exists in 60.x
  (compile error; `set_max_row_group_bytes` is the byte-based alternative). Polars uses its own Arrow implementation (polars-arrow) but speaks the same C ABI.

## 9. Measured (powerslabs: 24-core x86_64, 125 GB RAM, NVMe; pyarrow 26.0.1; warm page cache)

50M rows `{ts ns, topic dict<int8,string> (8 topics), x/y/z float64 random walk, quality uint8}` = 1700 MB.

| Parquet (write / read all / read `x`) | rg 128k | rg 1M | rg 8M |
|---|---|---|---|
| none | 2074 MB, 13.9 / 0.88 / 0.16 s | 1716 MB, 5.3 / 2.0 / 0.44 s | 1670 MB, 1.8 / 2.9 / 0.39 s |
| lz4 | 1946 MB, 13.0 / 0.53 / 0.24 s | 1586 MB, 3.0 / 0.37 / 0.09 s | 1541 MB, 2.1 / 0.95 / 0.41 s |
| zstd-3 | 1666 MB, 15.2 / 1.43 / 0.26 s | 1334 MB, 5.3 / 1.47 / 0.44 s | 1292 MB, 4.1 / 2.2 / 0.63 s |
| zstd-9 | 1676 MB, 20.3 / 0.84 / 0.16 s | 1334 MB, 10.8 / 1.43 / 0.35 s | 1291 MB, 9.7 / 1.1 / 0.59 s |

| Same data, 1M-row groups unless noted | Size | Write / read |
|---|---|---|
| zstd, default `use_dictionary=True` (rg 128k) | 1699 MB | 14.7 / 0.45 s |
| zstd, `use_dictionary=["topic","quality"]` (rg 128k) | 1287 MB | 3.1 / 0.29 s |
| zstd, + `use_byte_stream_split=["x","y","z"]` | 1106 MB | 2.8 / 0.35 s |
| zstd, + `column_encoding` DELTA ts + BYTE_STREAM_SPLIT xyz | **1067 MB** | 2.6 / 0.30 s |
| lz4, DELTA ts + BYTE_STREAM_SPLIT xyz | 1079 MB | 2.0 / 0.29 s |
| Polars `write_parquet(compression="zstd")` (its defaults: no float dictionary, ~122k-row groups) | 1275 MB | **0.62 s** |

Pushdown (1 % time window, `x` only): ts-sorted file **0.011 s, 2/48 row groups read**; shuffled copy 0.209 s,
48/48 (full scan 0.19–0.25 s). Hive dataset by topic (`write_dataset` 3.1 s): `topic == "/gps"` 1.0M rows in
< 0.01 s (partition pruning), `/imu & quality > 95` 0.05 s, unfiltered 0.10 s.

| Reading the 50M-row file | Open | Peak RSS |
|---|---|---|
| IPC, `pa.memory_map` | 0.000 s (0 bytes allocated) | 471 MB |
| IPC, `pa.OSFile` read | 0.23 s | 1734 MB |
| zstd IPC, memory-mapped | 0.30 s | 3025 MB |
| Parquet zstd-3 `read_table` | 0.36 s | 3533 MB |
| Polars `scan_ipc(...).select(sum)` | — | 762 MB |

Numbers are single runs on a warm cache; re-measure on your data (sensor floats compress far worse than
counters or enums).

## 10. Pitfalls

- `pyarrow` from conda-forge without `libarrow-flight` → no Flight. Mixing pip and conda pyarrow → ABI errors.
- `to_numpy()` silently copies (and turns ints with nulls into floats) unless `zero_copy_only=True`.
- Chunked columns: many consumers want one chunk (`combine_chunks()`), which copies.
- `large_string` vs `string` vs `string_view` mismatches fail `Table.equals`/concat: `cast` first.
- Default `use_dictionary=True` on float columns bloats files and slows writes (§4).
- Tiny row groups / tiny files kill scan speed; huge row groups (8M) slowed full reads here (less parallel work).
- Compressed IPC cannot be zero-copy; don't memory-map it expecting low RSS.
- Releasing C Data structures twice, or calling child release callbacks as a consumer, crashes later.
