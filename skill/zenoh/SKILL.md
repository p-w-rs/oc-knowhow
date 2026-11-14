---
name: zenoh
description: Build distributed robotics/IoT systems with Eclipse Zenoh 1.x — key expressions and wildcards (*, **, $*), selectors and parameters, sessions, publishers/subscribers, queryables/get/querier, liveliness tokens, matching listeners, attachments, encodings, QoS (priority, congestion control, express, reliability), peer/client/router modes, scouting (multicast, gossip), zenohd router JSON5 config, TLS/QUIC/mTLS, user/password and ACL, REST plugin, storage manager and storages, HLC timestamps, admin space, APIs in Python, Rust, C (zenoh-c), C++ (zenoh-cpp), zenoh-pico for microcontrollers (serial, UDP, TCP), shared memory, throughput/latency tools, calling zenoh-c from Odin, and 0.11→1.x migration. Load before writing or deploying anything that uses Zenoh.
---

# Zenoh 1.x

Zenoh is a pub/sub + query protocol with routing: data goes to **key expressions**, not to topics or brokers.
For ROS 2 interop see the **zenoh-ros2** skill, for recording to files see **mcap**. Environments come from
**pixi**; for Odin bindings also load **odin**; sockets, firewalls and tunnels are in **c-networking**.
The reference library holds the 1.10.2 sources: `zenoh-rust-source` (DEFAULT_CONFIG.json5 — every config key with its
comment — zenohd, REST/storage plugins, Rust API), `zenoh-c-source`, `zenoh-pico-source`, `zenoh-python-source`
(`.pyi` stubs). Check config keys and function signatures there with `library_search` before writing them.

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
  (endpoint keys `baudrate` (default 9600), `exclusive`, `tout` (µs), `release_on_close`; **only** in a `zenohd` built
  with the zenoh crate feature `transport_serial`, which conda-forge's is not (§7); default features are tcp, udp, tls, quic,
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

### Security (tested 13 Nov 2026: conda-forge zenohd 1.10.2 + Python eclipse-zenoh 1.10.2)

**TLS and QUIC** share one block, `transport/link/tls`. Keys at 1.10.2: `root_ca_certificate`, `listen_certificate`,
`listen_private_key`, `enable_mtls`, `connect_certificate`, `connect_private_key`, `verify_name_on_connect` (default
true), `close_link_on_expiration`, `so_rcvbuf`/`so_sndbuf`. The server certificate needs a SAN for the name or IP that
clients dial (`subjectAltName=DNS:localhost,IP:127.0.0.1`). Test PKI (openssl 3):
`openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -keyout ca.key -out ca.pem -subj "/CN=Test CA" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign`,
then a CSR for each leaf, signed with `openssl x509 -req … -CA ca.pem -CAkey ca.key -extfile <(printf 'subjectAltName=…\nextendedKeyUsage=serverAuth')`
(`clientAuth` for client certificates).
```json5
// router (mTLS on; drop the last two keys for server-only TLS)
{ mode: "router", listen: { endpoints: ["tls/0.0.0.0:7448", "quic/0.0.0.0:7449"] },
  transport: { link: { tls: { listen_certificate: "server.pem", listen_private_key: "server.key",
                              root_ca_certificate: "ca.pem", enable_mtls: true } } } }
// client: connect tls/<host>:7448 (or quic/…) with
  transport: { link: { tls: { root_ca_certificate: "ca.pem",
                              enable_mtls: true, connect_certificate: "client.pem", connect_private_key: "client.key" } } }
```
- Results: right CA works, and `session.info.links()[i].auth_identifier` is the server CN. With no CA or the wrong
  CA, the client logs `invalid peer certificate: UnknownIssuer` and the router logs `received fatal alert: UnknownCA`.
  Python only raises `Unable to connect to any of [...]`: set `RUST_LOG=zenoh=debug` to see why.
- **mTLS pitfall**: the client also needs `enable_mtls: true`. Otherwise it never sends its certificate, even with
  `connect_certificate` set, and the router logs `peer sent no certificates` (QUIC: `crypto(74) … peer sent no
  certificates`). Presenting the CA as a client certificate fails with `CaUsedAsEndEntity`.
- **QUIC pitfall**: UDP doesn't fall back between address families. On a host where `localhost` resolves only to
  `::1`, `quic/localhost:7449` against a listener on `127.0.0.1` times out after 10 s (`deadline has elapsed`; TLS
  over TCP worked). Dial the IP that is listening, or listen on `quic/[::]:7449`.

**User/password**: the router gets `transport: { auth: { usrpwd: { dictionary_file: "users.txt" } } }`, with one
`user:password` line per user (plain text, so protect the file; combine with TLS). Clients get
`transport/auth/usrpwd/{user,password}`. With a wrong password or an unknown user, the client logs `Received a close
message (reason GENERIC) in response to an OpenSyn` and the open fails. With no credentials it logs `… (reason 0)
in response to an InitSyn`. The router logs no WARN or ERROR for rejected logins.

**Access control** (tested with `usernames` and `cert_common_names` subjects):
```json5
access_control: { enabled: true, default_permission: "deny",
  rules: [
    { id: "pub",     messages: ["put", "delete", "query"], flows: ["ingress"], permission: "allow", key_exprs: ["demo/allowed/**"] },
    { id: "secret",  messages: ["put", "query"],           flows: ["ingress"], permission: "deny",  key_exprs: ["demo/secret/**"] },
    { id: "rep_out", messages: ["reply"],                  flows: ["egress"],  permission: "allow", key_exprs: ["demo/**"] },
    { id: "sub_in",  messages: ["declare_subscriber", "declare_queryable", "reply"], flows: ["ingress"], permission: "allow", key_exprs: ["demo/**"] },
    { id: "sub_out", messages: ["put", "delete", "query"], flows: ["egress"],  permission: "allow", key_exprs: ["demo/**"] } ],
  subjects: [ { id: "alice", usernames: ["alice"] }, { id: "bob", usernames: ["bob"] } ],   // or cert_common_names: ["client.example"]
  policies: [ { rules: ["pub", "secret", "rep_out"], subjects: ["alice"] }, { rules: ["sub_in", "sub_out"], subjects: ["bob"] } ] }
```
- Flows are seen from the router. A publisher needs `put` **ingress**. Its subscribers need `declare_subscriber`
  ingress **and** `put` egress. A querier needs `query` ingress + `reply` egress. A queryable needs
  `declare_queryable` + `reply` ingress and `query` egress. Anything not allowed falls to `default_permission`.
- Results: alice's `demo/allowed/a` reached bob. `demo/secret/b` and `demo/other/c` were **dropped silently**
  (`put()` still returns OK), and `get("demo/secret/q")` returned 0 replies, the same as no queryable.
- A subscription wider than what is allowed is **denied as a whole**: `declare_subscriber("demo/**")` with only
  `demo/allowed/**` allowed received nothing. Subscribe inside the allowed keys.
- Denials are logged only at TRACE: `RUST_LOG=info,zenoh::net::routing::interceptor::access_control=trace zenohd -c …`
  → `<zid> on Interface(lo)+Username(alice)+Transport(Tcp)+<zid> is unauthorized to Put (ingress) on demo/secret/b`
  (TLS: `CertCommonName(client.example)+Transport(Tls)`). According to the source (not seen in the tests), a session
  that matches no subject is logged at INFO as `did not match any configured ACL subject`.

## 5. Shared memory

SHM avoids copies between processes on one host. A large payload goes into a POSIX shared-memory segment
(`/dev/shm/<id>.zenoh`) and only a reference crosses the socket. Config (1.10.2 defaults):
`transport/shared_memory/{enabled: true, mode: "lazy"|"init"}` and
`transport/shared_memory/transport_optimization/{enabled: true, pool_size: 16777216, message_size_threshold: 3072,
messages: ["put","query","reply"]}`. The optimization is **implicit SHM**: a plain `put` of ≥ 3 KiB is copied into
the pool. Both sides must have SHM enabled and be on the same host, and a link that fails the SHM probe falls back
to the network silently. Build support: PyPI `eclipse-zenoh` and conda-forge `libzenohc` 1.10.2 have it
(`zenoh_configure.h`: `Z_FEATURE_SHARED_MEMORY`, `Z_FEATURE_UNSTABLE_API`). A Rust or `zenohd` build needs cargo
feature `shared-memory`.

Explicit API (Python 1.10.2, `@_unstable`, tested):
```python
provider = zenoh.shm.ShmProvider.default_backend(6 * 1024 * 1024)        # pool bytes (or MemoryLayout)
buf = provider.alloc(len(data), policy=zenoh.shm.BlockOn(zenoh.shm.GarbageCollect()))   # ZShmMut
buf[:] = data                                                           # or fill slices in place
pub.put(buf)
# receiver: smp.payload.as_shm() is a ZShm (not None) when it arrived through SHM; None = copied/RAW
```
C: `z_shm_provider_default_new(&p, size)`, `z_shm_provider_alloc_gc_defrag_blocking(&res, z_loan(p), len)`, then
`z_shm_from_mut` → `z_bytes_from_shm` → `z_publisher_put`. Receivers check with
`z_bytes_as_loaned_shm(payload, &shm) == Z_OK` (zenoh-c examples `z_pub_shm.c`/`z_sub_shm.c`).
**Pool sizing (tested)**: a pool exactly the size of one message never works. The 1.10.2 example `z_ping_shm.c`
calls `z_shm_provider_default_new(&provider, args.size)` and fails at every size, even with 8 GB of memlock: below
~64 KiB with `Error initializing Talc backend!` and a core dump, and above that with `Unexpected failure during SHM buffer
allocation`. Patched to `args.size * 2 + 65536`, it works. Implicit SHM with `pool_size` == message size sent 0/20
through SHM. Size pools ≥ 2× the largest message (more for messages in flight), and raise `RLIMIT_MEMLOCK` to match.

**Locked memory pitfall (tested)**: zenoh **`mlock()`s every SHM segment it creates or opens**, so `ulimit -l`
(`RLIMIT_MEMLOCK`) caps SHM. On a host with an 8 MiB limit, the default 16 MiB pool failed with
`Error creating lazy ShmProvider: Unable to create POSIX shm segment: OS error 12`, and every sample arrived RAW with
no other symptom. Each process locks its own pool, the peers' segments it opens, and about 1.3 MiB of internals. When
ping and pong both used 6 MiB pools, they deadlocked with no output. Check `ulimit -l` and raise it
(`/etc/security/limits.conf` `memlock`, systemd `LimitMEMLOCK=`, Docker `--ulimit memlock=-1` plus `--ipc=host` or
`--shm-size`), or shrink `pool_size`. Budget per process: its own pool + the peers' pools it maps + ~1.3 MiB. For
64–256 MiB messages, use pools of 512 MiB–1 GiB and a memlock limit in GB (Jetson Ubuntu default: ~8 GB). The WARN
`error setting scheduling priority for thread` from the SHM watchdog is harmless. Processes that are killed leave
`/dev/shm/<id>.zenoh` behind (a 512 MiB pool stays allocated in RAM). Remove the ones `fuser` shows as unused.

Measured (zenoh 1.10.2, two processes, peer↔peer over loopback TCP, 24-core x86_64, pools of 6 MiB because of that
limit). Python one-way latency: 1 MiB **760 µs with explicit SHM vs 2.7 ms without**, 4 MiB **750 µs vs 7.0 ms**.
Implicit SHM at 1 MiB: 1.2 ms, 13.6 k msg/s (≈ 14 GB/s, 299/300 samples SHM). At 4 MiB, implicit SHM ran out of the
6 MiB pool for 27 of 60 samples, which fell back to RAW. zenoh-c `z_ping`/`z_pong` 1 MiB RTT: **43 µs with implicit
SHM vs 534 µs** with `transport/shared_memory/enabled:false`. 64 B RTT is 24 µs either way. Without SHM: 64 MiB
messages took 40 ms each (1.3 GB/s). The gain grows with message size and the number of local subscribers. Small
messages gain nothing (hence the threshold).

**Large messages (tested: Jetson AGX Orin aarch64, memlock 8 GB, Python 1.10.2, peer↔peer loopback, the receiver
acks)**:

| 64 MiB / 256 MiB message | SHM received | RTT | throughput |
|---|---|---|---|
| explicit, pool 512 MiB / 1 GiB | 20/20, 10/10 | **0.12 ms / 0.27 ms** (filling the buffer: 4.2 / 16.7 ms) | 15 / 11 GB/s incl. fill |
| implicit, pool 512 MiB (128 MiB also) / 1 GiB | 19/20, 4/5 (first message RAW: lazy pool) | 17 ms / 65 ms (copy into pool) | ~2–4 GB/s |
| SHM off | – | 36 ms / 143 ms | 1.75 GB/s |

Write straight into a `ZShmMut` (explicit SHM). Implicit SHM only halves the cost, because the payload is still
copied once. zenoh-c (patched `z_ping_shm` → `z_pong`) RTT: 64 B 82 µs, 1 MiB 142 µs, 64 MiB 118 µs, 256 MiB 120 µs.
**256 MiB over the network path is lost silently with the default `CongestionControl.DROP`**: none of the
RAW 256 MiB messages arrived (`put` returned OK), including the first message under implicit SHM. Fragments time out (`transport/link/tx/queue/congestion_control/
drop/max_wait_before_drop_fragments`, 50 ms). Use `congestion_control=BLOCK` for big non-SHM messages
(defragmentation limit `transport/link/rx/max_message_size`, default 1 GiB).

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
Arduino, ESP-IDF, Mbed, RPi Pico (also USB CDC, needs `Z_FEATURE_LINK_SERIAL_USB` + `Z_FEATURE_UNSTABLE_API`) and Linux/macOS/BSD ttys
(all serial needs `Z_FEATURE_LINK_SERIAL=1`, default 0);
FreeRTOS-Plus-TCP: UDP unicast + TCP. Build-time features `Z_FEATURE_{PUBLICATION,SUBSCRIPTION,QUERY,QUERYABLE,LIVELINESS,
MATCHING,INTEREST,MULTI_THREAD,LINK_TLS,LINK_UDP_MULTICAST,RAWETH_TRANSPORT,ADVANCED_PUBLICATION,…}` (CMake options)
shrink RAM/flash. The API is the same `z_*` C API as zenoh-c (owned/loaned/moved), so code ports with small changes. zenoh-cpp
can sit on top of pico. Client calls: `zp_config_insert(z_loan_mut(cfg), Z_CONFIG_MODE_KEY, "client")`,
`Z_CONFIG_CONNECT_KEY, "tcp/…"`.

**Unix (tested 1.10.2)**: `cmake -S zenoh-pico -B build -DBUILD_TESTING=OFF && cmake --build build -j`, with
`cmake`/`c-compiler` from Pixi. Examples are in `build/examples/` (`z_pub`, `z_sub`, `z_get`, `z_queryable`, … with
getopt flags `-m client -e tcp/127.0.0.1:7447 -k key -v value -n count`). They talked to `zenohd` and Python both ways.
Add `stdbuf -oL` when you redirect their output.

**Serial (tested 13 Nov 2026, zenohd and zenoh-pico 1.10.2 on Linux x86_64)**. conda-forge `zenohd` has no
serial support (`Unable to open listener serial//dev/pts/0#…: Unicast not supported for serial protocol`).
Build your own, using `rust` from Pixi (rustc 1.100; this took 105 s on 24 cores and gives an 18 MB binary):
`git clone -b 1.10.2 --depth 1 https://github.com/eclipse-zenoh/zenoh && cd zenoh && pixi run cargo build --release -j24 -p zenohd --features zenoh/transport_serial`.
zenoh-pico **does** have a POSIX serial link (`src/link/transport/serial/tty_posix.c`, Linux/macOS/BSD), but it is
off by default: `cmake … -DZ_FEATURE_LINK_SERIAL=1`. A test rig without hardware, all tested:
```sh
socat -d -d pty,raw,echo=0,link=$PWD/ttyA pty,raw,echo=0,link=$PWD/ttyB &          # virtual null-modem cable
zenohd --no-multicast-scouting -l "serial/$PWD/ttyA#baudrate=115200" -l tcp/127.0.0.1:7447
build/examples/z_pub -m client -e "serial/$PWD/ttyB#baudrate=115200" -k demo/pico -v hi   # also z_sub, z_get, z_pong
```
Pico pub, sub and get all worked against Python clients on the router's TCP side. A real MCU on a USB UART works
the same way: host `zenohd -l "serial//dev/ttyACM0#baudrate=115200"` (`serial/` + absolute path; Rust keys
`baudrate` (default 9600), `exclusive` (default true, locks the port), `tout` (µs, default 50000),
`release_on_close`). Device side: `-DZENOH_CONFIG_CONNECT="serial/uart1_0#baudrate=115200"` (Zephyr device
name) or `serial/<txpin>.<rxpin>#baudrate=…` on boards that take pins. Limits from the source: pico **requires**
`baudrate`; an address that contains `.` is parsed as pins, so device paths must not contain dots; POSIX pico accepts
only 1200–230400 baud; there is no flow control, parity or stop-bit option. Framing (`z-serial` 0.3.1 in Rust,
`serial_protocol.c` in pico): COBS with a 0x00 delimiter, 1-byte header with I/A/R flags for the init/ack/reset
handshake, 2-byte length, CRC32. MTU 1500. The link is **unreliable** (`is_reliable: false`), so frames with a bad CRC
are dropped. Measured on ptys (ptys ignore the baud rate): Python → router → serial → pico `z_pong` → back RTT 0.7 ms at 8 B, 2–4 ms at
64 B–1.4 KB. With the line throttled to ~11.5 kB/s (`pv -L`, ≈115200 baud), 64 B echoes ran at ~150 msg/s each way.
**Pitfalls (tested)**: (1) **router → pico messages of ≥ ~1470 B payload are lost silently**. The Rust side fills
1500 B frames whose COBS encoding is up to 1516 B, but pico rejects anything above its 1507 B buffer (pico DEBUG
`tmp_buf too small`, then `First fragment received without the start marker`). pico → router fragmentation worked up to
5000 B. Shrinking batches doesn't help: pico `-DBATCH_UNICAST_SIZE=1400` makes the router reject the link
(`Recv buffer is too small, required minimum 1500`), and a router with `transport/link/tx/batch_size:1400` never
completes the open. Keep downlink payloads to an MCU below ~1.4 KB. (2) After a pico process dies mid-session, the
next connect often fails (router ERROR `Unable COBS decode`) and the one after that works, so retry the open.

**Zephyr in QEMU (tested: zenoh-pico 1.10.2, Zephyr v4.4.2, Zephyr SDK 1.0.1, board `qemu_x86`)**. The SDK's
`hosttools` bundle includes QEMU 10.0.2, so you don't need to build QEMU. Steps:
`west init -m https://github.com/zephyrproject-rtos/zephyr --mr v4.4.2 ws` →
`west config manifest.project-filter -- "-.*"` → `west update` (zephyr only, 1.5 GB). Unpack the SDK `_minimal`
tarball, put `toolchain_gnu_linux-x86_64_x86_64-zephyr-elf` into `<sdk>/gnu/`, run
`hosttools/zephyr-sdk-x86_64-hosttools-standalone-*.sh -y -d .` and `./setup.sh -c`. West and the Zephyr Python
requirements come from Pixi (pypi `west`, `pyelftools`, `pykwalify`, …). zenoh-pico is a Zephyr module
(`zephyr/module.yml`):
```sh
west build -b qemu_x86 -d build app -- -DZEPHYR_EXTRA_MODULES=/path/to/zenoh-pico   # 638 KB RAM
west build -d build -t run          # qemu: -nic user,model=e1000  → guest 10.0.2.15, host = 10.0.2.2
```
App `prj.conf` essentials. NIC and user networking:
`CONFIG_NETWORKING=y CONFIG_PCIE=y CONFIG_NET_L2_ETHERNET=y CONFIG_NET_QEMU_USER=y CONFIG_NET_IPV4=y CONFIG_NET_TCP=y CONFIG_NET_UDP=y CONFIG_NET_SOCKETS=y CONFIG_DNS_RESOLVER=y CONFIG_NET_CONFIG_SETTINGS=y CONFIG_NET_CONFIG_NEED_IPV4=y CONFIG_NET_CONFIG_MY_IPV4_ADDR="10.0.2.15" CONFIG_NET_CONFIG_MY_IPV4_GW="10.0.2.2"`.
libc and POSIX:
`CONFIG_NEWLIB_LIBC=y CONFIG_POSIX_API=y CONFIG_MAIN_STACK_SIZE=8192 CONFIG_HEAP_MEM_POOL_SIZE=150000 CONFIG_MAX_PTHREAD_MUTEX_COUNT=32 CONFIG_MAX_PTHREAD_COND_COUNT=16 CONFIG_POSIX_THREAD_THREADS_MAX=8`.
zenoh-pico: `CONFIG_ZENOH_PICO=y` plus each feature you use, because the module's booleans have **no defaults**:
`_MULTI_THREAD _PUBLICATION _SUBSCRIPTION _QUERY _QUERYABLE _INTEREST _FRAGMENTATION _BATCHING _UNICAST_TRANSPORT _LINK_TCP _TCP_NODELAY _ENCODING_VALUES _SESSION_CHECK` (each `=y`).
Connect with `tcp/10.0.2.2:7447`; the host router listens on `127.0.0.1:7447` or `0.0.0.0:7447`. Result: Zephyr
pub → Python sub (45/45), Python put → Zephyr sub, Zephyr `z_get` → Python queryable, Python `get` → Zephyr
queryable all worked. Failures on the way, with fixes:
- Without `CONFIG_DNS_RESOLVER`, `z_open` returned -102 (`_Z_ERR_TRANSPORT_OPEN_FAILED`). zenoh-pico calls
  `getaddrinfo` even for an IP address.
- With Zephyr's default POSIX pools (5 mutexes, 5 condition variables, 5 threads), the Zenoh INIT/OPEN handshake
  succeeded, then `System error: 12` (ENOMEM from `pthread_mutex_init`) and `z_open` returned -80. Raise the counts
  above.
- To see pico's debug log, add `zephyr_compile_definitions(ZENOH_LOG_DEBUG)` to the app's `CMakeLists.txt`.
  `ZENOH_LOG_{ERROR,WARN,INFO,DEBUG,TRACE}` (and legacy `ZENOH_DEBUG=1..3`) select the level.

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
8. Security fails quietly. mTLS needs `enable_mtls: true` on **both** sides. ACL denials drop data silently (put
   returns OK, get returns 0 replies) and are logged only at TRACE. Test allowed **and** denied keys before shipping.
9. SHM fails quietly too. With `ulimit -l` below the pool size, or a pool no bigger than one message, every sample
   goes RAW. Check `payload.as_shm()` on the receiver once. Huge RAW messages with `DROP` vanish, so use `BLOCK`.
10. Serial to zenoh-pico: build `zenohd` with `transport_serial`, keep downlink payloads under ~1.4 KB, and retry the open.
