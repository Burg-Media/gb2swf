// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
//
// HTML player for a gb2swf game. Runs the SWF in Ruffle (self-hosted, in ruffle/)
// and adds controls, gamepad and touch input, save files and input recording.
// Everything is local: this page makes no requests to other servers.
(function () {
  "use strict";
  const game = window.GB2SWF_GAME;
  const $ = (id) => document.getElementById(id);
  const BUTTONS = ["right", "left", "up", "down", "a", "b", "select", "start"];
  const LABELS = { up: "Up", down: "Down", left: "Left", right: "Right", a: "A", b: "B", start: "Start", select: "Select" };
  const DEFAULT_KEYS = { up: [38], down: [40], left: [37], right: [39], a: [88], b: [90], start: [13], select: [16] };
  const store = {
    get(k) { try { return JSON.parse(localStorage.getItem("gb2swf:" + k)); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem("gb2swf:" + k, JSON.stringify(v)); } catch (e) { /* private mode: not remembered */ } },
  };

  // ---------------------------------------------------------------- loading Ruffle offline
  // Browsers block fetch() on file:// pages. Ruffle fetches its WebAssembly module,
  // so hand it the copy that ruffle-wasm.js put on the page (gzip + base64).
  function b64bytes(s) {
    const bin = atob(s), out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  const realFetch = window.fetch ? window.fetch.bind(window) : null;
  window.fetch = function (input, init) {
    const url = typeof Request !== "undefined" && input instanceof Request ? input.url : String(input);
    if (/\.wasm(\?|$)/.test(url) && window.GB2SWF_RUFFLE_WASM) {
      const gz = new Blob([b64bytes(window.GB2SWF_RUFFLE_WASM)]);
      const body = gz.stream().pipeThrough(new DecompressionStream("gzip"));
      return Promise.resolve(new Response(body, { status: 200, headers: { "Content-Type": "application/wasm" } }));
    }
    return realFetch ? realFetch(input, init) : Promise.reject(new Error("fetch unavailable"));
  };
  // Only the "MVP" build of Ruffle's WebAssembly is included. Ruffle picks its build
  // by probing WebAssembly features with tiny test modules; answer those with "no".
  const realValidate = WebAssembly.validate.bind(WebAssembly);
  WebAssembly.validate = (bytes) => (bytes && bytes.byteLength < 64 ? false : realValidate(bytes));

  window.RufflePlayer = window.RufflePlayer || {};
  window.RufflePlayer.config = {
    publicPath: "ruffle/",
    polyfills: false,
    autoplay: "on",
    unmuteOverlay: "hidden",
    splashScreen: false,
    contextMenu: "off",
    letterbox: "on",
    warnOnUnsupportedContent: false,
    showSwfDownload: false,
    openUrlMode: "deny",
    upgradeToHttps: false,
    logLevel: "error",
    quality: "low",
  };

  // ---------------------------------------------------------------- helpers
  let player = null;
  const call = (name, ...args) => {
    try { return player && typeof player[name] === "function" ? player[name](...args) : undefined; } catch (e) { return undefined; }
  };
  function download(name, data, type) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([data], { type }));
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }
  function toggle(btn, panel) {
    const open = panel.hidden;
    for (const p of document.querySelectorAll(".panel")) p.hidden = true;
    for (const b of document.querySelectorAll("[aria-expanded]")) b.setAttribute("aria-expanded", "false");
    panel.hidden = !open;
    btn.setAttribute("aria-expanded", String(open));
    if (!open) focusGame();
  }
  function focusGame() { if (player) player.focus(); }

  // ---------------------------------------------------------------- keys
  let keys = Object.assign({}, DEFAULT_KEYS, store.get("keys") || {});
  let waiting = null;
  const keyName = (c) => ({ 37: "←", 38: "↑", 39: "→", 40: "↓", 13: "Enter", 16: "Shift", 17: "Ctrl", 18: "Alt", 32: "Space", 8: "Backspace", 9: "Tab" })[c]
    || (c >= 48 && c <= 90 ? String.fromCharCode(c) : "key " + c);
  const keysParam = () => BUTTONS.map((b) => b + ":" + (keys[b] || []).join(",")).join(";");
  function renderKeys() {
    const list = $("keylist");
    list.innerHTML = "";
    for (const b of ["up", "down", "left", "right", "a", "b", "start", "select"]) {
      const btn = document.createElement("button");
      btn.className = "keybtn" + (waiting === b ? " wait" : "");
      btn.textContent = LABELS[b] + ": " + (waiting === b ? "press a key…" : (keys[b] || []).map(keyName).join(", "));
      btn.onclick = () => { waiting = b; renderKeys(); };
      list.appendChild(btn);
    }
  }
  window.addEventListener("keydown", (e) => {
    if (!waiting) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.keyCode !== 27) {
      for (const b of BUTTONS) keys[b] = (keys[b] || []).filter((c) => c !== e.keyCode);
      keys[waiting] = [e.keyCode];
      store.set("keys", keys);
      call("gbSetKeys", keysParam());
    }
    waiting = null;
    renderKeys();
  }, true);

  // Arrow keys and space must not scroll the page while the game has the keyboard
  window.addEventListener("keydown", (e) => {
    if (player && document.activeElement === player && [32, 33, 34, 37, 38, 39, 40].includes(e.keyCode)) e.preventDefault();
  });

  // ---------------------------------------------------------------- gamepad and touch
  let padMask = 0, touchMask = 0, lastSent = -1;
  function pollPads() {
    let m = 0;
    for (const gp of (navigator.getGamepads ? navigator.getGamepads() : [])) {
      if (!gp) continue;
      const p = (i) => gp.buttons[i] && gp.buttons[i].pressed;
      if (p(1) || p(3)) m |= 16;   // A: right / top face button
      if (p(0) || p(2)) m |= 32;   // B: bottom / left face button
      if (p(8)) m |= 64;
      if (p(9)) m |= 128;
      if (p(12) || gp.axes[1] < -0.5) m |= 4;
      if (p(13) || gp.axes[1] > 0.5) m |= 8;
      if (p(14) || gp.axes[0] < -0.5) m |= 2;
      if (p(15) || gp.axes[0] > 0.5) m |= 1;
    }
    padMask = m;
    const all = padMask | touchMask;
    if (all !== lastSent) { lastSent = all; call("gbPad", all); }
    requestAnimationFrame(pollPads);
  }
  function setupTouch() {
    const pad = $("pad");
    if (!matchMedia("(pointer: coarse)").matches) return;
    pad.hidden = false;
    const active = new Map();
    const update = () => { touchMask = 0; for (const k of active.values()) touchMask |= k; };
    const hit = (x, y) => { const el = document.elementFromPoint(x, y); return el && el.dataset && el.dataset.k ? +el.dataset.k : 0; };
    const handle = (e) => {
      e.preventDefault();
      for (const t of e.changedTouches) {
        if (e.type === "touchend" || e.type === "touchcancel") active.delete(t.identifier);
        else active.set(t.identifier, hit(t.clientX, t.clientY));
      }
      update();
    };
    for (const ev of ["touchstart", "touchmove", "touchend", "touchcancel"]) pad.addEventListener(ev, handle, { passive: false });
  }

  // ---------------------------------------------------------------- start
  function start() {
    const status = $("status");
    if (!game || !window.RufflePlayer || !window.RufflePlayer.newest) {
      status.textContent = "The player files are incomplete (game.js or ruffle/ is missing).";
      return;
    }
    document.title = game.title || document.title;
    const ruffle = window.RufflePlayer.newest();
    player = ruffle.createPlayer();
    player.id = "game";
    $("screen").appendChild(player);
    const pal = store.get("palette:" + game.name);
    player.ruffle().load({
      data: b64bytes(game.swf),
      swfFileName: game.file,
      allowScriptAccess: true,
      parameters: Object.assign({ keys: keysParam() }, pal ? { pal } : {}, /[?&]nosound\b/.test(location.search) ? { sound: "0" } : {}),
    }).then(() => {
      status.remove();
      setTimeout(onReady, 300);
    }).catch((e) => { status.textContent = "Could not start the game: " + e; });

    $("b-full").onclick = () => { if (player.enterFullscreen) player.enterFullscreen(); else player.requestFullscreen(); };
    let soundOn = store.get("sound") !== false;
    let volume = store.get("volume");
    if (volume == null) volume = 80;
    $("volume").value = volume;
    const applySound = () => {
      if (window.gb2swfAudioVolume) window.gb2swfAudioVolume(soundOn ? volume / 100 : 0);
      if (player.volume !== undefined) player.volume = soundOn ? volume / 100 : 0;
      $("b-sound").textContent = "Sound: " + (soundOn ? "on" : "off");
    };
    applySound();
    $("b-sound").onclick = () => { soundOn = !soundOn; store.set("sound", soundOn); applySound(); focusGame(); };
    $("volume").oninput = (e) => { volume = +e.target.value; store.set("volume", volume); applySound(); };
    $("b-keys").onclick = () => { renderKeys(); toggle($("b-keys"), $("keys")); };
    $("b-more").onclick = () => toggle($("b-more"), $("more"));
    $("keys-reset").onclick = () => { keys = Object.assign({}, DEFAULT_KEYS); store.set("keys", null); call("gbSetKeys", keysParam()); renderKeys(); };
    $("palette").onchange = (e) => {
      const v = e.target.value;
      store.set("palette:" + game.name, v || null);
      if (v) call("gbSetPalette", v); else location.reload();
      focusGame();
    };
    $("sav-export").onclick = () => {
      const b64 = call("gbGetSave");
      if (!b64) { alertBox("This game has no battery save."); return; }
      download(game.name + ".sav", b64bytes(b64), "application/octet-stream");
    };
    $("sav-import").onchange = (e) => {
      const f = e.target.files[0];
      if (!f) return;
      f.arrayBuffer().then((buf) => {
        let s = "";
        const u = new Uint8Array(buf);
        for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
        alertBox(call("gbSetSave", btoa(s)) ? "Save loaded; the game was restarted." : "This game has no battery save.");
        e.target.value = "";
        focusGame();
      });
    };
    let recording = false;
    $("rec").onclick = () => {
      if (!recording) {
        if (call("gbRecStart")) { recording = true; $("rec").textContent = "Stop and download recording"; focusGame(); }
      } else {
        const json = call("gbRecStop");
        recording = false;
        $("rec").textContent = "Start recording";
        if (json) download(game.name + "-input-" + new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-") + ".json", json, "application/json");
      }
    };
    let info = false;
    $("b-info").onclick = () => { info = !info; call("gbShowInfo", info); $("b-info").textContent = info ? "Hide fps" : "Show fps"; focusGame(); };
    $("b-reset").onclick = () => { call("gbReset"); focusGame(); };
    setupTouch();
    requestAnimationFrame(pollPads);
  }

  function alertBox(msg) {
    // No window.alert: it would freeze the game
    const n = document.createElement("div");
    n.className = "toast";
    n.textContent = msg;
    document.body.appendChild(n);
    setTimeout(() => n.remove(), 4000);
  }

  function onReady() {
    const inf = call("gbInfo");
    if (inf) {
      if (!inf.cgb) $("pal-wrap").hidden = false;
      if (!inf.hasSave) $("save-row").classList.add("off");
      const pal = store.get("palette:" + game.name);
      if (pal) $("palette").value = pal;
    }
    focusGame();
  }

  // Exposed for automated tests (fps and recompiled share)
  window.GB2SWF = { start, stats: () => call("gbStats") };
})();
