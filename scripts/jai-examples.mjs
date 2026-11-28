// Compiles and runs the Jai examples (examples/jai/<skill>/<name>.jai or <name>/) with the installed compiler and
// checks what each example's header says should happen. Run it whenever the compiler changes (a new beta):
//   pixi run jai-examples                                    every example on this computer (~/jai/current)
//   pixi run jai-examples -- --skill jai-systems --filter alloc
//   pixi run jai-examples -- --remote powerslabs --ssh-config "$OCM_SSH_CONFIG" [--kit name]   (remote dir ~/oc-validate/jai/<kit>)
//   pixi run jai-examples -- --list
// Header directives: the leading comment block of the example file (or, for a folder, of its entry file:
// first.jai, build.jai or main.jai), one per line:
//   // EXPECT: <line>               the program's exact stdout, one directive per output line, in order
//   // EXPECT-CONTAINS: <text>       stdout or stderr contains this (repeatable)
//   // EXPECT-COMPILE: <text>        compiler output contains this, e.g. print() from #run (repeatable)
//   // EXPECT-COMPILE-ERROR: <text>  compiling must fail and the output contain this (repeatable)
//   // EXPECT-EXIT: <n>              the program's exit code (default 0)
//   // JAI-ARGS: <args>              extra compiler arguments (-quiet is always passed)
//   // RUN-ARGS: <args>              program arguments
//   // EXE: <path>                   what the build produces (default: the entry name without .jai)
//   // NO-RUN                        compile only
//   // PLATFORMS: macos linux        where the example applies (default: both)
//   // TIMEOUT: <seconds>            for running the program (default 60; compiling gets 300)
import { spawnSync } from "node:child_process"
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { basename, dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const argv = process.argv.slice(2)
const option = name => { const i = argv.indexOf(`--${name}`); return i >= 0 ? argv[i + 1] : undefined }
const flag = name => argv.includes(`--${name}`)
const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(option("root") ?? join(here, "..", "examples", "jai"))
const platform = process.platform === "darwin" ? "macos" : "linux"
const jai = resolve(option("jai") ?? join(homedir(), "jai", "current", "bin", platform === "macos" ? "jai-macos" : "jai-linux"))
const work = resolve(option("work") ?? join(tmpdir(), "oc-knowhow-jai-run"))
const skillFilter = option("skill")
const nameFilter = option("filter")

/** Splits an argument string like a shell would for simple cases: spaces separate, double quotes group. */
const split = text => [...text.matchAll(/"([^"]*)"|(\S+)/g)].map(m => m[1] ?? m[2])

function compilerVersion(compiler) {
  try {
    const top = realpathSync(join(dirname(compiler), ".."))
    const line = /Version:\s*(beta [\d.]+)[^\n]*/.exec(readFileSync(join(top, "CHANGELOG.txt"), "utf8"))
    return { version: line?.[1] ?? "unknown", root: top }
  } catch { return { version: "unknown", root: dirname(compiler) } }
}

function examples() {
  const found = []
  if (!existsSync(root)) return found
  for (const skill of readdirSync(root).sort()) {
    const dir = join(root, skill)
    if (!statSync(dir).isDirectory() || (skillFilter && skill !== skillFilter)) continue
    for (const name of readdirSync(dir).sort()) {
      if (name.startsWith(".") || name.startsWith("_")) continue
      const path = join(dir, name)
      const isDir = statSync(path).isDirectory()
      if (!isDir && !name.endsWith(".jai")) continue
      if (nameFilter && !`${skill}/${name}`.includes(nameFilter)) continue
      const entry = isDir ? ["first.jai", "build.jai", "main.jai"].find(file => existsSync(join(path, file))) : name
      if (!entry) { found.push({ skill, name, path, isDir, problem: "folder example without first.jai, build.jai or main.jai" }); continue }
      found.push({ skill, name, path, isDir, entry })
    }
  }
  return found
}

function directives(text) {
  const d = { expect: [], hasExpect: false, contains: [], compile: [], compileError: [], exit: 0, jaiArgs: [], runArgs: [], exe: undefined, noRun: false, platforms: ["macos", "linux"], timeout: 60 }
  for (const line of text.replace(/\r\n?/g, "\n").split("\n")) {
    if (!line.trim()) continue
    if (!line.trimStart().startsWith("//")) break
    const m = /^\s*\/\/\s*([A-Z][A-Z-]*)(?::\s?(.*))?$/.exec(line)
    if (!m) continue
    const [, key, value = ""] = m
    switch (key) {
      case "EXPECT": d.expect.push(value.trimEnd()); d.hasExpect = true; break
      case "EXPECT-CONTAINS": d.contains.push(value.trim()); break
      case "EXPECT-COMPILE": d.compile.push(value.trim()); break
      case "EXPECT-COMPILE-ERROR": d.compileError.push(value.trim()); break
      case "EXPECT-EXIT": d.exit = Number(value.trim()); break
      case "JAI-ARGS": d.jaiArgs.push(...split(value)); break
      case "RUN-ARGS": d.runArgs.push(...split(value)); break
      case "EXE": d.exe = value.trim(); break
      case "NO-RUN": d.noRun = true; break
      case "PLATFORMS": d.platforms = value.trim().split(/[\s,]+/).filter(Boolean); break
      case "TIMEOUT": d.timeout = Number(value.trim()) || 60; break
    }
  }
  return d
}

const lines = text => text.replace(/\r\n?/g, "\n").split("\n").map(line => line.trimEnd()).join("\n").replace(/\n+$/, "")
const tail = (text, n = 1200) => { const t = text.trim(); return t.length > n ? `…${t.slice(-n)}` : t }

function check(example) {
  if (example.problem) return { status: "FAIL", detail: example.problem }
  const target = join(work, example.skill, example.name.replace(/\.jai$/, ""))
  rmSync(target, { recursive: true, force: true })
  mkdirSync(target, { recursive: true })
  if (example.isDir) cpSync(example.path, target, { recursive: true })
  else cpSync(example.path, join(target, example.name))
  const d = directives(readFileSync(join(target, example.entry), "utf8"))
  if (!d.platforms.includes(platform)) return { status: "skip", detail: `only ${d.platforms.join(", ")}` }

  const t0 = Date.now()
  const built = spawnSync(jai, [example.entry, "-quiet", ...d.jaiArgs], { cwd: target, encoding: "utf8", timeout: 300_000, maxBuffer: 64 * 1024 * 1024 })
  const compileSeconds = (Date.now() - t0) / 1000
  const compileOutput = `${built.stdout ?? ""}${built.stderr ?? ""}`
  if (built.error) return { status: "FAIL", detail: `compiler did not finish: ${built.error.message}` }
  if (d.compileError.length) {
    if (built.status === 0) return { status: "FAIL", detail: `expected a compile error, but it compiled\n${tail(compileOutput)}` }
    const missing = d.compileError.filter(text => !compileOutput.includes(text))
    return missing.length ? { status: "FAIL", detail: `compile error output lacks: ${missing.map(m => JSON.stringify(m)).join(", ")}\n${tail(compileOutput)}` } : { status: "ok", detail: `compile error as expected (${compileSeconds.toFixed(2)} s)` }
  }
  if (built.status !== 0) return { status: "FAIL", detail: `compile failed (exit ${built.status})\n${tail(compileOutput)}` }
  const missingCompile = d.compile.filter(text => !compileOutput.includes(text))
  if (missingCompile.length) return { status: "FAIL", detail: `compiler output lacks: ${missingCompile.map(m => JSON.stringify(m)).join(", ")}\n${tail(compileOutput)}` }
  if (d.noRun) return { status: "ok", detail: `compiled (${compileSeconds.toFixed(2)} s), not run` }

  const exe = join(target, d.exe ?? example.entry.replace(/\.jai$/, ""))
  if (!existsSync(exe)) return { status: "FAIL", detail: `no executable at ${exe}\n${tail(compileOutput)}` }
  const t1 = Date.now()
  const ran = spawnSync(exe, d.runArgs, { cwd: target, encoding: "utf8", timeout: d.timeout * 1000, maxBuffer: 64 * 1024 * 1024 })
  const runSeconds = (Date.now() - t1) / 1000
  const stdout = ran.stdout ?? "", both = `${stdout}${ran.stderr ?? ""}`
  if (ran.error) return { status: "FAIL", detail: `program did not finish: ${ran.error.message}\n${tail(both)}` }
  const problems = []
  if (ran.status !== d.exit) problems.push(`exit ${ran.status ?? ran.signal}, expected ${d.exit}`)
  if (d.hasExpect && lines(stdout) !== lines(d.expect.join("\n"))) problems.push(`stdout differs\n--- expected\n${lines(d.expect.join("\n"))}\n--- got\n${tail(lines(stdout), 2000)}`)
  const missing = d.contains.filter(text => !both.includes(text))
  if (missing.length) problems.push(`output lacks: ${missing.map(m => JSON.stringify(m)).join(", ")}\n${tail(both)}`)
  if (!d.hasExpect && !d.contains.length) problems.push("no EXPECT or EXPECT-CONTAINS: say what the output must be")
  return problems.length ? { status: "FAIL", detail: problems.join("\n") } : { status: "ok", detail: `compile ${compileSeconds.toFixed(2)} s, run ${runSeconds.toFixed(2)} s` }
}

// ---- remote: copy the examples and this script, run there with the remote compiler
const remote = option("remote")
if (remote) {
  const config = option("ssh-config")
  const ssh = config ? ["-F", config] : []
  const kit = `oc-validate/jai/${option("kit") ?? "kit"}`
  const forwarded = []
  for (let i = 0; i < argv.length; i++) {
    if (["--remote", "--ssh-config", "--root", "--jai", "--work", "--kit"].includes(argv[i])) { i++; continue }
    forwarded.push(argv[i])
  }
  const step = (command, args) => { const r = spawnSync(command, args, { stdio: "inherit" }); if (r.status !== 0) { console.error(`${command} failed (exit ${r.status})`); process.exit(1) } }
  step("ssh", [...ssh, remote, `mkdir -p ${kit}/examples`])
  const rsh = config ? `ssh -F '${config}'` : "ssh"
  step("rsync", ["-a", "--delete", "-e", rsh, `${root}/`, `${remote}:${kit}/examples/`])
  step("rsync", ["-a", "-e", rsh, fileURLToPath(import.meta.url), `${remote}:${kit}/jai-examples.mjs`])
  const command = `cd ~/${kit} && PIXI=$(command -v pixi || echo ~/.pixi/bin/pixi) && "$PIXI" exec --spec nodejs=24 node jai-examples.mjs --root examples --work ~/${kit}/run ${forwarded.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" ")}`
  const result = spawnSync("ssh", [...ssh, remote, command], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 })
  process.stdout.write(result.stdout ?? ""); process.stderr.write(result.stderr ?? "")
  mkdirSync(work, { recursive: true })
  writeFileSync(join(work, `results-${remote}${skillFilter ? `-${skillFilter}` : ""}.txt`), result.stdout ?? "")
  process.exit(result.status ?? 1)
}

// ---- local
const found = examples()
if (flag("list")) { for (const e of found) console.log(`${e.skill}/${e.name}${e.isDir ? "/" : ""}`); process.exit(0) }
if (!existsSync(jai)) { console.error(`No Jai compiler at ${jai} (pass --jai /path/to/jai-macos|jai-linux)`); process.exit(2) }
const { version, root: jaiRoot } = compilerVersion(jai)
console.log(`Jai ${version} (${jaiRoot}) on ${platform}; ${found.length} example(s) from ${root}`)
const results = []
for (const example of found) {
  const result = check(example)
  results.push({ ...example, ...result })
  const label = `${example.skill}/${example.name}`
  console.log(`${result.status === "ok" ? "ok  " : result.status === "skip" ? "skip" : "FAIL"} ${label}${result.status === "FAIL" ? `\n     ${result.detail.replace(/\n/g, "\n     ")}` : ` (${result.detail})`}`)
}
const failed = results.filter(r => r.status === "FAIL")
const summary = `${results.filter(r => r.status === "ok").length} ok, ${failed.length} failed, ${results.filter(r => r.status === "skip").length} skipped (Jai ${version}, ${platform})`
console.log(summary)
mkdirSync(work, { recursive: true })
writeFileSync(join(work, `results-${version.replace(/\s+/g, "-")}-${platform}${skillFilter ? `-${skillFilter}` : ""}.txt`), [summary, ...results.map(r => `${r.status}\t${r.skill}/${r.name}\t${r.detail.split("\n")[0]}`)].join("\n") + "\n")
process.exit(failed.length ? 1 : 0)
