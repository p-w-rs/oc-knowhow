#!/usr/bin/env node
// jails-query.mjs: one-shot command-line front end for the Jails language server (Jai), so an agent (or an
// OpenCode V2 plugin tool) can navigate Jai code without an editor. Prototype; tested with Jails 0.2.22 @ 42fa76c8
// and Jai beta 0.2.032 on macOS arm64 and Linux x86-64. Dependency-free Node >= 20 (run it with
// `pixi exec --spec nodejs=24 node jails-query.mjs ...`).
//
//   jails-query.mjs [options] symbols <file>                      document symbols (tree)
//   jails-query.mjs [options] def <file>:<line>:<col>             go to definition (1-based line and column)
//   jails-query.mjs [options] def <file> <identifier> [--line N]  definition of the first use of <identifier>
//   jails-query.mjs [options] complete <file>:<line>:<col>        completion items at a position
//   jails-query.mjs [options] sig <file>:<line>:<col>             signature help inside a call
//   jails-query.mjs [options] wsym <query>                        workspace symbols (project files only)
//   jails-query.mjs [options] diag                                compile the build root through Jails (first error only)
//
// Options: --root <dir> (project root; default: nearest parent of the first file argument, or the current
// directory, containing jails.json, else that file's directory), --jails <binary> (default
// ~/jai/tools/jails/current/jails or $JAILS_BIN), --jai <compiler root> (default ~/jai/current or $JAI_ROOT),
// --json (raw LSP results), --timeout <ms> (per request, default 15000), --verbose (print Jails log messages),
// --stats (print startup time, files parsed and the server's resident memory to stderr).
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const argv = process.argv.slice(2);
const opts = { json: false, verbose: false, timeout: 15000 };
const rest = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--json") opts.json = true;
  else if (a === "--verbose") opts.verbose = true;
  else if (a === "--stats") opts.stats = true;
  else if (["--root", "--jails", "--jai", "--timeout", "--line"].includes(a)) opts[a.slice(2)] = argv[++i];
  else rest.push(a);
}
const [command, ...params] = rest;
const usage = () => {
  const head = fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").filter((l) => l.startsWith("//")).map((l) => l.slice(3));
  console.error(head.join("\n"));
  process.exit(2);
};
if (!command) usage();

const home = os.homedir();
const expand = (p) => (p ? path.resolve(p.replace(/^~(?=$|\/)/, home)) : p);
const JAILS = expand(opts.jails ?? process.env.JAILS_BIN ?? "~/jai/tools/jails/current/jails");
const JAI = expand(opts.jai ?? process.env.JAI_ROOT ?? "~/jai/current");
if (!fs.existsSync(JAILS)) { console.error(`Jails binary not found: ${JAILS} (build it with jails-build.mjs)`); process.exit(2); }
if (!fs.existsSync(path.join(JAI, "modules"))) { console.error(`Jai compiler root not found: ${JAI}`); process.exit(2); }

// "<file>:<line>:<col>" -> { file, line, col } (1-based).
function parseLocation(spec) {
  const m = /^(.*?):(\d+):(\d+)$/.exec(spec ?? "");
  if (!m) return null;
  return { file: path.resolve(m[1]), line: Number(m[2]), col: Number(m[3]) };
}
const firstFile = params.map((p) => parseLocation(p)?.file ?? path.resolve(p)).find((p) => p.endsWith(".jai") && fs.existsSync(p));
function findRoot(start) {
  let dir = start;
  for (;;) {
    if (fs.existsSync(path.join(dir, "jails.json"))) return dir;
    const up = path.dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
}
const startDir = firstFile ? path.dirname(firstFile) : process.cwd();
const ROOT = expand(opts.root) ?? findRoot(startDir) ?? startDir;

// ---- minimal LSP connection ----
const child = spawn(JAILS, ["-jai_path", JAI], { cwd: ROOT, stdio: ["pipe", "pipe", "pipe"] });
child.on("error", (e) => { console.error(`cannot start Jails: ${e.message}`); process.exit(2); });
let buf = Buffer.alloc(0);
let nextId = 1;
const pending = new Map();
const listeners = [];
const logs = [];
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
    if (msg.method === "window/logMessage") {
      logs.push(msg.params.message);
      if (opts.verbose) console.error(`[jails] ${msg.params.message}`);
    }
    if (!msg.method && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    else for (const l of [...listeners]) l(msg);
  }
});
child.stderr.on("data", (d) => opts.verbose && process.stderr.write(d));
const send = (obj) => {
  const body = JSON.stringify({ jsonrpc: "2.0", ...obj });
  child.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
};
// Jails never answers methods it does not implement (hover, references, ...), so every request has a timeout.
const request = (method, params, timeout = Number(opts.timeout)) => new Promise((resolve, reject) => {
  const id = nextId++;
  const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method}: no answer within ${timeout} ms`)); }, timeout);
  pending.set(id, (msg) => { clearTimeout(timer); msg.error ? reject(new Error(`${method}: ${msg.error.message}`)) : resolve(msg.result); });
  send({ id, method, params });
});
const notify = (method, params) => send({ method, params });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Jails compiles the build root in the background on every start (diagnostics). Stop that compiler when we leave,
// so a query never leaves an orphaned compile behind (a custom build.jai could otherwise still write output files).
function killCompilerChildren() {
  let pids = [];
  try { pids = execFileSync("pgrep", ["-P", String(child.pid)], { encoding: "utf8" }).trim().split(/\s+/).filter(Boolean); } catch {}
  for (const pid of pids) { try { process.kill(Number(pid), "SIGTERM"); } catch {} }
  return pids.length;
}
async function shutdown(code) {
  const killed = killCompilerChildren();
  if (killed && opts.verbose) console.error(`[jails-query] stopped ${killed} background compile(s)`);
  try { await request("shutdown", null, 2000); notify("exit", null); } catch {}
  child.stdin.end();
  setTimeout(() => { child.kill(); process.exit(code); }, 300).unref();
  child.on("exit", () => process.exit(code));
}

const uriOf = (file) => pathToFileURL(file).href;
const fileOf = (uri) => (uri.startsWith("file://") ? decodeURIComponent(uri.slice(7)) : uri);
const rel = (file) => {
  const f = fileOf(file);
  if (f.startsWith(ROOT + "/")) return path.relative(process.cwd(), f) || f;
  if (f.startsWith(JAI + "/")) return f.replace(JAI, "$JAI");
  return f;
};
const KIND = { 2: "module", 5: "class", 8: "field", 10: "enum", 12: "procedure", 13: "variable", 14: "constant", 22: "enum member", 23: "struct" };
const CKIND = { 2: "method", 3: "procedure", 5: "field", 6: "variable", 7: "class", 9: "module", 13: "enum", 14: "keyword", 20: "enum member", 21: "constant", 22: "struct" };

async function open(file) {
  const text = fs.readFileSync(file, "utf8");
  notify("textDocument/didOpen", { textDocument: { uri: uriOf(file), languageId: "jai", version: 1, text } });
  await sleep(50);
  return text;
}
const position = (line, col) => ({ line: line - 1, character: col - 1 });
const out = (v) => console.log(typeof v === "string" ? v : JSON.stringify(v, null, 2));

const initStarted = Date.now();
await request("initialize", {
  processId: process.pid,
  clientInfo: { name: "jails-query", version: "0.1" },
  rootUri: uriOf(ROOT),
  workspaceFolders: [{ uri: uriOf(ROOT), name: path.basename(ROOT) }],
  capabilities: {},
}, 120000);
notify("initialized", {});
const initMs = Date.now() - initStarted;
if (opts.verbose) console.error(`[jails-query] root ${ROOT}, initialize took ${initMs} ms`);
function printStats() {
  if (!opts.stats) return;
  let rss = "?";
  try { rss = `${Math.round(Number(execFileSync("ps", ["-o", "rss=", "-p", String(child.pid)], { encoding: "utf8" }).trim()) / 1024)} MB`; } catch {}
  console.error(`[stats] root=${ROOT} initialize=${initMs} ms rss=${rss}`);
}

try {
  switch (command) {
    case "symbols": {
      const file = path.resolve(params[0] ?? usage());
      await open(file);
      const result = await request("textDocument/documentSymbol", { textDocument: { uri: uriOf(file) } });
      if (opts.json) { out(result); break; }
      const walk = (syms, depth) => (syms ?? []).forEach((s) => {
        console.log(`${"  ".repeat(depth)}${s.name}  [${KIND[s.kind] ?? s.kind}]${s.detail ? `  ${s.detail}` : ""}  :${s.range.start.line + 1}`);
        walk(s.children, depth + 1);
      });
      walk(result, 0);
      break;
    }
    case "def": {
      let loc = parseLocation(params[0]);
      if (!loc) {
        const file = path.resolve(params[0] ?? usage());
        const ident = params[1] ?? usage();
        const lines = fs.readFileSync(file, "utf8").split("\n");
        const from = Number(opts.line ?? 1) - 1;
        const re = new RegExp(`(?<![A-Za-z0-9_])${ident.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z0-9_])`);
        for (let i = from; i < lines.length && !loc; i++) {
          const code = lines[i].replace(/\/\/.*$/, "");
          const m = re.exec(code);
          if (m) loc = { file, line: i + 1, col: m.index + 1 + Math.floor(ident.length / 2) };
        }
        if (!loc) throw new Error(`'${ident}' not found in ${file}`);
      }
      await open(loc.file);
      const result = await request("textDocument/definition", { textDocument: { uri: uriOf(loc.file) }, position: position(loc.line, loc.col) });
      if (opts.json) { out(result); break; }
      const list = Array.isArray(result) ? result : result ? [result] : [];
      if (!list.length) { console.log("no definition found"); process.exitCode = 1; break; }
      for (const l of list) {
        const uri = l.uri ?? l.targetUri;
        const r = l.range ?? l.targetRange;
        const target = fileOf(uri);
        const src = fs.existsSync(target) ? fs.readFileSync(target, "utf8").split("\n")[r.start.line] ?? "" : "";
        console.log(`${rel(uri)}:${r.start.line + 1}:${r.start.character + 1}: ${src.trim()}`);
      }
      break;
    }
    case "complete":
    case "sig": {
      const loc = parseLocation(params[0]) ?? usage();
      await open(loc.file);
      const method = command === "sig" ? "textDocument/signatureHelp" : "textDocument/completion";
      const result = await request(method, { textDocument: { uri: uriOf(loc.file) }, position: position(loc.line, loc.col), context: { triggerKind: 1 } });
      if (opts.json) { out(result); break; }
      if (command === "sig") {
        for (const s of result?.signatures ?? []) console.log(`${s.label}${typeof s.activeParameter === "number" ? `  (active parameter ${s.activeParameter + 1})` : ""}`);
        if (!result?.signatures?.length) { console.log("no signature"); process.exitCode = 1; }
        break;
      }
      const items = Array.isArray(result) ? result : result?.items ?? [];
      // Jails does not filter by the typed prefix: do it here.
      const line = fs.readFileSync(loc.file, "utf8").split("\n")[loc.line - 1] ?? "";
      const prefix = /[A-Za-z0-9_]*$/.exec(line.slice(0, loc.col - 1))[0];
      const shown = items.filter((i) => i.label.startsWith(prefix));
      for (const i of shown) console.log(`${i.label}  [${CKIND[i.kind] ?? i.kind}]${i.detail ? `  ${i.detail}` : ""}`);
      if (!shown.length) { console.log(`no completions${prefix ? ` for '${prefix}'` : ""}`); process.exitCode = 1; }
      break;
    }
    case "wsym": {
      const result = await request("workspace/symbol", { query: params[0] ?? usage() });
      if (opts.json) { out(result); break; }
      for (const s of result ?? []) console.log(`${s.name}  [${KIND[s.kind] ?? s.kind}]  ${rel(s.location.uri)}:${s.location.range.start.line + 1}`);
      if (!result?.length) { console.log("no symbols"); process.exitCode = 1; }
      break;
    }
    case "diag": {
      // initialize already started one compile of the build root. Jails publishes only when there is an error,
      // so wait for a publish or for its compiler child process to finish.
      const diags = [];
      listeners.push((m) => { if (m.method === "textDocument/publishDiagnostics" && m.params.diagnostics.length) diags.push(m.params); });
      const deadline = Date.now() + 40000;
      let sawChild = false;
      while (Date.now() < deadline && !diags.length) {
        await sleep(150);
        let children = "";
        try { children = execFileSync("pgrep", ["-P", String(child.pid)], { encoding: "utf8" }).trim(); } catch {}
        if (children) sawChild = true;
        else if (sawChild || logs.some((l) => l.startsWith("Running diagnostics"))) { await sleep(300); break; }
      }
      if (!logs.some((l) => l.startsWith("Running diagnostics"))) { console.log("no build root found (add build_root to jails.json)"); process.exitCode = 2; break; }
      if (opts.json) { out(diags); break; }
      if (!diags.length) { console.log("ok: no errors"); break; }
      for (const d of diags) for (const x of d.diagnostics) console.log(`${rel(d.uri)}:${x.range.start.line + 1}:${x.range.start.character + 1}: error:${x.message}`);
      process.exitCode = 1;
      break;
    }
    default:
      usage();
  }
} catch (e) {
  console.error(`error: ${e.message}`);
  process.exitCode = 1;
}
printStats();
await shutdown(process.exitCode ?? 0);
