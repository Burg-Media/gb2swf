// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import haxe.io.Bytes;
import tool.Sm83;

/**
 * Static recompilation: Game Boy ROM -> Haxe source, one function per basic block.
 *
 * Only instructions that actually ran while profiling are translated, so data is
 * never mistaken for code. Everything else keeps running on the interpreter.
 * Output: Blocks.hx (the dispatch table) and one BankXX.hx per ROM bank.
 *
 * Optional names file (grows with your own disassembly work):
 *   <bank>:<address hex> <name> [# comment]      e.g.  00:0150 Main
 */
class Recompiler {
	public static inline var MAX_INSTR = 48;
	static inline var GROUP_BITS = 7;
	static inline var GROUP = 1 << GROUP_BITS;

	public var blockCount = 0;
	public var instrCount = 0;
	public var executedCount = 0;

	var rom:Bytes;
	var executed = new Map<Int, Bool>();
	var entries = new Map<Int, Bool>();
	var names = new Map<Int, String>();
	var excluded = new Map<Int, Bool>();
	var covered = new Map<Int, Bool>();
	var mbc1 = false;

	public function new(rom:Bytes) {
		this.rom = rom;
		var t = rom.get(0x147);
		mbc1 = t >= 0x01 && t <= 0x03;
	}

	/** Adds one profile run: [[offset, count, enteredByJump], ...] */
	public function addProfile(rows:Array<Array<Int>>) {
		for (r in rows) {
			executed.set(r[0], true);
			if (r.length > 2 && r[2] != 0)
				entries.set(r[0], true);
		}
	}

	/** Block entries that must be left to the interpreter (found by the lockstep check). */
	public function exclude(entries:Map<Int, Bool>) {
		for (k in entries.keys())
			excluded.set(k, true);
	}

	/** ROM offsets of all instructions inside generated blocks (valid after run()). */
	public function coveredOffsets():Map<Int, Bool>
		return covered;

	public function loadNames(text:String) {
		for (line in text.split("\n")) {
			var s = StringTools.trim(line.split("#")[0]);
			if (s == "")
				continue;
			var parts = ~/\s+/g.split(s);
			if (parts.length < 2)
				continue;
			var loc = parts[0].split(":");
			if (loc.length != 2)
				continue;
			var bank = Std.parseInt("0x" + loc[0]), addr = Std.parseInt("0x" + loc[1]);
			if (bank == null || addr == null)
				continue;
			names.set(addr < 0x4000 ? addr : bank * 0x4000 + addr - 0x4000, parts[1]);
		}
	}

	static function lit(v:Int, n:Int = 4):String
		return "0x" + StringTools.hex(v, n);

	static inline function addrOf(off:Int):Int
		return off < 0x4000 ? off : 0x4000 + (off & 0x3FFF);

	static inline function offOf(addr:Int, bank:Int):Int
		return addr < 0x4000 ? addr : bank * 0x4000 + (addr - 0x4000);

	function decode(off:Int):{op:Int, len:Int, imm:Int} {
		var op = rom.get(off);
		var len = Sm83.LENGTH[op];
		var imm = 0;
		if (len == 2 && off + 1 < rom.length)
			imm = rom.get(off + 1);
		else if (len == 3 && off + 2 < rom.length)
			imm = rom.get(off + 1) | (rom.get(off + 2) << 8);
		return {op: op, len: len, imm: imm};
	}

	/** Returns file name -> Haxe source. */
	public function run():Map<String, String> {
		var exec = [for (k in executed.keys()) k];
		exec.sort((x, y) -> x - y);
		executedCount = exec.length;

		// Extra block entries: jump targets, return addresses, fall-through after conditional jumps
		for (off in exec) {
			var ins = decode(off);
			var fl = Sm83.flow(ins.op);
			var bank = off >> 14;
			switch (fl) {
				case Call, CondCall, Cond, CondRet, Stop:
					if (executed.exists(off + ins.len))
						entries.set(off + ins.len, true);
				default:
					if (ins.op == 0xF3 && executed.exists(off + ins.len))
						entries.set(off + ins.len, true);
			}
			switch (fl) {
				case Jump, Cond, Call, CondCall:
					var t = Sm83.staticTarget(ins.op, addrOf(off), ins.imm);
					if (t >= 0 && t < 0x8000) {
						var tb = t < 0x4000 ? 0 : (bank > 0 ? bank : -1);
						if (tb >= 0) {
							var to = offOf(t, tb);
							if (executed.exists(to))
								entries.set(to, true);
						}
					}
				default:
			}
		}
		for (v in [0x40, 0x48, 0x50, 0x58, 0x60, 0x100])
			if (executed.exists(v))
				entries.set(v, true);

		var blocks:Array<{entry:Int, name:String, code:String, count:Int}> = [];
		var ents = [for (k in entries.keys()) if (executed.exists(k) && !excluded.exists(k)) k];
		ents.sort((x, y) -> x - y);
		for (entry in ents) {
			var bank = entry >> 14;
			var banked = entry >= 0x4000;
			var lines = [];
			var off = entry;
			var count = 0;
			while (true) {
				var ins = decode(off);
				var op = ins.op, imm = ins.imm;
				var addr = addrOf(off);
				var nxt = (addr + ins.len) & 0xFFFF;
				if (op == 0xCB)
					imm = off + 1 < rom.length ? rom.get(off + 1) : 0;
				var ctx = new RecCtx(op, addr, imm, nxt, banked, bank, mbc1);
				var code = Sm83.gen(ctx, op);
				var cyc = op == 0xCB ? Sm83.cbCycles(imm) * 4 : Sm83.CYC[op] * 4;
				var mn = op == 0xCB ? Sm83.mnemonic(op, 0, addr, imm) : Sm83.mnemonic(op, imm, addr);
				var tag = banked ? '${StringTools.hex(bank, 2)}:${StringTools.hex(addr, 4)}' : StringTools.hex(addr, 4);
				var label = (names.exists(off) && off != entry) ? '  <${names.get(off)}>' : "";
				var pre = Sm83.isIllegal(op) ? "" : 'cy += $cyc; ';
				lines.push('\t\t\t\t\t// $tag  $mn$label');
				var fl = Sm83.flow(op);
				var stops = switch (fl) {
					case Jump, Call, Ret, Stop: true;
					default: false;
				}
				// After a slow memory access: pick up extra cycles, the new deadline and a changed ROM bank
				if (ctx.mayTouch && !stops)
					code += " " + ctx.refresh();
				if (op == 0xFB)
					code += " dl = -1;"; // EI: the main loop handles the delayed interrupt enable
				lines.push('\t\t\t\t\t$pre$code');
				covered.set(off, true);
				count++;
				var offNext = off + ins.len;
				if (stops || ctx.endsBlock) {
					// halt/stop/illegal and jumps set npc themselves; EI and MBC writes do not
					var setsPc = switch (fl) {
						case Jump, Call, Ret: true;
						default: op == 0x76 || op == 0x10 || Sm83.isIllegal(op);
					}
					if (!setsPc)
						lines.push('\t\t\t\t\tnpc = ${lit(nxt)};');
					break;
				}
				// Next instruction unknown, an entry of its own, in another bank, or block too long
				if (!executed.exists(offNext) || entries.exists(offNext) || (banked && (offNext >> 14) != bank)
					|| (!banked && offNext >= 0x4000) || count >= MAX_INSTR) {
					lines.push('\t\t\t\t\tnpc = ${lit(nxt)};');
					break;
				}
				off = offNext;
			}
			var name = (banked ? StringTools.hex(bank, 2) + ":" : "") + StringTools.hex(addrOf(entry), 4) + (names.exists(entry) ? " " + names.get(entry) : "");
			blocks.push({entry: entry, name: name, code: lines.join("\n"), count: count});
			blockCount++;
			instrCount += count;
		}

		var files = new Map<String, String>();
		var b = new StringBuf();
		b.add("// GENERATED by gb2swf from the game's ROM: translated code of that game.\n");
		b.add("// Do not edit by hand; add names to names.txt and rebuild instead.\n");
		b.add("import gb.Gb;\nimport gb.Mem;\n\nclass Blocks {\n");
		b.add('\tpublic static inline var COUNT = $blockCount;\n\n');
		b.add("\t/** Maps ROM offsets to block numbers + 1 (0 = not recompiled). */\n");
		b.add("\tpublic static function install(g:Gb):Void {\n");
		b.add('\t\tvar t = new haxe.ds.Vector<Int>(${rom.length});\n');
		b.add('\t\t#if !flash\n\t\tfor (i in 0...${rom.length})\n\t\t\tt[i] = 0;\n\t\t#end\n');
		for (i in 0...blocks.length)
			b.add('\t\tt[${lit(blocks[i].entry, 5)}] = ${i + 1};\n');
		b.add("\t\tg.blockIndex = t;\n\t}\n\n");
		// Blocks are spread over functions of GROUP blocks (neighbours in the ROM end up
		// together). Within a function, registers and time live in local variables and
		// blocks follow each other directly; the Haxe Flash backend gets very slow on
		// much larger functions.
		var groups = Std.int((blocks.length + GROUP - 1) / GROUP);
		b.add("\t/** Runs block `k` and, while nothing needs the main loop (g.deadline), the blocks after it. */\n");
		b.add("\tpublic static function run(g:Gb, k:Int):Void {\n");
		b.add("\t\twhile (k >= 0) {\n\t\t\tk = switch (k >> " + GROUP_BITS + ") {\n");
		for (gi in 0...groups)
			b.add('\t\t\t\tcase $gi: run$gi(g, k & ${GROUP - 1});\n');
		b.add("\t\t\t\tdefault: -1;\n\t\t\t}\n\t\t}\n\t}\n\n");
		var temps = ["_a", "_c", "_ci", "_hl", "_n", "_p", "_r", "_v", "_w"];
		var tempDecl = ~/var (_[a-z]+) = /g;
		for (gi in 0...groups) {
			b.add('\t/** Blocks ${gi * GROUP} to ${Std.int(Math.min(blocks.length, (gi + 1) * GROUP)) - 1}. Returns the next block in another group, or -1. */\n');
			b.add('\tstatic function run$gi(g:Gb, k:Int):Int {\n');
			b.add("\t\tvar a = g.a, b = g.b, c = g.c, d = g.d, e = g.e, h = g.h, l = g.l, sp = g.sp;\n");
			b.add("\t\tvar fz = g.fz, fn = g.fn, fh = g.fh, fc = g.fc;\n");
			b.add("\t\tvar cy = g.cycles, dl = g.deadline, ic = 0, npc = 0, next = -1;\n");
			b.add("\t\tvar " + [for (t in temps) t + " = 0"].join(", ") + ";\n");
			b.add("\t\tvar ix = g.blockIndex;\n");
			b.add("\t\twhile (true) {\n\t\t\tswitch (k) {\n");
			for (i in gi * GROUP...Std.int(Math.min(blocks.length, (gi + 1) * GROUP))) {
				var bl = blocks[i];
				b.add('\t\t\t\tcase ${i & (GROUP - 1)}: // ${bl.name}\n');
				b.add('\t\t\t\t\tic += ${bl.count};\n\t\t\t\t\tdo {\n${tempDecl.replace(bl.code, "$1 = ")}\n\t\t\t\t\t} while (false);\n');
			}
			b.add("\t\t\t\tdefault:\n\t\t\t}\n");
			b.add("\t\t\t// Continue with the next block straight away, unless the main loop has work to do\n");
			b.add("\t\t\tif (cy >= dl)\n\t\t\t\tbreak;\n");
			b.add("\t\t\tvar o = npc < 0x4000 ? (g.rom0Bank == 0 ? npc : -1) : (npc < 0x8000 ? (g.romBank << 14) + npc - 0x4000 : -1);\n");
			b.add("\t\t\tif (o < 0)\n\t\t\t\tbreak;\n");
			b.add("\t\t\tvar nk = ix[o] - 1;\n\t\t\tif (nk < 0)\n\t\t\t\tbreak;\n");
			b.add('\t\t\tif ((nk >> $GROUP_BITS) != $gi) {\n\t\t\t\tnext = nk;\n\t\t\t\tbreak;\n\t\t\t}\n');
			b.add('\t\t\tk = nk & ${GROUP - 1};\n');
			b.add("\t\t}\n");
			b.add("\t\tg.a = a; g.b = b; g.c = c; g.d = d; g.e = e; g.h = h; g.l = l; g.sp = sp;\n");
			b.add("\t\tg.fz = fz; g.fn = fn; g.fh = fh; g.fc = fc;\n");
			b.add("\t\tg.cycles = cy; g.pc = npc; g.instrRec += ic;\n\t\treturn next;\n\t}\n\n");
		}
		b.add("\t/** Entry offset and instruction count of every block (used by the build report). */\n");
		b.add('\tpublic static function sizes():Array<Int>\n\t\treturn [${[for (bl in blocks) bl.entry + "," + bl.count].join(",")}];\n}\n');
		files.set("Blocks.hx", b.toString());
		return files;
	}
}

class RecCtx implements Ctx {
	var op:Int;
	var addr:Int;
	var imm:Int;
	var nxt:Int;
	var banked:Bool;
	var bankCheck:String;

	/** Set when the instruction may switch the ROM bank this code runs from. */
	public var endsBlock = false;

	/** Set when the instruction uses a slow memory path (IO, cartridge, unknown address). */
	public var mayTouch = false;

	public function new(op:Int, addr:Int, imm:Int, nxt:Int, banked:Bool, bank:Int, mbc1:Bool) {
		this.op = op;
		this.addr = addr;
		this.imm = imm;
		this.nxt = nxt;
		this.banked = banked;
		// After a write to an unknown address, leave the block if the bank under our feet changed
		if (banked)
			bankCheck = ' if (g.romXOff != ${lit(gb.Mem.ROM + bank * 0x4000 - 0x4000, 6)}) { npc = ${lit(nxt)}; break; }';
		else if (mbc1)
			bankCheck = ' if (g.rom0Off != ${lit(gb.Mem.ROM, 6)}) { npc = ${lit(nxt)}; break; }';
		else
			bankCheck = "";
	}

	public function refresh():String
		return 'if (g.touched) { g.touched = false; cy += g.extra; g.extra = 0; dl = g.deadline;$bankCheck }';

	static function lit(v:Int, n:Int = 4):String
		return "0x" + StringTools.hex(v, n);

	static function time(d:Int):String
		return d == 0 ? "cy" : 'cy - $d';

	static function constant(a:String):Null<Int> {
		if (!~/^(0x[0-9A-Fa-f]+|[0-9]+)$/.match(a))
			return null;
		return Std.parseInt(a);
	}

	public function n8()
		return lit(imm, 2);

	public function n16()
		return lit(imm);

	public function next()
		return lit(nxt);

	public function jrTarget()
		return lit((nxt + ((imm ^ 0x80) - 0x80)) & 0xFFFF);

	public function rd(a:String, d:Int):String {
		var v = constant(a);
		if (v == null) {
			mayTouch = true;
			return 'g.rdT($a, ${time(d)})';
		}
		if (v < 0x4000)
			return 'Mem.get(g.rom0Off + ${lit(v)})';
		if (v < 0x8000)
			return 'Mem.get(g.romXOff + ${lit(v)})';
		if (v < 0xA000)
			return 'Mem.get(g.vramOff + ${lit(v)})';
		if ((v >= 0xC000 && v < 0xE000) || (v >= 0xFF80 && v < 0xFFFF))
			return 'Mem.get(${lit(v)})';
		if (v >= 0xE000 && v < 0xFE00)
			return 'Mem.get(${lit(v & 0xDFFF)})';
		if (v >= 0xFF00) {
			mayTouch = true;
			return 'g.rdSlowT(${lit(v)}, ${time(d)})';
		}
		mayTouch = true; // cartridge RAM / clock, OAM: rare, but the clock wants the exact time
		return 'g.rdSlowT(${lit(v)}, ${time(d)})';
	}

	public function wr(a:String, val:String, d:Int):String {
		var v = constant(a);
		if (v == null) {
			mayTouch = true;
			return 'g.wrT($a, $val, ${time(d)});';
		}
		if (v < 0x8000) {
			mayTouch = true;
			if (banked || v >= 0x4000)
				endsBlock = true;
			return 'g.wrSlow(${lit(v)}, $val);';
		}
		if (v < 0xA000)
			return 'Mem.set(g.vramOff + ${lit(v)}, $val);';
		if ((v >= 0xC000 && v < 0xE000) || (v >= 0xFF80 && v < 0xFFFF))
			return 'Mem.set(${lit(v)}, $val);';
		if (v >= 0xE000 && v < 0xFE00)
			return 'Mem.set(${lit(v & 0xDFFF)}, $val);';
		if (v >= 0xFF00) {
			mayTouch = true;
			return 'g.wrSlowT(${lit(v)}, $val, ${time(d)});';
		}
		mayTouch = true;
		return 'g.wrSlowT(${lit(v)}, $val, ${time(d)});';
	}

	public function rdIO(n:String)
		return rd(lit(0xFF00 | Std.parseInt(n)), 0);

	public function wrIO(n:String, v:String)
		return wr(lit(0xFF00 | Std.parseInt(n)), v, 0);

	public function g(name:String)
		return "g." + name;

	/** Before leaving the block: catch up after a slow access in this instruction. */
	function leave():String
		return (mayTouch ? refresh() + " " : "") + (op == 0xD9 ? "dl = -1; " : "");

	public function jump(t:String, extra:Int, kind:JumpKind)
		return leave() + (extra != 0 ? 'cy += $extra; ' : "") + 'npc = $t; break;';

	public function cjump(cond:String, t:String, extra:Int)
		return 'if ($cond) { cy += $extra; npc = $t; break; }';

	public function ccall(cond:String, t:String, pushCode:String, extra:Int)
		return 'if ($cond) { cy += $extra; $pushCode ${leave()}npc = $t; break; }';

	public function cret(cond:String, popCode:String, v:String, extra:Int)
		return 'if ($cond) { cy += $extra; $popCode ${leave()}npc = $v; break; }';

	public function halt()
		return 'npc = ${lit(nxt)}; g.halt(); dl = -1; break;';

	public function stop()
		return 'g.cycles = cy; g.stop(); cy = g.cycles; dl = -1; npc = ${lit(nxt)}; break;';

	public function illegal()
		return 'g.illegal($op); npc = ${lit(addr)}; dl = -1; break;';

	public function cb()
		return Sm83.cbop(this, imm);
}
