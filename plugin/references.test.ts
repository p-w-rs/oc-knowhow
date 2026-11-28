// Free references on disk: updates to new pinned versions, retries after failures, one download at a time.
import { after, before, test } from "node:test"
import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { createServer, type Server } from "node:http"
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { promisify } from "node:util"
import { downloadReferences, downloadRunning, lockDownloads, readDownloadErrors, referenceStates, refreshReferences, type Reference } from "./references.js"

const run = promisify(execFile)
const dirs: string[] = []
const scratch = async () => { const dir = await mkdtemp(join(tmpdir(), "ockh-refs-")); dirs.push(dir); return dir }
let server: Server, base = ""
const archives = new Map<string, Buffer>()
let requests: string[] = []

/** A source archive like GitHub's: one top folder holding the files. */
async function archive(files: Record<string, string>): Promise<Buffer> {
  const dir = await scratch()
  for (const [path, text] of Object.entries(files)) {
    await mkdir(join(dir, "repo-1.0", path, ".."), { recursive: true })
    await writeFile(join(dir, "repo-1.0", path), text)
  }
  await run("tar", ["-czf", join(dir, "out.tar.gz"), "-C", dir, "repo-1.0"])
  return readFile(join(dir, "out.tar.gz"))
}

before(async () => {
  archives.set("/v1.tar.gz", await archive({ "README.md": "# Version one\n", "src/a.c": "int one(void) { return 1; }\n", "extra/skip.c": "int skip;\n" }))
  archives.set("/v2.tar.gz", await archive({ "README.md": "# Version two\n", "src/a.c": "int two(void) { return 2; }\n", "src/b.c": "int b;\n" }))
  server = createServer((req, res) => {
    requests.push(req.url ?? "")
    const body = archives.get(req.url ?? "")
    if (body) { res.writeHead(200, { "content-type": "application/gzip" }); res.end(body); return }
    if (req.url === "/doc.html") { res.writeHead(200, { "content-type": "text/html" }); res.end("<h1>Doc</h1>"); return }
    res.writeHead(404); res.end()
  })
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve))
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`
  page = { id: "doc", title: "Doc", kind: "html", url: `${base}/doc.html`, status: "current" }
  broken = { id: "broken", title: "Broken", kind: "pdf", url: `${base}/missing.pdf`, status: "current" }
})
after(async () => { server.close(); await Promise.all(dirs.map(dir => rm(dir, { recursive: true, force: true }))) })

const tree = (version: string, paths = ["README.md", "src"]): Reference => ({ id: "lib-source", title: "Lib source", kind: "source-tree", url: `${base}/${version}.tar.gz`, version, paths, status: "current" })
// Built once the server runs (it picks a free port).
let page: Reference, broken: Reference
/** Requests the server got since the last call. */
const served = () => { const list = requests; requests = []; return list }

test("a new pinned version replaces the downloaded tree in one step, without leftovers (also when every pin moved)", async () => {
  const dir = await scratch()
  assert.deepEqual(await downloadReferences(dir, [tree("v1")]), {})
  assert.equal(await readFile(join(dir, "lib-source", "README.md"), "utf8"), "# Version one\n")
  assert.deepEqual((await readdir(join(dir, "lib-source"))).sort(), [".oc-knowhow-version", "README.md", "src"], "only the listed paths are kept")
  // The pin moves: the tree counts as missing until the new version is in place.
  assert.equal((await referenceStates(dir, [tree("v2")]))[0]!.state, "missing")
  const result = await refreshReferences(dir, [tree("v2")])
  assert.deepEqual(result, { attempted: ["lib-source"], errors: {} })
  assert.equal(await readFile(join(dir, "lib-source", "README.md"), "utf8"), "# Version two\n")
  assert.deepEqual((await readdir(join(dir, "lib-source", "src"))).sort(), ["a.c", "b.c"])
  assert.equal((await referenceStates(dir, [tree("v2")]))[0]!.state, "downloaded")
  assert.deepEqual((await readdir(dir)).sort(), ["auto-download.json", "errors.json", "lib-source"], "no archives, staging or old trees left")
})

test("automatic updates: only for users who downloaded before; failures wait 1 h, 4 h, then a day; a new URL retries at once", async () => {
  const dir = await scratch()
  assert.deepEqual(await refreshReferences(dir, [page, broken]), { attempted: [], errors: {}, skipped: "not-opted-in" }, "never downloaded: nothing happens")
  await downloadReferences(dir, [page])
  const hour = 3600_000, start = Date.UTC(2026, 10, 28, 12)
  const first = await refreshReferences(dir, [page, broken], { now: start })
  assert.deepEqual(first.attempted, ["broken"])
  assert.match(first.errors.broken!, /failed/)
  assert.equal((await readDownloadErrors(dir)).broken, first.errors.broken)
  served()
  const check = async (at: number, due: boolean, label: string) => {
    const result = await refreshReferences(dir, [page, broken], { now: at })
    const hits = served()
    if (due) { assert.deepEqual(result.attempted, ["broken"], label); assert.ok(hits.length && hits.every(url => url === "/missing.pdf"), label) }
    else { assert.equal(result.skipped, "nothing-due", label); assert.deepEqual(hits, [], `${label}: nothing reached the server`) }
  }
  await check(start + 59 * 60_000, false, "waits an hour after the first failure")
  await check(start + hour, true, "retried after 1 h")
  await check(start + hour + 3 * hour, false, "then waits 4 h")
  await check(start + 5 * hour, true, "retried after 4 h")
  await check(start + 5 * hour + 23 * hour, false, "then a day")
  await check(start + 29 * hour, true, "retried after a day")
  await check(start + 29 * hour + 23 * hour, false, "and daily from then on")
  // The pin changes (a fixed URL): tried at once, and the error goes away when it works.
  const fixed = { ...broken, kind: "html" as const, url: `${base}/doc.html` }
  assert.deepEqual(await refreshReferences(dir, [page, fixed], { now: start + 29 * hour + 1 }), { attempted: ["broken"], errors: {} })
  assert.deepEqual(await readDownloadErrors(dir), {})
  assert.deepEqual(JSON.parse(await readFile(join(dir, "auto-download.json"), "utf8")), {})
})

test("one download at a time across processes: a live lock skips, a dead one is taken over", async () => {
  const dir = await scratch()
  await downloadReferences(dir, [page])
  const lock = await lockDownloads(dir)
  assert.ok(lock)
  assert.equal(await lockDownloads(dir), undefined, "held: a second taker gets nothing")
  assert.equal(await downloadRunning(dir), true)
  assert.equal((await refreshReferences(dir, [page, tree("v1")])).skipped, "locked")
  await lock!.release()
  assert.equal(await downloadRunning(dir), false)
  // A lock left by a process that no longer exists (a crash) does not block downloads.
  await writeFile(join(dir, ".download.lock"), JSON.stringify({ pid: 999_999_999, token: "gone", at: new Date().toISOString() }))
  assert.equal(await downloadRunning(dir), false)
  assert.deepEqual((await refreshReferences(dir, [page, tree("v1")])).attempted, ["lib-source"])
  assert.ok(!(await readdir(dir)).includes(".download.lock"), "released after the download")
  // A waiting taker gets the lock once it is released.
  const held = await lockDownloads(dir)
  const waiting = lockDownloads(dir, { wait: true })
  setTimeout(() => void held!.release(), 300)
  const next = await waiting
  assert.ok(next)
  await next!.release()
})

test("download problems stay listed until that reference works or is no longer wanted", async () => {
  const dir = await scratch()
  const errors = await downloadReferences(dir, [page, broken])
  assert.deepEqual(Object.keys(errors), ["broken"])
  // Downloading something else keeps the earlier problem.
  await downloadReferences(dir, [page, broken, tree("v1")], { only: ["lib-source"] })
  assert.deepEqual(Object.keys(await readDownloadErrors(dir)), ["broken"])
  // Removed from the list: the problem goes too.
  await downloadReferences(dir, [page, tree("v1")])
  assert.deepEqual(await readDownloadErrors(dir), {})
})
