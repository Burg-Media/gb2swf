// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
//
// Builds the public demo (Tobu Tobu Girl Deluxe by Tangram Games: code MIT,
// assets CC BY 4.0) into release/demo/, with the required credits on the page
// and the license texts next to it.
//
//   node scripts/make-demo.mjs        (needs homebrew/tobudx.gb, see tests/homebrew.json)
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const hb = JSON.parse(fs.readFileSync(path.join(root, "tests/homebrew.json"), "utf8"));
const game = hb.games.find((g) => g.id === "tobudx");
const rom = path.join(root, "homebrew", game.file);
if (!fs.existsSync(rom)) throw new Error(`${rom} missing: download it from ${game.page}`);
if (crypto.createHash("sha256").update(fs.readFileSync(rom)).digest("hex") !== game.sha256) throw new Error("tobudx.gb has an unexpected checksum");

const out = path.join(root, "release/demo");
const work = path.join(root, "build/demo");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
execFileSync(process.execPath, [path.join(root, "lib/gb2swf.js"), rom, "-o", work, "--name", "tobu-tobu-girl-deluxe",
  "--title", "Tobu Tobu Girl Deluxe - gb2swf demo"], { stdio: "inherit" });
const dir = path.join(out, "tobu-tobu-girl-deluxe");
fs.cpSync(path.join(work, "tobu-tobu-girl-deluxe_html"), dir, { recursive: true });

const credit = `Tobu Tobu Girl Deluxe &copy; 2017 Tangram Games (sound by potato-tan, as credited in the game). ` +
  `Code: <a href="LICENSE-tobu-tobu-girl-deluxe.txt">MIT License</a>. Images, text, sound and music: ` +
  `<a href="https://creativecommons.org/licenses/by/4.0/" rel="noreferrer">CC BY 4.0</a>. ` +
  `Original game: <a href="https://tangramgames.itch.io/tobu-tobu-girl-deluxe" rel="noreferrer">tangramgames.itch.io</a>, ` +
  `source: <a href="https://github.com/SimonLarsen/tobutobugirl-dx" rel="noreferrer">github.com/SimonLarsen/tobutobugirl-dx</a>. ` +
  `Unchanged ROM, converted to SWF with gb2swf. Not affiliated with Nintendo.`;
const index = path.join(dir, "index.html");
fs.writeFileSync(index, fs.readFileSync(index, "utf8").replace('<p id="foot">', `<p id="credits">${credit}</p>\n<p id="foot">`));
fs.appendFileSync(path.join(dir, "gb2swf-player.css"), "#credits { color: var(--muted); font-size: 12px; max-width: 720px; padding: 0 16px; margin: 0; }\n#credits a { color: var(--muted); }\n");
fs.copyFileSync(path.join(root, "tests/licenses/tobutobugirl-dx-LICENSE.txt"), path.join(dir, "LICENSE-tobu-tobu-girl-deluxe.txt"));
fs.writeFileSync(path.join(dir, "CREDITS.txt"), credit.replace(/<[^>]+>/g, "").replace(/&copy;/g, "(c)") + "\n\n" +
  "The page and player: gb2swf (MIT License, Copyright (c) 2026 Burg Media) and Ruffle (MIT OR Apache-2.0,\n" +
  "Copyright (c) 2018 Ruffle LLC and Ruffle contributors), see ruffle/LICENSE_MIT and ruffle/LICENSE_APACHE.\n");
console.log("demo written to " + path.relative(root, dir));
