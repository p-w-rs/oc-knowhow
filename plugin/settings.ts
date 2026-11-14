import { readFileSync, statSync } from "node:fs"
import { mkdir, rename, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import { isAbsolute, join } from "node:path"

export const PLUGIN_ID = "oc-knowhow"
export const VERSION = "1.6.1"

export const dataDirectory = (configured?: string) => configured ?? join(process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), PLUGIN_ID)

/** Skill groups the user can turn off. */
export const GROUPS = {
  ml: ["ml-training", "ml-data", "ml-tuning", "ml-qat", "ml-metrics", "ml-deploy", "gpu-kernels"],
  datascience: ["stats-inference", "experiment-design", "datasets", "field-methods", "arrow", "polars"],
  figures: ["gnuplot", "diagrams"],
  odin: ["odin", "odin-performance", "odin-targets"],
  robotics: ["zenoh", "zenoh-ros2", "mcap", "rerun", "robot-serialization", "dora", "robot-math", "mcu-tooling", "mujoco", "genesis", "isaac-sim", "opencv"],
  clibs: ["c-platform", "c-networking", "c-crypto", "c-data", "c-gamedev", "c-perf"],
} as const
export type Group = keyof typeof GROUPS

export interface LibraryFolder { readonly path: string; readonly name: string }
export interface Settings {
  readonly ml: boolean
  readonly datascience: boolean
  readonly figures: boolean
  readonly odin: boolean
  readonly robotics: boolean
  readonly clibs: boolean
  /** Library tools (search your folders and the downloaded free references). */
  readonly library: boolean
  readonly folders: readonly LibraryFolder[]
}

export const DEFAULTS: Settings = { ml: true, datascience: true, figures: true, odin: true, robotics: true, clibs: true, library: true, folders: [] }

export function normalizeSettings(raw: unknown, base: Settings = DEFAULTS): Settings {
  const value = raw && typeof raw === "object" && !Array.isArray(raw) ? raw as Record<string, unknown> : {}
  const result: Record<string, unknown> = { ...base }
  for (const key of ["ml", "datascience", "figures", "odin", "robotics", "clibs", "library"] as const) if (typeof value[key] === "boolean") result[key] = value[key]
  if (Array.isArray(value.folders)) {
    result.folders = value.folders.flatMap(item => {
      const folder = item as Record<string, unknown>
      const path = typeof folder?.path === "string" ? folder.path.replace(/^~(?=\/|$)/, homedir()) : ""
      if (!path || !isAbsolute(path)) return []
      return [{ path, name: typeof folder.name === "string" && folder.name.trim() ? folder.name.trim().slice(0, 80) : path.split("/").filter(Boolean).pop() ?? path }]
    }).slice(0, 20)
  }
  return result as unknown as Settings
}

/** `<data>/settings.json`, shared by every OpenCode server on this computer. */
export class SettingsStore {
  #value: Settings = DEFAULTS
  #mtime = -1
  private constructor(readonly path: string) {}

  static async open(directory: string): Promise<SettingsStore> {
    await mkdir(directory, { recursive: true, mode: 0o700 })
    const store = new SettingsStore(join(directory, "settings.json"))
    store.current()
    return store
  }

  current(): Settings {
    let mtime = 0
    try { mtime = statSync(this.path).mtimeMs } catch {}
    if (mtime !== this.#mtime) {
      this.#mtime = mtime
      try { this.#value = mtime ? normalizeSettings(JSON.parse(readFileSync(this.path, "utf8"))) : DEFAULTS } catch { this.#value = DEFAULTS }
    }
    return this.#value
  }

  async update(patch: unknown): Promise<Settings> {
    const next = normalizeSettings(patch, this.current())
    const temporary = `${this.path}.${process.pid}.tmp`
    await writeFile(temporary, JSON.stringify(next, null, 2) + "\n", { mode: 0o600 })
    await rename(temporary, this.path)
    return this.current()
  }

  watch(listener: (settings: Settings) => void, intervalMs = 3000): () => void {
    let last = JSON.stringify(this.current())
    const timer = setInterval(() => { const now = JSON.stringify(this.current()); if (now !== last) { last = now; listener(this.current()) } }, intervalMs)
    timer.unref?.()
    return () => clearInterval(timer)
  }
}
