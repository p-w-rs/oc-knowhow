import type { Plugin } from "@opencode/plugin"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { isAbsolute, join } from "node:path"
import { fileURLToPath } from "node:url"
import { Backend, type Runtime } from "./backend.js"
import { folderSources, Library, libraryId, type LibrarySpec, type SyncReport } from "./library.js"
import { downloadReferences, loadReferences, referenceSources, referenceStates, REFERENCES_LIBRARY } from "./references.js"
import { KnowhowRpc, type StateView } from "./rpc.js"
import { dataDirectory, GROUPS, PLUGIN_ID, SettingsStore, VERSION, type Group } from "./settings.js"

export { PLUGIN_ID, VERSION }

export interface KnowhowOptions {
  /** Absolute path; default `$XDG_DATA_HOME/oc-knowhow`. */
  readonly dataDirectory?: string
  /** Absolute path of a references.json to use instead of the bundled one (tests). */
  readonly referencesFile?: string
}

export function parseOptions(raw: unknown): KnowhowOptions {
  const options = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>
  for (const key of ["dataDirectory", "referencesFile"]) if (options[key] !== undefined && (typeof options[key] !== "string" || !isAbsolute(options[key] as string))) throw new Error(`${PLUGIN_ID}: ${key} must be an absolute path`)
  return Object.fromEntries(["dataDirectory", "referencesFile"].filter(key => options[key] !== undefined).map(key => [key, options[key]])) as KnowhowOptions
}

const SKILLS = fileURLToPath(new URL("../skill/", import.meta.url))
const EXAMPLES = fileURLToPath(new URL("../examples/", import.meta.url))
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
      const cleanup = async () => { await Promise.allSettled(registrations.splice(0).reverse().map(async item => item.dispose())) }
      try {
        const options = parseOptions(ctx.options)
        const data = dataDirectory(options.dataDirectory)
        const settings = await SettingsStore.open(data)
        const backend = new Backend(join(data, "search"))
        const runtime = () => sharedRuntime(backend)
        const library = new Library(data, runtime)
        const references = await loadReferences(options.referencesFile)
        const downloads = join(data, "references")
        let referenceErrors: Record<string, string> = {}
        try { referenceErrors = JSON.parse(await readFile(join(downloads, "errors.json"), "utf8")) } catch {}
        let lastSync: (SyncReport & { at: string }) | undefined
        let busy: Promise<unknown> | undefined

        const specs = async (): Promise<LibrarySpec[]> => [
          { id: REFERENCES_LIBRARY, name: "Free references", sources: await referenceSources(downloads, references) },
          ...await Promise.all(settings.current().folders.map(async folder => ({ id: libraryId(folder.path), name: folder.name, sources: await folderSources(folder.path) }))),
        ]
        const sync = async () => { const report = await library.sync(await specs()); lastSync = { ...report, at: new Date().toISOString() }; return report }
        const background = (task: () => Promise<unknown>) => { busy ??= task().catch(error => warn("library update failed", error)).finally(() => { busy = undefined }); return busy }

        const folderOf = (libraryKey: string) => settings.current().folders.find(folder => libraryId(folder.path) === libraryKey)
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
            description: "List the reference library: free references (statistics, experiment design, datasets, ML evaluation, reporting standards, visualization, gnuplot, diagrams) and the user's own folders, each with what it is good for and its status (current, dated, superseded). Use it to pick sources, then library_search. Pass source=<id> for its table of contents.",
            input: { type: "object", properties: { source: { type: "string", maxLength: 200 }, field: { type: "string", maxLength: 60, description: "e.g. statistics, ml, datasets, causal, clinical, gnuplot, diagrams" } }, additionalProperties: false } as never,
            options: { codemode: false },
            execute: async (raw: unknown) => {
              const input = raw as { source?: string; field?: string }
              if (input.source) {
                const outline = await library.outline(input.source)
                if (!outline.length) throw new Error(`No indexed source ${JSON.stringify(input.source)} (see library_catalog without arguments)`)
                return text(`Sections of ${input.source} (read with library_read ref=…):\n${outline.slice(0, 400).map(item => `- ${item.ref}  ${item.where}`).join("\n")}${outline.length > 400 ? `\n… ${outline.length - 400} more` : ""}`)
              }
              const stored = await library.stored()
              const field = input.field?.toLowerCase()
              const lines = stored.filter(item => !field || (item.meta.fields ?? []).some(value => value.toLowerCase() === field)).map(item => {
                const meta = item.meta
                const folder = item.library === REFERENCES_LIBRARY ? "free" : folderOf(item.library)?.name ?? item.library
                return `- ${meta.id} [${folder}; ${meta.status ?? "unknown"}${meta.supersededBy ? ` → ${meta.supersededBy}` : ""}${item.units.length ? `; ${item.units.length} sections` : item.kind === "link" ? "; online only" : ""}${item.error ? `; NOT READABLE: ${item.error.slice(0, 80)}` : ""}] ${meta.title}${meta.authors ? ` — ${meta.authors}` : ""}${meta.year ? ` (${meta.year})` : ""}${meta.useFor ? `\n    use for: ${meta.useFor}` : ""}${meta.note ? `\n    note: ${meta.note}` : ""}${item.kind === "link" && meta.url ? `\n    read online: ${meta.url}` : ""}`
              })
              const missing = (await referenceStates(downloads, references)).filter(state => state.state === "missing").length
              return text([
                `Reference library: ${stored.length} sources${field ? ` in ${field}` : ""}. Status: current = use as written; dated = sound in parts, check the note and the skills; superseded = see the newer source. Cite as <title>, <where>.`,
                ...(missing ? [`${missing} free references are not downloaded yet (the user can click Download in Settings → Know-how).`] : []),
                ...lines,
              ].join("\n"))
            },
          })
          editor.add({
            name: "library_search",
            description: "Search the reference library (books, papers, manuals, standards, gnuplot demos; the user's own folders and free references) for ground truth: methods, definitions, assumptions, recommended practice, worked examples, exact syntax. Returns passages with section/page citations and each source's status; dated sources are flagged. Then library_read for the full section.",
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
                const folder = folderOf(hit.ref.split("--")[0]!)
                if (folder) { try { await assertRead(context, folder.path) } catch (error) { if (blocked(error)) { hidden++; continue } throw error } }
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
              const folder = folderOf(input.ref.split("--")[0]!)
              if (folder) await assertRead(context, folder.path)
              const section = await library.read(input.ref, { neighbors: input.neighbors ?? 0 })
              if (!section) throw new Error(`No section ${input.ref}. Use library_search or library_catalog source=<id>.`)
              const meta = section.meta
              return text(`# ${meta.title}${meta.authors ? ` — ${meta.authors}` : ""}${meta.year ? ` (${meta.year})` : ""}\nCite: ${meta.title}, ${section.where}. Status: ${meta.status ?? "unknown"}${meta.note ? ` — ${meta.note}` : ""}\n\n${section.text}\n\n${section.previous ? `previous: ${section.previous}  ` : ""}${section.next ? `next: ${section.next}` : ""}`)
            },
          })
        }))

        // ---- Skills ----
        let skillReady = false
        try {
          const skills = await Promise.all((Object.entries(GROUPS) as [Group, readonly string[]][]).flatMap(([group, ids]) => ids.map(async id => {
            const path = join(SKILLS, id, "SKILL.md")
            const examples = id === "gnuplot" ? "gnuplot" : id === "diagrams" ? "diagrams" : undefined
            const content = (await readFile(path, "utf8")) + (examples ? `\n\n---\nOn this computer the examples are in: ${join(EXAMPLES, examples)}\n` : "")
            return { group, id, path, content, description: /^description:\s*(.+)$/m.exec(content)?.[1] ?? id }
          })))
          registrations.push(await ctx.skill.transform(editor => {
            const current = settings.current()
            for (const skill of skills) if (current[skill.group]) editor.add({ id: skill.id as never, name: skill.id as never, description: skill.description, path: skill.path as never, content: skill.content })
          }))
          skillReady = true
        } catch (error) { warn("skills not registered", error) }

        let reloading: Promise<void> | undefined
        const reload = () => { reloading ??= Promise.all([ctx.tool.reload(), skillReady ? ctx.skill.reload() : undefined]).then(() => {}).catch(error => warn("reload failed", error)).finally(() => { reloading = undefined }); return reloading }
        let lastFolders = JSON.stringify(settings.current().folders)
        registrations.push({ dispose: settings.watch(current => {
          void reload()
          if (JSON.stringify(current.folders) !== lastFolders) { lastFolders = JSON.stringify(current.folders); void background(sync) }
        }) })
        // Pick up new or changed files in the user's folders without blocking startup.
        const timer = setTimeout(() => void background(sync), 5000)
        timer.unref?.()
        registrations.push({ dispose: () => clearTimeout(timer) })

        // ---- GUI ----
        const state = async (): Promise<StateView> => {
          const stored = await library.stored()
          const own = await backend.status()
          const shared = !own.installed && await runtime() ? "using the search engine downloaded by oc-enhance" : undefined
          return {
            version: VERSION, settings: settings.current(), dataDirectory: data,
            references: await referenceStates(downloads, references, referenceErrors),
            sources: stored.map(item => ({ library: item.library === REFERENCES_LIBRARY ? "Free references" : folderOf(item.library)?.name ?? item.library, id: item.meta.id, title: item.meta.title, status: item.meta.status ?? "unknown", sections: item.units.length, ...(item.error && { error: item.error }) })),
            ...(library.progress && { progress: library.progress }), ...(lastSync && { lastSync }),
            search: { ...own, installed: own.installed || !!shared, ...(shared && { shared }) },
          }
        }
        registrations.push(await ctx.rpc.register(KnowhowRpc, {
          state: async () => state(),
          update: async (input: unknown) => { await settings.update(input); await reload(); return state() },
          addFolder: async (input: unknown) => {
            const { path, name } = input as { path: string; name?: string }
            const resolved = path.replace(/^~(?=\/|$)/, homedir())
            const { stat } = await import("node:fs/promises")
            if (!isAbsolute(resolved) || !(await stat(resolved).then(info => info.isDirectory(), () => false))) throw new Error(`${path} is not a folder`)
            await settings.update({ folders: [...settings.current().folders.filter(folder => folder.path !== resolved), { path: resolved, ...(name && { name }) }] })
            lastFolders = JSON.stringify(settings.current().folders)
            void background(sync)
            return state()
          },
          removeFolder: async (input: unknown) => {
            const { path } = input as { path: string }
            await settings.update({ folders: settings.current().folders.filter(folder => folder.path !== path) })
            lastFolders = JSON.stringify(settings.current().folders)
            void background(sync)
            return state()
          },
          downloadReferences: async () => {
            void background(async () => {
              referenceErrors = await downloadReferences(downloads, references, { onProgress: (step, done, total) => { library.progress = { step, done, total } } })
              await sync()
            })
            return state()
          },
          reindex: async () => { void background(sync); return state() },
          installSearch: async () => { void backend.install().then(() => background(sync)).catch(error => warn("search setup failed", error)); return state() },
        } as never))
      } catch (error) {
        warn("disabled", error)
        await cleanup()
      }
      return cleanup
    },
  }) satisfies Plugin.Plugin
}

export default createPlugin()
