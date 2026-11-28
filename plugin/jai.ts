// Jai support. Jai is in closed beta: its compiler bundle (how_to lessons, module sources, examples, CHANGELOG) is
// for private distribution only, so nothing of it ships with this plugin. Instead the plugin finds the compiler the
// user installed and indexes that copy locally, stamped with its version; the skills say which version they were
// validated with, so agents notice when the installed beta is newer.
import { open, realpath, stat } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import type { SourceInput } from "./library.js"

/** The compiler version the Jai skills and examples were validated with. */
export const VALIDATED_JAI = "beta 0.2.032"
export const VALIDATED_JAI_DATE = "26 November 2026"
export const JAI_LIBRARY = "jai-local"
export const JAI_SKILLS = ["jai", "jai-metaprogramming", "jai-systems", "jai-modules"] as const

export interface JaiInstall {
  /** The folder as configured or found (e.g. ~/jai/current). */
  readonly root: string
  /** The resolved folder (symlinks followed), used for permission checks and paths shown to agents. */
  readonly path: string
  /** "beta 0.2.032" */
  readonly version: string
  readonly date?: string
  /** The compiler executable for this computer, if present. */
  readonly compiler?: string
}

/** Where to look for the compiler. A configured folder (setting, option or $OC_KNOWHOW_JAI) is the only place looked at. */
export function jaiCandidates(configured?: string, env: NodeJS.ProcessEnv = process.env): string[] {
  if (configured) return [configured]
  if (env.OC_KNOWHOW_JAI) return [env.OC_KNOWHOW_JAI]
  const home = env.HOME || homedir()
  return [join(home, "jai", "current"), join(home, "jai")]
}

/** The first line of CHANGELOG.txt names the version: "Version: beta 0.2.032, 26 November 2026". */
export function parseJaiVersion(text: string): { version: string; date?: string } | undefined {
  const match = /Version:\s*(beta\s+[\d.]+)\s*(?:,\s*([^\n]+?))?\s*$/m.exec(text.slice(0, 400))
  return match ? { version: match[1]!.replace(/\s+/g, " "), ...(match[2] && { date: match[2].trim() }) } : undefined
}

async function head(path: string, bytes = 400): Promise<string> {
  const file = await open(path, "r")
  try { const buffer = Buffer.alloc(bytes); const { bytesRead } = await file.read(buffer, 0, bytes, 0); return buffer.subarray(0, bytesRead).toString("utf8") } finally { await file.close() }
}

/** Recent answers, shared by every plugin instance in this process (one per project location). */
const detected: Map<string, { at: number; result: Promise<JaiInstall | undefined> }> = ((globalThis as Record<symbol, unknown>)[Symbol.for("oc-knowhow.jai")] ??= new Map()) as Map<string, { at: number; result: Promise<JaiInstall | undefined> }>

/** The installed Jai compiler bundle, if any (cheap: a few stats and the first bytes of CHANGELOG.txt; cached 30 s). */
export function detectJai(configured?: string, env: NodeJS.ProcessEnv = process.env, maxAgeMs = 30_000): Promise<JaiInstall | undefined> {
  const key = JSON.stringify(jaiCandidates(configured, env))
  const cached = detected.get(key)
  if (cached && Date.now() - cached.at < maxAgeMs) return cached.result
  const result = findJai(configured, env)
  detected.set(key, { at: Date.now(), result })
  return result
}

async function findJai(configured: string | undefined, env: NodeJS.ProcessEnv): Promise<JaiInstall | undefined> {
  for (const root of jaiCandidates(configured, env)) {
    try {
      const path = await realpath(root)
      if (!(await stat(join(path, "modules", "Basic")).then(info => info.isDirectory(), () => false))) continue
      const parsed = parseJaiVersion(await head(join(path, "CHANGELOG.txt")))
      if (!parsed) continue
      const name = process.platform === "darwin" ? "jai-macos" : process.platform === "win32" ? "jai.exe" : "jai-linux"
      const compiler = await stat(join(path, "bin", name)).then(() => join(path, "bin", name), () => undefined)
      return { root, path, version: parsed.version, ...(parsed.date && { date: parsed.date }), ...(compiler && { compiler }) }
    } catch {}
  }
  return undefined
}

/** The Jails language server binary built by scripts/jails-build.mjs ($JAILS_BIN, else ~/jai/tools/jails/current/jails). */
export async function detectJails(env: NodeJS.ProcessEnv = process.env): Promise<string | undefined> {
  for (const path of [env.JAILS_BIN, join(env.HOME || homedir(), "jai", "tools", "jails", "current", "jails")]) {
    if (path && await stat(path).then(info => info.isFile(), () => false)) return path
  }
  return undefined
}

/** Compares "beta 0.2.032" style versions; negative when a is older. */
export function compareJai(a: string, b: string): number {
  const parts = (value: string) => (value.match(/\d+/g) ?? []).map(Number)
  const x = parts(a), y = parts(b)
  for (let i = 0; i < Math.max(x.length, y.length); i++) { const d = (x[i] ?? 0) - (y[i] ?? 0); if (d) return d }
  return 0
}

/** Windows-only GPU bindings and Windows copies of generated bindings: not indexed (still on disk for grep). */
const WINDOWS_ONLY = ["modules/d3d11", "modules/d3d12", "modules/dxgi", "modules/dxc_compiler", "modules/d3d_compiler", "modules/nvidia_aftermath", "modules/radeon_gpu_analyzer", "modules/Vulkan/generated_windows.jai", "modules/freetype/windows.jai", "modules/ImGui/windows.jai", "modules/Bindings_Generator/windows.jai"]

/** The installed bundle as four local library sources. */
export function jaiSources(install: JaiInstall): SourceInput[] {
  const stamp = `${install.version}${install.date ? `, ${install.date}` : ""}`
  const local = `Indexed from your installed compiler at ${install.path} (${stamp}); private to this computer (the Jai beta is not redistributable).`
  const common = { authors: "Jonathan Blow, Thekla and Jai beta contributors", year: Number(/\b(20\d\d)\b/.exec(install.date ?? "")?.[1] ?? new Date().getFullYear()), version: install.version, fields: ["jai", "source"], status: "current" as const, license: "private distribution only (Jai beta)", deep: true, path: install.path }
  return [
    { ...common, id: "jai-how-to", title: `Jai how_to lessons (${install.version})`, kind: "source-tree", paths: ["how_to", "README.txt"], extensions: [".jai", ".txt"],
      useFor: "the official step-by-step introduction: every language feature explained in a runnable lesson (how_to/NNN_topic.jai), from declarations to polymorphism, context, temporary storage, workspaces, metaprograms, #insert, for_expansion, allocators, inline assembly and cross-compiling",
      note: `${local} Lessons are meant to be read in numeric order.` },
    { ...common, id: "jai-modules-src", title: `Jai modules source (${install.version})`, kind: "source-tree", paths: ["modules"], extensions: [".jai"], exclude: WINDOWS_ONLY,
      useFor: "exact signatures, parameters and doc comments of every bundled module: Basic (print, arrays, strings, memory, temporary storage), Compiler (workspaces, Build_Options, messages), String, File, Hash_Table, Thread, Simp, GetRect, Bindings_Generator, …",
      note: `${local} Windows-only GPU bindings are not indexed; grep ${join(install.path, "modules")} for those.` },
    { ...common, id: "jai-examples-src", title: `Jai examples (${install.version})`, kind: "source-tree", paths: ["examples"], extensions: [".jai", ".txt"], exclude: ["**/license.txt", "**/LICENSE.txt", "examples/beta_key_mailer/paradise_lost.txt"],
      useFor: "larger programs from the bundle: build metaprograms, DLLs, output types, import replacement, a game (invaders), skeletal animation, VR, wasm, iOS library",
      note: local },
    { ...common, id: "jai-changelog", title: `Jai CHANGELOG (${install.version})`, kind: "changelog", path: join(install.path, "CHANGELOG.txt"), paths: undefined, extensions: undefined, deep: undefined,
      useFor: "what changed in which beta version (one section per version): renamed procedures, syntax changes, new directives, removed features; how to update older Jai code",
      note: `${local} Newest versions first.` },
  ]
}

/** Appended to every Jai skill: the installed compiler, how it compares with the validated version, and where things are. */
export function jaiSkillNote(skill: string, install: JaiInstall | undefined, places: { examples: string; runner: string; libraryOn: boolean; jailsQuery?: string; jails?: string }): string {
  const examples = join(places.examples, "jai", skill)
  const run = `pixi exec --spec nodejs=24 node ${places.runner}`
  const lines = ["", "---", `Validated with Jai ${VALIDATED_JAI} (${VALIDATED_JAI_DATE}) on macOS arm64 and Linux x86-64.`]
  if (!install) {
    lines.push("No Jai compiler was found on this computer (looked in $OC_KNOWHOW_JAI, ~/jai/current, ~/jai). The user can set its folder in Settings → Know-how → Jai; the local library sources below appear once it is found.")
  } else {
    const order = compareJai(install.version, VALIDATED_JAI)
    lines.push(`Installed here: Jai ${install.version}${install.date ? ` (${install.date})` : ""} at ${install.path}${install.compiler ? `; compiler ${install.compiler}` : ""}.`)
    if (order > 0) lines.push(`The installed compiler is NEWER than the one this skill was validated with: before relying on details, check what changed since ${VALIDATED_JAI} (library_search sources=["jai-changelog"], or read the top of ${join(install.path, "CHANGELOG.txt")}) and re-run the examples (${run}). Trust the compiler and the installed module source over this text.`)
    if (order < 0) lines.push(`The installed compiler is OLDER than ${VALIDATED_JAI}: some features described here may not exist yet; check jai-changelog.`)
    if (places.libraryOn) lines.push("Local library sources from this compiler (library_search with sources=[…]): jai-how-to (lessons), jai-modules-src (module source: exact signatures), jai-examples-src, jai-changelog (what changed when).")
  }
  lines.push(`Tested examples for this skill: ${examples} (each file's header says what it must print). Run them with the installed compiler: ${run} --skill ${skill}${install ? "" : " --jai /path/to/jai-macos|jai-linux"}`)
  if (places.jailsQuery) {
    const query = `pixi exec --spec nodejs=24 node ${places.jailsQuery}`
    lines.push(places.jails
      ? `Code navigation (Jails language server at ${places.jails}): ${query} def <file> <identifier> | def <file>:<line>:<col> | symbols <file> | sig <file>:<line>:<col> | wsym <query>. Trusted code only (it compiles the project).`
      : `Code navigation: the Jails language server is not built on this computer; build it with pixi exec --spec nodejs=24 node ${places.jailsQuery.replace(/jails-query\.mjs$/, "jails-build.mjs")} (needs git and the Jai compiler), then use ${query} def <file> <identifier>.`)
  }
  return lines.join("\n") + "\n"
}
