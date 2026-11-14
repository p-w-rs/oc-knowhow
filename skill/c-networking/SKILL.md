---
name: c-networking
description: Real-time game/simulation networking and utilities in C (and from Odin) with ENet (zpl-c fork, single header, dual-stack IPv6; upstream lsalzman/enet and Odin vendor:ENet), librg (world/chunk interest management and entity replication: owners, chunk radius queries, librg_world_write/read with event callbacks, over ENet) and zpl (single-header C99 toolkit: arenas/allocators, strings, arrays, hash tables, JSON5 parser, threads/jobs) — host/service loop, channels and reliability flags, timeouts and bandwidth, testing two processes and across machines, NAT and firewalls, security (ENet is unencrypted). Load before writing or debugging ENet, librg or zpl code.
---

# C networking: ENet, librg, zpl

## Ground truth first

- Versions as of Nov 2026 (verify with `git ls-remote --tags`): **zpl-c/enet v2.7.0** (2026-06, `ENET_VERSION_MAJOR 2`),
  upstream **lsalzman/enet v1.3.18**, **librg v7.4.0** (2025-01; `master` has only CI commits since), **zpl 19.5.0**
  (2024-08; tag `19.5.0` — note `git ls-remote --tags | sort -V` lists the old `v9.8.5` last because of the `v` prefix; take the single header from GitHub Releases). Use the release assets:
  `https://github.com/zpl-c/{enet,librg,zpl}/releases/download/<tag>/{enet,librg,zpl}.h`. In the zpl repo,
  `code/zpl.h` is a multi-file dev header, not the single-file distribution.
- The reference library holds these sources at the pinned tags (`enet-zpl-source`, `enet-upstream-source`,
  `librg-source`, `zpl-source`; Odin's `vendor:ENet` in `odin-source`): `library_search` returns each declaration with
  its doc comment and file:line, e.g. `library_search query="enet_host_service" sources=["enet-zpl-source"]`.
- Read the header for the version you vendor: ENet `enet.h` (API near line 900–1080), librg `code/header/*.h` +
  `docs/`, zpl `code/header/**` (one file per module). Docs: http://enet.bespin.org (upstream tutorial and design; the API
  is the same apart from the differences listed below), https://zpl-c.github.io/librg/, https://github.com/zpl-c/zpl.
- conda-forge has no `enet`, `librg` or `zpl` package: vendor the headers. Compilers and CMake come from Pixi
  (`pixi add c-compiler cmake ninja`; see pixi).

## ENet

- Reliable/unreliable messages, ordered per channel, fragmentation, RTT/throttling, all over one UDP socket. You get
  **no** encryption, authentication, NAT traversal, lobby or serialization.
- **zpl fork**: one header. Put `#define ENET_IMPLEMENTATION` before `#include "enet.h"` in exactly one `.c` file (or
  build with CMake `-DENET_STATIC=1` / `-DENET_SHARED=1` and `ENET_DLL`). Compared with upstream: **dual-stack IPv6 by
  default** (`ENetAddress.host` is an `in6_addr`; IPv4 peers appear as `::ffff:a.b.c.d`; define `ENET_IPV4_ONLY` for
  the old 4-byte layout), monotonic time, accessors (`enet_peer_get_ip/port/rtt/packets_lost`,
  `enet_host_get_*`, `enet_packet_get_data`), an extra `ENET_EVENT_TYPE_DISCONNECT_TIMEOUT` event, and
  `ENET_PACKET_FLAG_UNTHROTTLED`. `enet_address_set_host` is a macro for `_old` (IPv4 lookup) unless
  `ENET_FEATURE_ADDRESS_MAPPING` is defined (then `_new`: getaddrinfo `AF_UNSPEC`); `::1` and `localhost` both worked.
  **The fork and upstream 1.3.18 speak the same wire protocol**: an Odin vendor:ENet (upstream) client exchanged
  reliable and unsequenced packets with a zpl-fork server.
- Core loop (validated):
  ```c
  enet_initialize(); atexit(enet_deinitialize);
  ENetAddress a = {0}; a.host = ENET_HOST_ANY; a.port = 7777;
  ENetHost *srv = enet_host_create(&a, 32 /*peers*/, 2 /*channels*/, 0, 0 /*bandwidth in/out B/s, 0 = unlimited*/);
  ENetEvent ev;
  while (enet_host_service(srv, &ev, 16 /*ms; 0 = poll*/) > 0) switch (ev.type) {
    case ENET_EVENT_TYPE_CONNECT: ev.peer->data = my_player; break;          /* ev.data = value from host_connect */
    case ENET_EVENT_TYPE_RECEIVE: handle(ev.channelID, ev.packet->data, ev.packet->dataLength);
                                  enet_packet_destroy(ev.packet); break;     /* you own received packets */
    case ENET_EVENT_TYPE_DISCONNECT: case ENET_EVENT_TYPE_DISCONNECT_TIMEOUT: ev.peer->data = NULL; break;
  }
  /* client */ ENetHost *c = enet_host_create(NULL, 1, 2, 0, 0); enet_address_set_host(&a, "server");
  ENetPeer *p = enet_host_connect(c, &a, 2, 1234); /* then wait for CONNECT in host_service, e.g. 5000 ms */
  enet_peer_send(p, 0, enet_packet_create(buf, len, ENET_PACKET_FLAG_RELIABLE));  /* ENet owns the packet now */
  enet_host_broadcast(srv, 1, pkt); enet_host_flush(c);   /* sends happen in host_service/flush */
  enet_peer_disconnect(p, 0); /* then service until DISCONNECT; enet_peer_reset = hard drop, no notification */
  ```
- Flags: `RELIABLE` (resend until acked, in order per channel), none (unreliable but sequenced: late packets are
  dropped), `UNSEQUENCED` (unreliable, unordered), `UNRELIABLE_FRAGMENT`, `NO_ALLOCATE` (you keep the buffer alive),
  `UNTHROTTLED` (fork). Typical layout: channel 0 reliable events/RPC, channel 1 unsequenced state snapshots. Keep
  packets under the MTU (`ENET_HOST_DEFAULT_MTU` 1392) unless you mean to fragment.
- Tuning: `enet_peer_timeout(peer, limit, min_ms, max_ms)` (defaults 32 / 5000 / 30000),
  `enet_peer_ping_interval`, `enet_host_bandwidth_limit`, `enet_peer_throttle_configure`, `enet_host_channel_limit`,
  `enet_host_compress(host, &compressor)` (custom `ENetCompressor`; the fork removed upstream's
  `enet_host_compress_with_range_coder`). `enet_peer_get_rtt` reads 500 ms until the first
  measurement (validated), so don't read it right after connect.
- Threads: ENet is not thread-safe. Keep one network thread per `ENetHost` and pass messages to it through queues.
- Pitfalls: forgetting `enet_packet_destroy` on RECEIVE leaks memory; a packet created and never sent also leaks;
  `enet_host_service` processes **one** event per call, so loop until it returns 0; if you service only on one
  side (e.g. client sends in a loop) also drain events there, or you will drop echoes; host byte order for `port`,
  network order for `host`.

## librg (interest management / replication)

- What it does: the server keeps a **world** split into **chunks** (2D/3D grid). Entities have a chunk, an optional
  **owner** (a client id) and visibility overrides. For each owner, `librg_world_write` serializes what that owner
  should see (entities within `chunk_radius` of the chunks of the entities it owns) as CREATE/UPDATE/REMOVE records
  since that owner's last snapshot; the client applies it with `librg_world_read`. Your callbacks append or read the
  per-entity payload. Transport is yours (ENet in `code/apps/example-enet.c`; `librg_enet.h` is only a stub).
- `#define LIBRG_IMPL` (or `LIBRG_IMPLEMENTATION`) once before `#include "librg.h"`; it embeds zpl (nano + math)
  unless `LIBRG_CUSTOM_ZPL`. Validated flow (2 entities visible, 1 far; then one moves out of range):
  ```c
  librg_world *w = librg_world_create();
  librg_config_chunksize_set(w, 16, 16, 1); librg_config_chunkamount_set(w, 16, 16, 1);
  librg_config_chunkoffset_set(w, LIBRG_OFFSET_MID, LIBRG_OFFSET_MID, LIBRG_OFFSET_MID);
  librg_event_set(w, LIBRG_WRITE_CREATE, on_write); librg_event_set(w, LIBRG_WRITE_UPDATE, on_write);
  librg_entity_track(w, id); librg_entity_chunk_set(w, id, librg_chunk_from_realpos(w, x, y, 0));
  librg_entity_owner_set(w, id, client_id);
  size_t len = sizeof buf; librg_world_write(w, client_id, 1 /*chunk radius*/, buf, &len, userdata);  /* -> send */
  /* client world: */ librg_event_set(cw, LIBRG_READ_CREATE/UPDATE/REMOVE, on_read); librg_world_read(cw, client_id, buf, len, ud);
  int32_t on_write(librg_world *w, librg_event *e) {   /* return bytes written, or LIBRG_WRITE_REJECT */
      int64_t id = librg_event_entity_get(w, e);
      if (librg_event_size_get(w, e) < sizeof(Pos)) return LIBRG_WRITE_REJECT;
      memcpy(librg_event_buffer_get(w, e), &pos[id], sizeof(Pos)); return sizeof(Pos); }
  ```
  Result: tick 1 CREATE 1,2; tick 2 UPDATE 1,2; after entity 2 moved away: UPDATE 1, REMOVE 2. On the client, received
  entities are **foreign** (`librg_entity_foreign` == 1). Return codes: `LIBRG_OK` (0), negative = error
  (`LIBRG_FAIL(code)`).
- Queries without packing: `librg_world_query(w, owner, radius, ids, &n)`, `librg_world_fetch_chunk/owner/all`.
  Visibility: `librg_entity_visibility_global_set(w, id, LIBRG_VISIBLITY_NEVER/ALWAYS)` (the misspelling is the
  real API name), `_owner_set` per owner, `librg_entity_dimension_set` for separate layers or interiors. Multi-chunk
  entities: `librg_entity_chunkarray_set`.
- Owners send their own entities' state back: in the server's WRITE_UPDATE callback reject entities owned by the
  target (`librg_entity_owner_get(w, id) == owner` → `LIBRG_WRITE_REJECT`), and the client writes its owned entity
  (see example-enet.c). Limits: `LIBRG_WORLDWRITE_MAXQUERY` (16384 entities per write); per-entity payload size is a
  `uint16_t` unless `LIBRG_ENABLE_EXTENDED_EVENTBUFFER`. If the buffer is too small, write returns a positive number
  (bytes missing); grow the buffer and call write again.
- Deprecated/unavailable: `librg_entity_radius_set` (since 7.0, pass the radius to write/query instead);
  `librg_entity_behavior_*` is behind `#if 0`. The v5/v6 API (`librg_ctx`, built-in network) is gone.
- Pitfall: a helper named `sync()` in your file collides with `unistd.h`'s `sync` that librg pulls in.

## zpl (single-header toolkit)

- `#define ZPL_IMPLEMENTATION` once. Distributions: default (everything), `ZPL_NANO` (essentials, core,
  collections, strings, memory, file, print…), `ZPL_PICO` (preprocessor, debug, memory without VM, collections). Add
  modules to nano/pico with `ZPL_ENABLE_{MATH,THREADING,JOBS,PARSER,SOCKET,HASHING,REGEX,DLL,OPTS,PROCESS,TIMER,EVENT}`,
  remove with `ZPL_DISABLE_*`, or `ZPL_CUSTOM_MODULES` + `ZPL_MODULE_*`. Options: `ZPL_EXPOSE_TYPES` (`u32` etc.
  without the prefix), `ZPL_NO_MATH_H`, `ZPL_PARSER_DISABLE_ANALYSIS` (faster parse, no style preservation).
- Validated (`-std=gnu11`; plain `-std=c99` fails on arm64 because of an inline `asm`; Linux also needs `-ldl -lm
  -pthread`):
  ```c
  zpl_arena arena; zpl_arena_init_from_allocator(&arena, zpl_heap_allocator(), zpl_megabytes(1));
  zpl_allocator a = zpl_arena_allocator(&arena);     /* also _init_from_memory, _init_sub, zpl_arena_snapshot_begin/_end */
  zpl_json_object root = {0};
  zpl_u8 err = zpl_json_parse(&root, text, a);         /* JSON5; parses IN PLACE: text must be writable and outlive root */
  zpl_adt_query(&root, "players/[id=2]/hp")->integer;  /* also "arr/3", "arr/[value]"; zpl_adt_find(node, "name", deep) */
  zpl_string out = zpl_json_write_string(a, &root, ZPL_JSON_INDENT_STYLE_COMPACT);  /* keeps JSON5 style (unquoted keys, hex) */
  zpl_string s = zpl_string_make(a, "hi"); s = zpl_string_append_fmt(s, " %d", 1);  /* always reassign */
  zpl_array(int) xs; zpl_array_init(xs, a); zpl_array_append(xs, 4); zpl_array_count(xs);
  ZPL_TABLE(static, ScoreTable, score_, int)  /* score_init(&t, a); score_set(&t, key_u64, v); int *v = score_get(&t, k); */
  zpl_jobs_system js; zpl_jobs_init(&js, zpl_heap_allocator(), 4); zpl_jobs_enqueue(&js, fn, data);
  while (!zpl_jobs_done(&js)) zpl_jobs_process(&js); zpl_jobs_free(&js);
  zpl_arena_free(&arena);   /* frees JSON tree, strings, arrays, tables in one go */
  ```
  Node fields: `type` (`ZPL_ADT_TYPE_OBJECT/ARRAY/STRING/INTEGER/REAL`), `name`, `string`, `integer`, `real`,
  `nodes` (zpl_array of children); booleans/null are in `props` (`ZPL_ADT_PROPS_TRUE/FALSE/NULL`). Errors
  `ZPL_JSON_ERROR_*`. Other modules: file IO (`zpl_file_read_contents`), CSV/URI parsers, hashing (crc32, murmur,
  fnv, base64), regex, options parser, threads (`zpl_thread_init/start/join`, mutex, semaphores, atomics), math
  (vec/mat/quat), sockets, random, sort.

## From Odin

- **vendor:ENet** binds **upstream 1.3.18** (not the zpl fork) and links `system:enet` on macOS/Linux (bundled
  `.lib` on Windows). Build upstream with CMake (`cmake -S enet -B b -G Ninja && cmake --build b` → `libenet.a`) and
  link with `odin build . -extra-linker-flags:"-L<dir with libenet.a>"`. IPv4 only (`Address{host: u32, port: u16}`),
  flags are a bit_set (`enet.packet_create(ptr, len, {.RELIABLE})`), events `.CONNECT/.RECEIVE/.DISCONNECT` (no
  `DISCONNECT_TIMEOUT`). Validated echo with 50 reliable + 50 unsequenced packets, and against a zpl-fork C server.
- librg/zpl: no bindings. Compile a C file with the implementation into a static library
  (`cc -c -O2 librg_impl.c && ar rcs liblibrg.a librg_impl.o`) and declare only the procs you need:
  `foreign import librg "liblibrg.a"` + `@(default_calling_convention="c") foreign librg { librg_world_create ::
  proc() -> rawptr --- … }`. Callbacks are `proc "c"` (set `context = runtime.default_context()` inside). Odin's own
  `core:encoding/json`, `core:mem` arenas and `core:thread` cover most of zpl, so prefer them. See odin, odin-targets.

## Testing

- Two processes on one machine: start the server in the background and run the client against `127.0.0.1` (also try
  `::1` with the fork). Use different ports per test and kill stray servers afterwards (`pkill -f "app server"`;
  don't run `pkill -f` through `ssh host 'bash -c …'` with a pattern that also matches the command line, because it
  kills its own shell).
- Across machines: the server must listen on a reachable interface (`ENET_HOST_ANY`) and inbound UDP must be allowed.
  Validated: Mac → Jetson over a work tunnel (RTT 37 ms; the server saw the tunnel NAT address), Linux server
  ← Mac on the LAN failed (host firewall drops inbound UDP) but the reverse direction worked (5 ms). When connect
  times out, check routing first (can the hosts reach each other at all?), then the firewall on the server, then the
  port.
- NAT: ENet clients behind NAT work against a public server (the client sends first, and keepalive pings hold the
  mapping). Peer-to-peer between two NATed hosts needs hole punching via a rendezvous server (both send to each
  other's public ip:port at the same time) or a relay. ENet has no built-in support; use a VPN (WireGuard/Tailscale)
  for development. Raise `enet_peer_timeout` for mobile or Wi-Fi links.

## Security

- ENet packets are plaintext and unauthenticated, and the connect `data` is not a credential. Anyone on the path can read
  or spoof. Options: encrypt payloads per peer after a key exchange (libsodium `crypto_kx` + `crypto_secretbox` /
  `crypto_aead_xchacha20poly1305`, with nonces/counters against replay), intercept raw datagrams with
  `enet_host_set_intercept`, or use a transport with security built in (QUIC: msquic/quiche; DTLS; GameNetworkingSockets;
  WebRTC data channels for browsers). Browsers cannot use raw UDP, so ENet doesn't work from WebAssembly.
- Treat every received byte as hostile: check lengths before `memcpy` (librg callbacks get `librg_event_size_get`),
  bound array indices from the network (entity ids!), and rate-limit connects and packets per peer. Never `eval` or
  parse untrusted JSON5 into fixed buffers without limits. The server is authoritative: validate client-owned entity
  updates (speed and teleport checks) before applying them.
