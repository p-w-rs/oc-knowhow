// Which pinned source trees in references.json have newer upstream releases (maintainer tool):
//   pixi run versions            table of pins vs the newest upstream tag (commit pins: vs the default branch)
//   pixi run versions --json     the same as JSON (for agents and scheduled checks)
// Also reports the Jai compiler installed on this computer against the version the Jai skills were validated with.
// Uses `git ls-remote`, so it needs network access but no GitHub token.
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

/** The commit the default branch points to. */
async function headOf(repo, host = "github.com") {
  const { stdout } = await run("git", ["ls-remote", `https://${host}/${repo}`, "HEAD"], { timeout: 60_000 })
  return stdout.split(/\s/)[0] || undefined
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
    if (pin.kind === "branch") { rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref, status: "branch (follows upstream)" }); continue }
    if (pin.kind === "commit") {
      try {
        const head = await headOf(pin.repo, pin.host)
        const same = !!head && (head.startsWith(pin.ref) || pin.ref.startsWith(head))
        rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref.slice(0, 12), newest: head?.slice(0, 12), status: same ? "current" : head ? "COMMITS" : "commit (check the changelog)" })
      } catch (error) { rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref.slice(0, 12), status: `error: ${String(error.message ?? error).split("\n")[0]}` }) }
      continue
    }
    try {
      if (!cache.has(pin.repo)) cache.set(pin.repo, await tagsOf(pin.repo, pin.host))
      const newest = newestLike(pin.ref, cache.get(pin.repo))
      rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref, newest: newest ?? pin.ref, status: newest && compareVersions(newest, pin.ref) > 0 ? "UPDATE" : "current" })
    } catch (error) { rows.push({ id: reference.id, repo: pin.repo, pinned: pin.ref, status: `error: ${String(error.message ?? error).split("\n")[0]}` }) }
  }
  return rows
}

/** The installed Jai compiler against the validated one, and the CHANGELOG versions in between (to review). */
export async function checkJai() {
  const { compareJai, detectJai, VALIDATED_JAI } = await import("../plugin/jai.ts")
  const found = await detectJai()
  if (!found) return { validated: VALIDATED_JAI, status: "not installed (~/jai/current)" }
  const order = compareJai(found.version, VALIDATED_JAI)
  let newer = []
  if (order > 0) {
    const text = await readFile(`${found.path}/CHANGELOG.txt`, "utf8")
    newer = [...text.matchAll(/^Version:\s*(beta [\d.]+)[^\n]*/gm)].map(m => m[1]).filter(version => compareJai(version, VALIDATED_JAI) > 0)
  }
  return { validated: VALIDATED_JAI, installed: found.version, path: found.path, status: order > 0 ? "NEWER" : order < 0 ? "older" : "current", ...(newer.length && { review: newer }) }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { sources } = JSON.parse(await readFile(new URL("../references.json", import.meta.url), "utf8"))
  const rows = await checkVersions(sources)
  const jai = await checkJai().catch(error => ({ status: `error: ${error.message}` }))
  if (process.argv.includes("--json")) console.log(JSON.stringify({ references: rows, jai }, null, 2))
  else {
    for (const row of rows) console.log(`${(row.status === "UPDATE" || row.status === "COMMITS" ? row.status : "").padEnd(8)}${row.id.padEnd(26)} ${String(row.pinned).padEnd(28)} ${row.newest && row.newest !== row.pinned ? `→ ${row.newest}` : row.status === "UPDATE" || row.status === "current" ? "" : row.status}`)
    const updates = rows.filter(row => row.status === "UPDATE").length, commits = rows.filter(row => row.status === "COMMITS").length
    console.log(`\n${updates} of ${rows.length} pinned sources have a newer release${commits ? `; ${commits} commit pins are behind their default branch` : ""}.${updates || commits ? " Revalidate the skill that cites each one, then bump the pin in references.json." : ""}`)
    console.log(`Jai: validated with ${jai.validated ?? "?"}; installed ${jai.installed ?? "-"} (${jai.status})${jai.review ? `. Review the CHANGELOG entries ${jai.review.join(", ")}, re-run pixi run jai-examples on macOS and Linux, then update VALIDATED_JAI in plugin/jai.ts and the skills.` : ""}`)
  }
}
