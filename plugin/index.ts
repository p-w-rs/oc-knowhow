import type { Plugin } from "@opencode/plugin"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { isAbsolute, join } from "node:path"
import { fileURLToPath } from "node:url"
import { Backend, type Runtime } from "./backend.js"
import { compareJai, detectJai, detectJails, JAI_LIBRARY, jaiSkillNote, jaiSources, VALIDATED_JAI } from "./jai.js"
import { folderSources, Library, libraryId, type LibrarySpec, type SyncReport } from "./library.js"
import { downloadReferences, downloadRunning, loadReferences, lockDownloads, readDownloadErrors, referenceSources, referenceStates, REFERENCES_LIBRARY, refreshReferences } from "./references.js"
import { KnowhowRpc, type StateView } from "./rpc.js"
import { dataDirectory, DEFAULTS, GROUPS, PLUGIN_ID, SettingsStore, VERSION, type Group } from "./settings.js"

export { PLUGIN_ID, VERSION }

export interface KnowhowOptions {
  /** Absolute path; default `$XDG_DATA_HOME/oc-knowhow`. */
  readonly dataDirectory?: string
  /** Absolute path of a references.json to use instead of the bundled one (tests). */
  readonly referencesFile?: string
  /** Absolute path of the Jai compiler folder when it is not at ~/jai/current (the setting takes precedence). */
  readonly jaiRoot?: string
  /** Milliseconds after loading before the first background update (default 5000; tests use less). */
  readonly startupDelayMs?: number
}

export function parseOptions(raw: unknown): KnowhowOptions {
  const options = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>
  const keys = ["dataDirectory", "referencesFile", "jaiRoot"]
  for (const key of keys) if (options[key] !== undefined && (typeof options[key] !== "string" || !isAbsolute(options[key] as string))) throw new Error(`${PLUGIN_ID}: ${key} must be an absolute path`)
  const delay = options.startupDelayMs
  if (delay !== undefined && (typeof delay !== "number" || !Number.isFinite(delay) || delay < 0)) throw new Error(`${PLUGIN_ID}: startupDelayMs must be a number of milliseconds`)
  return { ...Object.fromEntries(keys.filter(key => options[key] !== undefined).map(key => [key, options[key]])), ...(delay !== undefined && { startupDelayMs: delay }) } as KnowhowOptions
}

const SKILLS = fileURLToPath(new URL("../skill/", import.meta.url))
const EXAMPLES = fileURLToPath(new URL("../examples/", import.meta.url))
const JAI_RUNNER = fileURLToPath(new URL("../scripts/jai-examples.mjs", import.meta.url))
const JAILS_QUERY = fileURLToPath(new URL("../scripts/jails-query.mjs", import.meta.url))

/** When this process last synced each data folder, and with which libraries (plugin instances share one library). */
const syncedAt: Map<string, { key: string; at: number }> = ((globalThis as Record<symbol, unknown>)[Symbol.for("oc-knowhow.synced")] ??= new Map()) as Map<string, { key: string; at: number }>
const specsKey = (specs: readonly LibrarySpec[]) => JSON.stringify(specs.map(spec => [spec.id, spec.sources.map(source => [source.id, source.path ?? source.url ?? "", source.version ?? "", source.status ?? ""])]))
/** Pointer for the agent: verified sources beat memory for anything quoted or cited. */
export const LIBRARY_HINT = "Reference library (oc-knowhow): before you quote, cite, or state exact wording, numbers, assumptions or syntax from a standard, paper, manual or textbook, check it with library_search (then library_read) and cite the section it returns. Prefer that over memory or web search; say so when the library has nothing."
const warn = (message: string, error?: unknown) => console.warn(`[${PLUGIN_ID}] ${message}${error ? `: ${error instanceof Error ? error.message : String(error)}` : ""}`)
const record = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value)
const blocked = (error: unknown) => record(error) && (error.name === "Permission.BlockedError" || (record(error.error) && error.error._tag === "Permission.BlockedError"))

/** The search engine: our own download, or oc-enhance's if it is already on this computer (same pinned versions). */
async function sharedRuntime(own: Backend): Promise<Runtime | undefined> {
  const runtime = await own.runtime()
  if (runtime) return runtime
  const enhance = new Backend(join(process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "oc-enhance", "search"))
  const other = await enhance.runtime()
  return other ? { ...other, home: own.directory + "/home" } : undefined
}

export function createPlugin(): Plugin.Plugin {
  return ({
    id: PLUGIN_ID,
    async setup(ctx) {
      const registrations: { dispose(): Promise<void> | void }[] = []
      const stopped = new AbortController()
      const cleanup = async () => { stopped.abort(); await Promise.allSettled(registrations.splice(0).reverse().map(async item => item.dispose())) }
      let options: KnowhowOptions, data: string, settings: SettingsStore
      try {
        options = parseOptions(ctx.options)
        data = dataDirectory(options.dataDirectory)
        settings = await SettingsStore.open(data)
      } catch (error) {
        warn("disabled", error)
        return cleanup
      }
      // Each part below fails on its own: a broken library never hides the skills, and the other way round.
      const problems = new ProblemLog(data)
      let jai = await detectJai(settings.current().jaiRoot ?? options.jaiRoot).catch(() => undefined)
      let jails = await detectJails().catch(() => undefined)

      // ---- Skills ----
      let skillReady = false
      try {
        // Each skill loads on its own: one missing or unreadable file must not hide the others.
        const skills = (await Promise.all((Object.entries(GROUPS) as [Group, readonly string[]][]).flatMap(([group, ids]) => ids.map(async id => {
          const path = join(SKILLS, id, "SKILL.md")
          const examples = id === "gnuplot" ? "gnuplot" : id === "diagrams" ? "diagrams" : undefined
          try {
            const content = (await readFile(path, "utf8")) + (examples ? `\n\n---\nOn this computer the examples are in: ${join(EXAMPLES, examples)}\n` : "")
            return [{ group, id, path, content, description: /^description:\s*(.+)$/m.exec(content)?.[1] ?? id }]
          } catch (error) { problems.report(`skill ${id} not registered`, error); return [] }
        })))).flat()
        registrations.push(await ctx.skill.transform(editor => {
          const current = settings.current()
          for (const skill of skills) {
            if (!current[skill.group]) continue
            // Jai skills carry a live note: the installed compiler and how it compares with the validated version.
            const content = skill.group === "jai" ? skill.content + jaiSkillNote(skill.id, jai, { examples: EXAMPLES, runner: JAI_RUNNER, libraryOn: current.library, jailsQuery: JAILS_QUERY, ...(jails && { jails }) }) : skill.content
            editor.add({ id: skill.id as never, name: skill.id as never, description: skill.description, path: skill.path as never, content })
          }
        }))
        skillReady = true
      } catch (error) { problems.report("skills not registered", error) }

      // ---- Reference library: tools, background updates ----
      let lib: LibraryPart | undefined
      let toolsReady = false
      const libraryStart = registrations.length
      try {
        const backend = new Backend(join(data, "search"))
        const runtime = () => sharedRuntime(backend)
        // One library per process and data folder: OpenCode loads this plugin once per project location.
        const library = Library.acquire(data, runtime)
        registrations.push({ dispose: () => library.release() })
        const references = await loadReferences(options.referencesFile)
        const downloads = join(data, "references")
        let referenceErrors = await readDownloadErrors(downloads)
        let lastSync: (SyncReport & { at: string }) | undefined
        let lastDownload: StateView["lastDownload"]
        let busy: Promise<unknown> | undefined

        const specs = async (): Promise<LibrarySpec[]> => [
          { id: REFERENCES_LIBRARY, name: "Free references", sources: await referenceSources(downloads, references) },
          ...(settings.current().jai && jai ? [{ id: JAI_LIBRARY, name: `Jai ${jai.version} (installed)`, sources: jaiSources(jai) }] : []),
          ...await Promise.all(settings.current().folders.map(async folder => ({ id: libraryId(folder.path), name: folder.name, sources: await folderSources(folder.path) }))),
        ]
        const sync = async () => {
          const wanted = await specs()
          const report = await library.sync(wanted)
          lastSync = { ...report, at: new Date().toISOString() }
          syncedAt.set(data, { key: specsKey(wanted), at: Date.now() })
          return report
        }
        // Background work runs one task at a time. A request made meanwhile waits its turn instead of being dropped (a
        // folder added during a long download is still indexed); repeated requests of one kind run once.
        const pending = new Map<string, () => Promise<unknown>>()
        const drain = () => {
          busy = (async () => {
            for (let next = pending.entries().next(); !next.done; next = pending.entries().next()) {
              const [kind, task] = next.value
              pending.delete(kind)
              if (stopped.signal.aborted) { pending.clear(); break }
              try { await task() } catch (error) { if (!stopped.signal.aborted) problems.report(`library ${kind} failed`, error) }
            }
          })().finally(() => { busy = undefined; if (pending.size && !stopped.signal.aborted) drain() })
        }
        const background = (kind: "update" | "sync" | "download", task: () => Promise<unknown>) => { pending.set(kind, task); if (!busy) drain() }

        const folderOf = (libraryKey: string) => settings.current().folders.find(folder => libraryId(folder.path) === libraryKey)
        /** Libraries whose sections are private files on this computer: searching them needs read permission on their folder. */
        const guardOf = (libraryKey: string): { name: string; path: string } | undefined =>
          libraryKey === JAI_LIBRARY ? (jai ? { name: "Jai", path: jai.path } : { name: "Jai", path: join(homedir(), "jai") }) : folderOf(libraryKey)
        const libraryName = (libraryKey: string) => libraryKey === REFERENCES_LIBRARY ? "free" : libraryKey === JAI_LIBRARY ? "Jai, local" : folderOf(libraryKey)?.name ?? libraryKey
        const assertRead = async (context: { sessionID: string; agent: string; messageID: string; id: string }, path: string) => ctx.permission.assert({
          sessionID: context.sessionID, agent: context.agent, action: "read", resources: [path], save: [path],
          source: { type: "tool", messageID: context.messageID, id: context.id },
        } as never)
        const text = (content: string, metadata: Record<string, unknown> = {}) => ({ content, metadata: { plugin: PLUGIN_ID, ...metadata } })

        // ---- Tools ----
        registrations.push(await ctx.tool.transform(editor => {
          if (!settings.current().library) return
          editor.add({
            name: "library_catalog",
            description: "List the reference library: free references (statistics, experiment design, datasets, ML evaluation, reporting standards, visualization, gnuplot, diagrams, Odin, C libraries, robotics), the Jai compiler's own lessons, module source and changelog when Jai is installed, and the user's own folders, each with what it is good for and its status (current, dated, superseded). Use it to pick sources, then library_search. Pass source=<id> for its table of contents.",
            input: { type: "object", properties: { source: { type: "string", maxLength: 200 }, field: { type: "string", maxLength: 60, description: "e.g. statistics, ml, datasets, causal, clinical, gnuplot, diagrams, odin, jai" } }, additionalProperties: false } as never,
            options: { codemode: false },
            execute: async (raw: unknown, context) => {
              const input = raw as { source?: string; field?: string }
              if (input.source) {
                const item = await library.find(input.source)
                const guard = item && guardOf(item.library)
                if (guard) await assertRead(context, guard.path)
                const outline = await library.outline(input.source)
                if (!outline.length) throw new Error(`No indexed source ${JSON.stringify(input.source)} (see library_catalog without arguments)`)
                return text(`Sections of ${input.source} (read with library_read ref=…):\n${outline.slice(0, 400).map(item => `- ${item.ref}  ${item.where}`).join("\n")}${outline.length > 400 ? `\n… ${outline.length - 400} more` : ""}`)
              }
              const stored = await library.stored()
              const field = input.field?.toLowerCase()
              const lines = stored.filter(item => !field || (item.meta.fields ?? []).some(value => value.toLowerCase() === field)).map(item => {
                const meta = item.meta
                const folder = libraryName(item.library)
                return `- ${meta.id} [${folder}; ${meta.status ?? "unknown"}${meta.supersededBy ? ` → ${meta.supersededBy}` : ""}${item.sections ? `; ${item.sections} sections` : item.kind === "link" ? "; online only" : ""}${item.error ? `; NOT READABLE: ${item.error.slice(0, 80)}` : ""}] ${meta.title}${meta.authors ? ` — ${meta.authors}` : ""}${meta.year ? ` (${meta.year})` : ""}${meta.useFor ? `\n    use for: ${meta.useFor}` : ""}${meta.note ? `\n    note: ${meta.note}` : ""}${item.kind === "link" && meta.url ? `\n    read online: ${meta.url}` : ""}`
              })
              const missing = (await referenceStates(downloads, references)).filter(state => state.state === "missing").length
              return text([
                `Reference library: ${field ? `${lines.length} of ${stored.length} sources in ${field}${lines.length ? "" : " (none; fields in use: " + [...new Set(stored.flatMap(item => item.meta.fields ?? []))].sort().join(", ") + ")"}` : `${stored.length} sources`}. Status: current = use as written; dated = sound in parts, check the note and the skills; superseded = see the newer source. Cite as <title>, <where>.`,
                ...(missing ? [`${missing} free references are not downloaded yet (the user can click Download in Settings → Know-how).`] : []),
                ...lines,
              ].join("\n"))
            },
          })
          editor.add({
            name: "library_search",
            description: "Search the reference library (books, papers, manuals, standards, pinned library and language source code, gnuplot demos; the installed Jai compiler's lessons, modules and changelog; the user's own folders and free references) for ground truth: methods, definitions, assumptions, recommended practice, worked examples, exact syntax and signatures. Returns passages with section/page citations and each source's status; dated sources are flagged. Then library_read for the full section.",
            input: {
              type: "object",
              properties: {
                query: { type: "string", minLength: 2, maxLength: 1000, description: "What you need, in plain words (e.g. 'paired comparison of classifiers across datasets', 'gnuplot parallel axes plot')" },
                sources: { type: "array", maxItems: 20, items: { type: "string" }, description: "Only these source ids (from library_catalog)" },
                field: { type: "string", maxLength: 60 },
                limit: { type: "integer", minimum: 1, maximum: 20 },
                mode: { enum: ["auto", "semantic", "keyword"] },
              },
              required: ["query"], additionalProperties: false,
            } as never,
            options: { codemode: false },
            execute: async (raw: unknown, context) => {
              const input = raw as { query: string; sources?: string[]; field?: string; limit?: number; mode?: "auto" | "semantic" | "keyword" }
              const result = await library.search(input.query, { ...(input.sources && { sources: input.sources }), ...(input.field && { fields: [input.field] }), ...(input.limit && { limit: input.limit }), ...(input.mode && { mode: input.mode }), signal: context.signal })
              let hidden = 0
              const hits = []
              for (const hit of result.hits) {
                const guard = guardOf(hit.ref.split("--")[0]!)
                if (guard) { try { await assertRead(context, guard.path) } catch (error) { if (blocked(error)) { hidden++; continue } throw error } }
                hits.push(hit)
              }
              const lines = [`${hits.length} result(s), ${result.mode} ranking${hidden ? `; ${hidden} hidden by read permissions` : ""}.${result.note ? ` ${result.note}` : ""}`]
              hits.forEach((hit, index) => lines.push(`\n${index + 1}. ${hit.title} — ${hit.where}  [ref ${hit.ref}; ${hit.status}]${hit.note ? `\n   NOTE: ${hit.note}` : ""}\n${hit.excerpt}`))
              if (!hits.length) lines.push("No matches. Try other words, library_catalog to pick a source, or the source's own documentation online.")
              return text(lines.join("\n"), { results: hits.length, mode: result.mode })
            },
          })
          editor.add({
            name: "library_read",
            description: "Read a library section by ref (from library_search or library_catalog source=…), optionally with neighbouring sections. Returns the text with its citation and links to the previous/next section.",
            input: { type: "object", properties: { ref: { type: "string", minLength: 3, maxLength: 300 }, neighbors: { type: "integer", minimum: 0, maximum: 3 } }, required: ["ref"], additionalProperties: false } as never,
            options: { codemode: false },
            execute: async (raw: unknown, context) => {
              const input = raw as { ref: string; neighbors?: number }
              // The ref may name a source by its id alone: find its library first, so private folders are always checked.
              const item = await library.find(input.ref.replace(/#\d+$/, ""))
              const guard = guardOf(item?.library ?? input.ref.split("--")[0]!)
              if (guard) await assertRead(context, guard.path)
              const section = await library.read(input.ref, { neighbors: input.neighbors ?? 0 })
              if (!section) throw new Error(`No section ${input.ref}. Use library_search or library_catalog source=<id>.`)
              const meta = section.meta
              return text(`# ${meta.title}${meta.authors ? ` — ${meta.authors}` : ""}${meta.year ? ` (${meta.year})` : ""}\nCite: ${meta.title}, ${section.where}. Status: ${meta.status ?? "unknown"}${meta.note ? ` — ${meta.note}` : ""}\n\n${section.text}\n\n${section.previous ? `previous: ${section.previous}  ` : ""}${section.next ? `next: ${section.next}` : ""}`)
            },
          })
        }))
        toolsReady = true

        registrations.push(await ctx.session.hook("context", async input => {
          if (!settings.current().library || (input.tools && !("library_search" in input.tools))) return
          input.system.push({ type: "text", text: LIBRARY_HINT } as never)
        }))

        const syncIfChanged = async (fresh: boolean) => {
          const last = syncedAt.get(data)
          // Every project location loads this plugin: the first one syncs, the others skip while nothing changed.
          if (!fresh && last && last.key === specsKey(await specs())) return
          await sync()
        }
        /** New references and new pinned versions, for users who downloaded references before (and kept updates on). */
        const refresh = async (): Promise<boolean> => {
          const current = settings.current()
          if (!current.library || !current.autoDownload) return false
          const result = await refreshReferences(downloads, references, { signal: stopped.signal, onProgress: (step, done, total) => { library.progress = { step, done, total } } })
          if (!result.attempted.length) return false
          referenceErrors = await readDownloadErrors(downloads)
          const failed = Object.keys(result.errors).length
          lastDownload = { at: new Date().toISOString(), downloaded: result.attempted.length - failed, failed }
          if (failed) problems.report(`could not download ${Object.entries(result.errors).map(([id, error]) => `${id} (${error})`).join(", ")}; retrying later`)
          return result.attempted.length > failed
        }
        // Downloads first, so the index is built once with the new files. Another window or the terminal may be
        // downloading right now: then this check waits for the next round instead of indexing half-done work.
        const update = async (startup: boolean) => {
          const downloaded = await refresh()
          if (await downloadRunning(downloads)) return
          // At startup, a check more than 10 minutes old also looks for files changed in place (the user's folders).
          const last = syncedAt.get(data)
          await syncIfChanged(downloaded || startup && (!last || Date.now() - last.at >= 10 * 60_000))
        }
        const startup = setTimeout(() => background("update", () => update(true)), options.startupDelayMs ?? 5000)
        startup.unref?.()
        const hourly = setInterval(() => background("update", () => update(false)), 3600_000)
        hourly.unref?.()
        registrations.push({ dispose: () => { clearTimeout(startup); clearInterval(hourly) } })

        lib = {
          state: async () => {
            const stored = await library.stored()
            const own = await backend.status()
            const shared = !own.installed && await runtime() ? "using the search engine downloaded by oc-enhance" : undefined
            return {
              references: await referenceStates(downloads, references, referenceErrors),
              sources: stored.map(item => ({ library: item.library === REFERENCES_LIBRARY ? "Free references" : item.library === JAI_LIBRARY ? `Jai ${jai?.version ?? ""} (installed)`.replace("  ", " ") : folderOf(item.library)?.name ?? item.library, id: item.meta.id, title: item.meta.title, status: item.meta.status ?? "unknown", sections: item.sections, ...(item.error && { error: item.error }) })),
              ...(library.progress && { progress: library.progress }), ...(lastSync && { lastSync }), ...(lastDownload && { lastDownload }),
              search: { ...own, installed: own.installed || !!shared, ...(shared && { shared }) },
            }
          },
          changed: () => background("sync", sync),
          downloadReferences: () => background("download", async () => {
            library.progress = { step: "Waiting for another download to finish", done: 0, total: 1 }
            const lock = await lockDownloads(downloads, { wait: true, signal: stopped.signal })
            try { await downloadReferences(downloads, references, { signal: stopped.signal, onProgress: (step, done, total) => { library.progress = { step, done, total } } }) }
            finally { await lock?.release() }
            referenceErrors = await readDownloadErrors(downloads)
            await sync()
          }),
          installSearch: () => void backend.install().then(() => background("sync", sync)).catch(error => problems.report("search setup failed", error)),
        }
      } catch (error) {
        problems.report("reference library disabled", error)
        lib = undefined
        await Promise.allSettled(registrations.splice(libraryStart).reverse().map(async item => item.dispose()))
      }

      // ---- Settings and the installed Jai compiler ----
      let reloading: Promise<void> | undefined
      const reload = () => { reloading ??= Promise.all([toolsReady ? ctx.tool.reload() : undefined, skillReady ? ctx.skill.reload() : undefined]).then(() => {}).catch(error => problems.report("reload failed", error)).finally(() => { reloading = undefined }); return reloading }
      const librarySettings = (current: typeof DEFAULTS) => JSON.stringify([current.folders, current.jai, current.jaiRoot ?? ""])
      let lastLibrary = librarySettings(settings.current())
      const redetect = async () => {
        const found = await detectJai(settings.current().jaiRoot ?? options.jaiRoot).catch(() => undefined)
        const foundJails = await detectJails().catch(() => undefined)
        const changed = JSON.stringify(found ?? null) !== JSON.stringify(jai ?? null) || foundJails !== jails
        jai = found
        jails = foundJails
        return changed
      }
      try {
        registrations.push({ dispose: settings.watch(current => {
          void (async () => {
            if (librarySettings(current) !== lastLibrary) { lastLibrary = librarySettings(current); await redetect(); lib?.changed() }
            await reload()
          })().catch(error => problems.report("settings update failed", error))
        }) })
        // A new Jai beta installed (e.g. ~/jai/current pointing to a new folder): new skill notes and library sources.
        const jaiTimer = setInterval(() => void redetect().then(changed => { if (changed) { void reload(); lib?.changed() } }).catch(() => {}), 60_000)
        jaiTimer.unref?.()
        registrations.push({ dispose: () => clearInterval(jaiTimer) })
      } catch (error) { problems.report("settings watch failed", error) }

      // ---- Settings page ----
      const state = async (): Promise<StateView> => {
        const base = {
          version: VERSION, settings: settings.current(), dataDirectory: data, problems: await problems.recent(),
          jai: { validated: VALIDATED_JAI, ...(jai && { found: { version: jai.version, path: jai.path, ...(jai.date && { date: jai.date }), ...(jai.compiler && { compiler: jai.compiler }), newer: compareJai(jai.version, VALIDATED_JAI) > 0 } }) },
        }
        return { ...base, ...(lib ? await lib.state() : { references: [], sources: [], search: { supported: false, installed: false, platform: `${process.platform}-${process.arch}` } }) }
      }
      const needLibrary = () => { if (!lib) throw new Error("The reference library could not start on this server; see Recent problems.") ; return lib }
      try {
        registrations.push(await ctx.rpc.register(KnowhowRpc, {
          state: async () => state(),
          update: async (input: unknown) => { await settings.update(input); await reload(); return state() },
          addFolder: async (input: unknown) => {
            const library = needLibrary()
            const { path, name } = input as { path: string; name?: string }
            const resolved = path.replace(/^~(?=\/|$)/, homedir())
            const { stat } = await import("node:fs/promises")
            if (!isAbsolute(resolved) || !(await stat(resolved).then(info => info.isDirectory(), () => false))) throw new Error(`${path} is not a folder`)
            await settings.update({ folders: [...settings.current().folders.filter(folder => folder.path !== resolved), { path: resolved, ...(name && { name }) }] })
            lastLibrary = librarySettings(settings.current())
            library.changed()
            return state()
          },
          removeFolder: async (input: unknown) => {
            const library = needLibrary()
            const { path } = input as { path: string }
            await settings.update({ folders: settings.current().folders.filter(folder => folder.path !== path) })
            lastLibrary = librarySettings(settings.current())
            library.changed()
            return state()
          },
          downloadReferences: async () => { needLibrary().downloadReferences(); return state() },
          reindex: async () => { needLibrary().changed(); return state() },
          installSearch: async () => { needLibrary().installSearch(); return state() },
        } as never))
      } catch (error) { problems.report("settings page not available", error) }
      return cleanup
    },
  }) satisfies Plugin.Plugin
}

/** What the settings page needs from the reference library part (absent when that part could not start). */
interface LibraryPart {
  state(): Promise<Pick<StateView, "references" | "sources" | "progress" | "lastSync" | "lastDownload" | "search">>
  /** The libraries changed (folders, Jai, a forced update): re-index in the background. */
  changed(): void
  downloadReferences(): void
  installSearch(): void
}

/**
 * Problems this plugin hit: printed (the server's console is not always visible), appended to <data>/warnings.log
 * (bounded) and listed on the settings page, so a part that could not start is never silent.
 */
class ProblemLog {
  readonly #file: string
  #writing: Promise<void> = Promise.resolve()
  constructor(data: string) { this.#file = join(data, "warnings.log") }

  report(message: string, error?: unknown): void {
    warn(message, error)
    const detail = error ? `: ${error instanceof Error ? error.message : String(error)}` : ""
    const line = `${new Date().toISOString()} ${VERSION} ${message}${detail}`.replace(/\s+/g, " ").slice(0, 1000)
    this.#writing = this.#writing.then(async () => {
      const { appendFile, stat, writeFile } = await import("node:fs/promises")
      await appendFile(this.#file, `${line}\n`, { mode: 0o600 })
      if (((await stat(this.#file)).size) > 64 * 1024) {
        const text = await readFile(this.#file, "utf8")
        await writeFile(this.#file, text.slice(-32 * 1024).replace(/^[^\n]*\n/, ""), { mode: 0o600 })
      }
    }).catch(() => {})
  }

  /** This version's problems of the last week, newest last. */
  async recent(limit = 10): Promise<string[]> {
    await this.#writing
    const text = await readFile(this.#file, "utf8").catch(() => "")
    const since = Date.now() - 7 * 24 * 3600_000
    return text.split("\n").filter(line => {
      const [at, version] = line.split(" ")
      return version === VERSION && Date.parse(at ?? "") >= since
    }).slice(-limit)
  }
}

export default createPlugin()
