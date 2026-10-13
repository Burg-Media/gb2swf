# Third-party notices

gb2swf itself is MIT-licensed (see LICENSE). This file lists the other software
that gb2swf includes or uses, with its license. Everything gb2swf includes is
under the MIT or Apache-2.0 license, which may be combined with MIT code. gb2swf
does not include any GPL software.

## In every HTML player (and in the gb2swf packages)

### Ruffle

Flash Player emulator, https://ruffle.rs. Folder `player/ruffle/` (and `ruffle/`
inside every generated player). Unmodified; version and origin in
`player/ruffle/README.md`. Licensed under the MIT license or the Apache License 2.0,
at your option; both texts are included (`LICENSE_MIT`, `LICENSE_APACHE`).

```
Copyright (c) 2018 Ruffle LLC <ruffle@ruffle.rs> and Ruffle contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## In every SWF made by gb2swf

### Haxe standard library

Parts of the Haxe standard library are compiled into every SWF (for example
string, JSON and Base64 handling). MIT license:

```
Copyright (C)2005-2016 Haxe Foundation

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

A SWF also contains the game ROM supplied by the user. Its license or ownership
is the user's matter; gb2swf adds no rights to it.

## Bundled tool (gb2swf packages only, folder `toolchain/`)

### Node.js 24.21.0

https://nodejs.org. Included unmodified so that it does not have to be installed;
only the `node` program. MIT license; Node.js contains components under other
permissive licenses. The complete license text, including those components, is in
`toolchain/node/LICENSE`.

## Required but not included

### Haxe compiler

gb2swf needs the Haxe compiler (version 4.3 or later) to build SWF files. It is
not part of gb2swf; users install it themselves from https://haxe.org. The Haxe
compiler is licensed under the GNU GPL version 2. That license covers the
compiler program, not the files it produces; the parts of the Haxe standard
library that end up in a SWF are MIT-licensed (see above).

## Used for testing only (not included)

gb2swf's tests use these test ROMs. They are not part of the gb2swf packages or
repository; `scripts/fetch-testroms.mjs` downloads them from their authors'
publications (pinned versions, checked by SHA-256).

| Test ROMs | Author | License |
|---|---|---|
| Blargg's Game Boy test ROMs (cpu_instrs, instr_timing, mem_timing, mem_timing-2, halt_bug, interrupt_time, oam_bug, dmg_sound, cgb_sound) | Shay Green (blargg) | No license is stated by the author; therefore only downloaded for testing, never redistributed |
| Mooneye Test Suite | Joonas Javanainen | MIT |
| dmg-acid2, cgb-acid2 | Matt Currie | MIT |
| rtc3test | aaaaaa123456789 | The Unlicense (public domain) |

The open-licensed homebrew games used for the compatibility table are listed with
their licenses in `tests/homebrew.json` and `docs/compatibility.md`; they are not
included either.
