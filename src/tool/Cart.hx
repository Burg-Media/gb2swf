// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import haxe.io.Bytes;

/** Cartridge header information, for checks and the build report. */
class Cart {
	public var title:String;
	public var type:Int;
	public var typeName:String;
	public var supported:Bool;
	public var romSize:Int;
	public var ramSize:Int;
	public var cgbFlag:Int;
	public var headerChecksum:Int;
	public var headerOk:Bool;
	public var globalChecksum:Int;
	public var sha1:String;

	static final TYPES:Map<Int, String> = [
		0x00 => "ROM only", 0x01 => "MBC1", 0x02 => "MBC1+RAM", 0x03 => "MBC1+RAM+BATTERY", 0x05 => "MBC2", 0x06 => "MBC2+BATTERY",
		0x08 => "ROM+RAM", 0x09 => "ROM+RAM+BATTERY", 0x0B => "MMM01", 0x0C => "MMM01+RAM", 0x0D => "MMM01+RAM+BATTERY",
		0x0F => "MBC3+TIMER+BATTERY", 0x10 => "MBC3+TIMER+RAM+BATTERY", 0x11 => "MBC3", 0x12 => "MBC3+RAM", 0x13 => "MBC3+RAM+BATTERY",
		0x19 => "MBC5", 0x1A => "MBC5+RAM", 0x1B => "MBC5+RAM+BATTERY", 0x1C => "MBC5+RUMBLE", 0x1D => "MBC5+RUMBLE+RAM",
		0x1E => "MBC5+RUMBLE+RAM+BATTERY", 0x20 => "MBC6", 0x22 => "MBC7+SENSOR+RUMBLE+RAM+BATTERY", 0xFC => "POCKET CAMERA",
		0xFD => "BANDAI TAMA5", 0xFE => "HuC3", 0xFF => "HuC1+RAM+BATTERY"
	];

	static final SUPPORTED = [0x00, 0x08, 0x09, 0x01, 0x02, 0x03, 0x05, 0x06, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E];

	public function new(rom:Bytes) {
		if (rom.length < 0x150)
			throw "file is too small to be a Game Boy ROM";
		var sb = new StringBuf();
		cgbFlag = rom.get(0x143);
		for (i in 0x134...((cgbFlag & 0x80) != 0 ? 0x143 : 0x144)) {
			var c = rom.get(i);
			if (c == 0)
				break;
			if (c >= 0x20 && c < 0x7F)
				sb.addChar(c);
		}
		title = StringTools.trim(sb.toString());
		type = rom.get(0x147);
		typeName = TYPES.exists(type) ? TYPES.get(type) : "unknown (0x" + StringTools.hex(type, 2) + ")";
		supported = SUPPORTED.indexOf(type) >= 0;
		romSize = rom.length;
		ramSize = [0, 0x800, 0x2000, 0x8000, 0x20000, 0x10000][rom.get(0x149) % 6];
		if (type == 0x05 || type == 0x06)
			ramSize = 0x200;
		headerChecksum = rom.get(0x14D);
		var x = 0;
		for (i in 0x134...0x14D)
			x = (x - rom.get(i) - 1) & 0xFF;
		headerOk = x == headerChecksum;
		globalChecksum = (rom.get(0x14E) << 8) | rom.get(0x14F);
		sha1 = Host.sha1(rom);
	}

	public function mode():String {
		return if ((cgbFlag & 0xC0) == 0xC0) "Game Boy Color only" else if ((cgbFlag & 0x80) != 0) "Game Boy Color (also runs on Game Boy)" else
			"Game Boy";
	}

	public function describe():String {
		var lines = [
			'Title:      ${title == "" ? "(none)" : title}',
			'Hardware:   ${mode()}',
			'Cartridge:  $typeName${supported ? "" : "  <- NOT SUPPORTED"}',
			'ROM / RAM:  ${romSize >> 10} KiB / ${ramSize >= 1024 ? (ramSize >> 10) + " KiB" : ramSize + " bytes"}',
			'Checksums:  header 0x${StringTools.hex(headerChecksum, 2)} (${headerOk ? "valid" : "INVALID"}), global 0x${StringTools.hex(globalChecksum, 4)}',
			'SHA-1:      $sha1'
		];
		return lines.join("\n");
	}
}
