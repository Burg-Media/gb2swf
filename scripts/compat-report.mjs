// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
//
// Builds every game in tests/homebrew.json, measures it in headless Chrome + Ruffle
// and writes the compatibility table (docs/compatibility.md), together with the
// test ROM results. Needs the games (scripts/fetch-testroms.mjs --homebrew, plus
// the itch.io downloads by hand) and Chrome.
//
//   node scripts/compat-report.mjs [--only <id>] [--out build/compat]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const opt = (n, d) => (args.includes(n) ? args[args.indexOf(n) + 1] : d);
const only = opt("--only", null);
const outDir = path.resolve(opt("--out", path.join(root, "build/compat")));
const node = process.execPath;
const cli = path.join(root, "lib/gb2swf.js");
const hb = JSON.parse(fs.readFileSync(path.join(root, "tests/homebrew.json"), "utf8"));
fs.mkdirSync(outDir, { recursive: true });

function sh(cmd, argv) {
  try { return { ok: true, out: execFileSync(cmd, argv, { encoding: "utf8", maxBuffer: 64 << 20 }) }; }
  catch (e) { return { ok: false, out: (e.stdout || "") + (e.stderr || "") }; }
}

const rows = [];
for (const g of hb.games) {
  if (only && g.id !== only) continue;
  const rom = path.join(root, "homebrew", g.file);
  if (!fs.existsSync(rom)) { console.log(`skip ${g.id}: ${g.file} not present`); continue; }
  console.log(`== ${g.name}`);
  const build = sh(node, [cli, rom, "-o", outDir, "--name", g.id]);
  const report = JSON.parse(fs.readFileSync(path.join(outDir, `${g.id}_work`, "report.json"), "utf8"));
  // In the browser: wait for the title screen, press Start and A a few times, then measure twice
  const steps = [["wait", 4000], ["key", "Enter", 1], ["wait", 1500], ["key", "x", 2], ["wait", 1500], ["key", "Enter", 1],
    ["wait", 4000], ["js", "JSON.stringify(GB2SWF.stats())"], ["wait", 4000], ["js", "JSON.stringify(GB2SWF.stats())"],
    ["shot", path.join(outDir, `${g.id}.png`)]];
  const drive = sh(node, [path.join(root, "test/drive.mjs"), "file://" + path.join(outDir, `${g.id}_html/index.html`), JSON.stringify(steps)]);
  const stats = [...drive.out.matchAll(/^js: "(.*)"$/gm)].map((m) => JSON.parse(JSON.parse(`"${m[1]}"`)));
  const external = (drive.out.match(/^requests: (.*)$/m) || [, "[]"])[1];
  const offline = JSON.parse(external).every((u) => u.startsWith("file://"));
  const last = stats[stats.length - 1] || {};
  rows.push({
    g, report, ok: build.ok && report.checked !== false && !report.fallback,
    fps: last.fps, ms: last.msPerFrame, offline,
    errors: /exception|panic|ERROR/i.test(drive.out.replace(/^log: .*WebAssembly extensions.*$/gm, "")),
  });
  console.log(`   rec ${report.coverage?.validation}%  fps ${last.fps}  ${last.msPerFrame} ms/frame  ${Math.round(report.swfBytes / 1024)} KiB  offline=${offline}`);
}

const testroms = sh(node, [cli, "dev", "testroms", "--rec", "--md", path.join(outDir, "testroms.md")]);
const cpu = os.cpus()[0].model.trim();
const ruffle = JSON.parse(fs.readFileSync(path.join(root, "player/ruffle/package.json"), "utf8")).version;
const version = fs.readFileSync(path.join(root, "src/tool/Version.hx"), "utf8").match(/VERSION = "([^"]+)"/)[1];
const date = new Date().toISOString().slice(0, 10);

let md = `# Compatibility

Measured on ${date} with gb2swf ${version}, Ruffle ${ruffle}, headless Chrome on
${os.platform() === "darwin" ? "macOS" : os.platform()} (${cpu}). Everything in this file is produced by
\`node scripts/compat-report.mjs\` and can be reproduced with the same files.

## Homebrew games

All games below have open licenses that allow redistribution; see each game's page.
"Recompiled" is the share of executed instructions that ran as recompiled code on
an input sequence the profiler had not seen (the rest ran on the interpreter).
"ms/frame" is the time the SWF spent per Game Boy frame (emulation, sound and
picture); the budget for full speed is 16.7 ms. Measured during the first seconds
of play with automated input, so the numbers describe that scene, not the whole game.

| Game | License | Link | Works | Recompiled | fps in Ruffle | ms/frame | SWF size | Notes |
|---|---|---|---|---|---|---|---|---|
`;
for (const r of rows) {
  if (r.g.public === false) continue; // tested, but not listed (licence of some assets unclear)
  const works = r.ok && r.fps >= 55 && !r.errors && r.offline ? "yes" : (r.ok ? "partly (see notes)" : "no");
  md += `| ${r.g.name} (${r.g.hardware}) | ${r.g.license} | ${r.g.page} | ${works} | ${r.report.coverage ? r.report.coverage.validation + "%" : "interpreter only"} | ${r.fps ?? "?"} | ${r.ms ?? "?"} | ${Math.round(r.report.swfBytes / 1024)} KiB | ${r.g.note || ""} |\n`;
}
md += `
"Works" means: the build passed the interpreter-vs-recompiled check, the game ran
at full speed in Ruffle without errors, and the page loaded only its own local
files. It does not mean every level was played through.

## Test ROMs

Interpreter: the ROM run on gb2swf's interpreter. Recompiled: the ROM profiled,
recompiled, checked and run from its recompiled code (not run for Mooneye and
rtc3test). Failures listed with a reason are known limitations.

${fs.existsSync(path.join(outDir, "testroms.md")) ? fs.readFileSync(path.join(outDir, "testroms.md"), "utf8") : "(not run)"}
`;
fs.mkdirSync(path.join(root, "docs"), { recursive: true });
fs.writeFileSync(path.join(root, "docs/compatibility.md"), md);
fs.writeFileSync(path.join(outDir, "compat.json"), JSON.stringify(rows.map((r) => ({ id: r.g.id, ok: r.ok, fps: r.fps, ms: r.ms, offline: r.offline, coverage: r.report.coverage, swfBytes: r.report.swfBytes })), null, 1));
console.log("docs/compatibility.md written" + (testroms.ok ? "" : " (test ROMs: unexpected failures)"));
