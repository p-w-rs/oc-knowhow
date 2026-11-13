---
name: zenoh
description: Build distributed robotics/IoT systems with Eclipse Zenoh 1.x — key expressions and wildcards (*, **, $*), selectors and parameters, sessions, publishers/subscribers, queryables/get/querier, liveliness tokens, matching listeners, attachments, encodings, QoS (priority, congestion control, express, reliability), peer/client/router modes, scouting (multicast, gossip), zenohd router JSON5 config, TLS/QUIC/mTLS, user/password and ACL, REST plugin, storage manager and storages, HLC timestamps, admin space, APIs in Python, Rust, C (zenoh-c), C++ (zenoh-cpp), zenoh-pico for microcontrollers (serial, UDP, TCP), shared memory, throughput/latency tools, calling zenoh-c from Odin, and 0.11→1.x migration. Load before writing or deploying anything that uses Zenoh.
---

# Zenoh 1.x

Zenoh is a pub/sub + query protocol with routing: data goes to **key expressions**, not to topics or brokers.
For ROS 2 interop see the **zenoh-ros2** skill, for recording to files see **mcap**. Environments come from
**pixi**; for Odin bindings also load **odin**; sockets, firewalls and tunnels are in **c-networking**.

## 0. Ground truth first (as of Nov 2026, verify)

| Item | State (checked 13 Nov 2026) |
|---|---|
| zenoh, zenoh-c, zenoh-cpp, zenoh-pico, zenoh-python, zenoh-plugin-ros2dds | **1.10.2** (28 Oct 2026); 1.10.0 Aug 2026, 1.9.0 Apr 2026. All repos are released together with the same version. Mix only matching versions (the wire protocol is compatible within 1.x, but plugins (`.so`) must match `zenohd` **exactly**). |
| Python | PyPI **`eclipse-zenoh`** (`import zenoh`), abi3 wheels for x86_64/aarch64/macOS. Not on conda-forge: `pixi add --pypi eclipse-zenoh`. |
| conda-forge | `zenohd`, `zenoh` (= zenohd + `zenoh-plugin-rest` + `zenoh-plugin-storage-manager`), `libzenohc` (C), `libzenohcxx` (C++), `zenoh-pico`, `zenoh-plugin-webserver`. They can lag a patch release (a RoboStack ROS env pinned `libzenohc` to 1.10.1). |
| Rust | crate `zenoh = "1.10"` (docs: https://docs.rs/zenoh/1.10.2/zenoh/). |
| Docs | https://zenoh.io/docs/ · Python https://zenoh-python.readthedocs.io/en/1.10.2/ · C https://zenoh-c.readthedocs.io/en/1.10.2/ · C++ https://zenoh-cpp.readthedocs.io/en/1.10.2/ · pico https://zenoh-pico.readthedocs.io/en/1.10.2/ |
| Config reference | `DEFAULT_CONFIG.json5` at the tag: https://github.com/eclipse-zenoh/zenoh/blob/1.10.2/DEFAULT_CONFIG.json5 (the only complete list of keys; commented = default). |
| Examples (best API reference) | `zenoh/examples/examples/*.rs`, `zenoh-python/examples/*.py`, `zenoh-c/examples/*.c`, `zenoh-pico/examples/unix/c11/*.c` at the tag. |

The Python API has typed stubs: `$(python -c "import zenoh,os;print(os.path.dirname(zenoh.__file__))")/__init__.pyi`
lists every keyword argument. Read it (or the C header `zenoh_commons.h`) instead of guessing names.

**Zenoh 1.0 (Oct 2024) broke the 0.11 API in every binding**, and 1.x and 0.11 nodes do **not** interoperate on the
wire. Signs of pre-1.0 code (blog posts, older answers, your memory): Rust `.res()` / `.res_sync()` / `.res_async()`
(1.x: `.await` or `.wait()` with `zenoh::Wait`), Python `zenoh.Value`, subscriber `reliability=` options, C code without
the owned/loaned/moved pattern (`z_loan`, `z_move`, `z_drop`, `z_view_*`). Port it with the 1.x examples; don't copy it.
For ROS 2 use `zenoh-plugin-ros2dds`, not the generic DDS bridge `zenoh-plugin-dds` (see **zenoh-ros2**).

## 1. Concepts

- **Key expression**: `/`-separated chunks, no leading or trailing `/`, no empty chunks. `*` = exactly one chunk,
  `**` = zero or more chunks, `$*` = any substring inside a chunk (`robot/r$*/temp` matches `robot/r12/temp`).
  Chunks starting with `@` are **hermetic**: `*`/`**` never match them (admin space `@/…`, rmw_zenoh `@ros2_lv/…`).
- **Selector** = key expression + `?` + parameters `k=v;k2=v2` (used by `get`). The queryable reads them
  (`query.parameters.get("unit")`, `z_query_parameters`). Reserved: `_time=[..]` for storages with time-series backends.
- **Session**: one per process; it is a peer, client or router (below). Everything (publisher, subscriber,
  queryable, token) is declared on it and dropped with it.
- **Publisher / Subscriber**: `put` and `delete` samples (`SampleKind.PUT` / `DELETE`). `session.put(key, value)` is
  fine for occasional messages; for a stream declare a publisher once (key declared once, QoS fixed, matching status).
- **Queryable / get**: request/response. A `get` goes to every matching queryable (and storage) and returns a stream
  of replies, ended by timeout or when all answered. Options: `target` (`BEST_MATCHING`, `ALL`, `ALL_COMPLETE`),
  `consolidation` (`AUTO`, `NONE`, `MONOTONIC`, `LATEST`), `timeout`, `payload`, `attachment`. A queryable declared
  `complete=True` claims to answer for the whole key expression. A **Querier** (`declare_querier`) is the
  publisher-style object for repeated gets. Reply with the concrete key (`query.reply("demo/x", …)`), not the query's
  wildcard key.
- **Liveliness**: `session.liveliness().declare_token(key)`; others see it with `liveliness().get(key)` (current
  tokens) or `liveliness().declare_subscriber(key, history=True)` (PUT on appear, DELETE on disappear, including
  crashed or disconnected sessions). Use it for presence/discovery (rmw_zenoh builds the ROS graph from it).
- **Matching listener**: `publisher.declare_matching_listener(cb)` / `publisher.matching_status.matching` — whether any
  subscriber matches; skip expensive work (encoding a camera frame) when nobody listens. Queriers have it too.
- **Attachment**: extra bytes next to the payload (metadata, sequence numbers, ROS GIDs). **Encoding**: a MIME-like
  label (`zenoh.Encoding.TEXT_PLAIN`, `APPLICATION_CDR`, `APPLICATION_PROTOBUF`, `ZENOH_BYTES` default); it is not
  enforced, just carried. **Payload** is `ZBytes` (`.to_bytes()`, `.to_string()`; Python `zenoh.ext` has typed
  `z_serialize`/`z_deserialize` compatible with Rust/C/C++).
- **QoS** per publisher/put: `priority` (`REAL_TIME` 1 … `DATA` 5 default … `BACKGROUND` 7; separate queues per
  priority on links with QoS), `congestion_control` (`DROP` default for put, `BLOCK`, `BLOCK_FIRST`), `express=True`
  (bypass batching: lower latency, lower throughput), `reliability` (`RELIABLE`/`BEST_EFFORT`; best effort uses UDP
  only if such a link exists). Routers can override per key: config `qos/publication` (keys, `congestion_control`,
  `priority`, `express`, `reliability`, `allowed_destination`) and `qos/network`.
- **Timestamps**: routers add an HLC timestamp (hybrid logical clock; time + ZID) to data that has none
  (`timestamping/enabled`, default router only; `zenohd --no-timestamp` disables). Storages need timestamps to order
  and replicate. `session.new_timestamp()` stamps your own.
- **Advanced pub/sub** (Python `zenoh.ext.declare_advanced_publisher/subscriber` with `CacheConfig`, `HistoryConfig`,
  `RecoveryConfig`, `MissDetectionConfig`; `zenoh-ext` crate; C `ze_declare_advanced_publisher/subscriber`):
  publication cache, history for late joiners, sample-miss detection, recovery. rmw_zenoh uses it for TRANSIENT_LOCAL.

## 2. Python (tested: eclipse-zenoh 1.10.2, Python 3.13/3.14)

```python
import json, time, zenoh

conf = zenoh.Config()                                          # or zenoh.Config.from_file("x.json5")
conf.insert_json5("mode", json.dumps("client"))                # values are JSON5 strings
conf.insert_json5("connect/endpoints", json.dumps(["tcp/127.0.0.1:7447"]))
zenoh.init_log_from_env_or("error")                            # RUST_LOG-style filters

with zenoh.open(conf) as s:
    got = []
    sub = s.declare_subscriber("demo/sensor/*/temp", lambda smp: got.append(
        (str(smp.key_expr), smp.payload.to_string(), smp.attachment and smp.attachment.to_string())))
    pub = s.declare_publisher("demo/sensor/r1/temp", encoding=zenoh.Encoding.TEXT_PLAIN,
                              priority=zenoh.Priority.DATA_HIGH,
                              congestion_control=zenoh.CongestionControl.BLOCK, express=True)
    ml = pub.declare_matching_listener(lambda st: print("matching:", st.matching))
    pub.put("21.5", attachment=b"seq=1")
    s.put("demo/sensor/r2/temp", "19.5")

    qbl = s.declare_queryable("demo/calc/**",
                              lambda q: q.reply("demo/calc/temp/r1", f"21.0 {q.parameters.get('unit', 'C')}"))
    for r in s.get("demo/calc/temp/*?unit=F", timeout=2.0):   # handler omitted -> iterable FIFO channel
        print(r.ok.payload.to_string() if r.ok else r.err.payload.to_string())

    tok = s.liveliness().declare_token("demo/alive/node-a")
    print([str(r.ok.key_expr) for r in s.liveliness().get("demo/alive/**", timeout=1) if r.ok])
    time.sleep(0.5)
```

Handlers: pass a callable (runs on a Zenoh thread: keep it short, don't block), or nothing / `zenoh.handlers.FifoChannel(n)`
/ `RingChannel(n)` and iterate or call `.recv()` / `.try_recv()`. Callbacks that raise print "callback error" and keep
going. The stubs say publishers, subscribers and queriers "are automatically undeclared when dropped": keep a
reference for as long as they should live (`sub = s.declare_subscriber(…)`), and `undeclare()` explicitly when done.

## 3. C (zenoh-c) and C++ (zenoh-cpp)

conda-forge `libzenohc` gives `zenoh.h` + `libzenohc.so` + `zenohc.pc`; build with `cc … $(pkg-config --cflags --libs zenohc)
-Wl,-rpath,$CONDA_PREFIX/lib` inside `pixi run` (the `c-compiler` 2.x package puts `cc`/`gcc` on PATH; it does **not** set
`$CC`). CMake: `find_package(zenohc)` → `zenohc::lib`. Pattern: `z_owned_X_t` (you own it, `z_drop(z_move(x))`), `z_loan(x)`
(borrow), `z_view_*` (non-owning views of your strings), `z_moved_*` (ownership passes to the callee):

```c
z_owned_config_t config; z_config_default(&config);
zc_config_insert_json5(z_loan_mut(config), "mode", "\"client\"");
zc_config_insert_json5(z_loan_mut(config), "connect/endpoints", "[\"tcp/127.0.0.1:7447\"]");
z_owned_session_t s; if (z_open(&s, z_move(config), NULL) < 0) return 1;

z_view_keyexpr_t ke; z_view_keyexpr_from_str(&ke, "demo/**");
z_owned_closure_sample_t cb; z_closure(&cb, on_sample, NULL, NULL);     // void on_sample(z_loaned_sample_t*, void*)
z_owned_subscriber_t sub; z_declare_subscriber(z_loan(s), &sub, z_loan(ke), z_move(cb), NULL);

z_owned_bytes_t p; z_bytes_copy_from_str(&p, "hi");
z_view_keyexpr_t pk; z_view_keyexpr_from_str(&pk, "demo/c/pub");
z_put(z_loan(s), z_loan(pk), z_move(p), NULL);                          // or z_declare_publisher + z_publisher_put

z_owned_fifo_handler_reply_t h; z_owned_closure_reply_t rcb; z_fifo_channel_reply_new(&rcb, &h, 16);
z_get(z_loan(s), z_loan(ke), "unit=F", z_move(rcb), NULL);              // parameters as a separate string
z_owned_reply_t reply;
while (z_recv(z_loan(h), &reply) == Z_OK) { if (z_reply_is_ok(z_loan(reply))) { /* z_reply_ok(...) */ } z_drop(z_move(reply)); }
```

Queryable reply: `z_query_reply(query, z_loan(ke), z_move(payload), NULL)`. Strings out: `z_bytes_to_string` →
`z_owned_string_t`, `z_string_data`/`z_string_len`. Unstable APIs (some SHM, advanced pub/sub) need
`Z_FEATURE_UNSTABLE_API` defined and a build that enabled it. zenoh-cpp is header-only on top of zenoh-c (or zenoh-pico):
conda-forge `libzenohcxx`, `#include "zenoh.hxx"`, RAII objects (`zenoh::Session::open(std::move(config))`).

Rust: `let s = zenoh::open(zenoh::Config::default()).await?; s.put("k", "v").await?;` with
`s.declare_subscriber("k/**").callback(|s| …).await?` — follow `examples/examples/*.rs` of the tag.

## 4. Deployment: modes, scouting, routers

| Mode | Behaviour | Use for |
|---|---|---|
| `peer` (default for apps) | connects directly to other peers (full mesh in a LAN), also to routers | processes on one host or LAN |
| `client` | one connection to a router (or peer); all traffic via it | constrained devices, NAT, WAN, many processes |
| `router` (`zenohd`) | routes between peers/clients/routers, runs plugins, link-state routing between routers | infrastructure, crossing networks |

- Scouting: **multicast** UDP `224.0.0.224:7446` (`scouting/multicast/enabled`, `interface`, `autoconnect`) — fails
  across subnets, in Docker bridge networks and on hosts whose firewall drops multicast; **gossip** (on by default)
  spreads locators over existing connections. When anything is not found, configure explicit `connect/endpoints`
  and disable multicast (`--no-multicast-scouting`).
- Endpoints: `tcp/host:7447`, `udp/host:7447` (best effort), `tls/host:7447`, `quic/host:7447`, `ws/host:7447`,
  `unixsock-stream/path`, `udp/224.0.0.123:7447#iface=eth0` (multicast transport), `serial//dev/ttyACM0#baudrate=115200`
  (**only** in a `zenohd` built with cargo feature `transport_serial`; default features are tcp, udp, tls, quic,
  quic_datagram, ws, unixsock-stream, multilink, compression, auth_pubkey, auth_usrpwd; SHM is feature `shared-memory`).
- Two routers on different hosts: `connect` on one to the other's `listen`. Cross-network via SSH when only SSH gets
  through (tested): `ssh -L 27447:127.0.0.1:7447 hostA` + `ssh -R 17447:127.0.0.1:27447 hostB`, then the router on B
  `connect: { endpoints: ["tcp/127.0.0.1:17447"] }`. Prefer a VPN (WireGuard) or TLS/QUIC listener for real use.

### `zenohd` router config (tested with zenohd 1.10.1/1.10.2)

```json5
{
  mode: "router",
  listen: { endpoints: ["tcp/0.0.0.0:7447"] },
  connect: { endpoints: [] },                       // other routers, e.g. "tcp/10.0.0.2:7447"
  scouting: { multicast: { enabled: false } },
  adminspace: { enabled: true, permissions: { read: true, write: false } },
  plugins_loading: { enabled: true, search_dirs: ["/path/to/env/lib"] },   // needed for conda/pixi installs
  plugins: {
    rest: { __required__: true, http_port: 8000 },
    storage_manager: {
      __required__: true,
      storages: { demo: { key_expr: "demo/store/**", volume: "memory" } },
    },
  },
}
```

Run `zenohd -c router.json5` (CLI also: `-l`, `-e`, `-P <plugin>`, `--plugin-search-dir`, `--rest-http-port 8000`,
`--no-multicast-scouting`, `--no-timestamp`, `--adminspace-permissions rw`, `--cfg='key/path:json5value'`).
**Pixi/conda pitfall**: the plugins are in `$CONDA_PREFIX/lib`, which `zenohd` does not search; without
`plugins_loading.search_dirs` you get `Plugin load failure: Library file 'libzenoh_plugin_rest.so' not found`
(and `__required__: true` makes that fatal instead of a log line). Plugin and `zenohd` versions must match exactly.

Other keys that exist (see `DEFAULT_CONFIG.json5`): `id`, `metadata`, `timestamping/enabled`,
`queries_default_timeout`, `routing/router/linkstate`, `aggregation`, `namespace` (prefix all keys of a session),
`downsampling` (per-key max frequency on interfaces/flows), `low_pass_filter` (size limit), `access_control`,
`transport/unicast/{lowlatency,qos/enabled,compression/enabled,max_links,max_sessions}`,
`transport/link/tx/{batch_size,lease,keep_alive,queue/…}`, `transport/link/tls/…`, `transport/shared_memory/…`,
`transport/auth/{usrpwd,pubkey}`. `lowlatency: true` requires `qos/enabled: false`.

### REST, storages, admin space (tested)

```sh
curl -X PUT -H 'Content-Type: text/plain' -d 'hello' http://localhost:8000/demo/store/a   # = put
curl 'http://localhost:8000/demo/store/**'          # = get → [{"key":…,"value":"hello","encoding":"text/plain","timestamp":"…/<zid>"}]
curl 'http://localhost:8000/@/*/router'             # router info: locators, sessions, plugins, version
curl 'http://localhost:8000/@/*/router/subscriber/**'   # who subscribes to what
```
Storage volumes: `memory` built in; RocksDB, InfluxDB, filesystem, S3 backends are separate repos
(`eclipse-zenoh/zenoh-backend-{rocksdb,influxdb,filesystem,s3}`) that must match the router version. `strip_prefix`, `complete`, `replication`,
`garbage_collection` are storage options. A storage answers `get` like a queryable: apps don't know it's there.
From any session: `session.get("@/*/router")`, `@/<zid>/router/status/plugins/**`, `@/<zid>/session/**`.

### Security

- TLS: endpoints `tls/…` + `transport/link/tls/{root_ca_certificate, listen_private_key, listen_certificate,
  enable_mtls, connect_private_key, connect_certificate, verify_name_on_connect}` (QUIC uses the same TLS block).
  With `enable_mtls`, ACL subjects can match `cert_common_names`.
- `transport/auth/usrpwd/{user,password,dictionary_file}` (router has the dictionary, clients user/password).
- `access_control`: `enabled`, `default_permission` (`deny`/`allow`), `rules` (id, `messages` [put, delete,
  declare_subscriber, query, reply, declare_queryable, liveliness_token, liveliness_query,
  declare_liveliness_subscriber], `flows` [ingress, egress], `permission`, `key_exprs`), `subjects` (interfaces,
  cert_common_names, usernames, link_protocols, zids), `policies` (rules × subjects). Copy the block from
  `DEFAULT_CONFIG.json5` at your tag and test both allowed and denied keys.

## 5. Shared memory

SHM avoids copies between processes on one host: large payloads (images, point clouds) go through a shared segment,
only a reference crosses the socket. Config `transport/shared_memory/enabled` (true by default in 1.10's
DEFAULT_CONFIG; check yours), `mode` (`lazy`/`init`), `transport_optimization/{enabled,pool_size,message_size_threshold}`
(implicit SHM for any big `put`; default threshold 3072 B in zenoh 1.10.2's config). Both ends must enable it
and be on the same host (falls back to the network otherwise). Explicit API (not run in validation; follow the
examples): Python `zenoh.shm.ShmProvider.default_backend(layout)` → `provider.alloc(…)` (policies `BlockOn`,
`GarbageCollect`, `Defragment`) → write into the `ZShmMut` → `put`; receivers can check `payload.as_shm()`.
C `z_shm_provider_default_new`; examples `z_pub_shm.py`, `z_pub_shm.c`, `z_sub_shm.c`, `z_alloc_shm.rs`.
Gains are for large messages (images, point clouds) and fan-out to several local subscribers; for small messages
there is no benefit, which is why the threshold exists (measure with `z_pub_shm_thr`/`z_ping_shm`). `/dev/shm` must be
large enough (Docker: `--ipc=host` or `--shm-size`). A `zenohd` built from source needs cargo feature `shared-memory`
for SHM on router links; check what your package was built with.

## 6. Performance

- Use declared publishers for streams; `express=True` only for latency-critical small messages; leave batching
  on for throughput. `congestion_control=BLOCK` gives back-pressure (publisher waits), `DROP` sheds load.
- Tools (examples in each binding, same flags): `z_pub_thr <size>` / `z_sub_thr -s <measurements> -n <msgs>`,
  `z_ping <size> -n <samples>` / `z_pong`; common flags `-m peer|client`, `-e <endpoint>`, `-l <endpoint>`,
  `--no-multicast-scouting`, `-c config.json5`, `--cfg key:value`. Build zenoh-c's from the tag matching your lib.
- Measured (zenoh-c 1.10.1, peer↔peer over loopback TCP, 24-core x86_64): **≈5 M msg/s at 8 B**, `z_ping` 64 B
  **RTT 22 µs** (one-way ~11 µs). Router in the path and real networks add latency; measure on the target.
- Peer mesh scales O(n²) connections: many processes → clients to a local router, or `routing/peer` with fewer links.
- For many small topics use one key space with `*` subscriptions rather than thousands of declarations.
- Logs: `RUST_LOG=zenoh=debug` (or `zenoh::net=trace` …) for apps and `zenohd`.

## 7. zenoh-pico (microcontrollers, as of 1.10.2)

C library for MCUs/RTOS (Zephyr ≥ 3.7, Arduino/ESP32, ESP-IDF, Mbed, FreeRTOS-Plus-TCP, ThreadX/STM32,
Raspberry Pi Pico, plus Unix/Windows). Usually **client** mode to a `zenohd` (or peer over UDP multicast).
Transports per README: Unix/Windows/Zephyr/Arduino/ESP-IDF/Mbed: UDP unicast+multicast, TCP; serial on Zephyr,
Arduino, ESP-IDF, Mbed, RPi Pico (also USB CDC, needs `Z_FEATURE_LINK_SERIAL_USB` + `Z_FEATURE_UNSTABLE_API`);
FreeRTOS-Plus-TCP: UDP unicast + TCP. Build-time features `Z_FEATURE_{PUBLICATION,SUBSCRIPTION,QUERY,QUERYABLE,LIVELINESS,
MATCHING,INTEREST,MULTI_THREAD,LINK_TLS,LINK_UDP_MULTICAST,RAWETH_TRANSPORT,ADVANCED_PUBLICATION,…}` (CMake options)
shrink RAM/flash. Serial: device `-DZENOH_CONFIG_CONNECT="serial/uart1_0#baudrate=38400"`, host
`zenohd -l serial//dev/ttyACM0#baudrate=115200` with a serial-enabled `zenohd`. API is the same `z_*` C API as zenoh-c
(owned/loaned/moved), so code ports with small changes; zenoh-cpp can sit on top of pico.

## 8. Odin (brief; see the odin skill)

zenoh-c is a plain C ABI, so `foreign import zenohc "system:zenohc"` works. The `z_owned_*`/`z_view_*` types are
opaque **fixed-size blobs**: declare them as `struct #align(8) { _0: [N]u8 }` with N from `zenoh_opaque.h` of the exact
version and platform (zenoh-c 1.10.1 x86_64: config 2064, session 8, bytes 40, view_keyexpr 32). The C macros
(`z_loan`, `z_move`, `z_drop`) are `_Generic` wrappers: call the typed functions (`z_config_loan_mut`, `z_session_loan`,
`z_view_keyexpr_loan`, `z_session_drop`) and pass `&x` where C passes `z_move(x)`. Tested: an Odin `z_put` received
by a Python subscriber. Link with `-extra-linker-flags:"-L$CONDA_PREFIX/lib -Wl,-rpath,$CONDA_PREFIX/lib"`. Generate
bindings from the header for anything larger (and re-check blob sizes on each upgrade).

## 9. Checklist / pitfalls

1. Same Zenoh minor everywhere you can; plugins == `zenohd` exactly; never mix 0.11 and 1.x.
2. Nothing discovered → explicit `connect`, multicast off; check firewalls (`7447/tcp`, `7446/udp` scouting).
3. Python callbacks run on Zenoh threads; hand work to a queue. Keep references to declared objects.
4. `get` with no answer = timeout (default `queries_default_timeout`, 10 s): pass `timeout=`.
5. `session.put` with no subscriber is cheap but not free; use the matching listener for heavy producers.
6. Wildcards in `reply` keys are an error: reply with a concrete key inside the query's key expression.
7. Document the config: commit the JSON5, and print the effective config (`zenohd` logs `Initial conf: …` at INFO).
