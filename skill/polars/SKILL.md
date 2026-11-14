---
name: polars
description: Polars 2.x for fast dataframes in Python (and the Rust crate) — eager vs lazy (scan_parquet/scan_ipc/scan_csv, collect, the streaming engine that is now the lazy default, out-of-core spilling, sink_parquet and PartitionBy), expressions (select/with_columns/filter/group_by/agg, when/then/otherwise, over windows, rolling, group_by_dynamic, join and join_asof for sensor alignment, pivot/unpivot, list/struct/str/dt namespaces), query plans (explain, predicate/projection pushdown, QueryOptFlags), performance rules (no map_elements, Enum/Categorical, streaming for larger-than-RAM), Arrow/NumPy/pandas/PyTorch interop, MCAP robotics logs into Polars (per-topic rates, gaps, latency), quick plots via gnuplot, the GPU engine (cudf-polars, version pin, fallbacks), pl.SQLContext, and the 1.x → 2.0 breaking changes and pitfalls (row order, null vs NaN, casts, sorted flags). Load before writing or reviewing Polars code or analysing tabular/log data in Python.
---

# Polars

Polars is a Rust dataframe engine on the Arrow memory format (**arrow** skill: buffers, Parquet, IPC, zero-copy).
Python only through **pixi** (`pixi add polars`). Robotics logs: **mcap**; plots: **gnuplot**; statistics on the
results: **stats-inference**; training data: **ml-data**. Reference library (proposed): `polars-guide-source`
(user guide + upgrade notes at `py-2.1.0`): `library_search query="join_asof tolerance" sources=["polars-guide-source"]`.
API reference: https://docs.pola.rs/api/python/stable/ (Rust: https://docs.rs/polars).

## 0. Versions (13 Nov 2026, verify)

- **Python Polars 2.1.0** (2026-10-25; 2.0.0 on 2026-10-06). conda-forge `polars` 2.1.0. Rust crate **`polars`
  0.55.2** (2026-08-06): the crate is versioned separately and lags the Python release.
- **cudf-polars-cu13 / -cu12 26.10.2** (PyPI; conda channel `rapidsai`) requires **`polars>=1.35,<1.45`**: the GPU
  engine does **not** work with Polars 2.x yet. Use a separate Pixi environment with `polars==1.44.2` (§9).
- Read the upgrade guide when porting: `docs/source/releases/upgrade/2.md` in the repo
  (https://docs.pola.rs/releases/upgrade/2/). Removed APIs raise `AttributeRemovedError`/`ArgumentRemovedError`
  with the replacement in the message.

## 1. Polars 2.0 changes that silently change results

- **Lazy `collect()` defaults to the streaming engine** (`engine="auto"` → streaming). The streaming engine does
  not keep row order for `group_by`, joins, `unpivot`, `unique`: sort explicitly, or use `maintain_order=True` /
  `join(..., maintain_order="left")`. Eager `DataFrame` methods still run in memory. Old behaviour:
  `collect(engine="in-memory")`, `pl.Config.set_engine_affinity("in-memory")` or `POLARS_ENGINE_AFFINITY=in-memory`.
- `pl.concat(how="horizontal")` requires equal heights (used to pad with nulls). `explode()` drops empty lists
  (`empty_as_null=False`). Signed int + `UInt64` → `Int128` (was Float64). Arrow/Parquet maps load as `pl.Map`
  (was `List(Struct)`). `pl.from_arrow(obj)` on a stream-only PyCapsule object returns a **Series of Struct**.
- Removed: `String → Date/Datetime` cast (`InvalidOperationError`; use `str.to_date()`/`str.to_datetime(fmt)`),
  `melt` (→ `unpivot`), `with_row_count` (→ `with_row_index`), `profile()`, `streaming=` (→ `engine=`),
  the individual optimization kwargs (→ `optimizations=pl.QueryOptFlags(...)`), `join_nulls` (→ `nulls_equal`),
  `read_ipc(memory_map=)`, `cut/qcut` deprecated (→ `bin_intervals`/`bin_quantiles`), the DataFrame interchange
  protocol (use the Arrow PyCapsule interface or `to_arrow()`). CSV auto names start at `column_0`.
- Categoricals: global, always lexically ordered; `pl.StringCache()` still works but warns
  "the string cache has been replaced by pl.Categories" — you don't need it any more.

## 2. Eager vs lazy

```python
import polars as pl
df = pl.read_parquet("log.parquet")                  # eager: everything in RAM, executes line by line
lf = pl.scan_parquet("logs/*.parquet")               # lazy: a plan; also scan_ipc, scan_csv, scan_ndjson,
                                                     # scan_delta, scan_iceberg, scan_pyarrow_dataset, scan_arrow_c_stream
q = (lf.filter(pl.col("quality") > 90)
       .group_by("topic").agg(pl.col("x").mean(), pl.len()))
print(q.explain())                                   # optimized plan: look for SELECTION and PROJECT n/m COLUMNS
q.collect()                                          # streaming by default in 2.x
pl.collect_all([q1, q2])                             # shared sub-plans run once
q.sink_parquet("out.parquet")                        # result never fully in RAM; also sink_ipc/csv/ndjson/batches
q.sink_parquet(pl.PartitionBy("out_dir", key="topic"))   # hive dirs topic=%2Fimu/… (URL-encoded)
for batch in q.collect_batches(): ...                # iterate DataFrames
```

- Write **lazy from the scan**: on 50M rows, `read_parquet → filter → group_by` took 0.217 s; the same query from
  `scan_parquet` took 0.044 s (projection + predicate pushdown read 3 of 6 columns and skipped rows early).
- `explain()` shows the optimized IR: `Parquet SCAN … PROJECT 3/4 COLUMNS, SELECTION: col("q") > 50` means both
  pushdowns happened. If a filter sits above a `map_batches`/UDF or a `with_columns` it depends on, it can't move.
  `explain(format="tree")`, `show_graph()` (physical streaming graph by default in 2.x, needs graphviz).
- Disable optimizations for debugging: `collect(optimizations=pl.QueryOptFlags(predicate_pushdown=False))`.
- A `LazyFrame` is a recipe: reusing it runs it again (and with streaming may return a different row order).
  Materialize (`collect()`) or use `collect_all`/`cache()` when several results share work.
- `scan_*` on many files: glob, list of paths, or a directory. Hive columns (`topic=…/`) are added
  automatically when you scan the **directory**, but **not** for a glob like `"dir/**/*.parquet"` (checked):
  pass `hive_partitioning=True` there. `include_file_paths="file"` adds the source path. Parquet statistics are used for row-group skipping
  (`use_statistics=True`).

## 3. Expressions (the whole API is these)

```python
df.select(pl.col("x", "y"), (pl.col("x") ** 2 + pl.col("y") ** 2).sqrt().alias("r"))
df.with_columns(                                      # all expressions in one context run in parallel
    grade=pl.when(pl.col("q") > 90).then(pl.lit("good")).when(pl.col("q") > 50).then(pl.lit("ok")).otherwise(pl.lit("bad")),
    x_c=pl.col("x") - pl.col("x").mean().over("topic"),               # window: per-group value broadcast back
    x_r=pl.col("x").rolling_mean(window_size=100).over("topic"),      # per-group rolling, row-based
)
df.group_by("topic").agg(pl.len(), pl.col("x", "y", "z").mean(), pl.col("quality").median(),
                         pl.col("x").filter(pl.col("q") > 50).max().alias("x_max_good"))
import polars.selectors as cs; df.select(cs.numeric(), cs.by_name("ts"))
```

- Namespaces: `.str` (`split`, `contains`, `extract`, `to_datetime`, `json_decode(dtype)`), `.dt`
  (`truncate("1s")`, `total_microseconds()`, `epoch("ns")`, `replace_time_zone`, `offset_by`), `.list` (`len`,
  `sum`, `get`, `eval(pl.element()*2)`, `explode`), `.arr` (fixed-size Array), `.struct` (`field`, `unnest`,
  `rename_fields`), `.cat`, `.map` (new Map dtype), `.bin`.
- `pivot(on="topic", index="ts", values="x")` (eager), `unpivot(index="ts")`; `df.unnest("payload", separator=".")`.
- Missing data: **null** (missing) ≠ **NaN** (a float value). `mean()` of `[1.0, null, NaN]` is NaN;
  `fill_nan(None)` turns NaN into null so null-aware aggregations skip it. `is_null` vs `is_nan`; `fill_null`
  (`strategy="forward"`), `interpolate()` (doesn't extrapolate: trailing nulls stay null).
- Casts are strict: `pl.Series(["1","x"]).cast(pl.Int64)` raises `InvalidOperationError`; `strict=False` gives
  null. Integer ↔ categorical casts are removed (`.cat.to(Enum)`, `.cat.physical()`).

## 4. Time series and sensor alignment (robotics)

```python
imu = df.filter(pl.col("topic") == "/imu").select("ts", ax="x", ay="y", az="z")         # 200 Hz
cam = df.filter(pl.col("topic") == "/camera/info").select("ts", "frame")                # 30 Hz
aligned = cam.join_asof(imu, on="ts", strategy="nearest", tolerance="1ms")   # also "backward" (default), "forward"
aligned = cam.join_asof(imu, on="ts", by="robot_id")                        # match within a key
per_s = df.group_by_dynamic("ts", every="1s", group_by="topic").agg(pl.len().alias("msgs"))  # needs sorted ts
win = imu.rolling("ts", period="10ms").agg(pl.col("ax").mean())             # time-based rolling window
up = df.upsample("ts", every="5ms").with_columns(pl.col("x").interpolate())  # resample to a fixed rate
```

- `join_asof` requires both `on` columns **sorted ascending**; unsorted input raises `InvalidOperationError:
  argument in operation 'asof_join' is not sorted`. Sort, or if you know it's sorted (e.g. read from a sorted
  Parquet file, where no sorted flag is set) `set_sorted("ts")`. `check_sortedness=False` skips the check
  silently — wrong results if the data isn't sorted.
- `tolerance` takes a duration string for temporal keys (`"1ms"`); without it, every row matches something.
- Datetimes default to µs from Python `datetime`; nanosecond timestamps from MCAP/ROS: `pl.from_epoch(col,
  time_unit="ns")` or cast an `Int64` to `pl.Datetime("ns")`. Keep both sides of a join in the same unit.
- Measured, 50M-row log (24 cores): `join_asof` of 4.0M camera rows against 20M IMU rows (nearest, 1 ms
  tolerance) **0.10 s**; `group_by_dynamic("1s", group_by="topic")` 1.1 s; `rolling_mean(100).over("topic")`
  1.1 s; `over()` mean-centering 0.58 s; sort by (topic, ts) 2.2 s.

## 5. Performance rules

1. **No Python per row**: `map_elements` is ~15–50× slower (1M rows: 65 ms vs 4 ms for `pl.col("x")*2+1`) and
   Polars warns `PolarsInefficientMapWarning` with the replacement expression. `map_batches` (whole Series → NumPy
   ufunc) is acceptable. For custom kernels write an expression plugin (Rust) instead of Python.
2. **Lazy from the scan**, filter and select early (they push down anyway, but UDFs block pushdown).
3. **Enum** for known label sets (`pl.Enum(["/imu", "/odom"])`, unknown values raise), **Categorical** for open
   sets: group_by on a Categorical topic 12 ms vs 29 ms on String (50M rows). Smaller ints/floats
   (`UInt8`, `Float32`) halve memory.
4. **Streaming for big data**: 300M rows / 30 Parquet files (7.9 GB zstd), filter + truncate + group_by (808
   groups): streaming **1.35 s, 3.1 GB peak RSS**; `collect(engine="in-memory")` 9.0 s, 40 GB; eager
   `read_parquet` + ops 9.5 s, 51 GB; `sink_parquet` 1.5 s, 3.4 GB; sorting all 300M rows by `x` into a sink
   5.8 s, 9.8 GB (out-of-core sort). Polars 1.44 streaming did the same query in 1.7 s but 12 GB.
5. Out-of-core (2.0+, on by default): spills when memory passes `POLARS_OOC_MEMORY_BUDGET_FRACTION` (0.8 of RAM)
   or `POLARS_OOC_MEMORY_BUDGET_MB`; disk cap `POLARS_OOC_DISK_BUDGET_MB` (64000); spill dir `POLARS_OOC_SPILL_DIR`
   (put it on fast local NVMe); `POLARS_OOMKILL_THRESHOLD_MB` aborts cleanly instead of being OOM-killed.
   (Names from `crates/polars-config/src/lib.rs` at py-2.1.0; check there for new ones.)
6. Threads: `pl.thread_pool_size()` (all cores); set `POLARS_MAX_THREADS` **before import** when sharing a
   machine or inside DataLoader workers (one Polars pool per worker otherwise oversubscribes).
7. Parquet out: `write_parquet(compression="zstd")` is fast (50M rows: 0.62 s, 1275 MB) because it doesn't
   dictionary-encode floats; `row_group_size=` and `statistics=True` (default) for later pushdown. Sort by the
   column you filter on before writing.

## 6. Interop (all zero-copy where the arrow skill says so)

- Arrow: `pl.from_arrow(table)`, `df.to_arrow()` (numeric buffers shared; strings export as `large_string`,
  `compat_level=pl.CompatLevel.newest()` → `string_view`), PyCapsule: `pl.DataFrame(any_arrow_obj)`,
  `pa.table(df)`. `pl.scan_pyarrow_dataset(ds)` for pyarrow datasets with filters pushed into them.
- NumPy: `df["x"].to_numpy()` is a view when there are no nulls; `df.to_numpy()` copies for mixed types.
- pandas: `df.to_pandas(use_pyarrow_extension_array=True)` (Arrow-backed, cheap), `pl.from_pandas(pdf)`.
- PyTorch: `df.select("x", "y").to_torch()` → 2D tensor (common supertype), `to_torch("dict")` keeps dtypes,
  `to_torch("dataset", label="y")` → `PolarsDataset` (a torch `TensorDataset` subclass). Polars → DLPack via `to_arrow()` for no-null columns.
- C/Odin/Rust producers: anything exporting the Arrow C Stream Interface → `pl.scan_arrow_c_stream` or
  `pl.from_arrow(pa.RecordBatchReader._import_from_c(ptr))` (arrow skill §7).

## 7. MCAP robotics logs → Polars (validated with mcap 1.6.0)

Decode once into plain Python lists or Arrow arrays, then build one frame — never append rows to a DataFrame:
```python
from mcap.reader import make_reader
cols = {"topic": [], "log_time": [], "publish_time": [], "payload": []}
with open("run.mcap", "rb") as f:
    for schema, channel, msg in make_reader(f).iter_messages(topics=["/imu", "/odom"]):
        cols["topic"].append(channel.topic); cols["log_time"].append(msg.log_time)
        cols["publish_time"].append(msg.publish_time); cols["payload"].append(msg.data.decode())  # JSON channels
df = pl.DataFrame(cols, schema_overrides={"log_time": pl.Datetime("ns"), "publish_time": pl.Datetime("ns"),
                                          "topic": pl.Categorical})
df = df.with_columns(pl.col("payload").str.json_decode(pl.Struct({"x": pl.Float64, "seq": pl.Int64}))).unnest("payload", separator=".")
stats = (df.lazy().sort("topic", "publish_time")
   .with_columns(dt_ms=pl.col("publish_time").diff().over("topic").dt.total_microseconds() / 1000,
                 lat_ms=(pl.col("log_time") - pl.col("publish_time")).dt.total_microseconds() / 1000)
   .group_by("topic").agg(n=pl.len(),
        rate_hz=(pl.len() - 1) / ((pl.col("publish_time").max() - pl.col("publish_time").min()).dt.total_nanoseconds() / 1e9),
        dt_max_ms=pl.col("dt_ms").max(), gaps=(pl.col("dt_ms") > 3 * pl.col("dt_ms").median()).sum(),
        lat_p50_ms=pl.col("lat_ms").median(), lat_p99_ms=pl.col("lat_ms").quantile(0.99))
   .sort("topic").collect())
```
On a generated 20 s log (imu 200 Hz, odom 50 Hz, camera 30 Hz with a 1 s dropout, gps 5 Hz) this reported 200.0 /
50.0 / 28.5 / 5.0 Hz, camera `dt_max` 1033 ms and 1 gap, latency p50/p99 per topic. For CDR (ROS 2) payloads
decode with `mcap-ros2-support` (`make_reader(f, decoder_factories=[DecoderFactory()])`, `iter_decoded_messages`)
and pick the fields you need into lists (**mcap** skill). Very large logs: write per-topic Parquet once, then
`scan_parquet`.

## 8. Quick plots

Polars has `df.plot` (Altair; without `altair>=5.4.0` it raises `ModuleUpgradeRequiredError`); for publication figures write whitespace-separated data and use
**gnuplot**: `df.select(t_s=(pl.col("ts").dt.epoch("ns") - t0) / 1e9, y=pl.col("x")).write_csv("x.dat",
separator=" ", include_header=False)` then `plot "x.dat" using 1:2 with lines`. Downsample first
(`group_by_dynamic` mean/min/max per window) instead of plotting 50M points.

## 9. GPU engine (cudf-polars)

```toml
# pixi.toml: separate environment, Polars pinned to what cudf-polars accepts
[workspace]
platforms = [{ name = "linux-64-cuda", platform = "linux-64", cuda = "13" }]
[feature.gpu.pypi-dependencies]
polars = "==1.44.2"
cudf-polars-cu13 = "==26.10.2"
[environments]
gpu = ["gpu"]
```
- `q.collect(engine="gpu")` or `engine=pl.GPUEngine(device=0, raise_on_fail=True)`; lazy API only; also
  `sink_*`. `engine="gpu"` **falls back to the CPU silently** (no warning seen) for unsupported plans;
  use `raise_on_fail=True` while developing to see `NotImplementedError: … unsupported operations`.
- Not supported (26.10): `Categorical` columns (`dtype=Categorical conversion not supported`; cast to String),
  `map_elements`/Python UDFs.
- Measured on an RTX 5090 that had only ~3.4 GB free (other processes held 29 GB), 10M rows, warm: filter +
  group_by CPU-streaming 0.029 s vs GPU 1.72 s; sort + head 0.052 vs 0.096 s; truncate + group_by 0.051 vs
  0.075 s; join 0.080 vs 0.163 s. Results matched CPU within float tolerance. 300M rows failed:
  `MemoryError: Try lowering target_partition_size … and/or RAPIDSMPF_SPILL_DEVICE_LIMIT`. On a free GPU and
  bigger scans the balance shifts; measure with your query (cold start includes CUDA init and file reads). The
  CPU streaming engine is a hard baseline to beat on a 24-core machine.

## 10. SQL and Rust

- `pl.SQLContext(log=lf).execute("SELECT topic, COUNT(*) AS n, AVG(x) FROM log WHERE q > 50 GROUP BY topic")`
  returns a LazyFrame (resolved at `collect()` in 2.x: syntax errors show up there); `df.sql("… FROM self")`;
  `pl.sql(query)` sees frames in scope. Exact numeric literals are `Decimal` in 2.x (`1.5e0` for float).
- Rust (`polars = { version = "0.55.2", features = ["lazy", "parquet", "temporal", "dtype-categorical"] }`):
  `LazyFrame::scan_parquet(PlRefPath::new("f.parquet"), Default::default())?.filter(col("t").gt(lit(5)))
  .group_by([(col("t") % lit(4)).alias("k")]).agg([col("x").mean(), col("x").null_count(), len()])
  .sort(["k"], Default::default()).collect()?` (validated with Rust 1.100 from Pixi `rust`; it read a file
  written by arrow-rs `ArrowWriter`; the path type is `PlRefPath`, not `&str`/`PathBuf`). Feature flags gate most
  functionality; the release build pulls ~1.4 GB of `target/`. arrow-rs and Polars use different Arrow crates;
  exchange via the C Data Interface or Parquet/IPC files. arrow-rs 60 renamed the row-group setter:
  `WriterProperties::builder().set_max_row_group_row_count(Some(n))` (or `set_max_row_group_bytes`).

## 11. Pitfalls checklist

- Row order after `group_by`/`join`/`unique` in lazy queries (streaming default): sort or `maintain_order`.
- Null vs NaN; `fill_nan(None)` before aggregations on floats that can be NaN.
- `String → Date` cast removed: `str.to_date(format)`. Mixed string/number arithmetic raises in 2.1.
- Asof joins: both sides sorted, same time unit, use `tolerance`, check `null_count()` of the joined columns.
- `group_by_dynamic`/`rolling` need sorted index columns (sort per group first when using `group_by=`).
- Building frames row by row (`vstack` in a loop, `pl.concat` of 1-row frames) is quadratic: collect lists first.
- `pl.read_csv` infers types from the first rows; pass `schema_overrides` or `infer_schema_length=None`.
- `to_numpy()` on a column with nulls copies and turns ints into floats.
- GPU env: never let the solver pick an old Polars silently — pin it (cudf-polars bounds the version).
