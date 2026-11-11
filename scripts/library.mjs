// The reference library from a terminal (the Settings page does the same):
//   pixi run library status                     what is indexed
//   pixi run library add <folder> [name]        add a private folder and index it
//   pixi run library remove <folder>
//   pixi run library download                   download the free references and index them
//   pixi run library sync                       re-index (new or changed files only)
//   pixi run library search "<query>" [--keyword]
import { join, resolve } from "node:path"
import { Backend } from "../plugin/backend.ts"
import { folderSources, Library, libraryId } from "../plugin/library.ts"
import { downloadReferences, loadReferences, referenceSources, referenceStates, REFERENCES_LIBRARY } from "../plugin/references.ts"
import { dataDirectory, SettingsStore } from "../plugin/settings.ts"

const [command = "status", ...args] = process.argv.slice(2)
const data = dataDirectory(process.env.OC_KNOWHOW_DATA_DIR || undefined)
const settings = await SettingsStore.open(data)
const backend = new Backend(join(data, "search"))
const enhance = new Backend(join(process.env.XDG_DATA_HOME || join(process.env.HOME, ".local", "share"), "oc-enhance", "search"))
const runtime = async () => (await backend.runtime()) ?? (await enhance.runtime().then(r => r && { ...r, home: join(backend.directory, "home") }))
const library = new Library(data, runtime)
const references = await loadReferences()
const downloads = join(data, "references")
const specs = async () => [
  { id: REFERENCES_LIBRARY, name: "Free references", sources: await referenceSources(downloads, references) },
  ...await Promise.all(settings.current().folders.map(async folder => ({ id: libraryId(folder.path), name: folder.name, sources: await folderSources(folder.path) }))),
]
const sync = async () => {
  const timer = setInterval(() => { if (library.progress) process.stdout.write(`\r  ${library.progress.step.slice(0, 90).padEnd(90)} ${library.progress.done}/${library.progress.total}`) }, 1000)
  try { const report = await library.sync(await specs()); process.stdout.write("\n"); console.log(report); for (const failure of report.failed) console.log(`  unreadable: ${failure.source}: ${failure.error}`) }
  finally { clearInterval(timer) }
}

if (command === "add") {
  const folder = resolve(args[0] ?? "")
  await settings.update({ folders: [...settings.current().folders.filter(item => item.path !== folder), { path: folder, ...(args[1] && { name: args[1] }) }] })
  await sync()
} else if (command === "remove") {
  await settings.update({ folders: settings.current().folders.filter(item => item.path !== resolve(args[0] ?? "")) })
  await sync()
} else if (command === "download") {
  const errors = await downloadReferences(downloads, references, { onProgress: (step, done, total) => process.stdout.write(`\r  ${step.slice(0, 90).padEnd(90)} ${done + 1}/${total}`) })
  process.stdout.write("\n")
  for (const [id, error] of Object.entries(errors)) console.log(`  could not download ${id}: ${error}`)
  await sync()
} else if (command === "sync") await sync()
else if (command === "search") {
  const result = await library.search(args.filter(arg => !arg.startsWith("--")).join(" "), { mode: args.includes("--keyword") ? "keyword" : "auto", limit: 8 })
  console.log(`${result.mode}${result.note ? ` (${result.note})` : ""}`)
  for (const hit of result.hits) console.log(`- ${hit.title} — ${hit.where} [${hit.status}${hit.note ? `; ${hit.note.slice(0, 80)}` : ""}]\n    ${hit.excerpt.replace(/\s+/g, " ").slice(0, 220)}`)
} else {
  const stored = await library.stored()
  console.log(`Data: ${data}\nFolders: ${settings.current().folders.map(f => f.path).join(", ") || "(none)"}`)
  const states = await referenceStates(downloads, references)
  console.log(`Free references: ${states.filter(s => s.state === "downloaded").length} downloaded, ${states.filter(s => s.state === "missing").length} missing, ${states.filter(s => s.state === "link").length} online only`)
  console.log(`Indexed: ${stored.length} sources, ${stored.reduce((n, s) => n + s.units.length, 0)} sections; meaning-based search: ${(await runtime()) ? "yes" : "no"}`)
  for (const item of stored.filter(s => s.error)) console.log(`  unreadable: ${item.meta.id}: ${item.error}`)
}
process.exit(0)
