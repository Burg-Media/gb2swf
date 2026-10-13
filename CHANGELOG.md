# Changelog

All notable changes to gb2swf. Versions follow [Semantic Versioning](https://semver.org).

## 1.0.0 - 2026-10-13

First public release.

### Conversion
- One command: `gb2swf game.gb` profiles the game (one run without input, four
  runs with random input), recompiles the code it saw, checks the recompiled code
  against the interpreter instruction by instruction, and builds `game.swf` plus
  an HTML player.
- The build reports the share of executed instructions that ran as recompiled
  code on an input sequence the profiler had not seen.
- Blocks that fail the check are left to the interpreter automatically; if the
  check cannot be made to pass, the SWF is built with the interpreter only.
- `--record`: extra profiling runs from input recordings made in the HTML player;
  the build reports whether a recording replayed exactly.
- `--interp-only`, `--palette`, `--keys`, `--dmg`, `--names`, `--seeds`,
  `--frames`, `--strict`.
- `gb2swf info` (ROM header) and `gb2swf doctor` (installation check).
- Packages for macOS (Apple silicon and Intel), Windows x64 and Linux
  (x64, arm64) with Node.js included; the Haxe compiler (4.3 or later) is
  installed separately by the user.

### Emulation
- Game Boy and Game Boy Color: double speed, VRAM and WRAM banks, colour
  palettes, HDMA.
- Cartridges: ROM only, ROM+RAM, MBC1, MBC2, MBC3 with real-time clock, MBC5.
- Memory accesses happen in the right M-cycle of each instruction.
- Passes Blargg's cpu_instrs, instr_timing, mem_timing, mem_timing-2, halt_bug and
  interrupt_time, dmg-acid2, cgb-acid2 and rtc3test.

### Player
- HTML player that works from disk and from a web server, with self-hosted
  Ruffle; no network requests.
- Battery saves in the browser (Flash SharedObject), `.sav` download and upload
  (with the common 48-byte clock block for MBC3). The MBC3 clock follows emulated
  time while playing and catches up with the real time after the page was closed.
- Key remapping, gamepad support, touch buttons, palettes, volume, full screen,
  fps overlay.
- Input recording for `--record`.
