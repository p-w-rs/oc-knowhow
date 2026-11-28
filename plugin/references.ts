// Free references: oc-knowhow ships only their links and descriptions (references.json). Each user downloads them to
// their own computer, where they are converted and indexed like a private library.
import { createHash, randomBytes } from "node:crypto"
import { execFile } from "node:child_process"
import { createWriteStream } from "node:fs"
import { mkdir, open, readdir, readFile, rename, rm, stat, utimes, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { Readable } from "node:stream"
import { pipeline } from "node:stream/promises"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"
import { untar, type SourceInput } from "./library.js"

export interface Reference extends Omit<SourceInput, "kind" | "path"> { readonly kind: "pdf" | "html" | "link" | "gnuplot-source" | "source-tree"; readonly url: string; readonly sha256?: string }
export const REFERENCES_FILE = fileURLToPath(new URL("../references.json", import.meta.url))
export const REFERENCES_LIBRARY = "references"

export async function loadReferences(file = REFERENCES_FILE): Promise<Reference[]> {
  return (JSON.parse(await readFile(file, "utf8")) as { sources: Reference[] }).sources
}

const extensionOf = (reference: Reference) => reference.kind === "pdf" ? ".pdf" : reference.kind === "html" ? ".html" : ".tar.gz"
const fileOf = (directory: string, reference: Reference) => join(directory, `${reference.id}${extensionOf(reference)}`)
const treeOf = (directory: string, reference: Reference) => join(directory, reference.id)
const isTree = (kind: Reference["kind"]) => kind === "gnuplot-source" || kind === "source-tree"
const VERSION_MARK = ".oc-knowhow-version"
const markOf = (reference: Reference) => `${reference.url} ${(reference.paths ?? []).join(",")}`

export interface DownloadState { readonly id: string; readonly title: string; readonly kind: string; readonly state: "link" | "missing" | "downloaded"; readonly error?: string }

/** Where each reference stands on this computer. */
export async function referenceStates(directory: string, references: readonly Reference[], errors: Record<string, string> = {}): Promise<DownloadState[]> {
  return Promise.all(references.map(async reference => {
    if (reference.kind === "link") return { id: reference.id, title: reference.title, kind: reference.kind, state: "link" as const }
    const present = reference.kind === "source-tree"
      ? await readFile(join(treeOf(directory, reference), VERSION_MARK), "utf8").then(text => text.trim() === markOf(reference), () => false)
      : await stat(isTree(reference.kind) ? treeOf(directory, reference) : fileOf(directory, reference)).then(() => true, () => false)
    return { id: reference.id, title: reference.title, kind: reference.kind, state: present ? "downloaded" as const : "missing" as const, ...(errors[reference.id] && { error: errors[reference.id] }) }
  }))
}

const run = promisify(execFile)

/** Checks that a download is the kind of file expected (sites sometimes answer with a web page instead). */
async function looksRight(path: string, kind: Reference["kind"]): Promise<boolean> {
  const head = Buffer.alloc(8)
  const handle = await open(path, "r")
  try { await handle.read(head, 0, 8, 0) } finally { await handle.close() }
  if (kind === "pdf") return head.subarray(0, 5).toString() === "%PDF-"
  if (isTree(kind)) return head[0] === 0x1f && head[1] === 0x8b
  return true
}

async function viaFetch(url: string, partial: string, userAgent: string, signal?: AbortSignal) {
  const response = await fetch(url, { redirect: "follow", headers: { "user-agent": userAgent }, ...(signal && { signal }) })
  if (!response.ok || !response.body) throw new Error(`download failed (${response.status})`)
  await pipeline(Readable.fromWeb(response.body as never), createWriteStream(partial, { mode: 0o600 }))
}

/** Temporary names are unique per process and attempt: two downloads (another window, the terminal) never share one. */
const unique = () => `${process.pid}-${randomBytes(4).toString("hex")}`
const TEMPORARY = /\.\d+-[0-9a-f]{8}\.(part|tar\.gz|staging|old)$|\.(part|staging)$|\.tar\.gz$/

/** Downloads with fetch; if the server refuses or answers with a web page, retries with the system's curl. */
async function fetchTo(url: string, path: string, kind: Reference["kind"], sha256?: string, signal?: AbortSignal): Promise<void> {
  const partial = `${path}.${unique()}.part`
  const attempts: (() => Promise<void>)[] = [
    () => viaFetch(url, partial, kind === "gnuplot-source" ? "curl/8.7.1" : "Mozilla/5.0 (oc-knowhow reference download)", signal),
    () => run("curl", ["-sSfL", "--max-time", "600", "-A", kind === "gnuplot-source" ? "curl/8.7.1" : "Mozilla/5.0 (oc-knowhow reference download)", "-o", partial, url]).then(() => {}),
  ]
  let problem = "download failed"
  for (const attempt of attempts) {
    signal?.throwIfAborted()
    try {
      await attempt()
      if (!(await looksRight(partial, kind))) { problem = "the site returned a web page instead of the file"; continue }
      if (sha256 && createHash("sha256").update(await readFile(partial)).digest("hex") !== sha256) { problem = "checksum mismatch; not saved"; continue }
      await rename(partial, path)
      return
    } catch (error) { if (signal?.aborted) throw error; problem = error instanceof Error ? error.message.split("\n")[0]! : String(error) }
  }
  await rm(partial, { force: true })
  throw new Error(problem)
}

/**
 * Downloads one source tree next to the old one and swaps it in when it is complete, so a running search (or another
 * process indexing) never sees a half-written tree.
 */
async function downloadTree(directory: string, reference: Reference, signal?: AbortSignal): Promise<void> {
  const tree = treeOf(directory, reference), tag = unique()
  const archive = `${tree}.${tag}.tar.gz`, staging = `${tree}.${tag}.staging`, old = `${tree}.${tag}.old`
  try {
    await fetchTo(reference.url, archive, reference.kind, reference.sha256, signal)
    await untar(archive, staging)
    const [top] = await readdir(staging)
    if (!top) throw new Error("the archive is empty")
    const fresh = join(staging, top)
    if (reference.kind === "source-tree") {
      if (reference.paths?.length) await prune(fresh, reference.paths); else await dropBinaries(fresh)
      await writeFile(join(fresh, VERSION_MARK), markOf(reference))
    }
    const hadOld = await rename(tree, old).then(() => true, () => false)
    try { await rename(fresh, tree) }
    catch (error) { if (hadOld) await rename(old, tree).catch(() => {}); throw error }
  } finally {
    await Promise.all([rm(archive, { force: true }), rm(staging, { recursive: true, force: true }), rm(old, { recursive: true, force: true })])
  }
}

/** Leftovers of downloads that were interrupted (a crash, a closed laptop) more than an hour ago. */
async function removeLeftovers(directory: string): Promise<void> {
  for (const name of await readdir(directory).catch(() => [] as string[])) {
    if (!TEMPORARY.test(name)) continue
    const info = await stat(join(directory, name)).catch(() => undefined)
    if (info && Date.now() - info.mtimeMs > 3600_000) await rm(join(directory, name), { recursive: true, force: true }).catch(() => {})
  }
}

/** Download problems by reference id, from the last attempt of each (kept across runs until it succeeds). */
export async function readDownloadErrors(directory: string): Promise<Record<string, string>> {
  try {
    const value = JSON.parse(await readFile(join(directory, "errors.json"), "utf8")) as unknown
    return value && typeof value === "object" && !Array.isArray(value) ? Object.fromEntries(Object.entries(value).filter(([, message]) => typeof message === "string")) as Record<string, string> : {}
  } catch { return {} }
}

async function writeJson(file: string, value: unknown) {
  const temporary = `${file}.${unique()}.tmp`
  await writeFile(temporary, JSON.stringify(value, null, 2), { mode: 0o600 })
  await rename(temporary, file)
}

/**
 * Downloads the missing references (or the given ids): new ones and those whose pinned version changed. Returns errors
 * by id; other downloads continue. Hold `lockDownloads` around it when another process may download too.
 */
export async function downloadReferences(directory: string, references: readonly Reference[], options: { only?: readonly string[]; onProgress?: (step: string, done: number, total: number) => void; signal?: AbortSignal } = {}): Promise<Record<string, string>> {
  await mkdir(directory, { recursive: true, mode: 0o700 })
  await removeLeftovers(directory)
  const todo = (await referenceStates(directory, references)).filter(state => state.state === "missing" && (!options.only || options.only.includes(state.id)))
  const errors: Record<string, string> = {}
  for (const [index, state] of todo.entries()) {
    options.signal?.throwIfAborted()
    const reference = references.find(item => item.id === state.id)!
    options.onProgress?.(`Downloading ${reference.title}`, index, todo.length)
    try {
      if (isTree(reference.kind)) await downloadTree(directory, reference, options.signal)
      else await fetchTo(reference.url, fileOf(directory, reference), reference.kind, reference.sha256, options.signal)
    } catch (error) { if (options.signal?.aborted) throw error; errors[reference.id] = error instanceof Error ? error.message : String(error) }
  }
  // Earlier problems stay listed until that reference is downloaded or no longer wanted.
  const states = await referenceStates(directory, references)
  const kept = Object.entries(await readDownloadErrors(directory)).filter(([id]) => !todo.some(state => state.id === id) && states.some(state => state.id === id && state.state === "missing"))
  await writeJson(join(directory, "errors.json"), { ...Object.fromEntries(kept), ...errors })
  return errors
}

// ------------------------------------------------------------------ one download at a time, across processes

const LOCK = ".download.lock"
const LOCK_STALE_MS = 30 * 60_000

export interface DownloadLock { release(): Promise<void> }

const alive = (pid: number) => { try { process.kill(pid, 0); return true } catch (error) { return (error as NodeJS.ErrnoException).code === "EPERM" } }

/**
 * Takes `<references>/.download.lock`, or returns undefined when another download holds it (this or another process:
 * every OpenCode window and the terminal command share the folder). A lock whose process is gone, or that was not
 * touched for 30 minutes, is taken over. `wait` keeps trying until the lock is free (or the signal aborts).
 */
export async function lockDownloads(directory: string, options: { wait?: boolean; signal?: AbortSignal } = {}): Promise<DownloadLock | undefined> {
  await mkdir(directory, { recursive: true, mode: 0o700 })
  const file = join(directory, LOCK)
  const token = unique()
  for (;;) {
    options.signal?.throwIfAborted()
    try {
      await writeFile(file, JSON.stringify({ pid: process.pid, token, at: new Date().toISOString() }), { flag: "wx", mode: 0o600 })
      const heartbeat = setInterval(() => { const now = new Date(); void utimes(file, now, now).catch(() => {}) }, 5 * 60_000)
      heartbeat.unref?.()
      return {
        release: async () => {
          clearInterval(heartbeat)
          const current = await readFile(file, "utf8").catch(() => "")
          if (current.includes(token)) await rm(file, { force: true })
        },
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error
    }
    const holder = await lockHolder(file)
    if (!holder.held) {
      // Take over a stale lock only if it is still the one judged stale (another process may have taken it meanwhile).
      if ((await readFile(file, "utf8").catch(() => "")) === holder.text) await rm(file, { force: true })
      continue
    }
    if (!options.wait) return undefined
    await new Promise(resolve => setTimeout(resolve, 2000))
  }
}

async function lockHolder(file: string): Promise<{ held: boolean; text: string }> {
  const [text, info] = await Promise.all([readFile(file, "utf8").catch(() => ""), stat(file).catch(() => undefined)])
  if (!info) return { held: false, text }
  let pid: unknown
  try { pid = (JSON.parse(text) as { pid?: unknown }).pid } catch {}
  const age = Date.now() - info.mtimeMs
  // An empty file is a lock being written right now, unless it stays empty.
  const held = age <= LOCK_STALE_MS && (typeof pid === "number" ? alive(pid) : age <= 10_000)
  return { held, text }
}

/** Whether a download holds the lock right now (this or another window, or the terminal). Does not take it. */
export async function downloadRunning(directory: string): Promise<boolean> {
  return (await lockHolder(join(directory, LOCK))).held
}

// ------------------------------------------------------------------ keeping downloaded references up to date

const AUTO_STATE = "auto-download.json"

/** Whether the user ever downloaded free references here (any version of any of them, or a download attempt). */
async function downloadedBefore(directory: string, references: readonly Reference[]): Promise<boolean> {
  if (await stat(join(directory, "errors.json")).then(() => true, () => false)) return true
  for (const reference of references) {
    if (reference.kind === "link") continue
    if (await stat(isTree(reference.kind) ? treeOf(directory, reference) : fileOf(directory, reference)).then(() => true, () => false)) return true
  }
  return false
}
/** After an automatic attempt fails, wait 1 h, then 4 h, then a day before the next one. */
const BACKOFF_MS = [3600_000, 4 * 3600_000, 24 * 3600_000]

export interface RefreshResult {
  /** References downloaded or tried in this run. */
  readonly attempted: readonly string[]
  readonly errors: Record<string, string>
  /** Why nothing was tried: the user never downloaded references, everything is current (or waits for a retry), or another download runs. */
  readonly skipped?: "not-opted-in" | "nothing-due" | "locked"
}

/**
 * Brings already downloaded references up to date: new references and new pinned versions are downloaded in the
 * background. Only for users who downloaded references before (the first download is their choice), and failed ones
 * are retried after 1 h, 4 h, then daily.
 */
export async function refreshReferences(directory: string, references: readonly Reference[], options: { signal?: AbortSignal; onProgress?: (step: string, done: number, total: number) => void; now?: number } = {}): Promise<RefreshResult> {
  const now = options.now ?? Date.now()
  if (!(await downloadedBefore(directory, references))) return { attempted: [], errors: {}, skipped: "not-opted-in" }
  const states = await referenceStates(directory, references)
  const missing = references.filter(reference => states.some(state => state.id === reference.id && state.state === "missing"))
  const file = join(directory, AUTO_STATE)
  type Tries = Record<string, { url: string; failures: number; last: number }>
  let tries: Tries = {}
  try {
    const raw = JSON.parse(await readFile(file, "utf8")) as Record<string, Partial<Tries[string]>>
    for (const [id, entry] of Object.entries(raw)) {
      if (entry && typeof entry.url === "string" && Number.isInteger(entry.failures) && entry.failures! > 0 && Number.isFinite(entry.last)) tries[id] = entry as Tries[string]
    }
  } catch {}
  const due = missing.filter(reference => {
    const entry = tries[reference.id]
    return !entry || entry.url !== reference.url || now - entry.last >= BACKOFF_MS[Math.min(entry.failures, BACKOFF_MS.length) - 1]!
  })
  if (!due.length) return { attempted: [], errors: {}, skipped: "nothing-due" }
  const lock = await lockDownloads(directory)
  if (!lock) return { attempted: [], errors: {}, skipped: "locked" }
  try {
    const errors = await downloadReferences(directory, references, { only: due.map(reference => reference.id), ...(options.onProgress && { onProgress: options.onProgress }), ...(options.signal && { signal: options.signal }) })
    const next: Tries = {}
    for (const reference of missing) {
      if (errors[reference.id]) {
        const entry = tries[reference.id]
        next[reference.id] = { url: reference.url, failures: entry && entry.url === reference.url ? entry.failures + 1 : 1, last: now }
      } else if (!due.includes(reference) && tries[reference.id]) next[reference.id] = tries[reference.id]!
    }
    await writeJson(file, next)
    return { attempted: due.map(reference => reference.id), errors }
  } finally { await lock.release() }
}

/** Library sources for the downloaded references; links are listed (not indexed) so agents can open them. */
export async function referenceSources(directory: string, references: readonly Reference[]): Promise<SourceInput[]> {
  const states = await referenceStates(directory, references)
  return references.flatMap((reference): SourceInput[] => {
    const state = states.find(item => item.id === reference.id)!
    const { kind, sha256: _, ...meta } = reference
    if (kind === "link") return [{ ...meta, kind: "link" as const }]
    if (state.state !== "downloaded") return []
    return [{ ...meta, kind: kind === "gnuplot-source" || kind === "source-tree" ? kind : "file" as const, path: isTree(kind) ? treeOf(directory, reference) : fileOf(directory, reference) }]
  })
}


/** Keeps only the listed paths (files or directories, relative to the tree root) of a downloaded source tree. */
async function prune(root: string, keep: readonly string[]): Promise<void> {
  const wanted = keep.map(path => path.replace(/^\/+|\/+$/g, ""))
  const visit = async (dir: string, rel: string): Promise<void> => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const childRel = rel ? `${rel}/${entry.name}` : entry.name
      if (wanted.some(path => childRel === path || childRel.startsWith(`${path}/`))) { if (entry.isDirectory()) await dropBinaries(join(dir, entry.name)); else if (BINARY.test(entry.name)) await rm(join(dir, entry.name), { force: true }); continue }
      if (entry.isDirectory() && wanted.some(path => path.startsWith(`${childRel}/`))) { await visit(join(dir, entry.name), childRel); continue }
      await rm(join(dir, entry.name), { recursive: true, force: true })
    }
  }
  await visit(root, "")
}

// Prebuilt libraries, executables and media in vendored trees: large and useless for reading the code.
const BINARY = /\.(lib|dll|a|so(\.\d+)*|dylib|pdb|exe|o|obj|exp|ilk|png|jpe?g|gif|bmp|qoi|tga|ttf|otf|wav|ogg|mp3|flac|zip|7z|gz|bin)$/i

async function dropBinaries(dir: string): Promise<void> {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) await dropBinaries(path)
    else if (BINARY.test(entry.name)) await rm(path, { force: true })
  }
}
