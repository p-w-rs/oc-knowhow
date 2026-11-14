---
name: zenoh-ros2
description: Connect Zenoh applications to ROS 2 systems — rmw_zenoh (RMW_IMPLEMENTATION=rmw_zenoh_cpp, rmw_zenohd router, key expressions <domain>/<topic>/<type>/<RIHS01 hash>, @ros2_lv liveliness graph, attachment format, ZENOH_ROUTER_CONFIG_URI / ZENOH_SESSION_CONFIG_URI / ZENOH_CONFIG_OVERRIDE, shared memory, QoS mapping), talking to rmw_zenoh nodes from plain Python/C/Rust Zenoh (CDR with rclpy.serialization or by hand, type hashes, publishing, calling services), zenoh-bridge-ros2dds / zenoh-plugin-ros2dds for DDS-based ROS 2 (topic→key mapping, namespace, allow/deny, services and actions as queryables, CycloneDDS, discovery range), choosing between them, domain IDs, and installing ROS 2 (Lyrical/Kilted/Jazzy) with apt or Pixi/RoboStack. Load before bridging Zenoh and ROS 2.
---

# Zenoh ↔ ROS 2

The user's systems are Zenoh-first; ROS 2 is something to interface with. Read the **zenoh** skill first (sessions,
key expressions, routers). Recording either side to files: **mcap**. Environments: **pixi**. Ports, firewalls,
tunnels: **c-networking**. The reference library holds `rmw-zenoh-source` (docs/design.md: key expressions,
liveliness, attachment format, QoS; default configs), `zenoh-ros2dds-source` (bridge README, DEFAULT_CONFIG.json5,
key mapping), `rosbag2-mcap-source` and the `ros2-docs-lyrical` link: `library_search` them before writing mappings.

## 0. Versions and install (as of 13 Nov 2026, verify)

| ROS 2 distro | Released | EOL | Tier-1 Ubuntu | rmw_zenoh (RoboStack build) |
|---|---|---|---|---|
| **Lyrical Luth** (LTS, newest) | 22 May 2026 | May 2031 | **26.04 Resolute** amd64/arm64 (24.04 Noble is Tier 3 = source only) | 0.10.6 |
| Kilted Kaiju | 23 May 2025 | Dec 2026 | 24.04 Noble | 0.6.9 |
| Jazzy Jalisco (LTS) | 23 May 2024 | May 2029 | 24.04 Noble | 0.2.11 |
| Humble Hawksbill (LTS) | 23 May 2022 | May 2027 | 22.04 Jammy | — |

Sources: https://docs.ros.org/en/lyrical/Releases.html and `Releases/lyrical/supported-platforms` in ros2_documentation.
rmw_zenoh has branches `humble`, `jazzy`, `kilted`, `lyrical`, `rolling` (tags up to 0.14.x on rolling): read
`docs/design.md` and `README.md` **on the branch of your distro** (https://github.com/ros2/rmw_zenoh/tree/lyrical).
zenoh-plugin-ros2dds: 1.10.2 (same versioning as Zenoh). Default RMW is still `rmw_fastrtps_cpp` in Lyrical.

**"Ubuntu with the latest ROS 2"** means Lyrical on 26.04 or (very common on robots and Jetsons, Ubuntu 24.04)
Jazzy/Kilted. Ask which distro the robot runs: rmw_zenoh is only compatible between nodes of the **same distro**
(type hashes and the key format can change between distros), and ROS messages differ between distros.

- apt (on the robot): `sudo apt install ros-$ROS_DISTRO-rmw-zenoh-cpp` (also builds its vendored Zenoh).
- Pixi + RoboStack (any Linux incl. non-Ubuntu, macOS; no root; tested on Arch-based x86_64):
  ```toml
  [workspace]
  channels = ["robostack-lyrical", "conda-forge"]     # robostack-kilted / -jazzy / -humble also exist
  platforms = ["linux-64"]                             # linux-aarch64, osx-arm64 also built
  [dependencies]
  ros-lyrical-ros-base = "*"
  ros-lyrical-rmw-zenoh-cpp = "*"
  ros-lyrical-rmw-cyclonedds-cpp = "*"                 # for the DDS bridge (section 3)
  ros-lyrical-demo-nodes-cpp = "*"
  ros-lyrical-rosbag2-storage-mcap = "*"
  [pypi-dependencies]
  eclipse-zenoh = "*"                                  # plain Zenoh Python next to rclpy
  ```
  `pixi run ros2 …` activates the environment (`ROS_DISTRO=lyrical`, `AMENT_PREFIX_PATH`). RoboStack pins
  `libzenohc`/`zenohd` to the version rmw_zenoh was built with (1.10.1 here), while PyPI `eclipse-zenoh` was 1.10.2:
  fine, 1.x patch releases interoperate. Python was 3.14 in that environment.
- zenoh-bridge-ros2dds: not on conda-forge/RoboStack. Use the release zip
  (`https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds/releases/download/1.10.2/zenoh-plugin-ros2dds-1.10.2-x86_64-unknown-linux-gnu-standalone.zip`,
  also aarch64, musl, macOS), the Eclipse apt repo (`sudo apt install zenoh-bridge-ros2dds`), Docker
  `eclipse/zenoh-bridge-ros2dds:latest`, or build it as a ROS package (colcon).

## 1. Which way?

| Situation | Use |
|---|---|
| You control the ROS 2 deployment (same distro everywhere) | **rmw_zenoh**: every node speaks Zenoh, no DDS. Plain Zenoh apps join the router directly. |
| Robot runs default DDS (Fast DDS/Cyclone) and you can't change it | **zenoh-bridge-ros2dds** on the robot (Cyclone recommended for the nodes), Zenoh everywhere else |
| Several robots, WAN, Wi-Fi, NAT | either; bridge with `namespace: "/botX"` per robot is the classic pattern; rmw_zenoh with router-to-router `connect` works too |
| Zenoh-native app needs a few ROS topics | both work; rmw_zenoh needs the type hash + attachment, the bridge just takes CDR on `topic` |

The two key schemes are **different** (rmw_zenoh: `0/chatter/<type>/<hash>` with attachments; bridge: `chatter`),
so rmw_zenoh nodes and bridge-exposed DDS nodes do not see each other without extra glue.

## 2. rmw_zenoh

```sh
ros2 run rmw_zenoh_cpp rmw_zenohd                       # router, listens tcp/[::]:7447; start it first
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
ros2 run demo_nodes_cpp talker & ros2 run demo_nodes_cpp listener
ros2 daemon stop                                        # after switching RMW, else `ros2 topic list` shows a stale graph
```
Tested on Lyrical: talker/listener, `ros2 topic pub`, services, `ros2 bag record/play`. Nodes are **peers** that
connect to the router at `tcp/localhost:7447` for discovery, then talk peer-to-peer (`tcp/localhost:0` listener);
multicast scouting is off in both default configs, gossip on. `ZENOH_ROUTER_CHECK_ATTEMPTS` (README): unset = check
once, `0` = wait for the router forever, `N>0` = N tries 1 s apart, `<0` = skip the check. After the check a node
continues anyway and connects when a router appears later.

Config (defaults ship in `share/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_{ROUTER,SESSION}_CONFIG.json5`):
- `ZENOH_ROUTER_CONFIG_URI=/abs/router.json5`, `ZENOH_SESSION_CONFIG_URI=/abs/session.json5` (copy the defaults, edit).
- `ZENOH_CONFIG_OVERRIDE='key/path=value;key2=value2'` on top, e.g. two hosts:
  `ZENOH_CONFIG_OVERRIDE='connect/endpoints=["tcp/192.168.0.3:7447"]' ros2 run rmw_zenoh_cpp rmw_zenohd` on one router,
  or a node as client of a remote router: `ZENOH_CONFIG_OVERRIDE='mode="client";connect/endpoints=["tcp/192.168.1.1:7447"]'`.
- Without any router: `ZENOH_ROUTER_CHECK_ATTEMPTS=-1` + `ZENOH_CONFIG_OVERRIDE='scouting/multicast/enabled=true'`.
- Shared memory: `ZENOH_CONFIG_OVERRIDE='transport/shared_memory/enabled=true'` on **all** nodes (and router);
  per-node pool `transport/shared_memory/transport_optimization/pool_size` (README: 48 MiB default),
  threshold `…/message_size_threshold`; size `/dev/shm` for all nodes; Docker `--ipc=host`. Falls back to the
  network transparently.
- `RMW_ZENOH_BUFFER_POOL_MAX_SIZE_BYTES` (serialization buffer pool, 8 MiB default).
- `rmw_zenohd` 0.10.6 logs warnings that `routing.router.peers_failover_brokering` and `routing.peer.mode`/`linkstate`
  are deprecated: harmless (its own default file still has them). It is a normal Zenoh router: a plain `zenohd` with
  an equivalent config also works, and so does router-to-router (tested: Jetson `zenohd` 1.10.2 ↔ `rmw_zenohd` 1.10.1).

### Key expressions and graph (from `docs/design.md`, confirmed on the wire)

- Topic/service key: `<domain_id>/<fully_qualified_name without leading />/<pkg>::msg::dds_::<Type>_/RIHS01_<hash>`,
  e.g. `0/chatter/example_interfaces::msg::dds_::String_/RIHS01_5509d866…` (Lyrical's `demo_nodes_cpp` talker uses
  `example_interfaces/msg/String`!), `0/robot1/status/std_msgs::msg::dds_::String_/RIHS01_df668c74…`,
  `0/cmd_vel/geometry_msgs::msg::dds_::Twist_/RIHS01_9c45bf16…`, `0/imu/sensor_msgs::msg::dds_::Imu_/RIHS01_7d9a00ff…`,
  `0/add_two_ints/example_interfaces::srv::dds_::AddTwoInts_/RIHS01_e118de6b…`.
- Type hash (REP-2016, `RIHS01_` + SHA-256): `$PREFIX/share/<pkg>/msg/<Type>.json` → `"type_hashes"[…]["hash_string"]`
  (first entry = the type itself), or read it from the liveliness token of an existing endpoint. A wrong hash = no match.
- Graph = liveliness tokens `@ros2_lv/<domain>/<zid>/<nid>/<eid>/<kind>/<enclave>/<namespace>/<node>/<%topic>/<type>/<hash>/<qos>`,
  kind `NN` node, `MP`/`MS` publisher/subscription, `SS`/`SC` service server/client; `/` in names mangled to `%`.
  `@` makes it hermetic: subscribe with `@ros2_lv/0/**`, not `**`.
- Every publication and request carries an **attachment**: int64 sequence number LE, int64 source timestamp (ns) LE,
  uint8 GID length (16), 16-byte GID. **Subscribers reject samples without it** (tested: listener logs
  `[rmw_zenoh_cpp]: Unable to obtain attachment for topic '0/chatter/…'` and drops the message).
- Services = queryables declared complete; clients `get` with `target=ALL_COMPLETE`, request attachment, the reply
  echoes the sequence number and GID. Actions = their component services/topics (`<name>/_action/send_goal` etc.).
- QoS: RELIABLE/BEST_EFFORT map to Zenoh reliability (only matters if a UDP link exists); KEEP_ALL + RELIABLE →
  `CongestionControl::BLOCK`; TRANSIENT_LOCAL → advanced publisher cache + advanced subscriber history; DEADLINE,
  LIFESPAN unimplemented; only AUTOMATIC liveliness. In Zenoh there are no "incompatible QoS": everything matches.
- Domain IDs are just the first key chunk (`ROS_DOMAIN_ID`, default 0); same router, different domains don't mix.

### Plain Zenoh ↔ rmw_zenoh (tested, Python; same logic in C/Rust)

```python
import json, os, struct, time, zenoh
from rclpy.serialization import deserialize_message, serialize_message   # CDR without creating a ROS node
from rosidl_runtime_py.utilities import get_message

conf = zenoh.Config()
conf.insert_json5("mode", '"client"')
conf.insert_json5("connect/endpoints", json.dumps(["tcp/127.0.0.1:7447"]))   # the rmw_zenohd router
with zenoh.open(conf) as s:
    def on_sample(smp):                                  # subscribe: key → type → CDR decode
        _dom, rest = str(smp.key_expr).split("/", 1)
        topic, dds_type, _hash = rest.rsplit("/", 2)
        pkg, kind, _, name = dds_type.split("::")        # example_interfaces::msg::dds_::String_
        msg = deserialize_message(smp.payload.to_bytes(), get_message(f"{pkg}/{kind}/{name[:-1]}"))
        seq, src_ns, _ = struct.unpack_from("<qqB", smp.attachment.to_bytes())
        print(f"/{topic}", seq, msg)
    sub = s.declare_subscriber("0/chatter/**", on_sample)   # or "0/**" for every topic of domain 0

    # publish to ROS subscribers: exact key (with hash) + CDR + attachment
    key = "0/chatter/example_interfaces::msg::dds_::String_/RIHS01_5509d866a579951f2fc6c19577c32605ba16f308cae7b498341d79536d4eb06b"
    pub, gid = s.declare_publisher(key), os.urandom(16)
    String = get_message("example_interfaces/msg/String")
    for seq in range(1, 6):
        att = struct.pack("<qqB", seq, time.time_ns(), 16) + gid
        pub.put(serialize_message(String(data=f"Hello from plain Zenoh: {seq}")), attachment=att)
        time.sleep(0.2)
```
Calling a service (tested, `AddTwoInts` → `sum=42`): `s.get(service_key, payload=serialize_message(req),
attachment=att, target=zenoh.QueryTarget.ALL_COMPLETE, timeout=3)` and `deserialize_message(reply.ok.payload.to_bytes(),
AddTwoInts.Response)`. `ros2 topic pub` / `ros2 topic echo` work as the other end for checks.

Without ROS installed (a Jetson or MCU with only Zenoh): decode CDR yourself or with a pure-Python library
(PyPI `rosbags` 0.11.x has CDR (de)serializers and built-in type stores; `pycdr2` 1.0 (BSD-3) for hand-written
IDL dataclasses; `mcap-ros2-support` decodes from a `.msg` definition text; none of these were run here, check their
docs). CDR = 4-byte encapsulation header (`00 01 00 00` = little-endian
CDR) then fields with natural alignment relative to the end of the header; a string is uint32 length (incl. NUL) +
bytes + NUL. Tested on aarch64 without ROS: `payload[8:8+n-1]` for `String`, `struct.unpack_from("<6d", payload, 4)`
for `Twist`. Hand decoding is fine for a few fixed types; use a library for anything nested or with sequences.
Get the type hash from the robot (liveliness tokens) rather than computing it.

## 3. zenoh-bridge-ros2dds (ROS 2 on DDS)

```sh
export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST   # nodes AND bridge: keep DDS on the host, Zenoh crosses the network
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp      # the bridge embeds CycloneDDS; tested with Cyclone nodes
zenoh-bridge-ros2dds                                # router mode, listens tcp/[::]:7447; on the robot
zenoh-bridge-ros2dds -e tcp/<robot-ip>:7447         # on the operator host: ROS topics appear locally too
```
Options (`--help`, 1.10.2): `[MODE]` (router default; peer, client), `-c config.json5`, `-e`, `-l`, `-n/--namespace`,
`-d/--domain` (default `$ROS_DOMAIN_ID`), `--ros-localhost-only`, `--ros-automatic-discovery-range`,
`--ros-static-peers`, `--no-multicast-scouting`, `--enable-shm`, `--pub-max-frequency '<regex>=<Hz>'`,
`--queries-timeout-default`, `-r/--rest-http-port`, `-w/--watchdog`. Run it **inside the ROS environment** (needs
`ROS_DISTRO`; without it: `ROS_DISTRO environment variable is not set. Assuming 'iron'`).

Mapping (tested): topic `/chatter` ↔ Zenoh key `chatter` (fully qualified name without the leading `/`, prefixed by
the bridge `namespace` if set); payload = the raw CDR **including** the 4-byte header; **no attachment needed**;
publishing to `from_zenoh` reached a DDS `ros2 topic echo /from_zenoh` once that subscriber existed (routes are created
per discovered DDS reader/writer). Services → Zenoh queryables on the service name: `s.get("add_two_ints",
payload=serialize_message(AddTwoInts.Request(a=20, b=22)))` → `sum=42`. Actions → `<name>/_action/{send_goal,cancel_goal,
get_result,feedback,status}`. Bridge admin space (with `-r 8000`):
`curl 'localhost:8000/@/*/ros2/route/**'` (routes with `ros2_name`, `ros2_type`, `zenoh_key_expr`), `@/*/ros2/node/**`,
`@/*/ros2/dds/**`.

Config file keys (`plugins/ros2dds/…`, see `DEFAULT_CONFIG.json5` at the tag): `nodename`, `namespace`, `domain`,
`ros_localhost_only`, `ros_automatic_discovery_range`, `ros_static_peers`, `shm_enabled`, `allow` **or** `deny`
with regex lists for `publishers`, `subscribers`, `service_servers`, `service_clients`, `action_servers`,
`action_clients`; `pub_max_frequencies` (`".*/laser_scan=5"`), `pub_priorities` (`"/scan=1:express"`),
`reliable_routes_blocking`, `queries_timeout` (default, transient_local_subscribers, services, actions),
`transient_local_cache_multiplier`. Plus normal Zenoh keys (`mode`, `connect`, `listen`, `plugins/rest/http_port`).

Pitfalls found in validation:
1. **DDS discovery over the LAN failed** on a host whose firewall drops multicast: the bridge saw 0 writers
   (`Publish update on 'ros_discovery_info' with 0 writers`). `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST` for nodes and
   bridge fixed it (and is what the README recommends anyway: no DDS between bridged hosts, or traffic loops).
2. **Fast DDS nodes were not discovered** by the bridge on the same host (only Cyclone participants appeared in
   `@/*/ros2/dds/**`); with `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` everything worked. Fast DDS's default
   shared-memory/localhost transports are the likely reason (not investigated further); use Cyclone on bridged robots
   as the README advises, or test a UDP-only Fast DDS profile.
3. A bridge per robot with `namespace: "/botX"` prefixes **all** names (incl. `/tf`, `/rosout`).

## 4. Debugging checklist

- `curl localhost:8000/@/*/router` (zenohd/bridge with REST) or `s.get("@/*/router")`: who is connected.
- `s.liveliness().get("@ros2_lv/0/**")`: the rmw_zenoh graph, with exact keys and type hashes.
- Subscribe to `0/**` (rmw_zenoh) or `**` (bridge) and print keys before decoding anything.
- Same `ROS_DOMAIN_ID` everywhere; same distro for rmw_zenoh; `ros2 daemon stop` after RMW changes.
- Firewalls: 7447/tcp for Zenoh; DDS needs UDP 7400+ and multicast, which is why keeping DDS on localhost helps.
- Nothing crosses two networks → router-to-router `connect`, a VPN, or (tested) SSH port forwards between routers.
