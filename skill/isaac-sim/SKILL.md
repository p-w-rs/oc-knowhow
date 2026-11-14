---
name: isaac-sim
description: Run NVIDIA Isaac Sim 6.x (Kit 110, Omniverse RTX) and Isaac Lab 3.x — pip install via Pixi (Python 3.12, glibc 2.35+, pypi.nvidia.com index strategy, torch cu130, EULA env, libxml2 fix), GPU/driver requirements and VRAM checks, headless standalone scripts (SimulationApp, isaacsim.core.experimental stage/app utils, SimulationManager, Articulation, GroundPlane), USD basics (stage, prims, references, variants, units/up-axis, physics schemas, articulation roots), URDF/MJCF importers (URDFImporter, Physics variant sets), RTX cameras (RtxCamera + CameraSensor annotators), RTX lidar, ROS 2 bridge (bundled Jazzy/Humble libs, env before launch, graph_api helpers for clock/joint states/camera, joint commands back in, RoboStack client, zenoh-bridge-ros2dds), livestream/WebRTC, Replicator synthetic data, containers (nvcr.io/nvidia/isaac-sim), Newton vs PhysX backends and physics= presets, Isaac Lab 3 training and play via Pixi (isaaclab train/play --rl_library rsl_rl, dependency overrides, task names, tensorboard scalars, --video, measured steps/s and VRAM), startup/shader-cache timings, typical errors and the bundled agent skills. Load before installing, scripting or debugging Isaac Sim or Isaac Lab.
---

# Isaac Sim 6 and Isaac Lab 3

Isaac Sim is NVIDIA's Omniverse (Kit) robot simulator: USD scenes, PhysX 5 or Newton physics, RTX path-traced/
real-time sensors, ROS 2 bridge, Replicator SDG. **Isaac Lab** is the RL/IL framework on top. Lighter alternatives:
**mujoco** (accurate rigid-body, MJWarp/Playground/mjlab), **genesis** (GPU multi-material). ROS 2 + Zenoh:
**zenoh-ros2**; logs: **mcap**; training: **ml-training**; deployment: **ml-deploy**; envs: **pixi**.
References: `isaacsim-source` (repo at tag: `source/standalone_examples`, extension `config/python_api.md`, skills),
`isaaclab-source` (`docs/source`, `scripts`, `source/isaaclab*`), docs site (link):
https://docs.isaacsim.omniverse.nvidia.com/latest/. `library_search` them for API signatures, e.g.
`library_search query="CameraSensor annotators get_data" sources=["isaacsim-source"]`.

## 0. Ground truth first (as of 13 Nov 2026, verify)

| Item | State |
|---|---|
| Isaac Sim | **6.2.0** (PyPI `isaacsim==6.2.0.0`, 13 Oct 2026; GitHub tag `v6.2.0`; `v7.0.0a1` pre-release). Kit 110. 5.1 was the last 5.x. Source on GitHub (Apache-2.0 for the repo; Kit/RTX/PhysX binaries under the NVIDIA Omniverse EULA). |
| Python | **3.12 only** (`==3.12.*`); wheels `manylinux_2_35` x86_64/aarch64 + Windows → **glibc ≥ 2.35**. |
| GPU/driver | RTX GPU (no GTX/Tesla-without-RTX for rendering); the 6.2 requirements page lists Linux driver 595.58.03, Isaac Lab 3.0 docs require only **≥ 580.65.06** (torch cu130). **Tested: 580.159.03 runs Isaac Sim 6.2 + Isaac Lab 3.0 fine** (Ubuntu 24.04, RTX PRO 6000 Blackwell: training, RTX video, ROS 2 bridge); also Arch (glibc 2.44, driver 615.78). Ubuntu 22.04/24.04 supported (22.04 deprecated). |
| Isaac Lab | **3.0.0** (PyPI `isaaclab`, tag `v3.0.0`), targets Isaac Sim 6.2, Python 3.12, torch 2.11.0, BSD-3 (mimic: Apache-2.0). Multi-backend: PhysX, Newton, OvPhysX; some workflows run **without** Isaac Sim (Newton). |
| Bundled agent skills | `site-packages/isaacsim/skills/` (~45 SKILL.md: headless deployment, camera, sensors, ROS 2 bridge, URDF/MJCF→USD, physics, troubleshooting, web viewer…) and Isaac Lab `skills/user/*` in the repo. Read them: they track Kit 110 APIs. |

**API churn**: 4.5 renamed `omni.isaac.*` → `isaacsim.*`; 6.0 moved new code to `isaacsim.core.experimental.*`
(prims/objects/utils), `isaacsim.core.simulation_manager`, and cameras to `isaacsim.sensors.experimental.rtx`.
`isaacsim.core.api.World`, `isaacsim.core.utils.stage`, `isaacsim.sensors.camera.Camera` are deprecated in Kit 110.
Code from blogs (`from omni.isaac.core import World`) will not load.

## 1. Install with Pixi (validated: 2 min 17 s, 23 GB env)

```toml
[workspace]
channels = ["conda-forge"]
platforms = [{ platform = "linux-64", cuda = "13.0", glibc = "2.35" }]
[dependencies]
python = "3.12.*"
libxml2 = "<2.14"                        # provides libxml2.so.2 (see errors)
[pypi-options]
extra-index-urls = ["https://pypi.nvidia.com"]
index-strategy = "unsafe-best-match"     # else: "no version of mujoco-usd-converter==0.6.1"
[pypi-dependencies]
torch = { version = "==2.11.0", index = "https://download.pytorch.org/whl/cu130" }   # version NVIDIA documents
isaacsim = { version = "==6.2.0.0", extras = ["all", "extscache"] }                # extras: ros2, rl, compatibility-check
[activation.env]
OMNI_KIT_ACCEPT_EULA = "YES"             # otherwise an interactive EULA prompt on first import
```
`pip install "isaacsim[all,extscache]==6.2.0.0" --extra-index-url https://pypi.nvidia.com` is NVIDIA's form. The
`isaacsim` package pins its own `mujoco` 3.12.0, `newton` 1.6.1, `warp-lang` 1.19.0 and USD converters: give it its own
environment, never mix with your MuJoCo/Genesis env. CLI: `isaacsim` (full app), `isaacsim isaacsim.exp.full.streaming
--no-window` (headless WebRTC), `isaacsim isaacsim.exp.compatibility_check`. Alternatives: the standalone zip
(`./python.sh script.py`, `./isaac-sim.sh`), containers `nvcr.io/nvidia/isaac-sim:<ver>` (NVIDIA Container Toolkit,
`--gpus all`, mount cache dirs to keep shader caches), cloud images (AWS/Azure/GCP marketplace, Brev).

**Check the GPU first**: `nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total --format=csv` and
`nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv`. Our single-robot RTX scene peaked at
0.85 GB VRAM and 7.5 GB host RAM; Isaac Lab RL with thousands of envs and cameras needs 10–40 GB. NVIDIA advises
staying under 90 % VRAM; Kit leaks if stages are not cleared between episodes.

## 2. Headless standalone script (tested: Go2 URDF → USD, PD stand, RTX frame)

```python
from isaacsim import SimulationApp
app = SimulationApp({"headless": True, "width": 960, "height": 540})   # FIRST; import omni/isaacsim modules after
import numpy as np
import isaacsim.core.experimental.utils.app as app_utils
import isaacsim.core.experimental.utils.stage as stage_utils
from isaacsim.core.simulation_manager import SimulationManager
from isaacsim.core.experimental.objects import GroundPlane
from isaacsim.core.experimental.prims import Articulation
from isaacsim.sensors.experimental.rtx import RtxCamera, CameraSensor
from isaacsim.asset.importer.urdf import URDFImporter, URDFImporterConfig
from pxr import UsdLux, UsdPhysics

usd = URDFImporter(URDFImporterConfig(urdf_path="go2/urdf/go2.urdf", usd_path="out", fix_base=False,
    joint_drive_type="force", joint_target_type="position",
    override_joint_stiffness=60.0, override_joint_damping=3.0)).import_urdf()      # 2.1 s -> out/go2/go2.usda
stage = stage_utils.create_new_stage(); stage_utils.set_stage_up_axis("Z"); stage_utils.set_stage_units(meters_per_unit=1.0)
UsdLux.DomeLight.Define(stage, "/World/Dome").CreateIntensityAttr(800.0)      # no light = black frames
GroundPlane("/World/Ground")
stage_utils.add_reference_to_stage(usd, "/World/Go2", variants=[("Physics", "physx")])   # see pitfall
cam = RtxCamera("/World/Cam", positions=[[1.4, -1.4, 0.8]], orientations=[wxyz])   # camera looks down -Z, +Y up
sensor = CameraSensor(cam, resolution=(540, 960), annotators=["rgb"])          # (height, width)
SimulationManager.setup_simulation(dt=1 / 200, device="cuda")
app_utils.play()
root = [p.GetPath().pathString for p in stage.Traverse() if p.HasAPI(UsdPhysics.ArticulationRootAPI)][0]
robot = Articulation(root)                                  # /World/Go2/Geometry/base here
robot.set_dof_positions(q0); robot.set_dof_position_targets(q0)   # (1, num_dofs); robot.dof_names gives the order
for _ in range(400): app_utils.update_app()                 # physics + render: 24 fps with RTX on a 5090
rgb, info = sensor.get_data("rgb")                          # warp array (H,W,3) uint8, None during warm-up
SimulationManager.step(steps=1000)                          # physics only: 4.4 s
app_utils.stop(); app.close()
```
Measured on powerslabs (RTX 5090): `SimulationApp` startup **12 s first run, 91 s on the run that first loaded the
asset-converter extension (cache warm-up), 6.7 s warm**; whole script 29 s. NVIDIA's skills warn that the first
launch compiles MDL shaders for 5–15 min with large scenes. Keep one long-lived process; don't restart per episode.
Dof order is per joint type (4 hips, 4 thighs, 4 calves), not the URDF order: always index by `robot.dof_names`.

## 3. USD essentials

- Stage = layers composed; prims at paths (`/World/Go2`); `references`/`payloads` pull files in; **variant sets**
  select alternatives. Units: `metersPerUnit` and `upAxis` metadata (Isaac default Z-up, m; USD-from-DCC often cm/Y-up:
  fix on import). Quaternions in Isaac APIs are **w,x,y,z**.
- Physics schemas: `UsdPhysics.RigidBodyAPI`, `CollisionAPI`, `MassAPI`, joints (`PhysicsRevoluteJoint`…),
  `DriveAPI` (stiffness/damping = PD gains), `ArticulationRootAPI` (one per articulation), `PhysicsScene`; PhysX and
  Newton add their own `PhysxSchema`/`Newton*API`. Edit with `pxr` (`Usd`, `UsdGeom`, `UsdPhysics`, `Sdf`) directly.
- Assets: `isaacsim.storage.native.get_assets_root_path()` (NVIDIA's S3/CDN asset root; needs internet; first fetch
  is slow) — Franka, Carter, warehouses, etc. Local copies speed up CI.

## 4. Importers (URDF, MJCF)

- `URDFImporterConfig` fields: `urdf_path`, `usd_path` (output dir; defaults to the URDF folder), `merge_fixed_joints`,
  `merge_mesh`, `collision_from_visuals`, `collision_type` ("Convex Hull"|"Convex Decomposition"|"Bounding Sphere"|
  "Bounding Cube"), `allow_self_collision`, `fix_base` (None keeps the source), `link_density`, `joint_drive_type`,
  `joint_target_type`, `override_joint_stiffness/damping`, `ros_package_paths`, `run_asset_transformer`,
  `run_multi_physics_conversion`. MJCF: `isaacsim.asset.importer.mjcf` with the same pattern (uses
  `mujoco-usd-converter`). No xacro: run `xacro robot.xacro > robot.urdf` first, or import from a running
  `robot_state_publisher` (`isaacsim.ros2.urdf`).
- **Pitfall (cost us a crash)**: the converter writes `go2.usda` with `variantSet "Physics" = {mujoco, none, physics,
  physx}` and **no default selection**. Referencing it plainly gives a robot with no rigid bodies or articulation
  root, and `Articulation(...)` then fails with `AttributeError: 'NoneType' object has no attribute 'strip'`. Pass
  `variants=[("Physics", "physx")]` (or `"physics"` for Newton/generic).
- Re-importing into the same `usd_path` writes `go2_1/`, `go2_2/` instead of overwriting: reuse or delete the output.
- Isaac Lab equivalent: `scripts/tools/convert_urdf.py` / `convert_mjcf.py` (config-driven).

## 5. Sensors, ROS 2, streaming, SDG

- Cameras: `RtxCamera` (USD camera + `OmniSensorAPI`) + `CameraSensor` (render product + annotators `rgb`,
  `distance_to_image_plane`, `distance_to_camera`, `normals`, `semantic_segmentation`, `instance_segmentation`,
  `bounding_box_2d_tight`, `pointcloud`, `camera_params`); `TiledCameraSensor` for many envs in one render;
  OpenCV distortion via `OmniLensDistortionOpenCvPinholeAPI`/`…FisheyeAPI` attributes. Focal length/aperture are in
  tenths of a scene unit.
- RTX lidar/radar: `isaacsim.sensors.experimental.rtx` lidar classes with configs in `SUPPORTED_LIDAR_CONFIGS`
  (vendor profiles); PhysX raycast lidar is the cheap alternative. Contact/IMU sensors: `isaacsim.sensors.experimental.physics` (old `isaacsim.sensors.physics`).
- ROS 2: see section 6 (tested).
- Remote viewing: `isaacsim isaacsim.exp.full.streaming --no-window` + the Isaac Sim WebRTC Streaming Client (native
  app) or the web viewer stack (Chromium, `http://HOST:8210`); WebRTC needs UDP reachability (firewalls/VPN; use an SSH
  or WireGuard tunnel only for signalling, media still needs UDP). Over plain ssh, render to files instead.
- Replicator (`omni.replicator.core as rep`): randomize poses/lights/materials per frame (`rep.trigger.on_frame`),
  writers (`BasicWriter`, KITTI, COCO) for labeled datasets (see **datasets** for curation).

## 6. ROS 2 bridge (tested: Go2 + clock/joint states/camera out, joint commands in, Zenoh)

- **Bundled ROS**: `isaacsim.ros2.core/{humble,jazzy}/lib` (rclpy, std/sensor/geometry/nav/tf2 msgs,
  `rmw_fastrtps_cpp`, `rmw_cyclonedds_cpp`; no rmw_zenoh). With `ROS_DISTRO` unset it picks by Ubuntu version (22→humble,
  24→jazzy; other distros: error + humble) and logs `Attempting to load internal rclpy for ROS Distro: jazzy`. The zip's
  `python.sh` sources `setup_ros_env.sh`; **the pip/Pixi install does not**: export the env yourself before Python starts:
  ```bash
  EXT=$PWD/.pixi/envs/default/lib/python3.12/site-packages/isaacsim/exts/isaacsim.ros2.core   # in the workspace
  export ROS_DISTRO=jazzy RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_DOMAIN_ID=77
  export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$EXT/jazzy/lib
  env -u DISPLAY pixi run python ros_bridge.py
  ```
  System ROS instead (custom msgs, `rmw_zenoh_cpp`, see **zenoh-ros2**): source `/opt/ros/<distro>/setup.bash` in the
  parent shell first; never patch `LD_LIBRARY_PATH` in a running process.
- **Graphs from Python** (`isaacsim.ros2.nodes` helpers build the OmniGraph; topics tick **only while playing**):
  ```python
  app_utils.enable_extension("isaacsim.ros2.bridge"); app.update()     # after SimulationApp, before importing below
  from isaacsim.ros2.nodes import (Ros2ClockGraphConfig, Ros2JointStatesGraphConfig, Ros2CameraGraphConfig,
      create_ros2_clock_graph, create_ros2_joint_states_graph, create_ros2_camera_graph)
  create_ros2_clock_graph(Ros2ClockGraphConfig())                       # /clock (sim time)
  create_ros2_joint_states_graph(Ros2JointStatesGraphConfig(articulation_root=root, publish_joint_states=True,
      subscribe_joint_states=True, subscribe_topic="/joint_command", move_robot_on_subscribe=True))
  create_ros2_camera_graph(Ros2CameraGraphConfig(camera_prim="/World/Cam", frame_id="cam", rgb_topic="/rgb",
      publish_depth=False))                                             # + /camera_info; any UsdGeom.Camera works
  SimulationManager.setup_simulation(dt=1/200, device="cuda"); app_utils.play()
  while running: app_utils.update_app()
  ```
  Also `Ros2{Tf,Odometry,RtxLidar,RtxRadar}GraphConfig`. Hand-built: `og.Controller.edit` with `isaacsim.ros2.bridge.
  ROS2Publish*`/`ROS2Subscribe*`/`ROS2CameraHelper` nodes (repo `standalone_examples/api/isaacsim.ros2.bridge/*.py`).
- **Measured** (Go2, RTX on, shared GPU): topics `/clock /joint_states /joint_command /rgb /camera_info`; one message
  per app frame → 8.4 Hz clock/joint_states, 4.1 Hz rgb at 7–8 app fps; `/rgb` is **1280×720 rgb8** (2.76 MB; the
  helper's render product ignores the app width/height); one app update = 1/60 s sim time; joint names in Isaac dof
  order (4 hips, 4 thighs, 4 calves); sim time in `header.stamp`. Warning `Forcing fy to fx` = non-square aperture.
- **Client via Pixi RoboStack** (same distro): channels `https://prefix.dev/robostack-jazzy` + conda-forge,
  `ros-jazzy-ros-core ros-jazzy-ros2topic ros-jazzy-sensor-msgs ros-jazzy-rmw-fastrtps-cpp` (5 s, 0.6 GB). `ros2 topic
  list/hz/echo --once /joint_states` and an rclpy node work; commands: publish `sensor_msgs/JointState(name=[…12],
  position=[…])` on `/joint_command` → the robot's PD targets follow (FL_hip −0.003 → 0.412 rad).
- **Zenoh**: `zenoh-bridge-ros2dds` (not on conda-forge/RoboStack; GitHub release `…-x86_64-unknown-linux-gnu-
  standalone.zip`, v1.10.2): `ROS_DISTRO=jazzy ./zenoh-bridge-ros2dds -d 77 -l tcp/127.0.0.1:7448
  --no-multicast-scouting` (without `ROS_DISTRO` it assumes "iron"). Routes appear as `ROS:/rgb -> Zenoh:rgb`,
  `Zenoh:joint_command -> ROS:/joint_command`; payloads are CDR (rgb 2 764 848 B). A plain `eclipse-zenoh` client got
  all topics at full rate and drove the robot with a hand-encoded CDR JointState on key `joint_command`.
- **Pitfall (cost a hang)**: a busy `ROS_DOMAIN_ID` on a shared LAN (domain 42 carried someone's Open-RMF stack and a
  foreign 100 Hz `/clock`) gave wrong `hz` numbers, and the Isaac process stalled in that run (fine on an empty
  domain). Check `ros2 topic list` first and pick a private id. Call `ros2` via `pixi run` (else `AMENT_PREFIX_PATH` warning).

## 7. Isaac Lab 3 (tested: Pixi install, Cartpole + Go2 training, play with video)

- **Pixi install** (4 min, 25 GB env; same platform/libxml2/EULA/index settings as section 1). `isaaclab[isaacsim]`
  is **unsatisfiable without overrides** (`isaacsim-kernel==6.2.0.0` pins `urllib3==2.7.0`, isaaclab needs ≥ 2.8.0);
  mirror the repo's `[tool.uv].override-dependencies`:
  ```toml
  [pypi-options]
  extra-index-urls = ["https://pypi.nvidia.com"]
  index-strategy = "unsafe-best-match"
  prerelease-mode = "allow"
  [pypi-options.dependency-overrides]      # = IsaacLab v3.0.0 pyproject [tool.uv].override-dependencies
  numpy = ">=2"
  mujoco = "~=3.12.0"
  mujoco-warp = "~=3.12.0"
  newton = "==1.6.1"
  newton-usd-schemas = ">=0.5.0"
  usd-exchange = "==3.0.1"
  usd-optimize = "~=1.3.1"
  torch = "==2.11.0"
  torchvision = "==0.26.0"
  fsspec = ">=2026.6.0"
  packaging = ">=20,<27"
  urllib3 = ">=2.8.0"
  [pypi-dependencies]
  torch = { version = "==2.11.0", index = "https://download.pytorch.org/whl/cu130" }
  torchvision = { version = "==0.26.0", index = "https://download.pytorch.org/whl/cu130" }
  isaaclab = { version = "==3.0.0", extras = ["isaacsim", "rsl-rl", "video"] }   # also skrl, rl-games, sb3, all
  ```
  Gives isaacsim 6.2.0.0, warp-lang 1.17.0, newton 1.6.1, rsl-rl-lib 5.5.1. Other routes: `uv run --extra isaacsim
  isaaclab …` in a checkout (docs-recommended), `uv pip install isaaclab==3.0.0 --index https://pypi.nvidia.com
  --torch-backend cu130`, `./isaaclab.sh -i`.
- **Tasks**: `isaaclab list_envs` (140 tasks). 3.0 names have **no `-v0`**: `Isaac-Cartpole-Direct`, `Isaac-Cartpole`,
  `Isaac-Velocity-Flat-UnitreeGo2`, `Isaac-Velocity-Flat-AnymalD`, `…-G1`, `…-H1`; Anymal-C moved to
  `IsaacContrib-Velocity-Flat-AnymalC-Direct`. `isaaclab train --rl_library rsl_rl --task X --help` lists flags and
  the task's presets: `physics=isaacsim_physx|physx|newton_mjwarp|newton_kamino|ovphysx`, `renderer=…`, `presets=…`.
- **Train** (headless by default; logs under `./logs/rsl_rl/<experiment>/<timestamp>/`, checkpoints every 50 it):
  ```bash
  env -u DISPLAY pixi run isaaclab train --rl_library rsl_rl --task Isaac-Cartpole-Direct --num_envs 4096 \
      --max_iterations 300 --seed 42 physics=isaacsim_physx
  ```
  | Task (4096 envs, 300 it, RTX PRO 6000, shared) | Wall | steps/s | Reward | VRAM / RSS |
  |---|---|---|---|---|
  | Isaac-Cartpole-Direct | 4 min 11 s | mean 106 k | −3.9 → 4.93 plateau by it 40 | 5.2 GB / 5.2 GB |
  | Isaac-Velocity-Flat-UnitreeGo2 | 13 min 50 s | 13 k (GPU busy) → 81 k | −0.9 → −20 (it 45) → 26.5; ep len 960 | 4.4 GB / 7.7 GB |
  The Go2 dip (it 0–45) recovered by itself: judge locomotion runs after a few hundred iterations. Scalars in tfevents:
  `Train/mean_reward`, `Train/mean_episode_length`, `Perf/total_fps`, `Loss/*`; dump with
  `tensorboard.backend.event_processing.event_accumulator.EventAccumulator(run, size_guidance={"scalars": 0})` and
  plot with **gnuplot** (`set terminal … noenhanced`, else `rsl_rl` renders as a subscript).
- **Play + video**: `isaaclab play --rl_library rsl_rl --task Isaac-Cartpole-Direct --num_envs 16 --video
  --video_length 200 physics=isaacsim_physx` loads the latest run's last checkpoint (`--checkpoint` to pick), injects
  a headless Kit visualizer itself (no `--enable_cameras` flag in 3.0), writes `videos/play/clip_model_299_0000.mp4`
  (1280×720; 200 frames at 60 fps for Cartpole, 300 at 50 fps for Go2, which walked with its command arrows) and
  `exported/policy.{pt,onnx}` (→ **ml-deploy**), then exits. First play took 7 min (RTX shader warm-up); the next one 1 min 11 s.
- Backends: PhysX (Isaac Gym-like), Newton (MuJoCo-Warp, can run without Isaac Sim), OvPhysX (kit-less). Multi-GPU:
  `isaaclab train_multigpu`. Migration guides: `skills/user/migrate-2x-to-3x`, `migrate-from-isaac-gym`.

## 8. Typical errors (found or documented)

| Symptom | Fix |
|---|---|
| `libxml2.so.2: cannot open shared object file` → `omni.kit.asset_converter` and `omni.kit.tool.asset_importer` fail to start | distro ships libxml2 2.14+ (`.so.16`): add conda-forge `libxml2<2.14` to the env |
| pip/pixi cannot find `isaacsim-*`/`mujoco-usd-converter` | NVIDIA index + `index-strategy = "unsafe-best-match"`; glibc ≥ 2.35 declared; Python 3.12 |
| EULA prompt hangs a batch job | `OMNI_KIT_ACCEPT_EULA=YES` |
| `X11 connection rejected` / viewport waits for a display over ssh | `env -u DISPLAY`, `SimulationApp({"headless": True})` |
| Black frames | add Dome/Distant lights; warm up with ~10–120 `update_app()` before reading |
| Minutes at first launch | shader/MDL + extension cache warm-up (caches under the env's `kit/cache` ~0.6 GB, `~/.cache/ov`, `~/.nv/ComputeCache`); later 7 s |
| Vulkan/driver errors (`VkResult`, no ICD) | `vulkaninfo`; `/usr/share/vulkan/icd.d/nvidia_icd.json` must exist; containers need `NVIDIA_DRIVER_CAPABILITIES=all` |
| CUDA OOM | `nvidia-smi`; fewer envs/cameras, lower resolution, `{"renderer": None}`/`--/app/renderer/enabled=false` for physics-only |
| `omni.isaac.*` import errors | port to `isaacsim.*` / `isaacsim.core.experimental.*` (migration guides) |
| `isaaclab[isaacsim]==3.0.0 … depends on urllib3==2.7.0 … unsatisfiable` | `[pypi-options.dependency-overrides]` as in section 7 |
| `NameNotFound: Environment Isaac-Velocity-Flat-Anymal-C doesn't exist` | 3.0 names: no `-v0`, `…-AnymalD`, `…-UnitreeGo2`; `isaaclab list_envs` |
| `ROS2 Bridge startup failed` / rclpy symbols missing (pip install) | export `ROS_DISTRO`, `RMW_IMPLEMENTATION`, `LD_LIBRARY_PATH=…/isaacsim.ros2.core/<distro>/lib` before launch |
| Foreign topics, odd rates, bridge stalls | shared `ROS_DOMAIN_ID`: pick an empty one |

Cleanup after experiments: the env (23–25 GB), `logs/` (checkpoints, videos), the Pixi/uv package cache, `~/.cache/ov`, `~/.local/share/ov`,
`~/.nvidia-omniverse`, `/dev/shm/carb-*` leftovers after crashes.
