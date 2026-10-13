// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
//
// Drives a headless Chrome (sound muted) over the DevTools protocol, for testing
// the HTML player:  node test/drive.mjs <url> '<json steps>' [port]
// Steps: ["wait",ms] ["click",x,y] ["key",name,times] ["hold",name,ms] ["shot",file] ["js",expr]
//        ["castStart",dir] ... ["castStop"]  (screen recording: PNG frames + frames.txt with timestamps)
// Prints every network request the page makes, so tests can check that a player
// only loads its own local files. Requires Node.js 22+ (global WebSocket).
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [url, stepsJson = "[]", port = "9335"] = process.argv.slice(2);
const candidates = {
  darwin: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Chromium.app/Contents/MacOS/Chromium"],
  linux: ["/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser"],
  win32: ["C:/Program Files/Google/Chrome/Application/chrome.exe", "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"],
}[process.platform] || [];
const chromePath = process.env.CHROME || candidates.find((p) => fs.existsSync(p));
if (!chromePath) { console.error("Chrome not found; set CHROME=/path/to/chrome"); process.exit(2); }
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "gb2swf-chrome-"));
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--ignore-gpu-blocklist", "--enable-gpu"] : [];
const chrome = spawn(chromePath, ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--autoplay-policy=no-user-gesture-required", "--mute-audio", `--window-size=${process.env.WINDOW || "900,1000"}`, "--no-first-run",
  "--no-default-browser-check", "--disable-background-networking", "--disable-component-update", ...gpu, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws;
for (let i = 0; i < 100 && !ws; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
    const page = list.find((x) => x.type === "page");
    if (page) ws = new WebSocket(page.webSocketDebuggerUrl);
  } catch { /* not up yet */ }
  if (!ws) await sleep(100);
}
await new Promise((r) => (ws.onopen = r));
let id = 0;
const pending = new Map(), logs = [], requests = [];
let cast = null;
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
  else if (d.method === "Runtime.consoleAPICalled") logs.push(d.params.type + ": " + d.params.args.map((a) => a.value ?? a.description).join(" "));
  else if (d.method === "Runtime.exceptionThrown") logs.push("exception: " + (d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text));
  else if (d.method === "Network.requestWillBeSent") requests.push(d.params.request.url.slice(0, 120));
  else if (d.method === "Page.screencastFrame") {
    ws.send(JSON.stringify({ id: ++id, method: "Page.screencastFrameAck", params: { sessionId: d.params.sessionId } }));
    if (cast) {
      const f = `${cast.dir}/f${String(cast.n++).padStart(5, "0")}.png`;
      fs.writeFileSync(f, Buffer.from(d.params.data, "base64"));
      cast.list.push([f, d.params.metadata.timestamp]);
    }
  }
};
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Runtime.enable");
await send("Network.enable");
await send("Page.enable");
await send("Page.navigate", { url });
const codes = { ArrowDown: 40, ArrowUp: 38, ArrowLeft: 37, ArrowRight: 39, Enter: 13, Shift: 16, Tab: 9, Escape: 27 };
for (const [op, a, b] of JSON.parse(stepsJson)) {
  if (op === "wait") await sleep(a);
  if (op === "click") for (const type of ["mouseMoved", "mousePressed", "mouseReleased"]) await send("Input.dispatchMouseEvent", { type, x: a, y: b, button: "left", clickCount: 1 });
  if (op === "key" || op === "hold") {
    const kc = codes[a] || a.toUpperCase().charCodeAt(0);
    const text = a.length === 1 ? a : undefined;
    const code = text ? "Key" + a.toUpperCase() : a;
    for (let i = 0; i < (op === "key" ? b || 1 : 1); i++) {
      await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: a, code, windowsVirtualKeyCode: kc });
      if (text) await send("Input.dispatchKeyEvent", { type: "char", text, key: a });
      await sleep(op === "hold" ? b : 80);
      await send("Input.dispatchKeyEvent", { type: "keyUp", key: a, code, windowsVirtualKeyCode: kc });
      await sleep(40);
    }
  }
  if (op === "js") {
    const r = await send("Runtime.evaluate", { expression: a, awaitPromise: true, returnByValue: true });
    console.log("js: " + JSON.stringify(r.result?.result?.value ?? r.result?.exceptionDetails?.text));
  }
  if (op === "castStart") {
    fs.mkdirSync(a, { recursive: true });
    cast = { dir: a, n: 0, list: [] };
    await send("Page.startScreencast", { format: "png", everyNthFrame: 1 });
  }
  if (op === "castStop") {
    await send("Page.stopScreencast");
    // ffmpeg concat list: every frame with how long it was on screen
    const l = cast.list, lines = [];
    for (let i = 0; i < l.length; i++) {
      const dur = i + 1 < l.length ? l[i + 1][1] - l[i][1] : 0.04;
      lines.push(`file '${l[i][0]}'`, `duration ${dur.toFixed(4)}`);
    }
    if (l.length) lines.push(`file '${l[l.length - 1][0]}'`);
    fs.writeFileSync(cast.dir + "/frames.txt", lines.join("\n") + "\n");
    console.log(`cast ${l.length} frames`);
    cast = null;
  }
  if (op === "shot") {
    const s = await send("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(a, Buffer.from(s.result.data, "base64"));
    console.log("shot " + a);
  }
}
console.log("requests: " + JSON.stringify([...new Set(requests)]));
const shown = logs.filter((l) => !/^debug:/.test(l));
if (shown.length) console.log("console:\n" + shown.slice(0, 20).join("\n"));
chrome.kill();
await new Promise((r) => { chrome.on("exit", r); setTimeout(r, 3000); });
try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch { /* leftover temp dir */ }
process.exit(0);
