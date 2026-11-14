---
name: mcap
description: Record, inspect, repair and read MCAP robotics log files — the format (spec v0 records, chunks with lz4/zstd, schemas and channels, message encodings cdr/ros2msg, protobuf, json, flatbuffer, ros1; summary and indexes, attachments, metadata, profiles), the mcap CLI (info, doctor, cat, list, filter, compress, merge, sort, recover, convert, du, add/get), ros2 bag record -s mcap with presets and writer options, Python mcap + mcap-ros2-support (writer, reader, decoding without ROS), the C++ header-only library and Rust crate, a tested Zenoh→MCAP recorder for rmw_zenoh traffic and existing recorders, Foxglove, performance tuning (chunk size, compression, indexes) and recovering truncated files. Load before writing or processing MCAP files.
---

# MCAP

MCAP is a self-describing container for timestamped multi-channel messages (any serialization), the default
rosbag2 storage since Iron and Foxglove's native format. Getting data from Zenoh/ROS 2 into it: **zenoh**,
**zenoh-ros2**. Environments: **pixi**. Analysis of recorded data: **stats-inference**, plots: **gnuplot**.
The reference library holds `mcap-source` (the spec and well-known encodings registry, Python and C++ APIs) and
`rosbag2-mcap-source` (writer options and presets): `library_search` there for record layouts and API signatures.

## 0. Versions (as of 13 Nov 2026, verify at https://github.com/foxglove/mcap/releases)

Each language has its own release tags in `foxglove/mcap`: CLI `releases/mcap-cli/v0.4.0` (16 Oct 2026),
Python `mcap` 1.6.0 and `mcap-ros2-support` 0.6.0 (PyPI; `mcap` also on conda-forge), C++ `releases/cpp/v2.2.0`
(21 Oct 2026; rosbag2 Lyrical's plugin reported `libmcap 2.1.3`), Rust crate `mcap` 0.26.0, Go `go/mcap/v1.10.0`,
TypeScript `@mcap/core` 2.4.0. Spec: https://mcap.dev/spec, registry of encodings and profiles:
https://mcap.dev/spec/registry. License MIT.

The CLI is a single binary (no conda package): download `mcap-linux-amd64` / `-arm64` / `mcap-macos-arm64` from the
CLI release and `chmod +x`. **v0.4.0 is a rewrite with new flags** (`mcap version` no longer exists, use `mcap --version`;
`cat --json` is deprecated for `--format=ndjson`); old blog posts show older flags: check `mcap <cmd> --help`.

## 1. The format in one screen

`<Magic><Header><Data section>[<Summary section>][<Summary Offset section>]<Footer><Magic>`, magic
`0x89 M C A P 0x30 \r \n` at both ends. Records are `opcode (u8) | length (u64) | content`.

- **Header** (`profile`, `library`) · **Schema** (id, `name`, `encoding`, `data`) · **Channel** (id, `topic`,
  `message_encoding`, schema id, metadata map) · **Message** (channel id, `sequence` u32, `log_time` and
  `publish_time` in ns, `data`) · **Chunk** (compressed batch of Schema/Channel/Message records; `compression`
  `""`, `lz4` or `zstd`; start/end time, CRC) · **Message Index** (per channel offsets inside a chunk) ·
  **Attachment** (named file with media type and times) · **Metadata** (name + string map) · **Data End** · **Footer**.
- **Summary section** (after the data): repeated Schema/Channel records, **Statistics** (counts, time range),
  **Chunk Index**, Attachment Index, Metadata Index; **Summary Offsets** point to each group. With it a reader seeks
  straight to the chunks it needs (time range, topics) and `mcap info` is instant. Without it (crashed writer,
  `noSummary`) readers must scan the whole file.
- Encodings (registry): message `cdr` (ROS 2, XCDR1/2 with the RTPS 4-byte header), `ros1`, `protobuf`, `flatbuffer`,
  `json`, `cbor`, `msgpack`, `capnproto`; schema `ros2msg` (`.msg` text with dependencies appended, each after a line of
  80 `=` and `MSG: pkg/Type`), `ros2idl`, `omgidl`, `ros1msg`, `protobuf` (a FileDescriptorSet), `flatbuffer` (`.bfbs`),
  `jsonschema`, or empty (schemaless). **Profile `ros2`**: channel `message_encoding` MUST be `cdr`, schema `ros2msg` or
  `ros2idl`, channel metadata `offered_qos_profiles` (YAML) required by the spec (rosbag2 writes it; Foxglove and the
  Python reader don't need it; `ros2 bag play` uses defaults when it is missing).

## 2. CLI (v0.4.0, tested)

```sh
mcap info rec.mcap          # library, profile, message count, duration, compression ratio, channels with Hz and schema
mcap doctor rec.mcap        # structural check; exit 1 + errors on problems, silent exit 0 when fine
mcap list channels|schemas|chunks|attachments|metadata rec.mcap
mcap cat rec.mcap --topics /chatter            # one line per message (raw bytes shown for cdr)
mcap cat rec.mcap --format=ndjson               # decoded only for ros1, protobuf, json; cdr errors out
mcap filter in.mcap -o out.mcap -y '/cmd_vel|/imu' -S 2026-11-13T22:01:23Z -E 2026-11-13T22:01:25Z --compression lz4
mcap filter in.mcap -o out.mcap -n '/camera/.*'  # exclude; --chunk-size, --no-chunks, --order log_time|topic|preserve
mcap compress|decompress|sort in.mcap -o out.mcap   # presets over filter
mcap merge a.mcap b.mcap -o all.mcap            # rosbag2 files: add --allow-duplicate-metadata (each has a 'rosbag2' record)
mcap recover broken.mcap -o fixed.mcap          # exit 3 if anything was lost
mcap convert in.db3 out.mcap                    # ROS 2 SQLite bag or ROS 1 .bag → MCAP
mcap du rec.mcap; mcap add attachment|metadata …; mcap get attachment|metadata …
```
Inputs can be `http(s)://`, `s3://`, `gs://`, `az://` (indexed reads; whole-file scans need `--allow-remote-scan`).
`--time-format rfc3339|seconds|nanoseconds` controls printed times.

### Recovery (tested on a 110-message file)

- Truncated at 2/3 of a chunked file: `doctor` → `MCAP file ended in the middle of a record`, `File does not contain a
  Footer record`, exit 1; `info` → `Bad magic number`; `recover` → **all 110 messages**, exit 0 (the data was in one
  complete chunk; index and summary rebuilt).
- Truncated mid-record in an unchunked file: `recover` → 12 messages, `Recovery was lossy: stopped early`, exit 3.
- So: data in complete chunks survives; the open chunk at a crash is lost. Smaller chunks lose less but compress worse.
  The Python reader also reads summary-less files sequentially (`make_reader` falls back to a stream reader).

## 3. ROS 2: `ros2 bag record -s mcap` (rosbag2 0.33 in Lyrical, tested)

```sh
ros2 bag record -s mcap --storage-preset-profile zstd_fast -o bags/run1 --topics /chatter /cmd_vel /imu
ros2 bag record -s mcap -a --storage-config-file mcap_writer_options.yml -d 300   # split every 300 s
ros2 bag info bags/run1/*.mcap ;  ros2 bag play bags/run1 --topics /cmd_vel
```
`-s mcap` is the default since Iron (`--storage {mcap,sqlite3}`, "defaults to 'mcap'"); write it anyway for older
distros and clarity. Output: a directory with `metadata.yaml` and `<n>_<name>_<timestamp>.mcap`. Presets: `none`, `fastwrite` (no CRCs, no
message index: lowest CPU, for small robots), `zstd_fast`, `zstd_small`. `--storage-config-file` YAML = `mcap::McapWriterOptions`
fields: `noChunking`, `noSummary`, `noMessageIndex`, `noChunkCRC`, `noSummaryCRC`, `enableDataCRC`, `chunkSize`,
`compression` (`None`, `Lz4`, `Zstd`), `compressionLevel` (`Fastest` … `Slowest`), `forceCompression`, `noSummaryOffsets`.
Other recorder options: `-e/--regex`, `--exclude-regex`, `--exclude-topics`, `--all-services`, `--all-actions`,
`-b/--max-bag-size` (bytes), `-d/--max-bag-duration` (s), `--max-cache-size`, `--snapshot-mode`, `--use-sim-time`,
`--compression-mode file|message` (rosbag2's own compression; with MCAP prefer the chunk compression above).
Works with any RMW (tested with `rmw_zenoh_cpp`). `ros2 bag info`/`play` also accept MCAP files written by other
tools if they use the `ros2` profile (tested with the Zenoh recorder below; `ROS Distro: unknown` is shown).

## 4. Python (`mcap` 1.6.0, `mcap-ros2-support` 0.6.0; tested)

```python
from mcap.reader import make_reader
from mcap_ros2.decoder import DecoderFactory          # pure Python CDR decoding from the ros2msg schema; no ROS needed

with open("rec.mcap", "rb") as f:
    reader = make_reader(f, decoder_factories=[DecoderFactory()])
    summary = reader.get_summary()                    # None for files without a summary
    for schema, channel, message, ros_msg in reader.iter_decoded_messages(topics=["/cmd_vel"]):
        print(channel.topic, message.log_time, ros_msg.linear.x)
    # reader.iter_messages(...) gives raw (schema, channel, message) for any encoding
    # start_time/end_time (ns), log_time_order, reverse are keyword arguments
```

Writing (generic API; any encoding):
```python
from mcap.writer import Writer, CompressionType
with open("out.mcap", "wb") as f:
    w = Writer(f, chunk_size=1 << 20, compression=CompressionType.ZSTD)   # also LZ4, NONE
    w.start(profile="ros2", library="my-recorder")
    sid = w.register_schema(name="geometry_msgs/msg/Twist", encoding="ros2msg", data=msgdef_text.encode())
    cid = w.register_channel(topic="/cmd_vel", message_encoding="cdr", schema_id=sid, metadata={})
    w.add_message(cid, log_time=t_ns, data=cdr_bytes, publish_time=t_ns, sequence=0)
    w.add_metadata("recording", {"robot": "bot1"}); w.add_attachment(...)
    w.finish()
```
`mcap_ros2.writer.Writer(output).register_msgdef(datatype, msgdef_text)` + `.write_message(topic, schema, message_dict_or_obj,
log_time=…)` serializes Python objects to CDR for you. Protobuf/JSON helpers: `mcap-protobuf-support`, plain JSON with
`encoding="jsonschema"` schemas.

## 5. Zenoh → MCAP

Existing tools (not run here; check maintenance before relying on them):
- `ZettaScaleLabs/rmw-zenoh-mcap-writer` (Rust, Apache-2.0, from the Zenoh authors): records rmw_zenoh topics into
  rosbag-compatible MCAP without ROS installed; controlled by Zenoh queries/REST on `@mcap/writer/start?domain=0;topic=…`,
  `@mcap/writer/stop`, `@mcap/writer/status`. No tagged releases as of Nov 2026 (build from source); uses a
  `ros2-types-registry` service for schemas.
- Domain-specific: EdgeFirst recorder, BlueOS recorder, keelson `mcap` connector (each for its own message types).

Tested recorder (`zenoh_to_mcap.py`, 80 lines): subscribe to `0/**` on the rmw_zenoh router; per new topic build the
`ros2msg` schema from `$CONDA_PREFIX/share/<pkg>/msg/<Type>.msg` (+ nested types), register channel with
`message_encoding="cdr"`; write the payload **as received** (CDR, no re-serialization), `log_time` = receive time,
`publish_time` and `sequence` from the rmw_zenoh attachment (`<qqB` + GID). Result: 110 messages on 4 topics
(`/imu`, `/cmd_vel`, `/rosout`, `/chatter`), zstd ratio 85 %, `mcap doctor` clean, decoded by `mcap_ros2`, and
`ros2 bag play` republished all 50 `/cmd_vel` messages. Key parts:

```python
def on_sample(s):                                     # key: 0/<topic>/<pkg>::msg::dds_::<T>_/RIHS01_<hash>
    parts = str(s.key_expr).split("/")
    if "::msg::" not in parts[-2]: return             # skip services
    topic = "/" + "/".join(parts[1:-2]); pkg, _, _, t = parts[-2].split("::"); t = t[:-1]
    seq, pub_ns, _ = struct.unpack_from("<qqB", s.attachment.to_bytes())
    with lock:                                        # Zenoh callbacks run on several threads
        if topic not in channels:
            sid = w.register_schema(name=f"{pkg}/msg/{t}", encoding="ros2msg", data=msgdef(pkg, t).encode())
            channels[topic] = w.register_channel(topic=topic, message_encoding="cdr", schema_id=sid,
                                                 metadata={"type_hash": parts[-1]})
        w.add_message(channels[topic], log_time=time.time_ns(), data=s.payload.to_bytes(),
                      publish_time=pub_ns, sequence=seq & 0xFFFFFFFF)
```
`msgdef()` concatenates the `.msg` file and each nested type (resolve `Header` → `std_msgs`, strip array suffixes and
bounds, skip primitives), every dependency once, separated by `"=" * 80 + "\nMSG: pkg/Type\n"`. For the DDS bridge,
keys are plain topic names and there is no attachment: take the type from the bridge admin space
(`@/*/ros2/route/topic/**` → `ros2_type`). For non-ROS Zenoh data pick a matching encoding (`json` + `jsonschema`,
`protobuf` + FileDescriptorSet) so Foxglove can decode it. Python is fine for tens of MB/s; for camera streams use
the Rust crate or C++ writer, and do the file I/O off the Zenoh callback thread (a queue).

## 6. C++ and Rust

- C++ (header-only, `#define MCAP_IMPLEMENTATION` in exactly one `.cpp`, `#include <mcap/writer.hpp>` /
  `<mcap/reader.hpp>`; needs lz4 and zstd unless `MCAP_COMPRESSION_NO_LZ4` / `MCAP_COMPRESSION_NO_ZSTD`; Conan or vcpkg
  `mcap`): `mcap::McapWriter w; w.open("out.mcap", mcap::McapWriterOptions("ros2"));` → `addSchema`, `addChannel`,
  `write(mcap::Message)`, `close()`. Reader: `mcap::McapReader r; r.open("in.mcap"); for (auto& m : r.readMessages()) …`.
  The `cpp/examples` folder at the tag has ROS 2 and protobuf examples. (Not compiled in this validation.)
- Rust: crate `mcap` (https://docs.rs/mcap/0.26.0/mcap/): `Writer`, `MessageStream` (iterate messages of a
  memory-mapped file, the documented pattern), `read::LinearReader`, `Summary`. (Not compiled here.)

## 7. Foxglove

Foxglove (app and web) opens MCAP directly, local or remote, and decodes `cdr`+`ros2msg`, protobuf, flatbuffers, JSON.
Use the `foxglove_msgs` / Foxglove schemas (`foxglove.CompressedImage`, `PointCloud`, `SceneUpdate`, `FrameTransform`, …)
for 3D/image panels with non-ROS data; ROS standard types (`sensor_msgs/Image`, `tf2_msgs/TFMessage`) also work.
Live data: `foxglove_bridge` (ROS 2) or the Foxglove SDK WebSocket server, not MCAP. Docs: https://foxglove.dev/docs.

## 8. Performance and layout

- Chunk size: 1 MiB default (Python, CLI) / 768 KiB in rosbag2's example; bigger = better compression and fewer index
  entries, more loss on crash and more memory per open chunk. Keep messages ≪ chunk size or a chunk holds one message.
- zstd for storage (≈4–7× on typical ROS telemetry here), lz4 when the recorder is CPU-bound (Jetson), none for
  already-compressed payloads (JPEG, H.264). Re-compress later with `mcap compress`/`filter --compression zstd`.
- Keep indexes and the summary (defaults) unless write throughput is the bottleneck; `fastwrite` drops message
  indexes and CRCs. Add the index later with `mcap filter`/`recover` (rewrites the file).
- Split long recordings (`-d`, `--max-bag-size`) so a crash loses one file's open chunk only.
- For reading one topic out of a huge file, `mcap filter --order topic` groups each channel contiguously.
- Message `log_time` must be monotonic per file for efficient time queries; `mcap sort` fixes out-of-order files
  (`doctor --strict-message-order` makes decreasing times an error).
