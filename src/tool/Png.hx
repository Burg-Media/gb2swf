// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import haxe.io.Bytes;

/** Minimal PNG writer (RGBA) and reader (8-bit RGB/RGBA/palette, no interlace). */
class Png {
	static var crcTable:Array<Int> = null;

	static function crc(b:Bytes, start:Int, len:Int):Int {
		if (crcTable == null) {
			crcTable = [];
			for (n in 0...256) {
				var c = n;
				for (k in 0...8)
					c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
				crcTable.push(c);
			}
		}
		var c = 0xFFFFFFFF;
		for (i in start...start + len)
			c = crcTable[(c ^ b.get(i)) & 0xFF] ^ (c >>> 8);
		return c ^ 0xFFFFFFFF;
	}

	static function be32(b:Bytes, p:Int, v:Int) {
		b.set(p, (v >>> 24) & 0xFF);
		b.set(p + 1, (v >>> 16) & 0xFF);
		b.set(p + 2, (v >>> 8) & 0xFF);
		b.set(p + 3, v & 0xFF);
	}

	static function rd32(b:Bytes, p:Int):Int
		return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);

	/** `rgba` holds width*height pixels as R,G,B,A bytes. */
	public static function encode(w:Int, h:Int, rgba:Bytes):Bytes {
		var raw = Bytes.alloc((w * 4 + 1) * h);
		for (y in 0...h) {
			raw.set(y * (w * 4 + 1), 0);
			raw.blit(y * (w * 4 + 1) + 1, rgba, y * w * 4, w * 4);
		}
		var idat = Host.deflate(raw);
		var chunks = new haxe.io.BytesBuffer();
		chunks.add(Bytes.ofHex("89504e470d0a1a0a"));
		function chunk(type:String, data:Bytes) {
			var c = Bytes.alloc(12 + data.length);
			be32(c, 0, data.length);
			c.blit(4, Bytes.ofString(type), 0, 4);
			c.blit(8, data, 0, data.length);
			be32(c, 8 + data.length, crc(c, 4, 4 + data.length));
			chunks.add(c);
		}
		var ihdr = Bytes.alloc(13);
		be32(ihdr, 0, w);
		be32(ihdr, 4, h);
		ihdr.set(8, 8);
		ihdr.set(9, 6);
		chunk("IHDR", ihdr);
		chunk("IDAT", idat);
		chunk("IEND", Bytes.alloc(0));
		return chunks.getBytes();
	}

	/** Decodes to RGBA bytes. */
	public static function decode(png:Bytes):{w:Int, h:Int, rgba:Bytes} {
		var p = 8;
		var w = 0, h = 0, depth = 0, ctype = 0;
		var idat = new haxe.io.BytesBuffer();
		var pal:Bytes = null;
		while (p < png.length) {
			var len = rd32(png, p);
			var type = png.getString(p + 4, 4);
			var data = png.sub(p + 8, len);
			switch (type) {
				case "IHDR":
					w = rd32(data, 0);
					h = rd32(data, 4);
					depth = data.get(8);
					ctype = data.get(9);
					if (data.get(12) != 0)
						throw "interlaced PNG not supported";
				case "PLTE":
					pal = data;
				case "IDAT":
					idat.add(data);
				default:
			}
			p += 12 + len;
		}
		if (depth != 8 && !(depth < 8 && (ctype == 0 || ctype == 3)))
			throw "unsupported PNG bit depth";
		var bpp = switch (ctype) {
			case 2: 3;
			case 6: 4;
			case 3: 1;
			case 0: 1;
			case 4: 2;
			default: throw "PNG colour type " + ctype;
		}
		var raw = Host.inflate(idat.getBytes());
		var stride = depth < 8 ? Std.int((w * depth + 7) / 8) : w * bpp;
		var cur = Bytes.alloc(stride), prev = Bytes.alloc(stride);
		var out = Bytes.alloc(w * h * 4);
		for (y in 0...h) {
			var f = raw.get(y * (stride + 1));
			var row = y * (stride + 1) + 1;
			for (i in 0...stride) {
				var x = raw.get(row + i);
				var a = i >= bpp ? cur.get(i - bpp) : 0;
				var b = prev.get(i);
				var c = i >= bpp ? prev.get(i - bpp) : 0;
				var v = switch (f) {
					case 0: x;
					case 1: x + a;
					case 2: x + b;
					case 3: x + ((a + b) >> 1);
					default:
						var pp = a + b - c;
						var pa = Std.int(Math.abs(pp - a)), pb = Std.int(Math.abs(pp - b)), pc = Std.int(Math.abs(pp - c));
						x + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c));
				}
				cur.set(i, v & 0xFF);
			}
			if (depth < 8) {
				// Unpack 1/2/4-bit samples to one byte each (grey scaled up to 0-255)
				var unpacked = Bytes.alloc(w);
				var max = (1 << depth) - 1;
				for (x in 0...w) {
					var bit = x * depth;
					var v = (cur.get(bit >> 3) >> (8 - depth - (bit & 7))) & max;
					unpacked.set(x, ctype == 0 ? Std.int(v * 255 / max) : v);
				}
				for (x in 0...w) {
					var o = (y * w + x) * 4;
					var v = unpacked.get(x);
					if (ctype == 3) {
						out.set(o, pal.get(v * 3));
						out.set(o + 1, pal.get(v * 3 + 1));
						out.set(o + 2, pal.get(v * 3 + 2));
					} else {
						out.set(o, v);
						out.set(o + 1, v);
						out.set(o + 2, v);
					}
					out.set(o + 3, 255);
				}
				var t = prev;
				prev = cur;
				cur = t;
				continue;
			}
			for (x in 0...w) {
				var o = (y * w + x) * 4;
				switch (ctype) {
					case 2:
						out.set(o, cur.get(x * 3));
						out.set(o + 1, cur.get(x * 3 + 1));
						out.set(o + 2, cur.get(x * 3 + 2));
						out.set(o + 3, 255);
					case 6:
						out.blit(o, cur, x * 4, 4);
					case 3:
						var i = cur.get(x);
						out.set(o, pal.get(i * 3));
						out.set(o + 1, pal.get(i * 3 + 1));
						out.set(o + 2, pal.get(i * 3 + 2));
						out.set(o + 3, 255);
					case 0:
						var g = cur.get(x);
						out.set(o, g);
						out.set(o + 1, g);
						out.set(o + 2, g);
						out.set(o + 3, 255);
					default:
						var g = cur.get(x * 2);
						out.set(o, g);
						out.set(o + 1, g);
						out.set(o + 2, g);
						out.set(o + 3, cur.get(x * 2 + 1));
				}
			}
			var t = prev;
			prev = cur;
			cur = t;
		}
		return {w: w, h: h, rgba: out};
	}
}
