// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
//
// Developer/CI helper: downloads the test ROMs (tests/testroms.json) and the
// open-licensed homebrew games (tests/homebrew.json) into testroms/ and homebrew/.
// Every file is checked against its pinned SHA-256. This is the only part of the
// gb2swf repository that uses the network; gb2swf itself never does.
//
//   node scripts/fetch-testroms.mjs [--homebrew] [--only <text>]
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const only = args.includes("--only") ? args[args.indexOf("--only") + 1] : null;
const sha256 = (buf) => crypto.createHash("sha256").update(buf).digest("hex");
let failed = 0;

async function download(url) {
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  return Buffer.from(await res.arrayBuffer());
}

function have(file, hash) {
  return fs.existsSync(file) && sha256(fs.readFileSync(file)) === hash;
}

async function fetchFile(file, url, hash) {
  if (have(file, hash)) return true;
  if (!url) { console.log(`  missing (download by hand, see the manifest): ${path.relative(root, file)}`); return false; }
  const buf = await download(url);
  if (sha256(buf) !== hash) { console.log(`  CHECKSUM MISMATCH, not saved: ${url}`); failed++; return false; }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, buf);
  console.log(`  ok ${path.relative(root, file)}`);
  return true;
}

const manifest = JSON.parse(fs.readFileSync(path.join(root, "tests/testroms.json"), "utf8"));
for (const suite of manifest.suites) {
  if (only && !suite.name.includes(only)) continue;
  console.log(suite.name);
  const dir = path.join(root, "testroms", suite.dir);
  if (suite.archive) {
    const missing = suite.tests.filter((t) => !have(path.join(dir, t.rom), t.sha256));
    if (missing.length) {
      const buf = await download(suite.archive.url);
      if (sha256(buf) !== suite.archive.sha256) { console.log("  ARCHIVE CHECKSUM MISMATCH"); failed++; continue; }
      // Unpack into an empty temporary folder with the system tar, then copy only the listed ROMs
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "gb2swf-roms-"));
      const arc = path.join(tmp, "archive.tar.gz");
      fs.writeFileSync(arc, buf);
      execFileSync("tar", ["xzf", arc, "-C", tmp]);
      for (const t of missing) {
        const src = path.join(tmp, suite.archive.strip || "", t.rom);
        if (!fs.existsSync(src) || sha256(fs.readFileSync(src)) !== t.sha256) { console.log(`  not found or wrong checksum in archive: ${t.rom}`); failed++; continue; }
        fs.mkdirSync(path.dirname(path.join(dir, t.rom)), { recursive: true });
        fs.copyFileSync(src, path.join(dir, t.rom));
      }
      fs.rmSync(tmp, { recursive: true, force: true });
      console.log(`  ok ${missing.length} files from the archive`);
    }
  } else {
    for (const t of suite.tests) await fetchFile(path.join(dir, t.rom), t.url, t.sha256);
  }
  for (const f of suite.files || []) await fetchFile(path.join(dir, f.file), f.url, f.sha256);
}

if (args.includes("--homebrew")) {
  console.log("Homebrew");
  const hb = JSON.parse(fs.readFileSync(path.join(root, "tests/homebrew.json"), "utf8"));
  for (const g of hb.games) {
    if (only && !g.id.includes(only)) continue;
    await fetchFile(path.join(root, "homebrew", g.file), g.url, g.sha256);
  }
}
if (failed) { console.log(`${failed} problem(s)`); process.exit(1); }
console.log("done");
