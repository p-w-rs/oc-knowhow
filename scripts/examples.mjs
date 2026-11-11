// Renders every example (gnuplot scripts and diagrams) into .local/examples and fails on any error or empty output.
// Look at the results afterwards: rendering without errors is not the same as looking right.
import { spawnSync } from "node:child_process"
import { mkdirSync, readdirSync, statSync } from "node:fs"
import { join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const root = resolve(fileURLToPath(new URL("..", import.meta.url)))
const bin = name => join(root, ".pixi", "envs", "default", "bin", name)
const out = join(root, ".local", "examples")
mkdirSync(out, { recursive: true })
const failures = []
const run = (label, command, args, cwd, file) => {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", timeout: 300_000 })
  const size = (() => { try { return statSync(file).size } catch { return 0 } })()
  const errors = `${result.stderr ?? ""}`.split("\n").filter(line => /error|warning|unexpected|invalid/i.test(line) && !/slow font initialization/.test(line))
  const ok = result.status === 0 && size > 0 && !errors.length
  console.log(`${ok ? "ok  " : "FAIL"} ${label} → ${file} (${size} bytes)${ok ? "" : `\n     ${(errors.join("\n     ") || result.stderr || result.error?.message || "").slice(0, 600)}`}`)
  if (!ok) failures.push(label)
}
spawnSync(bin("dot"), ["-c"])
const gp = join(root, "examples", "gnuplot")
for (const name of readdirSync(gp).filter(name => /^[a-z].*\.gp$/.test(name)).sort()) {
  const base = name.slice(0, -3)
  const file = join(out, `${base}.${base === "rotate-3d" ? "webp" : base === "interactive" ? "html" : "png"}`)
  run(`gnuplot ${name}`, bin("gnuplot"), ["-e", `out='${file}'`, name], gp, file)
}
const dg = join(root, "examples", "diagrams")
for (const name of readdirSync(dg).sort()) {
  const base = name.replace(/\.[^.]+$/, "")
  if (name.endsWith(".d2")) {
    run(`d2 ${name}`, bin("d2"), [name, join(out, `${base}.svg`)], dg, join(out, `${base}.svg`))
    run(`png ${base}`, bin("rsvg-convert"), ["-w", "1400", "-b", "white", join(out, `${base}.svg`), "-o", join(out, `${base}.png`)], dg, join(out, `${base}.png`))
  }
  if (name.endsWith(".dot")) run(`dot ${name}`, bin("dot"), ["-Tpng", "-Gdpi=150", name, "-o", join(out, `${base}.png`)], dg, join(out, `${base}.png`))
}
if (failures.length) { console.error(`${failures.length} example(s) failed: ${failures.join(", ")}`); process.exit(1) }
console.log(`All examples rendered into ${out}. Look at them.`)
