---
name: c-gamedev
description: Game and simulation building blocks in C (and from Odin) — flecs v4 ECS (world, components, systems and pipeline phases, queries, observers, relationships/pairs, prefabs with IsA, hierarchies, multithreading, reflection and the REST API/explorer), Jolt Physics 5.6 from C via JoltC (layers, shapes, bodies, stepping, job system, cross-platform determinism), meshoptimizer 1.3 (indexing, vertex cache/overdraw/fetch optimization, simplification and LODs, meshlets, vertex/index codecs, gltfpack and EXT_meshopt_compression decoding), ufbx (FBX/OBJ loading, axis/unit conversion, triangulation, skinning, animation evaluation and baking) and cgltf (glTF 2.0 parse, buffers, validate, accessors; Odin vendor:cgltf) — builds through Pixi, measured numbers, pitfalls. Load before writing ECS, physics, mesh-processing or asset-loading code in C or Odin.
---

# C game building blocks: flecs, Jolt, meshoptimizer, ufbx, cgltf

## Ground truth first

- Versions as of Nov 2026 (verify with `git ls-remote --tags`; sort with `sort -V`): **flecs v4.2.0** (2026-11-04),
  **JoltPhysics v5.6.0** (2026-07), **JoltC** (SecondHalfGames, untagged; commit 429235de wraps Jolt 5.6.0 as a git
  submodule), **meshoptimizer v1.3** (2026-09, `MESHOPTIMIZER_VERSION 1030`), **ufbx v0.23.1**, **cgltf v1.15**
  (2025-02; Odin's `vendor/cgltf/src/cgltf.h` is identical). All MIT (ufbx: MIT or Unlicense; JoltC: MIT or Apache-2.0).
- The reference library holds them at these tags (`flecs-source`, `jolt-source`, `joltc-source`,
  `meshoptimizer-source`, `ufbx-source`, `cgltf-source`): `library_search query="ecs_system_desc_t"
  sources=["flecs-source"]` returns the declaration with its doc comment. **Read the header of the version you vendor**:
  docs lag the code (flecs example below).
- conda-forge has `jolt-physics 5.6.0` and `meshoptimizer 1.3` (library only, no `gltfpack` binary); no flecs, ufbx,
  cgltf or JoltC. Vendor the sources; compilers, CMake and Ninja from Pixi (`pixi add c-compiler cxx-compiler cmake
  ninja`; see pixi). Linux note: conda-forge gcc 15 rejects the JoltC header in C mode, so `pixi add clang` there.
- Pairing: replicate ECS state over the network with librg/ENet (c-networking), render with sokol/SDL3 and lay out UI
  with clay (c-platform), profile with Tracy and pick allocators with c-perf, write Odin with odin and
  odin-performance.

## flecs (ECS, C99, single amalgamated file)

- Add `distr/flecs.c` + `distr/flecs.h` (all addons) or `distr/flecs_no_addons.*`. Compile flecs.c once into an object
  (~20 s at `-O2`) and link it: `cc -O2 -std=gnu99 -c flecs.c`; Linux also needs `-lpthread`. Use C99 or later.
- Validated core (100k entities, M2 Max):
  ```c
  ecs_world_t *world = ecs_init();
  ECS_COMPONENT(world, Position); ECS_COMPONENT(world, Velocity); ECS_TAG(world, Enemy);
  ecs_system(world, { .entity = ecs_entity(world, { .name = "Move" }), .phase = EcsOnUpdate,
      .query.terms = { { ecs_id(Position) }, { ecs_id(Velocity), .inout = EcsIn } },
      .callback = Move, .multi_threaded = true });          /* or ECS_SYSTEM(world, Move, EcsOnUpdate, Position, [in] Velocity) */
  void Move(ecs_iter_t *it) { Position *p = ecs_field(it, Position, 0); const Velocity *v = ecs_field(it, Velocity, 1);
      for (int i = 0; i < it->count; i++) p[i].x += v[i].x * it->delta_time; }   /* field indices are 0-based in v4 */
  ecs_entity_t e = ecs_new(world); ecs_set(world, e, Position, {1, 2}); ecs_add(world, e, Enemy);
  ecs_observer(world, { .query.terms = {{ ecs_id(Health) }}, .events = { EcsOnSet }, .callback = OnSet });
  ecs_entity_t Orc = ecs_entity(world, { .name = "Orc" }); ecs_add_id(world, Orc, EcsPrefab); ecs_set(world, Orc, Health, {100});
  ecs_add_pair(world, e, EcsIsA, Orc);                      /* e inherits Health (shared until ecs_set overrides it) */
  ecs_add_pair(world, bob, Eats, apples); ecs_get_target(world, bob, Eats, 0);   /* relationships */
  ecs_set_threads(world, 8); while (ecs_progress(world, dt)) {}
  ecs_query_t *q = ecs_query(world, { .terms = {{ ecs_id(Position) }, { ecs_id(Health) }, { Enemy }}, .cache_kind = EcsQueryCacheAuto });
  ecs_iter_t it = ecs_query_iter(world, q); while (ecs_query_next(&it)) { … ecs_field_is_self(&it, 1) ? h[i] : h[0] … }
  ```
  Results: creating 100k entities with 2 components (10% IsA + tag) 21 ms; `Move` over 100k 0.02 ms/frame single
  threaded, **0.07 ms with 8 threads** (thread sync costs more than the work: thread only heavy systems); cached query
  over 10k prefab instances 0.016 ms; the OnSet observer fired 10000 times for the IsA instances (inherited values
  count as set).
- **Pitfall (4.2)**: `ecs_entity_desc_t` has no `.add`/`.set` arrays any more, but `docs/PrefabsManual.md` and the
  migration guide still show `ecs_entity(world, { .add = ecs_ids(EcsPrefab) })` → compile error. Use `ecs_add_id`
  after creating, and the system's `.phase` field (not `.add = ecs_ids(ecs_dependson(EcsOnUpdate))`).
- Inherited components arrive as a single shared value: check `ecs_field_is_self(&it, n)` and index `[0]` when false.
- Pipeline phases in order: `EcsOnLoad, EcsPostLoad, EcsPreUpdate, EcsOnUpdate, EcsOnValidate, EcsPostUpdate,
  EcsPreStore, EcsOnStore`; custom phases are entities with `EcsPhase` + `DependsOn`. Structural changes inside
  systems are deferred until the end of the stage. Hierarchies: `ecs_entity(world, { .name = "Earth", .parent = sun })`
  or `(ChildOf, parent)` pairs; `ecs_children(world, parent)` iterates them; names resolve as `Sun.Earth`.
- **REST + explorer** (validated): reflection is needed for JSON values: `ECS_STRUCT(Position, { float x; float y; });`
  at file scope, then `ECS_META_COMPONENT(world, Position)`. `ecs_singleton_set(world, EcsRest, { .port = 27751 })`
  (default port 27750) and run with `ecs_app_run(world, &(ecs_app_desc_t){ .target_fps = 30, .frames = 300 })` or
  `ecs_progress`. `curl localhost:27751/entity/Sun/Earth` → `{"parent":"Sun", "name":"Earth",
  "components":{"Position":{"x":1.5, "y":2}}}`; `GET /query?expr=Position`; `PUT
  /component/Sun/Earth?component=Position&value=%7B%22x%22%3A10%7D` → 200, value now `{"x":10, "y":2}`. The web explorer
  (flecs.dev/explorer) connects to localhost from your browser. Set `.readonly = true` for anything reachable from a network.
- Odin: no vendor package. Community bindings: `Truc4/oflecs` (active 2026-10), `CoolAndMysterious/Flecs-Bindings-For-Odin`
  (generated with odin-c-bindgen), `nowhereware/flecs_odin` (2024); not validated here. Check that they target 4.2
  (struct layouts changed), or `foreign import` the few procs you need from a static flecs build. The ECS macros are C
  macros, so in Odin you call `ecs_component_init`, `ecs_system_init` etc. with desc structs directly.

## Jolt Physics from C (JoltC)

- Jolt is C++17 (`Jolt/` headers, `Docs/Architecture.md`). C options: **SecondHalfGames/JoltC** (opaque handles, layout
  asserts, used by jolt-rust; validated here), amerkoleci/joltc (JoltPhysicsSharp), zphysics' JoltC (zig-gamedev).
  Build: `ln -s ../JoltPhysics JoltC/JoltPhysics` (or clone with `--recurse-submodules`), then `cmake -S JoltC -B b -G
  Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build b` (155 steps, 11 s on M2 Max) → `b/libjoltc.a` +
  `b/JoltPhysics/Build/libJolt.a`; link your C object with **c++** (`c++ app.o libjoltc.a libJolt.a -lpthread`).
  Options: `-DDOUBLE_PRECISION=ON`, `-DOBJECT_LAYER_BITS=32`, `-DCROSS_PLATFORM_DETERMINISTIC=ON`; the C side must
  see the same `JPC_*` defines.
- Validated flow (`jolt_boxes.c`, plain C11):
  ```c
  JPC_RegisterDefaultAllocator(); JPC_FactoryInit(); JPC_RegisterTypes();
  JPC_TempAllocatorImpl *temp = JPC_TempAllocatorImpl_new(16 << 20);
  JPC_JobSystemThreadPool *jobs = JPC_JobSystemThreadPool_new3(JPC_MAX_PHYSICS_JOBS, JPC_MAX_PHYSICS_BARRIERS, threads /* -1 = cores-1 */);
  /* layers: object layer -> broad-phase layer mapping + two collide filters, as C fn tables */
  JPC_BroadPhaseLayerInterface *bpl = JPC_BroadPhaseLayerInterface_new(NULL, (JPC_BroadPhaseLayerInterfaceFns){ .GetNumBroadPhaseLayers = n, .GetBroadPhaseLayer = map });
  JPC_PhysicsSystem *ps = JPC_PhysicsSystem_new();
  JPC_PhysicsSystem_Init(ps, maxBodies, 0, maxBodyPairs, maxContacts, bpl, ovbFilter, ovoFilter);
  JPC_BodyInterface *bi = JPC_PhysicsSystem_GetBodyInterface(ps);
  JPC_BoxShapeSettings bs; JPC_BoxShapeSettings_default(&bs); bs.HalfExtent = (JPC_Vec3){.5f,.5f,.5f,0};
  JPC_Shape *box; JPC_String *err; if (!JPC_BoxShapeSettings_Create(&bs, &box, &err)) puts(JPC_String_c_str(err));
  JPC_BodyCreationSettings s; JPC_BodyCreationSettings_default(&s);
  s.Position = (JPC_RVec3){x, y, z, 0}; s.MotionType = JPC_MOTION_TYPE_DYNAMIC; s.ObjectLayer = OL_MOVING; s.Shape = box;
  JPC_BodyID id = JPC_BodyInterface_CreateAndAddBody(bi, &s, JPC_ACTIVATION_ACTIVATE);
  JPC_PhysicsSystem_OptimizeBroadPhase(ps);
  JPC_PhysicsSystem_Update(ps, 1.0f/60, 1 /*collision steps*/, temp, (JPC_JobSystem *)jobs);
  JPC_RVec3 p = JPC_BodyInterface_GetPosition(bi, id); JPC_BodyInterface_IsActive(bi, id);
  ```
  Shapes and other `RefTarget` objects come back with refcount 0, and adding them to a body takes a reference
  (`JPC_Shape_AddRef/Release` if you keep them). Tear down in reverse and finish with `JPC_UnregisterTypes();
  JPC_FactoryDelete();`.
- 1000 boxes dropped in a 10×10 grid onto a static floor, 300 steps: M2 Max 1.17 / 0.66 / 0.40 ms per step with 0 / 1 /
  7 worker threads; Core Ultra 9 285K 0.84 / 0.62 / 0.24 ms (0 / 1 / 23). After 5 s, 790–820 bodies were still active
  (a stacked pile settles slowly). The state hash was identical for every thread count on the same machine.
- **Determinism**: same binary + same API call order ⇒ identical results (any thread count). Across platforms, build
  with `-DCROSS_PLATFORM_DETERMINISTIC=ON` (≈5–10% slower) **and keep your own float code from changing inputs**.
  The Mac (arm64) and Linux (x86_64) hashes only matched (`a00ade112638236f`) after compiling the app with
  `-ffp-contract=off`, because clang on arm64 fuses `a*b+c` into FMA when computing initial positions. Without
  CROSS_PLATFORM_DETERMINISTIC the two platforms diverge (b436… vs 710a…). Contact listener callbacks and
  `GetActiveBodies` order are not deterministic (Architecture.md "Deterministic Simulation"); sort before using them.
  For rollback you need Jolt's C++ `StateRecorder` (`PhysicsSystem::SaveState/RestoreState`); JoltC at 429235de does
  not wrap it, so add a C shim if you need it.
- Pitfalls: **gcc in C mode** fails on `JoltC/Functions.h:649` ("variably modified 'Impulses' at file scope": a
  `static const uint` used as an array size), so compile C users of JoltC with clang (it warns
  `-Wgnu-folding-constant`, harmless) or as C++. With `-std=c11`, glibc hides `clock_gettime`: use `-std=gnu11`.
  Call `OptimizeBroadPhase` after bulk inserts, not every frame. Keep object layers ≤ 16 bits unless you rebuild
  with `OBJECT_LAYER_BITS=32`.
- Odin: no vendor package; `foreign import` `libjoltc.a` + `libJolt.a` + the C++ runtime (`system:c++` on macOS,
  `system:stdc++` on Linux). The `JPC_*` structs need `#align(16)` on vector fields to match `alignas(16)` in Functions.h.
  Not validated here.

## meshoptimizer

- Add `src/*.cpp` (21 files) to your build, or `cmake -DMESHOPT_BUILD_GLTFPACK=ON` for the `gltfpack` CLI. C API in
  `src/meshoptimizer.h` (callable from C; compile the .cpp files as C++). Full pipeline, validated on Khronos
  `DamagedHelmet.glb` (15452 triangles; CC-BY 4.0), with triangles shuffled first to simulate a bad exporter:
  ```c
  size_t vc = meshopt_generateVertexRemap(remap, idx, ic, verts, n, sizeof(Vertex));   /* dedupe: 14556 -> 14356 */
  meshopt_remapIndexBuffer(ib, idx, ic, remap); meshopt_remapVertexBuffer(vb, verts, n, sizeof(Vertex), remap);
  meshopt_optimizeVertexCache(ib, ib, ic, vc);                                          /* ACMR 2.998 -> 0.978 */
  meshopt_optimizeOverdraw(ib, ib, ic, &vb[0].px, vc, sizeof(Vertex), 1.05f);          /* overdraw 1.314 -> 1.155, ACMR 0.990 */
  meshopt_optimizeVertexFetch(vb, ib, ic, vb, vc, sizeof(Vertex));                      /* overfetch 3.700 -> 1.027 */
  meshopt_analyzeVertexCache(ib, ic, vc, 16, 0, 0).acmr;  meshopt_analyzeOverdraw(…).overdraw;  meshopt_analyzeVertexFetch(…).overfetch;
  ```
  Order matters: indexing → vertex cache → overdraw (optional, costs a little ACMR) → vertex fetch (last, it reorders
  vertices). The as-exported helmet already had ACMR 1.070.
- Simplification: `meshopt_simplify(dst, ib, ic, &vb[0].px, vc, stride, target_index_count, target_error, options,
  &result_error)`. Error is relative to the mesh extent (`meshopt_simplifyScale` converts it to absolute units).
  Results: 50% → 7725 triangles (err 0.0032). At 20% and 5% it **stops at 3398 triangles**, because the 0.05 error
  limit is reached before the target, so check the returned count. `meshopt_simplifyWithAttributes` (normals weighted
  0.5) 3576; `meshopt_simplifySloppy` reaches 607 triangles at 5% (err 0.057; no topology preservation);
  `meshopt_SimplifyLockBorder` keeps borders for chunked terrain. Newer options include `meshopt_SimplifyPrune`,
  `meshopt_SimplifyPermissive`, `meshopt_SimplifyRegularize`, plus `meshopt_simplifyWithUpdate` and
  `meshopt_simplifyPrune`; read the header comments.
- Meshlets (mesh shaders and cluster culling): `meshopt_buildMeshletsBound(ic, 64, 124)` →
  `meshopt_buildMeshlets(ml, mlv, mlt, ib, ic, pos, vc, stride, 64, 124, cone_weight 0.25)` → per meshlet
  `meshopt_optimizeMeshlet` + `meshopt_computeMeshletBounds` (sphere + cone, culling usable when `cone_cutoff < 1`).
  Helmet: 244 meshlets (bound 748), average 63.3 triangles / 63.6 vertices, 101 with a usable cone. Limits: max_vertices
  ≤ 256, max_triangles ≤ 512. Also `buildMeshletsFlex/Spatial`, `partitionClusters` (for Nanite-style DAGs) and
  meshlet codecs.
- Codecs: `meshopt_encodeVertexBuffer` 459 KB → 331 KB (71.9%, decodes bit-exact); `meshopt_encodeIndexBuffer` 185 KB
  → 17 KB (9.2%). The decoded **triangles come back rotated** (10499 of 15452 had their vertex order rotated, with
  winding kept), so compare triangles, not raw index arrays. Run the optimizers first (better ratio), then compress
  further with zstd. Decoders are safe on untrusted input (they can produce garbage indices: bound-check them).
  `meshopt_encodeVertexVersion`/`IndexVersion` pin the format.
- **gltfpack**: `gltfpack -i in.glb -o out.glb -cc -si 0.5 -v` produced 7726 triangles, vertex data 74 KB, index data
  8.3 KB; the file only went from 3.77 to 3.30 MB because the textures dominate (`-tc` converts them to KTX2/BasisU).
  Output uses `KHR_mesh_quantization` + **`EXT_meshopt_compression`** (`-ce khr` writes `KHR_meshopt_compression`,
  which cgltf 1.15 does not parse); `-noq` disables quantization.

## cgltf (glTF 2.0)

- `#define CGLTF_IMPLEMENTATION` in one C file. Validated:
  ```c
  cgltf_options o = {0}; cgltf_data *d;
  cgltf_parse_file(&o, path, &d); cgltf_load_buffers(&o, d, path); cgltf_validate(d);   /* each returns cgltf_result_success (0) */
  cgltf_primitive *p = &d->meshes[0].primitives[0];
  const cgltf_accessor *pos = cgltf_find_accessor(p, cgltf_attribute_type_position, 0);
  cgltf_accessor_unpack_floats(pos, out, pos->count * 3);                  /* handles normalized/sparse; NULL out = count */
  cgltf_accessor_unpack_indices(p->indices, idx, sizeof(uint32_t), p->indices->count);
  cgltf_free(d);
  ```
  Positions in **local** space: apply `cgltf_node_transform_world(node, mat)` for each node that references the mesh.
- **EXT_meshopt_compression is parsed but not decoded**: on a gltfpack output, `unpack_floats` returns garbage or 0
  (the C test measured ACMR 0; Odin got 0 floats and all-zero indices). Decode before unpacking (validated; 4 views
  decoded):
  ```c
  for (size_t i = 0; i < d->buffer_views_count; i++) { cgltf_buffer_view *v = &d->buffer_views[i];
    if (!v->has_meshopt_compression || v->data) continue; cgltf_meshopt_compression *mc = &v->meshopt_compression;
    const uint8_t *src = (const uint8_t *)mc->buffer->data + mc->offset; void *dst = malloc(mc->count * mc->stride);
    int rc = mc->mode == cgltf_meshopt_compression_mode_attributes ? meshopt_decodeVertexBuffer(dst, mc->count, mc->stride, src, mc->size)
           : mc->mode == cgltf_meshopt_compression_mode_triangles ? meshopt_decodeIndexBuffer(dst, mc->count, mc->stride, src, mc->size)
           : meshopt_decodeIndexSequence(dst, mc->count, mc->stride, src, mc->size);
    if (mc->filter == cgltf_meshopt_compression_filter_octahedral) meshopt_decodeFilterOct(dst, mc->count, mc->stride); /* + quaternion, exponential */
    v->data = dst; }                       /* cgltf_buffer_view_data() prefers v->data; cgltf_free frees it */
  ```
  Quantized positions then come back in integer units; the dequantization is in the node transform. Draco
  (`has_draco_mesh_compression`) needs the Draco library.
- **Odin `vendor:cgltf`** (validated, dev-2026-11a): only `lib/cgltf_wasm.o` ships for macOS/Linux, so first run
  `sh $(odin root)/vendor/cgltf/src/build_cgltf.sh` (macOS: fat x86_64+arm64 `lib/darwin/cgltf.a`; Linux:
  `lib/cgltf.a`). Without it, the build stops with a `#panic` that tells you so.
  ```odin
  import "vendor:cgltf"
  opts: cgltf.options
  data, res := cgltf.parse_file(opts, cpath)          // multiple return values; res == .success
  defer cgltf.free(data)
  _ = cgltf.load_buffers(opts, data, cpath); cgltf.validate(data)
  for &m in data.meshes { for &p in m.primitives {   // slices, not pointer+count
      pos := cgltf.find_accessor(&p, .position, 0)
      got := cgltf.accessor_unpack_floats(pos, raw_data(floats), pos.count * 3)
      _ = cgltf.accessor_unpack_indices(p.indices, raw_data(idx), size_of(u32), p.indices.count)  // @(require_results)
  } }
  ```
  Helmet result: 14556 vertices, 15452 triangles, max index 14555, bbox [-0.947,-1.187,-0.901]..[0.942,0.813,0.901].

## ufbx (FBX and OBJ)

- One file: compile `ufbx.c` once (3 s) and link `-lm`. Validated:
  ```c
  ufbx_load_opts o = { 0 };
  o.target_axes = ufbx_axes_right_handed_y_up; o.target_unit_meters = 1.0f; o.generate_missing_normals = true;
  ufbx_error err; ufbx_scene *s = ufbx_load_file(path, &o, &err);
  if (!s) { char b[1024]; ufbx_format_error(b, sizeof b, &err); }
  for each mesh: uint32_t tri[mesh->max_face_triangles * 3];
      n = ufbx_triangulate_face(tri, cap, mesh, mesh->faces.data[f]);   /* indices into mesh->vertex_* (per-index attributes) */
      ufbx_get_vertex_vec3(&mesh->vertex_position, index);             /* also vertex_normal, vertex_uv, vertex_color */
  ufbx_anim_stack *st = s->anim_stacks.data[0];                        /* st->anim, st->time_begin/time_end (s) */
  ufbx_evaluate_opts eo = { 0 }; eo.evaluate_skinning = true;
  ufbx_scene *ev = ufbx_evaluate_scene(s, st->anim, t, &eo, &err);     /* copy of the scene at time t */
  ev->meshes.data[i]->skinned_position;                                /* world space unless skinned_is_local */
  ufbx_transform tr = ufbx_evaluate_transform(st->anim, bone_node, t); /* cheap per-bone sampling */
  ufbx_baked_anim *bake = ufbx_bake_anim(s, st->anim, &(ufbx_bake_opts){0}, &err);  /* keyframes for runtime playback */
  ufbx_free_scene(ev); ufbx_free_baked_anim(bake); ufbx_free_scene(s);
  ```
- Results on files from ufbx's own `data/` test corpus: `maya_kenney_character_7700_binary.fbx` (FBX 7700, unit 0.01 m
  converted to metres): 1 mesh, 826 faces → 1604 triangles, a skin with 45 clusters and at most 4 weights per vertex,
  animation "Take 001" lasting 0.833 s. The skinned mid-animation bbox differs from the bind pose ((-1.81..1.81) →
  (-0.67..0.75) in x), and `ufbx_bake_anim` gave 59 baked nodes. `blender_293_barbarian_7400_binary.fbx`: 34 meshes,
  27 materials, 2 skins, 2 blend deformers, 3165 triangles. OBJ files load through the same call
  (`file_format` 2; material parts).
- Skinning for the GPU: per vertex up to `skin->max_weights_per_vertex` weights from `skin->vertices`/`skin->weights`,
  bone matrices = `cluster->geometry_to_bone` × node world transform at time t (`ufbx_get_skin_vertex_matrix` for the
  CPU path). Use `mesh->material_parts` for one draw per material. Feed the result to meshoptimizer the same way as
  glTF.
- Odin: no vendor package. ufbx ships `bindgen/` tooling. `foreign import` a static `ufbx.a`, or convert offline to glTF
  (e.g. Blender, FBX2glTF) and use vendor:cgltf. Not validated here.

## Wiring it together

- Loop: input → `ecs_progress` (systems: gameplay → write intended velocities → step Jolt in a PostUpdate system →
  copy body transforms back into components) → render the ECS state (sokol/SDL3, c-platform) → replicate dirty
  components with librg (c-networking). Keep physics body IDs in a component, and clean them up with an `EcsOnRemove`
  observer.
- Assets offline: FBX/OBJ through ufbx, or glTF through cgltf → meshoptimizer (index, optimize, LODs, meshlets) →
  your own binary format, or gltfpack for glTF delivery. Load at runtime with cgltf plus the meshopt decoder.
- Fixed timestep for physics and netcode (e.g. 60 Hz with an accumulator); render with interpolation. Determinism
  across machines needs the Jolt flag **and** fp-contract discipline in your own code (see above).
