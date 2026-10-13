// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package gb;

/**
 * MBC3 real-time clock.
 *
 * The clock is kept as register values plus the time (in seconds) at which they
 * were valid; reading brings them up to date. Where "now" comes from is up to the
 * frontend: the Flash player uses the wall clock (so time passes while the game
 * is closed, like on a real cartridge), the headless tools use emulated time so
 * that runs are reproducible.
 */
class Rtc {
	public var sec = 0;
	public var min = 0;
	public var hour = 0;
	public var days = 0; // 9 bits
	public var halt = false;
	public var carry = false;

	public var latched:Array<Int> = [0, 0, 0, 0, 0];

	/** Current time in seconds (any epoch, but saves use Unix time). */
	var now:Void->Float;

	var base = 0.0; // time at which the registers were last brought up to date
	var frozen = 0.0; // while halted: the part of a second that had passed
	var latchArm = false;

	public function new(now:Void->Float) {
		setClock(now);
	}

	/** Uses another time source; the registers keep their values. */
	public function setClock(now:Void->Float) {
		this.now = now;
		base = now() - frozen;
	}

	/** Brings the registers up to the current time. */
	public function update():Void {
		var t = now();
		if (halt) {
			base = t - frozen;
			return;
		}
		var dt = Math.floor(t - base);
		if (dt <= 0)
			return;
		base += dt;
		advance(dt);
	}

	/** Adds `n` seconds, with the counter behaviour of the real chip. */
	public function advance(n:Float):Void {
		// Out-of-range values (a game can write e.g. 63 seconds) only roll over
		// at the counter width, without a carry; step those one second at a time.
		while (n > 0 && (sec > 59 || min > 59 || hour > 23)) {
			tick();
			n--;
		}
		if (n <= 0)
			return;
		var total = sec + min * 60.0 + hour * 3600.0 + days * 86400.0 + n;
		var d = Math.floor(total / 86400);
		var rest = Std.int(total - d * 86400.0);
		hour = Std.int(rest / 3600);
		min = Std.int((rest % 3600) / 60);
		sec = rest % 60;
		if (d >= 512) {
			carry = true;
			d = d % 512;
		}
		days = Std.int(d);
	}

	function tick() {
		sec = (sec + 1) & 63;
		if (sec != 60)
			return;
		sec = 0;
		min = (min + 1) & 63;
		if (min != 60)
			return;
		min = 0;
		hour = (hour + 1) & 31;
		if (hour != 24)
			return;
		hour = 0;
		days++;
		if (days == 512) {
			days = 0;
			carry = true;
		}
	}

	/** Write to 0x6000-0x7FFF: writing 0 and then 1 copies the clock to the latch. */
	public function latchWrite(v:Int):Void {
		if (v == 0)
			latchArm = true;
		else {
			if (v == 1 && latchArm) {
				update();
				latched = [sec, min, hour, days & 0xFF, dh()];
			}
			latchArm = false;
		}
	}

	inline function dh():Int
		return ((days >> 8) & 1) | (halt ? 0x40 : 0) | (carry ? 0x80 : 0);

	/** Register 0x08-0x0C as selected through the RAM bank number. */
	public function read(reg:Int):Int {
		return switch (reg) {
			case 0x08: latched[0] & 0x3F;
			case 0x09: latched[1] & 0x3F;
			case 0x0A: latched[2] & 0x1F;
			case 0x0B: latched[3];
			default: latched[4] & 0xC1;
		}
	}

	public function write(reg:Int, v:Int):Void {
		update();
		switch (reg) {
			case 0x08:
				sec = v & 63;
				base = now(); // writing the seconds resets the sub-second counter
				frozen = 0;
			case 0x09:
				min = v & 63;
			case 0x0A:
				hour = v & 31;
			case 0x0B:
				days = (days & 0x100) | v;
			default:
				days = (days & 0xFF) | ((v & 1) << 8);
				var h = (v & 0x40) != 0;
				if (h && !halt)
					frozen = now() - base; // stopping keeps the part of a second that had passed
				else if (!h && halt)
					base = now() - frozen;
				halt = h;
				carry = (v & 0x80) != 0;
		}
		// The written value can be read back straight away
		latched[reg - 8] = switch (reg) {
			case 0x08: sec;
			case 0x09: min;
			case 0x0A: hour;
			case 0x0B: days & 0xFF;
			default: dh();
		}
	}

	/**
	 * The 48-byte trailer that BGB, mGBA and VBA-M append to .sav files:
	 * live S M H DL DH, latched S M H DL DH (32-bit little endian each), then a
	 * 64-bit Unix timestamp.
	 */
	public function save():haxe.io.Bytes {
		update();
		var b = haxe.io.Bytes.alloc(48);
		var live = [sec, min, hour, days & 0xFF, dh()];
		for (i in 0...5) {
			b.setInt32(i * 4, live[i]);
			b.setInt32(20 + i * 4, latched[i]);
		}
		var ts = base;
		b.setInt32(40, Std.int(ts % 4294967296.0));
		b.setInt32(44, Std.int(ts / 4294967296.0));
		return b;
	}

	public function load(b:haxe.io.Bytes, pos:Int):Void {
		var len = b.length - pos;
		if (len < 44)
			return;
		sec = b.getInt32(pos) & 63;
		min = b.getInt32(pos + 4) & 63;
		hour = b.getInt32(pos + 8) & 31;
		var dl = b.getInt32(pos + 12) & 0xFF;
		var dhv = b.getInt32(pos + 16);
		days = dl | ((dhv & 1) << 8);
		halt = (dhv & 0x40) != 0;
		carry = (dhv & 0x80) != 0;
		for (i in 0...5)
			latched[i] = b.getInt32(pos + 20 + i * 4) & 0xFF;
		var lo:Float = b.getInt32(pos + 40);
		if (lo < 0)
			lo += 4294967296.0;
		var hi:Float = len >= 48 ? b.getInt32(pos + 44) : 0;
		var ts = lo + hi * 4294967296.0;
		var t = now();
		// A timestamp in the future or absurdly far back: just continue from now
		base = (ts > t || ts < t - 50 * 365 * 86400.0) ? t : ts;
		update();
	}
}
