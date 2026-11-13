// Free references: oc-knowhow ships only their links and descriptions (references.json). Each user downloads them to
// their own computer, where they are converted and indexed like a private library.
import { createHash } from "node:crypto"
import { execFile } from "node:child_process"
import { createWriteStream } from "node:fs"
import { mkdir, open, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises"
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

/** Downloads with fetch; if the server refuses or answers with a web page, retries with the system's curl. */
async function fetchTo(url: string, path: string, kind: Reference["kind"], sha256?: string, signal?: AbortSignal): Promise<void> {
  const partial = `${path}.part`
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

/** Downloads the missing references (or the given ids). Returns errors by id; other downloads continue. */
export async function downloadReferences(directory: string, references: readonly Reference[], options: { only?: readonly string[]; onProgress?: (step: string, done: number, total: number) => void; signal?: AbortSignal } = {}): Promise<Record<string, string>> {
  await mkdir(directory, { recursive: true, mode: 0o700 })
  const todo = (await referenceStates(directory, references)).filter(state => state.state === "missing" && (!options.only || options.only.includes(state.id)))
  const errors: Record<string, string> = {}
  for (const [index, state] of todo.entries()) {
    options.signal?.throwIfAborted()
    const reference = references.find(item => item.id === state.id)!
    options.onProgress?.(`Downloading ${reference.title}`, index, todo.length)
    try {
      if (isTree(reference.kind)) {
        const archive = fileOf(directory, reference)
        await fetchTo(reference.url, archive, reference.kind, reference.sha256, options.signal)
        const staging = `${treeOf(directory, reference)}.staging`
        await rm(staging, { recursive: true, force: true })
        await untar(archive, staging)
        const [top] = await readdir(staging)
        await rm(treeOf(directory, reference), { recursive: true, force: true })
        await rename(join(staging, top!), treeOf(directory, reference))
        if (reference.kind === "source-tree") { if (reference.paths?.length) await prune(treeOf(directory, reference), reference.paths); else await dropBinaries(treeOf(directory, reference)) }
        if (reference.kind === "source-tree") await writeFile(join(treeOf(directory, reference), VERSION_MARK), markOf(reference))
        await rm(staging, { recursive: true, force: true })
        await rm(archive, { force: true })
      } else await fetchTo(reference.url, fileOf(directory, reference), reference.kind, reference.sha256, options.signal)
    } catch (error) { if (options.signal?.aborted) throw error; errors[reference.id] = error instanceof Error ? error.message : String(error) }
  }
  await writeFile(join(directory, "errors.json"), JSON.stringify(errors, null, 2))
  return errors
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
