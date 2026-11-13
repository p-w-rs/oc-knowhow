import type { Rpc } from "@opencode/plugin/rpc"
import type { BackendStatus } from "./backend.js"
import type { DownloadState } from "./references.js"
import type { Progress, SyncReport } from "./library.js"
import type { Settings } from "./settings.js"

const output = {} as const
const object = (properties: Record<string, unknown>, required: string[] = []) => ({ type: "object", properties, required, additionalProperties: false }) as const

export const KnowhowRpc = {
  id: "oc-knowhow.admin",
  methods: {
    state: { input: object({}), output },
    update: { input: object({ ml: { type: "boolean" }, datascience: { type: "boolean" }, figures: { type: "boolean" }, odin: { type: "boolean" }, robotics: { type: "boolean" }, clibs: { type: "boolean" }, library: { type: "boolean" } }), output },
    addFolder: { input: object({ path: { type: "string", minLength: 1, maxLength: 4000 }, name: { type: "string", maxLength: 80 } }, ["path"]), output },
    removeFolder: { input: object({ path: { type: "string", minLength: 1, maxLength: 4000 } }, ["path"]), output },
    downloadReferences: { input: object({}), output },
    reindex: { input: object({}), output },
    installSearch: { input: object({}), output },
  },
  events: {},
} as const satisfies Rpc.PortableDefinition

export interface StateView {
  readonly version: string
  readonly settings: Settings
  readonly dataDirectory: string
  readonly references: readonly DownloadState[]
  readonly sources: { readonly library: string; readonly id: string; readonly title: string; readonly status: string; readonly sections: number; readonly error?: string }[]
  readonly progress?: Progress
  readonly lastSync?: SyncReport & { readonly at: string }
  readonly search: BackendStatus & { readonly shared?: string }
}
