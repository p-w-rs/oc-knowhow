// Reference libraries for agents: sources (PDF, web pages, Markdown, notebooks, Office files, gnuplot's demos and docs)
// are converted into clean sections with heading paths and page numbers, indexed for keyword (BM25) and meaning-based
// search, and read back by id with citations. Everything lives in the plugin's data folder; nothing is shipped.
import { execFile } from "node:child_process"
import { createHash, randomBytes } from "node:crypto"
import { readFileSync } from "node:fs"
import { mkdir, open, readdir, readFile, rename, rm, stat, unlink, writeFile } from "node:fs/promises"
import { basename, extname, join, relative, resolve, sep } from "node:path"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"
import { colgrep, type Runtime } from "./backend.js"
import { documentKind, extractDocument, readBounded, type Extracted } from "./documents.js"
import { VERSION } from "./settings.js"

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
/**
 * A source to index: a file on disk, a source tree (code + READMEs), a changelog, gnuplot's sources, or a link that is
 * only listed. `deep`: a source tree that can change in place (the user's folders, an installed compiler), so its
 * fingerprint looks at every kept file, not only the folder.
 */
export interface SourceInput extends SourceMeta { readonly kind: "file" | "link" | "gnuplot-source" | "source-tree" | "changelog"; readonly path?: string; readonly version?: string; readonly paths?: readonly string[]; readonly exclude?: readonly string[]; readonly extensions?: readonly string[]; readonly deep?: boolean }
export interface Unit { readonly id: number; readonly heading: readonly string[]; readonly pages?: readonly [number, number]; readonly text: string }
/** What the library knows about a stored source, without its section texts (those are loaded on demand). */
export interface StoredInfo { version: 1; library: string; meta: SourceMeta; kind: string; path?: string; fingerprint: string; sections: number; error?: string; indexedAt: string }
interface Stored extends Omit<StoredInfo, "sections"> { units: Unit[] }

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
export const LIBRARY_FILES = new Set([...TEXT_FILES, ".pdf", ".html", ".htm", ".ipynb", ".docx", ".pptx", ".xlsx", ".jai", ".odin"])

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

// ------------------------------------------------------------------ source code (Odin, C, C++ headers)

export const CODE_FILES = new Set([".odin", ".jai", ".c", ".h", ".cc", ".cpp", ".hpp", ".inl", ".rs", ".zig", ".py", ".pyi", ".js", ".ts", ".json5", ".fbs", ".proto", ".cmake", ".repl", ".resc", ".robot", ".yaml"])
const CODE_UNIT_CHARS = 2500

interface Declaration { readonly line: number; readonly name: string }

/**
 * Groups declarations into units of about `size` characters. Each declaration owns the comment lines just above it;
 * `inner` adds the names of members (struct fields, foreign procedures) to the unit's label.
 */
function groupDeclarations(relpath: string, source: string, lines: readonly string[], starts: readonly Declaration[], ownsAbove: (line: number) => boolean, size: number, inner: (part: string) => string[]): Omit<Unit, "id">[] {
  const begin = (line: number) => { let j = line; while (j > 0 && ownsAbove(j - 1)) j--; return j }
  const decls = starts.map((start, k) => ({ name: start.name, line: start.line, from: begin(start.line), to: k + 1 < starts.length ? begin(starts[k + 1]!.line) : lines.length }))
  if (!decls.length) return chunk(source, size).map(text => ({ heading: [relpath], text: `${relpath}\n\n${text}` }))
  if (decls[0]!.from > 0) decls.unshift({ name: "(file header)", line: 0, from: 0, to: decls[0]!.from })
  const units: Omit<Unit, "id">[] = []
  let group: typeof decls = []
  let length = 0
  const flush = () => {
    if (!group.length) return
    const first = group[0]!, last = group.at(-1)!
    const body = lines.slice(first.from, last.to).join("\n").replace(/\n{3,}/g, "\n\n").trim()
    const names = group.map(d => d.name)
    const label = names.length <= 4 ? names.join(", ") : `${names.slice(0, 3).join(", ")} … ${names.at(-1)}`
    for (const [index, part] of chunk(body, size).entries()) {
      const members = [...new Set(inner(part))].filter(name => !names.includes(name))
      const shown = members.length ? `${label}: ${members.slice(0, 3).join(", ")}${members.length > 3 ? " …" : ""}` : label
      units.push({ heading: [relpath, `${shown} (line ${first.line + 1})${index ? ` part ${index + 1}` : ""}`], text: `${relpath}:${first.line + 1} — ${[...names, ...members].join(", ")}\n\n${part}` })
    }
    group = []; length = 0
  }
  for (const decl of decls) {
    const span = lines.slice(decl.from, decl.to).join("\n").length
    if (length && length + span > size) flush()
    group.push(decl); length += span
    if (length > size) flush()
  }
  flush()
  return units
}

/** Top-level declarations of one source file with the comments above them, in groups of about UNIT_CHARS. */
export function codeUnits(relpath: string, source: string, size = CODE_UNIT_CHARS): Omit<Unit, "id">[] {
  const ext = extname(relpath).toLowerCase()
  if (ext === ".jai") return jaiUnits(relpath, source, size)
  const lines = source.replace(/\r\n?/g, "\n").split("\n")
  const odin = ext === ".odin"
  // A declaration starts at depth 0 on a line that is not a comment/blank/closing brace; it owns the comment lines just above it.
  const starts: { line: number; name: string }[] = []
  let depth = 0, inBlock = false, transparent = 0
  const nameOf = (line: string): string | undefined => {
    if (odin) {
      const m = /^\s*(?:@\([^)]*\)\s*)*([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:[:=]/.exec(line) ?? /^\s*(foreign\s+import\s+\w+|when\b|foreign\s+\w+)/.exec(line)
      return m?.[1]?.trim()
    }
    if (/^\s*#\s*define\s+(\w+)/.test(line)) return /^\s*#\s*define\s+(\w+)/.exec(line)![1]
    if (/^\s*#/.test(line)) return undefined
    const t = /^\s*(?:typedef\s+)?(?:struct|union|enum|class)\s+(\w+)/.exec(line); if (t) return t[1]
    const f = /([A-Za-z_]\w*)\s*\([^;]*$|([A-Za-z_]\w*)\s*\(.*\)\s*(?:const\s*)?[{;]?\s*$/.exec(line); if (f && !/^\s*(if|for|while|switch|return)\b/.test(line)) return f[1] ?? f[2]
    const v = /([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|;)/.exec(line); return v?.[1]
  }
  const commentOnly: boolean[] = []
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i]!
    let line = raw
    if (inBlock) { const end = line.indexOf("*/"); if (end < 0) { commentOnly[i] = true; continue } line = line.slice(end + 2); inBlock = false; if (!line.trim()) { commentOnly[i] = true; continue } }
    const code = line.replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[^`]*`/g, '""').replace(/\/\*.*?\*\//g, "")
    const open = code.indexOf("/*")
    const stripped = (open >= 0 ? code.slice(0, open) : code).replace(/\/\/.*$/, "")
    if (open >= 0) inBlock = true
    if (!stripped.trim() && raw.trim() && (open >= 0 || /^\s*\/\//.test(raw) || /\*\//.test(raw))) commentOnly[i] = true
    if (!stripped.trim() && /^\s*(@\(|#\+)/.test(raw)) commentOnly[i] = true
    if (depth === 0 && stripped.trim() && !/^\s*[})\]]/.test(stripped)) {
      const name = nameOf(stripped)
      if (name) starts.push({ line: i, name })
    }
    // extern "C" { … } and namespace blocks do not nest declarations.
    if (depth === 0 && /^\s*(extern\s*""|namespace\b[^{(;]*)\s*\{\s*$/.test(stripped)) { transparent++; continue }
    for (const ch of stripped) {
      if (ch === "{" || ch === "(") depth++
      else if (ch === "}" || ch === ")") { if (depth > 0) depth--; else if (ch === "}" && transparent > 0) transparent-- }
    }
  }
  // Each declaration's span begins at its leading comment block. Inside foreign/struct/enum blocks the members carry
  // the names people search for (e.g. CreateWindow).
  const member = odin ? /^[ \t]+([A-Za-z_]\w*)\s*::/gm : /^[ \t]{0,4}(?:[A-Z_][\w]*\s+)?(?:const\s+)?(?:struct\s+)?[A-Za-z_]\w*[\s*]+([A-Za-z_]\w*)\s*\([^;{]*\)\s*;/gm
  return groupDeclarations(relpath, source, lines, starts, j => !!commentOnly[j] || /^\s*@\(/.test(lines[j]!), size, part => [...part.matchAll(member)].map(m => m[1]!))
}

// ------------------------------------------------------------------ Jai

/** Directives that start a top-level statement worth its own entry (as opposed to modifiers such as #c_call). */
const JAI_TOP_DIRECTIVES = /^\s*(#(?:import|load|run|insert|if|assert|scope_file|scope_export|scope_module|module_parameters|add_context|placeholder|program_export|library|system_library|foreign_library|foreign_system_library|poke_name|note))\b(?:,\w+)*\s*(?:"([^"]*)"|\(?\s*([A-Za-z_]\w*))?/

/** The name a top-level Jai line declares, if any: `name :: …`, `name: T`, `name := …`, `operator + :: …`, directives. */
export function jaiDeclarationName(line: string): string | undefined {
  const operator = /^\s*(operator\s*(?:\[\]=?|\*=|\/=|\+=|-=|%=|==|!=|<=|>=|<<|>>|[-+*\/%<>!&|^~=]+))\s*::/.exec(line)
  if (operator) return operator[1]!.replace(/\s+/g, " ")
  const declared = /^\s*(?:using\s+)?([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:(?!=\s*=)/.exec(line)
  if (declared && !/^\s*(if|else|for|while|case|return|defer|using|push_context|break|continue|remove)\b/.test(line)) return declared[1]!.replace(/\s+/g, "")
  const directive = JAI_TOP_DIRECTIVES.exec(line)
  if (directive) return [directive[1], directive[2] ? `"${directive[2]}"` : directive[3]].filter(Boolean).join(" ")
  return undefined
}

/**
 * Jai source → top-level declarations with their comments. A small scanner knows Jai's lexical rules: nested block
 * comments, `//` comments, string literals, and `#string IDENT` here-strings that end at the first line starting
 * (after spaces) with IDENT. Backticks are not quotes in Jai (they mark macro backticks). Top-level `#if`/`else`
 * blocks are transparent (their contents are declarations of the file).
 */
export function jaiUnits(relpath: string, source: string, size = CODE_UNIT_CHARS): Omit<Unit, "id">[] {
  const lines = source.replace(/\r\n?/g, "\n").split("\n")
  const starts: Declaration[] = []
  const commentOnly: boolean[] = []
  let depth = 0, comment = 0
  let here: string | undefined
  const transparent: number[] = []
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i]!
    if (here !== undefined) {
      const trimmed = raw.trimStart()
      if (trimmed.startsWith(here) && !/[\w]/.test(trimmed[here.length] ?? "")) here = undefined
      continue
    }
    // The code on this line with comments removed and string contents blanked (strings become ""); `named` keeps
    // the string contents so that `#import "Basic"` stays recognisable.
    let code = "", named = ""
    let j = 0
    while (j < raw.length) {
      if (comment > 0) {
        if (raw.startsWith("/*", j)) { comment++; j += 2 } else if (raw.startsWith("*/", j)) { comment--; j += 2 } else j++
        continue
      }
      if (raw.startsWith("//", j)) break
      if (raw.startsWith("/*", j)) { comment++; j += 2; continue }
      const ch = raw[j]!
      if (ch === "\"") {
        const from = j
        j++
        while (j < raw.length && raw[j] !== "\"") j += raw[j] === "\\" ? 2 : 1
        j++; code += "\"\""; named += raw.slice(from, j)
        continue
      }
      const string = /^#string(?:,\w+)*\s+([A-Za-z_]\w*)/.exec(raw.slice(j))
      if (string) { here = string[1]!; code += "#string"; named += "#string"; break }
      code += ch; named += ch; j++
    }
    const stripped = code.trim()
    if (!stripped) { if (raw.trim()) commentOnly[i] = true; continue }
    if (depth === 0 && !/^[})\]]/.test(stripped)) {
      const name = jaiDeclarationName(named)
      if (name) starts.push({ line: i, name })
    }
    // `#if X {` and `} else {` at the top level: their contents are top-level declarations.
    const opensTransparent = depth === 0 && /^(#if\b.*|\}?\s*else\b.*)\{\s*$/.test(stripped) && !/\}\s*$/.test(stripped.replace(/^\}/, ""))
    for (const ch of code) {
      if (ch === "{" || ch === "(" || ch === "[") depth++
      else if (ch === "}" || ch === ")" || ch === "]") {
        if (depth > 0) depth--
        else if (ch === "}" && transparent.length) transparent.pop()
      }
    }
    if (opensTransparent && depth === 1) { depth = 0; transparent.push(i) }
  }
  // Struct and enum members, and procedures inside foreign blocks, are searchable by name.
  const member = /^[ \t]+([A-Za-z_]\w*)\s*(?::|;\s*$)/gm
  return groupDeclarations(relpath, source, lines, starts, j => !!commentOnly[j] || /^\s*@\w/.test(lines[j]!), size, part => [...part.matchAll(member)].map(m => m[1]!).filter(name => !/^(if|else|for|while|case|return|defer|using|it|it_index)$/.test(name)))
}

/**
 * A changelog with versioned headings ("Version: beta 0.2.032, 26 November 2026", "## 1.2.0 - 2026-01-02",
 * "v1.2.0 (2026-01-02)") → one section per version, split further when long. The heading is the version line.
 */
export function changelogUnits(text: string): Omit<Unit, "id">[] {
  const units: Omit<Unit, "id">[] = []
  const lines = text.replace(/\r\n?/g, "\n").split("\n")
  const isVersion = (line: string) => /^(?:#{1,3}\s*)?(?:Version:?\s+)?(?:beta\s+)?v?\d+\.\d+(?:\.\d+)?\b.*$/i.test(line.trim()) && line.trim().length < 120 && !/^\s/.test(line)
  let heading = "(start)"
  let buffer: string[] = []
  const flush = () => {
    const body = buffer.join("\n").replace(/^[-=\s]+\n/, "").replace(/\n{3,}/g, "\n\n").trim()
    if (body.length > 20 || heading !== "(start)") for (const [index, part] of chunk(body || "(no notes)").entries()) units.push({ heading: [`${heading}${index ? ` (part ${index + 1})` : ""}`], text: `${heading}\n\n${part}` })
    buffer = []
  }
  for (const line of lines) {
    if (isVersion(line)) { flush(); heading = line.trim().replace(/^#+\s*/, ""); continue }
    buffer.push(line)
  }
  flush()
  return units.filter(unit => unit.text.length > 10)
}

export interface TreeOptions { readonly paths?: readonly string[]; readonly exclude?: readonly string[]; readonly extensions?: readonly string[]; readonly signal?: AbortSignal; readonly maxFileBytes?: number }

/**
 * The files of a source tree that get indexed: code files and README/Markdown under the kept paths. `exclude` entries
 * are path prefixes, or `*` patterns over the whole relative path ("**\/windows.jai", "modules/*\/examples"). Plain
 * text files (.txt) are kept only when `extensions` lists ".txt".
 */
export async function sourceTreeFiles(root: string, options: TreeOptions = {}): Promise<{ rel: string; path: string; size: number; mtimeMs: number }[]> {
  // Unit tests drown real API matches in search results: skip them, except under a path the reference keeps on purpose.
  const kept = (rel: string) => (options.paths ?? []).some(path => { const p = path.replace(/\/$/, ""); return /(^|\/)tests?(\/|$)/.test(p) && (rel === p || rel.startsWith(`${p}/`)) })
  const patterns = (options.exclude ?? []).filter(pattern => pattern.includes("*")).map(pattern => new RegExp(`^${pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*\*\//g, "(?:.*/)?").replace(/\*\*/g, ".*").replace(/\*/g, "[^/]*")}(?:/|$)`))
  const excluded = (rel: string) => (options.exclude ?? []).some(pattern => !pattern.includes("*") && (rel === pattern || rel.startsWith(`${pattern.replace(/\/$/, "")}/`)))
    || patterns.some(pattern => pattern.test(rel))
    || /(^|\/)(\.git|node_modules|build|\.build|\.pixi)(\/|$)/.test(rel)
    || (!kept(rel) && (/(^|\/)(tests?|__tests__|testdata|test_data)(\/|$)/.test(rel) || /(^|\/)(test_[^/]*|[^/]*_tests?)\.(py|c|cc|cpp|rs|odin|jai)$/.test(rel)))
  const wanted = (name: string) => {
    const ext = extname(name).toLowerCase()
    if (ext === ".md" || ext === ".markdown" || ext === ".rst") return true
    if (ext === ".txt") return !!options.extensions?.includes(".txt")
    return CODE_FILES.has(ext) && (!options.extensions?.length || options.extensions.includes(ext))
  }
  const files: { rel: string; path: string; size: number; mtimeMs: number }[] = []
  const add = async (path: string, rel: string) => {
    const info = await stat(path).catch(() => undefined)
    if (info?.isFile() && info.size <= (options.maxFileBytes ?? 2 * 1024 * 1024)) files.push({ rel, path, size: info.size, mtimeMs: info.mtimeMs })
  }
  const walk = async (dir: string, rel: string): Promise<void> => {
    options.signal?.throwIfAborted()
    for (const entry of (await readdir(dir, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
      const childRel = rel ? `${rel}/${entry.name}` : entry.name
      if (excluded(childRel)) continue
      if (entry.isDirectory()) { await walk(join(dir, entry.name), childRel); continue }
      if (entry.isFile() && wanted(entry.name)) await add(join(dir, entry.name), childRel)
    }
  }
  for (const top of options.paths?.length ? options.paths : [""]) {
    const target = join(root, top)
    const info = await stat(target).catch(() => undefined)
    if (!info) continue
    if (info.isDirectory()) await walk(target, top.replace(/\/$/, ""))
    else if (info.isFile() && wanted(top)) await add(target, top)
  }
  return files
}

/** Every code file and README/Markdown under the kept paths of a source tree, as units headed by file and declaration. */
export async function sourceTreeUnits(root: string, options: TreeOptions = {}): Promise<Omit<Unit, "id">[]> {
  const units: Omit<Unit, "id">[] = []
  for (const file of await sourceTreeFiles(root, options)) {
    options.signal?.throwIfAborted()
    const ext = extname(file.rel).toLowerCase()
    const text = await readFile(file.path, "utf8")
    if (ext === ".md" || ext === ".markdown" || ext === ".rst") units.push(...markdownUnits(text).map(unit => ({ ...unit, heading: [file.rel, ...unit.heading] })))
    else if (ext === ".txt") units.push(...markdownUnits(text).map(unit => ({ ...unit, heading: [file.rel, ...unit.heading] })))
    else units.push(...codeUnits(file.rel, text))
  }
  return units
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
//
// Layout under <data>/library/:
//   sources/<key>.jsonl       one source: line 1 describes it, then one section per line (written once per change)
//   info/<key>.json           the description plus each section's byte offset in the .jsonl (rebuilt from it if lost)
//   index-v3.json             keyword index header: source keys, terms, sizes
//   index-v3.<id>.bin         uint32 arrays: section source, unit id and length; term offsets and counts; postings as
//                             (section, count) pairs
//   mirror/<key>--<n>.md      one small file per section for the meaning-based engine
// A process keeps one Library per data folder (OpenCode loads plugins once per project location), the index lives in
// typed arrays, and section texts are read from disk one section at a time.

interface IndexHeader {
  version: 3
  /** Unique per rebuild: names the matching .bin file. */
  id: string
  keys: string[]
  sections: number
  terms: string[]
  pairs: number
}

interface LoadedIndex {
  readonly id: string
  readonly keys: readonly string[]
  readonly sectionSource: Uint32Array
  readonly sectionUnit: Uint32Array
  readonly lengths: Uint32Array
  readonly average: number
  readonly terms: ReadonlyMap<string, number>
  readonly termOffsets: Uint32Array
  readonly termCounts: Uint32Array
  readonly postings: Uint32Array
  /** Mirror file name → section, built on first use by meaning-based search. */
  byName?: Map<string, number>
}

interface InfoFile extends StoredInfo { sourceStamp: number; offsets: number[] }
interface Entry { readonly item: StoredInfo; readonly stamp: number; readonly offsets: readonly number[] }

const EMPTY_INDEX: LoadedIndex = { id: "", keys: [], sectionSource: new Uint32Array(), sectionUnit: new Uint32Array(), lengths: new Uint32Array(), average: 0, terms: new Map(), termOffsets: new Uint32Array(), termCounts: new Uint32Array(), postings: new Uint32Array() }
const CHUNK = 1 << 22

/**
 * Library instances shared within this process, one per data folder and copy of this file. OpenCode evaluates the
 * plugin once per project location, so several copies of this module run side by side: copies of the same file share
 * one library, and use another copy's instance only through its methods (a copy cannot touch another's #fields).
 */
const shared: Map<string, Library> = ((globalThis as Record<symbol, unknown>)[Symbol.for("oc-knowhow.libraries.v2")] ??= new Map()) as Map<string, Library>
const MODULE_FILE = (() => { const url = import.meta.url.replace(/[?#].*$/, ""); try { return fileURLToPath(url) } catch { return url } })()
let moduleHash: string | undefined
/** This file's path and contents: a changed or different copy (a newer release, a development checkout) never shares. */
function moduleKey(): string {
  try { moduleHash ??= createHash("sha256").update(readFileSync(MODULE_FILE)).digest("hex").slice(0, 16) } catch { moduleHash ??= VERSION }
  return `${MODULE_FILE}:${moduleHash}`
}

/** Byte offsets where the lines of a file start. */
function lineStarts(bytes: Uint8Array): number[] {
  const starts = [0]
  for (let at = bytes.indexOf(10); at >= 0; at = bytes.indexOf(10, at + 1)) starts.push(at + 1)
  return starts
}

export class Library {
  readonly root: string
  readonly sourcesDir: string
  readonly infoDir: string
  readonly mirror: string
  #index?: LoadedIndex
  #indexStamp?: number
  #info = new Map<string, Entry>()
  progress?: Progress
  #running?: Promise<SyncReport>
  #runningKey?: string
  #refs = 0
  #sharedKey?: string

  constructor(dataDirectory: string, private readonly runtime: () => Promise<Runtime | undefined>) {
    this.root = join(dataDirectory, "library")
    this.sourcesDir = join(this.root, "sources")
    this.infoDir = join(this.root, "info")
    this.mirror = join(this.root, "mirror")
  }

  /** The process-wide library for a data folder: every plugin instance (one per project location) shares it. */
  static shared(dataDirectory: string, runtime: () => Promise<Runtime | undefined>): Library {
    const key = `${moduleKey()}:${resolve(dataDirectory)}`
    let library = shared.get(key)
    if (!library) { library = new Library(dataDirectory, runtime); library.#sharedKey = key; shared.set(key, library) }
    return library
  }

  /** `shared`, counting users: when the last one releases it (plugin unloaded or updated), its memory is let go. */
  static acquire(dataDirectory: string, runtime: () => Promise<Runtime | undefined>): Library {
    // A method call, not `library.#refs++`: the instance may come from another copy of this module.
    return Library.shared(dataDirectory, runtime).retain()
  }

  /** Counts one more user of a shared library (see `acquire`). */
  retain(): this {
    this.#refs++
    return this
  }

  release(): void {
    if (--this.#refs > 0) return
    const drop = () => {
      if (this.#refs > 0 || !this.#sharedKey || shared.get(this.#sharedKey) !== this) return
      shared.delete(this.#sharedKey)
      this.#index = undefined; this.#indexStamp = undefined; this.#info.clear()
    }
    // A running update finishes first (a new instance must not start a second one on the same folder meanwhile).
    if (this.#running) void this.#running.then(drop, drop); else drop()
  }

  #file = (key: string) => join(this.sourcesDir, `${key}.jsonl`)
  #infoFile = (key: string) => join(this.infoDir, `${key}.json`)
  static key = (library: string, source: string) => `${library}--${source}`

  /** Every stored source (without section texts). Rereads entries another process changed. */
  async stored(): Promise<StoredInfo[]> {
    await mkdir(this.sourcesDir, { recursive: true })
    await mkdir(this.infoDir, { recursive: true })
    const names = await readdir(this.sourcesDir)
    const result: StoredInfo[] = []
    const seen = new Set<string>()
    for (const name of names) {
      if (!name.endsWith(".jsonl")) continue
      const key = name.slice(0, -6)
      const entry = await this.#entry(key)
      if (!entry) continue
      seen.add(key)
      result.push(entry.item)
    }
    for (const key of [...this.#info.keys()]) if (!seen.has(key)) this.#info.delete(key)
    return result
  }

  /** A source's description and section offsets: cached, else from its sidecar, else from the .jsonl itself. */
  async #entry(key: string): Promise<Entry | undefined> {
    const stamp = await stat(this.#file(key)).then(info => info.mtimeMs, () => undefined)
    if (stamp === undefined) { this.#info.delete(key); return undefined }
    const cached = this.#info.get(key)
    if (cached && cached.stamp === stamp) return cached
    let entry: Entry | undefined
    try {
      const { sourceStamp, offsets, ...item } = JSON.parse(await readFile(this.#infoFile(key), "utf8")) as InfoFile
      if (sourceStamp === stamp && Array.isArray(offsets)) entry = { item, stamp, offsets }
    } catch {}
    if (!entry) {
      try {
        const bytes = await readFile(this.#file(key))
        const starts = lineStarts(bytes)
        const item = JSON.parse(bytes.subarray(0, starts[1]! - 1).toString("utf8")) as StoredInfo
        const offsets = starts.slice(1)
        entry = { item: { ...item, sections: Math.max(0, offsets.length - 1) }, stamp, offsets }
        await this.#writeInfo(key, entry)
      } catch { return undefined }
    }
    this.#info.set(key, entry)
    return entry
  }

  async #writeInfo(key: string, entry: Entry) {
    await mkdir(this.infoDir, { recursive: true })
    const temporary = `${this.#infoFile(key)}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`
    await writeFile(temporary, JSON.stringify({ ...entry.item, sourceStamp: entry.stamp, offsets: entry.offsets }))
    await rename(temporary, this.#infoFile(key))
  }

  /** All sections of one source, read from disk. */
  async units(key: string): Promise<Unit[]> {
    const text = await readFile(this.#file(key), "utf8").catch(() => undefined)
    if (!text) return []
    const lines = text.split("\n")
    return lines.slice(1).filter(Boolean).map(line => JSON.parse(line) as Unit)
  }

  /** Sections `from`…`to` of one source, reading only their bytes. */
  async #sections(key: string, from: number, to = from): Promise<Unit[]> {
    const entry = await this.#entry(key)
    if (!entry) return []
    const last = Math.min(to, entry.item.sections - 1)
    if (from < 0 || from > last) return []
    try {
      const start = entry.offsets[from]!, end = entry.offsets[last + 1]!
      const handle = await open(this.#file(key), "r")
      try {
        const buffer = Buffer.alloc(end - start)
        await handle.read(buffer, 0, end - start, start)
        return buffer.toString("utf8").split("\n").filter(Boolean).map(line => JSON.parse(line) as Unit)
      } finally { await handle.close() }
    } catch {
      // Replaced by another process between reading the offsets and the file: read it whole.
      this.#info.delete(key)
      return (await this.units(key)).slice(from, last + 1)
    }
  }

  /**
   * Brings the index in line with the given libraries: new and changed sources are converted, removed ones dropped.
   * One run at a time per library: a request for the same libraries joins the running one; a different request (new
   * downloads, another folder) runs after it, so its changes are never lost to a run that started earlier.
   */
  sync(libraries: readonly LibrarySpec[], signal?: AbortSignal): Promise<SyncReport> {
    const key = JSON.stringify(libraries)
    if (this.#running && this.#runningKey === key) return this.#running
    const previous = this.#running
    const run: Promise<SyncReport> = (async () => {
      if (previous) await previous.catch(() => {})
      return this.#sync(libraries, signal)
    })().finally(() => { if (this.#running === run) { this.#running = undefined; this.#runningKey = undefined; this.progress = undefined } })
    this.#running = run
    this.#runningKey = key
    return run
  }

  async #sync(libraries: readonly LibrarySpec[], signal?: AbortSignal): Promise<SyncReport> {
    await mkdir(this.mirror, { recursive: true })
    await this.#cleanTemporary()
    const report: SyncReport = { added: 0, updated: 0, removed: 0, unchanged: 0, failed: [] }
    const wanted = new Map<string, { library: LibrarySpec; source: SourceInput }>()
    for (const library of libraries) for (const source of library.sources) wanted.set(Library.key(library.id, source.id), { library, source })
    const existing = await this.stored()
    const changed = new Set<string>()
    for (const item of existing) {
      const key = Library.key(item.library, item.meta.id)
      if (!wanted.has(key)) {
        await unlink(this.#file(key)).catch(() => {}); await unlink(this.#infoFile(key)).catch(() => {})
        this.#info.delete(key); report.removed++
      }
    }
    const current = new Map(existing.map(item => [Library.key(item.library, item.meta.id), item]))
    let done = 0
    for (const [key, { library, source }] of wanted) {
      signal?.throwIfAborted()
      this.progress = { step: `Reading ${source.title}`, done: done++, total: wanted.size }
      const fingerprint = await this.#fingerprint(source, signal)
      const old = current.get(key)
      if (old && old.fingerprint === fingerprint) {
        if (JSON.stringify(old.meta) !== JSON.stringify(metaOf(source))) {
          // Description changes (catalog entries, references.json) don't need a re-read; the texts stay as they are.
          const { sections: _, ...rest } = old
          await this.#save(key, { ...rest, meta: metaOf(source), units: await this.units(key) })
          changed.add(key)
        }
        report.unchanged++
        continue
      }
      let units: Omit<Unit, "id">[] = [], error: string | undefined
      try { units = source.kind === "link" ? [] : await this.#convert(source, signal) }
      catch (cause) { if (signal?.aborted) throw cause; error = cause instanceof Error ? cause.message : String(cause); report.failed.push({ source: source.title, error }) }
      const stored: Stored = { version: 1, library: library.id, meta: metaOf(source), kind: source.kind, ...(source.path && { path: source.path }), fingerprint, units: units.map((unit, id) => ({ id, ...unit })), ...(error && { error }), indexedAt: new Date().toISOString() }
      await this.#save(key, stored)
      changed.add(key)
      if (old) report.updated++; else report.added++
    }
    const header = await this.#header()
    let stale = !header || header.keys.length !== wanted.size || header.keys.some(key => !wanted.has(key))
    if (!stale && header && !changed.size && !report.removed) {
      // The mirror (one file per section, for the meaning-based engine) must match the index; rebuild it if not.
      const files = (await readdir(this.mirror).catch(() => [] as string[])).length
      stale = files !== header.sections
    }
    if (changed.size || report.removed || stale) {
      this.progress = { step: "Building the index", done: wanted.size, total: wanted.size + 1 }
      await this.#rebuild(changed)
      const runtime = await this.runtime()
      if (runtime) {
        this.progress = { step: "Building the meaning-based index (first time can take several minutes)", done: wanted.size, total: wanted.size + 1 }
        await colgrep(runtime, this.mirror, "index warm-up", 1, signal, 60 * 60_000).catch(() => {})
      }
    }
    return report
  }

  /** Leftovers of interrupted writes (another process may still be writing a recent one). */
  async #cleanTemporary() {
    const now = Date.now()
    for (const dir of [this.root, this.sourcesDir, this.infoDir]) {
      for (const name of await readdir(dir).catch(() => [] as string[])) {
        if (!name.endsWith(".tmp")) continue
        const path = join(dir, name)
        const info = await stat(path).catch(() => undefined)
        if (info && now - info.mtimeMs > 10 * 60_000) await unlink(path).catch(() => {})
      }
    }
  }

  async #save(key: string, stored: Stored) {
    await mkdir(this.sourcesDir, { recursive: true })
    const { units, ...rest } = stored
    const item: StoredInfo = { ...rest, sections: units.length }
    const lines = [JSON.stringify(item), ...units.map(unit => JSON.stringify(unit))]
    const offsets: number[] = []
    let position = Buffer.byteLength(lines[0]!) + 1
    for (let i = 1; i < lines.length; i++) { offsets.push(position); position += Buffer.byteLength(lines[i]!) + 1 }
    offsets.push(position)
    const temporary = `${this.#file(key)}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`
    await writeFile(temporary, `${lines.join("\n")}\n`)
    await rename(temporary, this.#file(key))
    const stamp = await stat(this.#file(key)).then(info => info.mtimeMs, () => -1)
    const entry: Entry = { item, stamp, offsets }
    await this.#writeInfo(key, entry)
    this.#info.set(key, entry)
  }

  /** What identifies a source's content: file size and time, or for deep trees every kept file's. */
  async #fingerprint(source: SourceInput, signal?: AbortSignal): Promise<string> {
    if (source.kind === "link" || !source.path) return `link:${source.url ?? ""}`
    // Same format as before for existing kinds, so an upgrade does not re-read every book and source tree.
    const options = `${source.version ?? ""}:${(source.paths ?? []).join(",")}:${(source.exclude ?? []).join(",")}:${(source.extensions ?? []).join(",")}:${source.kind === "source-tree" ? "v3" : "v2"}`
    try {
      if (source.kind === "source-tree" && source.deep) {
        const files = await sourceTreeFiles(source.path, { paths: source.paths, exclude: source.exclude, extensions: source.extensions, signal })
        return `tree:${hash(files.map(file => `${file.rel}:${file.size}:${Math.round(file.mtimeMs)}`).join("\n"))}:${options}`
      }
      const info = await stat(source.path)
      return `${source.kind}:${info.size}:${Math.round(info.mtimeMs)}:${options}`
    } catch { return "missing" }
  }

  async #convert(source: SourceInput, signal?: AbortSignal): Promise<Omit<Unit, "id">[]> {
    const path = source.path!
    if (source.kind === "source-tree") return sourceTreeUnits(path, { paths: source.paths, exclude: source.exclude, extensions: source.extensions, signal })
    if (source.kind === "changelog") return changelogUnits(await readFile(path, "utf8"))
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
    if (CODE_FILES.has(extension) && !TEXT_FILES.has(extension)) return codeUnits(basename(path), await readFile(path, "utf8"))
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

  /**
   * Keyword index (BM25 postings) over every stored section, plus one small file per section for the meaning-based
   * engine. Pass 1 reads one source at a time and records each section's (term, count) pairs in compact chunks; pass 2
   * places them by term. Memory stays near the size of the finished index; mirror files are rewritten only for sources
   * that changed.
   */
  async #rebuild(changed: ReadonlySet<string>): Promise<void> {
    const infos = await this.stored()
    const keys = infos.map(info => Library.key(info.library, info.meta.id))
    const termIds = new Map<string, number>()
    let df = new Uint32Array(1 << 16)
    const sectionSource: number[] = [], sectionUnit: number[] = [], lengths: number[] = [], distinct: number[] = []
    const chunks: Uint32Array[] = []
    let current = new Uint32Array(CHUNK), used = 0
    const push = (value: number) => { if (used === CHUNK) { chunks.push(current); current = new Uint32Array(CHUNK); used = 0 } current[used++] = value }
    const expected = new Set<string>()
    const existing = new Set(await readdir(this.mirror).catch(() => [] as string[]))
    for (const [source, info] of infos.entries()) {
      const key = keys[source]!
      for (const unit of await this.units(key)) {
        sectionSource.push(source); sectionUnit.push(unit.id)
        const counts = new Map<number, number>()
        for (const term of terms(`${info.meta.title} ${unit.heading.join(" ")} ${unit.text}`)) {
          let id = termIds.get(term)
          if (id === undefined) { id = termIds.size; termIds.set(term, id) }
          counts.set(id, (counts.get(id) ?? 0) + 1)
        }
        let length = 0
        for (const [id, count] of counts) {
          length += count
          if (id >= df.length) { const grown = new Uint32Array(df.length * 2); grown.set(df); df = grown }
          df[id] = df[id]! + 1
          push(id); push(count)
        }
        lengths.push(length); distinct.push(counts.size)
        const name = mirrorName(key, unit.id)
        expected.add(name)
        if (!existing.has(name) || changed.has(key)) await writeFile(join(this.mirror, name), `${info.meta.title} — ${unit.heading.join(" › ")}${unit.pages ? ` (p. ${unit.pages[0]}${unit.pages[1] !== unit.pages[0] ? `–${unit.pages[1]}` : ""})` : ""}\n\n${unit.text}\n`)
      }
    }
    chunks.push(current.subarray(0, used))
    for (const name of existing) if (!expected.has(name)) await unlink(join(this.mirror, name)).catch(() => {})
    // Pass 2: one array holds everything; postings of each term are in section order.
    const n = lengths.length, t = termIds.size
    let pairs = 0
    for (let id = 0; id < t; id++) pairs += df[id]!
    const data = new Uint32Array(3 * n + 2 * t + 2 * pairs)
    data.set(sectionSource, 0); data.set(lengths, 2 * n); data.set(sectionUnit, n)
    const termOffsets = data.subarray(3 * n, 3 * n + t), termCounts = data.subarray(3 * n + t, 3 * n + 2 * t)
    let offset = 0
    for (let id = 0; id < t; id++) { termOffsets[id] = offset; termCounts[id] = df[id]!; offset += df[id]! }
    const cursor = termOffsets.slice()
    const postings = data.subarray(3 * n + 2 * t)
    let chunk = 0, at = 0
    const next = () => { if (at === chunks[chunk]!.length) { chunk++; at = 0 } return chunks[chunk]![at++]! }
    for (let section = 0; section < n; section++) {
      for (let k = distinct[section]!; k > 0; k--) {
        const id = next(), count = next()
        const slot = cursor[id]!
        cursor[id] = slot + 1
        postings[2 * slot] = section; postings[2 * slot + 1] = count
      }
    }
    chunks.length = 0
    const termList = new Array<string>(t)
    for (const [term, id] of termIds) termList[id] = term
    termIds.clear()
    const indexId = `${Date.now().toString(36)}${randomBytes(3).toString("hex")}`
    const header: IndexHeader = { version: 3, id: indexId, keys, sections: n, terms: termList, pairs }
    const binary = join(this.root, `index-v3.${indexId}.bin`)
    await writeFile(`${binary}.${process.pid}.tmp`, new Uint8Array(data.buffer, data.byteOffset, data.byteLength))
    await rename(`${binary}.${process.pid}.tmp`, binary)
    const temporary = join(this.root, `index-v3.json.${process.pid}.${randomBytes(4).toString("hex")}.tmp`)
    await writeFile(temporary, JSON.stringify(header))
    await rename(temporary, join(this.root, "index-v3.json"))
    // Older index files: keep recent ones for a while (another process may still be reading them).
    for (const name of await readdir(this.root)) {
      if (!/^index-v3\.\w+\.bin$/.test(name) || name === `index-v3.${indexId}.bin`) continue
      const info = await stat(join(this.root, name)).catch(() => undefined)
      if (info && Date.now() - info.mtimeMs > 10 * 60_000) await unlink(join(this.root, name)).catch(() => {})
    }
    this.#index = loadIndex(header, data)
    this.#indexStamp = await stat(join(this.root, "index-v3.json")).then(info => info.mtimeMs, () => undefined)
  }

  async #header(): Promise<IndexHeader | undefined> {
    try { return JSON.parse(await readFile(join(this.root, "index-v3.json"), "utf8")) as IndexHeader } catch { return undefined }
  }

  async #loadIndex(): Promise<LoadedIndex> {
    // Reload when index-v3.json was rewritten (by this process or another, e.g. `pixi run library download`).
    const file = join(this.root, "index-v3.json")
    const stamp = await stat(file).then(info => info.mtimeMs, () => undefined)
    if (this.#index && stamp === this.#indexStamp) return this.#index
    this.#indexStamp = stamp
    try {
      const header = JSON.parse(await readFile(file, "utf8")) as IndexHeader
      const bytes = await readFile(join(this.root, `index-v3.${header.id}.bin`))
      const data = bytes.byteOffset % 4 === 0 ? new Uint32Array(bytes.buffer, bytes.byteOffset, bytes.byteLength >> 2) : new Uint32Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength))
      this.#index = loadIndex(header, data)
    } catch { this.#index = EMPTY_INDEX }
    return this.#index
  }

  keyword(index: LoadedIndex, query: string, allowed: (position: number) => boolean, k: number): [number, number][] {
    const wanted = [...new Set(terms(query))]
    const n = index.lengths.length
    const scores = new Map<number, number>()
    for (const term of wanted) {
      const id = index.terms.get(term)
      if (id === undefined) continue
      const offset = index.termOffsets[id]!, df = index.termCounts[id]!
      const idf = Math.log(1 + (n - df + 0.5) / (df + 0.5))
      for (let i = offset * 2, end = (offset + df) * 2; i < end; i += 2) {
        const position = index.postings[i]!, tf = index.postings[i + 1]!
        if (!allowed(position)) continue
        scores.set(position, (scores.get(position) ?? 0) + idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * index.lengths[position]! / Math.max(1, index.average))))
      }
    }
    return [...scores].sort((a, b) => b[1] - a[1]).slice(0, k)
  }

  async search(query: string, options: { limit?: number; sources?: readonly string[]; fields?: readonly string[]; mode?: "auto" | "semantic" | "keyword"; signal?: AbortSignal } = {}): Promise<{ hits: SearchHit[]; mode: string; note?: string }> {
    const index = await this.#loadIndex()
    const stored = new Map((await this.stored()).map(item => [Library.key(item.library, item.meta.id), item]))
    const fields = options.fields?.map(field => field.toLowerCase())
    const okSource = (item: StoredInfo | undefined) => !!item && (!options.sources?.length || options.sources.includes(item.meta.id)) && (!fields?.length || (item.meta.fields ?? []).some(field => fields.includes(field.toLowerCase())))
    const sourceOk = index.keys.map(key => okSource(stored.get(key)))
    const allowed = (position: number) => sourceOk[index.sectionSource[position]!] === true
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
          const byName = index.byName ??= (() => {
            const names = new Map<string, number>()
            for (let position = 0; position < index.lengths.length; position++) names.set(mirrorName(index.keys[index.sectionSource[position]!]!, index.sectionUnit[position]!), position)
            return names
          })()
          const hits = await colgrep(runtime, this.mirror, query, pool * (options.sources?.length || fields?.length ? 4 : 1), options.signal)
          rankings.push(hits.flatMap(hit => { const position = byName.get(basename(hit.file)); return position !== undefined && allowed(position) ? [position] : [] }))
          mode = rankings.length > 1 ? "hybrid" : "semantic"
        } catch (error) { if (options.signal?.aborted) throw error; note = `Meaning-based search failed (${error instanceof Error ? error.message : String(error)}); keyword ranking was used.`; mode = "keyword" }
      }
    }
    const fused = new Map<number, number>()
    for (const ranking of rankings) ranking.forEach((position, rank) => fused.set(position, (fused.get(position) ?? 0) + 1 / (60 + rank + 1)))
    // Spread results over sources, unless the caller asked for particular sources (then depth within them is wanted).
    const perSourceCap = options.sources?.length ? limit : 2
    const perSource = new Map<string, number>()
    const hits: SearchHit[] = []
    for (const [position, score] of [...fused].sort((a, b) => b[1] - a[1])) {
      const key = index.keys[index.sectionSource[position]!]!
      const item = stored.get(key)
      if (!item) continue
      if ((perSource.get(key) ?? 0) >= perSourceCap) continue
      const unit = (await this.#sections(key, index.sectionUnit[position]!))[0]
      if (!unit) continue
      perSource.set(key, (perSource.get(key) ?? 0) + 1)
      hits.push({
        ref: `${key}#${unit.id}`, source: item.meta.id, title: item.meta.title, status: item.meta.status ?? "unknown",
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
    const item = await this.find(match[1]!)
    if (!item) return undefined
    const key = Library.key(item.library, item.meta.id)
    const id = Number(match[2])
    const from = Math.max(0, id - (options.neighbors ?? 0)), to = Math.min(item.sections - 1, id + (options.neighbors ?? 0))
    const units = await this.#sections(key, from, to)
    if (!units.length) return undefined
    return {
      meta: item.meta, where: units.length === 1 ? where(units[0]!) : `${where(units[0]!)} … ${where(units.at(-1)!)}`,
      text: units.map(unit => `### ${where(unit)}\n\n${unit.text}`).join("\n\n"),
      ...(from > 0 && { previous: `${key}#${from - 1}` }), ...(to < item.sections - 1 && { next: `${key}#${to + 1}` }),
    }
  }

  /**
   * A stored source by its id or full key (`<library>--<id>`). A bare id can name a link in the references and the
   * user's own copy in a folder; the one with text wins.
   */
  async find(sourceOrKey: string): Promise<StoredInfo | undefined> {
    const stored = await this.stored()
    const exact = stored.find(entry => Library.key(entry.library, entry.meta.id) === sourceOrKey)
    if (exact) return exact
    const byId = stored.filter(entry => entry.meta.id === sourceOrKey)
    return byId.find(entry => entry.sections > 0) ?? byId[0]
  }

  /** Headings of a source (its table of contents) with section references. */
  async outline(sourceId: string): Promise<{ ref: string; where: string }[]> {
    const item = await this.find(sourceId)
    if (!item) return []
    const key = Library.key(item.library, item.meta.id)
    const seen = new Set<string>()
    return (await this.units(key)).flatMap(unit => { const label = unit.heading.join(" › "); if (seen.has(label)) return []; seen.add(label); return [{ ref: `${key}#${unit.id}`, where: where(unit) }] })
  }

  async clear(): Promise<void> { await rm(this.root, { recursive: true, force: true }); this.#index = undefined; this.#indexStamp = undefined; this.#info.clear() }
}

function loadIndex(header: IndexHeader, data: Uint32Array): LoadedIndex {
  const n = header.sections, t = header.terms.length
  let at = 0
  const take = (count: number) => { const view = data.subarray(at, at + count); at += count; return view }
  const sectionSource = take(n), sectionUnit = take(n), lengths = take(n), termOffsets = take(t), termCounts = take(t), postings = take(2 * header.pairs)
  let sum = 0
  for (const length of lengths) sum += length
  const terms = new Map<string, number>()
  header.terms.forEach((term, id) => terms.set(term, id))
  return { id: header.id, keys: header.keys, sectionSource, sectionUnit, lengths, average: sum / Math.max(1, n), terms, termOffsets, termCounts, postings }
}

const mirrorName = (key: string, unit: number) => `${key}--${unit}.md`.replace(/[^\w.-]/g, "_")

export interface SyncReport { added: number; updated: number; removed: number; unchanged: number; failed: { source: string; error: string }[] }

const metaOf = (source: SourceInput): SourceMeta => {
  const { kind: _, path: __, paths: ___, exclude: ____, extensions: _____, deep: ______, version, ...meta } = source
  return { ...meta, ...(version && !meta.edition && { edition: version }) }
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

export interface FolderCatalogEntry extends Partial<SourceMeta> {
  readonly file: string
  readonly kind?: "file" | "source-tree"
  readonly skip?: boolean
  readonly paths?: readonly string[]
  readonly exclude?: readonly string[]
  readonly extensions?: readonly string[]
  readonly version?: string
}

/** A folder as a library: every supported file, described by the folder's catalog.json where present. */
/**
 * A folder as a library: every supported file, described by the folder's catalog.json where present. A catalog entry
 * for a sub-folder with `"kind": "source-tree"` turns that folder (e.g. a cloned repository) into one source, indexed
 * like a source tree (`paths`, `exclude`, `extensions`); `"skip": true` leaves a file or folder out.
 */
export async function folderSources(folder: string): Promise<SourceInput[]> {
  let catalog: FolderCatalogEntry[] = []
  try { catalog = (JSON.parse(await readFile(join(folder, "catalog.json"), "utf8")) as { sources?: FolderCatalogEntry[] }).sources ?? [] } catch {}
  const clean = (path: string) => path.replace(/^\.\//, "").replace(/\/+$/, "")
  const described = new Map(catalog.map(entry => [clean(entry.file), entry]))
  const trees = catalog.filter(entry => (entry as { kind?: string }).kind === "source-tree" && !(entry as { skip?: boolean }).skip).map(entry => clean(entry.file))
  const skipped = catalog.filter(entry => (entry as { skip?: boolean }).skip).map(entry => clean(entry.file))
  const files: string[] = []
  const walk = async (directory: string, depth: number) => {
    if (depth > 6) return
    for (const entry of await readdir(directory, { withFileTypes: true }).catch(() => [])) {
      if (entry.name.startsWith(".")) continue
      const path = join(directory, entry.name)
      const rel = relative(folder, path).split(sep).join("/")
      if (entry.isDirectory()) { if (!trees.includes(rel) && !skipped.includes(rel)) await walk(path, depth + 1) }
      else if (entry.isFile() && LIBRARY_FILES.has(extname(entry.name).toLowerCase()) && rel !== "catalog.json") files.push(rel)
    }
  }
  await walk(folder, 0)
  const used = new Set<string>()
  const unique = (id: string) => { let result = id; while (used.has(result)) result = `${id}-${used.size}`; used.add(result); return result }
  const sources: SourceInput[] = []
  for (const tree of trees.sort()) {
    const entry = described.get(tree)!
    const info = await stat(join(folder, tree)).catch(() => undefined)
    if (!info?.isDirectory()) continue
    const { file: _, kind: __, ...meta } = entry as FolderCatalogEntry & { kind?: string }
    sources.push({ ...meta, id: unique(entry.id ?? slug(basename(tree))), title: entry.title ?? basename(tree).replace(/[_-]+/g, " "), status: entry.status ?? "unknown", kind: "source-tree", path: join(folder, tree), deep: true })
  }
  for (const file of files.sort()) {
    const entry = described.get(file)
    if (entry && (entry as { skip?: boolean }).skip) continue
    const { file: _, ...meta } = entry ?? { file }
    const { kind: _k, skip: _s, ...fileMeta } = meta as FolderCatalogEntry
    sources.push({ ...fileMeta, id: unique(entry?.id ?? slug(basename(file, extname(file)))), title: entry?.title ?? basename(file, extname(file)).replace(/[_-]+/g, " "), status: entry?.status ?? "unknown", kind: "file", path: join(folder, file) })
  }
  return sources
}

export const libraryId = (folder: string) => `lib-${hash(folder).slice(0, 10)}`
export async function untar(archive: string, into: string): Promise<void> { await mkdir(into, { recursive: true }); await run("tar", ["-xzf", archive, "-C", into], { timeout: 300_000 }) }
