# Contributing to gb2swf

Thanks for helping. Bug reports, test results with homebrew games and pull
requests are welcome.

## Never share ROMs

Do not attach, link to or paste (parts of) commercial ROMs, disassemblies of
commercial games, or generated code from them (`*_work/rec/`) in issues, pull
requests or discussions. Identify a game by its name and the checksums that
`gb2swf info game.gb` prints. Pull requests that contain such material will be
closed.

## Layout

```
src/gb/          the emulator core (shared by the SWF and the tools)
  Machine.hx     memory map, cartridges (MBC1/2/3/5, RTC), timer, IO, Game Boy Color extras
  Cpu.hx         the interpreter, GENERATED from src/tool/Sm83.hx (gb2swf dev gen-interp)
  Gb.hx          main loop: interpreter, recompiled blocks, interrupts
  Ppu.hx Apu.hx  picture and sound
  Rtc.hx Mem.hx  MBC3 clock, the flat memory block
src/swf/Main.hx  the Flash frontend (picture, keys, sound, saves, recording)
src/tool/        the command line tool (compiled to lib/gb2swf.js, runs on Node.js)
  Sm83.hx        the instruction set: one description for interpreter and recompiler
  Recompiler.hx  ROM + profiles -> Haxe code
  Build.hx       the build pipeline; Harness.hx: the lockstep check
  TestRoms.hx    test ROM runner
player/          the HTML player template and the vendored Ruffle
scripts/         fetch test ROMs, compatibility report, release packages
tests/           test ROM and homebrew manifests (URLs, SHA-256, licenses)
test/drive.mjs   headless Chrome driver for player tests
```

## Building and testing

You need Node.js 22 or later and Haxe 4.3.

```
haxe build-tool.hxml                         # lib/gb2swf.js
node scripts/fetch-testroms.mjs --homebrew   # test ROMs and homebrew games
node lib/gb2swf.js dev testroms --rec        # must report no UNEXPECTED failures
node lib/gb2swf.js homebrew/libbet.gb -o build/t   # full build incl. lockstep check
```

If you change `src/tool/Sm83.hx`, regenerate the interpreter with
`node lib/gb2swf.js dev gen-interp` and commit `src/gb/Cpu.hx` too.

A test ROM that starts passing should get its `expect` entry removed from
`tests/testroms.json`. A change that makes the lockstep check fail for any game is
a bug, even if the game looks fine.

## Style

- Code and comments in English, Haxe formatted like the existing code (tabs).
- Every source file starts with the two-line MIT header.
- Keep it offline: no network access in gb2swf or the players it makes.
- Claims in documentation must be backed by a test or a measurement that others
  can repeat.

## License of contributions

By contributing you agree that your contribution is licensed under the MIT
license of this project.
