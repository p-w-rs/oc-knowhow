---
name: c-data
description: Fast data handling in C (and from Odin) with yyjson (read/write, in-situ parsing, JSON pointer, iteration, mutable documents, JSON5 flags, write_buf), xxHash (XXH3_64bits/XXH3_128bits, seeds, streaming state, XXH_INLINE_ALL), zstd (simple and advanced API, levels incl. negative, streaming with ZSTD_compressStream2, pledged size and checksums, multithreading with ZSTD_c_nbWorkers/jobSize, dictionaries with ZDICT_trainFromBuffer / zstd --train, frame format) and lz4 (LZ4_compress_default/fast, LZ4_compress_HC, lz4frame) — measured ratio and speed on real JSON and a binary sensor log (zstd levels vs lz4 vs lz4hc, SoA/delta/byte-shuffle preprocessing), yyjson GB/s, relation to MCAP chunk compression, conda-forge packages, and Odin (core:encoding/json, core:hash/xxhash, core:compress/lz4, vendor:compress/lz4, foreign import of zstd/xxhash/yyjson with a C shim). Load before parsing JSON, hashing, or compressing data in C or Odin.
---

# C data: yyjson, xxHash, zstd, lz4

## Ground truth first

- Versions as of Nov 2026 (verify with `git ls-remote --tags`): **yyjson 0.13.0** (2026-09-08), **xxHash v0.8.4**,
  **zstd v1.5.7** (Feb 2025, still the latest; ignore the odd `vxyz` and `zstd-0.x` tags), **lz4 v1.11.1** (1.11.0
  fixed a data-corruption bug in ring-buffer decoding and rare streaming cases; 1.11.1 fixed an out-of-bounds write in
  `LZ4_resetStreamHC` at levels ≥ 10 — don't stay on 1.10/1.11.0).
- conda-forge (`pixi add zstd lz4-c xxhash`, `pkg-config --cflags --libs libzstd liblz4 libxxhash`): zstd 1.5.7,
  lz4-c 1.11.1, xxhash **0.8.3** (one behind). `lz4` and `zstandard` on conda-forge are the Python bindings; there is no
  yyjson package (`r-yyjsonr` is R): vendor `src/yyjson.{c,h}` (two files). xxHash is header-only with
  `#define XXH_INLINE_ALL` before `#include "xxhash.h"` (no library to link, best speed for small inputs).
- Proposed library references: `yyjson-source` (`src/yyjson.h` doc comments, `doc/API.md`, `doc/DataStructure.md`,
  `CHANGELOG.md`), `xxhash-source` (`xxhash.h`, `README.md`, `doc/xxhash_spec.md`), `zstd-source` (`lib/zstd.h`,
  `lib/zdict.h`, `doc/zstd_compression_format.md`, `programs/zstd.1.md`, `README.md`), `lz4-source` (`lib/lz4.h`,
  `lib/lz4hc.h`, `lib/lz4frame.h`, `doc/lz4_Block_format.md`, `doc/lz4_Frame_format.md`). `library_search` them for exact
  signatures, flags and parameter ranges.

## yyjson (validated)

```c
#include "yyjson.h"                                   /* cc -O3 app.c yyjson.c */
yyjson_read_err err;
yyjson_doc *doc = yyjson_read_opts(buf, len, 0 /*flags*/, NULL /*alc*/, &err);   /* NULL on error: err.msg, err.pos */
yyjson_val *root = yyjson_doc_get_root(doc);
yyjson_val *v = yyjson_obj_get(root, "packages");     /* linear scan of keys; fine for small objects */
yyjson_val *lic = yyjson_ptr_get(root, "/packages/zstd/license");      /* RFC 6901 JSON pointer */
size_t i, n; yyjson_val *k, *x;
yyjson_obj_foreach(v, i, n, k, x) { if (yyjson_is_str(x)) use(yyjson_get_str(x)); }   /* also yyjson_arr_foreach */
char *out = yyjson_write_opts(doc, YYJSON_WRITE_PRETTY, NULL, &out_len, NULL); free(out);
size_t w = yyjson_write_buf(dst, cap, doc, 0, NULL);  /* 0.13: no allocation; returns 0 if cap too small */
yyjson_doc_free(doc);                                 /* frees every value at once (arena) */
yyjson_mut_doc *md = yyjson_mut_doc_new(NULL); yyjson_mut_val *o = yyjson_mut_obj(md); yyjson_mut_doc_set_root(md, o);
yyjson_mut_obj_add_str(md, o, "frame", "imu");        /* key/value NOT copied: must outlive md */
yyjson_mut_obj_add_strcpy(md, o, "id", tmp);          /* copied into md's pool */
yyjson_mut_obj_add_int(md, o, "seq", 42); yyjson_mut_val *a = yyjson_mut_obj_add_arr(md, o, "acc");
yyjson_mut_arr_add_real(md, a, 9.81); char *s = yyjson_mut_write(md, 0, NULL); yyjson_mut_doc_free(md);
```
- Flags: `YYJSON_READ_INSITU` (parses inside your buffer: it must stay alive, be writable and have
  `YYJSON_PADDING_SIZE` (4) zero bytes after the data), `YYJSON_READ_JSON5` (0.12+: comments, trailing commas,
  unquoted keys, single quotes, hex, Inf/NaN; individual `ALLOW_*` flags too), `YYJSON_READ_NUMBER_AS_RAW`,
  `BIGNUM_AS_RAW`, `STOP_WHEN_DONE` (concatenated/NDJSON); write: `PRETTY`, `PRETTY_TWO_SPACES`, `ESCAPE_UNICODE`,
  `NEWLINE_AT_END`, `ALLOW_INF_AND_NAN`. Strict read rejected a JSON5 sample; `YYJSON_READ_JSON5` read it (validated).
- Also: `yyjson_val_write` (one subtree), `yyjson_doc_mut_copy`, `yyjson_equals`, JSON Patch / Merge Patch,
  `yyjson_incr_read` (incremental), custom allocators (`yyjson_alc_pool_init` on a fixed buffer, `yyjson_alc_dyn_new`).
- Speed (23.8 MB conda-forge `channeldata.json`, 1.42 M values): parse **2.07 GB/s** Mac M2 Max / 1.35 GB/s
  Core Ultra 9 285K; INSITU +5–15%; minified write 3.8 / 4.4 GB/s; write → read roundtrip `yyjson_equals` true.
- Version notes: 0.13 changed `set_int()` to take `int64_t` and made read-only parameters `const`; 0.12 removed
  non-standard JSON from `yyjson_incr_read`. Most accessors are `static inline` (matters for FFI, below).

## xxHash (validated)

- `XXH3_64bits(p, n)`, `XXH3_64bits_withSeed(p, n, seed)`, `XXH3_128bits(p, n)` (`XXH128_hash_t {low64, high64}`;
  `XXH128_canonicalFromHash` for a byte-order-stable form), `XXH64(p, n, seed)`, `XXH32`. Streaming:
  `XXH3_state_t *st = XXH3_createState(); XXH3_64bits_reset(st)` (or `_reset_withSeed`), `XXH3_64bits_update(st, p, n)`…,
  `XXH3_64bits_digest(st)`, `XXH3_freeState`. Streaming with 64 KiB updates == one-shot; `XXH3_64bits("", 0)` =
  `2D06800538D394C2`.
- Not cryptographic: fine for checksums, dedup, hash tables, cache keys; use BLAKE2b/SHA-256 (c-crypto) when an
  attacker controls the input (hash flooding, forged content). Seeds don't make it secure.
- Speed (in cache): XXH3_64 **40 GB/s** Mac, 37 GB/s 285K (XXH3_128 the same, XXH64 15.6 / 23.5); 16-byte keys
  2.2 ns / 0.85 ns per hash. CLI: `xxhsum -H3 file` (from the conda-forge package).
- Benchmark pitfall seen: a pure hash of an unchanged buffer in a loop got hoisted (`XXH64 inf GB/s`); vary the seed and
  accumulate into a `volatile` sink.

## zstd (validated)

```c
#include <zstd.h>                                      /* -lzstd; zdict.h for dictionaries */
size_t cap = ZSTD_compressBound(n), c = ZSTD_compress(dst, cap, src, n, 3);     /* levels ZSTD_minCLevel()..22, default 3 */
if (ZSTD_isError(c)) puts(ZSTD_getErrorName(c));
unsigned long long sz = ZSTD_getFrameContentSize(dst, c);   /* ZSTD_CONTENTSIZE_UNKNOWN / _ERROR */
size_t d = ZSTD_decompress(out, sz, dst, c);           /* reuse ZSTD_CCtx/ZSTD_DCtx (…CCtx/…DCtx variants) in loops */
ZSTD_CCtx *cc = ZSTD_createCCtx();                     /* advanced API */
ZSTD_CCtx_setParameter(cc, ZSTD_c_compressionLevel, 3);
ZSTD_CCtx_setParameter(cc, ZSTD_c_checksumFlag, 1);    /* 32-bit content checksum at frame end */
ZSTD_CCtx_setParameter(cc, ZSTD_c_nbWorkers, 8);       /* returns an error if the lib was built without threads */
ZSTD_CCtx_setPledgedSrcSize(cc, total);                /* optional: puts content size in the streamed frame */
/* streaming: */ ZSTD_inBuffer in = {p, len, 0}; ZSTD_outBuffer ob = {dst, cap, 0};
size_t rem = ZSTD_compressStream2(cc, &ob, &in, last ? ZSTD_e_end : ZSTD_e_continue);   /* loop until in consumed; with e_end until rem == 0 */
ZSTD_decompressStream(dctx, &ob, &in);                 /* loop while in.pos < in.size */
```
- Measured (23.8 MB JSON, single thread, Mac; ratio · compress MB/s · decompress MB/s):

| codec | ratio | comp | dec | 285K comp/dec |
|---|---|---|---|---|
| zstd -5 (fast) | 3.73 | 959 | 2644 | 1148 / 3974 |
| zstd 1 | 5.37 | 766 | 2144 | 967 / 3266 |
| **zstd 3 (default)** | **5.93** | 503 | 2047 | 683 / 3163 |
| zstd 9 | 7.02 | 108 | 2275 | 149 / 3380 |
| zstd 19 | 8.09 | 3 | 2282 | 3 / 2229 |
| lz4 (block) | 3.82 | 959 | 5300 | 892 / 4694 |
| lz4hc 9 / 12 | 5.08 / 5.12 | 86 / 35 | 5964 | 70 / 4991 |
| lz4 frame, 4 MB blocks, checksum | 3.82 | 788 | 2589 | 666 / 2108 |

- Binary sensor log (200 k × 60 B IMU/encoder records, 12 MB, packed AoS): zstd 3 only **1.61×**, zstd 19 2.36×,
  lz4 1.20×. The same data as **struct-of-arrays + delta-coded integers + byte-shuffled floats** (all byte 0s of a column,
  then byte 1s…; reversible, like Blosc/Parquet filters): zstd 3 **4.27×** at 1.3 GB/s, lz4 3.39× at 3.4 GB/s, zstd 19
  4.71×. Preprocessing beats any level change for numeric logs.
- Multithreading: `nbWorkers=8` at level 3 on the 24 MB JSON: 1.48 GB/s (Mac) with the default job size, **3.5 GB/s**
  (Mac) / 2.0 GB/s (285K) with `ZSTD_c_jobSize` 1 MB (ratio 5.92 → 5.84). The default job is several MB, so small
  inputs get few jobs. Level 19 barely gained (3 → 6 MB/s): high levels use huge jobs; MT pays off on large streams.
  CLI: `zstd -T0` (all cores), `--long` for large-window dedup, `--ultra -20..-22`.
- **Dictionaries** for many small messages (the conda-forge per-package JSON objects, 616 B average): zstd 3 gives 1.75×,
  lz4 1.37×, **zstd 3 + a 110 KB dictionary 4.03×**. `ZDICT_trainFromBuffer(dict, 112640, samples, sizes, n)` (concatenated
  samples + size array; 28 k samples in 0.55 s), `ZSTD_createCDict(dict, sz, level)` + `ZSTD_compress_usingCDict`,
  `ZSTD_createDDict` + `ZSTD_decompress_usingDDict`. CLI: `zstd --train samples/* -o dict`, `zstd -D dict`. The frame
  stores the dict ID; decompressing without it fails with "Dictionary mismatch" (validated). Version the dictionary with
  your protocol and retrain when the data changes.
- Frame facts: magic `28 B5 2F FD`; frames concatenate (decoders read them in sequence); streaming without
  `setPledgedSrcSize` leaves the content size **unknown** in the header (validated), so decoders must stream or grow
  the buffer. With the checksum on, a flipped byte gave "Data corruption detected" (Mac) / "Restored data doesn't match
  checksum" (Linux) — either way an error, never silent garbage. Spec: `doc/zstd_compression_format.md`.

## lz4 (validated)

```c
#include <lz4.h>   /* -llz4; lz4hc.h, lz4frame.h in the same lib */
int c = LZ4_compress_default(src, dst, n, LZ4_compressBound(n));    /* ints: max input LZ4_MAX_INPUT_SIZE ≈ 2 GB */
int c2 = LZ4_compress_fast(src, dst, n, cap, 8);                    /* acceleration > 1: faster, worse */
int c3 = LZ4_compress_HC(src, dst, n, cap, 9);                      /* LZ4HC_CLEVEL_DEFAULT 9, MAX 12 */
int d = LZ4_decompress_safe(dst, out, c, out_cap);                  /* < 0 on malformed input; the block has NO size header */
LZ4F_preferences_t p = {0}; p.frameInfo.contentChecksumFlag = LZ4F_contentChecksumEnabled;
p.frameInfo.contentSize = n; p.frameInfo.blockSizeID = LZ4F_max4MB; p.compressionLevel = 0;   /* >= LZ4HC_CLEVEL_MIN (2) uses HC */
size_t fc = LZ4F_compressFrame(fdst, LZ4F_compressFrameBound(n, &p), src, n, &p);           /* LZ4F_isError(fc) */
LZ4F_dctx *dx; LZ4F_createDecompressionContext(&dx, LZ4F_VERSION);
size_t o = out_cap, i = fc; LZ4F_decompress(dx, out, &o, fdst, &i, NULL);   /* loop: returns hint of next src size, 0 = done */
```
- Block format = raw; store the original size yourself. Frame format (`.lz4` files, magic `04 22 4D 18`) adds sizes,
  optional checksums, linked/independent blocks; it is what MCAP's `lz4` chunk compression uses.
- When: lz4 decompresses 2–3× faster than zstd and compresses ~as fast as zstd at negative levels; zstd 1–3 gives a much
  better ratio for similar compress speed. lz4hc is for write-once/read-many (slow compress, fastest decompress).

## Choosing, and MCAP

- Default: **zstd 3** (or 1) for storage and network; **lz4** when decompression CPU is the bottleneck (many readers,
  Jetson playback) or for in-memory caches; **zstd 19 / lz4hc** only for archives written once; dictionaries for
  small-message streams (telemetry, RPC); preprocess numeric data (SoA, delta, shuffle) before any codec.
- MCAP chunks (see mcap) are compressed with `lz4` (frame) or `zstd`; the numbers above apply per chunk. Chunks
  are 1 MiB by default: big enough for full ratio (zstd uses no dictionary across chunks). Raw IMU/encoder CDR messages
  compress poorly (≈1.2–1.6× like the AoS log above); images should be compressed by an image codec, not the chunk.
- Checksums: zstd/lz4 frame checksums catch corruption, not tampering; authenticate with an AEAD/signature
  (c-crypto) if it matters. Compress before encrypting (ciphertext doesn't compress), and beware of compressing secrets
  together with attacker-controlled data (CRIME/BREACH-style length leaks).

## From Odin

- Odin core has **`core:encoding/json`** (parse, marshal/unmarshal, JSON5/SJSON specs), **`core:hash/xxhash`**
  (XXH32/64/XXH3, pure Odin), **`core:compress/lz4`** (clean-room block + frame, compress levels 1–12, dictionaries),
  `core:compress/zlib`/`gzip`/`deflate`/`shoco`, and **`vendor:compress/lz4`** (binds lz4 **1.10** block + HC API,
  `system:lz4`, buffers are `[^]u8`) and `vendor:zlib`. **No zstd or yyjson bindings**: use `foreign import`.
- Validated (dev-2026-11a, Mac and Linux):
  - `xxhash.XXH3_64(data)`, `XXH3_128(data)` (`u128` = `high64 << 64 | low64` of the C struct), seeded variants ==
    libxxhash; ~13–14 GB/s, same as the C library through FFI on this data. **Bug: core streaming XXH3
    (`XXH3_64_update`/`_digest`) gave wrong digests in 7 of 90 (length, chunk) combinations** (e.g. 10 000 bytes in one
    update, 65 537 bytes in 1000-byte chunks) on both arm64 and x86_64; the one-shot functions were always right. Use
    one-shot or libxxhash for streaming until fixed.
  - `lz4.compress_frame(&out, data)` (core) is read by liblz4 `LZ4F_decompress`, and `lz4.decompress_frame(&out,
    frame)` reads liblz4 frames with content checksums; ratio 3.79 vs 3.81, 679–790 MB/s (≈ liblz4 frame speed).
    `vendor:compress/lz4.compress_default(raw_data(src), raw_data(dst), n, cap)` → `core:compress/lz4.decompress_block`.
  - zstd: `foreign import zstd "system:zstd"` + `@(default_calling_convention="c", link_prefix="ZSTD_") foreign zstd {
    compress :: proc(dst: rawptr, cap: c.size_t, src: rawptr, size: c.size_t, level: c.int) -> c.size_t --- … }`
    (also `decompress`, `compressBound`, `getFrameContentSize`, `isError`, `getErrorName`); same ratio and speed as C.
  - yyjson: accessors are `static inline`, so compile a tiny C shim exporting what you need (`yy_read`, `yy_root`,
    `yy_ptr`, `yy_str`, …) into `libyyjson_shim.a` with `yyjson.c` and `foreign import yy "libyyjson_shim.a"`.
    1.68 GB/s vs `json.parse` 0.24 GB/s (Mac; 0.89 vs 0.14 on the 285K), and `json.destroy_value` alone took 59–79 ms:
    parse into an arena (`context.allocator = virtual.arena_allocator(&a)`, see odin-performance) and free it at once.
- Linking pitfall (macOS): Odin passes `-L/usr/local/lib -L/opt/local/lib` **before** `-extra-linker-flags`, so
  `system:lz4` picked MacPorts' 1.10.0 instead of the Pixi 1.11.1 (`otool -L` showed it). Check with `-print-linker-flags`
  and `otool -L`/`ldd`; link a full path (`foreign import lz4 "/path/liblz4.a"`) to be sure. On Linux the Pixi libraries
  were used (`-extra-linker-flags:"-L$CONDA_PREFIX/lib -Wl,-rpath,$CONDA_PREFIX/lib"`).

## Pitfalls

- yyjson: `yyjson_mut_obj_add_str` keeps your pointer (use `_strcpy` for temporaries); INSITU needs padding and a
  writable buffer that outlives the doc; `yyjson_get_str` on a non-string returns NULL; free docs, not values.
- zstd: check every return with `ZSTD_isError`; `ZSTD_decompress` needs the exact content size or a big enough buffer
  (else "Destination buffer is too small", validated) — for unknown sizes use streaming; reuse contexts (creating one per
  message costs more than compressing small messages); `nbWorkers` needs a threaded build (conda-forge's is).
- lz4: block decompression needs the size from somewhere else; never call `LZ4_decompress_fast` (deprecated since 1.9;
  not safe on untrusted input); `LZ4_compressBound` for the destination.
- Benchmarks: report best-of-N, the CPU, and the data; compression ratios depend entirely on the data (JSON 5.9× vs raw
  sensor data 1.6× at the same level). Use stats-inference for comparisons across runs.
