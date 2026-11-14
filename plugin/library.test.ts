import { after, test } from "node:test"
import assert from "node:assert/strict"
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Backend } from "./backend.js"
import { chunk, cleanPages, codeUnits, excerpt, folderSources, gnuplotDocUnits, htmlToText, Library, markdownUnits, pdfUnits, sourceTreeUnits } from "./library.js"
import { pdf } from "./testdocs.js"

const dirs: string[] = []
after(async () => { await Promise.all(dirs.map(dir => rm(dir, { recursive: true, force: true }))) })
const scratch = async () => { const dir = await mkdtemp(join(tmpdir(), "ockh-lib-")); dirs.push(dir); return dir }

test("running headers, footers and page numbers are removed; hyphenation is joined", () => {
  const pages = Array.from({ length: 6 }, (_, i) => `Journal of Things 2024\nSection ${String.fromCharCode(65 + i)} starts here.\nBody text about regres-\nsion models, case ${i * 7}.\nMore discussion of item ${i}.\nClosing remark ${i * 3}.\n${i + 1}`)
  const cleaned = cleanPages(pages)
  assert.doesNotMatch(cleaned[2]!, /Journal of Things/)
  assert.doesNotMatch(cleaned[2]!, /\n3$/)
  assert.match(cleaned[2]!, /regression models/)
})

test("PDF sections follow the bookmarks with page ranges; without bookmarks pages are grouped", () => {
  const sections = Array.from({ length: 6 }, (_, i) => ({ label: `page ${i + 1}`, text: `Text of page ${i + 1}. `.repeat(10) }))
  const outline = [{ title: "1 Introduction", level: 1, page: 1 }, { title: "2 Methods", level: 1, page: 3 }, { title: "2.1 Tests", level: 2, page: 4 }, { title: "3 Results", level: 1, page: 6 }]
  const units = pdfUnits({ summary: "", sections, outline })
  assert.deepEqual(units.map(u => [u.heading.join(" > "), u.pages]), [["1 Introduction", [1, 2]], ["2 Methods", [3, 3]], ["2 Methods > 2.1 Tests", [4, 5]], ["3 Results", [6, 6]]])
  assert.equal(pdfUnits({ summary: "", sections }).length, 1)
})

test("HTML becomes headed text without navigation and scripts; Markdown splits at headings", () => {
  const text = htmlToText("<html><nav>Home | About</nav><script>x()</script><h1>Title</h1><p>Alpha &amp; beta.</p><h2>Part</h2><pre>code\n  here</pre></html>")
  assert.doesNotMatch(text, /Home|x\(\)/)
  assert.match(text, /# Title\n\nAlpha & beta\./)
  const units = markdownUnits(`# A\n\n${"word ".repeat(20)}\n\n## B\n\n${"more ".repeat(20)}\n\`\`\`\n# not a heading\n\`\`\``)
  assert.deepEqual(units.map(u => u.heading), [["A"], ["A", "B"]])
  assert.equal(chunk("x".repeat(20000)).length, 4)
  assert.match(excerpt(`${"a ".repeat(2000)} needle here ${"b ".repeat(2000)}`, "needle"), /needle/)
})

test("gnuplot's documentation source becomes one section per topic with help keywords", () => {
  const doc = "C comment\n1 Gnuplot\n?gnuplot\n^<html>\n Intro text that is long enough to keep as a section here.\n2 parallelaxes\n?parallelaxes\n Parallel axis plots show many columns, one vertical axis per column of data.\n"
  const units = gnuplotDocUnits(doc)
  assert.deepEqual(units.map(u => u.heading), [["gnuplot manual", "Gnuplot"], ["gnuplot manual", "Gnuplot", "parallelaxes"]])
  assert.match(units[1]!.text, /^help keywords: parallelaxes/)
  assert.doesNotMatch(units[0]!.text, /<html>|comment/)
})

async function libraryFolder() {
  const folder = await scratch()
  await mkdir(join(folder, "papers"))
  await writeFile(join(folder, "papers", "welch.md"), `# Comparing two groups\n\n${"Welch's t-test does not assume equal variances and is the default for two independent groups. ".repeat(3)}\n\n# Paired designs\n\n${"Analyze the differences of paired observations, e.g. the same seeds for both models. ".repeat(3)}`)
  await writeFile(join(folder, "old-book.pdf"), pdf(["Stepwise regression selects variables by p-values. This is a classic procedure described in old textbooks."]))
  await writeFile(join(folder, "notes.txt"), "ignored? no, text files are indexed. Bootstrap confidence intervals resample the data many times to estimate uncertainty.")
  await writeFile(join(folder, "image.png"), new Uint8Array([1, 2, 3]))
  await writeFile(join(folder, "catalog.json"), JSON.stringify({ sources: [
    { file: "old-book.pdf", id: "old-stats", title: "Old Statistics Book", year: 1998, status: "dated", note: "stepwise selection is outdated", fields: ["statistics"] },
    { file: "papers/welch.md", title: "Welch notes", status: "current", fields: ["statistics"] },
  ] }))
  return folder
}

test("a folder becomes sources described by its catalog; search cites, flags dated sources, and reads by ref", async () => {
  const folder = await libraryFolder()
  const sources = await folderSources(folder)
  assert.deepEqual(sources.map(s => [s.id, s.title, s.status]), [["notes", "notes", "unknown"], ["old-stats", "Old Statistics Book", "dated"], ["welch", "Welch notes", "current"]])
  const library = new Library(await scratch(), async () => undefined)
  const report = await library.sync([{ id: "mine", name: "Mine", sources }])
  assert.deepEqual([report.added, report.failed.length], [3, 0])

  const welch = await library.search("unequal variances two independent groups", { mode: "keyword" })
  assert.equal(welch.hits[0]!.title, "Welch notes")
  assert.equal(welch.hits[0]!.where, "Comparing two groups")
  const old = await library.search("stepwise regression", { mode: "keyword" })
  assert.equal(old.hits[0]!.status, "dated")
  assert.match(old.hits[0]!.note!, /stepwise selection is outdated/)
  assert.match(old.hits[0]!.where, /p\. 1/)
  assert.equal((await library.search("stepwise", { mode: "keyword", fields: ["biology"] })).hits.length, 0)

  const section = await library.read(welch.hits[0]!.ref, { neighbors: 1 })
  assert.match(section!.text, /Paired designs/)
  assert.equal((await library.outline("welch")).length, 2)

  // Unchanged files are not re-read; removed ones leave the index.
  assert.equal((await library.sync([{ id: "mine", name: "Mine", sources }])).unchanged, 3)
  assert.equal((await library.sync([{ id: "mine", name: "Mine", sources: sources.slice(1) }])).removed, 1)
  assert.equal((await library.search("bootstrap resample", { mode: "keyword" })).hits.length, 0)
})

test("a sync by another process (CLI, other window) is seen by a running library without a restart", async () => {
  const folder = await libraryFolder()
  const sources = await folderSources(folder)
  const data = await scratch()
  const running = new Library(data, async () => undefined)
  await running.sync([{ id: "mine", name: "Mine", sources: sources.slice(1) }])
  assert.equal((await running.search("bootstrap resample", { mode: "keyword" })).hits.length, 0)
  await new Promise(r => setTimeout(r, 20))
  await new Library(data, async () => undefined).sync([{ id: "mine", name: "Mine", sources }])
  const hits = (await running.search("bootstrap resample", { mode: "keyword" })).hits
  assert.equal(hits[0]?.source, "notes")
  assert.equal((await running.stored()).length, 3)
})

test("meaning-based search with the real engine (when downloaded via pixi run setup-search)", async t => {
  const runtime = await new Backend(join(import.meta.dirname, "..", ".local", "search")).runtime()
  if (!runtime) return t.skip("search engine not downloaded (pixi run setup-search)")
  const library = new Library(await scratch(), async () => runtime)
  await library.sync([{ id: "mine", name: "Mine", sources: await folderSources(await libraryFolder()) }])
  const result = await library.search("how should I compare two models trained with the same random seeds")
  assert.notEqual(result.mode, "keyword")
  assert.equal(result.hits[0]!.title, "Welch notes")
})

test("source code splits into declarations with their comments (Odin and C)", () => {
  const odin = `package mem

import "base:runtime"

// Arena is a linear allocator.
// Free individual allocations is not possible.
Arena :: struct {
\tdata:   []byte,
\toffset: int,
}

@(require_results)
arena_init :: proc(a: ^Arena, data: []byte) {
\ta.data = data
\tif true { a.offset = 0 }
}

DEFAULT_ALIGNMENT :: 2*align_of(rawptr)
`
  const units = codeUnits("core/mem/allocators.odin", odin, 160)
  const all = units.map(u => u.text).join("\n")
  assert.match(units[0]!.heading[0]!, /core\/mem\/allocators\.odin/)
  const arena = units.find(u => /Arena \(line/.test(u.heading[1]!) || /^Arena/.test(u.heading[1]!))!
  assert.ok(arena, JSON.stringify(units.map(u => u.heading)))
  assert.match(arena.text, /linear allocator/)
  assert.match(all, /arena_init :: proc/)
  assert.ok(units.some(u => /arena_init/.test(u.heading[1]!)))
  assert.ok(units.some(u => /DEFAULT_ALIGNMENT/.test(u.heading[1]!)))

  const c = `#include <stdint.h>
/* Creates a host. */
ENetHost * enet_host_create (const ENetAddress * address, size_t peerCount)
{
    if (peerCount > 4095) return NULL;
    for (int i = 0; i < 2; i++) { }
    return host;
}

typedef struct _ENetPeer {
    int state;
} ENetPeer;

#define ENET_VERSION 0x10305
static int counter = 0;
`
  const cu = codeUnits("enet.h", c, 100)
  const names = cu.map(u => u.heading[1]).join(" | ")
  assert.match(names, /enet_host_create/)
  assert.match(names, /_ENetPeer/)
  assert.match(names, /ENET_VERSION/)
  assert.match(cu.find(u => /enet_host_create/.test(u.heading[1]!))!.text, /Creates a host/)
  assert.doesNotMatch(names, /\bif\b|\bfor\b/)
})

test("a source tree keeps only the listed paths and indexes code and READMEs", async () => {
  const root = await scratch()
  await mkdir(join(root, "core", "mem"), { recursive: true })
  await mkdir(join(root, "tests"), { recursive: true })
  await writeFile(join(root, "README.md"), "# Odin\n\nA language for high performance, built for the joy of programming and data-oriented design.\n")
  await writeFile(join(root, "core", "mem", "a.odin"), "package mem\n\n// Pool allocator.\nPool :: struct { x: int }\n")
  await writeFile(join(root, "core", "mem", "image.png"), "x")
  await writeFile(join(root, "tests", "t.odin"), "package t\nnot_wanted :: proc() {}\n")
  const units = await sourceTreeUnits(root, { paths: ["core", "README.md"] })
  const text = units.map(u => `${u.heading.join(" > ")}\n${u.text}`).join("\n")
  assert.match(text, /core\/mem\/a\.odin/)
  assert.match(text, /Pool allocator/)
  assert.match(text, /README\.md/)
  assert.doesNotMatch(text, /not_wanted|image\.png/)
  const lib = new Library(await scratch(), async () => undefined)
  await lib.sync([{ id: "references", name: "Free", sources: [{ id: "odin-src", title: "Odin source", kind: "source-tree", path: root, version: "dev-2026-11", paths: ["core"] }] }])
  const hit = (await lib.search("pool allocator", { mode: "keyword" })).hits[0]!
  assert.equal(hit.source, "odin-src")
  assert.match(hit.where, /core\/mem\/a\.odin/)
  assert.equal((await lib.stored())[0]!.meta.edition, "dev-2026-11")
})

test("source trees skip unit tests unless the reference keeps a test folder on purpose", async () => {
  const root = await scratch()
  await mkdir(join(root, "pkg", "tests"), { recursive: true })
  await mkdir(join(root, "keep", "tests"), { recursive: true })
  await writeFile(join(root, "pkg", "api.py"), "def put_model(m):\n    \"\"\"Copies a model to the GPU.\"\"\"\n    return m\n")
  await writeFile(join(root, "pkg", "api_test.py"), "def test_put_model():\n    put_model(1)\n")
  await writeFile(join(root, "pkg", "tests", "t.py"), "def helper_in_tests():\n    pass\n")
  await writeFile(join(root, "keep", "tests", "keywords.py"), "def wanted_keyword():\n    pass\n")
  const text = (await sourceTreeUnits(root, { paths: ["pkg", "keep/tests"] })).map(u => u.text).join("\n")
  assert.match(text, /Copies a model/)
  assert.match(text, /wanted_keyword/)
  assert.doesNotMatch(text, /test_put_model|helper_in_tests/)
})
