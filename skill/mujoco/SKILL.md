---
name: mujoco
description: Simulate robots with MuJoCo 4.x — pip packages (mujoco = mujoco-core + mujoco-studio), MJCF modeling (worldbody/body/joint/geom/site, actuators, sensors, tendons, equality, contact pairs/exclude, default classes, compiler/option: timestep, integrators implicitfast/RK4/discrete, cones, solref/solimp, keyframes, mesh assets), mjModel/mjData API (mj_step, mj_step1/2, mj_forward, Jacobians, mj_inverse, contacts, named access), MjSpec editing and attaching Menagerie robots, headless rendering (MUJOCO_GL=egl, mujoco.Renderer rgb/depth/segmentation), viewers, CPU batching (mujoco.rollout, mujoco.batch, mjbatch.h), GPU batching with MuJoCo Warp and MJX (JAX/Warp impl, CUDA graphs, overflow, VRAM), the C API and Odin bindings, determinism and stability pitfalls, logging to MCAP/Rerun and publishing over Zenoh. Load before writing or debugging MuJoCo code or models.
---

# MuJoCo 4.x

Fast, accurate rigid-body + contact physics (DeepMind, Apache-2.0). Other simulators: **genesis** (GPU-native, many
material solvers), **isaac-sim** (RTX sensors, USD, Isaac Lab). Environments: **pixi**. Logging: **mcap**, **zenoh**.
RL training around it: **ml-training**, **ml-tuning**; deploying policies: **ml-deploy**; custom kernels: **gpu-kernels**.
The reference library holds `mujoco-source` (doc/*.rst, include/mujoco/*.h, python/mujoco, the official agent skills),
`mujoco-warp-source` and `mujoco-menagerie`: `library_search` there for XML attributes, C signatures and Python APIs
(e.g. `library_search query="option integrator implicitfast" sources=["mujoco-source"]`).

## 0. Ground truth first (as of 13 Nov 2026, verify)

| Item | State |
|---|---|
| MuJoCo | **4.0.1** (11 Nov 2026); 4.0.0 6 Nov, 3.17.0 Oct 22 (added `mujoco.batch`), releases every 2–3 weeks. Tags `4.0.1` (no `v`). |
| Python | PyPI `mujoco` = `mujoco-core` (bindings + C lib, numpy only) + `mujoco-studio` (Studio, Filament). Python ≥ 3.11 (3.10 dropped in 4.0). Upgrading a pre-4.0 pip env: `pip uninstall -y mujoco` first (Pixi envs are rebuilt, no issue). |
| GPU | `mujoco-warp` 4.0.1 (NVIDIA Warp, `import mujoco_warp as mjw`, officially released since 3.12), `mujoco-mjx` 4.0.1 (JAX; `impl="jax"` or `impl="warp"`; the `[warp]` extra pins `warp-lang==1.18.0`). |
| conda-forge | `mujoco`/`mujoco-python` lag (3.16.0 on 13 Nov 2026): use PyPI. No OSMesa package. |
| C | GitHub release `mujoco-4.0.1-linux-x86_64.tar.gz` (35 MB: `bin/simulate`, `testspeed`, `lib/libmujoco.so.4.0.1`, `include/mujoco/`). |
| Models | Menagerie tag `v2026.11.3` (date tags), ~70 robots, per-robot licenses (most BSD/Apache/MIT). |
| Bundled docs | `pathlib.Path(mujoco.__file__).parent/"doc"` holds the whole manual (`XMLreference.rst`, `python.rst`, `mjx.rst`, `mjwarp/`) and **official agent skills** in `doc/skills/{python,spec_editing,rendering,accelerated,parity,studio}/SKILL.md`. grep them for `.. _Label:` anchors. |

Check `doc/changelog.rst` for breaking changes before porting older code. 4.0 broke: `sidesite` tendon semantics,
RK4 on ball/free joints (now 4th order), cable plugin and `<composite>` removed (use 1D `flexcomp`), duplicate
`<include>` rejected. 3.x→4.x Python: joint `damping`/`stiffness` are **3-vectors** `[a, b, c]` (polynomial): in
MjSpec `j.damping = 5.0` raises `TypeError`, write `[5, 0, 0]`. dm_control/`mujoco-py` names (`load_model_from_path`,
`physics.named`, `sim.data`) do not exist.

Pixi workspace used for validation (installs in ~70 s):
```toml
[workspace]
channels = ["conda-forge"]
platforms = [{ platform = "linux-64", cuda = "13.0" }]
[dependencies]
python = "3.12.*"
c-compiler = "*"          # for C API programs (use `cc`, not $CC)
[pypi-dependencies]
mujoco = "==4.0.1"
mujoco-warp = "==4.0.1"
mujoco-mjx = "==4.0.1"
jax = { version = "==0.12.0.1", extras = ["cuda13"] }
```

## 1. MJCF essentials

```xml
<mujoco model="arm">
  <compiler angle="radian" autolimits="true"/>      <!-- default angle is DEGREE: the #1 unit bug -->
  <option timestep="0.002" integrator="implicitfast" cone="elliptic" impratio="10"/>
  <default>
    <joint damping="0.5" armature="0.01"/>
    <geom friction="1 0.005 0.0001" solref="0.005 1" solimp="0.95 0.99 0.001"/>
    <default class="link"><geom type="capsule" size="0.04"/></default>
    <position kp="80" dampratio="1" ctrlrange="-2.5 2.5"/>
  </default>
  <worldbody>
    <light pos="0 0 3" dir="0 0 -1" directional="true"/>
    <geom name="floor" type="plane" size="2 2 0.1"/>
    <camera name="front" pos="1.6 -1.6 1.2" xyaxes="1 1 0 -0.35 0.35 0.87"/>
    <body name="upper" pos="0 0 0.1">
      <joint name="shoulder" axis="0 1 0" range="-1.6 1.6"/>
      <geom class="link" fromto="0 0 0 0 0 0.4"/>
      <site name="tip" pos="0 0 0.42" size="0.02"/>
    </body>
    <body name="box" pos="0.5 0 0.3"><freejoint/><geom name="box" type="box" size=".05 .05 .05" mass="0.2"/></body>
  </worldbody>
  <actuator><position name="shoulder" joint="shoulder"/></actuator>
  <sensor>
    <framepos name="tip_pos" objtype="site" objname="tip"/>
    <touch name="touch" site="tip"/>
    <contact name="box_floor" geom1="box" geom2="floor" data="found force" reduce="netforce"/>
  </sensor>
  <keyframe><key name="home" qpos="0.3  0.5 0 0.3 1 0 0 0" ctrl="0.3"/></keyframe>
</mujoco>
```
- Bodies nest; a body without joints is welded to its parent; `<freejoint/>` = 7 qpos (pos + quat **w,x,y,z**), 6 qvel.
- Collision filter: `contype`/`conaffinity` bitmasks, `<contact><exclude body1 body2/>`, explicit `<pair>` (overrides
  friction/solref per pair). Parent–child bodies never collide.
- Actuators: `motor` (torque, ctrl = force), `position` (kp, `dampratio` or kv), `velocity`, `general`, `muscle`,
  `dcmotor`. **Menagerie quadrupeds like Go2 use `<motor>`**: the keyframe ctrl is 0 and the robot collapses
  (z 0.27 → 0.08) unless you run a PD loop (`ctrl = kp*(q_des-q) - kd*qd`; kp 60, kd 3 held it at 0.255).
- `solref="timeconst dampratio"` (timeconst ≥ 2×timestep), `solimp` sets softness vs penetration. Stiffer contacts
  need smaller timesteps. Use primitives (box/capsule/sphere) for collision, meshes for visuals (`group`, `contype=0`).
- Use **`contact` sensors** (fixed-size, deterministic) for observations, not `data.contact` (variable length/order).

## 2. Python core (tested)

```python
m = mujoco.MjModel.from_xml_path("scene.xml"); d = mujoco.MjData(m)
mujoco.mj_resetDataKeyframe(m, d, m.key("home").id); mujoco.mj_forward(m, d)  # forward before reading sensors at t=0
for _ in range(1500):
    d.ctrl[:] = policy(d.sensordata); mujoco.mj_step(m, d)            # 129k steps/s for a 3-DoF arm + 3 free bodies
d.sensor("tip_pos").data; d.body("box").xpos; d.joint("shoulder").qpos  # named access returns VIEWS: .copy() to log
f6 = np.zeros(6); mujoco.mj_contactForce(m, d, 0, f6)   # contact i < d.ncon, contact frame, normal first
jacp, jacr = np.zeros((3, m.nv)), np.zeros((3, m.nv)); mujoco.mj_jacSite(m, d, jacp, jacr, m.site("tip").id)
mujoco.mj_inverse(m, d)   # qfrc_inverse == qfrc_actuator + qfrc_applied (+J'xfrc): residual 2.8e-8 here
```
- `mj_step1` (positions/velocities/sensors) → set `ctrl`/`qfrc_applied` from them → `mj_step2`.
  `mj_kinematics` for FK only, `mj_forward` for everything without integrating.
- State save/restore: `mj_stateSize/mj_getState/mj_setState(m, d, buf, mjtState.mjSTATE_FULLPHYSICS)`;
  `mjSTATE_INTEGRATION` for exact replay (includes warmstart).
- Diagnostics: `m.opt.enableflags |= mjENBL_ENERGY` (`d.energy`), `mjENBL_FWDINV` (`d.solver_fwdinv`), `d.warning`.
- Quaternions are **w,x,y,z** (SciPy/ROS/Foxglove are x,y,z,w).

## 3. MjSpec: build and edit models in code (tested)

```python
scene = mujoco.MjSpec(); scene.compiler.degree = False
scene.worldbody.add_geom(type=mujoco.mjtGeom.mjGEOM_PLANE, size=[3, 3, .1])
for side, y in (("left_", .45), ("right_", -.45)):        # same Menagerie arm twice
    arm = mujoco.MjSpec.from_file("mujoco_menagerie/franka_emika_panda/panda.xml")
    scene.attach(arm, frame=scene.worldbody.add_frame(pos=[0, y, 0]), prefix=side)  # frame= or site=, required
scene.body("left_hand").add_site(name="tcp", pos=[0, 0, .1])
scene.add_sensor(name="tcp_pos", type=mujoco.mjtSensor.mjSENS_FRAMEPOS, objtype=mujoco.mjtObj.mjOBJ_SITE, objname="tcp")
m = scene.compile()                       # 155 ms, 134 meshes; errors raise with the element named
m, d = scene.recompile(m, d)              # after further edits; keeps the state (time, qpos) of existing elements
xml = scene.to_xml()
```
Attached keyframes are prefixed (`left_home`) and only cover that child's qpos: merge them yourself. `model.bind(elem)` /
`data.bind(elem)` map spec elements to compiled arrays. `scene.delete(elem)`, `default` classes via `spec.add_default`.

## 4. Rendering and viewers

- Headless: `MUJOCO_GL=egl` **before** `import mujoco` (NVIDIA EGL; worked on an Arch box). `osmesa` needs a system
  libOSMesa (failed: `'NoneType' object has no attribute 'glGetError'`); `glfw` needs a display.
- Size the offscreen buffer in XML (`<visual><global offwidth="1280" offheight="720"/>`) or renders larger fail.
```python
with mujoco.Renderer(m, height=480, width=640) as r:      # create once, outside the loop
    r.update_scene(d, camera="front"); rgb = r.render()    # uint8 (H,W,3); .copy() if kept
    r.enable_depth_rendering(); r.update_scene(d, camera="front"); depth = r.render()   # metres
    r.enable_segmentation_rendering(); ...                  # (H,W,2): object id, mjtObj type
cam = mujoco.MjvCamera(); cam.type = mujoco.mjtCamera.mjCAMERA_TRACKING; cam.trackbodyid = m.body("base").id
```
- Interactive: `python -m mujoco.viewer --mjcf=scene.xml`; in code `with mujoco.viewer.launch_passive(m, d) as v:`
  step yourself, then `v.sync()` (macOS needs `mjpython`). MuJoCo Studio (`mujoco-studio`, `--gfx=web` browser viewer)
  is the 4.x app; Filament PBR renderer in `mujoco.mjrf`. Over ssh prefer EGL renders or the web viewer.

## 5. Batching and GPU (measured on RTX 5090 + 24-core CPU, Go2 `scene_mjx.xml`, 4096 worlds × 200 steps)

| Method | steps/s | Notes |
|---|---|---|
| Python loop, 1 thread | 76 k | |
| `mujoco.rollout` (24 threads) | 1.40 M | stateless: `(nbatch, nstep, nu)` controls → states, sensordata |
| `mujoco.batch.Batch` (24 threads) | 1.25 M | stateful RL-style; bit-identical to a serial loop |
| MJWarp `mjw.step` | 2.0 M (7.2 M @16384) | |
| MJWarp + CUDA graph | **7.3 M (11.5 M @16384)** | `iterations=1` model; 4.6 M (8.7 M @16384) with `iterations=8` |
| MJX `impl="warp"` vmap+scan | 0.79 M (2.7 M @16384) | iterations=8; jit 3–4 s |
| MJX `impl="jax"` | 0.79 M | jit 9 s; differentiable |

```python
b = mujoco.batch.Batch(m, nsim=4096, nthread=24); b.reset(keyframe=key)
ctrl = b.bind("ctrl")                                   # live (nsim, nu) view; state fields are views, others outputs
for k in range(S): ctrl[:] = u[:, k]; b.step()
with mujoco.rollout.Rollout(nthread=24) as ro: state, sens = ro.rollout(m, [mujoco.MjData(m) for _ in range(24)], x0, u)

import warp as wp, mujoco_warp as mjw
mw = mjw.put_model(m); mw.opt.warn_overflow = 0          # see pitfall below
dw = mjw.put_data(m, d, nworld=4096, nconmax=16, njmax=64)   # sizes are NOT read from <size>
with wp.ScopedCapture() as cap: wp.copy(dw.ctrl, ctrl_buf); mjw.step(mw, dw)
for k in range(S): wp.copy(ctrl_buf, u_wp[:, k]); wp.capture_launch(cap.graph)
bad = dw.overflow.numpy() != 0                           # per-world mjw.OverflowType bitmask; check at resets
```
- **Overflow printf kills throughput**: with the default `warn_overflow`, every world that hits a limit (here
  `solver iterations limit reached`) prints from the GPU: 0.2 M instead of 7.3 M steps/s. Disable and read
  `d.overflow` instead; MJX-Warp exposes no switch (stays slow until the model stops overflowing: raise
  `opt.iterations`). Size `nconmax/naconmax/njmax` for the peak: excess contacts are dropped silently otherwise.
- Per-world parameters: `mjw.put_model(m, batch_sizes={"dof_damping": N})` (indexed `world % N`); `Batch.expand()` /
  `b.body("x").mass = …` on CPU. GPU float32 vs CPU float64 differs: compare with the official `parity` skill.
- MJX: `XLA_PYTHON_CLIENT_PREALLOCATE=false` (JAX grabs 75 % of VRAM otherwise), `jax_compilation_cache_dir`,
  `mjx.make_data(m, impl="warp", naconmax=…, njmax=…)`, resets with `data.where(done, reset)`.
- **Check free VRAM before large batches**: `nvidia-smi --query-gpu=memory.used,memory.total --format=csv` and
  `nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv` (other users' processes count). With
  only 3 GB free, MJX-JAX at 4096 worlds failed with `cuSolver internal error gpusolverDnCreate`, MJX-Warp at 16384
  with `CUDA_ERROR_OUT_OF_MEMORY` and graph capture with `Warp CUDA error 2: out of memory`; all ran with the GPU free.
  `wp.get_device("cuda:0").free_memory` gives it from Python.
- RL stacks: MuJoCo Playground (`playground` 1.0.1, MJX), mjlab (Isaac-Lab-style API on mujoco_warp + PyTorch).

## 6. C API and Odin (tested)

```c
mjModel* m = mj_loadXML(path, NULL, err, sizeof err);  mjData* d = mj_makeData(m);
mj_resetDataKeyframe(m, d, mj_name2id(m, mjOBJ_KEY, "home"));
for (...) { d->ctrl[i] = ...; mj_step(m, d); }        mj_contactForce(m, d, i, f6);  mj_jacBodyCom(m, d, jacp, NULL, b);
mjBatch* b = mjb_makeBatch(m, 256, &cfg, err, sizeof err);   /* mjbatch.h, cfg from mjb_defaultConfig */
void* xpos = mjb_output(b, "xpos", &sz, &es);   /* register non-state outputs BEFORE the calls */
mjb_reset(b, NULL, 0, keys, mjSTAGE_ACC); mjb_step(b, NULL, 0, 500, mjSTAGE_NONE);
mjtNum* q = mjb_stateComponent(b, mjSTATE_QPOS, &n);  /* state fields live in rows mjb_nstate(b) apart; mjb_output("qpos") is NULL */
mj_saveModel(m, "x.mjb", NULL, 0);
```
Build: `cc -O2 -I$MJ/include main.c -L$MJ/lib -lmujoco -Wl,-rpath,$MJ/lib` (Pixi gcc 15.3). `bin/testspeed
--nstep=20000 --nthread=24 scene.xml` (flags now `--name=value`; the old positional form fails) gave 680 k steps/s
for Go2, Newton 2.2 iterations/step. **Odin** (no vendor package): `foreign import mujoco "system:mujoco"`, declare
`mjModel :: struct {}` / `mjData :: struct {}` as opaque and move data through `mj_getState`/`mj_setState`
(`mjSTATE_QPOS = 1<<1`, `QVEL = 1<<2`, `CTRL = 1<<6`, `mjOBJ_KEY = 24`) instead of mirroring the huge structs;
`odin build . -extra-linker-flags:"-L$MJ/lib -Wl,-rpath,$MJ/lib"` reproduced the C result exactly (z 0.2555).
See **odin**, **c-platform**.

## 7. Stability, determinism, performance

- Diverging/exploding: check units (degrees!, mm meshes), initial penetrations (pause at t=0), CAD inertias, then
  `implicitfast` + joint `armature`, smaller `timestep`, softer `solref`. Energy growth in a passive model = instability.
  `noslip_iterations` for gripper slip; `cone="elliptic"` + `impratio` 10–100 for grasping; `speculative` flag (4.0)
  against tunneling.
- Determinism: CPU MuJoCo is deterministic for identical inputs and thread count; `mujoco.batch` is bit-identical at
  any thread count; GPU (float32, atomics) is not bit-reproducible across runs/devices.
- Speed: fewer contacts (primitives, `exclude`), `jacobian="sparse"` for big models, islands, `sleep` for static
  bodies, CPU batching before GPU for <1–2 k worlds, GPU + CUDA graphs for thousands.

## 8. Logging and middleware (tested)

- **MCAP** (see **mcap**): `mcap.writer.Writer`, JSON + `jsonschema` channels (`/joint_states`, base pose as
  `foxglove.PoseInFrame` with the quaternion reordered to x,y,z,w), `log_time = int(d.time*1e9)`; 300 msgs → 76 KB zstd.
- **Rerun** 0.43 (`rerun-sdk`): `rr.init("app"); rr.save("run.rrd")` (or `rr.spawn()`), `rr.set_time("sim_time",
  duration=d.time)`, `rr.log(f"world/{body}", rr.Transform3D(translation=d.xpos[b], quaternion=[*q[1:], q[0]]))`,
  batch scalars with `rr.send_columns(path, indexes=[rr.TimeColumn("sim_time", duration=t)],
  columns=rr.Scalars.columns(scalars=x))`, frames with `rr.Image(rgb).compress(jpeg_quality=85)`; `rerun rrd stats`.
- **Zenoh** (see **zenoh**): publish JSON/CDR state on `sim/<robot>/state`. On a hardened host multicast scouting
  never matched: give the subscriber `listen/endpoints` and the publisher `connect/endpoints`, and wait for
  `pub.matching_status.matching` before a short run (150/150 messages then).
