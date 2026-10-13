// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package gb;

/**
 * One flat memory block for the whole machine. On Flash this is "domain memory"
 * (the fastest memory access in AVM2 and Ruffle), elsewhere a Uint8Array or Bytes.
 *
 * Layout (offsets into the block):
 *   0x00000-0x0FFFF  address space 0x8000-0xFFFF at its own address
 *                    (VRAM bank 0, WRAM, OAM, IO, HRAM; 0xD000-0xDFFF holds the
 *                    currently selected WRAM bank)
 *   0x10000-0x10FFF  scratch for the scanline renderer (pixel indices, priorities,
 *                    palettes as framebuffer pixels, sprite pixels)
 *   0x20000-0x3FFFF  cartridge RAM (max. 128 KB)
 *   0x40000-0x567FF  framebuffer 160x144, 32 bit (byte order of BitmapData.setPixels)
 *   0x58000-0x59FFF  VRAM bank 1 (Game Boy Color)
 *   0x5A000-0x61FFF  WRAM banks 0-7 while not mapped at 0xD000 (Game Boy Color)
 *   0x80000-0xFFFFF  tile decoding table: for every pair of tile bytes (lo, hi) the
 *                    8 colour indices (0-3), so the renderer needs no bit fiddling
 *   0x100000-...     ROM
 */
class Mem {
	public static inline var SCRATCH = 0x10000;
	public static inline var ERAM = 0x20000;
	public static inline var FB = 0x40000;
	public static inline var VRAM1 = 0x58000;
	public static inline var WRAMX = 0x5A000;
	public static inline var TILES = 0x80000;
	public static inline var ROM = 0x100000;

	#if flash
	public static var bytes:flash.utils.ByteArray;

	public static function init(size:Int) {
		bytes = new flash.utils.ByteArray();
		bytes.length = size;
		flash.Memory.select(bytes);
	}

	public static inline function get(a:Int):Int
		return flash.Memory.getByte(a);

	public static inline function set(a:Int, v:Int):Void
		flash.Memory.setByte(a, v);

	public static inline function set32(a:Int, v:Int):Void
		flash.Memory.setI32(a, v);

	public static inline function get32(a:Int):Int
		return flash.Memory.getI32(a);
	#elseif js
	public static var u8:js.lib.Uint8Array;
	public static var i32:js.lib.Int32Array;

	public static function init(size:Int) {
		size = (size + 3) & ~3;
		var buf = new js.lib.ArrayBuffer(size);
		u8 = new js.lib.Uint8Array(buf);
		i32 = new js.lib.Int32Array(buf);
	}

	public static inline function get(a:Int):Int
		return u8[a];

	public static inline function set(a:Int, v:Int):Void
		u8[a] = v;

	public static inline function set32(a:Int, v:Int):Void
		i32[a >> 2] = v;

	public static inline function get32(a:Int):Int
		return i32[a >> 2];
	#else
	public static var b:haxe.io.Bytes;

	public static function init(size:Int)
		b = haxe.io.Bytes.alloc((size + 3) & ~3);

	public static inline function get(a:Int):Int
		return b.get(a);

	public static inline function set(a:Int, v:Int):Void
		b.set(a, v);

	public static inline function set32(a:Int, v:Int):Void
		b.setInt32(a, v);

	public static inline function get32(a:Int):Int
		return b.getInt32(a);
	#end
}
