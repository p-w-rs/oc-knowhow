---
name: genesis
description: Simulate robots and soft matter with Genesis (genesis-world 1.5.x, Quadrants kernels) — install with Pixi (Python 3.12+, torch CUDA wheels incl. Blackwell sm_120, glibc and undeclared-dependency pitfalls), gs.init backends (gpu/cuda/cpu/metal, precision, performance_mode), Scene and options (SimOptions dt/substeps, RigidOptions, MPM/SPH/PBD/FEM options, couplers), entities from morphs (URDF, MJCF, Mesh, Plane, Box, Terrain, USD) and materials (rigid, MPM elastic/plastic/sand/snow/liquid, SPH, PBD cloth/liquid, FEM elastic/muscle), batched environments (scene.build n_envs, envs_idx), PD control (set_dofs_kp/kv, control_dofs_position/velocity/force), IK and motion planning, sensors (IMU, contact, raycaster/lidar, tactile) and cameras (rasterizer, ray tracer, batch renderer, headless EGL), measured throughput and VRAM, differentiable simulation, and when to choose Genesis vs MuJoCo or Isaac Sim. Load before writing or debugging Genesis code.
---

# Genesis 1.5

Genesis (Genesis-Embodied-AI, Apache-2.0) is a Python physics platform whose solvers (rigid, MPM, SPH, PBD, FEM,
couplers) are written in **Quadrants** (the project's Taichi successor) and run on CUDA, AMD, Metal or CPU, with
batched environments, torch tensors in and out, and built-in rasterizer/ray-tracer cameras. Compare with **mujoco**
(reference rigid-body accuracy, C API, MJWarp) and **isaac-sim** (RTX sensors, USD, Isaac Lab). Environments:
**pixi**; RL training: **ml-training**, **ml-tuning**; policies on robots: **ml-deploy**; logging: **mcap**, **zenoh**.
The reference library holds `genesis-source` (the `genesis/` package, `examples/`, `RELEASE.md`): `library_search`
there for option fields and method signatures, e.g. `library_search query="RigidOptions max_collision_pairs"
sources=["genesis-source"]`. Read `examples/` at the tag before inventing calls; the API changes between minors.

## 0. Ground truth first (as of 27 Nov 2026, verify)

| Item | State |
|---|---|
| Version | **genesis-world 1.5.0** (23 Nov 2026; PyPI), GitHub tag `v1.5.0`; validated 27 Nov back to back with 1.4.7 (same rigid results, speed equal or a few % higher). 1.5.0 changes: URDF `effort` 0 or missing = unbounded (§3), a debug view replaces `vis_mode` (§3), thin-lens `lens=` (§4), cheaper setters without `skip_forward` (§5), dynamic visual textures. 1.4.7: non-rigid fixes, deterministic mode for all solvers. Releases every 1–3 weeks; read `RELEASE.md` ("Breaking" sections; 1.5.0's misses the `skip_forward` removal). |
| Python | **3.12–3.14** (`>=3.12,<3.15`; 1.4.6 dropped 3.10 and 3.11). |
| Kernel language | `quadrants` 1.4.0 (pinned `==1.4.0` by 1.4.7 and 1.5.0, pulled automatically). Kernels compile on first use and are cached in `$XDG_CACHE_HOME/quadrants` (default `~/.cache`; persistent since 1.4.5): the same scene in a new process built in 13 s instead of 35 s; another `n_envs` compiles again. Taichi is gone: old `ti.*` snippets do not apply. |
| torch | Not a declared dependency: install a CUDA build yourself. Since 1.5.0 (read in `__init__.py`, not run) `import genesis` raises below torch 2.8, and `gs.init` on Apple Metal below 2.12. Blackwell (RTX 50xx, sm_120) needs cu128+ wheels; validated with `torch 2.15.0+cu132`. |
| Extras pulled | `mujoco` (MJCF parsing, now 4.0.1), `gs-madrona` (batch renderer, Linux x86_64), `pymeshlab`, `coacd`, `tetgen`, `libigl`, OpenCV, PyAV (video encoding; 1.5.0 dropped moviepy). The env is ~7.5 GB. |
| Docs | https://genesis-world.readthedocs.io (user guide), `examples/` (tutorials, locomotion/go2_*.py, speed_benchmark, sensors, rendering, coupling, deformable). |

Pixi workspace that works (82 s install):
```toml
[workspace]
channels = ["conda-forge"]
platforms = [{ platform = "linux-64", cuda = "13.0", glibc = "2.35" }]   # glibc: see pitfall 1
[dependencies]
python = "3.12.*"
[pypi-dependencies]
torch = { version = "==2.15.0", index = "https://download.pytorch.org/whl/cu132" }
genesis-world = "==1.5.0"
pillow = "*"
```
Install pitfalls found:
1. Pixi's default `__glibc` 2.28 makes it unsolvable: `pymeshlab>=2023.12 has no wheels with a matching platform tag
   (manylinux_2_28_x86_64)` → declare the host's glibc (`ldd --version`) on the platform.
2. 1.4.6 only: `import genesis` → `ModuleNotFoundError: No module named 'matplotlib'` (imported by
   `genesis/utils/hybrid.py`, missing from the requirements) → add it. 1.4.7 imports it lazily; the 1.5.0 env above
   has no matplotlib and ran everything in this skill.
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
scene.build(n_envs=4096, env_spacing=(1.0, 1.0))          # compiles kernels: 35-50 s the first time
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

## 2. Measured (powerslabs, RTX 5090 32 GB, driver 615, 27 Nov 2026, 1.5.0 and 1.4.7 back to back)

| Run | build (1.5.0) | steps | 1.5.0 env-steps/s | 1.4.7 env-steps/s | peak VRAM (nvidia-smi) |
|---|---|---|---|---|---|
| GPU, 16 envs | 40.9 s (cold) | 100 | 19 k | 19 k | 1.8 GB |
| GPU, 4096 envs | 35.7 s (12.9 s cached) | 500 | **2.80–2.81 M** | 2.61–2.76 M | 2.6 GB |
| GPU, 16384 envs | 37.2 s | 500 | **5.15 M** | 4.95 M | 5.0 GB |
| CPU backend, 64 envs | 25.8 s | 200 | 57 k | 55 k | — |

Two 4096 runs per version (order 1.4.7, 1.5.0, 1.5.0, 1.4.7); base z 0.256 and contact forces alike in both; 1.4.6 on
13 Nov gave the same (2.79 M, 5.19 M). Go2 at dt 0.02 with 2 substeps (physics at 0.01 s), so per step it does about
1/5 of the work of MuJoCo's go2 at 0.002 s. MJWarp ran the same robot at 4.6–8.7 M steps/s (see **mujoco**). Compare
frameworks at equal physics dt, solver iterations and contact settings, and measure on your own scene:
`examples/speed_benchmark/franka.py` claims 43 M FPS for a Franka with 30 000 envs (a no-contact best case; 32 M with
the arm in floor contact).

A llama-server holding 24 GB of the GPU at 0 % utilization changed nothing here; on 2P (20 Nov) another user's jobs at
99 % utilization cut the same script to 0.12 M env-steps/s (~23× slower): **throughput on a busy GPU says nothing about
the simulator**. Check `nvidia-smi` utilization (not just memory) before benchmarking; compare versions back to back.
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
- URDF `<limit effort>` becomes `dofs_force_range`. **1.5.0 reads `effort="0"` or a missing effort as unbounded**
  (as MuJoCo and Isaac Sim do; CAD exporters often write 0); up to 1.4.7 both gave `[0, 0]`, an unactuated joint.
  Tested with PD to 1 rad: effort 0 and missing reached 1.000 on 1.5.0 and stayed at 0 on 1.4.7; effort −10 now
  becomes ±10 with a warning (1.4.7 built the inverted range `[10, −10]` and drove the joint into its lower limit).
  A missing effort is silent and effort 0 logs only at INFO (hidden by `logging_level="warning"`). For passive joints
  call `robot.set_dofs_force_range(zeros, zeros, dofs)`; check `robot.get_dofs_force_range()` after loading. The
  bundled Go2 declares every effort (±23.7/±35.55 N·m, unchanged).
- Materials per entity: `gs.materials.Rigid(rho=…, friction=…)` (default), `MPM.Elastic/ElastoPlastic/
  Sand/Snow/Liquid/Muscle`, `SPH.Liquid`, `PBD.Cloth/Elastic/Liquid/Particle`, `FEM.Elastic/Muscle/Cloth`, `Hybrid`
  (rigid skeleton + soft skin). Each non-rigid solver needs its options and a bounded domain, e.g.
  `mpm_options=gs.options.MPMOptions(lower_bound=(-.5,-1,0), upper_bound=(.5,1,1))`, `SimOptions(dt=4e-3,
  substeps=10)`. Coupling: `LegacyCouplerOptions` (default), `SAPCouplerOptions` (rigid–FEM, implicit),
  `IPCCouplerOptions`. Particle/FEM scenes are far more expensive than rigid: start with few envs.
- `gs.surfaces.*` set the look (color, roughness, textures). 1.5.0 adds `gs.textures.DynamicTexture` (images switched
  or written per env at run time, rasterizer only; `examples/rendering/dynamic_texture.py`, not run) and deprecates
  `vis_mode` (warns; the material decides how an entity is drawn). To see collision geometry (or particles, tets,
  SDFs) use the debug view: per entity
  `scene.add_entity(spec=gs.entities.Rigid(morph=…, vis=gs.options.EntityVisOptions(debug=True)))`
  (`debug_vis_mode="sdf"` etc.; `gs.entities.MPM/SPH/PBD/FEM` likewise) or `VisOptions(debug=True)` for every
  entity; the viewer and `add_camera(debug=True)` cameras draw it (tested: Go2 collision primitives, while a normal
  camera kept the meshes). Link frames, contact arrows and solver boundaries moved from `VisOptions` to the solver
  options (old names warn): `RigidOptions(vis=gs.options.RigidVisOptions(link_frames=True))`,
  `MPMOptions(vis=gs.options.ParticleVisOptions(boundary=True))`.

## 4. Sensors and rendering

- `scene.add_sensor(gs.sensors.IMU(entity_idx=robot.idx, link_idx_local=…, acc_noise=…, delay=…))`, `Contact`,
  `ContactForce`, `JointTorque`, `Raycaster` (+ `GridPattern`, `SphericalPattern` for lidar), `DepthCamera`,
  tactile probes, `TemperatureGrid`; `sensor.read()` returns batched named tuples. `sensor.start_recording(
  gs.recorders.…)` for plots/files. Since 1.5.0 `Contact`, `ContactForce` and `TemperatureGrid` need an `entity_idx`
  (`Contact()` without one: `GenesisException: Contact requires entity_idx >= 0` at build; 1.4.7 accepted it).
  `draw_debug=True` on a sensor (camera sensors too since 1.5.0) draws its readings in the viewer and debug cameras.
- Cameras: `scene.add_camera(...)` uses the scene renderer: `gs.renderers.Rasterizer()` (OpenGL, fast; first render
  8–10 s with empty caches, then 0.12 s at 640×480, also in later processes), `RayTracer()` (LuisaRender path tracer,
  needs its own build; `spp`, `denoise`), `BatchRenderer()` (Madrona, many envs at once for vision RL; also fisheye).
  Depth of field (RayTracer only): since 1.5.0 `add_camera(..., lens=gs.options.ThinLens(aperture=2.8, focal_len=0.05))`
  (focus defaults to the `lookat` distance; 1.5.0 also fixed the focal length being ignored; created, not rendered:
  no LuisaRender build); `model="thinlens"`, `aperture=`, `focus_dist=` still work but warn. `add_camera(debug=True)`
  always rasterizes and draws the debug view and markers, without changing what robot sensors see.
  `cam.follow_entity(entity)`, `cam.start_recording(save_to_filename="run.mp4", fps=30)` … `cam.stop_recording()`
  for videos (frames stream to the file while the scene steps).
- Interactive viewer: `show_viewer=True` (needs a display; on headless servers use cameras + files).

## 5. Pitfalls and practice

- `gs.init` once per process (`Genesis already initialized` otherwise); `gs.destroy()` to re-init. Build cost is per
  process: keep one long-lived process per training run; changing `n_envs` recompiles some kernels.
- The rigid solver is MuJoCo-like (soft constraints, Newton/CG); check `RigidOptions(constraint_solver, iterations,
  tolerance, integrator, impratio, noslip_iterations, enable_mujoco_compatibility)` before comparing to MuJoCo.
  `use_hibernation` sleeps resting bodies. `substeps` multiply cost.
- Setters between steps (resets, domain randomization): since 1.5.0 derived quantities (link poses, …) are refreshed
  lazily when read. Measured with Go2 × 4096 on the 5090 (one run each): `set_qpos` on all envs 0.125 → 0.042 ms; a
  setter followed by a read costs the same as before (0.13 ms); an RL step with six reads and 2 % resets 1.66 → 1.60
  ms (equal to 1.4.7 with `skip_forward=True`). **`skip_forward=` is gone** from `set_pos`, `set_quat`, `set_qpos`,
  `set_dofs_velocity`, `zero_all_dofs_velocity` (`TypeError` on 1.5.0; not in the release notes): delete the argument
  when porting. Solver getters take `copy=False` for a zero-copy view
  (`scene.sim.rigid_solver.get_links_pos(copy=False)`); a setter does not update a view: it showed the old pose until
  a getter or `scene.step()` ran.
- GPU results are deterministic only with `use_deterministic_algorithms` on (the default, except that
  `performance_mode=True` turns it off unless you pass `True`), a `seed=` and the same device; 1.4.4/1.4.6 fixed
  several GPU non-determinism bugs, and 1.4.7 extends deterministic mode to MPM, SPH and the SAP coupler (~15%
  slower): stay on the latest patch.
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
