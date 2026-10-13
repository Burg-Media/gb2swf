// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
//
// Builds the release packages: release/gb2swf-<version>-<platform>.zip with the
// bundled Node.js for that platform, plus SHA256SUMS.txt. The Haxe compiler is
// not bundled: users install it themselves from haxe.org.
//
//   node scripts/make-release.mjs [--only <platform>]
//
// Needs: haxe (to build lib/gb2swf.js), zip, tar and unzip on the PATH, and the
// network for the first run (toolchain downloads are cached in build/downloads
// and checked against pinned SHA-256 sums).
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const version = fs.readFileSync(path.join(root, "src/tool/Version.hx"), "utf8").match(/VERSION = "([^"]+)"/)[1];
const args = process.argv.slice(2);
const only = args.includes("--only") ? args[args.indexOf("--only") + 1] : null;
const dl = path.join(root, "build/downloads");
const stage = path.join(root, "build/stage");
const out = path.join(root, "release");

const NODE = "24.21.0";
const nodeUrl = (f) => `https://nodejs.org/dist/v${NODE}/${f}`;
const PLATFORMS = {
  "macos-arm64": { node: ["node-v24.21.0-darwin-arm64.tar.gz", "bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057"] },
  "macos-x64": { node: ["node-v24.21.0-darwin-x64.tar.gz", "1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097"] },
  "linux-x64": { node: ["node-v24.21.0-linux-x64.tar.xz", "fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6"] },
  "linux-arm64": { node: ["node-v24.21.0-linux-arm64.tar.xz", "6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2"] },
  "windows-x64": { node: ["node-v24.21.0-win-x64.zip", "158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541"] },
};

const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { stdio: ["ignore", "pipe", "inherit"], ...opts });

async function fetchPinned(url, file, hash) {
  const dst = path.join(dl, file);
  if (fs.existsSync(dst) && sha256(dst) === hash) return dst;
  console.log("downloading " + url);
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`${res.status} for ${url}`);
  fs.mkdirSync(dl, { recursive: true });
  fs.writeFileSync(dst, Buffer.from(await res.arrayBuffer()));
  if (sha256(dst) !== hash) { fs.rmSync(dst); throw new Error("checksum mismatch: " + file); }
  return dst;
}

function extract(archive, into) {
  fs.rmSync(into, { recursive: true, force: true });
  fs.mkdirSync(into, { recursive: true });
  if (archive.endsWith(".zip")) run("unzip", ["-q", archive, "-d", into]);
  else run("tar", ["xf", archive, "-C", into]);
  const entries = fs.readdirSync(into);
  return entries.length === 1 ? path.join(into, entries[0]) : into;
}

function copy(src, dst) {
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.cpSync(src, dst, { recursive: true });
}

// ---------------------------------------------------------------- build the tool
console.log(`gb2swf ${version}`);
run("haxe", ["build-tool.hxml"], { cwd: root });
// Prepare the offline Ruffle module once (player/ruffle/ruffle-wasm.js)
run(process.execPath, ["lib/gb2swf.js", "dev", "player-cache"], { cwd: root });
fs.mkdirSync(out, { recursive: true });

const SH = `#!/bin/sh
# gb2swf launcher: runs lib/gb2swf.js with the Node.js bundled in toolchain/.
self="$0"
while [ -h "$self" ]; do
  link=$(readlink "$self")
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
DIR=$(cd "$(dirname "$self")" && pwd)
exec "$DIR/toolchain/node/node" "$DIR/lib/gb2swf.js" "$@"
`;
const CMD = `@echo off
rem gb2swf launcher: runs lib\\gb2swf.js with the Node.js bundled in toolchain\\.
rem You can also drag a .gb or .gbc file onto this file.
setlocal
set "DIR=%~dp0"
"%DIR%toolchain\\node\\node.exe" "%DIR%lib\\gb2swf.js" %*
set "RC=%ERRORLEVEL%"
rem Keep the window open when started from Explorer (double click or drag and drop)
echo %CMDCMDLINE% | find /i "/c" >nul && pause
exit /b %RC%
`;

const docs = ["README.md", "LICENSE", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md", "LEGAL.md"];
const sums = [];
for (const [plat, p] of Object.entries(PLATFORMS)) {
  if (only && plat !== only) continue;
  const win = plat.startsWith("windows");
  const name = `gb2swf-${version}-${plat}`;
  const dir = path.join(stage, name);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  for (const f of docs) copy(path.join(root, f), path.join(dir, f));
  copy(path.join(root, "docs"), path.join(dir, "docs"));
  copy(path.join(root, "lib/gb2swf.js"), path.join(dir, "lib/gb2swf.js"));
  for (const f of ["src/gb", "src/swf", "src/tool", "build-tool.hxml"]) copy(path.join(root, f), path.join(dir, f));
  for (const f of ["index.html", "gb2swf-player.js", "gb2swf-player.css", "gb2swf-audio.js"]) copy(path.join(root, "player", f), path.join(dir, "player", f));
  for (const f of ["ruffle.js", "ruffle-wasm.js", "LICENSE_MIT", "LICENSE_APACHE", "README.md"]) copy(path.join(root, "player/ruffle", f), path.join(dir, "player/ruffle", f));

  // Node.js: only the program and its license
  const nodeDir = extract(await fetchPinned(nodeUrl(p.node[0]), p.node[0], p.node[1]), path.join(stage, "x-node"));
  copy(path.join(nodeDir, win ? "node.exe" : "bin/node"), path.join(dir, "toolchain/node", win ? "node.exe" : "node"));
  copy(path.join(nodeDir, "LICENSE"), path.join(dir, "toolchain/node/LICENSE"));
  copy(path.join(root, "scripts/toolchain-README.md"), path.join(dir, "toolchain/README.md"));
  if (win) fs.writeFileSync(path.join(dir, "gb2swf.cmd"), CMD.replace(/\n/g, "\r\n"));
  else {
    fs.writeFileSync(path.join(dir, "gb2swf"), SH);
    fs.chmodSync(path.join(dir, "gb2swf"), 0o755);
    fs.chmodSync(path.join(dir, "toolchain/node/node"), 0o755);
  }
  const zip = path.join(out, name + ".zip");
  fs.rmSync(zip, { force: true });
  run("zip", ["-q", "-r", "-X", "-9", zip, name], { cwd: stage });
  console.log(`${name}.zip  ${(fs.statSync(zip).size / 1048576).toFixed(1)} MB`);
  fs.rmSync(dir, { recursive: true, force: true });
}
fs.rmSync(path.join(stage, "x-node"), { recursive: true, force: true });

for (const f of fs.readdirSync(out).sort())
  if (f.startsWith("gb2swf-") && f.endsWith(".zip")) sums.push(`${sha256(path.join(out, f))}  ${f}`);
fs.writeFileSync(path.join(out, "SHA256SUMS.txt"), sums.join("\n") + "\n");
console.log("release/SHA256SUMS.txt written");
