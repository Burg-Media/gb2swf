// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package gb;

/**
 * Picture processing unit (DMG and Game Boy Color). Draws one scanline at the
 * start of mode 3 into the framebuffer at Mem.FB. Runs lazily via advance(); the
 * machine syncs at every mode change (nextEventAt), so register writes between
 * scanlines (scroll splits, status bars) take effect on the right line.
 */
class Ppu {
	public var m:Machine;
	/** Time (CPU T-cycles) up to which the PPU has been brought up to date. */
	public var at = 0;
	var shift = 0; // 1 in double speed mode: the PPU then gets one dot per two CPU cycles

	public var lcdc = 0x91;
	public var stat = 0x85;
	public var scy = 0;
	public var scx = 0;
	public var ly = 0;
	public var lyc = 0;
	public var bgp = 0xFC;
	public var obp0 = 0xFF;
	public var obp1 = 0xFF;
	public var wy = 0;
	public var wx = 0;

	public var dot = 0; // position within the current line (0-455)
	public var mode = 2;
	public var winLine = 0;
	var winTriggered = false; // WY matched LY somewhere in this frame
	public var statLine = false;
	public var frameDone = false;
	public var frames = 0;

	// Game Boy Color palette RAM: 64 bytes each
	var bcps = 0;
	var ocps = 0;
	var opri = 0;
	var bgPalRam = [for (i in 0...64) 0xFF];
	var obPalRam = [for (i in 0...64) 0xFF];

	/** The 4 shades of grey (DMG) as framebuffer pixels. */
	public var shades:Array<Int> = [];

	// Scratch areas in Mem (see Mem.hx)
	static inline var IDX = Mem.SCRATCH; // background colour index per pixel (0-3)
	static inline var PRI = Mem.SCRATCH + 0x100; // CGB: background priority attribute per pixel
	static inline var OBJF = Mem.SCRATCH + 0x200; // sprite pixel of this line: 0 none, 1 in front, 2 behind
	static inline var BGPAL = Mem.SCRATCH + 0x400; // 8 palettes x 4 colours, as framebuffer pixels
	static inline var OBPAL = Mem.SCRATCH + 0x480; // DMG: OBP0 = palette 0, OBP1 = palette 1
	static inline var OBJC = Mem.SCRATCH + 0x800; // sprite pixel colours of this line

	var sel:Array<Int> = [for (i in 0...10) 0];

	public function new(m:Machine) {
		this.m = m;
		// Tile decoding table: entry ((hi << 8) | lo) * 8 + p = colour index of pixel p (0 = left)
		for (v in 0...0x10000) {
			var lo = v & 0xFF, hi = v >> 8;
			var o = Mem.TILES + (v << 3);
			for (p in 0...8)
				Mem.set(o + p, (((hi >> (7 - p)) & 1) << 1) | ((lo >> (7 - p)) & 1));
		}
		for (x in 0...160)
			Mem.set(OBJF + x, 0);
		if (m.cgb)
			for (i in 0...32) {
				Mem.set32(BGPAL + (i << 2), toPixel(0xFFFFFF));
				Mem.set32(OBPAL + (i << 2), toPixel(0xFFFFFF));
			}
		setPalette([0xE0F8D0, 0x88C070, 0x346856, 0x081820]);
	}

	/** DMG colours as 0xRRGGBB, light to dark. */
	public function setPalette(rgb:Array<Int>) {
		shades = [for (c in rgb) toPixel(c)];
		updatePals();
	}

	public static inline function toPixel(rgb:Int):Int {
		// Bytes A, R, G, B in memory; setI32 writes little endian
		return 0xFF | (((rgb >> 16) & 0xFF) << 8) | (((rgb >> 8) & 0xFF) << 16) | ((rgb & 0xFF) << 24);
	}

	/** Game Boy Color RGB555 to a framebuffer pixel (each 5-bit channel scaled to 8 bits). */
	static inline function cgbPixel(lo:Int, hi:Int):Int {
		var v = lo | (hi << 8);
		var r = v & 31, g = (v >> 5) & 31, b = (v >> 10) & 31;
		return toPixel((((r << 3) | (r >> 2)) << 16) | (((g << 3) | (g >> 2)) << 8) | ((b << 3) | (b >> 2)));
	}

	function updatePals() {
		if (m.cgb)
			return; // the Game Boy Color palettes come from palette RAM
		for (i in 0...4) {
			Mem.set32(BGPAL + (i << 2), shades[(bgp >> (i * 2)) & 3]);
			Mem.set32(OBPAL + (i << 2), shades[(obp0 >> (i * 2)) & 3]);
			Mem.set32(OBPAL + 16 + (i << 2), shades[(obp1 >> (i * 2)) & 3]);
		}
	}

	public function speed(ds:Int) {
		shift = ds;
	}

	public function read(addr:Int):Int {
		return switch (addr) {
			case 0xFF40: lcdc;
			case 0xFF41: 0x80 | (stat & 0x78) | (ly == lyc ? 4 : 0) | ((lcdc & 0x80) != 0 ? mode : 0);
			case 0xFF42: scy;
			case 0xFF43: scx;
			case 0xFF44: ly;
			case 0xFF45: lyc;
			case 0xFF46: 0xFF;
			case 0xFF47: bgp;
			case 0xFF48: obp0;
			case 0xFF49: obp1;
			case 0xFF4A: wy;
			case 0xFF4B: wx;
			case 0xFF68: bcps | 0x40;
			case 0xFF69: bgPalRam[bcps & 0x3F];
			case 0xFF6A: ocps | 0x40;
			case 0xFF6B: obPalRam[ocps & 0x3F];
			case 0xFF6C: 0xFE | opri;
			default: 0xFF;
		}
	}

	public function write(addr:Int, v:Int) {
		switch (addr) {
			case 0xFF40:
				var was = (lcdc & 0x80) != 0;
				lcdc = v;
				var on = (v & 0x80) != 0;
				if (was && !on) {
					ly = 0;
					dot = 0;
					mode = 0;
					clearScreen();
					frameDone = true;
				} else if (!was && on) {
					ly = 0;
					dot = 4; // the first line after switching on is slightly shorter
					mode = 2;
					winLine = 0;
					winTriggered = wy == 0;
					updateStat();
				}
			case 0xFF41:
				stat = v & 0x78;
				updateStat();
			case 0xFF42:
				scy = v;
			case 0xFF43:
				scx = v;
			case 0xFF44:
			case 0xFF45:
				lyc = v;
				updateStat();
			case 0xFF47:
				bgp = v;
				updatePals();
			case 0xFF48:
				obp0 = v;
				updatePals();
			case 0xFF49:
				obp1 = v;
				updatePals();
			case 0xFF4A:
				wy = v;
			case 0xFF4B:
				wx = v;
			case 0xFF68:
				bcps = v & 0xBF;
			case 0xFF69:
				var i = bcps & 0x3F;
				bgPalRam[i] = v;
				var p = i & 0x3E;
				Mem.set32(BGPAL + (p << 1), cgbPixel(bgPalRam[p], bgPalRam[p + 1]));
				if ((bcps & 0x80) != 0)
					bcps = 0x80 | ((i + 1) & 0x3F);
			case 0xFF6A:
				ocps = v & 0xBF;
			case 0xFF6B:
				var i = ocps & 0x3F;
				obPalRam[i] = v;
				var p = i & 0x3E;
				Mem.set32(OBPAL + (p << 1), cgbPixel(obPalRam[p], obPalRam[p + 1]));
				if ((ocps & 0x80) != 0)
					ocps = 0x80 | ((i + 1) & 0x3F);
			case 0xFF6C:
				opri = v & 1;
			default:
		}
	}

	function updateStat() {
		var on = (lcdc & 0x80) != 0
			&& (((stat & 0x40) != 0 && ly == lyc)
				|| ((stat & 0x08) != 0 && mode == 0)
				|| ((stat & 0x10) != 0 && mode == 1)
				|| ((stat & 0x20) != 0 && mode == 2));
		if (on && !statLine)
			m.iflag |= 2;
		statLine = on;
	}

	public inline function nextEventAt():Int {
		if ((lcdc & 0x80) == 0)
			return 0x7FFFFFFF;
		var end = if (mode == 2) 80 else if (mode == 3) 252 else 456;
		return at + ((end - dot) << shift);
	}

	public function advance(now:Int) {
		var dt = (now - at) >> shift;
		if (dt <= 0)
			return;
		at += dt << shift;
		if ((lcdc & 0x80) == 0)
			return;
		dot += dt;
		while (true) {
			if (mode == 2) {
				if (dot < 80)
					break;
				mode = 3;
				renderLine();
			} else if (mode == 3) {
				if (dot < 252)
					break;
				mode = 0;
				updateStat();
				if (m.cgb)
					m.hblankDma();
			} else {
				if (dot < 456)
					break;
				dot -= 456;
				ly++;
				if (ly == 144) {
					mode = 1;
					m.iflag |= 1;
					frameDone = true;
					frames++;
				} else if (ly > 153) {
					ly = 0;
					winLine = 0;
					winTriggered = false;
					mode = 2;
				} else if (ly < 144) {
					mode = 2;
				}
				if (ly == wy)
					winTriggered = true;
				updateStat();
			}
		}
	}

	function clearScreen() {
		var c = m.cgb ? toPixel(0xFFFFFF) : shades[0];
		var p = Mem.FB;
		for (i in 0...160 * 144) {
			Mem.set32(p, c);
			p += 4;
		}
	}

	// ------------------------------------------------------------------ rendering

	function renderLine() {
		var y = ly;
		if (y == wy)
			winTriggered = true;
		var out = Mem.FB + y * 640;
		var cgb = m.cgb;
		// Sprites first: if none are on this line, the background needs no index buffer
		var n = (lcdc & 2) != 0 ? selectSprites(y) : 0;
		var keep = n > 0;

		if ((lcdc & 1) != 0 || cgb) {
			var signed = (lcdc & 0x10) == 0;
			var winX = 999;
			if ((lcdc & 0x20) != 0 && winTriggered && wx <= 166)
				winX = wx - 7;
			var limit = winX < 160 ? (winX < 0 ? 0 : winX) : 160;
			var map = ((lcdc & 8) != 0 ? 0x9C00 : 0x9800) + ((((scy + y) & 0xFF) >> 3) << 5);
			drawTiles(map, (scy + y) & 7, scx, 0, limit, out, signed, cgb, true, keep);
			if (winX < 160) {
				var wmap = ((lcdc & 0x40) != 0 ? 0x9C00 : 0x9800) + ((winLine >> 3) << 5);
				drawTiles(wmap, winLine & 7, limit - winX, limit, 160, out, signed, cgb, false, keep);
				winLine++;
			}
		} else {
			// DMG with the background switched off: white, and sprites always on top
			var c = shades[0];
			for (x in 0...160) {
				Mem.set(IDX + x, 0);
				Mem.set32(out + (x << 2), c);
			}
		}
		if (n > 0)
			drawSprites(y, n, out, cgb);
	}

	/**
	 * Draws background or window pixels x0 to x1 (exclusive). `px` is the position in
	 * the tile map at x0. `keep` stores colour indices (and CGB priorities) for the sprites.
	 */
	function drawTiles(map:Int, fine:Int, px:Int, x0:Int, x1:Int, out:Int, signed:Bool, cgb:Bool, wrap:Bool, keep:Bool) {
		var x = x0;
		var pal = BGPAL;
		var prio = 0;
		while (x < x1) {
			var col = wrap ? ((px >> 3) & 31) : (px >> 3);
			var tile = Mem.get(map + col);
			var ta = signed ? 0x9000 + (((tile ^ 0x80) - 0x80) << 4) : 0x8000 + (tile << 4);
			var row = fine;
			var flip = false;
			if (cgb) {
				var attr = Mem.get(Mem.VRAM1 - 0x8000 + map + col);
				if ((attr & 8) != 0)
					ta += Mem.VRAM1 - 0x8000;
				if ((attr & 0x40) != 0)
					row = 7 - fine;
				flip = (attr & 0x20) != 0;
				pal = BGPAL + ((attr & 7) << 4);
				prio = attr & 0x80;
			}
			var t = Mem.TILES + ((Mem.get(ta + (row << 1)) | (Mem.get(ta + (row << 1) + 1) << 8)) << 3);
			var first = px & 7;
			var o = out + (x << 2);
			if (first == 0 && x + 8 <= x1) {
				// Whole tile: the common case, unrolled
				var c0, c1, c2, c3, c4, c5, c6, c7;
				if (!flip) {
					c0 = Mem.get(t);
					c1 = Mem.get(t + 1);
					c2 = Mem.get(t + 2);
					c3 = Mem.get(t + 3);
					c4 = Mem.get(t + 4);
					c5 = Mem.get(t + 5);
					c6 = Mem.get(t + 6);
					c7 = Mem.get(t + 7);
				} else {
					c0 = Mem.get(t + 7);
					c1 = Mem.get(t + 6);
					c2 = Mem.get(t + 5);
					c3 = Mem.get(t + 4);
					c4 = Mem.get(t + 3);
					c5 = Mem.get(t + 2);
					c6 = Mem.get(t + 1);
					c7 = Mem.get(t);
				}
				Mem.set32(o, Mem.get32(pal + (c0 << 2)));
				Mem.set32(o + 4, Mem.get32(pal + (c1 << 2)));
				Mem.set32(o + 8, Mem.get32(pal + (c2 << 2)));
				Mem.set32(o + 12, Mem.get32(pal + (c3 << 2)));
				Mem.set32(o + 16, Mem.get32(pal + (c4 << 2)));
				Mem.set32(o + 20, Mem.get32(pal + (c5 << 2)));
				Mem.set32(o + 24, Mem.get32(pal + (c6 << 2)));
				Mem.set32(o + 28, Mem.get32(pal + (c7 << 2)));
				if (keep) {
					var ix = IDX + x;
					Mem.set(ix, c0);
					Mem.set(ix + 1, c1);
					Mem.set(ix + 2, c2);
					Mem.set(ix + 3, c3);
					Mem.set(ix + 4, c4);
					Mem.set(ix + 5, c5);
					Mem.set(ix + 6, c6);
					Mem.set(ix + 7, c7);
					if (cgb)
						for (i in 0...8)
							Mem.set(PRI + x + i, prio);
				}
				x += 8;
				px += 8;
				continue;
			}
			var p = first;
			while (p < 8 && x < x1) {
				var ci = Mem.get(t + (flip ? 7 - p : p));
				if (keep) {
					Mem.set(IDX + x, ci);
					Mem.set(PRI + x, prio);
				}
				Mem.set32(o, Mem.get32(pal + (ci << 2)));
				o += 4;
				x++;
				px++;
				p++;
			}
		}
	}

	/** Picks the first 10 sprites (in OAM order) on line y, sorted by priority. Returns how many. */
	function selectSprites(y:Int):Int {
		var hgt = (lcdc & 4) != 0 ? 16 : 8;
		var n = 0;
		var i = 0;
		while (i < 40 && n < 10) {
			var sy = Mem.get(0xFE00 + (i << 2)) - 16;
			if (y >= sy && y < sy + hgt)
				sel[n++] = i;
			i++;
		}
		// On DMG the smallest X wins (then the lowest index); on CGB the lowest index
		if (n > 1 && (!m.cgb || opri == 1)) {
			var j = 1;
			while (j < n) {
				var s = sel[j];
				var sx = Mem.get(0xFE01 + (s << 2));
				var k = j - 1;
				while (k >= 0) {
					var o = sel[k];
					var ox = Mem.get(0xFE01 + (o << 2));
					if (ox < sx || (ox == sx && o < s))
						break;
					sel[k + 1] = o;
					k--;
				}
				sel[k + 1] = s;
				j++;
			}
		}
		return n;
	}

	function drawSprites(y:Int, n:Int, out:Int, cgb:Bool) {
		var hgt = (lcdc & 4) != 0 ? 16 : 8;
		// Highest priority first: a pixel belongs to the first sprite that is opaque there
		for (q in 0...n) {
			var o = 0xFE00 + (sel[q] << 2);
			var sy = Mem.get(o) - 16;
			var sx = Mem.get(o + 1) - 8;
			var tile = Mem.get(o + 2);
			var attr = Mem.get(o + 3);
			if (hgt == 16)
				tile &= 0xFE;
			var row = y - sy;
			if ((attr & 0x40) != 0)
				row = hgt - 1 - row;
			var ta = 0x8000 + (tile << 4) + (row << 1);
			if (cgb && (attr & 8) != 0)
				ta += Mem.VRAM1 - 0x8000;
			var t = Mem.TILES + ((Mem.get(ta) | (Mem.get(ta + 1) << 8)) << 3);
			var flip = (attr & 0x20) != 0;
			var flag = (attr & 0x80) != 0 ? 2 : 1;
			var pal = OBPAL + (cgb ? (attr & 7) << 4 : ((attr & 0x10) != 0 ? 16 : 0));
			for (p in 0...8) {
				var xx = sx + p;
				if (xx < 0 || xx >= 160 || Mem.get(OBJF + xx) != 0)
					continue;
				var ci = Mem.get(t + (flip ? 7 - p : p));
				if (ci == 0)
					continue;
				Mem.set(OBJF + xx, flag);
				Mem.set32(OBJC + (xx << 2), Mem.get32(pal + (ci << 2)));
			}
		}
		// Combine with the background, sprite by sprite, clearing the marks as we go
		var master = (lcdc & 1) != 0; // CGB: when off, sprites are always on top
		for (q in 0...n) {
			var sx = Mem.get(0xFE01 + (sel[q] << 2)) - 8;
			for (p in 0...8) {
				var x = sx + p;
				if (x < 0 || x >= 160)
					continue;
				var f = Mem.get(OBJF + x);
				if (f == 0)
					continue;
				Mem.set(OBJF + x, 0);
				if (Mem.get(IDX + x) != 0) {
					if (cgb) {
						if (master && (Mem.get(PRI + x) != 0 || f == 2))
							continue;
					} else if (f == 2)
						continue;
				}
				Mem.set32(out + (x << 2), Mem.get32(OBJC + (x << 2)));
			}
		}
	}
}
