---
name: c-platform
description: Build windowed, rendering, input and audio programs in C (and from Odin) with SDL3, the sokol headers and the clay UI layout library — choosing between them, getting them through Pixi or vendored source, build flags per OS (macOS frameworks, Linux X11/GL/PulseAudio, headless Xvfb/offscreen/dummy), the SDL3 callbacks main, SDL_Renderer vs SDL_GPU, sokol_gfx pipelines with sokol-shdc shaders, clay declarations/measure-text/render commands, pixel readback for tests, WebAssembly builds with emscripten, and Odin bindings (vendor:sdl3, sokol-odin, clay-odin). Load before writing or building any SDL3, sokol or clay program.
---

# C platform layers: SDL3, sokol, clay

## Ground truth first

- Versions as of Nov 2026 (verify: `git ls-remote --tags https://github.com/libsdl-org/SDL.git | tail`): **SDL 3.4.20**
  (`release-3.4.20`), SDL_image 3.4.8, SDL_ttf 3.2.2, SDL_mixer 3.2.4. **sokol** has no release tags: pin a commit of
  `master` (validated 93aa187, 2026-11-10) and read `CHANGELOG.md` before updating; it breaks APIs (Oct 2026:
  `sg_image_desc.data` became one `sg_range`; Linux sokol_audio switched to PulseAudio). **clay**: last release
  **v0.14** (2025-06) but `main` is 99 commits ahead with a **different declaration API** (below); the Odin bindings
  follow `main`. Read the header you actually compile against; never write clay code from memory.
- Headers are the documentation: SDL `include/SDL3/*.h` (+ https://wiki.libsdl.org/SDL3/), sokol: the comment block at
  the top of each `sokol_*.h` (link flags, backends, usage), clay `README.md` + `clay.h`. Examples:
  https://github.com/libsdl-org/SDL/tree/main/examples, https://github.com/floooh/sokol-samples, clay `examples/`.

## Which one

| Need | Pick |
|---|---|
| Full platform layer: windows, input incl. gamepads/pens/touch, audio streams, file dialogs, threads, IO, camera, 2D renderer, modern GPU API | **SDL3** (zlib). Shared library, CMake, big but complete. |
| Smallest portable app + 3D API wrapper, WebAssembly first-class, single-file headers, many language bindings | **sokol** (zlib): `sokol_app` (window/context/input), `sokol_gfx` (GL 4.1/4.3, GLES3/WebGL2, Metal, D3D11, WebGPU, Vulkan), `sokol_audio`, `sokol_time`, `sokol_fetch`, `sokol_log`, `sokol_glue`; `util/` has debugtext, gl (immediate mode), shape, imgui glue. |
| UI layout (flex-box like, immediate mode, no allocations after init), you already have a renderer | **clay** (zlib): only computes boxes and emits render commands; renderers for raylib, sokol, SDL2/3, web, terminal, cairo in `renderers/`. |

Combinations are normal: clay on SDL3 or sokol; SDL3 window + your own Vulkan/Metal. Networking: see c-networking.
Odin language details: odin, odin-targets.

## Getting them

- **Pixi (conda-forge)**: `pixi add sdl3` (3.4.20; also linux-64/aarch64/osx/win), plus `c-compiler cmake ninja
  pkg-config`. No conda-forge `sdl3-ttf`/`sdl3-image` packages (Nov 2026): build those from source with CMake.
  `pkg-config --cflags --libs sdl3`; add `-Wl,-rpath,$CONDA_PREFIX/lib` or the binary won't find `libSDL3` outside
  `pixi run`. Linux headless extras: `xorg-xvfb-server` (not `xorg-xvfb`), `mesalib` (llvmpipe), `libgl-devel`,
  `xorg-libx11 xorg-libxi xorg-libxcursor`, `pulseaudio-client`.
- **Vendored source**: SDL: `git clone -b release-3.4.20 --depth 1` then `cmake -S SDL -B b -G Ninja
  -DCMAKE_BUILD_TYPE=Release && cmake --build b` (or `add_subdirectory(SDL)` + `target_link_libraries(app SDL3::SDL3)`).
  sokol/clay: copy the headers; one `.c` file defines the implementation.
- **sokol-shdc** (shader compiler): prebuilt binaries in https://github.com/floooh/sokol-tools-bin `bin/{osx_arm64,osx,
  linux,linux_arm64,win32}/sokol-shdc`; keep it from the same era as `sokol_gfx.h` (generated code is version-stamped).

## SDL3

- **Callbacks main** (preferred; required for good web/mobile behaviour): `#define SDL_MAIN_USE_CALLBACKS 1` before
  `#include <SDL3/SDL_main.h>`, then implement `SDL_AppInit(void**, int, char**)`, `SDL_AppEvent(void*, SDL_Event*)`,
  `SDL_AppIterate(void*)`, `SDL_AppQuit(void*, SDL_AppResult)`; return `SDL_APP_CONTINUE/SUCCESS/FAILURE`. No `main()`.
  Classic loop also works: `SDL_Init`, `while (SDL_PollEvent(&e))`, render, `SDL_RenderPresent`.
- SDL3 functions return **`bool`** (true = success; SDL2 returned 0) — check with `if (!SDL_Foo()) SDL_GetError()`.
  Event types are `SDL_EVENT_*`; `SDL_CreateWindowAndRenderer(title, w, h, flags, &win, &ren)`; floating-point rects
  (`SDL_FRect`) everywhere in the renderer.
- **SDL_Renderer** (2D: rects, textures, `SDL_RenderGeometry` for colored/textured triangles, `SDL_RenderDebugText`
  with the built-in 8×8 font, `SDL_SetRenderScale`) vs **SDL_GPU** (`SDL_CreateGPUDevice`, command buffers,
  render/compute passes; Vulkan/Metal/D3D12; shaders as SPIR-V/MSL/DXIL — use SDL_shadercross to convert). Use the
  renderer for 2D/UI, SDL_GPU for real 3D.
- Testing/headless: `SDL_VIDEO_DRIVER=dummy` → software renderer everywhere (validated on macOS);
  `SDL_VIDEO_DRIVER=offscreen` → EGL/OpenGL, works on Linux with Mesa, **fails on macOS** ("Could not initialize
  OpenGL / GLES library"). Readback: `SDL_Surface *s = SDL_RenderReadPixels(ren, NULL)` **before**
  `SDL_RenderPresent`, then `SDL_SavePNG(s, "out.png")` (built in since 3.4, no SDL_image needed).
- Audio: `SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, callback, userdata)` +
  `SDL_ResumeAudioStreamDevice`; push with `SDL_PutAudioStreamData`. High DPI: windows are in points;
  `SDL_GetWindowPixelDensity`, `SDL_GetRenderOutputSize` for pixels; `SDL_WINDOW_HIGH_PIXEL_DENSITY` flag.
- Validated build: `cc -O2 app.c $(pkg-config --cflags --libs sdl3) -Wl,-rpath,$CONDA_PREFIX/lib`.

## sokol

- Implementation: in **one** file `#define SOKOL_IMPL` and **one backend** (`SOKOL_METAL`, `SOKOL_GLCORE`,
  `SOKOL_GLES3`, `SOKOL_D3D11`, `SOKOL_WGPU`, `SOKOL_VULKAN`) before including the headers. Shader code must match.
- App: return a `sapp_desc` from `sokol_main()` with `init_cb`, `frame_cb`, `cleanup_cb`, `event_cb`, `width`,
  `height`, `high_dpi`, `logger.func = slog_func`. In `init`: `sg_setup(&(sg_desc){ .environment = sglue_environment(),
  .logger.func = slog_func })`. Frame: `sg_begin_pass(&(sg_pass){ .action = pass_action, .swapchain =
  sglue_swapchain() })`, `sg_apply_pipeline`, `sg_apply_bindings`, `sg_apply_uniforms(UB_name, &SG_RANGE(u))`,
  `sg_draw(0, n, 1)`, `sg_end_pass()`, `sg_commit()`. Quit with `sapp_request_quit()`.
- **Shaders via sokol-shdc**: annotated GLSL with `@vs name … @end`, `@fs …`, `@program tri vs fs`; uniform blocks need
  `layout(binding=0) uniform vs_params { … };`. Compile:
  `sokol-shdc -i tri.glsl -o tri.glsl.h -l glsl410:glsl300es:metal_macos:hlsl5:wgsl` (`-f sokol_odin` for Odin).
  It generates `tri_shader_desc(sg_query_backend())`, `ATTR_tri_<input>`, `UB_<block>`, `<block>_t` structs:
  `.layout.attrs = { [ATTR_tri_position].format = SG_VERTEXFORMAT_FLOAT3, … }`.
- Link (from the `sokol_app.h` header): **macOS** compile as Objective-C (`-x objective-c` or a `.m` file) +
  `-framework Cocoa -framework QuartzCore` + `-framework Metal -framework MetalKit` (Metal) or `-framework OpenGL`
  (GLCORE). **Linux** `-pthread -lX11 -lXi -lXcursor -lGL -ldl -lm` (+`-lEGL` with `SOKOL_FORCE_EGL`, `-lvulkan`);
  sokol_audio now `-lpulse-simple -lpulse` (ALSA only with `SAUDIO_USE_ALSA`, deprecated). **Windows/MSVC**: pragmas.
- Readback: sokol_gfx has no screenshot API. For tests on GLCORE call `glReadPixels` after `sg_commit()` inside
  `frame_cb` (before the swap, `GL_PACK_ALIGNMENT 1`, flip rows); or render into an offscreen image + copy to a buffer.
- Text/debug: `util/sokol_debugtext.h` (`sdtx_setup`, `sdtx_canvas`, `sdtx_printf`, `sdtx_draw()` inside the pass).

## clay

- Implementation: `#define CLAY_IMPLEMENTATION` in one file. Setup: `uint32_t n = Clay_MinMemorySize();
  Clay_Arena a = Clay_CreateArenaWithCapacityAndMemory(n, malloc(n)); Clay_Initialize(a, (Clay_Dimensions){w,h},
  (Clay_ErrorHandler){ fn, ud }); Clay_SetMeasureTextFunction(measure, ud);` (~5.8 MB default; tune with
  `Clay_SetMaxElementCount`). Each frame: `Clay_SetLayoutDimensions`, `Clay_SetPointerState(pos, down)`,
  `Clay_BeginLayout()`, declarations, `Clay_EndLayout(…)`, then draw the returned `Clay_RenderCommandArray`.
- **Declarations differ by version** (both validated):

  | | v0.14 (release) | main (2026) |
  |---|---|---|
  | element | `CLAY({ .id = CLAY_ID("Box"), .layout = {…}, .backgroundColor = c }) { … }` | `CLAY(CLAY_ID("Box"), { .layout = {…} }) { … }`, anonymous `CLAY_AUTO_ID({…})` |
  | text | `CLAY_TEXT(CLAY_STRING("hi"), CLAY_TEXT_CONFIG({ .fontSize = 16 }))` | `CLAY_TEXT(CLAY_STRING("hi"), { .fontSize = 16 })` |
  | end | `Clay_EndLayout()` | `Clay_EndLayout(deltaTime)` (transitions), plus `.transition`, `.overlayColor` |

  Common: sizing `CLAY_SIZING_GROW(min)`, `_FIT()`, `_FIXED(px)`, `_PERCENT(0..1)`; `.padding = CLAY_PADDING_ALL(n)` or
  `{l, r, t, b}`; `.childGap`; `.layoutDirection = CLAY_TOP_TO_BOTTOM`; `.childAlignment = { .x = CLAY_ALIGN_X_CENTER }`;
  `.border = { .color, .width = CLAY_BORDER_OUTSIDE(1) }`; `.cornerRadius = CLAY_CORNER_RADIUS(r)`; `.clip`,
  `.floating`, `.image`, `.custom`. Indexed IDs `CLAY_IDI("Item", i)`. Hover: `Clay_Hovered()` inside an element,
  `Clay_PointerOver(id)` anywhere, `Clay_GetElementData(id).boundingBox` after layout.
- Measure callback: `Clay_Dimensions measure(Clay_StringSlice s, Clay_TextElementConfig *cfg, void *ud)`; text wraps
  on words by default (`CLAY_TEXT_WRAP_WORDS`). `Clay_StringSlice`/`Clay_String` are **not NUL-terminated** —
  copy before passing to C string APIs. Strings must outlive the frame (`CLAY_STRING` needs a literal).
- Render commands: switch on `commandType`: `RECTANGLE` (`renderData.rectangle.backgroundColor/cornerRadius`),
  `BORDER`, `TEXT` (`renderData.text.stringContents/fontSize/textColor`), `IMAGE`, `SCISSOR_START/END`, `CUSTOM`,
  (main) `OVERLAY_COLOR_START/END`. `renderers/SDL3/clay_renderer_SDL3.c` needs SDL3_ttf + SDL3_image; a 40-line
  renderer with `SDL_RenderFillRect` + `SDL_RenderDebugText` is enough for tools/tests.

## WebAssembly (emscripten)

- conda-forge `emscripten` is stale (4.0.9). Use the official emsdk in the project dir:
  `git clone --depth 1 https://github.com/emscripten-core/emsdk && ./emsdk install latest && ./emsdk activate latest
  && source ./emsdk_env.sh` (7.0.0 in Nov 2026; needs Python ≥ 3.10 — on macOS the system one is 3.9: set
  `EMSDK_PYTHON=$(pixi run which python)` from a Pixi env with `python=3.12`).
- sokol (WebGL2): `emcc -O2 -DSOKOL_GLES3 app.c -o app.html -sUSE_WEBGL2=1 --shell-file shell.html` (shaders compiled
  with `glsl300es`; WebGPU: `-DSOKOL_WGPU --use-port=emdawnwebgpu` + `wgsl`). 180 KB wasm for triangle + debugtext.
- SDL3: `emcc -O2 app.c -o app.html --use-port=sdl3 -sALLOW_MEMORY_GROWTH=1` (the port was SDL **3.4.2** in emsdk 7.0.0,
  older than desktop); the callbacks main maps directly onto the browser frame loop. clay+SDL3 ≈ 1.1 MB wasm.
- Shell file: `<canvas id="canvas">` + `var Module = { canvas: … }` + `{{{ SCRIPT }}}`. Serve over HTTP
  (`python -m http.server`), `file://` won't load wasm. clay also has a pure web renderer (`renderers/web`, canvas2d/html).

## From Odin

- **vendor:sdl3** ships with Odin (`import sdl "vendor:sdl3"`, also `vendor:sdl3/image|ttf|mixer`) and links
  `system:SDL3`: on macOS/Linux pass the library path, e.g.
  `odin build . -extra-linker-flags:"-L$LIB -Wl,-rpath,$LIB"` with `LIB=$CONDA_PREFIX/lib` (Pixi `sdl3`). Names drop
  the prefix (`sdl.CreateWindowAndRenderer`, `sdl.RenderReadPixels`, `sdl.SavePNG`), flags are bit_sets
  (`sdl.Init({.VIDEO})`), results enums (`.CONTINUE`). Callbacks main without the C macro:
  `sdl.EnterAppMainCallbacks(0, nil, app_init, app_iterate, app_event, app_quit)` with `proc "c"` callbacks that set
  `context = runtime.default_context()`. Validated with Odin dev-2026-11a.
- **sokol-odin** (https://github.com/floooh/sokol-odin): copy `sokol/`, build the C libs once
  (`cd sokol && ./build_clibs_macos.sh` / `build_clibs_linux.sh`, `build_clibs_wasm.sh`), generate shaders with
  `sokol-shdc … -f sokol_odin`, then `odin run examples/triangle`. Callbacks are `proc "c"`; packages
  `sokol/{app,gfx,glue,log,…}`; default backend Metal on macOS, D3D11 on Windows, GL on Linux (`-define:SOKOL_USE_GL=true`).
- **clay-odin** (clay `bindings/odin/clay-odin`, prebuilt `clay.a`/`.lib`/wasm `.o` per platform):
  `if clay.UI(clay.ID("Outer"))({ layout = { padding = clay.PaddingAll(16) } }) { … }`, `clay.Text(…)`,
  `clay.EndLayout(dt)`, measure/error callbacks are `proc "c"`. Tracks clay `main`; check `clay.odin` for exact procs.

## Pitfalls

- Two backends or two `*_IMPL` translation units → duplicate symbols; mismatched shader language vs backend → black
  screen or `sg_make_shader` validation error (run debug builds: sokol validation is on unless `NDEBUG`).
- macOS sokol without `-x objective-c` → hundreds of Objective-C syntax errors.
- Linux Xvfb from conda-forge aborts with "Failed to activate virtual core keyboard": start it with
  `Xvfb :99 -screen 0 1024x768x24 -xkbdir $CONDA_PREFIX/share/xkeyboard-config-2 &` (xkeyboard-config ≥ 2.45 moved
  the data). Then `DISPLAY=:99`; GL renders through Mesa llvmpipe.
- SDL2 habits in SDL3: int return codes, `SDL_RENDERER_ACCELERATED` flags, `SDL_QUIT` event name, `SDL_RWops` → all
  changed (see SDL `docs/README-migration.md`).
- clay: code samples from the internet target older APIs (`CLAY_RECTANGLE`, `CLAY_LAYOUT` macros from ≤ v0.12, or
  v0.14 vs main above). Match the header.
- Headless CI: `timeout` doesn't exist on macOS; run a fixed number of frames then quit from the program.
