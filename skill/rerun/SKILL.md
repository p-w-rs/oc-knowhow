---
name: rerun
description: Log, view and query robot data with Rerun (rerun.io, SDK 0.43) — data model (entities and entity paths, archetypes vs components, timelines with set_time/send_columns, static data, named transform frames), logging Points3D, Boxes3D, Transform3D, Pinhole, Image/DepthImage/EncodedImage, Scalars/SeriesLines, LineStrips3D, TextLog, Tensor, blueprints from code (rerun.blueprint views and layout), sinks (save .rrd, spawn, connect_grpc, serve_grpc, web viewer), the rerun CLI (rrd print/stats/verify/optimize/merge/filter/compare, mcap info/check/convert), reading recordings back as Arrow/DataFusion/Polars dataframes (RrdReader, local catalog server + SQL), MCAP import (ROS 2 and Foxglove protobuf to archetypes, reflection of custom protobuf/ros2msg), a tested Zenoh→Rerun bridge, headless screenshots for agents, memory limits and micro-batching. Load before logging to, viewing or querying Rerun data.
---

# Rerun

Rerun records multimodal, time-indexed data (poses, point clouds, images, plots, logs) into a columnar store and
shows it in a native or web viewer; recordings are `.rrd` files you can also query as dataframes. The user's
stack is Zenoh-first: live data comes from **zenoh** (bridge in §8), files from **mcap** (§7); message formats are
in **robot-serialization**. Environments: **pixi**. Plots for papers: **gnuplot**. The reference library holds
`rerun-python-source` (the `rerun_py/rerun_sdk/rerun` package with type hints, `docs/content`, `docs/snippets/all`,
small `examples/python`) and the `rerun-docs` link: `library_search` there for exact signatures before writing code.

## 0. Versions (as of 13 Nov 2026, verify at https://github.com/rerun-io/rerun/releases)

- **0.43.2** (13 Nov 2026; 0.43.0 11 Nov, 0.42.0 4 Nov). Releases come every 1–2 weeks and the API moves:
  check `rr.__version__` and read the changelog (https://rerun.io/docs/changelog) before trusting older code.
  The SDK, viewer and `.rrd` must have the same minor version; `rerun rrd migrate` upgrades old files.
- Python: PyPI `rerun-sdk` (abi3 wheels, bundles the `rerun` CLI/viewer), conda-forge `rerun-sdk`. **conda-forge
  lagged on linux-64** (0.43.1 while osx-arm64 had 0.43.2): pin the version and use `pixi add --pypi
  "rerun-sdk[catalog]==0.43.2"` when they differ. Rust: crate `rerun` 0.43.2. C++: CMake `FetchContent` of
  `https://github.com/rerun-io/rerun/releases/latest/download/rerun_cpp_sdk.zip` (pin `/download/0.43.2/`), conda
  `librerun-sdk`, or vcpkg `rerun-sdk`. The CLI alone: release assets `rerun-cli-0.43.2-<target>`.
- **Querying needs DataFusion**, which is *not* a default dependency: `ModuleNotFoundError: No module named
  'datafusion'` from `store.reader()`. The `catalog` extra pins `datafusion==54.0.0`; with Pixi either `pixi add
  "datafusion==54.0.0"` (worked on osx-arm64) or the PyPI extra (conda-forge's 54.0.0 builds conflicted with
  Python 3.13 + libprotobuf 7 on linux-64).
- **`rr.dataframe.load_recording(...).view(...).select()` is gone** (pre-0.30 API in blog posts and model memory).
  Use `rerun.chunk.RrdReader` or `rr.server.Server` (§6).
- The SDK sends anonymous usage analytics by default: `rerun analytics disable` (once per machine) to opt out.

## 1. Data model

- **Entity path** `world/robot/camera` = a node in a tree; transforms and pinholes apply to the subtree. Escape
  arbitrary strings with `rr.escape_entity_path_part`.
- **Archetype** (`rr.Points3D`, `rr.Transform3D`, …) = a bundle of **components** (`positions`, `colors`, `radii`)
  the viewer knows how to draw. Logging an archetype writes its components; partial updates
  (`rr.Points3D.from_fields(colors=…)`) change only some. Query columns are named `/entity:Archetype:field`
  (e.g. `/telemetry/speed:Scalars:scalars`); every cell is a **list** (a batch).
- **Timelines**: every row gets the current time on each timeline set with `rr.set_time("frame", sequence=i)`,
  `rr.set_time("sim_time", duration=t)` (seconds or timedelta), `rr.set_time("robot_time", timestamp=ns_or_datetime64)`.
  `rr.log` also adds `log_time` (wall clock). **Time is thread-local per recording stream**: set it in the thread
  that logs. `rr.reset_time()`, `rr.disable_timeline(name)`.
- **Static data** (`rr.log(..., static=True)`): no time, latest wins, never garbage-collected — for calibration,
  meshes, coordinate conventions, styling. Static on many different paths grows memory without bound.
- **Columnar logging**: `rr.send_columns(path, indexes=[rr.TimeColumn("frame", sequence=arr)],
  columns=rr.Scalars.columns(scalars=values))` writes a whole series in one call (no `log_time` added).
- **Transforms**: `Transform3D` on an entity places its children; or named frames:
  `rr.Transform3D(translation=…, parent_frame="world", child_frame="base_link")` (TF style; the relationship is
  keyed by `child_frame`, logging another parent replaces it). Each entity has an implicit frame `tf#/<path>`.
  `rr.ViewCoordinates.RIGHT_HAND_Z_UP` (ROS convention) on the root, `RDF` for camera optical frames.

## 2. Logging a robot (tested: `robot.py`, 100 frames, 1.4 MB `.rrd`, 2 s)

```python
import numpy as np, rerun as rr, rerun.blueprint as rrb
rr.init("my_robot", recording_id="run-001")             # same recording_id from several processes = one recording
rr.save("robot.rrd", default_blueprint=blueprint)        # or rr.spawn(), rr.connect_grpc(url), rr.serve_grpc()
rr.log("world", rr.ViewCoordinates.RIGHT_HAND_Z_UP, static=True)
rr.log("world/robot/camera", rr.Pinhole(focal_length=100.0, width=160, height=120,
                                        camera_xyz=rr.ViewCoordinates.RDF), static=True)
rr.log("telemetry/speed", rr.SeriesLines(names="speed m/s", colors=[0, 160, 255]), static=True)
for i in range(N):
    rr.set_time("frame", sequence=i); rr.set_time("sim_time", duration=i * 0.1)
    rr.log("world/robot", rr.Transform3D(translation=[x, y, 0], rotation=rr.RotationAxisAngle(axis=[0, 0, 1], radians=yaw)))
    rr.log("world/robot/lidar", rr.Points3D(cloud_Nx3, radii=0.02, colors=[[255, 200, 0]]))
    rr.log("world/path", rr.LineStrips3D([path_xyz], colors=[[0, 200, 0]]))
    rr.log("world/robot/camera/rgb", rr.Image(rgb_hwc_uint8))              # under the pinhole: drawn in 2D and 3D
    rr.log("world/robot/camera/jpeg", rr.EncodedImage(contents=jpeg_bytes, media_type="image/jpeg"))
    rr.log("world/robot/camera/depth", rr.DepthImage(depth_f32, meter=1.0))
    rr.log("log", rr.TextLog("waypoint reached", level=rr.TextLogLevel.INFO))
    rr.log("debug/heatmap", rr.Tensor(arr, dim_names=["row", "col"]))
rr.log("world/obstacles", rr.Boxes3D(centers=[[3, 0, .5]], half_sizes=[[.5, .5, .5]], labels=["crate"]), static=True)
rr.send_columns("telemetry/speed", indexes=[rr.TimeColumn("frame", sequence=np.arange(N))],
                columns=rr.Scalars.columns(scalars=speed))
```
Other archetypes: `Arrows3D`, `Mesh3D`, `Asset3D` (glb/obj/stl), `Ellipsoids3D`, `Capsules3D`, `InstancePoses3D`,
`SegmentationImage`, `VideoStream`/`AssetVideo` (H.264/AV1: far smaller than per-frame images), `GeoPoints`,
`GridMap`, `TextDocument`, `BarChart`, `AnyValues` (arbitrary columns), URDF via `rr.log_file_from_path("robot.urdf")`.
Prefer `EncodedImage`/`VideoStream` over raw `Image` for cameras: raw RGB at 30 Hz fills RAM in minutes.

## 3. Blueprints (layout from code)

```python
blueprint = rrb.Blueprint(
    rrb.Horizontal(
        rrb.Spatial3DView(name="3D", origin="/world"),
        rrb.Vertical(rrb.Spatial2DView(name="camera", origin="/world/robot/camera"),
                     rrb.TimeSeriesView(name="speed / battery", origin="/telemetry"),
                     rrb.TextLogView(name="log", origin="/log")),
        column_shares=[3, 2]),
    rrb.TimePanel(state="collapsed"))
rr.send_blueprint(blueprint)          # or default_blueprint= on init/save/spawn/connect_grpc
```
Views: `Spatial3DView`, `Spatial2DView`, `TimeSeriesView`, `TextLogView`, `TensorView`, `DataframeView`,
`BarChartView`, `MapView`, `GraphView`, `TextDocumentView`, `StateTimelineView`; containers `Horizontal`,
`Vertical`, `Grid`, `Tabs`; `contents=["+ /world/**", "- /world/debug/**"]` filters entities. `rr.save(...,
default_blueprint=)` stores it in the `.rrd` (verified: the CLI screenshot showed exactly this layout). A
blueprint alone can be saved as `.rbl` (`blueprint.save("app_id", "layout.rbl")`) and opened next to data.

## 4. Sinks, viewers, ports

| Goal | Code / command |
|---|---|
| File | `rr.save("x.rrd")` or `rr.set_sinks(rr.FileSink("x.rrd"), rr.GrpcServerSink())` (several at once) |
| Local native viewer | `rr.spawn()` (port 9876; reuses a running viewer: its memory limit then stays) |
| Remote viewer | `rr.connect_grpc("rerun+http://host:9876/proxy")`; viewer side `rerun` (listens on 9876) |
| Serve from the robot | `uri = rr.serve_grpc()` (+ `rr.serve_web_viewer(connect_to=uri)`) ; viewers `rerun --connect <uri>` |
| Web viewer for a file | `rerun --web-viewer --web-viewer-port 9090 --port 9877 --bind 127.0.0.1 robot.rrd` → open `http://127.0.0.1:9090/?url=rerun%2Bhttp%3A%2F%2F127.0.0.1%3A9877%2Fproxy` |
| Native viewer for a file | `rerun robot.rrd` (also `.mcap`, images, meshes, URLs) |

The web viewer is a ~70 MB wasm download, uses WebGPU (`&renderer=webgl` URL parameter or `--renderer webgl` as
fallback) and is capped at 2.5 GB RAM. `--bind 0.0.0.0` (default) exposes the gRPC port to the LAN; firewalls
(powerslabs' drops inbound LAN ports) need an SSH tunnel: `ssh -L 9090:127.0.0.1:9090 -L 9877:127.0.0.1:9877 host`.
Flush before exit: `rr.disconnect()` or let the process end normally (the SDK flushes at exit; `kill -9` loses the
open batch). Micro-batching: `RERUN_FLUSH_TICK_SECS` (0.2 s for files, 8 ms for network sinks),
`RERUN_FLUSH_NUM_BYTES` (2 MiB).

## 5. CLI (0.43.2, tested)

```sh
rerun rrd verify robot.rrd            # "1 file verified without error."
rerun rrd stats robot.rrd             # chunks, rows, per-entity chunk counts (--no-decode: fast, transport level)
rerun rrd print robot.rrd [-v|-vv|-vvv]   # store info + one line per chunk with entity and columns
rerun rrd optimize robot.rrd -o opt.rrd   # compaction: 39 → 22 chunks, −4.9 % size here (--max-rows, --max-size)
rerun rrd merge a.rrd b.rrd -o all.rrd
rerun rrd filter robot.rrd --drop-entity /world/robot/camera/rgb --drop-timeline log_time -o small.rrd
rerun rrd compare a.rrd b.rrd         # strict: failed "Number of Chunks does not match: '27' vs. '22'" after optimize
rerun rrd split | route | migrate     # split on a timeline, rewrite stream metadata, upgrade old files
rerun mcap info|check|convert in.mcap # §7
rerun viewer-mcp                      # MCP server that drives a running viewer (agents)
```
`rrd` commands write to stdout without `-o`. `rerun --help` lists every viewer flag (`--memory-limit`,
`--server-memory-limit`, `--save`, `--port auto`/`--new`, `--threads`, `--hide-welcome-screen`).

## 6. Reading recordings back (tested)

```python
from rerun.chunk import RrdReader                       # no server; whole file in memory
store = RrdReader("robot.rrd").stream().collect()
df = store.reader(index="frame")                        # datafusion.DataFrame; index = any timeline, None = static only
sel = df.select("frame", "/telemetry/speed:Scalars:scalars", "/world/robot:Transform3D:translation")
pdf = pl.from_arrow(sel.to_arrow_table())               # polars; .to_pandas() also works
speed = pdf["/telemetry/speed:Scalars:scalars"].list.first()   # cells are lists
```
Results: 100 rows, the 1000-point cloud of frame 50 came back intact, values matched. Warm timings on an M2 Max:
`collect()` 11 ms, query + Arrow 34 ms; `import datafusion` 0.5 s; the **first** run on the Mac took 14.5 s (cold
imports/caches), 0.2 s on Linux.

Catalog server (many recordings, SQL, the same API as Rerun's hosted catalog):
```python
with rr.server.Server(host="127.0.0.1", datasets={"robot": ["robot.rrd"]}) as server:   # default host 0.0.0.0!
    client = server.client(); ds = client.get_dataset("robot")
    print(ds.info())                                    # segments, timelines with ranges, entity/column counts
    client.ctx.register_view("tele", ds.filter_contents("/telemetry/**").reader(index="sim_time"))
    q = client.ctx.sql('SELECT sim_time, "/telemetry/speed:Scalars:scalars"[1] AS speed FROM tele LIMIT 3')
    latest = ds.reader(index="frame", fill_latest_at=True)   # fill nulls with latest-at values, like the viewer
```
Quote column names in SQL; list indices start at 1. Each recording is a *segment* (`rerun_segment_id` column).
Printing a dataframe with image/video columns prints every byte: `select()` first. Rust: `rerun::dataframe::QueryEngine`.

## 7. MCAP import (tested with a 7-channel file from robot-serialization)

`rerun file.mcap` opens it directly; `rerun mcap convert in.mcap -o out.rrd` (0.03 s for 270 messages) writes an
`.rrd`. Options: `-d/--decoder` (attachments, foxglove, metadata, protobuf, raw, recording_info, ros2_reflection,
ros2msg, schema, stats, urdf), `-y/-n` topic regexes (RE2), `--start-time/--end-time`, `--recover` (no footer),
`--timestamp-offset-ns`, `--timeline-type duration`. Python: `rerun.chunk.McapReader(path).stream().write_rrd(out)`,
or `rr.log_file_from_path("x.mcap")`. `rerun mcap check` reports per-channel status (all `ok` here).

| Channel | Result in Rerun |
|---|---|
| `foxglove.FrameTransform` (protobuf) | `Transform3D` with `parent_frame`/`child_frame` |
| `foxglove.PointCloud` (protobuf) | `Points3D` + `InstancePoses3D` + `CoordinateFrame` |
| `foxglove.CompressedImage`, `foxglove.Log` | `EncodedImage`, `TextLog` |
| custom protobuf `robot.v1.RobotFrame` | reflected: column `/robot/frame_pb:robot.v1.RobotFrame:message` (Arrow struct mirroring the message) |
| custom `ros2msg` + `cdr` | reflected: `/robot/frame_cdr:robot_msgs.msg.RobotFrame:message` — **only if the schema text includes every dependency**, down to `builtin_interfaces/Time`; otherwise WARN `cannot be resolved by reflection` and raw bytes |
| `flatbuffer` (`.bfbs` schema) | **not decoded**: raw `McapMessage:data` |

ROS 2 standard types map to archetypes too (`sensor_msgs/Image`, `CompressedImage`, `CameraInfo`→`Pinhole`,
`PointCloud2`, `tf2_msgs/TFMessage`, `PoseStamped`, `NavSatFix`, `Imu`/`JointState`→`Scalars`, `rcl_interfaces/Log`,
`OccupancyGrid`). Timelines: `message_log_time`, `message_publish_time`, plus `ros2_timestamp` (header stamps) or
Foxglove `timestamp`. Docs: `docs/content/concepts/logging-and-ingestion/mcap/*.md`.

## 8. Zenoh → Rerun bridge (tested: 180/180 samples, 3 encodings, Mac and Linux)

```python
q = queue.Queue(maxsize=1000)
def on_sample(s):                                   # Zenoh thread: copy and return
    try: q.put_nowait((str(s.key_expr), str(s.encoding), s.payload.to_bytes()))
    except queue.Full: stats["dropped"] += 1
def worker():                                       # one thread owns the Rerun time cursor
    while (item := q.get()) is not None:
        key, enc, data = item
        frame = DECODERS[enc.split(";")[0]](data)   # application/protobuf | application/flatbuffers | application/cdr
        rr.set_time("robot_time", timestamp=np.datetime64(frame.stamp_ns, "ns"))
        rr.log("world/robot", rr.Transform3D(translation=…, quaternion=[qx, qy, qz, qw]))
        rr.log(f"world/robot/cloud_{key.rsplit('/', 1)[-1]}", rr.Points3D(frame.points))
rr.init("zenoh_bridge"); rr.set_sinks(rr.FileSink("live.rrd"), rr.GrpcServerSink())
sub = session.declare_subscriber("robot/**", on_sample)
```
Use the **message's** timestamp as the timeline (not receive time) so recordings from several robots line up;
`rr.set_time` is per thread, so set it in the worker. Map key expressions to entity paths 1:1. For rmw_zenoh
traffic decode CDR with `mcap_ros2`/`rclpy.serialization` (see **zenoh-ros2**). The full script is in
the validation folder (`zenoh_rerun_bridge.py`).

## 9. Headless use for agents (tested on macOS and on Linux without a display)

```sh
rerun --headless --window-size 1280x720 --screenshot-to shot.png --port auto robot.rrd   # renders and exits 0
```
```python
from rerun.experimental import ViewerClient
with ViewerClient.spawn(headless=True) as viewer:          # offscreen viewer + gRPC server
    rec = rr.RecordingStream("app", recording_id="run-001"); rec.connect_grpc(url=viewer.url)
    rec.log_file_from_path("robot.rrd"); view = rrb.Spatial3DView(origin="/world")
    rec.send_blueprint(rrb.Blueprint(view)); rec.flush(); time.sleep(3)
    viewer.save_screenshot("all.png"); viewer.save_screenshot("3d.png", view_id=view.id)
    rec.disconnect()
```
Pitfalls: `--screenshot-to` captures as soon as the first frames load (the time cursor was at frame 6 of 99):
use the Python client and wait, or a blueprint with a fixed time. On Linux run it with `env -u DISPLAY` when
an SSH X11 `DISPLAY` is set: with a forwarded display it printed `X11 connection rejected because of wrong
authentication`, still wrote the PNG, but never exited. Look at screenshots with the image reader instead of
guessing. `rerun viewer-mcp` lets an MCP client drive a live viewer.

## 10. Memory and performance

- Viewer limit: 75 % of RAM native, 2.5 GB web; `--memory-limit 16GB|50%` or `rr.spawn(memory_limit=…)`; oldest
  data is dropped first. Static data and the latest value of every component are never dropped. The gRPC server
  buffer (`--server-memory-limit`, default 1 GiB) is separate. `rr.spawn` reuses a viewer on 9876 and ignores your
  new limit: `--port auto`.
- Use `send_columns` for long series, `VideoStream` for cameras, downsample clouds before logging, `rrd optimize`
  files before sharing. One `rr.log` per message is fine at hundreds of Hz in Python; batch beyond that.
- Several processes → same `application_id` + `recording_id` and one gRPC server, or separate `.rrd` files merged
  later (`rrd merge`).

## 11. Checklist

1. Pin `rerun-sdk` and match viewer/SDK minor versions; add DataFusion if you query.
2. Static for constants, timelines for everything else; one thread sets time and logs (or pass explicit `TimeColumn`s).
3. Put the blueprint in the file (`default_blueprint=`) so screenshots and colleagues see the intended layout.
4. Verify outputs: `rerun rrd verify`, `rrd stats`, a dataframe query, a headless screenshot.
5. MCAP for interchange (Foxglove/ROS tools), `.rrd` for Rerun-native analysis; custom FlatBuffers are not
   visualized from MCAP: convert to Rerun archetypes in a bridge.
