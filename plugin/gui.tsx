import { Plugin, SettingsPage, type Context } from "@opencode/plugin/gui"
import { createSignal, For, onCleanup, onMount, Show, type JSX } from "solid-js"
import { KnowhowRpc, type StateView } from "./rpc.js"

const muted: JSX.CSSProperties = { opacity: 0.7, "font-size": "12px" }
const card: JSX.CSSProperties = { border: "1px solid color-mix(in srgb, currentColor 14%, transparent)", "border-radius": "8px", padding: "12px", display: "flex", "flex-direction": "column", gap: "8px" }
const message = (error: unknown) => (error instanceof Error ? error.message : String(error)).replace(/^.*?Error: /, "")

function KnowhowView(props: { ctx: Context }) {
  const { ctx } = props
  const [state, setState] = createSignal<StateView>()
  const [error, setError] = createSignal<string>()
  const [folder, setFolder] = createSignal("")
  const api = () => ctx.client.rpc(KnowhowRpc)
  const refresh = async () => { try { setState(await api().state({}) as unknown as StateView); setError(undefined) } catch (cause) { setError(message(cause)) } }
  const act = async (action: () => Promise<unknown>, success?: string) => {
    try { const next = await action() as StateView; if (next?.settings) setState(next); if (success) ctx.toast.show({ title: success, variant: "success" }) }
    catch (cause) { ctx.toast.show({ title: "Know-how", description: message(cause), variant: "error" }) }
  }
  onMount(() => {
    void refresh()
    const timer = setInterval(() => { if (state()?.progress || state()?.search.installing || !state()) void refresh() }, 1500)
    onCleanup(() => clearInterval(timer))
  })
  const toggle = (key: "ml" | "datascience" | "figures" | "odin" | "robotics" | "clibs" | "library", title: string, text: string) => (
    <div style={card}>
      <ctx.ui.Switch label={title} checked={state()!.settings[key]} onChange={value => void act(() => api().update({ [key]: value }))} />
      <span style={muted}>{text}</span>
    </div>
  )
  const counts = () => {
    const references = state()!.references
    return { downloaded: references.filter(item => item.state === "downloaded").length, missing: references.filter(item => item.state === "missing").length, links: references.filter(item => item.state === "link").length }
  }
  return (
    <div style={{ display: "flex", "flex-direction": "column", gap: "12px", "font-size": "13px" }}>
      <Show when={error() && !state()}><div style={{ color: "#e03131" }}>oc-knowhow is not answering: {error()}. Is it installed on this server?</div></Show>
      <Show when={!state() && !error()}><ctx.ui.Loader /></Show>
      <Show when={state()}>{current => <>
        {toggle("datascience", "Data science", "Skills: stats-inference (choosing and running tests, effect sizes and intervals, multiple comparisons, Bayesian options, what is outdated), experiment-design (ablations, whether model A really beats B, seeds and budgets, reporting standards) and datasets (collection, labeling, leakage, splits, documentation, versioning); arrow (columnar memory, Parquet, IPC, Flight, the C Data Interface from C and Odin) and polars (lazy queries, time-series joins, streaming, GPU engine).")}
        {toggle("figures", "Figures and diagrams", "Skills: gnuplot (2D/3D, interactive and animated plots, more than three dimensions, publication output, worked examples) and diagrams (D2, Graphviz, Mermaid, TikZ). Agents render and look at the result before showing you.")}
        {toggle("ml", "Machine learning", "Skills: ml-training (CUDA/ROCm Pixi environments, MLflow), ml-data (formats and loaders that keep GPUs busy), ml-tuning (Smith's LR range test and 1cycle, batch size, optimizers incl. Muon, normalization, regularization, EMA), ml-qat (quantization-aware training), ml-metrics (COCO AP/AR, TIDE, and metrics for every task), ml-deploy (TensorRT 11 and Jetson) and gpu-kernels (Triton, CUDA/HIP).")}
        {toggle("odin", "Odin", "Skills: odin (language, core and vendor packages, the compiler at expert level, C interop, testing), odin-performance (allocators and memory strategies, data-oriented design, SIMD, profiling) and odin-targets (embedded/freestanding and WebAssembly). The library holds the Odin core and vendor source to search.")}
        {toggle("robotics", "Robotics", "Skills: zenoh (pub/sub, queries, routers, security, shared memory, zenoh-pico), zenoh-ros2 (rmw_zenoh, zenoh-bridge-ros2dds), mcap (recording and reading logs), rerun (visualizing robot data), robot-serialization (FlatBuffers, Protobuf over Zenoh and MCAP), dora (dataflow robotics), robot-math (Eigen, Lie groups, GTSAM, Ceres, ICP), mcu-tooling (probe-rs, Renode, pico-sdk, ESP-IDF), simulators mujoco (incl. MJX/Warp), genesis and isaac-sim (incl. Isaac Lab), and opencv (calibration, geometry, features, video, DNN).")}
        {toggle("clibs", "C libraries", "Skills: c-platform (SDL3, sokol, clay), c-networking (ENet, librg, zpl), c-crypto (Monocypher, libsodium, encrypting ENet), c-data (yyjson, xxHash, zstd, lz4), c-gamedev (flecs, Jolt, meshoptimizer, ufbx, cgltf) and c-perf (Tracy, mimalloc, rpmalloc), from C and from Odin. The library holds their source to search.")}
        <div style={card}>
          <ctx.ui.Switch label="Reference library" checked={current().settings.library} onChange={value => void act(() => api().update({ library: value }))} />
          <span style={muted}>Agents search books, papers, manuals and standards for ground truth, with page citations (library_catalog, library_search, library_read). Everything stays on this computer: free references are downloaded here, and your own folders are indexed here, never shared or exported.</span>
          <Show when={current().settings.library}>
            <div style={{ display: "flex", gap: "8px", "align-items": "center", "flex-wrap": "wrap" }}>
              <span style={muted}>Free references: {counts().downloaded} downloaded, {counts().missing} not yet, {counts().links} read online.</span>
              <Show when={counts().missing}><ctx.ui.Button size="small" variant="contrast" icon="download" onClick={() => void act(() => api().downloadReferences({}), "Downloading in the background")}>Download free references</ctx.ui.Button></Show>
            </div>
            <Show when={current().references.some(item => item.error)}><span style={{ ...muted, color: "#e03131" }}>Could not download: {current().references.filter(item => item.error).map(item => item.title).join(", ")}</span></Show>
            <span style={muted}>Your folders (private; PDFs, web pages, Markdown, notebooks, Office files; an optional catalog.json describes each file):</span>
            <For each={current().settings.folders}>{item => (
              <div style={{ display: "flex", gap: "8px", "align-items": "center" }}>
                <span style={{ flex: 1 }}><b>{item.name}</b> <span style={muted}>{item.path}</span></span>
                <ctx.ui.IconButton icon="trash" label={`Remove ${item.name}`} size="small" variant="ghost" onClick={() => void act(() => api().removeFolder({ path: item.path }), "Folder removed from the library")} />
              </div>
            )}</For>
            <div style={{ display: "flex", gap: "6px", "align-items": "center" }}>
              <ctx.ui.TextInput label="Folder" placeholder="/Users/you/Documents/ds-library" value={folder()} onInput={setFolder} />
              <ctx.ui.Button size="small" disabled={!folder().trim()} onClick={() => void act(async () => { const next = await api().addFolder({ path: folder().trim() }); setFolder(""); return next }, "Folder added; indexing in the background")}>Add folder</ctx.ui.Button>
            </div>
            <div style={{ display: "flex", gap: "8px", "align-items": "center", "flex-wrap": "wrap" }}>
              <span style={muted}>{current().sources.length} sources, {current().sources.reduce((sum, item) => sum + item.sections, 0)} sections indexed.{current().lastSync ? ` Last update ${new Date(current().lastSync!.at).toLocaleTimeString()}${current().lastSync!.failed.length ? `; ${current().lastSync!.failed.length} unreadable` : ""}.` : ""}</span>
              <ctx.ui.Button size="small" variant="ghost" icon="refresh" onClick={() => void act(() => api().reindex({}), "Updating the index")}>Update index</ctx.ui.Button>
            </div>
            <Show when={current().progress}>{progress => <span style={muted}>{progress().step} ({Math.min(progress().done + 1, progress().total)}/{progress().total})…</span>}</Show>
            <Show when={!current().search.installed && current().search.supported}>
              <div style={{ display: "flex", gap: "8px", "align-items": "center" }}>
                <span style={muted}>{current().search.installing ? `${current().search.installing!.step}…` : "Meaning-based search is not installed (keyword search works). Download about 290 MB once."}</span>
                <Show when={!current().search.installing}><ctx.ui.Button size="small" icon="download" onClick={() => void act(() => api().installSearch({}))}>Download</ctx.ui.Button></Show>
              </div>
            </Show>
            <Show when={current().search.shared}><span style={muted}>Meaning-based search: {current().search.shared}.</span></Show>
          </Show>
        </div>
        <span style={muted}>oc-knowhow {current().version} · data in {current().dataDirectory}</span>
      </>}</Show>
    </div>
  )
}

export default Plugin.define({
  setup(ctx) {
    ctx.add(SettingsPage, {
      id: "knowhow", title: "Know-how", icon: "graduation-cap",
      entries: [{ id: "knowhow", title: "Know-how", description: "Skills and the reference library for data science, figures, diagrams, machine learning, Odin, robotics data (Zenoh, ROS 2, MCAP) and C libraries", keywords: "oc-knowhow odin zenoh ros2 mcap sdl3 sokol enet statistics data science experiment ablation datasets gnuplot plots figures diagrams d2 graphviz tikz library references tensorrt" }],
      render: () => (
        <ctx.ui.SettingsLayout title="Know-how" description="Expert know-how agents load when a task needs it, and a private reference library they can cite.">
          <KnowhowView ctx={ctx} />
        </ctx.ui.SettingsLayout>
      ),
    })
  },
})
