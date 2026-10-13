// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import gb.Gb;
import gb.Mem;
import haxe.io.Bytes;
import tool.Input;

/** Runs the emulator core without Flash: profiling, checks, test ROMs, screenshots. */
class Headless {
	public static function machine(rom:Bytes, ?forceDmg:Bool = false):Gb
		return new Gb(rom, forceDmg);

	/** Runs `frames` frames with the given input. Stops early on a hang or `ld b, b`. */
	public static function run(g:Gb, frames:Int, input:Input, ?onFrame:Int->Void):Int {
		var f = 0;
		while (f < frames) {
			if (input != null)
				g.setKeys(input.keys(f));
			g.runFrame();
			f++;
			if (onFrame != null)
				onFrame(f);
			if (g.locked || g.hitLdBB)
				break;
		}
		return f;
	}

	/** Profile of an interpreter run: [[offset, count, enteredByJump], ...] */
	public static function profileRows(g:Gb):Array<Array<Int>> {
		var rows = [];
		for (j in 0...g.romSize)
			if (g.profile[j] > 0)
				rows.push([j, g.profile[j], g.entries[j]]);
		return rows;
	}

	/** Framebuffer as RGBA bytes (160x144). */
	public static function rgba():Bytes {
		var out = Bytes.alloc(160 * 144 * 4);
		for (i in 0...160 * 144) {
			var p = Mem.FB + i * 4;
			out.set(i * 4, Mem.get(p + 1));
			out.set(i * 4 + 1, Mem.get(p + 2));
			out.set(i * 4 + 2, Mem.get(p + 3));
			out.set(i * 4 + 3, 255);
		}
		return out;
	}

	public static function png(scale:Int = 1):Bytes {
		var src = rgba();
		if (scale <= 1)
			return Png.encode(160, 144, src);
		var w = 160 * scale, h = 144 * scale;
		var out = Bytes.alloc(w * h * 4);
		for (y in 0...h)
			for (x in 0...w)
				out.setInt32((y * w + x) * 4, src.getInt32(((Std.int(y / scale)) * 160 + Std.int(x / scale)) * 4));
		return Png.encode(w, h, out);
	}

	public static function frameHash():Int {
		var hsh = 0;
		var p = Mem.FB;
		for (q in 0...160 * 144) {
			hsh = (hsh * 31 + Mem.get32(p)) | 0;
			p += 4;
		}
		return hsh;
	}

	// ------------------------------------------------------------------ test ROM verdicts

	/** Blargg tests that report through cartridge RAM: signature DE B0 61 at A001. */
	public static function blarggMemory(g:Gb):{done:Bool, pass:Bool, text:String} {
		if (Mem.get(Mem.ERAM + 1) != 0xDE || Mem.get(Mem.ERAM + 2) != 0xB0 || Mem.get(Mem.ERAM + 3) != 0x61)
			return {done: false, pass: false, text: ""};
		var status = Mem.get(Mem.ERAM);
		var sb = new StringBuf();
		var i = 4;
		while (i < 0x2000 && Mem.get(Mem.ERAM + i) != 0) {
			sb.addChar(Mem.get(Mem.ERAM + i));
			i++;
		}
		return {done: status != 0x80, pass: status == 0, text: sb.toString()};
	}

	/**
	 * Looks for a word on the background tile map, whatever tile number the font
	 * starts at (older Blargg tests only print their result on screen).
	 */
	public static function screenHas(word:String):Bool {
		for (base in [0x9800, 0x9C00]) {
			for (i in 0...0x400 - word.length) {
				var first = Mem.get(base + i);
				var ok = true;
				for (j in 1...word.length)
					if (((Mem.get(base + i + j) - first) & 0xFF) != ((word.charCodeAt(j) - word.charCodeAt(0)) & 0xFF)) {
						ok = false;
						break;
					}
				if (ok)
					return true;
			}
		}
		return false;
	}

	/** Mooneye: after `ld b, b` the registers hold 3 5 8 13 21 34 on success. */
	public static function mooneyePass(g:Gb):Bool
		return g.b == 3 && g.c == 5 && g.d == 8 && g.e == 13 && g.h == 21 && g.l == 34;

	/** Number of pixels that differ from a reference image (RGB compared exactly). */
	public static function compareImage(ref:{w:Int, h:Int, rgba:Bytes}):Int {
		if (ref.w != 160 || ref.h != 144)
			return 160 * 144;
		var mine = rgba();
		var diff = 0;
		for (i in 0...160 * 144) {
			var o = i * 4;
			if (mine.get(o) != ref.rgba.get(o) || mine.get(o + 1) != ref.rgba.get(o + 1) || mine.get(o + 2) != ref.rgba.get(o + 2))
				diff++;
		}
		return diff;
	}
}
