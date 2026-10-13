# Bundled tool

gb2swf runs on Node.js, which is included here unmodified so that it does not
have to be installed. gb2swf only starts it, it does not change it.

| Folder | Program | Version | License | Source |
|---|---|---|---|---|
| `node/` | Node.js (only the `node` program) | 24.21.0 LTS | MIT, plus the licenses of its components in `node/LICENSE` | https://nodejs.org/dist/v24.21.0/ |

The Haxe compiler, which gb2swf uses to build SWF files, is **not** included.
Install it yourself from https://haxe.org/download/ (version 4.3 or later).
