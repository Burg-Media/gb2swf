# gb2swf

gb2swf turns a Game Boy or Game Boy Color ROM into a Flash file (`.swf`) and a
ready-to-use HTML player. It statically recompiles the game code that it sees
running into ActionScript, and keeps an interpreter inside the SWF for everything
else, so a game always runs, even where the recompiler did not reach. The SWF
plays in [Ruffle](https://ruffle.rs) in any modern browser, from your disk or
from a web server, without an internet connection.

**[Download the latest release](https://github.com/Burg-Media/gb2swf/releases/latest)**
· [Play a demo in your browser](https://burgmedia.eu/shop/gb2swf#demo)
· Free and open source, made by [Burg Media](https://burgmedia.eu).

**Bring your own ROM.** gb2swf contains no games and no Nintendo code. Use dumps
of cartridges you own, or homebrew whose license allows it. See [LEGAL.md](LEGAL.md).

**Offline.** gb2swf and the players it makes never use the network: no
telemetry, no update check, no fonts or scripts from other servers. (Only the
developer script `scripts/fetch-testroms.mjs` downloads test files, and only when
you run it yourself.)

## Contents

- [Install](#install)
- [Your first game in 3 steps](#your-first-game-in-3-steps)
- [What you get](#what-you-get)
- [Playing](#playing)
- [Options](#options)
- [More recompiled code: record your own play](#more-recompiled-code-record-your-own-play)
- [How it works](#how-it-works)
- [What works and what does not](#what-works-and-what-does-not)
- [Problems](#problems)
- [Licenses](#licenses)
- [Building from source](#building-from-source)

## Install

gb2swf needs two programs: Node.js, which is included in the zip, and the Haxe
compiler, which you install once yourself.

1. **Install Haxe 4.3** (free) from https://haxe.org/download/. Use the
   installer for your system (on a Mac with Homebrew, `brew install haxe` also
   works). gb2swf finds it on the PATH or in its usual install location; if it is
   somewhere else, set the environment variable `GB2SWF_HAXE` to the full path.
2. **Download the gb2swf zip** for your system from the
   [releases page](https://github.com/Burg-Media/gb2swf/releases/latest) and unpack it anywhere.

| Package | System |
|---|---|
| `gb2swf-1.0.0-macos-arm64.zip` | Mac with Apple silicon (M1 and later) |
| `gb2swf-1.0.0-macos-x64.zip` | Mac with an Intel processor |
| `gb2swf-1.0.0-windows-x64.zip` | Windows 10 or 11, 64-bit |
| `gb2swf-1.0.0-linux-x64.zip` | Linux on x86-64 (glibc) |
| `gb2swf-1.0.0-linux-arm64.zip` | Linux on ARM64 (glibc) |

Check the download against `SHA256SUMS.txt` if you like:
`shasum -a 256 gb2swf-1.0.0-*.zip` (macOS, Linux) or
`certutil -hashfile gb2swf-1.0.0-windows-x64.zip SHA256` (Windows).

**Windows:** if Windows shows "Windows protected your PC" when you start
`gb2swf.cmd`, choose *More info* → *Run anyway*. You can avoid that by
right-clicking the zip before unpacking: *Properties* → tick *Unblock*.

**Linux:** unpack with a tool that keeps file permissions (`unzip` does).

To check the installation: `./gb2swf doctor` (macOS, Linux) or `gb2swf.cmd doctor` (Windows).

## Your first game in 3 steps

1. Open a terminal in the gb2swf folder (Windows: you can also drag the ROM file
   onto `gb2swf.cmd` and skip step 2).
2. Run `./gb2swf /path/to/game.gb` (Windows: `gb2swf.cmd C:\path\to\game.gb`).
3. Open `game_html/index.html` (next to your ROM) in your browser and play.

A build takes from about 15 seconds to a few minutes, depending on the game and
your computer. At the end gb2swf tells you how much of the game's code ran as
recompiled code in its check, for example:

```
[3/4] Checking: interpreter and recompiled code must behave identically
  passed (attract (no input), fuzz seed 1, fuzz seed 1004) in 13 s
  recompiled share on unseen input: 97.3% of executed instructions (profiling runs: 97.4%)
```

## What you get

Next to the ROM (or in the folder given with `-o`):

| | |
|---|---|
| `game.swf` | The game as a Flash file. Plays in Ruffle and in the Adobe Flash Player projector. |
| `game_html/` | A complete player: open `index.html`, or upload the whole folder to a web server. It contains Ruffle, the game and the page; it loads nothing from elsewhere. About 7.5 MB plus the game. |
| `game_work/` | Intermediate files (profiles, the generated code, `build.log`, `report.json`). Can be deleted; a later build creates it again. |

The SWF contains gb2swf's runtime (MIT license), parts of the Haxe standard
library (MIT) and the ROM you supplied, with its recompiled code. The rights to
the game stay with its owner: don't publish SWFs of games you have no rights to.

## Playing

**Keys** (change them in the player under *Controls*; they are remembered per browser):

| Game Boy | Keyboard |
|---|---|
| D-pad | arrow keys |
| A | X |
| B | Z |
| Start | Enter |
| Select | Shift |

Gamepads work in the HTML player (A/B, Start/Select, d-pad or left stick). On
touch screens the player shows on-screen buttons.

**Saves.** Games with a battery save to the browser's storage by themselves, as
on the real cartridge: one second after the game stops writing to its save
memory, and at least every 10 seconds while it keeps writing. The clock of MBC3
cartridges (games with a real-time clock) keeps running while the page is closed.
Under *More* you can download the save as a `.sav` file or load one, for example
a save from a real cartridge or another emulator (the usual layout, with the
48-byte clock block for MBC3 games). Saves are stored per browser and per address:
a page opened from disk and the same page on a web server have separate saves.

**Colours.** Original Game Boy games can use another palette (*Colours* in the
player, or `--palette` when building). Game Boy Color games use their own colours.

**Sound** plays as soon as you click or press a key (browsers require that).

**Flash Player projector.** The SWF also runs in the standalone Adobe Flash Player
(projector), with sound and saves. This has not been tested for this release.

## Options

```
./gb2swf <game.gb|game.gbc> [options]

  -o, --out <dir>       write the results to <dir>
  --name <name>         base name of the output files
  --title <text>        page title of the HTML player
  --palette <p>         green (default), grey, pocket, amber, or four hex colours light to dark
  --keys <map>          default keys as JavaScript keyCodes, e.g.
                        "up:38;down:40;left:37;right:39;a:88;b:90;start:13;select:16"
  --record <file>       extra profiling run from an input recording (repeatable)
  --seeds <n>           number of automatic random-input runs (default 4)
  --frames <n>          frames per automatic run (default 6000, about 100 seconds)
  --interp-only         no recompilation: interpreter only (always works, slower)
  --dmg                 run a Game Boy Color game that also supports the original Game Boy in DMG mode
  --names <file>        names for code addresses, as comments in the generated code
  --no-check            skip the interpreter-vs-recompiled check (not recommended)
  --no-player           only write the .swf
  --force               build even if the cartridge type is not supported
  -v, --verbose         more details

./gb2swf info <rom>     what the ROM header says (title, cartridge, checksums)
./gb2swf doctor         check that Node.js, Haxe and Ruffle are found
```

## More recompiled code: record your own play

gb2swf only recompiles code it has seen running. It finds that code by running
the game itself: once without any input (title screens and demo modes) and a few
times with random button presses. Parts of a game that random input never
reaches (later levels, menus behind a password) keep running on the interpreter:
correct, but slower.

To cover those parts, record yourself playing:

1. Open the player, *More* → *Start recording*. The game restarts.
2. Play the parts you care about, then *Stop and download recording*.
3. Build again with the recording: `./gb2swf game.gb --record game-input-....json`

The recording holds only button presses per frame (and the save the game started
with). gb2swf replays it exactly, so the code it reaches gets recompiled.

## How it works

1. **Profiling.** The emulator core runs the game in Node.js with the interpreter
   and notes every instruction that runs, and which ones are jumped to.
2. **Recompiling.** Every basic block of seen code is translated into Haxe code,
   with the CPU registers in local variables. Blocks are grouped into functions so
   that, in the SWF, one block can continue straight into the next.
3. **Checking (lockstep).** The game runs again, once on the interpreter and once
   on the recompiled code, with three input sequences (one the profiler never
   saw). At every block entry the registers and the cycle count must be
   identical, and every frame must be identical. If a block differs, it is left
   to the interpreter and the check runs again; if that does not help, the SWF is
   built with the interpreter only.
4. **Building.** The Haxe compiler turns runtime, recompiled code and ROM into
   the SWF; gb2swf then writes the HTML player.

The interpreter and the recompiler are generated from one description of the
instruction set (`src/tool/Sm83.hx`), so they cannot drift apart.

## What works and what does not

Measured results, with the files to repeat them, are in
[docs/compatibility.md](docs/compatibility.md). In short:

**Works**

- Game Boy (DMG) and Game Boy Color (CGB) games: double speed, VRAM/WRAM banks,
  colour palettes, HDMA (general purpose and HBlank).
- Cartridges: ROM only, ROM+RAM, MBC1, MBC2, MBC3 (with real-time clock), MBC5
  (rumble cartridges work, without rumble).
- CPU: passes Blargg's `cpu_instrs`, `instr_timing`, `mem_timing`,
  `mem_timing-2`, `halt_bug`, `interrupt_time`.
- Picture: passes `dmg-acid2` and `cgb-acid2` pixel for pixel.
- Clock: passes all three pages of `rtc3test`.
- 7 open-licensed homebrew games tested, all at full speed in Ruffle on an
  Apple M1 (see the table).

**Does not work, or not exactly**

- Not supported: MBC6, MBC7, MMM01, HuC1, HuC3, Pocket Camera and TAMA5
  cartridges; gb2swf refuses these unless you use `--force`. MBC1 multicarts
  (several games on one cartridge) look like normal MBC1 cartridges, so gb2swf
  builds them, but they will most likely not work correctly.
- No link cable, infrared, printer, rumble or Super Game Boy features.
- No Game Boy Color colourisation of original Game Boy games: those run in
  their own 4 shades (a palette of your choice).
- The picture is drawn one scanline at a time. Effects that change registers in
  the middle of a line are not shown; games that do that will look wrong.
- Sound: 6 of Blargg's 12 `dmg_sound` tests fail (rare hardware details such as
  reading wave RAM while it plays). Most game music sounds right, but not every
  sound effect is guaranteed to be exact.
- Not emulated: the DMG's OAM corruption bug, OAM DMA bus conflicts, exact PPU
  mode timings, the one-cycle TIMA reload delay. Of the 93 Mooneye tests used
  here, 36 of the 65 acceptance tests and 1 of the 28 cartridge (MBC) tests fail
  because of these; all are listed with the reason in [docs/compatibility.md](docs/compatibility.md).
- Code that a game copies to RAM and runs from there is never recompiled; it
  always runs on the interpreter (correct, but slower).
- Recompiled code updates the picture and timers between blocks of up to 48
  instructions instead of after every instruction. The CPU behaves the same
  either way (the lockstep check shows that), but a scanline can come out
  differently in rare cases.
- In Ruffle, sound goes through a small JavaScript file on the page
  (`gb2swf-audio.js`), because Ruffle cannot play sound that a SWF generates
  itself. A SWF embedded in another page without that file plays without sound.
- Speed depends on your computer and browser. On an Apple M1 a frame takes
  6 to 11 ms of the 16.7 ms available. Slower computers will have less margin;
  we have not measured them.

## Problems

| Problem | What to do |
|---|---|
| `this cartridge type ... is not supported` | The game uses hardware gb2swf does not emulate. `--force` builds anyway, but it will most likely not work. |
| `the header checksum is wrong` | The ROM is probably a bad dump. gb2swf builds it anyway. |
| The check reports a difference | gb2swf leaves that code to the interpreter and tries again; the SWF still works. Please report it (see below). |
| Black screen or "Could not start the game" in the browser | Use a current Chrome, Edge, Firefox or Safari. The page needs WebAssembly and `DecompressionStream` (Safari 16.4 or later). |
| No sound | Click into the game or press a key; check *Sound: on* and the volume. |
| Keys do nothing | Click into the game so it has the keyboard focus. |
| The game runs slowly | Try another browser; close other tabs. Recording your play (see above) can raise the recompiled share. |
| Save is gone | Saves belong to the browser and the page address. Use *More* → *Download .sav* to keep a copy. |
| `the Haxe compiler was not found` | Install Haxe 4.3 (see *Install*), open a new terminal, and run `gb2swf doctor`. |

**Reporting a game that does not work:** open an issue with the game's name, the
checksums from `./gb2swf info game.gb` (header and global checksum), the gb2swf
version and `game_work/build.log`. Never attach or link the ROM.

## Licenses

gb2swf is open source under the MIT license (see [LICENSE](LICENSE)),
Copyright (c) 2026 Burg Media.

The packages include other software, each under its own license (details in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)):

- **Ruffle** (MIT or Apache-2.0), in every HTML player.
- **Node.js** (MIT, with the licenses of its components), to run gb2swf.

The **Haxe compiler** is not included; you install it yourself from haxe.org. It
is licensed under the GPL, but that applies to the compiler program, not to what
it compiles: a SWF made by gb2swf contains only gb2swf's runtime (MIT), parts of
the Haxe standard library (MIT) and the game you supplied. The rights to that
game stay with whoever owns them.

## Building from source

Requirements: Node.js 22 or later and Haxe 4.3 (`haxe` on the PATH, or set
`GB2SWF_HAXE`), the same Haxe that users install.

```
haxe build-tool.hxml                         # builds lib/gb2swf.js
node lib/gb2swf.js path/to/game.gb           # same as ./gb2swf
node scripts/fetch-testroms.mjs --homebrew   # test ROMs and homebrew (needs the network)
node lib/gb2swf.js dev testroms --rec        # test ROMs, interpreter and recompiled
node scripts/compat-report.mjs               # builds and measures the homebrew games (needs Chrome)
node scripts/make-release.mjs                # release packages in release/
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the layout of the source.
