// Reference libraries for agents: sources (PDF, web pages, Markdown, notebooks, Office files, gnuplot's demos and docs)
// are converted into clean sections with heading paths and page numbers, indexed for keyword (BM25) and meaning-based
// search, and read back by id with citations. Everything lives in the plugin's data folder; nothing is shipped.
import { execFile } from "node:child_process"
import { createHash } from "node:crypto"
import { mkdir, readdir, readFile, rename, rm, stat, unlink, writeFile } from "node:fs/promises"
import { basename, extname, join, relative, sep } from "node:path"
import { promisify } from "node:util"
import { colgrep, type Runtime } from "./backend.js"
import { documentKind, extractDocument, readBounded, type Extracted } from "./documents.js"

const run = promisify(execFile)

export type Status = "current" | "dated" | "superseded" | "unknown"
export interface SourceMeta {
  readonly id: string
  readonly title: string
  readonly authors?: string
  readonly year?: number
  readonly edition?: string
  readonly fields?: readonly string[]
  readonly status?: Status
  readonly supersededBy?: string
  readonly useFor?: string
  readonly note?: string
  readonly license?: string
  readonly url?: string
}
/** A source to index: a file on disk (or a gnuplot source tree), or a link that is only listed. */
export interface SourceInput extends SourceMeta { readonly kind: "file" | "link" | "gnuplot-source"; readonly path?: string }
export interface Unit { readonly id: number; readonly heading: readonly string[]; readonly pages?: readonly [number, number]; readonly text: string }
interface Stored { version: 1; library: string; meta: SourceMeta; kind: string; path?: string; fingerprint: string; units: Unit[]; error?: string; indexedAt: string }

export interface LibrarySpec { readonly id: string; readonly name: string; readonly sources: readonly SourceInput[] }
export interface SearchHit {
  readonly ref: string
  readonly source: string
  readonly title: string
  readonly status: Status
  readonly where: string
  readonly excerpt: string
  readonly score: number
  readonly note?: string
}
export interface Progress { step: string; done: number; total: number }

const UNIT_CHARS = 6000
const TEXT_FILES = new Set([".md", ".markdown", ".txt", ".rst", ".tex", ".gp", ".gnu", ".plt", ".dem", ".py", ".d2", ".dot", ".mmd"])
export const LIBRARY_FILES = new Set([...TEXT_FILES, ".pdf", ".html", ".htm", ".ipynb", ".docx", ".pptx", ".xlsx"])

export const slug = (text: string) => text.toLowerCase().normalize("NFKD").replace(/[^\w\s-]/g, "").trim().replace(/[\s_]+/g, "-").replace(/-+/g, "-").slice(0, 60) || "source"
const hash = (data: string | Uint8Array) => createHash("sha256").update(data).digest("hex")
export const terms = (text: string) => text.replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []

// ------------------------------------------------------------------ cleaning and sectioning

/** Removes running headers/footers (lines repeated at the top or bottom of many pages) and joins hyphenated words. */
export function cleanPages(pages: readonly string[]): string[] {
  const split = pages.map(page => page.split(/\r?\n/).map(line => line.trimEnd()))
  const norm = (line: string) => line.trim().toLowerCase().replace(/\d+/g, "#").replace(/\s+/g, " ")
  const counts = new Map<string, number>()
  for (const lines of split) {
    if (lines.length < 6) continue
    const edge = new Set([...lines.slice(0, 2), ...lines.slice(-2)].map(norm).filter(line => line.length > 0 && line.length < 120))
    for (const line of edge) counts.set(line, (counts.get(line) ?? 0) + 1)
  }
  const threshold = Math.max(3, pages.length * 0.3)
  const repeated = new Set([...counts].filter(([line, n]) => n >= threshold || (/^#+$|^page #+( of #+)?$/.test(line) && n >= 3)).map(([line]) => line))
  return split.map(lines => {
    const kept = lines.length < 6 ? lines : lines.filter((line, index) => !((index < 2 || index >= lines.length - 2) && repeated.has(norm(line))))
    return kept.join("\n").replace(/(\p{L})-\n(\p{Ll})/gu, "$1$2").replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim()
  })
}

/** Splits long text into chunks of about UNIT_CHARS at paragraph boundaries. */
export function chunk(text: string, size = UNIT_CHARS): string[] {
  if (text.length <= size * 1.3) return text.trim() ? [text.trim()] : []
  const parts: string[] = []
  let current = ""
  for (const paragraph of text.split(/\n\s*\n/)) {
    if (current && current.length + paragraph.length > size) { parts.push(current.trim()); current = "" }
    if (paragraph.length > size * 1.5) { for (let i = 0; i < paragraph.length; i += size) parts.push(paragraph.slice(i, i + size)); continue }
    current += `${paragraph}\n\n`
  }
  if (current.trim()) parts.push(current.trim())
  return parts
}

/** PDF pages → sections following the bookmarks (chapter/section paths with page ranges), else groups of pages. */
export function pdfUnits(extracted: Extracted): Omit<Unit, "id">[] {
  const pages = cleanPages(extracted.sections.map(section => section.text.startsWith("(no text") ? "" : section.text))
  const total = pages.length
  const marks = (extracted.outline ?? []).filter(mark => mark.page >= 1 && mark.page <= total && mark.level <= 3)
  const units: Omit<Unit, "id">[] = []
  const pushRange = (heading: string[], from: number, to: number) => {
    // Split by pages so citations stay accurate.
    let start = from, buffer = ""
    for (let page = from; page <= to; page++) {
      const text = pages[page - 1] ?? ""
      if (buffer && buffer.length + text.length > UNIT_CHARS) { units.push({ heading, pages: [start, page - 1], text: buffer.trim() }); buffer = ""; start = page }
      buffer += `${text}\n\n`
    }
    if (buffer.trim()) units.push({ heading, pages: [start, to], text: buffer.trim() })
  }
  if (marks.length >= 3) {
    const sorted = [...marks].sort((a, b) => a.page - b.page || a.level - b.level)
    const path: string[] = []
    if (sorted[0]!.page > 1) pushRange(["Front matter"], 1, sorted[0]!.page - 1)
    for (const [index, mark] of sorted.entries()) {
      path.length = mark.level - 1
      path[mark.level - 1] = mark.title
      const next = sorted.slice(index + 1).find(other => other.page > mark.page)
      // A heading whose children start on the same page owns no pages of its own.
      if (sorted[index + 1] && sorted[index + 1]!.page === mark.page) continue
      pushRange([...path].filter(Boolean), mark.page, next ? Math.max(mark.page, next.page - 1) : total)
    }
  } else pushRange([], 1, total)
  return units.filter(unit => unit.text.length > 40)
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ", ndash: "–", mdash: "—", hellip: "…", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“" }
const decodeHtml = (text: string) => text.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (match, name: string) => name[0] === "#"
  ? String.fromCodePoint(name[1] === "x" || name[1] === "X" ? Number.parseInt(name.slice(2), 16) : Number.parseInt(name.slice(1), 10))
  : ENTITIES[name.toLowerCase()] ?? match)

/** HTML → Markdown-ish text with headings, without navigation, scripts and styles. */
export function htmlToText(html: string): string {
  let body = html.replace(/<!--[\s\S]*?-->/g, "").replace(/<(script|style|noscript|svg|nav|header|footer|form|aside|iframe)\b[\s\S]*?<\/\1>/gi, "")
  const main = /<(main|article)\b[\s\S]*?<\/\1>/i.exec(body)
  if (main && main[0].length > 2000) body = main[0]
  body = body
    .replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_, level: string, inner: string) => `\n\n${"#".repeat(Number(level))} ${inner.replace(/<[^>]+>/g, "").trim()}\n\n`)
    .replace(/<pre\b[^>]*>([\s\S]*?)<\/pre>/gi, (_, inner: string) => `\n\n\`\`\`\n${inner.replace(/<[^>]+>/g, "")}\n\`\`\`\n\n`)
    .replace(/<li\b[^>]*>/gi, "\n- ").replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|tr|table|ul|ol|blockquote|section)>/gi, "\n\n")
    .replace(/<t[dh]\b[^>]*>/gi, " | ").replace(/<[^>]+>/g, "")
  return decodeHtml(body).replace(/[ \t]+/g, " ").replace(/\n[ \t]+/g, "\n").replace(/\n{3,}/g, "\n\n").trim()
}

/** Markdown/plain text → units following its headings. */
export function markdownUnits(text: string): Omit<Unit, "id">[] {
  const units: Omit<Unit, "id">[] = []
  const path: string[] = []
  let buffer = ""
  const flush = () => { for (const part of chunk(buffer)) units.push({ heading: [...path].filter(Boolean), text: part }); buffer = "" }
  let fence = false
  for (const line of text.split(/\r?\n/)) {
    if (/^```/.test(line)) fence = !fence
    const heading = !fence && /^(#{1,4})\s+(.+?)\s*#*$/.exec(line)
    if (heading) {
      flush()
      const level = heading[1]!.length
      path.length = level - 1
      path[level - 1] = heading[2]!
      continue
    }
    buffer += `${line}\n`
  }
  flush()
  return units.filter(unit => unit.text.length > 40)
}

/** gnuplot's docs/gnuplot.doc: "<level> Title" lines start topics, "?" lines are keywords, "^" lines are HTML only. */
export function gnuplotDocUnits(doc: string): Omit<Unit, "id">[] {
  const units: Omit<Unit, "id">[] = []
  const path: string[] = []
  let keywords: string[] = []
  let buffer = ""
  const flush = () => {
    const text = buffer.replace(/\n{3,}/g, "\n\n").trim()
    if (text.length > 40) for (const part of chunk(text)) units.push({ heading: ["gnuplot manual", ...path.filter(Boolean)], text: keywords.length ? `help keywords: ${keywords.join(", ")}\n\n${part}` : part })
    buffer = ""; keywords = []
  }
  for (const line of doc.split(/\r?\n/)) {
    if (/^C/.test(line) || /^\^/.test(line) || /^[=@<%]/.test(line)) continue
    const topic = /^(\d) (.+)$/.exec(line)
    if (topic) { flush(); const level = Number(topic[1]); path.length = level - 1; path[level - 1] = topic[2]!.trim(); continue }
    if (line.startsWith("?")) { if (line.length > 1) keywords.push(line.slice(1)); continue }
    buffer += `${line.replace(/^ /, "")}\n`
  }
  flush()
  return units
}

/** A gnuplot demo script: its leading comments say what it shows. */
export function demoUnit(name: string, script: string): Omit<Unit, "id"> {
  return { heading: ["gnuplot demo", name], text: `gnuplot demo script ${name}\n\n${script.slice(0, UNIT_CHARS * 2)}` }
}

function notebookText(json: string): string {
  try {
    const notebook = JSON.parse(json) as { cells?: { cell_type: string; source: string | string[] }[] }
    return (notebook.cells ?? []).map(cell => {
      const source = Array.isArray(cell.source) ? cell.source.join("") : cell.source ?? ""
      return cell.cell_type === "code" ? `\`\`\`\n${source}\n\`\`\`` : source
    }).join("\n\n")
  } catch { return "" }
}

// ------------------------------------------------------------------ index store

interface IndexFile {
  version: 1
  units: { key: string; source: string; unit: number }[]
  lengths: number[]
  postings: Record<string, number[]>
}

export class Library {
  readonly root: string
  readonly sourcesDir: string
  readonly mirror: string
  #index?: IndexFile
  #stored = new Map<string, { item: Stored; stamp: number }>()
  #indexStamp?: number
  progress?: Progress
  #running?: Promise<SyncReport>

  constructor(dataDirectory: string, private readonly runtime: () => Promise<Runtime | undefined>) {
    this.root = join(dataDirectory, "library")
    this.sourcesDir = join(this.root, "sources")
    this.mirror = join(this.root, "mirror")
  }

  #file = (key: string) => join(this.sourcesDir, `${key}.json`)
  static key = (library: string, source: string) => `${library}--${source}`

  async stored(): Promise<Stored[]> {
    await mkdir(this.sourcesDir, { recursive: true })
    const result: Stored[] = []
    for (const name of await readdir(this.sourcesDir)) {
      if (!name.endsWith(".json")) continue
      const key = name.slice(0, -5)
      // Another process (the library CLI, another window) may have re-indexed a source: reread when the file changed.
      const stamp = await stat(join(this.sourcesDir, name)).then(info => info.mtimeMs, () => undefined)
      if (stamp === undefined) continue
      let cached = this.#stored.get(key)
      if (!cached || cached.stamp !== stamp) {
        try { cached = { item: JSON.parse(await readFile(join(this.sourcesDir, name), "utf8")) as Stored, stamp }; this.#stored.set(key, cached) } catch { continue }
      }
      result.push(cached.item)
    }
    return result
  }

  /** Brings the index in line with the given libraries: new and changed sources are converted, removed ones dropped. */
  sync(libraries: readonly LibrarySpec[], signal?: AbortSignal): Promise<SyncReport> {
    this.#running ??= this.#sync(libraries, signal).finally(() => { this.#running = undefined; this.progress = undefined })
    return this.#running
  }

  async #sync(libraries: readonly LibrarySpec[], signal?: AbortSignal): Promise<SyncReport> {
    await mkdir(this.mirror, { recursive: true })
    const report: SyncReport = { added: 0, updated: 0, removed: 0, unchanged: 0, failed: [] }
    const wanted = new Map<string, { library: LibrarySpec; source: SourceInput }>()
    for (const library of libraries) for (const source of library.sources) wanted.set(Library.key(library.id, source.id), { library, source })
    const existing = await this.stored()
    for (const item of existing) {
      const key = Library.key(item.library, item.meta.id)
      if (!wanted.has(key)) { await unlink(this.#file(key)).catch(() => {}); this.#stored.delete(key); report.removed++ }
    }
    let done = 0
    for (const [key, { library, source }] of wanted) {
      signal?.throwIfAborted()
      this.progress = { step: `Reading ${source.title}`, done: done++, total: wanted.size }
      const fingerprint = await this.#fingerprint(source)
      const old = this.#stored.get(key)?.item
      if (old && old.fingerprint === fingerprint) {
        if (JSON.stringify(old.meta) !== JSON.stringify(metaOf(source))) { old.meta = metaOf(source); await this.#save(key, old) }
        report.unchanged++
        continue
      }
      let units: Omit<Unit, "id">[] = [], error: string | undefined
      try { units = source.kind === "link" ? [] : await this.#convert(source, signal) }
      catch (cause) { if (signal?.aborted) throw cause; error = cause instanceof Error ? cause.message : String(cause); report.failed.push({ source: source.title, error }) }
      const stored: Stored = { version: 1, library: library.id, meta: metaOf(source), kind: source.kind, ...(source.path && { path: source.path }), fingerprint, units: units.map((unit, id) => ({ id, ...unit })), ...(error && { error }), indexedAt: new Date().toISOString() }
      await this.#save(key, stored)
      if (old) report.updated++; else report.added++
    }
    this.progress = { step: "Building the index", done: wanted.size, total: wanted.size + 1 }
    await this.#rebuild()
    const runtime = await this.runtime()
    if (runtime) {
      this.progress = { step: "Building the meaning-based index (first time can take several minutes)", done: wanted.size, total: wanted.size + 1 }
      await colgrep(runtime, this.mirror, "index warm-up", 1, signal, 60 * 60_000).catch(() => {})
    }
    return report
  }

  async #save(key: string, stored: Stored) {
    const temporary = `${this.#file(key)}.${process.pid}.tmp`
    await writeFile(temporary, JSON.stringify(stored))
    await rename(temporary, this.#file(key))
    const stamp = await stat(this.#file(key)).then(info => info.mtimeMs, () => -1)
    this.#stored.set(key, { item: stored, stamp })
  }

  async #fingerprint(source: SourceInput): Promise<string> {
    if (source.kind === "link" || !source.path) return `link:${source.url ?? ""}`
    try { const info = await stat(source.path); return `${source.kind}:${info.size}:${Math.round(info.mtimeMs)}:v2` } catch { return "missing" }
  }

  async #convert(source: SourceInput, signal?: AbortSignal): Promise<Omit<Unit, "id">[]> {
    const path = source.path!
    if (source.kind === "gnuplot-source") {
      const units: Omit<Unit, "id">[] = []
      const demos = join(path, "demo")
      for (const name of (await readdir(demos)).filter(name => name.endsWith(".dem")).sort()) units.push(demoUnit(name, await readFile(join(demos, name), "utf8")))
      units.push(...gnuplotDocUnits(await readFile(join(path, "docs", "gnuplot.doc"), "utf8")))
      return units
    }
    const extension = extname(path).toLowerCase()
    if (extension === ".pdf") {
      const extracted = await extractDocument(await readBounded(path, 300 * 1024 * 1024, signal), "pdf", signal, 20 * 60_000, { outline: true, maxPages: 5000 })
      return pdfUnits(extracted)
    }
    if (extension === ".html" || extension === ".htm") return markdownUnits(htmlToText(await readFile(path, "utf8")))
    if (extension === ".ipynb") return markdownUnits(notebookText(await readFile(path, "utf8")))
    const kind = documentKind(path)
    if (kind) {
      const extracted = await extractDocument(await readBounded(path, 100 * 1024 * 1024, signal), kind, signal, 5 * 60_000)
      return extracted.sections.flatMap(section => chunk(section.text).map(text => ({ heading: [section.label], text })))
    }
    if (TEXT_FILES.has(extension)) {
      const text = await readFile(path, "utf8")
      return [".md", ".markdown", ".txt", ".rst"].includes(extension) ? markdownUnits(text) : chunk(text).map(text => ({ heading: [basename(path)], text }))
    }
    throw new Error(`Unsupported file type ${extension}`)
  }

  /** Inverted index for keyword search, plus one small file per section for the meaning-based engine. */
  async #rebuild(): Promise<void> {
    const stored = await this.stored()
    // Null-prototype map: words such as "constructor" must not collide with Object.prototype.
    const index: IndexFile = { version: 1, units: [], lengths: [], postings: Object.create(null) as Record<string, number[]> }
    const expected = new Set<string>()
    const existing = new Set(await readdir(this.mirror))
    for (const item of stored) {
      const key = Library.key(item.library, item.meta.id)
      for (const unit of item.units) {
        const position = index.units.length
        index.units.push({ key, source: item.meta.id, unit: unit.id })
        const counts = new Map<string, number>()
        for (const term of terms(`${item.meta.title} ${unit.heading.join(" ")} ${unit.text}`)) counts.set(term, (counts.get(term) ?? 0) + 1)
        index.lengths.push([...counts.values()].reduce((a, b) => a + b, 0))
        for (const [term, count] of counts) (index.postings[term] ??= []).push(position, count)
        const name = `${key}--${unit.id}.md`.replace(/[^\w.-]/g, "_")
        expected.add(name)
        if (!existing.has(name)) await writeFile(join(this.mirror, name), `${item.meta.title} — ${unit.heading.join(" › ")}${unit.pages ? ` (p. ${unit.pages[0]}${unit.pages[1] !== unit.pages[0] ? `–${unit.pages[1]}` : ""})` : ""}\n\n${unit.text}\n`)
      }
    }
    for (const name of existing) if (!expected.has(name)) await unlink(join(this.mirror, name)).catch(() => {})
    const temporary = join(this.root, `index.json.${process.pid}.tmp`)
    await writeFile(temporary, JSON.stringify(index))
    await rename(temporary, join(this.root, "index.json"))
    this.#index = index
    this.#indexStamp = await stat(join(this.root, "index.json")).then(info => info.mtimeMs, () => undefined)
  }

  async #loadIndex(): Promise<IndexFile> {
    // Reload when index.json was rewritten (by this process or another, e.g. `pixi run library download`).
    const file = join(this.root, "index.json")
    const stamp = await stat(file).then(info => info.mtimeMs, () => undefined)
    if (this.#index && stamp === this.#indexStamp) return this.#index
    try { this.#index = JSON.parse(await readFile(file, "utf8")) as IndexFile }
    catch { this.#index = { version: 1, units: [], lengths: [], postings: {} } }
    this.#indexStamp = stamp
    return this.#index
  }

  keyword(index: IndexFile, query: string, allowed: (position: number) => boolean, k: number): [number, number][] {
    const wanted = [...new Set(terms(query))]
    const n = index.units.length
    const average = index.lengths.reduce((a, b) => a + b, 0) / Math.max(1, n)
    const scores = new Map<number, number>()
    for (const term of wanted) {
      const postings = Object.hasOwn(index.postings, term) ? index.postings[term] : undefined
      if (!Array.isArray(postings)) continue
      const df = postings.length / 2
      const idf = Math.log(1 + (n - df + 0.5) / (df + 0.5))
      for (let i = 0; i < postings.length; i += 2) {
        const position = postings[i]!, tf = postings[i + 1]!
        if (!allowed(position)) continue
        scores.set(position, (scores.get(position) ?? 0) + idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * index.lengths[position]! / Math.max(1, average))))
      }
    }
    return [...scores].sort((a, b) => b[1] - a[1]).slice(0, k)
  }

  async search(query: string, options: { limit?: number; sources?: readonly string[]; fields?: readonly string[]; mode?: "auto" | "semantic" | "keyword"; signal?: AbortSignal } = {}): Promise<{ hits: SearchHit[]; mode: string; note?: string }> {
    const index = await this.#loadIndex()
    const stored = new Map((await this.stored()).map(item => [Library.key(item.library, item.meta.id), item]))
    const fields = options.fields?.map(field => field.toLowerCase())
    const okSource = (item: Stored | undefined) => !!item && (!options.sources?.length || options.sources.includes(item.meta.id)) && (!fields?.length || (item.meta.fields ?? []).some(field => fields.includes(field.toLowerCase())))
    const allowed = (position: number) => okSource(stored.get(index.units[position]!.key))
    const limit = options.limit ?? 8
    const pool = Math.max(limit * 8, 60)
    const rankings: number[][] = []
    let mode = options.mode === "keyword" ? "keyword" : "semantic", note: string | undefined
    if (mode !== "semantic" || options.mode === "auto" || options.mode === undefined) rankings.push(this.keyword(index, query, allowed, pool).map(([position]) => position))
    if (mode === "semantic") {
      const runtime = await this.runtime()
      if (!runtime) { mode = "keyword"; note = "Meaning-based search is not set up; keyword ranking was used (Settings → Know-how)." }
      else {
        try {
          const positionByName = new Map(index.units.map((unit, position) => [`${unit.key}--${unit.unit}.md`.replace(/[^\w.-]/g, "_"), position]))
          const hits = await colgrep(runtime, this.mirror, query, pool * (options.sources?.length || fields?.length ? 4 : 1), options.signal)
          rankings.push(hits.flatMap(hit => { const position = positionByName.get(basename(hit.file)); return position !== undefined && allowed(position) ? [position] : [] }))
          mode = rankings.length > 1 ? "hybrid" : "semantic"
        } catch (error) { if (options.signal?.aborted) throw error; note = `Meaning-based search failed (${error instanceof Error ? error.message : String(error)}); keyword ranking was used.`; mode = "keyword" }
      }
    }
    const fused = new Map<number, number>()
    for (const ranking of rankings) ranking.forEach((position, rank) => fused.set(position, (fused.get(position) ?? 0) + 1 / (60 + rank + 1)))
    const perSource = new Map<string, number>()
    const hits: SearchHit[] = []
    for (const [position, score] of [...fused].sort((a, b) => b[1] - a[1])) {
      const entry = index.units[position]!
      const item = stored.get(entry.key)
      const unit = item?.units[entry.unit]
      if (!item || !unit) continue
      if ((perSource.get(entry.key) ?? 0) >= 2) continue
      perSource.set(entry.key, (perSource.get(entry.key) ?? 0) + 1)
      hits.push({
        ref: `${entry.key}#${unit.id}`, source: item.meta.id, title: item.meta.title, status: item.meta.status ?? "unknown",
        where: where(unit), excerpt: excerpt(unit.text, query), score: Number(score.toFixed(5)),
        ...(item.meta.status && item.meta.status !== "current" && { note: `${item.meta.status}${item.meta.supersededBy ? ` (see ${item.meta.supersededBy})` : ""}${item.meta.note ? `: ${item.meta.note}` : ""}` }),
      })
      if (hits.length >= limit) break
    }
    return { hits, mode, ...(note && { note }) }
  }

  async read(ref: string, options: { neighbors?: number } = {}): Promise<{ text: string; previous?: string; next?: string; meta: SourceMeta; where: string } | undefined> {
    const match = /^(.+)#(\d+)$/.exec(ref.trim())
    if (!match) throw new Error(`Not a section reference: ${ref} (expected <source ref>#<n>, as returned by library_search)`)
    const item = (await this.stored()).find(entry => Library.key(entry.library, entry.meta.id) === match[1] || entry.meta.id === match[1])
    if (!item) return undefined
    const id = Number(match[2])
    const from = Math.max(0, id - (options.neighbors ?? 0)), to = Math.min(item.units.length - 1, id + (options.neighbors ?? 0))
    const units = item.units.slice(from, to + 1)
    if (!units.length) return undefined
    const key = Library.key(item.library, item.meta.id)
    return {
      meta: item.meta, where: units.length === 1 ? where(units[0]!) : `${where(units[0]!)} … ${where(units.at(-1)!)}`,
      text: units.map(unit => `### ${where(unit)}\n\n${unit.text}`).join("\n\n"),
      ...(from > 0 && { previous: `${key}#${from - 1}` }), ...(to < item.units.length - 1 && { next: `${key}#${to + 1}` }),
    }
  }

  /** Headings of a source (its table of contents) with section references. */
  async outline(sourceId: string): Promise<{ ref: string; where: string }[]> {
    const item = (await this.stored()).find(entry => entry.meta.id === sourceId || Library.key(entry.library, entry.meta.id) === sourceId)
    if (!item) return []
    const key = Library.key(item.library, item.meta.id)
    const seen = new Set<string>()
    return item.units.flatMap(unit => { const label = unit.heading.join(" › "); if (seen.has(label)) return []; seen.add(label); return [{ ref: `${key}#${unit.id}`, where: where(unit) }] })
  }

  async clear(): Promise<void> { await rm(this.root, { recursive: true, force: true }); this.#index = undefined; this.#indexStamp = undefined; this.#stored.clear() }
}

export interface SyncReport { added: number; updated: number; removed: number; unchanged: number; failed: { source: string; error: string }[] }

const metaOf = (source: SourceInput): SourceMeta => {
  const { kind: _, path: __, ...meta } = source
  return meta
}
export const where = (unit: Unit) => `${unit.heading.join(" › ") || "(start)"}${unit.pages ? `, p. ${unit.pages[0]}${unit.pages[1] !== unit.pages[0] ? `–${unit.pages[1]}` : ""}` : ""}`

/** The part of a section around the best matching words. */
export function excerpt(text: string, query: string, size = 1200): string {
  if (text.length <= size) return text
  const words = new Set(terms(query))
  let best = 0, bestScore = -1
  for (let start = 0; start < text.length; start += 200) {
    const score = terms(text.slice(start, start + size)).filter(term => words.has(term)).length
    if (score > bestScore) { best = start; bestScore = score }
  }
  return `${best > 0 ? "…" : ""}${text.slice(best, best + size)}${best + size < text.length ? "…" : ""}`
}

// ------------------------------------------------------------------ private folders

export interface FolderCatalogEntry extends Partial<SourceMeta> { readonly file: string }

/** A folder as a library: every supported file, described by the folder's catalog.json where present. */
export async function folderSources(folder: string): Promise<SourceInput[]> {
  let catalog: FolderCatalogEntry[] = []
  try { catalog = (JSON.parse(await readFile(join(folder, "catalog.json"), "utf8")) as { sources?: FolderCatalogEntry[] }).sources ?? [] } catch {}
  const described = new Map(catalog.map(entry => [entry.file, entry]))
  const files: string[] = []
  const walk = async (directory: string, depth: number) => {
    if (depth > 6) return
    for (const entry of await readdir(directory, { withFileTypes: true }).catch(() => [])) {
      if (entry.name.startsWith(".")) continue
      const path = join(directory, entry.name)
      if (entry.isDirectory()) await walk(path, depth + 1)
      else if (entry.isFile() && LIBRARY_FILES.has(extname(entry.name).toLowerCase()) && entry.name !== "catalog.json") files.push(relative(folder, path).split(sep).join("/"))
    }
  }
  await walk(folder, 0)
  const used = new Set<string>()
  return files.sort().flatMap(file => {
    const entry = described.get(file)
    if (entry && (entry as { skip?: boolean }).skip) return []
    let id = entry?.id ?? slug(basename(file, extname(file)))
    while (used.has(id)) id = `${id}-${used.size}`
    used.add(id)
    const { file: _, ...meta } = entry ?? { file }
    return [{ ...meta, id, title: entry?.title ?? basename(file, extname(file)).replace(/[_-]+/g, " "), status: entry?.status ?? "unknown", kind: "file" as const, path: join(folder, file) }]
  })
}

export const libraryId = (folder: string) => `lib-${hash(folder).slice(0, 10)}`
export async function untar(archive: string, into: string): Promise<void> { await mkdir(into, { recursive: true }); await run("tar", ["-xzf", archive, "-C", into], { timeout: 300_000 }) }
