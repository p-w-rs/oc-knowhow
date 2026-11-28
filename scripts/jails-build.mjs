#!/usr/bin/env node
// jails-build.mjs: build the Jails language server for Jai (github.com/SogoCZE/Jails, MIT license) from source with
// the user's own Jai compiler, install it as <prefix>/<commit8>/jails (default ~/jai/tools/jails/<commit8>/jails),
// point <prefix>/current at it, and smoke-test it over LSP (initialize, document symbols, go to definition into
// Basic, compiler diagnostics after didSave).
//
// Needs: Node >= 20 (e.g. `pixi exec --spec nodejs=24 node jails-build.mjs`), git, a Jai compiler root, and on macOS
// Xcode's command line tools (the compiler links with ld; Jails' build.jai ad-hoc codesigns the binary).
// Tested 27 Nov 2026: Jails 0.2.22 @ 42fa76c8 with Jai beta 0.2.032 on macOS arm64 and Arch Linux x86-64,
// no patches needed. Windows is not supported by this script (untested).
//
// Usage:
//   node jails-build.mjs                  build the pinned commit, install it, smoke-test it
//   node jails-build.mjs --ref main       build the newest commit of a branch or tag instead
//   node jails-build.mjs --check          report what is installed; exit 0 if the pinned commit is installed
// Options:
//   --jai <dir>      Jai compiler root with bin/ and modules/ (default $JAI_ROOT or ~/jai/current)
//   --prefix <dir>   install root (default $JAILS_PREFIX or ~/jai/tools/jails)
//   --commit <sha>   full 40-character commit to build (default: the pinned, tested commit)
//   --ref <name>     branch or tag to build instead (resolved with git ls-remote)
//   --repo <url>     repository (default https://github.com/SogoCZE/Jails.git)
//   --patch <file>   apply a patch with `git apply` before building (repeatable; installs as <commit8>-p<hash>)
//   --work <dir>     build directory (default: a temporary directory, removed after a successful build)
//   --keep-work      keep the build directory
//   --force          rebuild even if the target is already installed
//   --no-current     do not repoint <prefix>/current
//   --no-smoke       skip the smoke test
//   --json           print a JSON summary on stdout (progress goes to stderr)
import { spawn, spawnSync, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const PINNED = { commit: "42fa76c816ad34c9f24a4bde586d145c992dc860", version: "0.2.22", testedWith: "beta 0.2.032" };
const DEFAULT_REPO = "https://github.com/SogoCZE/Jails.git";

// ---------- arguments ----------
const opts = { patch: [], current: true, smoke: true };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const value = () => {
    if (i + 1 >= argv.length) fail(`${a} needs a value`, 2);
    return argv[++i];
  };
  switch (a) {
    case "--jai": opts.jai = value(); break;
    case "--prefix": opts.prefix = value(); break;
    case "--commit": opts.commit = value(); break;
    case "--ref": opts.ref = value(); break;
    case "--repo": opts.repo = value(); break;
    case "--patch": opts.patch.push(value()); break;
    case "--work": opts.work = value(); break;
    case "--keep-work": opts.keepWork = true; break;
    case "--force": opts.force = true; break;
    case "--no-current": opts.current = false; break;
    case "--no-smoke": opts.smoke = false; break;
    case "--check": opts.check = true; break;
    case "--json": opts.json = true; break;
    case "-h": case "--help": help(0); break;
    default: fail(`unknown argument: ${a} (see --help)`, 2);
  }
}

function help(code) {
  const lines = fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n");
  console.error(lines.filter((l) => l.startsWith("//")).map((l) => l.slice(3)).join("\n"));
  process.exit(code);
}
function log(msg) { console.error(`[jails-build] ${msg}`); }
function fail(msg, code = 1) { console.error(`[jails-build] error: ${msg}`); process.exit(code); }

const home = os.homedir();
const expand = (p) => path.resolve(p.replace(/^~(?=$|\/)/, home));
const jaiRoot = expand(opts.jai ?? process.env.JAI_ROOT ?? "~/jai/current");
const prefix = expand(opts.prefix ?? process.env.JAILS_PREFIX ?? "~/jai/tools/jails");
const repo = opts.repo ?? DEFAULT_REPO;
const GIT = process.env.GIT ?? "git";

const exeName = { darwin: "jai-macos", linux: "jai-linux" }[process.platform];
if (!exeName) fail(`unsupported platform ${process.platform}; build by hand with: jai build.jai - -release`, 2);

// ---------- helpers ----------
function run(cmd, args, { cwd, timeout = 300_000, allowFail = false } = {}) {
  const r = spawnSync(cmd, args, { cwd, timeout, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  const output = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  if (!allowFail && (r.error || r.status !== 0)) {
    const why = r.error ? r.error.message : `exit ${r.status}${r.signal ? ` (${r.signal})` : ""}`;
    fail(`${cmd} ${args.join(" ")} failed: ${why}\n${output.split("\n").slice(-30).join("\n")}`);
  }
  return { status: r.status, output, stdout: r.stdout ?? "" };
}
const sha256 = (data) => createHash("sha256").update(data).digest("hex");
function readJson(file) { try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return null; } }
function compilerVersion(root) {
  // The first line of the bundle's change log names the version; `jai -version` only prints to a terminal.
  try {
    const first = fs.readFileSync(path.join(root, "CHANGELOG.txt"), "utf8").split("\n", 1)[0];
    return /^Version:\s*([^,]+)/.exec(first)?.[1].trim() ?? "unknown";
  } catch { return "unknown"; }
}
function installedSummary() {
  const current = path.join(prefix, "current");
  let target = null;
  try { target = fs.readlinkSync(current); } catch {}
  const versions = fs.existsSync(prefix)
    ? fs.readdirSync(prefix).filter((d) => d !== "current" && fs.existsSync(path.join(prefix, d, "jails")))
    : [];
  return {
    prefix,
    current: target ? path.join(prefix, target, "jails") : null,
    currentInfo: target ? readJson(path.join(prefix, target, "BUILD-INFO.json")) : null,
    installed: versions,
    pinned: PINNED.commit.slice(0, 8),
    pinnedInstalled: versions.includes(PINNED.commit.slice(0, 8)),
  };
}

// ---------- --check ----------
if (opts.check) {
  const s = installedSummary();
  if (opts.json) console.log(JSON.stringify(s, null, 2));
  else {
    log(`prefix ${s.prefix}`);
    log(`installed: ${s.installed.length ? s.installed.join(", ") : "nothing"}`);
    log(`current: ${s.current ?? "none"}${s.currentInfo ? ` (Jails ${s.currentInfo.version}, built with Jai ${s.currentInfo.compiler.version})` : ""}`);
    log(`pinned ${s.pinned}: ${s.pinnedInstalled ? "installed" : "not installed"}`);
  }
  process.exit(s.pinnedInstalled ? 0 : 1);
}

// ---------- preflight ----------
const jaiExe = path.join(jaiRoot, "bin", exeName);
if (!fs.existsSync(jaiExe)) fail(`Jai compiler not found: ${jaiExe} (pass --jai <root>)`, 2);
if (!fs.existsSync(path.join(jaiRoot, "modules", "Basic"))) fail(`no modules/Basic under ${jaiRoot}`, 2);
if (run(GIT, ["--version"], { allowFail: true }).status !== 0) fail("git is not available (set $GIT)", 2);
const jaiVersion = compilerVersion(jaiRoot);
log(`compiler ${jaiExe} (${jaiVersion})`);

// ---------- which commit ----------
let commit = opts.commit ?? PINNED.commit;
if (opts.ref) {
  const out = run(GIT, ["ls-remote", repo, opts.ref]).stdout.trim().split("\n").filter(Boolean).map((l) => l.split(/\s+/));
  const pick = (name) => out.find(([, ref]) => ref === name)?.[0];
  commit = pick(`refs/heads/${opts.ref}`) ?? pick(`refs/tags/${opts.ref}^{}`) ?? pick(`refs/tags/${opts.ref}`) ?? null;
  if (!commit) fail(`ref '${opts.ref}' not found in ${repo}`, 2);
  log(`${opts.ref} is at ${commit}`);
}
if (!/^[0-9a-f]{40}$/.test(commit)) fail(`--commit needs the full 40-character commit, got '${commit}'`, 2);
const patches = opts.patch.map((p) => {
  const file = expand(p);
  if (!fs.existsSync(file)) fail(`patch not found: ${file}`, 2);
  const data = fs.readFileSync(file);
  return { file, name: path.basename(file), sha256: sha256(data) };
});
const short = commit.slice(0, 8);
const dirName = patches.length ? `${short}-p${sha256(patches.map((p) => p.sha256).join("")).slice(0, 6)}` : short;
const installDir = path.join(prefix, dirName);
const installedBinary = path.join(installDir, "jails");

// ---------- build (unless already installed) ----------
let info = readJson(path.join(installDir, "BUILD-INFO.json"));
if (fs.existsSync(installedBinary) && !opts.force) {
  log(`already installed: ${installedBinary} (use --force to rebuild)`);
} else {
  const work = opts.work ? expand(opts.work) : fs.mkdtempSync(path.join(os.tmpdir(), "jails-build-"));
  const src = path.join(work, "Jails");
  fs.mkdirSync(work, { recursive: true });
  fs.rmSync(src, { recursive: true, force: true });
  log(`fetching ${repo} @ ${commit} into ${src}`);
  run(GIT, ["init", "-q", src]);
  run(GIT, ["-C", src, "remote", "add", "origin", repo]);
  run(GIT, ["-C", src, "fetch", "-q", "--depth", "1", "origin", commit], { timeout: 600_000 });
  run(GIT, ["-C", src, "checkout", "-q", "FETCH_HEAD"]);
  if (run(GIT, ["-C", src, "submodule", "update", "-q", "--init", "--depth", "1"], { allowFail: true, timeout: 600_000 }).status !== 0) {
    log("shallow submodule fetch failed, retrying with full history");
    run(GIT, ["-C", src, "submodule", "update", "-q", "--init"], { timeout: 900_000 });
  }
  const commitDate = run(GIT, ["-C", src, "log", "-1", "--format=%cI"]).stdout.trim();
  const submodules = run(GIT, ["-C", src, "submodule", "status"]).stdout.trim().split("\n").filter(Boolean).map((l) => {
    const [sha, subPath] = l.trim().replace(/^[-+U]/, "").split(/\s+/);
    return { path: subPath, commit: sha };
  });
  for (const p of patches) {
    log(`applying ${p.file}`);
    run(GIT, ["-C", src, "apply", "--whitespace=nowarn", p.file]);
  }
  const version = /VERSION\s*::\s*"([^"]+)"/.exec(fs.readFileSync(path.join(src, "server", "main.jai"), "utf8"))?.[1] ?? "unknown";

  log(`building Jails ${version} (jai build.jai - -release)`);
  const t0 = Date.now();
  const build = run(jaiExe, ["build.jai", "-", "-release"], { cwd: src, timeout: 900_000, allowFail: true });
  const buildSeconds = (Date.now() - t0) / 1000;
  fs.writeFileSync(path.join(work, "build.log"), build.output);
  const built = path.join(src, "bin", "jails");
  if (build.status !== 0 || !fs.existsSync(built)) {
    console.error(build.output.split("\n").slice(-40).join("\n"));
    fail(`build failed with ${jaiVersion} (exit ${build.status}); build directory kept: ${work}\n` +
      `Pinned commit ${short} is known to build with Jai ${PINNED.testedWith}. Read ${path.join(jaiRoot, "CHANGELOG.txt")} ` +
      `for language changes since then, fix the source in ${src}, save the fix as a patch and rerun with --patch.`);
  }
  log(`built in ${buildSeconds.toFixed(1)} s`);

  fs.mkdirSync(installDir, { recursive: true });
  const tmp = `${installedBinary}.tmp-${process.pid}`;
  fs.copyFileSync(built, tmp);
  fs.chmodSync(tmp, 0o755);
  fs.renameSync(tmp, installedBinary);
  const licenses = path.join(installDir, "licenses");
  fs.mkdirSync(licenses, { recursive: true });
  for (const [from, to] of [["LICENSE", "Jails"], ["modules/jai_parser/LICENSE", "jai_parser"], ["modules/jaison/LICENSE", "jaison"], ["modules/unicode_utils/LICENSE", "jai-unicode"]]) {
    const f = path.join(src, from);
    if (fs.existsSync(f)) fs.copyFileSync(f, path.join(licenses, `${to}-LICENSE`));
  }
  fs.writeFileSync(path.join(installDir, "BUILD-LOG.txt"), build.output);
  info = {
    name: "Jails",
    version,
    repo,
    commit,
    commitDate,
    submodules,
    patches: patches.map(({ name, sha256 }) => ({ name, sha256 })),
    compiler: { root: jaiRoot, version: jaiVersion },
    platform: `${process.platform}-${process.arch}`,
    builtAt: new Date().toISOString(),
    buildSeconds,
    binaryBytes: fs.statSync(installedBinary).size,
    command: [installedBinary, "-jai_path", jaiRoot],
  };
  fs.writeFileSync(path.join(installDir, "BUILD-INFO.json"), JSON.stringify(info, null, 2) + "\n");
  log(`installed ${installedBinary}`);
  if (!opts.keepWork) fs.rmSync(work, { recursive: true, force: true });
  else log(`build directory kept: ${work}`);
}

// ---------- current symlink ----------
if (opts.current) {
  const current = path.join(prefix, "current");
  let isLink = false;
  try { isLink = fs.lstatSync(current).isSymbolicLink(); } catch { isLink = true; }
  if (!isLink) log(`not touching ${current}: it is not a symlink`);
  else {
    const tmpLink = `${current}.tmp-${process.pid}`;
    fs.rmSync(tmpLink, { force: true });
    fs.symlinkSync(dirName, tmpLink);
    fs.renameSync(tmpLink, current);
    log(`${current} -> ${dirName}`);
  }
}

// ---------- smoke test ----------
let smoke = null;
if (opts.smoke) {
  smoke = await smokeTest(installedBinary, jaiRoot);
  log(`smoke test: ${smoke.ok ? "PASS" : "FAIL"} (${smoke.checks.map((c) => `${c.name} ${c.ok ? "ok" : "FAILED"}`).join(", ")})`);
}

const summary = { ok: !smoke || smoke.ok, binary: installedBinary, installDir, info, smoke };
if (opts.json) console.log(JSON.stringify(summary, null, 2));
else {
  console.log(`Jails ${info?.version ?? "?"} @ ${short} for ${jaiVersion}: ${installedBinary}`);
  console.log(`Start it as: ${installedBinary} -jai_path ${jaiRoot}`);
}
process.exit(summary.ok ? 0 : 1);

// Start the server on a throw-away project and check the features an agent relies on.
async function smokeTest(binary, root) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "jails-smoke-"));
  const main = path.join(dir, "main.jai");
  const good = '#import "Basic";\n\nmain :: () {\n    print("smoke\\n");\n}\n';
  fs.writeFileSync(main, good);
  const uri = pathToFileURL(main).href;
  const checks = [];
  const check = (name, ok, detail) => checks.push({ name, ok: !!ok, ...(detail === undefined ? {} : { detail }) });

  const child = spawn(binary, ["-jai_path", root], { cwd: dir, stdio: ["pipe", "pipe", "pipe"] });
  let buf = Buffer.alloc(0);
  let nextId = 1;
  const pending = new Map();
  const notes = [];
  child.stdout.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      const end = buf.indexOf("\r\n\r\n");
      if (end < 0) return;
      const m = /Content-Length:\s*(\d+)/i.exec(buf.subarray(0, end).toString());
      if (!m) { buf = buf.subarray(end + 4); continue; }
      const len = Number(m[1]);
      if (buf.length < end + 4 + len) return;
      const msg = JSON.parse(buf.subarray(end + 4, end + 4 + len).toString());
      buf = buf.subarray(end + 4 + len);
      if (!msg.method && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); } else notes.push(msg);
    }
  });
  child.stderr.resume();
  const send = (obj) => {
    const body = JSON.stringify({ jsonrpc: "2.0", ...obj });
    child.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
  };
  const request = (method, params, timeout = 20_000) => new Promise((resolve) => {
    const id = nextId++;
    const timer = setTimeout(() => { pending.delete(id); resolve(null); }, timeout);
    pending.set(id, (msg) => { clearTimeout(timer); resolve(msg.result ?? null); });
    send({ id, method, params });
  });
  const notify = (method, params) => send({ method, params });
  const waitFor = async (pred, timeout) => {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      const hit = notes.find(pred);
      if (hit) return hit;
      await new Promise((r) => setTimeout(r, 100));
    }
    return null;
  };

  try {
    const t0 = Date.now();
    const init = await request("initialize", { processId: process.pid, rootUri: pathToFileURL(dir).href, workspaceFolders: [{ uri: pathToFileURL(dir).href, name: "smoke" }], capabilities: {} }, 60_000);
    const initializeMs = Date.now() - t0;
    check("initialize", init?.serverInfo?.name === "Jails", init?.serverInfo ?? "no answer");
    notify("initialized", {});
    check("metaprogram written", fs.existsSync(path.join(path.dirname(binary), "metaprogram", "jails_diagnostics.jai")));
    notify("textDocument/didOpen", { textDocument: { uri, languageId: "jai", version: 1, text: good } });
    const symbols = await request("textDocument/documentSymbol", { textDocument: { uri } });
    check("documentSymbol", Array.isArray(symbols) && symbols.some((s) => s.name === "main"));
    const def = await request("textDocument/definition", { textDocument: { uri }, position: { line: 3, character: 6 } });
    const target = (Array.isArray(def) ? def[0] : def)?.uri ?? "";
    check("definition into Basic", target.includes("/modules/Basic/"), target || "none");
    const bad = good.replace('    print("smoke\\n");', '    print("smoke\\n");\n    x: int = "not an int";');
    fs.writeFileSync(main, bad);
    notify("textDocument/didChange", { textDocument: { uri, version: 2 }, contentChanges: [{ text: bad }] });
    notify("textDocument/didSave", { textDocument: { uri } });
    const diag = await waitFor((m) => m.method === "textDocument/publishDiagnostics" && m.params.diagnostics.length > 0, 45_000);
    const first = diag?.params.diagnostics[0];
    check("diagnostics on save", first && first.range.start.line === 4, first ? `${first.range.start.line + 1}:${first.range.start.character + 1}${first.message}` : "none");
    return { ok: checks.every((c) => c.ok), initializeMs, checks };
  } finally {
    try { for (const pid of execFileSync("pgrep", ["-P", String(child.pid)], { encoding: "utf8" }).trim().split(/\s+/).filter(Boolean)) process.kill(Number(pid), "SIGTERM"); } catch {}
    await request("shutdown", null, 2000);
    notify("exit", null);
    child.stdin.end();
    await new Promise((r) => { const t = setTimeout(() => { child.kill("SIGKILL"); r(); }, 3000); child.on("exit", () => { clearTimeout(t); r(); }); });
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
