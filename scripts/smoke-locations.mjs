// End-to-end check against a real OpenCode server (pinned version, or OC_KNOWHOW_SMOKE_OPENCODE=<version>) that every
// project location gets the plugin. OpenCode evaluates the plugin once per location; 1.7.0-1.7.2 worked only in the
// first location of a server process. Boots several locations, switches the config to a second copy of the plugin (what
// `pixi run install` does), boots more locations, and switches back. Each time every location must offer all know-how
// skills and answer the settings page.
import assert from "node:assert/strict"
import { spawn, spawnSync } from "node:child_process"
import { access, cp, mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises"
import net from "node:net"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { GROUPS } from "../plugin/settings.ts"

const OPENCODE_VERSION = process.env.OC_KNOWHOW_SMOKE_OPENCODE || "2.4.2"
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const cliPackage = `@opencode/cli-${process.platform}-${process.arch}`
const prefix = path.join(root, ".local", `host-${OPENCODE_VERSION}`)
const binary = path.join(prefix, "node_modules", cliPackage, "bin", "opencode")
try { await access(binary) } catch {
  console.log(`Installing ${cliPackage}@${OPENCODE_VERSION} into ${path.relative(root, prefix)} ...`)
  await mkdir(prefix, { recursive: true })
  const result = spawnSync("npm", ["install", "--no-save", "--no-package-lock", "--ignore-scripts", "--prefix", prefix, "--cache", path.join(root, ".local", "npm-cache"), `${cliPackage}@${OPENCODE_VERSION}`], { stdio: "inherit" })
  if (result.status !== 0) throw new Error(`Could not install ${cliPackage}@${OPENCODE_VERSION}`)
}

const expected = Object.values(GROUPS).flat().length
const base = await mkdtemp(path.join(await realpath(os.tmpdir()), "oc-knowhow-locations-"))
const home = path.join(base, "home"), data = path.join(base, "data")
const locations = Array.from({ length: 5 }, (_, i) => path.join(base, `project-${i + 1}`))
for (const dir of [...locations, data, path.join(home, "config", "opencode")]) await mkdir(dir, { recursive: true })
await writeFile(path.join(data, "settings.json"), JSON.stringify({ ...Object.fromEntries(Object.keys(GROUPS).map(group => [group, true])), library: true, autoDownload: false, folders: [] }))
await writeFile(path.join(data, "refs.json"), JSON.stringify({ sources: [] }))
// A second copy of the plugin, like a newly installed release (its dependencies are shared).
const second = path.join(base, "plugin-copy")
for (const part of ["package.json", "plugin", "skill", "examples", "dist", "references.json"]) await cp(path.join(root, part), path.join(second, part), { recursive: true })
await symlink(path.join(root, "node_modules"), path.join(second, "node_modules"))

const configPath = path.join(home, "config", "opencode", "opencode.json")
const usePlugin = plugin => writeFile(configPath, JSON.stringify({
  $schema: "https://opencode.ai/config.json",
  plugins: [{ package: plugin, options: { dataDirectory: data, referencesFile: path.join(data, "refs.json"), jaiRoot: path.join(data, "no-jai") } }],
}))
await usePlugin(root)

const port = await new Promise(resolve => { const server = net.createServer(); server.listen(0, "127.0.0.1", () => { const { port } = server.address(); server.close(() => resolve(port)) }) })
const password = `smoke-${Math.random().toString(36).slice(2)}`
const headers = { authorization: `Basic ${Buffer.from(`opencode:${password}`).toString("base64")}` }
const env = {
  HOME: home, TMPDIR: home, PATH: ["/usr/bin", "/bin"].join(":"),
  XDG_CONFIG_HOME: path.join(home, "config"), XDG_DATA_HOME: path.join(home, "data"), XDG_CACHE_HOME: path.join(home, "cache"), XDG_STATE_HOME: path.join(home, "state"),
  OPENCODE_DISABLE_CLAUDE_CODE: "true", OPENCODE_SERVER_PASSWORD: password,
}
let output = ""
const child = spawn(binary, ["serve", "--hostname", "127.0.0.1", "--port", String(port)], { cwd: locations[0], env, detached: true, stdio: ["ignore", "pipe", "pipe"] })
child.stdout.on("data", chunk => { output += chunk }); child.stderr.on("data", chunk => { output += chunk })
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const call = async (route, dir, body) => {
  const url = `http://127.0.0.1:${port}${route}?location%5Bdirectory%5D=${encodeURIComponent(dir)}`
  const response = await fetch(url, body ? { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify(body) } : { headers })
  const text = await response.text()
  try { return { status: response.status, body: JSON.parse(text) } } catch { return { status: response.status, body: text } }
}
const list = body => Array.isArray(body) ? body : body?.data ?? []
const own = new Set(Object.values(GROUPS).flat())
async function look(dir) {
  const skills = list((await call("/api/skill", dir)).body).filter(skill => own.has(skill.id ?? skill.name)).length
  const plugin = list((await call("/api/plugin", dir)).body).find(item => item.id === "oc-knowhow")
  const rpc = await call("/api/rpc/oc-knowhow.admin/state", dir, { input: {} })
  const state = rpc.body?.output
  return { skills, path: plugin?.source?.path, rpc: rpc.status === 200 && Array.isArray(state?.problems) ? "ok" : `${rpc.status} ${rpc.body?.type ?? ""}`, problems: state?.problems ?? [], library: !!state?.search?.platform && state?.search?.supported !== undefined && Array.isArray(state?.sources) }
}
/** Waits until a location offers every skill from the given copy of the plugin and its settings page answers without problems. */
async function ready(dir, plugin, step) {
  let last
  for (const started = Date.now(); Date.now() - started < 60_000; await sleep(500)) {
    last = await look(dir)
    if (last.skills === expected && last.rpc === "ok" && !last.problems.length && (!last.path || last.path === plugin)) return
  }
  assert.fail(`${step}: ${path.basename(dir)} has ${last.skills}/${expected} skills, settings page ${last.rpc}, plugin ${last.path}${last.problems.length ? `, problems: ${last.problems.join(" | ")}` : ""}`)
}
try {
  for (let i = 0; i < 120; i++) { try { if ((await fetch(`http://127.0.0.1:${port}/api/info`, { headers })).status < 500) break } catch {} await sleep(500) }
  for (const dir of locations.slice(0, 3)) await ready(dir, root, "first boot")
  await usePlugin(second)
  for (const dir of locations.slice(0, 3)) await ready(dir, second, "after switching to another copy")
  for (const dir of locations.slice(3)) await ready(dir, second, "locations opened after the switch")
  await usePlugin(root)
  for (const dir of locations) await ready(dir, root, "after switching back")
  assert.doesNotMatch(output, /\[oc-knowhow\] (disabled|reference library disabled|skills not registered|settings page not available)/, "no plugin warnings")
  console.log(`oc-knowhow location smoke passed (OpenCode ${OPENCODE_VERSION}, ${process.platform}-${process.arch}): ${expected} skills and the settings page in ${locations.length} locations, across two live switches of the plugin.`)
  await rm(base, { recursive: true, force: true })
} catch (error) {
  const log = path.join(root, ".local", "smoke-locations.log")
  await writeFile(log, output, { mode: 0o600 })
  console.error(`Smoke failed. Scratch home kept at ${base}; server output in ${log}`)
  throw error
} finally {
  try { process.kill(-child.pid, "SIGTERM") } catch {}
}
