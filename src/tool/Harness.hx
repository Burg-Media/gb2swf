// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import gb.Gb;
import haxe.io.Bytes;
import js.lib.Int32Array;
import tool.Input;

/**
 * Compiled together with a game's recompiled blocks (-D blocks) and run by the
 * gb2swf tool as a separate Node process:
 *
 *   node harness.js lockstep <rom> <spec.json>   interpreter vs recompiled, instruction-exact
 *   node harness.js run <rom> <spec.json>        recompiled run (test ROM verdicts, screenshots, speed)
 *
 * Results are printed as one JSON line on stdout.
 */
class Harness {
	static function main() {
		var argv = Host.args();
		var rom = Host.readBytes(argv[1]);
		var spec:Dynamic = haxe.Json.parse(Host.readText(argv[2]));
		var result:Dynamic = switch (argv[0]) {
			case "lockstep": lockstep(rom, spec);
			case "run": run(rom, spec);
			default: {error: "unknown command " + argv[0]};
		}
		Host.print(haxe.Json.stringify(result));
	}

	static function makeInput(r:Dynamic):Input {
		return switch (r.type) {
			case "fuzz": new Fuzz(r.seed);
			case "replay": new Replay(Host.readText(r.file), r.file);
			default: new Attract();
		}
	}

	static function newMachine(rom:Bytes, spec:Dynamic, input:Input):Gb {
		var g = new Gb(rom, spec.forceDmg == true);
		#if blocks
		Blocks.install(g);
		#end
		if (Std.isOfType(input, Replay)) {
			var rp:Replay = cast input;
			if (rp.save != null)
				g.setSave(rp.save);
		}
		return g;
	}

	static inline function stateHash(g:Gb):Int {
		var x = g.a | (g.b << 8) | (g.c << 16) | (g.d << 24);
		x = (x * 31 + (g.e | (g.h << 8) | (g.l << 16))) | 0;
		x = (x * 31 + (g.sp | (g.fz ? 0x10000 : 0) | (g.fn ? 0x20000 : 0) | (g.fh ? 0x40000 : 0) | (g.fc ? 0x80000 : 0)
			| (g.ime ? 0x100000 : 0))) | 0;
		x = (x * 31 + g.cycles) | 0;
		x = (x * 31 + g.romBank) | 0;
		return x;
	}

	static function stateText(g:Gb, off:Int):String {
		inline function hx(v:Int, n:Int)
			return StringTools.hex(v, n);
		return '@${hx(off, 5)} a${hx(g.a, 2)} b${hx(g.b, 2)} c${hx(g.c, 2)} d${hx(g.d, 2)} e${hx(g.e, 2)} h${hx(g.h, 2)} l${hx(g.l, 2)} sp${hx(g.sp, 4)} '
			+ (g.fz ? "z" : "-") + (g.fn ? "n" : "-") + (g.fh ? "h" : "-") + (g.fc ? "c" : "-") + ' ime${g.ime ? 1 : 0} t${g.cycles} bank${g.romBank}';
	}

	/** Growable list of 32-bit values. */
	static var chunks:Array<Int32Array>;
	static var count:Int;

	static function push(v:Int) {
		var c = count >> 20;
		if (c >= chunks.length)
			chunks.push(new Int32Array(1 << 20));
		chunks[c][count & 0xFFFFF] = v;
		count++;
	}

	static inline function get(i:Int):Int
		return chunks[i >> 20][i & 0xFFFFF];

	static function lockstep(rom:Bytes, spec:Dynamic):Dynamic {
		var runs:Array<Dynamic> = spec.runs;
		var results = [];
		var ok = true;
		for (r in runs) {
			var frames:Int = r.frames;
			// 1) interpreter, recording (offset, state) at every block entry and a hash per frame
			chunks = [];
			count = 0;
			var input = makeInput(r);
			var g = newMachine(rom, spec, input);
			g.lockstep = true;
			g.useBlocks = false;
			g.traceFn = function(off) {
				push(off);
				push(stateHash(g));
			};
			var frameHashes = [];
			Headless.run(g, frames, input, function(f) frameHashes.push(Headless.frameHash() ^ stateHash(g)));
			var total = count;

			// 2) recompiled, compared as it goes
			input = makeInput(r);
			var g2 = newMachine(rom, spec, input);
			g2.lockstep = true;
			g2.useBlocks = true;
			var idx = 0;
			var bad = -1;
			var prevOff = -1;
			var badOff = -1;
			var badPrev = -1;
			var got = "";
			g2.traceFn = function(off) {
				if (bad >= 0)
					return;
				if (idx >= total || get(idx) != off || get(idx + 1) != stateHash(g2)) {
					bad = idx;
					badOff = off;
					badPrev = prevOff;
					got = stateText(g2, off);
					g2.locked = true; // stop this run
				}
				prevOff = off;
				idx += 2;
			};
			var badFrame = -1;
			var n2 = Headless.run(g2, frames, input, function(f) {
				if (bad < 0 && badFrame < 0 && frameHashes[f - 1] != (Headless.frameHash() ^ stateHash(g2)))
					badFrame = f - 1;
			});
			var res:Dynamic = {
				name: input.describe(),
				frames: frames,
				entries: total >> 1,
				instrInterp: g.instrInterp,
				instrRec: g2.instrRec
			};
			if (bad < 0 && badFrame < 0 && idx != total) {
				bad = idx; // the recompiled run ended early
				badOff = -1;
			}
			if (bad >= 0) {
				ok = false;
				var expect = "(end of trace)";
				if (bad < total) {
					// Run the interpreter again up to the mismatch to print its state there
					var target = bad;
					var k = 0;
					var input3 = makeInput(r);
					var g3 = newMachine(rom, spec, input3);
					g3.lockstep = true;
					g3.useBlocks = false;
					g3.traceFn = function(off) {
						if (k == target)
							expect = stateText(g3, off);
						k += 2;
						if (k > target)
							g3.locked = true;
					};
					Headless.run(g3, frames, input3);
				}
				res.mismatch = {
					entry: bad >> 1,
					offset: badOff,
					previousBlock: badPrev,
					expected: expect,
					got: got
				};
			} else if (badFrame >= 0) {
				ok = false;
				res.mismatch = {frame: badFrame, offset: -1, previousBlock: -1};
			}
			if (res.mismatch == null) {
				// 3) recompiled with blocks chained (as in the SWF): every frame must match the interpreter
				input = makeInput(r);
				var g4 = newMachine(rom, spec, input);
				g4.lockstep = true;
				g4.useBlocks = true;
				var chainBad = -1;
				Headless.run(g4, frames, input, function(f) {
					if (chainBad < 0 && frameHashes[f - 1] != (Headless.frameHash() ^ stateHash(g4))) {
						chainBad = f - 1;
						g4.locked = true;
					}
				});
				if (chainBad >= 0) {
					ok = false;
					res.mismatch = {frame: chainBad, offset: -1, previousBlock: -1, chained: true};
				}
			}
			results.push(res);
		}
		return {ok: ok, runs: results};
	}

	static function run(rom:Bytes, spec:Dynamic):Dynamic {
		var input = makeInput(spec);
		var g = newMachine(rom, spec, input);
		if (spec.palette != null)
			g.ppu.setPalette(spec.palette);
		g.stopOnLdBB = spec.mooneye == true;
		var t0 = Host.now();
		var frames = Headless.run(g, spec.frames, input, function(f) {
			if (spec.until != null && g.serial.toString().indexOf(spec.until) >= 0)
				g.locked = true;
			if (spec.blarggMemory == true && f % 30 == 0 && Headless.blarggMemory(g).done)
				g.locked = true;
		});
		var ms = Host.now() - t0;
		if (spec.png != null)
			Host.writeBytes(spec.png, Headless.png(spec.scale != null ? spec.scale : 1));
		var mem = Headless.blarggMemory(g);
		return {
			frames: frames,
			ms: ms,
			serial: g.serial.toString(),
			memory: mem,
			mooneye: g.hitLdBB ? (Headless.mooneyePass(g) ? "pass" : "fail") : "timeout",
			instrInterp: g.instrInterp,
			instrRec: g.instrRec,
			rgbaHash: Headless.frameHash(),
			screenPassed: Headless.screenHas("Passed"),
			screenFailed: Headless.screenHas("Failed")
		};
	}
}
