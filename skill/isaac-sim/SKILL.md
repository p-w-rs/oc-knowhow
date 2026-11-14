---
name: isaac-sim
description: Run NVIDIA Isaac Sim 6.x (Kit 110, Omniverse RTX) and Isaac Lab 3.x — pip install via Pixi (Python 3.12, glibc 2.35+, pypi.nvidia.com index strategy, torch cu130, EULA env, libxml2 fix), GPU/driver requirements and VRAM checks, headless standalone scripts (SimulationApp, isaacsim.core.experimental stage/app utils, SimulationManager, Articulation, GroundPlane), USD basics (stage, prims, references, variants, units/up-axis, physics schemas, articulation roots), URDF/MJCF importers (URDFImporter, Physics variant sets), RTX cameras (RtxCamera + CameraSensor annotators), RTX lidar, ROS 2 bridge (OmniGraph, bundled ROS libs), livestream/WebRTC, Replicator synthetic data, containers (nvcr.io/nvidia/isaac-sim), Newton vs PhysX backends, Isaac Lab training (uv run isaaclab train), startup/shader-cache timings, typical errors and the bundled agent skills. Load before installing, scripting or debugging Isaac Sim or Isaac Lab.
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
| GPU/driver | RTX GPU (no GTX/Tesla-without-RTX for rendering); Linux driver ≥ 595.58.03 per the 6.2 requirements page; Ubuntu 22.04/24.04 supported (22.04 deprecated). Ran fine on Arch (glibc 2.44, driver 615.78) with the fixes below. |
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
- ROS 2 bridge (`isaacsim.ros2.bridge`, extra `ros2`): OmniGraph nodes `ROS2PublishClock`, `…JointState`,
  `…Image`, `…CameraInfo`, `…PointCloud`, `…TransformTree`, `ROS2SubscribeTwist`, … active **only while playing**.
  Without a sourced ROS (`ROS_DISTRO` unset) it falls back to ROS 2 libs bundled in `isaacsim.ros2.core`; source `/opt/ros/<distro>/setup.bash` (custom
  messages, `RMW_IMPLEMENTATION=rmw_zenoh_cpp`, see **zenoh-ros2**) in the parent shell **before** launch; never patch
  `LD_LIBRARY_PATH` in a running process. Publish `/clock` and set `use_sim_time` on ROS nodes.
- Remote viewing: `isaacsim isaacsim.exp.full.streaming --no-window` + the Isaac Sim WebRTC Streaming Client (native
  app) or the web viewer stack (Chromium, `http://HOST:8210`); WebRTC needs UDP reachability (firewalls/VPN; use an SSH
  or WireGuard tunnel only for signalling, media still needs UDP). Over plain ssh, render to files instead.
- Replicator (`omni.replicator.core as rep`): randomize poses/lights/materials per frame (`rep.trigger.on_frame`),
  writers (`BasicWriter`, KITTI, COCO) for labeled datasets (see **datasets** for curation).

## 6. Isaac Lab 3 (not run here; from the v3.0.0 repo)

- Install: from a checkout with uv (`uv run isaaclab …`, the docs-recommended route), pip `isaaclab` + `isaacsim`, or
  `./isaaclab.sh -i` (legacy, Newton-only default). It pins `torch==2.11.0`, `warp-lang==1.17.0`: use a dedicated env.
- Train/play: `uv run isaaclab train --task Isaac-Cartpole [--rl_library rsl_rl|skrl|rl_games|sb3] --num_envs 4096`,
  `uv run isaaclab play --task …` (the old `scripts/reinforcement_learning/*/train.py` are deprecated); headless is the
  default (add `--viz` for a viewer); lower `--num_envs` for camera tasks (camera support is automatic; pick a compatible renderer). Multi-GPU: `train_multigpu.py` / torchrun.
- Backends: PhysX (Isaac Gym-like behavior), Newton (MuJoCo-Warp based, can run without Isaac Sim), OvPhysX; choose
  per task with presets. Migration guides: `skills/user/migrate-2x-to-3x`, `migrate-from-isaac-gym`.

## 7. Typical errors (found or documented)

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

Cleanup after experiments: the env (23 GB), the Pixi/uv package cache, `~/.cache/ov`, `~/.local/share/ov`,
`~/.nvidia-omniverse`, `/dev/shm/carb-*` leftovers after crashes.
