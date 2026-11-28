import { after, before, test } from "node:test"
import assert from "node:assert/strict"
import { createServer, type Server } from "node:http"
import { mkdir, mkdtemp, realpath, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import type { Plugin } from "@opencode/plugin"
import plugin, { createPlugin, parseOptions, PLUGIN_ID } from "./index.js"
import { pdf } from "./testdocs.js"

const dirs: string[] = []
let server: Server, base = ""
before(async () => {
  server = createServer((req, res) => {
    if (req.url === "/stats.pdf") { res.writeHead(200, { "content-type": "application/pdf" }); res.end(Buffer.from(pdf(["Effect sizes with confidence intervals should be reported instead of significance verdicts."]))); return }
    if (req.url === "/page.html") { res.writeHead(200, { "content-type": "text/html" }); res.end("<h1>Colour maps</h1><p>Perceptually uniform colour maps avoid distorting data; rainbow maps mislead readers.</p>"); return }
    res.writeHead(404); res.end()
  })
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve))
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`
})
after(async () => { server.close(); await Promise.all(dirs.map(dir => rm(dir, { recursive: true, force: true }))) })
const scratch = async () => { const dir = await mkdtemp(join(tmpdir(), "ockh-")); dirs.push(dir); return dir }

async function host(options: { deny?: (path: string) => boolean; jaiRoot?: string } = {}) {
  const data = await scratch()
  const referencesFile = join(data, "refs.json")
  await writeFile(referencesFile, JSON.stringify({ sources: [
    { id: "stats-guide", title: "Stats Guide", kind: "pdf", url: `${base}/stats.pdf`, status: "current", fields: ["statistics"], useFor: "reporting effects" },
    { id: "colour", title: "Colour Paper", kind: "html", url: `${base}/page.html`, status: "current", fields: ["visualization"] },
    { id: "online-book", title: "Online Book", kind: "link", url: "https://example.org/book", status: "current", fields: ["causal"] },
    { id: "broken", title: "Broken Link", kind: "pdf", url: `${base}/missing.pdf`, status: "current" },
  ] }))
  const tools = new Map<string, { execute: (input: unknown, context: unknown) => Promise<{ content: string }> }>()
  const skills: { id: string; content: string }[] = []
  const transforms: ((editor: any) => void)[] = [], skillTransforms: ((editor: any) => void)[] = []
  let rpc: any, context: any
  const rebuild = () => { tools.clear(); for (const t of transforms) t({ add: (tool: any) => tools.set(tool.name, tool) }) }
  const rebuildSkills = () => { skills.length = 0; for (const t of skillTransforms) t({ add: (skill: any) => skills.push(skill) }) }
  const ctx = {
    // Tests never pick up a Jai compiler installed on the machine running them.
    options: { dataDirectory: data, referencesFile, jaiRoot: options.jaiRoot ?? join(data, "no-jai") },
    permission: { assert: async (input: { resources: string[] }) => { if (options.deny?.(input.resources[0]!)) throw Object.assign(new Error("denied"), { name: "Permission.BlockedError" }) } },
    tool: { transform: async (cb: any) => { transforms.push(cb); rebuild(); return { dispose: async () => {} } }, reload: async () => rebuild() },
    skill: { transform: async (cb: any) => { skillTransforms.push(cb); rebuildSkills(); return { dispose: async () => {} } }, reload: async () => rebuildSkills() },
    rpc: { register: async (_: unknown, handlers: any) => { rpc = handlers; return { dispose: async () => {} } } },
    session: { hook: async (name: string, cb: any) => { if (name === "context") context = cb; return { dispose: async () => {} } } },
  }
  const cleanup = await createPlugin().setup(ctx as unknown as Plugin.Context) as () => Promise<void>
  const call = async (name: string, input: unknown) => (await tools.get(name)!.execute(input, { sessionID: "s", agent: "build", messageID: "m", id: "c", signal: new AbortController().signal })).content
  const until = async (check: () => Promise<boolean>) => { for (let i = 0; i < 400 && !(await check()); i++) await new Promise(r => setTimeout(r, 50)) }
  const system = async (tools?: Record<string, unknown>) => { const input = { sessionID: "s", system: [] as { text: string }[], tools }; await context?.(input); return input.system.map(item => item.text).join("\n") }
  return { data, tools, skills, call, until, cleanup, system, rpc: () => rpc }
}

test("identity, tools, skills grouped by setting, example path filled in", async () => {
  assert.equal(plugin.id, PLUGIN_ID)
  assert.throws(() => parseOptions({ dataDirectory: "rel" }), /absolute/)
  const h = await host()
  assert.deepEqual([...h.tools.keys()].sort(), ["library_catalog", "library_read", "library_search"])
  const ids = h.skills.map(s => s.id)
  for (const id of ["datasets", "diagrams", "experiment-design", "field-methods", "gnuplot", "gpu-kernels", "ml-data", "ml-deploy", "ml-metrics", "ml-qat", "ml-training", "ml-tuning", "odin", "odin-performance", "odin-targets", "zenoh", "zenoh-ros2", "mcap", "c-platform", "c-networking", "stats-inference", "arrow", "polars", "rerun", "robot-serialization", "dora", "robot-math", "mcu-tooling", "c-crypto", "c-data", "c-gamedev", "c-perf", "mujoco", "genesis", "isaac-sim", "opencv"]) assert.ok(ids.includes(id), `skill ${id} registered`)
  assert.match(h.skills.find(s => s.id === "gnuplot")!.content, /examples are in: .*examples\/gnuplot/)
  assert.match(await h.system(), /library_search/)
  assert.equal(await h.system({ read: {} }), "", "no hint for agents without the library tools")
  await h.rpc().update({ ml: false, library: false })
  assert.equal(h.tools.size, 0)
  assert.equal(await h.system(), "")
  assert.ok(!h.skills.some(s => s.id === "ml-deploy"))
  await h.cleanup()
})

test("download free references, index them, search with citations; links are listed; a failed download is reported", async () => {
  const h = await host()
  await h.rpc().downloadReferences({})
  await h.until(async () => { const state = await h.rpc().state({}); return !state.progress && state.sources.length >= 3 })
  const state = await h.rpc().state({})
  assert.deepEqual(state.references.map((r: { id: string; state: string }) => [r.id, r.state]), [["stats-guide", "downloaded"], ["colour", "downloaded"], ["online-book", "link"], ["broken", "missing"]])
  assert.ok(state.references.find((r: { id: string }) => r.id === "broken").error)
  const catalog = await h.call("library_catalog", {})
  assert.match(catalog, /stats-guide \[free; current; 1 sections\] Stats Guide/)
  assert.match(catalog, /read online: https:\/\/example.org\/book/)
  assert.match(await h.call("library_catalog", { field: "visualization" }), /Colour Paper/)
  const found = await h.call("library_search", { query: "confidence intervals effect sizes", mode: "keyword" })
  assert.match(found, /1\. Stats Guide — \(start\), p\. 1/)
  const ref = /\[ref (\S+);/.exec(found)![1]!
  assert.match(await h.call("library_read", { ref }), /Cite: Stats Guide, \(start\), p\. 1/)
  await h.cleanup()
})

test("a private folder is indexed; read permission on the folder is respected", async () => {
  const folder = await scratch()
  await writeFile(join(folder, "private-notes.md"), `# Ablations\n\n${"Remove one component at a time with the same seeds and budget. ".repeat(4)}`)
  const h = await host({ deny: path => path === folder })
  try {
    await h.rpc().addFolder({ path: folder, name: "My books" })
    await h.until(async () => { const state = await h.rpc().state({}); return !state.progress && state.sources.some((s: { id: string }) => s.id === "private-notes") })
    const found = await h.call("library_search", { query: "ablation same seeds", mode: "keyword" })
    assert.match(found, /0 result\(s\).*1 hidden by read permissions/)
    await assert.rejects(h.call("library_read", { ref: "x" }), /Not a section reference|No section/)
    await assert.rejects(h.call("library_read", { ref: "private-notes#0" }), /denied/, "a ref naming only the source id is checked too")
    await assert.rejects(h.call("library_catalog", { source: "private-notes" }), /denied/)
  } finally { await h.cleanup() }
})

test("Jai: four skills with a live version note; the installed bundle becomes a local library, guarded by read permission", async () => {
  const bundle = await scratch()
  await mkdir(join(bundle, "modules", "Basic"), { recursive: true })
  await mkdir(join(bundle, "modules", "d3d12"), { recursive: true })
  await mkdir(join(bundle, "how_to"), { recursive: true })
  await mkdir(join(bundle, "examples", "demo"), { recursive: true })
  await mkdir(join(bundle, "bin"), { recursive: true })
  await writeFile(join(bundle, "CHANGELOG.txt"), "Version: beta 0.2.040, 1 March 2027\n---------------------\nRenamed set_temporary_storage_mark to set_temporary_mark (example entry).\n\nVersion: beta 0.2.032, 26 November 2026\n---------------------\nOlder notes about array literals.\n")
  await writeFile(join(bundle, "modules", "Basic", "module.jai"), "// Frees everything allocated with the temporary allocator since the program started or the last reset.\nreset_temporary_storage :: () {\n}\n")
  await writeFile(join(bundle, "modules", "d3d12", "bindings.jai"), "ID3D12Device :: struct { unique_windows_marker: int; }\n")
  await writeFile(join(bundle, "how_to", "012_temporary_storage.jai"), "// Temporary storage is a per-frame arena that you reset once per frame.\nmain :: () {\n}\n")
  await writeFile(join(bundle, "examples", "demo", "first.jai"), "// Builds the demo with a metaprogram.\nbuild :: () {\n}\n")
  const real = await realpath(bundle)
  let denyJai = false
  const h = await host({ jaiRoot: bundle, deny: path => denyJai && path === real })
  try {
    const ids = h.skills.map(s => s.id)
    for (const id of ["jai", "jai-metaprogramming", "jai-systems", "jai-modules"]) assert.ok(ids.includes(id), `skill ${id} registered`)
    const note = h.skills.find(s => s.id === "jai-systems")!.content
    assert.match(note, /Validated with Jai beta 0\.2\.032/)
    assert.match(note, /Installed here: Jai beta 0\.2\.040 \(1 March 2027\)/)
    assert.match(note, /NEWER than the one this skill was validated with/)
    assert.match(note, /examples\/jai\/jai-systems/)
    // The bundle is indexed as four local sources (Windows-only bindings left out).
    await h.rpc().reindex({})
    await h.until(async () => { const state = await h.rpc().state({}); return !state.progress && state.sources.filter((s: { id: string }) => s.id.startsWith("jai-")).length === 4 })
    const state = await h.rpc().state({})
    assert.equal(state.jai.found.version, "beta 0.2.040")
    assert.equal(state.jai.found.newer, true)
    assert.deepEqual(state.sources.filter((s: { id: string }) => s.id.startsWith("jai-")).map((s: { id: string }) => s.id).sort(), ["jai-changelog", "jai-examples-src", "jai-how-to", "jai-modules-src"])
    const found = await h.call("library_search", { query: "reset temporary storage", sources: ["jai-modules-src"], mode: "keyword" })
    assert.match(found, /modules\/Basic\/module\.jai/)
    assert.match(found, /reset_temporary_storage/)
    assert.match(await h.call("library_search", { query: "set_temporary_mark renamed", mode: "keyword" }), /Jai CHANGELOG \(beta 0\.2\.040\) — Version: beta 0\.2\.040, 1 March 2027/)
    assert.match(await h.call("library_search", { query: "unique_windows_marker", mode: "keyword" }), /0 result/)
    assert.match(await h.call("library_catalog", { field: "jai" }), /jai-how-to \[Jai, local; current; \d+ sections\]/)
    // Read permission on the Jai folder applies like on the user's own folders.
    denyJai = true
    assert.match(await h.call("library_search", { query: "reset temporary storage", mode: "keyword" }), /hidden by read permissions/)
    await assert.rejects(h.call("library_read", { ref: "jai-how-to#0" }), /denied/)
    denyJai = false
    // Turning Jai off removes the skills and the local sources.
    await h.rpc().update({ jai: false })
    assert.ok(!h.skills.some(s => s.id.startsWith("jai")))
    await h.until(async () => { const s = await h.rpc().state({}); return !s.progress && !s.sources.some((x: { id: string }) => x.id.startsWith("jai-")) })
  } finally { await h.cleanup() }
})
