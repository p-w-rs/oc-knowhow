// End-to-end check against a real OpenCode CLI (pinned) in an isolated home with a scripted local model (not a real
// LLM). Verifies inside OpenCode's own runtime: the know-how skills are offered, a private library folder (Markdown and
// PDF) is indexed, and library_catalog / library_search / library_read return cited passages with source status.
// --snapshot loads a verified installed snapshot instead of the checkout.
import assert from "node:assert/strict"
import { spawn, spawnSync } from "node:child_process"
import { access, mkdir, mkdtemp, realpath, rm, writeFile } from "node:fs/promises"
import { createServer } from "node:http"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { pdf } from "../plugin/testdocs.ts"

const OPENCODE_VERSION = "2.2.6"
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const cliPackage = `@opencode/cli-${process.platform}-${process.arch}`
const binary = path.join(root, ".local", "host", "node_modules", cliPackage, "bin", "opencode")
export async function ensureCli() {
  try { await access(binary); return binary } catch {}
  console.log(`Installing ${cliPackage}@${OPENCODE_VERSION} into .local/host ...`)
  await mkdir(path.join(root, ".local", "host"), { recursive: true })
  const result = spawnSync("npm", ["install", "--no-save", "--no-package-lock", "--ignore-scripts", "--prefix", path.join(root, ".local", "host"), "--cache", path.join(root, ".local", "npm-cache"), `${cliPackage}@${OPENCODE_VERSION}`], { stdio: "inherit" })
  if (result.status !== 0) throw new Error(`Could not install ${cliPackage}@${OPENCODE_VERSION}`)
  return binary
}
if (process.argv.includes("--install-cli")) { await ensureCli(); process.exit(0) }
await ensureCli()

const base = await mkdtemp(path.join(await realpath(os.tmpdir()), "oc-knowhow-smoke-"))
const home = path.join(base, "home"), workspace = path.join(base, "workspace"), data = path.join(base, "data"), library = path.join(base, "library")
for (const dir of [workspace, library, data, path.join(home, "config", "opencode")]) await mkdir(dir, { recursive: true })
await writeFile(path.join(library, "ablations.md"), `# Ablation studies\n\n${"Remove one component at a time, keep seeds, data and budget fixed, and report the change with a confidence interval. ".repeat(3)}`)
await writeFile(path.join(library, "old.pdf"), pdf(["Stepwise selection of predictors by p-values, as recommended in this older text."]))
await writeFile(path.join(library, "catalog.json"), JSON.stringify({ sources: [{ file: "old.pdf", id: "old-text", title: "Old Text", status: "dated", note: "stepwise selection is outdated" }] }))
await writeFile(path.join(data, "settings.json"), JSON.stringify({ folders: [{ path: library, name: "Smoke library" }] }))
await writeFile(path.join(data, "refs.json"), JSON.stringify({ sources: [] }))

let pluginPath = root
if (process.argv.includes("--snapshot")) {
  process.env.XDG_DATA_HOME = path.join(home, "data")
  const { deploy, verifyRelease } = await import("./install.mjs")
  pluginPath = await deploy()
  await verifyRelease(pluginPath)
  console.log(`Using snapshot ${pluginPath}`)
}

const calls = [
  { name: "library_catalog", input: {} },
  { name: "library_search", input: { query: "ablation remove one component same seeds", mode: "keyword" } },
  { name: "library_search", input: { query: "stepwise selection p-values", mode: "keyword" } },
  { name: "library_read", input: { ref: "REF" } },
]
const toolResults = []
const requests = []
let modelRequests = 0, toolNames = []
const server = createServer(async (req, res) => {
  const chunks = []
  for await (const part of req) chunks.push(part)
  let body
  try { body = JSON.parse(Buffer.concat(chunks).toString()) } catch { res.writeHead(400); res.end(); return }
  const main = Array.isArray(body.tools) && body.tools.some(tool => tool.function?.name === "library_search")
  if (main) {
    modelRequests++
    toolNames = body.tools.map(tool => tool.function?.name)
    requests.push(JSON.stringify(body))
    toolResults.length = 0
    for (const message of body.messages ?? []) if (message.role === "tool") toolResults.push(typeof message.content === "string" ? message.content : JSON.stringify(message.content))
  }
  // Wait until the library is indexed before the first call (indexing runs in the background at startup).
  if (main && modelRequests === 1) await new Promise(resolve => setTimeout(resolve, 8000))
  const call = main ? calls.shift() : undefined
  if (call?.input.ref === "REF") call.input.ref = /\[ref (\S+);/.exec(toolResults.join("\n"))?.[1] ?? "missing#0"
  if (!body.stream) {
    res.writeHead(200, { "content-type": "application/json" })
    res.end(JSON.stringify({ id: "x", object: "chat.completion", model: "probe", choices: [{ index: 0, message: { role: "assistant", content: "Smoke" }, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }))
    return
  }
  const chunk = (delta, finish_reason = null) => ({ id: `c${modelRequests}`, object: "chat.completion.chunk", created: 0, model: "probe", choices: [{ index: 0, delta, finish_reason }] })
  const events = call
    ? [chunk({ role: "assistant", tool_calls: [{ index: 0, id: `call-${modelRequests}`, type: "function", function: { name: call.name, arguments: JSON.stringify(call.input) } }] }), chunk({}, "tool_calls")]
    : [chunk({ role: "assistant", content: main ? "OC_KNOWHOW_SMOKE_COMPLETE" : "Smoke" }), chunk({}, "stop")]
  res.writeHead(200, { "content-type": "text/event-stream" })
  res.end(events.map(value => `data: ${JSON.stringify(value)}\n\n`).join("") + "data: [DONE]\n\n")
})
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
await writeFile(path.join(home, "config", "opencode", "opencode.json"), JSON.stringify({
  $schema: "https://opencode.ai/config.json", model: "probe/probe",
  plugins: [{ package: pluginPath, options: { dataDirectory: data, referencesFile: path.join(data, "refs.json") } }],
  providers: { probe: {
    package: "@opencode/ai/providers/openai-compatible",
    settings: { baseURL: `http://127.0.0.1:${server.address().port}/v1`, apiKey: "synthetic-not-a-secret" },
    models: { probe: { limit: { context: 64000, output: 1024 }, capabilities: { tools: true, input: ["text"], output: ["text"] } } },
  } },
}))
const env = {
  HOME: home, TMPDIR: home, PATH: [path.join(root, ".pixi/envs/default/bin"), "/usr/bin", "/bin"].join(":"),
  XDG_CONFIG_HOME: path.join(home, "config"), XDG_DATA_HOME: path.join(home, "data"), XDG_CACHE_HOME: path.join(home, "cache"), XDG_STATE_HOME: path.join(home, "state"),
  OPENCODE_DISABLE_CLAUDE_CODE: "true",
}
let stdout = "", stderr = ""
const child = spawn(binary, ["run", "--standalone", "--auto", "--format", "json", "--model", "probe/probe", "oc-knowhow smoke"], { cwd: workspace, env, detached: true, stdio: ["ignore", "pipe", "pipe"] })
child.stdout.on("data", d => { stdout += d }); child.stderr.on("data", d => { stderr += d })
const timer = setTimeout(() => { try { process.kill(-child.pid, "SIGKILL") } catch {} }, 240_000)
const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve) })
clearTimeout(timer); server.close()

const logs = path.join(root, ".local", "smoke-host.log")
await mkdir(path.dirname(logs), { recursive: true })
await writeFile(logs, `${stdout}\n----- stderr -----\n${stderr}`, { mode: 0o600 })
try {
  assert.equal(code, 0, `opencode exited ${code}; see ${logs}`)
  assert.equal(calls.length, 0, "every scripted call was made")
  assert.ok(stdout.includes("OC_KNOWHOW_SMOKE_COMPLETE"), "run completed")
  assert.doesNotMatch(stderr, /\[oc-knowhow\] (disabled|reload failed|skills not registered|library update failed)/, "no plugin warnings")
  for (const name of ["library_catalog", "library_search", "library_read"]) assert.ok(toolNames.includes(name), `${name} offered`)
  for (const skill of ["stats-inference", "experiment-design", "gnuplot", "diagrams", "ml-deploy", "ml-data", "ml-tuning", "ml-qat"]) assert.ok(requests[0].includes(skill), `skill ${skill} offered`)
  const all = toolResults.join("\n")
  assert.match(all, /ablations \[Smoke library; unknown; 1 sections\]/, "catalog lists the folder")
  assert.match(all, /old-text \[Smoke library; dated/, "catalog shows status from catalog.json")
  assert.match(all, /1\. ablations — Ablation studies/, "search finds the section")
  assert.match(all, /NOTE: dated: stepwise selection is outdated/, "dated source flagged")
  assert.match(all, /Cite: ablations, Ablation studies/, "read returns a citation")
  if (pluginPath !== root) await (await import("./install.mjs")).verifyRelease(pluginPath)
  console.log(`oc-knowhow host smoke passed${pluginPath !== root ? " from a snapshot" : ""} (OpenCode ${OPENCODE_VERSION}, ${process.platform}-${process.arch}, ${modelRequests} model requests).`)
  await rm(base, { recursive: true, force: true })
} catch (error) {
  console.error(`Smoke failed. Scratch home kept at ${base}; logs at ${logs}`)
  throw error
}
