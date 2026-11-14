---
name: genesis
description: Simulate robots and soft matter with Genesis (genesis-world 1.4.x, Quadrants kernels) — install with Pixi (Python 3.12+, torch CUDA wheels incl. Blackwell sm_120, glibc and undeclared-dependency pitfalls), gs.init backends (gpu/cuda/cpu/metal, precision, performance_mode), Scene and options (SimOptions dt/substeps, RigidOptions, MPM/SPH/PBD/FEM options, couplers), entities from morphs (URDF, MJCF, Mesh, Plane, Box, Terrain, USD) and materials (rigid, MPM elastic/plastic/sand/snow/liquid, SPH, PBD cloth/liquid, FEM elastic/muscle), batched environments (scene.build n_envs, envs_idx), PD control (set_dofs_kp/kv, control_dofs_position/velocity/force), IK and motion planning, sensors (IMU, contact, raycaster/lidar, tactile) and cameras (rasterizer, ray tracer, batch renderer, headless EGL), measured throughput and VRAM, differentiable simulation, and when to choose Genesis vs MuJoCo or Isaac Sim. Load before writing or debugging Genesis code.
---

# Genesis 1.4

Genesis (Genesis-Embodied-AI, Apache-2.0) is a Python physics platform whose solvers (rigid, MPM, SPH, PBD, FEM,
couplers) are written in **Quadrants** (the project's Taichi successor) and run on CUDA, AMD, Metal or CPU, with
batched environments, torch tensors in and out, and built-in rasterizer/ray-tracer cameras. Compare with **mujoco**
(reference rigid-body accuracy, C API, MJWarp) and **isaac-sim** (RTX sensors, USD, Isaac Lab). Environments:
**pixi**; RL training: **ml-training**, **ml-tuning**; policies on robots: **ml-deploy**; logging: **mcap**, **zenoh**.
The reference library holds `genesis-source` (the `genesis/` package, `examples/`, `RELEASE.md`): `library_search`
there for option fields and method signatures, e.g. `library_search query="RigidOptions max_collision_pairs"
sources=["genesis-source"]`. Read `examples/` at the tag before inventing calls; the API changes between minors.

## 0. Ground truth first (as of 13 Nov 2026, verify)

| Item | State |
|---|---|
| Version | **genesis-world 1.4.6** (8 Nov 2026; PyPI and conda-forge), GitHub tag `v1.4.6`. 1.4.x releases every 1–3 weeks; read `RELEASE.md` ("Breaking" sections). |
| Python | **3.12–3.14** (1.4.6 dropped 3.10 and 3.11). |
| Kernel language | `quadrants` 1.4.0 (pulled automatically). Kernels compile on first use and are cached in `~/.cache/quadrants` (persistent since 1.4.5). Taichi is gone: old `ti.*` snippets do not apply. |
| torch | Not a declared dependency: install a CUDA build yourself. Blackwell (RTX 50xx, sm_120) needs cu128+ wheels; validated with `torch 2.15.0+cu132`. |
| Extras pulled | `mujoco` (MJCF parsing, now 4.0.1), `gs-madrona` (batch renderer, Linux x86_64), `pymeshlab`, `coacd`, `tetgen`, `libigl`, OpenCV. The env is ~7.5 GB. |
| Docs | https://genesis-world.readthedocs.io (user guide), `examples/` (tutorials, locomotion/go2_*.py, speed_benchmark, sensors, rendering, coupling, deformable). |

Pixi workspace that works (77 s install):
```toml
[workspace]
channels = ["conda-forge"]
platforms = [{ platform = "linux-64", cuda = "13.0", glibc = "2.35" }]   # glibc: see pitfall 1
[dependencies]
python = "3.12.*"
[pypi-dependencies]
torch = { version = "==2.15.0", index = "https://download.pytorch.org/whl/cu132" }
genesis-world = "==1.4.6"
matplotlib = "*"          # pitfall 2
pillow = "*"
```
Install pitfalls found:
1. Pixi's default `__glibc` 2.28 makes it unsolvable: `pymeshlab>=2023.12 has no wheels with a matching platform tag
   (manylinux_2_28_x86_64)` → declare the host's glibc (`ldd --version`) on the platform.
2. `import genesis` → `ModuleNotFoundError: No module named 'matplotlib'` (imported by `genesis/utils/hybrid.py`,
   missing from the requirements) → add it.
3. Over `ssh -X`, `DISPLAY` is set and rendering tries X11 (`X11 connection rejected because of wrong
   authentication`). Run headless jobs with `env -u DISPLAY …`: Genesis then uses EGL (falls back to OSMesa only if
   no libEGL and no display; `PYOPENGL_PLATFORM` overrides).

## 1. Minimal batched robot (tested on RTX 5090)

```python
import torch, genesis as gs
gs.init(backend=gs.gpu, precision="32", performance_mode=True, logging_level="warning")  # once per process
scene = gs.Scene(
    sim_options=gs.options.SimOptions(dt=0.02, substeps=2),
    rigid_options=gs.options.RigidOptions(enable_self_collision=False, max_collision_pairs=20),
    vis_options=gs.options.VisOptions(rendered_envs_idx=[0, 1, 2, 3]),   # render only a few envs
    renderer=gs.renderers.Rasterizer(), show_viewer=False)
scene.add_entity(gs.morphs.URDF(file="urdf/plane/plane.urdf", fixed=True))   # bundled assets: genesis/assets/
robot = scene.add_entity(gs.morphs.URDF(file="urdf/go2/urdf/go2.urdf", pos=(0, 0, 0.42)))
cam = scene.add_camera(res=(640, 480), pos=(2, -2, 1.2), lookat=(0, 0, 0.3), fov=40, GUI=False)
scene.build(n_envs=4096, env_spacing=(1.0, 1.0))          # compiles kernels: 35-45 s the first time
dofs = [robot.get_joint(n).dofs_idx_local[0] for n in joint_names]
robot.set_dofs_kp([20.0] * 12, dofs); robot.set_dofs_kv([0.5] * 12, dofs)
robot.set_dofs_position(q0.repeat(4096, 1), dofs, zero_velocity=True)
for k in range(500):
    robot.control_dofs_position(targets, dofs)             # (n_envs, 12) torch tensor on gs.device
    scene.step()
pos = robot.get_pos(); f = robot.get_links_net_contact_force()   # (N,3), (N, n_links, 3) torch
rgb, depth, seg, normal = cam.render(rgb=True, depth=True, segmentation=True)
```
- Everything is batched along dim 0 once `n_envs` is given; without it tensors have no env dim. Subsets:
  `envs_idx=torch.tensor([1, 5, 7])` on any setter/control (others keep their previous target); resets via
  `set_dofs_position(..., envs_idx=…)`, `set_pos`, `set_quat`.
- Control: internal PD (`control_dofs_position`, `_velocity`, `_position_velocity`) uses `kp/kv` per dof;
  `control_dofs_force` for torque policies; `set_dofs_force_range` for limits. Readback: `get_dofs_position`,
  `get_dofs_velocity`, `get_dofs_force`, `get_links_pos`. Dof order follows the URDF tree, not your list: map names
  with `get_joint(name).dofs_idx_local` (the locomotion examples do this).
- Planning: `robot.inverse_kinematics(link=ee, pos=…, quat=…)` (batched), `robot.plan_path(qpos_goal=…, num_waypoints=…)`
  (OMPL-style, see `examples/tutorials/IK_motion_planning_grasp.py`).
- Bundled go2 warns `Neutral robot position (qpos0) exceeds joint limits` (harmless).

## 2. Measured (powerslabs, RTX 5090 32 GB, driver 615, 13 Nov 2026)

| Run | build | steps | env-steps/s | peak VRAM (nvidia-smi) |
|---|---|---|---|---|
| GPU, 16 envs | 42.7 s (cold) | 100 | 20 k | — |
| GPU, 4096 envs | 35.3 s | 500 | **2.79 M** | 2.6 GB |
| GPU, 16384 envs | 33.9 s | 500 | **5.19 M** | 5.0 GB |
| CPU backend, 64 envs | 22.5 s | 200 | 59 k | — |

Go2 at dt 0.02 with 2 substeps (physics at 0.01 s), so per step it does about 1/5 of the work of MuJoCo's go2 at
0.002 s. MJWarp ran the same robot at 4.6–8.7 M steps/s (see **mujoco**). Compare frameworks at equal physics dt,
solver iterations and contact settings, and measure on your own scene: `examples/speed_benchmark/franka.py` claims
43 M FPS for a Franka with 30 000 envs (a no-contact best case; 32 M with the arm in floor contact).
`torch.cuda.max_memory_allocated()` showed only 0.2–0.8 GB because Quadrants allocations are not counted, so use
`nvidia-smi`.

**Check free VRAM before scaling `n_envs`**: `nvidia-smi --query-gpu=memory.used,memory.total --format=csv` and
`--query-compute-apps=pid,process_name,used_memory` (shared GPUs!). Grow the env count gradually (1k → 4k → 16k) and
watch the peak. Cut memory with `max_collision_pairs`, `enable_self_collision=False`, `rendered_envs_idx` (render a
few envs only), fewer cameras, primitive collision geometry (`convexify`, `decimate` morph options).

## 3. Scenes, morphs, materials

- Morphs: `gs.morphs.URDF(file, pos, quat, fixed, merge_fixed_links, links_to_keep)`, `MJCF(file)` (parsed via MuJoCo:
  Menagerie robots work; actuators/defaults are mapped, check gains), `Mesh(file, scale, convexify, decimate)`,
  `Plane`, `Box`, `Sphere`, `Cylinder`, `Terrain(subterrain_types=…)`, `USD`, `Drone`. Paths resolve against
  `genesis/assets` first. Quaternions are **w,x,y,z**.
- Materials per entity: `gs.materials.Rigid(rho=…, friction=…)` (default), `MPM.Elastic/ElastoPlastic/
  Sand/Snow/Liquid/Muscle`, `SPH.Liquid`, `PBD.Cloth/Elastic/Liquid/Particle`, `FEM.Elastic/Muscle/Cloth`, `Hybrid`
  (rigid skeleton + soft skin). Each non-rigid solver needs its options and a bounded domain, e.g.
  `mpm_options=gs.options.MPMOptions(lower_bound=(-.5,-1,0), upper_bound=(.5,1,1))`, `SimOptions(dt=4e-3,
  substeps=10)`. Coupling: `LegacyCouplerOptions` (default), `SAPCouplerOptions` (rigid–FEM, implicit),
  `IPCCouplerOptions`. Particle/FEM scenes are far more expensive than rigid: start with few envs.
- `gs.surfaces.*` set the look (color, roughness, `vis_mode="visual"/"particle"`).

## 4. Sensors and rendering

- `scene.add_sensor(gs.sensors.IMU(entity_idx=robot.idx, link_idx_local=…, acc_noise=…, delay=…))`, `Contact`,
  `ContactForce`, `JointTorque`, `Raycaster` (+ `GridPattern`, `SphericalPattern` for lidar), `DepthCamera`,
  tactile probes, `TemperatureGrid`; `sensor.read()` returns batched named tuples. `sensor.start_recording(
  gs.recorders.…)` for plots/files.
- Cameras: `scene.add_camera(...)` uses the scene renderer: `gs.renderers.Rasterizer()` (OpenGL, fast; first render
  ~7.5 s for shader compile, then 0.12 s at 640×480), `RayTracer()` (LuisaRender path tracer, needs its own build;
  `spp`, `denoise`, thin-lens), `BatchRenderer()` (Madrona, many envs at once for vision RL; also fisheye).
  `cam.follow_entity(entity)`, `cam.start_recording(save_to_filename="run.mp4", fps=30)` … `cam.stop_recording()`
  for videos (frames stream to the file while the scene steps).
- Interactive viewer: `show_viewer=True` (needs a display; on headless servers use cameras + files).

## 5. Pitfalls and practice

- `gs.init` once per process (`Genesis already initialized` otherwise); `gs.destroy()` to re-init. Build cost is per
  process: keep one long-lived process per training run; changing `n_envs` recompiles some kernels.
- The rigid solver is MuJoCo-like (soft constraints, Newton/CG); check `RigidOptions(constraint_solver, iterations,
  tolerance, integrator, impratio, noslip_iterations, enable_mujoco_compatibility)` before comparing to MuJoCo.
  `use_hibernation` sleeps resting bodies. `substeps` multiply cost.
- GPU results are deterministic only with `gs.init(seed=…, use_deterministic_algorithms=True)` and the same device;
  1.4.4/1.4.6 fixed several GPU non-determinism bugs: stay on the latest patch.
- Differentiable sim: `SimOptions(requires_grad=True)`; 1.4.5+ works with plain torch tensors and `.backward()`;
  supported for rigid PD targets, MPM, FEM (see `RELEASE.md`).
- Debug on CPU (`gs.init(backend=gs.cpu, debug=True)`) for bounds checks; `logging_level="debug"` prints compile info.

## 6. Choosing a simulator

| Need | Pick |
|---|---|
| Accurate contact-rich control, MPC, system ID, C/C++ embedding, CPU batching | **mujoco** (CPU, `mujoco.batch`) |
| Massive rigid-body RL on NVIDIA with MuJoCo semantics | **mujoco** MJWarp / Playground / mjlab |
| Soft bodies, granular, liquids, cloth coupled with robots; torch-native diff-sim; AMD or Apple GPUs | **genesis** |
| Photoreal RTX cameras/lidar, USD/Omniverse assets, ROS 2 bridge, Isaac Lab tasks, SDG | **isaac-sim** |
Policies trained in one simulator should be checked in another (sim-to-sim) before hardware: MJCF and URDF load in
all three (Isaac imports them into USD).
