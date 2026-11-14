---
name: robot-serialization
description: Choose, define, evolve and ship robot message formats — FlatBuffers (flatc schemas, tables vs structs, builders, zero-copy reads, verifiers, evolution rules and flatc --conform; C via flatcc, C++, Python, Rust; .bfbs reflection), Protobuf (proto3/editions, protoc, well-known types, packed repeated fields, field-number and evolution rules, FileDescriptorSets, nanopb for MCUs with .options, buf lint/breaking), ROS 2 CDR (XCDR1 layout, ros2msg schemas), JSON; sending them over Zenoh (payload bytes + Encoding application/protobuf, application/cdr, custom application/flatbuffers with schema suffix, key conventions), recording them to MCAP so Foxglove and Rerun can decode them (protobuf + FileDescriptorSet, flatbuffer + .bfbs, cdr + ros2msg), a measured size/speed comparison on pose + 1000-point cloud, and calling flatcc from Odin. Load before designing a message schema, choosing a serialization format, or putting custom messages on Zenoh or into MCAP.
---

# Robot message serialization

How to get a typed message (header + pose + point cloud …) from one process, language or MCU to another, and into
log files that tools can open. Transport: **zenoh** (and **zenoh-ros2** for ROS graphs); files: **mcap**;
visualization and dataframes: **rerun**; C toolchains and Odin: **pixi**, **odin**, **c-networking**.
Reference library: `flatbuffers-source` (docs/source: schema, evolution, flatc, tutorial, internals; `include/`,
`python/`, `reflection/reflection.fbs`), `flatcc-source` (README, doc/, `include/flatcc`), `protobuf-docs-source`
(protobuf.dev sources: proto3, editions, encoding, best practices), `nanopb-source` (`pb*.h`, docs/),
`mcap-source` (MCAP well-known encodings registry + `python/mcap-protobuf-support`), `foxglove-schemas-source` (Foxglove message schemas in proto, fbs and ros2). `library_search` them for exact
rules and signatures.

## 0. Versions (as of 13 Nov 2026, verify)

| Tool | Version | Get it |
|---|---|---|
| FlatBuffers (`flatc`, C++ headers, Python, Rust crate) | **25.12.19** (also a 2026-02 re-tag `v25.12.19-2026-02-06-03fffb2`) | conda-forge `flatbuffers` (flatc + headers), `python-flatbuffers`; PyPI `flatbuffers`; crate `flatbuffers` |
| flatcc (C) | **0.6.4** (16 Sep 2026; 0.6.2/0.6.3 Jul 2026, after a 4-year gap) | not on conda-forge: build from the tag (§2) |
| Protobuf | **v36.2** (protoc 36.2 / Python 7.36.2, 17 Sep 2026); v37.0 in RC | conda-forge `libprotobuf` + `protobuf` (lagged at 7.35.1 / protoc 35.1); PyPI `protobuf` (upb backend) |
| nanopb | **0.4.9.3** (11 Nov 2026, security fixes for callbacks/oneofs/fixed arrays: upgrade) | PyPI `nanopb` = generator only; C runtime (`pb_encode.c`, …) from the git tag |
| buf | v1.75.0 (GitHub); conda-forge `buf` 1.66.0 | `pixi exec --spec buf buf …` |
| Foxglove schemas | `foxglove-schemas-protobuf` / `-flatbuffer` 0.4.0 (PyPI), SDK 0.31.0 | ready-made PointCloud, FrameTransform, CompressedImage, Log … |

## 1. Choosing

| | ROS 2 CDR | Protobuf | FlatBuffers | JSON |
|---|---|---|---|---|
| Schema | `.msg`/IDL, type hash | `.proto` | `.fbs` | none / JSON Schema |
| Read without parsing | no (but fixed layout: numpy views work) | no (parse to objects) | **yes, zero copy, random access** | no |
| Evolution | none on the wire (type hash changes) | good: numbered fields, unknown fields kept | good: append fields, ids, deprecate | ad hoc |
| MCU | micro-ROS | **nanopb** (static, no malloc) | flatcc (C, small runtime) | slow, big |
| Ecosystem | ROS 2, rmw_zenoh, rosbag2 | gRPC, Foxglove schemas, buf, every language | games, Arrow-ish tooling | everything |
| MCAP / Foxglove / Rerun | yes / yes / archetypes + reflection | yes / yes / archetypes (Foxglove types) + reflection | yes / yes / **raw only** | yes / yes / no |

Rules of thumb: talking to ROS → CDR (**zenoh-ros2**). Mixed-language services, MCUs, Foxglove-friendly logs →
Protobuf. Big arrays you read in place (clouds, maps, tensors), random access into large messages, or no parse
step on a weak CPU → FlatBuffers. JSON for config and debugging only. Put bulk arrays in **one bytes/vector
field**, never as repeated sub-messages per point.

## 2. Measured: one frame = header + pose (7 doubles) + 1000 xyz float32 + battery

Same message in each format (`robocodec.py`; Python 3.13, 200-rep best of 3; numbers in µs per message):

| Format | bytes | zstd-3 | enc / dec M2 Max | enc / dec x86_64 (powerslabs) | 10-point msg bytes |
|---|---|---|---|---|---|
| CDR via `mcap_ros2` dynamic (generic, pure Python) | 12092 | 11156 | 850 / 565 | 507 / 382 | 212 |
| CDR by hand (`struct` + numpy; byte-identical) | 12092 | 11156 | **1.8 / 0.8** | **1.2 / 0.6** | 212 |
| Protobuf (`repeated float points`, packed) | 12067 | 11158 | 72.7 / 3.4 | 36.6 / 2.4 | **186** |
| FlatBuffers (`[Vec3]` struct vector) | 12136 | 11202 | 21.9 / 7.0 | 17.6 / 5.3 | 256 |
| JSON (compact) | 61032 | 27385 | 1078 / 724 | 670 / 435 | 746 |

- For array-heavy messages all binary formats are the raw payload + <1 % overhead; size does not decide.
  Random float clouds don't compress (zstd ~8 %); JSON is 5× bigger and ~100× slower.
- In Python the cost is **per element conversion**: protobuf `points.extend(arr.tolist())` dominates encode; the
  upb decode is fast but `np.asarray(f.points)` copies element-wise. FlatBuffers and hand CDR decode to a numpy
  **view** of the receive buffer. To make protobuf fast, use a `bytes` field with raw little-endian floats (what
  `foxglove.PointCloud.data` does) — then it is a memcpy too.
- Small messages: protobuf is smallest (varints, absent fields cost 0), FlatBuffers carries vtables/offsets.
- C/C++ encoders of all three run at memory speed; choose on evolution, tooling and zero-copy, not on speed.

## 3. FlatBuffers

```fbs
namespace robot.fb;
struct Vec3 { x: float; y: float; z: float; }            // struct: fixed, inline, no evolution
struct Pose { x: double; y: double; z: double; qx: double; qy: double; qz: double; qw: double; }
table Header { stamp_ns: long; frame_id: string; seq: uint; }
table RobotFrame { header: Header; pose: Pose; points: [Vec3]; battery: float; }   // table: optional, evolvable
root_type RobotFrame;
file_identifier "RBFR";                                   // 4 bytes at offset 4: cheap type check
```
```sh
flatc --python --gen-object-api -o gen robot.fbs          # also --cpp, --rust, --ts, --go, --jsonschema …
flatc --binary --schema --bfbs-comments --bfbs-builtins -o gen robot.fbs   # robot.bfbs (reflection) for MCAP
flatc --conform robot_v1.fbs robot_v2.fbs                 # evolution check: exit 0 or "schemas don't conform"
```
- **Evolution** (docs/source/evolution.md): add new table fields **only at the end** (or give every field an
  `(id: n)`), never remove a field (mark `(deprecated)`), renames are free (names are not on the wire), structs can
  never change, and changing a default changes what old buffers read (defaults are not stored: the docs'
  "Changing Defaults" example). Tested: inserting a field before `pose` →
  `schemas don't conform: field renamed to different type … (renamed from …pose)`, exit 1; appending → exit 0.
- **Verify every buffer from the network** before reading (offsets in a hostile buffer point anywhere): C++
  `flatbuffers::Verifier` / `VerifyRobotFrameBuffer`, flatcc `robot_fb_RobotFrame_verify_as_root(buf, len)` (tested:
  truncated → `table header out of range or unaligned`, wrong id → `identifier mismatch`). Python has **no
  verifier**: wrap reads in try/except and bound-check, or verify in C first.
- Python: builders are back-to-front; create strings/vectors/sub-tables **before** `Start` of the table that holds
  them; structs are written inside `Start…End` (`AddPose(b, CreatePose(b, …))`). `CreateNumpyVector` handles scalar
  vectors only; for a struct vector copy raw bytes (`StartVector(12, n, 4)`, write `arr.tobytes()` at
  `b.head`, set `vectorNumElems`, `EndVector()`). Zero-copy read of it:
  `o = f._tab.Offset(8); np.frombuffer(buf, "<f4", count=3*f._tab.VectorLen(o), offset=f._tab.Vector(o))`.
  The Python package has no `reflection` module: generate it with `flatc --python reflection/reflection.fbs`.
- Alignment: the C/C++ verifiers check alignment relative to the buffer start, and C/C++ readers want the buffer
  itself aligned (8 bytes with doubles): `flatcc_builder_finalize_aligned_buffer`, and copy network payloads into
  aligned memory before reading in place.

### flatcc (C) — tested 0.6.4 on macOS arm64 and Linux x86_64
```sh
cmake -S flatcc-0.6.4 -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DFLATCC_TEST=OFF -DFLATCC_INSTALL=ON \
      -DCMAKE_INSTALL_PREFIX=$PWD/flatcc-install && cmake --build build && cmake --install build
flatcc-install/bin/flatcc -a --json -o gen_c robot.fbs     # robot_{reader,builder,verifier,json_parser,json_printer}.h
cc app.c -Igen_c -Iflatcc-install/include -Lflatcc-install/lib -lflatccrt
```
(flatcc also writes `bin/` and `lib/` into the **source** tree; use the install prefix.) API pattern:
```c
#define ns(x) FLATBUFFERS_WRAP_NAMESPACE(robot_fb, x)
flatcc_builder_t B; flatcc_builder_init(&B);              // reuse: flatcc_builder_reset(&B) per message
ns(RobotFrame_start_as_root(&B));
ns(RobotFrame_header_add(&B, ns(Header_create(&B, stamp, flatbuffers_string_create_str(&B, "base_link"), seq))));
ns(RobotFrame_pose_add(&B, &pose));                        // struct by pointer
ns(RobotFrame_points_add(&B, ns(Vec3_vec_create(&B, pts, n))));
ns(RobotFrame_end_as_root(&B));
void *buf = flatcc_builder_get_direct_buffer(&B, &size);   // no copy, valid until reset; or finalize_aligned_buffer + flatcc_builder_aligned_free
if (ns(RobotFrame_verify_as_root(buf, len)) == flatcc_verify_ok) {
    ns(RobotFrame_table_t) f = ns(RobotFrame_as_root(buf));
    ns(Vec3_vec_t) v = ns(RobotFrame_points(f)); size_t n = ns(Vec3_vec_len(v));   // v[i].x: zero copy
}
```

## 4. Protobuf

```proto
syntax = "proto3";                 // or edition = "2023"/"2024" (protobuf.dev/programming-guides/editions)
package robot.v1;                  // version in the package; buf expects the files under robot/v1/
import "google/protobuf/timestamp.proto";
message Header { google.protobuf.Timestamp stamp = 1; string frame_id = 2; uint32 seq = 3; }
message Pose { double x = 1; double y = 2; double z = 3; double qx = 4; double qy = 5; double qz = 6; double qw = 7; }
message RobotFrame { Header header = 1; Pose pose = 2; repeated float points = 3; float battery = 4; }
```
```sh
protoc -I schema -I $CONDA_PREFIX/include --python_out=gen --pyi_out=gen schema/robot.proto
protoc -I schema -I $CONDA_PREFIX/include --include_imports --descriptor_set_out=gen/robot.fds schema/robot.proto
```
- Evolution (proto3.md "Updating A Message Type"): never change or reuse a field number (`reserved 5;
  reserved "old";` after deleting), adding and removing fields is wire-safe, int32↔int64/uint and similar are
  only conditionally compatible (truncation), moving into an existing `oneof` is unsafe. Numbers 1–15 cost one tag
  byte (use them for frequent fields); 19000–19999 are reserved. proto3 scalars have no presence unless `optional`.
- Well-known types: `Timestamp`, `Duration`, `Any`, `Struct`, wrappers; ship them in the descriptor set
  (`--include_imports`).
- **buf** (tested 1.66.0): `buf lint` (STANDARD rules: package `robot.v1` must live in `robot/v1/`),
  `buf breaking --against ../previous` (detected `changed type from "float" to "double"`), `buf.yaml` `version: v2`.
- Untrusted input: set size limits before parsing in C/C++ and nanopb (bounded arrays, stream length).

### nanopb (MCU, static memory) — tested 0.4.9.3
```text
# robot.options
robot.v1.Header.frame_id max_size:32
robot.v1.RobotFrame.points max_count:3000
```
```sh
nanopb_generator -I schema -I $CONDA_PREFIX/include -D gen_nanopb -f schema/robot.options schema/robot.proto
nanopb_generator -I $CONDA_PREFIX/include -D gen_nanopb $CONDA_PREFIX/include/google/protobuf/timestamp.proto
cc app.c gen_nanopb/*.pb.c gen_nanopb/google/protobuf/timestamp.pb.c nanopb/pb_{encode,decode,common}.c -Inanopb -Igen_nanopb
```
Generated struct: `float points[3000]; pb_size_t points_count; bool has_pose;` (12 144 B) and
`robot_v1_RobotFrame_size` = 15 135 (worst-case encoded size: size the TX buffer with it). Encode
`pb_ostream_from_buffer` + `pb_encode(&os, robot_v1_RobotFrame_fields, &msg)`; decode `pb_istream_from_buffer` +
`pb_decode`. Results: nanopb 300 floats → 1247 B parsed by Python; Python 1000-point frame decoded by nanopb;
1001 points → `array overflow` (decode fails cleanly). Without `max_count` fields become callbacks
(`pb_callback_t`) — use those to stream big arrays without a buffer. Keep MCU→host messages under ~1.4 KB if they
cross zenoh-pico serial (see **zenoh** §7).

## 5. ROS 2 CDR without ROS

XCDR1 little endian: 4-byte encapsulation header `00 01 00 00`, then fields with natural alignment counted
**from after the header**; strings = u32 length incl. NUL + bytes + NUL; sequences = u32 count + elements. A
hand-written `struct.pack`/`np.frombuffer` codec for one type was byte-identical to `mcap_ros2` and ~400× faster
in Python. Schemas for MCAP/Foxglove/Rerun: `ros2msg` text with every dependency appended after a line of 80 `=`
and `MSG: pkg/Type` — **including `builtin_interfaces/Time`**, or Rerun's reflection gives up (mcap_ros2 tolerates
it). rmw_zenoh interop details: **zenoh-ros2**.

## 6. Over Zenoh (tested Python ↔ C, 1.10.2)

- Payload = the serialized bytes; describe them with the sample **Encoding**: `zenoh.Encoding.APPLICATION_PROTOBUF`,
  `APPLICATION_CDR`, `APPLICATION_JSON` exist; **there is no FlatBuffers constant** — use the string
  `zenoh.Encoding("application/flatbuffers")`. Add the type: `.with_schema("robot.v1.RobotFrame")` →
  `application/protobuf;robot.v1.RobotFrame` (C: `z_encoding_from_str(&e, "application/flatbuffers;robot.fb.RobotFrame")`
  or `z_encoding_set_schema_from_str`; `z_encoding_application_protobuf()`). Receivers dispatch on
  `str(sample.encoding).split(";")`. A `put` without encoding arrives as `zenoh/bytes`.
- Declare publishers with the encoding once (`declare_publisher(key, encoding=…)`, C `z_publisher_options_t.encoding`).
- Keys: one key per stream and type, e.g. `robot/<id>/frame/pb`; don't mix types on one key. Publish schemas
  next to the data so recorders can build MCAP channels: a queryable on `robot/<id>/frame/pb/@schema` (hermetic
  `@` chunk, not matched by `**`) returning the FileDescriptorSet / `.bfbs`, or a fixed schema registry key space.
- Results: C flatcc publisher → Python subscriber 50/50 (12 152 B frames, encoding preserved); Python → C 40/40
  verified; corrupt buffers rejected by the C verifier; protobuf/FlatBuffers/CDR all fed the Zenoh→Rerun bridge
  (**rerun** §8). Big payloads: SHM and congestion control in **zenoh** §5.

## 7. Into MCAP (Foxglove- and Rerun-readable; tested, `mcap doctor` clean)

| message_encoding | schema encoding | schema name | schema data |
|---|---|---|---|
| `protobuf` | `protobuf` | full name `robot.v1.RobotFrame` | `FileDescriptorSet` with all imports (`protoc --include_imports --descriptor_set_out`, or `mcap_protobuf.schema.build_file_descriptor_set(cls)`) |
| `flatbuffer` | `flatbuffer` | root table full name `robot.fb.RobotFrame` | `.bfbs` from `flatc -b --schema` (a `reflection.Schema`) |
| `cdr` | `ros2msg` | `pkg/msg/Type` | `.msg` text + dependencies |
| `json` | `jsonschema` | any | JSON Schema |

```python
from mcap.writer import Writer, CompressionType
from mcap_protobuf.schema import build_file_descriptor_set
w = Writer(f, compression=CompressionType.ZSTD); w.start(profile="", library="me")   # mixed encodings: no "ros2" profile
sid = w.register_schema(name=Cls.DESCRIPTOR.full_name, encoding="protobuf",
                        data=build_file_descriptor_set(Cls).SerializeToString())
ch = w.register_channel(topic="/robot/frame_pb", message_encoding="protobuf", schema_id=sid)
w.add_message(ch, log_time=t, publish_time=t, sequence=i, data=msg.SerializeToString())
```
`mcap_protobuf.writer.Writer(f).write_message(topic, msg, log_time=…)` does the registration for you. Checks run:
`mcap_protobuf.decoder.DecoderFactory` + `mcap_ros2.decoder.DecoderFactory` decoded every message (what
Foxglove does); `.bfbs` parsed with generated `reflection.Schema` and its root table name equals the schema name;
`mcap cat --format=ndjson` prints protobuf as JSON but fails on `flatbuffer` (`decoded output only supported for
ros1, protobuf, and json`). For Foxglove 3D/image panels use the Foxglove schemas (`foxglove.PointCloud` with
`PackedElementField` x/y/z FLOAT32 and `point_stride` 12, `foxglove.FrameTransform`, `foxglove.CompressedImage`):
Rerun also turns those into archetypes, while custom protobuf/ros2msg become queryable struct columns and
FlatBuffers stay raw bytes (**rerun** §7).

## 8. Odin (tested, dev-2026-11a)

flatcc's generated accessors are `static inline`, so bind a 40-line C shim (`rb_verify`, `rb_read` → a view
struct, `rb_build`, `rb_free`) built into `libfbshim.a`:
```odin
Vec3 :: struct { x, y, z: f32 }                         // == robot_fb_Vec3_t
foreign import fbshim {"libfbshim.a", "flatcc-install/lib/libflatccrt.a"}
@(default_calling_convention = "c")
foreign fbshim {
	rb_read  :: proc(buf: rawptr, len: c.size_t, out: ^Frame_View) -> c.int ---
	rb_verify_error :: proc(rc: c.int) -> cstring ---
}
pts := v.points[:v.n_points]                            // [^]Vec3 into the original buffer
```
Reading verified buffers needs no C at all: root = `u32` at 0; vtable = table − `i32` at table; field slot k at
`u16` vtable[4 + 2k] (0 = absent); vector = `u32` count + elements → `([^]Vec3)(&b[vec + 4])[:n]` gave the same
memory as the shim. Results: Odin read a Python-built frame (values match), built a 204-byte frame that Python
decoded, and the shim rejected a truncated buffer. nanopb should bind the same way (plain C structs and
non-inline functions, so no shim needed), but that was not tested.

## 9. Checklist

1. Write the schema first, version the package (`robot.v1`, `namespace robot.fb`), commit generated code or generate in CI.
2. Bulk data as one contiguous array; timestamps as int64 ns (or `Timestamp`); frame ids as strings.
3. Gate schema changes: `buf breaking` / `flatc --conform` in CI.
4. Verify untrusted FlatBuffers; bound nanopb arrays with `.options`; never trust lengths from the wire.
5. On Zenoh: set the encoding with the type name, one type per key, serve schemas; in MCAP: the right
   schema encoding + full schema data, then `mcap doctor` and a decode with the reference decoders.
