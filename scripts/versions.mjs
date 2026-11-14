// Which pinned source trees in references.json have newer upstream releases (maintainer tool):
//   pixi run versions            table of pins vs the newest upstream tag
//   pixi run versions --json     the same as JSON (for agents and scheduled checks)
// Uses `git ls-remote --tags`, so it needs network access but no GitHub token.
import { execFile } from "node:child_process"
import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"

const run = promisify(execFile)

/** owner/repo and the pinned ref (tag, branch or commit) of a codeload tarball URL. */
export function parsePin(url) {
  const gitlab = /^https:\/\/gitlab\.com\/([^/]+\/[^/]+)\/-\/archive\/([^/]+)\//.exec(url)
  if (gitlab) return { repo: gitlab[1], host: "gitlab.com", kind: "tag", ref: gitlab[2] }
  const m = /^https:\/\/codeload\.github\.com\/([^/]+\/[^/]+)\/tar\.gz\/(?:refs\/(tags|heads)\/)?(.+)$/.exec(url)
  if (!m) return undefined
  return { repo: m[1], host: "github.com", kind: m[2] === "tags" ? "tag" : m[2] === "heads" ? "branch" : "commit", ref: m[3] }
}

/** Version-like parts of a tag, for ordering: "release-3.4.20" → [3, 4, 20], "dev-2026-11a" → [2026, 11, 1]. */
export function versionKey(tag) {
  const core = tag.replace(/^.*?(?=\d)/, "")
  const numbers = (core.match(/\d+/g) ?? []).map(Number)
  const suffix = /\d([a-z])$/.exec(core)?.[1]
  return suffix ? [...numbers, suffix.charCodeAt(0) - 96] : numbers
}

export function compareVersions(a, b) {
  const x = versionKey(a), y = versionKey(b)
  for (let i = 0; i < Math.max(x.length, y.length); i++) { const d = (x[i] ?? -1) - (y[i] ?? -1); if (d) return d }
  return 0
}

const PRERELEASE = /(alpha|beta|rc|pre|preview|nightly|snapshot|test|\+|-g[0-9a-f]{7})/i

/** The newest release tag of a repo that looks like the pinned tag (same prefix, e.g. "release-", "v", "dev-"). */
/** A tag's shape: version numbers collapsed ("v25.12.19" → "vV", "dev-2026-11a" → "dev-V-V", "4.3a2" → "VaV"). */
export const shapeOf = tag => tag.replace(/(\d)[a-z]$/, "$1").replace(/\d+(\.\d+)*/g, "V")

export function newestLike(pinned, tags) {
  const shape = shapeOf(pinned)
  // Same shape only: skips dated builds ("v25.12.19-2026-02-06-03fffb2"), ".dev", "-kernel" and "4.3a2"-style tags.
  const candidates = tags.filter(tag => !PRERELEASE.test(tag) && /\d/.test(tag) && shapeOf(tag) === shape)
  return candidates.sort(compareVersions).at(-1)
}

async function tagsOf(repo, host = "github.com") {
  const { stdout } = await run("git", ["ls-remote", "--tags", "--refs", `https://${host}/${repo}`], { timeout: 60_000, maxBuffer: 64 * 1024 * 1024 })
  return stdout.split("\n").map(line => line.split("refs/tags/")[1]).filter(Boolean)
}

export async function checkVersions(references) {
  const rows = []
  const cache = new Map()
  for (const reference of references.filter(item => item.kind === "source-tree")) {
    const pin = parsePin(reference.url)
    if (!pin) { rows.push({ id: reference.id, status: "unknown-url", pinned: reference.url }); continue }
    if (pin.kind !== "tag") { rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref, status: pin.kind === "branch" ? "branch (follows upstream)" : "commit (check the changelog)" }); continue }
    try {
      if (!cache.has(pin.repo)) cache.set(pin.repo, await tagsOf(pin.repo, pin.host))
      const newest = newestLike(pin.ref, cache.get(pin.repo))
      rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref, newest: newest ?? pin.ref, status: newest && compareVersions(newest, pin.ref) > 0 ? "UPDATE" : "current" })
    } catch (error) { rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref, status: `error: ${String(error.message ?? error).split("\n")[0]}` }) }
  }
  return rows
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { sources } = JSON.parse(await readFile(new URL("../references.json", import.meta.url), "utf8"))
  const rows = await checkVersions(sources)
  if (process.argv.includes("--json")) console.log(JSON.stringify(rows, null, 2))
  else {
    for (const row of rows) console.log(`${row.status === "UPDATE" ? "UPDATE " : "       "}${row.id.padEnd(26)} ${String(row.pinned).padEnd(28)} ${row.newest && row.newest !== row.pinned ? `→ ${row.newest}` : row.status === "UPDATE" || row.status === "current" ? "" : row.status}`)
    const updates = rows.filter(row => row.status === "UPDATE").length
    console.log(`\n${updates} of ${rows.length} pinned sources have a newer release.${updates ? " Revalidate the skill that cites each one, then bump the pin in references.json." : ""}`)
  }
}
