---
name: dora
description: Build robotics/AI dataflows with dora-rs 1.x — install (pip dora-rs-cli / release binary / cargo), dataflow YAML (nodes, inputs/outputs, timers dora/timer/millis|hz, queue_size/queue_policy, operators vs custom nodes, deploy.machine, restart policies, debug inspection), Python node API (dora.Node, event dicts, send_output with Arrow, send_output_raw zero-copy), Rust/C/C++ node APIs and prebuilt C libraries, zero-copy shared memory (pool size vs memlock, silent fallbacks, 64 MiB daemon limit), CLI lifecycle (run, up/start/list/logs/stop/down, validate, graph, doctor), record/replay (.drec), multi-daemon and multi-machine deployment over Zenoh (coordinator 6013, --machine-id, overlays, routers), reading dora traffic from plain Zenoh, ROS 2 bridge, node hub (dora-rerun, dora-yolo, opencv-video-capture), debugging, and when dora beats plain Zenoh. Load before writing or running a dora dataflow.
---

# dora-rs 1.x

dora runs a **dataflow**: a YAML graph of nodes (processes) that exchange **Apache Arrow** arrays. A coordinator and one
daemon per machine start the nodes. Data goes node → node over **Zenoh** (shared memory on one host). For raw Zenoh see
the **zenoh** skill, for ROS 2 the **zenoh-ros2** skill, for log files the **mcap** skill. Environments come from
**pixi**. The reference library holds the v1.1.0 sources as `dora-source` (`docs/*.md`, `apis/`, `examples/`,
`binaries/cli`) and `dora-hub-source`. Use `library_search` there for exact flags, YAML keys and signatures before
writing them.

## 0. Ground truth (checked 13 Nov 2026, verify)

| Item | State |
|---|---|
| dora | **v1.1.0** (7 Oct 2026). 1.0 (2026) was the "adora → dora" consolidation, a clean break from 0.3.x/0.4.x: env vars, YAML keys (`_unstable_deploy` → `deploy`), CLI. `docs/migration-from-0.x.md` lists the changes. Blog posts and older answers describe 0.3. |
| CLI | PyPI **`dora-rs-cli`** 1.1.0 (abi3 wheels: linux x86_64/aarch64/armv7, macOS arm64) gives a `dora` binary. Alternatives: the release tarball `dora-cli-<triple>.tar.gz` (one 96 MB binary), or `cargo install dora-cli --locked`. conda-forge `dora-rs` is stale (0.5.0, linux-64 only), so don't use it. |
| Python API | PyPI **`dora-rs`** 1.1.0, `from dora import Node`. CPython ≥ 3.11 (abi3), no free-threaded builds. Keep it at the **same version as the CLI**. |
| Rust | crate `dora-node-api = "=1.1.0"` (MSRV 1.95; Pixi `rust` 1.100 works). Arrow 59 internally, Zenoh **1.10.1** (features shared-memory, unstable, tcp, udp, unixsock; **no TLS/QUIC**). |
| C / C++ | Release assets `dora-c-libraries-<triple>.tar.gz` / `dora-cpp-libraries-<triple>.tar.gz` (x86_64-linux, aarch64-linux, aarch64-apple-darwin, windows). These contain headers, a static lib and a CMake config. |
| Not published | `dora-record-node`, `dora-replay-node` and `dora-ros2-bridge-node` are on neither crates.io nor PyPI, and not in the CLI tarball (see §6). |
| Hub | `dora-rs/dora-hub` v0.5.0. Nodes on PyPI: `dora-rerun`, `dora-yolo`, `opencv-video-capture` 0.5.0 (each depends on `dora-rs>=0.3.9`, so pin `dora-rs==1.1.0` yourself). |

Pixi setup (tested on linux-64, linux-aarch64 and osx-arm64):
```toml
[dependencies]
python = "3.12.*"
numpy = "*"
pyarrow = "*"
[pypi-dependencies]
dora-rs = "==1.1.0"
dora-rs-cli = "==1.1.0"
eclipse-zenoh = "==1.10.1"    # only if you also talk plain Zenoh; match dora's zenoh
```
Run everything inside `pixi run`. **Python pitfall (tested):** dora picks the node interpreter with `uv python find`,
then `python`, then `python3`. Outside the Pixi env, a system `uv` won, and the nodes failed with
`ModuleNotFoundError: No module named 'numpy'`. Start `dora run/up/record` from `pixi run …`. The daemon started by `dora up`
inherits that shell's environment (`DORA_NODE_SHM_POOL_SIZE` etc.).

## 1. Dataflow YAML (`docs/yaml-spec.md`, schema `dora-schema.json`)

```yaml
nodes:
  - id: producer                       # no '/' in ids
    path: producer.py                  # .py → run with Python; else executable; or git:/hub:/module:
    inputs:
      tick: dora/timer/millis/20       # built-in timers: dora/timer/millis/N, dora/timer/hz/N
    outputs: [data]
    env: { N_ELEM: "1000000" }
    shared_memory_pool_size: 32MB      # per-node SHM pool (else DORA_NODE_SHM_POOL_SIZE, default 8 MiB), see §5
  - id: rust_sink
    build: cargo build --release --manifest-path rust-sink/Cargo.toml   # run by `dora build` / `dora run`
    path: rust-sink/target/release/rust-sink
    inputs:
      data: { source: producer/data, queue_size: 4, queue_policy: drop_oldest }   # or backpressure
    outputs: [count]
    restart_policy: on-failure         # never|on-failure|always, max_restarts, restart_delay, health_check_timeout
```
- Inputs are `<node>/<output>`. Default queue: 10, `drop_oldest`. `backpressure` blocks the producer, but it **moves that
  output off the zero-copy path for every consumer** (daemon path, 64 MiB limit).
- Other keys: `input_timeout` (closes the input → `INPUT_CLOSED`), `exit_when_nodes_finish: true` (timers otherwise
  keep a graph alive forever), `send_stdout_as` / `send_logs_as`, `min_log_level`, `cpu_affinity: [0,1]`,
  `output_framing: {out: arrow-ipc}`, `output_types`/`input_types` (`std/media/v1/Image` …, checked by `dora validate`),
  `dora/logs` inputs (log aggregation), `debug: {enable_debug_inspection: true}` (needed for `dora topic echo/hz/info/pub`).
- **Operators** (`operator: {python: op.py}` or `operators:` with `shared-library:`) run inside one runtime process:
  fast to start and no IPC hop, but they share a process (and the GIL for Python). Use custom nodes for real work and for
  isolation.
- Reserved env names (dropped with a warning if set in `env:`): `DORA_NODE_CONFIG`, `ZENOH_CONFIG`, `DORA_ZENOH_*`,
  `LD_*`/`DYLD_*`. Set Zenoh config in the **daemon's** environment instead.

## 2. Python node

```python
import time, numpy as np, pyarrow as pa
from dora import Node
node = Node()                                  # identity from env set by the daemon
for ev in node:                                # or node.next(timeout=1.0), node.drain(), await node.recv_async()
    if ev["type"] == "INPUT":                  # also INPUT_CLOSED, STOP, ERROR
        arr = ev["value"]                      # pyarrow.Array; ev["id"], ev["metadata"] (dict)
        node.send_output("data", pa.array(np.arange(1_000_000, dtype=np.float64)),
                         {"t_ns": time.monotonic_ns()})       # metadata: bool/int/float/str/lists/datetime
    elif ev["type"] == "STOP":
        break
# zero-copy write (Python ≥ 3.11): fill dora's buffer directly
with node.send_output_raw("data", n_bytes, metadata={"seq": 1}) as buf:
    a = np.asarray(buf, dtype=np.uint8); a[:] = payload; del a   # release views before the block ends
```
`send_output` accepts `bytes` or a `pyarrow.Array`, nothing else. Receive with `ev["value"].to_numpy(zero_copy_only=False)`.
A raw send arrives as **uint8**: reinterpret it with `.view(np.float64)`. `node.log("info", "msg", {"k": "v"})`
writes structured logs.

## 3. Rust, C, C++ nodes (tested: Rust and C on Linux x86_64)

```rust
use dora_node_api::{DoraArray, DoraNode, Event, IntoArrow, MetadataParameters};
let (mut node, mut events) = DoraNode::init_from_env()?;
while let Some(ev) = events.recv() {
    match ev {
        Event::Input { id, metadata, data } => {
            let v: &[f64] = (&data).try_into()?;          // borrows the Arrow buffer (SHM-backed when zero-copy)
            node.send_output("count".into(), MetadataParameters::default(), (v.len() as u64).into_arrow())?;
        }
        Event::Stop(_) => break,
        _ => {}
    }
}
```
`DoraArray` hides Arrow: there is **no** `dora_node_api::arrow`. Enable feature `arrow-v59` for `dora_node_api::arrow_v59`
and `data.as_array()`, or `arrow-v58` for a converting hop. Scalars need exactly one element, and slices and `Vec`s
reject nulls.

C (`node_api.h`): `init_dora_context_from_env()`, `dora_next_event(ctx)`, `read_dora_event_type(ev)`
(`DoraEventType_Stop/Input/InputClosed/Error/Unknown`), `read_dora_input_id/_data(ev, &ptr, &len)`,
`dora_send_output(ctx, id, id_len, data, len)`, `dora_log`, then `free_dora_event` / `free_dora_context`. One thread per
context. Build with the prebuilt archive:
`cc node.c -I$L/include -L$L/lib -ldora_node_api_c -lm -lrt -ldl -pthread -o build/node` (macOS per the example
README: `-framework CoreServices -framework Security -l System -l resolv -l pthread -l c -l m`). The binary is about 83 MB (the whole Rust runtime is linked statically).
**Pitfall (tested):** `read_dora_input_data` only exposes **UInt8** arrays. A float64 input gives `NULL, 0` plus an
error log line, so send raw bytes (`send_output_raw` / `bytes`) to C nodes. In C++, `dora-node-api.h` + `src/*.cc` (cxx
bridge) must be compiled with your code. 1.1.0 added `DoraEventType::NodeRestarted`, so give every `switch` a `default`.
**Odin (tested, dev-2026-11a, Linux x86_64)**: the C API is plain C (opaque `rawptr`s, no blobs), so it binds directly:
```odin
foreign import dora {"libdora_node_api_c.a", "system:m", "system:rt", "system:dl", "system:pthread"}
Event_Type :: enum c.int { Stop, Input, InputClosed, Error, Unknown }
@(default_calling_convention = "c")
foreign dora {
	init_dora_context_from_env :: proc() -> rawptr ---
	dora_next_event      :: proc(ctx: rawptr) -> rawptr ---
	read_dora_event_type :: proc(ev: rawptr) -> Event_Type ---
	read_dora_input_data :: proc(ev: rawptr, out_ptr: ^[^]u8, out_len: ^c.size_t) ---
	dora_send_output     :: proc(ctx: rawptr, id: [^]u8, id_len: c.size_t, data: [^]u8, len: c.size_t) -> c.int ---
	free_dora_event      :: proc(ev: rawptr) ---
	free_dora_context    :: proc(ctx: rawptr) ---
}
```
Put the `.a` next to the package and run `odin build odin-sink -out:build/odin_sink -o:speed` inside `pixi run`. Result:
275/275 raw 800 KB inputs, with element 0 (the sequence number) read correctly through `(cast(^f64)data_p)^` (see
**odin**).

## 4. CLI (tested)

```sh
dora validate flow.yml                 # "Input/output wiring OK." … also --strict-types
dora graph flow.yml --mermaid          # or HTML (--open)
dora run flow.yml --stop-after 10s     # no coordinator: one-shot, builds `build:` steps; logs to stdout + out/<uuid>/
dora up                                # coordinator (ws 127.0.0.1:6013) + unnamed daemon, background
dora start flow.yml --name bench --detach   # or --attach
dora list                              # UUID Name Status Nodes CPU Memory
dora logs bench --node consumer --tail 20   # live dataflows; after it finished: dora logs <UUID> --node x --local
dora stop bench                        # --all, --grace-duration
dora down                              # "Coordinator and daemons destroyed successfully"
dora doctor                            # checks version, /dev/shm, uv, coordinator; NOT memlock
dora top | dora topic echo|hz|info|pub -d <df> producer/data   # topics need enable_debug_inspection
dora new my-node --lang python|rust|c|cxx --kind node
```
Logs are JSON lines in `out/<dataflow-uuid>/log_<node>.jsonl`. For named daemons they go to
`<cwd>/_work/<uuid>/out/…`. Use `--stop-after` ≥ 10 s for smoke tests: on a cold Mac start the Python nodes took
more than 5 s, and the run ended with `node producer exited before connecting to dora`.

## 5. Zero-copy shared memory: what really happens (tested)

- Nodes publish outputs ≥ 4 KiB (`DORA_ZERO_COPY_THRESHOLD`) directly to their consumers over Zenoh (key
  `dora/default/<dataflow-uuid>/output/<node>/<output>`, publisher `CongestionControl::Drop`, express, `RealTime`).
  Each node allocates them in **its own Zenoh SHM pool, 8 MiB by default** (`DORA_NODE_SHM_POOL_SIZE` in bytes, or
  per-node YAML `shared_memory_pool_size`). If allocation fails, the node **silently falls back to heap + copy** (debug
  log only).
- **Zenoh mlocks SHM segments** (see the **zenoh** skill): own pool + each peer pool mapped ≤ `ulimit -l`. On powerslabs
  (memlock 8 MiB) the default 8 MiB pool **never** used SHM. A 100k-f64 (800 KB) message had p50 **4.7 ms**; with
  `DORA_NODE_SHM_POOL_SIZE=2097152` it went through SHM (244/245) at p50 **0.59 ms**. A 4 MiB pool fell back again
  (2 × 4 MiB + overhead > 8 MiB). Jetson (memlock 8 GB): 8 MB messages with the default pool were SHM for only
  120/244 (p50 10 ms). A 32 MiB pool gave 264/266, p50 2.3 ms (`send_output`) and **1.3 ms** (`send_output_raw`). 30 MiB
  messages with a 256 MiB pool: 4.1 ms. Mac (memlock unlimited): 8 MB p50 7.4 ms with the default pool, 1.1 ms with 32 MiB.
- Size the pool to **≥ 4× the largest message** and raise memlock (`limits.conf` memlock, systemd `LimitMEMLOCK=`,
  Docker `--ulimit memlock=-1 --ipc=host`). Verify on the receiver once: on Linux the input buffer address lies in a
  `/dev/shm/<id>.zenoh` mapping of `/proc/self/maps` (Python: `ev["value"].buffers()[-1].address`).
- **Hard limit**: anything on the daemon path (cross-daemon, `backpressure`, replay, SHM fallback after the first
  message) is capped at **64 MiB**. An 8M-f64 (61 MiB + IPC framing) send crashed the producer with `IPC-encoded message is
  72000328 bytes, exceeding the 67108864-byte daemon transport limit`. Split large tensors, or keep them on the SHM path
  with a big enough pool.
- The first send of each output prints `WARN … (dora-rs/dora#2742 diagnostic)` lines. They are harmless. Zenoh's
  `error setting scheduling priority for thread` WARN is harmless too.

## 6. Record and replay (`.drec`, tested)

`dora record` injects a `__dora_record__` node (see it with `--output-yaml x.yml`) and needs the `dora-record-node`
binary. The pip CLI does not ship it (`could not find dora-record-node … cargo install dora-record-node`), and the crate
is not on crates.io. Build it from the tag (1m51s on 24 cores, Pixi `rust`):
```sh
CARGO_HOME=$PWD/.cargo cargo install --git https://github.com/dora-rs/dora --tag v1.1.0 --root $PWD/dora-tools \
  dora-record-node dora-replay-node
export PATH=$PWD/dora-tools/bin:$PATH
dora record flow.yml -o run.drec --topics producer/data      # Ctrl-C once finalizes (prints Bytes/File); --queue-size N
dora replay run.drec --speed 1                               # --speed 0 = max, --loop, --replace a,b, --output-yaml
```
Replay swaps the recorded source node for `dora-replay-node` and turns every input into `queue_policy:
backpressure`. That means no SHM, the 64 MiB limit applies, and it warns about both. Result: 362/362 messages at
`--speed 1`. At `--speed 0` the consumer saw only 180/362, because it broke out of its loop on `STOP` while
inputs were still queued. Drain (`node.drain()`) before you exit. Recording drops are reported per topic (`INCOMPLETE`).
For MCAP/ROS tooling, convert in a node: see **mcap**.

## 7. Multi-daemon and multi-machine (`docs/multi-machine.md`)

- CLI → coordinator WebSocket on TCP **6013**. Every daemon dials the coordinator. Data flows daemon ↔ daemon and
  node ↔ node over Zenoh TCP (ports chosen by the OS). Daemons find each other through the coordinator; multicast is optional.
- Coordinator machine: `dora coordinator --interface <LAN-IP>`, plus `dora daemon --coordinator-addr <IP> --machine-id
  workstation`. Other machines: `dora daemon --coordinator-addr <IP> --machine-id robot`. Nodes go to machines with
  `deploy: {machine: robot}` (`labels`, `working_dir`, `distribute: local|scp|http`). A node without `deploy` goes to
  the unnamed daemon (the one `dora up` starts). `dora up --interface 0.0.0.0` makes the daemon listen on loopback only.
- Flags: `--zenoh-listen IP[:PORT]`, `--zenoh-connect tcp/…` (both sides dial, multicast off), `--zenoh-no-multicast`,
  `--zenoh-config-overlay x.json5` / `DORA_ZENOH_CONFIG_OVERLAY` (endpoint lists are **appended**, other keys replace;
  `ZENOH_CONFIG` replaces everything and breaks node-to-node links, so don't use it), `--local-listen-port` for a second daemon
  on one host. NAT/isolated sites: put a `zenohd` 1.10 in between (`gateway.south` regions, or one router per site). Zenoh
  ≥ 1.9 peers don't relay, so in one region with no direct path **nothing arrives and no error is shown**.
- **Tested, two daemons on one host** (`--machine-id a` / `b`, second with `--local-listen-port 53292`): relative
  `path: producer.py` failed (`failed to resolve node source consumer.py … Could not find source path consumer.py within
  uv`), because named daemons run nodes from `<cwd>/_work/<uuid>/`. Use absolute paths or `deploy.working_dir`. After the fix
  592/592 messages arrived over the daemon path (`remote node(s) [producer] have no routable zenoh endpoint`) at p50 6.6 ms
  per 800 KB, versus 0.59 ms in SHM. Cross-machine wasn't tested here (powerslabs blocks inbound connections, and agx-01
  can't reach it). Check `RUST_LOG=dora_daemon=debug` for `resolved 1/1 remote node zenoh endpoints`.

## 8. Reading dora traffic from plain Zenoh (tested)

Every direct-path output is a normal Zenoh publication. Join the node sessions with an overlay (dora disables
multicast for nodes and listens on random loopback ports):
```sh
echo '{ connect: { endpoints: ["tcp/127.0.0.1:7450"] } }' > overlay.json5     # your process listens on 7450
DORA_ZENOH_CONFIG_OVERLAY=$PWD/overlay.json5 dora run flow.yml
```
```python
sub = s.declare_subscriber("dora/*/*/output/**", cb)      # key: dora/default/<uuid>/output/<node>/<output>
# payload = Arrow IPC *stream* (schema + one batch); empty payloads = startup route markers
rd = pa.ipc.open_stream(pa.py_buffer(smp.payload.to_bytes())); batch = rd.read_next_batch()
# later messages may be schema-less batches: pa.ipc.read_record_batch(buf, schema); attachment = postcard metadata (68 B)
```
Result: 219/219 decoded, all through SHM (`payload.as_shm()` was not None), plus 94 empty markers. The extra subscriber
raised the dora consumer's p50 from 0.59 to 1.3 ms. This is internal wire format (no stability promise), so pin the dora
version. To **inject** data into a dora graph from outside, use a dynamic node (`path: dynamic`,
`Node(node_id="…")`) with `dora up/start`, not raw Zenoh puts.

## 9. ROS 2 bridge and hub (from docs; not run here)

- A node with a `ros2:` key (`topic`/`message_type`/`direction`, `topics: […]`, `service`, `action`, `qos`) is turned
  into a `dora-ros2-bridge-node` process. It uses a pure-Rust DDS stack (`ros2-client`/`rustdds`) and never links rcl,
  and messages become Arrow `StructArray`s. That binary is not in the pip/tarball CLI: build it like §6. It speaks
  **DDS**, not rmw_zenoh. For a Zenoh-first ROS 2 stack (rmw_zenoh), subscribe to the ROS keys from a dora node with
  the Zenoh API instead (**zenoh-ros2**). Python also has `dora.Ros2Context` for imperative ROS 2.
- Hub nodes: `path: opencv-video-capture` (env `CAPTURE_PATH`, `IMAGE_WIDTH/HEIGHT`) → `dora-yolo` → `dora-rerun`
  (input metadata `primitive: image|boxes2d|…` since its v0.24 format). Install them with `pip install` in the env, or
  `hub: dora-yolo@^0.5` (**unstable**, resolved by `dora build`).

## 10. dora vs plain Zenoh (decision)

| Need | Plain Zenoh (**zenoh**) | dora |
|---|---|---|
| Large local messages | explicit `ZShmMut`: 1 MiB ~0.76 ms (Python) | 800 KB 0.59 ms, 8 MB 1.3 ms (raw), **if** pool and memlock are sized |
| Process orchestration, restart, logs, timers | you write it (systemd, launch files) | YAML graph, `restart_policy`, `dora logs/top`, built-in timers |
| Record/replay | **mcap** recorders, Zenoh storages | `.drec`, needs extra binaries, replay is copy-only |
| Types | bytes + your encoding | Arrow arrays (zero-copy into numpy/pyarrow/Rust slices) |
| Cross-network, security | routers, TLS/QUIC/mTLS, ACL | Zenoh tcp/udp only (no TLS in dora's build), coordinator WebSocket (`--auth` token) |
| Interop with non-dora apps | native | internal key layout/encoding (§8), no stability promise |
| Message size | up to 1 GiB defrag (BLOCK) | 64 MiB on the daemon path |

Use dora for a **single-team pipeline** (camera → model → control, Python ML + Rust drivers) where launch,
restart, logging, timers and Arrow zero-copy matter more than open interop. Use plain Zenoh (or rmw_zenoh) for a
system-wide bus, many independent apps, WAN/security, or when other tools must read the data. They mix well: a
dora node can open its own `zenoh` session (matching 1.10.x) to bridge selected outputs to stable keys.

## 11. Checklist

1. Same `dora-rs` and `dora-rs-cli` version. Run inside `pixi run` (uv/python discovery).
2. Large outputs: raise `DORA_NODE_SHM_POOL_SIZE` (≥ 4× message) **and** memlock, then check that buffers come from
   `/dev/shm/*.zenoh`. Fallbacks are silent.
3. No message on the daemon path above 64 MiB. `backpressure`, replay and cross-daemon inputs all use the daemon path.
4. Timers keep graphs alive: `exit_when_nodes_finish: true` or `dora stop`. Drain inputs before you exit on `STOP`.
5. C nodes read only UInt8 inputs. Named daemons need absolute paths or `deploy.working_dir`.
6. `dora record/replay` and the ROS 2 bridge need binaries built from the git tag.
