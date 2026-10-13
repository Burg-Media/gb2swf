// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package gb;

/**
 * Everything of the Game Boy except the instructions themselves: memory map,
 * cartridge (MBC, RTC), timer, joypad, serial port, interrupts and the Game Boy
 * Color extras (VRAM/WRAM banks, double speed, HDMA).
 *
 * Time is counted in CPU T-cycles in `cycles`, relative to the start of the
 * current frame (4.194304 MHz, or twice that in double speed mode). Peripherals
 * run lazily behind the CPU and catch up in sync(): on every IO access and as soon
 * as `cycles >= nextEvent`.
 */
class Machine {
	/** T-cycles per frame at normal speed. */
	public static inline var FRAME = 70224;

	// CPU registers (used directly by Cpu.hx and the recompiled blocks)
	public var a = 0x01;
	public var b = 0x00;
	public var c = 0x13;
	public var d = 0x00;
	public var e = 0xD8;
	public var h = 0x01;
	public var l = 0x4D;
	public var sp = 0xFFFE;
	public var pc = 0x0100;
	public var fz = true;
	public var fn = false;
	public var fh = true;
	public var fc = true;
	public var ime = false;
	public var imeDelay = false;
	public var halted = false;
	public var haltBug = false;
	public var stopped = false;
	/** An illegal opcode was executed: the real CPU hangs. */
	public var locked = false;

	public var cycles = 0;
	public var nextEvent = 0;

	/**
	 * For recompiled code: the time up to which blocks may run back to back
	 * without returning to the main loop (next peripheral event or end of the
	 * frame); -1 when the main loop must look first (interrupt, frame done).
	 */
	public var deadline = -1;
	public var frameLimit = 0;
	/** Lockstep checks run one block at a time. */
	public var noChain = false;
	/** Set by the slow memory paths used by recompiled code; extra cycles they caused (HDMA). */
	public var touched = false;
	public var extra = 0;
	public var ie = 0;
	public var iflag = 0xE1;

	// Cartridge
	public var romSize = 0;
	public var romBanks = 2;
	public var mbc = 0; // 0 none, 1 MBC1, 2 MBC2, 3 MBC3, 5 MBC5
	public var ramSize = 0;
	public var battery = false;
	public var rumble = false;
	public var rtc:Rtc = null;
	public var romBank = 1; // bank mapped at 0x4000-0x7FFF
	public var rom0Bank = 0; // bank mapped at 0x0000-0x3FFF (MBC1 mode 1 only)
	public var ramBank = 0;
	public var ramEnabled = false;
	public var bankLo = 1;
	public var bankHi = 0;
	public var mbc1Mode = 0;
	public var rom0Off = Mem.ROM;
	public var romXOff = Mem.ROM;
	public var ramOff = Mem.ERAM - 0xA000;
	/** Set on every write to cartridge RAM (or the clock), cleared by the frontend after saving. */
	public var ramDirty = false;
	public var title = "";
	public var cartType = 0;
	public var headerChecksum = 0;
	public var globalChecksum = 0;

	// Game Boy Color
	public var cgb = false;
	public var ds = 0; // 1 in double speed mode
	public var key1 = 0;
	public var vbk = 0;
	public var vramOff = 0; // added to 0x8000-0x9FFF to reach the selected VRAM bank
	public var svbk = 1;
	var hdmaSrc = 0;
	var hdmaDst = 0;
	var hdmaLeft = 0; // 16-byte blocks still to copy in HBlank mode
	var hdmaActive = false;

	// Timer
	public var divCnt = 0xABCC;
	public var tima = 0;
	public var tma = 0;
	public var tac = 0xF8;
	public var timerAt = 0;

	/** Emulated time in seconds since power-on (normal-speed clock). */
	public var clockSeconds = 0.0;

	// Joypad: bit set = pressed. 0 right, 1 left, 2 up, 3 down, 4 A, 5 B, 6 select, 7 start
	public var keys = 0;
	public var p1 = 0x30;

	// Serial port (test ROMs print their results here)
	public var sb = 0;
	public var sc = 0;
	public var serial = new StringBuf();

	public var ppu:Ppu;
	public var apu:Apu;

	public function new(rom:haxe.io.Bytes, ?forceDmg:Bool = false) {
		romSize = rom.length;
		Mem.init(Mem.ROM + romSize + 0x8000);
		for (i in 0...romSize)
			Mem.set(Mem.ROM + i, rom.get(i));
		romBanks = romSize >> 14;
		if (romBanks < 2)
			romBanks = 2;
		cartType = Mem.get(Mem.ROM + 0x147);
		switch (cartType) {
			case 0x01, 0x02, 0x03:
				mbc = 1;
			case 0x05, 0x06:
				mbc = 2;
			case 0x0F, 0x10, 0x11, 0x12, 0x13:
				mbc = 3;
			case 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E:
				mbc = 5;
			default:
				mbc = 0;
		}
		battery = [0x03, 0x06, 0x09, 0x0F, 0x10, 0x13, 0x1B, 0x1E].indexOf(cartType) >= 0;
		rumble = cartType >= 0x1C && cartType <= 0x1E;
		if (cartType == 0x0F || cartType == 0x10)
			rtc = new Rtc(emulatedSeconds);
		ramSize = [0, 0x800, 0x2000, 0x8000, 0x20000, 0x10000][Mem.get(Mem.ROM + 0x149) % 6];
		if (mbc == 2)
			ramSize = 0x200;
		if (mbc == 0 && ramSize > 0)
			ramEnabled = true; // ROM+RAM cartridges have no enable register
		var cgbFlag = Mem.get(Mem.ROM + 0x143);
		cgb = !forceDmg && (cgbFlag & 0x80) != 0;
		// Title: 16 bytes on old cartridges, 15 or 11 when the CGB flag and maker code are used
		var sbuf = new StringBuf();
		var end = (cgbFlag & 0x80) != 0 ? 0x143 : 0x144;
		for (i in 0x134...end) {
			var ch = Mem.get(Mem.ROM + i);
			if (ch == 0)
				break;
			if (ch >= 0x20 && ch < 0x7F)
				sbuf.addChar(ch);
		}
		title = StringTools.trim(sbuf.toString());
		headerChecksum = Mem.get(Mem.ROM + 0x14D);
		globalChecksum = (Mem.get(Mem.ROM + 0x14E) << 8) | Mem.get(Mem.ROM + 0x14F);
		for (i in 0...0x20000)
			Mem.set(Mem.ERAM + i, 0xFF);
		if (cgb) {
			// Register values after the Game Boy Color boot ROM
			a = 0x11;
			fz = true;
			fn = fh = fc = false;
			b = 0x00;
			c = 0x00;
			d = 0xFF;
			e = 0x56;
			h = 0x00;
			l = 0x0D;
		}
		updateBanks();
	}

	// ------------------------------------------------------------------ memory

	public inline function rd(addr:Int):Int {
		return if (addr < 0x4000) Mem.get(rom0Off + addr); else if (addr < 0x8000) Mem.get(romXOff + addr); else if (addr >= 0xC000
			&& addr < 0xFE00) Mem.get(addr & 0xDFFF); else if (addr >= 0xFF80 && addr < 0xFFFF) Mem.get(addr); else rdSlow(addr);
	}

	public inline function wr(addr:Int, v:Int):Void {
		if (addr >= 0xC000 && addr < 0xFE00)
			Mem.set(addr & 0xDFFF, v);
		else if (addr >= 0xFF80 && addr < 0xFFFF)
			Mem.set(addr, v);
		else
			wrSlow(addr, v);
	}

	/**
	 * Read `d` T-cycles before the end of the current instruction (its cycles have
	 * already been added). Only IO cares about the exact moment.
	 */
	public inline function rdAt(addr:Int, d:Int):Int {
		return if (addr >= 0xC000 && addr < 0xFE00) Mem.get(addr & 0xDFFF); else if (addr >= 0xFF80
			&& addr < 0xFFFF) Mem.get(addr); else rdEarly(addr, d);
	}

	public inline function wrAt(addr:Int, v:Int, d:Int):Void {
		if (addr >= 0xC000 && addr < 0xFE00)
			Mem.set(addr & 0xDFFF, v);
		else if (addr >= 0xFF80 && addr < 0xFFFF)
			Mem.set(addr, v);
		else
			wrEarly(addr, v, d);
	}

	// Memory access for recompiled code. Blocks keep the time in a local variable,
	// so they pass the current time `t`; g.cycles is only brought up to date when a
	// block chain ends. Slow paths set `touched` so the block reloads what may have
	// changed (deadline, extra cycles, ROM bank).

	public inline function rdT(addr:Int, t:Int):Int {
		return if (addr < 0x4000) Mem.get(rom0Off + addr); else if (addr < 0x8000) Mem.get(romXOff + addr); else if (addr >= 0xC000
			&& addr < 0xFE00) Mem.get(addr & 0xDFFF); else if (addr >= 0xFF80 && addr < 0xFFFF) Mem.get(addr); else rdSlowT(addr, t);
	}

	public inline function wrT(addr:Int, v:Int, t:Int):Void {
		if (addr >= 0xC000 && addr < 0xFE00)
			Mem.set(addr & 0xDFFF, v);
		else if (addr >= 0xFF80 && addr < 0xFFFF)
			Mem.set(addr, v);
		else
			wrSlowT(addr, v, t);
	}

	public function rdSlowT(addr:Int, t:Int):Int {
		var saved = cycles;
		cycles = t;
		var v = rdSlow(addr);
		extra += cycles - t;
		cycles = saved;
		touched = true;
		return v;
	}

	public function wrSlowT(addr:Int, v:Int, t:Int):Void {
		var saved = cycles;
		cycles = t;
		wrSlow(addr, v);
		extra += cycles - t;
		cycles = saved;
		touched = true;
	}

	function rdEarly(addr:Int, d:Int):Int {
		cycles -= d;
		var v = rd(addr);
		cycles += d;
		return v;
	}

	function wrEarly(addr:Int, v:Int, d:Int):Void {
		cycles -= d;
		wrSlow(addr, v);
		cycles += d;
	}

	public function rdSlow(addr:Int):Int {
		if (addr < 0x8000)
			return rd(addr);
		if (addr < 0xA000)
			return Mem.get(vramOff + addr);
		if (addr < 0xC000) {
			if (!ramEnabled)
				return 0xFF;
			if (mbc == 3 && ramBank >= 8)
				return rtc != null && ramBank <= 0x0C ? rtc.read(ramBank) : 0xFF;
			if (ramSize == 0)
				return 0xFF;
			if (mbc == 2)
				return Mem.get(Mem.ERAM + (addr & 0x1FF)) | 0xF0;
			return Mem.get(ramOff + addr);
		}
		if (addr < 0xFE00)
			return Mem.get(addr & 0xDFFF);
		if (addr < 0xFF00)
			return addr < 0xFEA0 ? Mem.get(addr) : 0;
		return rdIO(addr);
	}

	public function wrSlow(addr:Int, v:Int):Void {
		if (addr < 0x8000) {
			mbcWrite(addr, v);
		} else if (addr < 0xA000) {
			Mem.set(vramOff + addr, v);
		} else if (addr < 0xC000) {
			if (!ramEnabled)
				return;
			if (mbc == 3 && ramBank >= 8) {
				if (rtc != null && ramBank <= 0x0C) {
					rtc.write(ramBank, v);
					ramDirty = true;
				}
				return;
			}
			if (ramSize == 0)
				return;
			if (mbc == 2)
				Mem.set(Mem.ERAM + (addr & 0x1FF), v | 0xF0);
			else
				Mem.set(ramOff + addr, v);
			ramDirty = true;
		} else if (addr < 0xFE00) {
			Mem.set(addr & 0xDFFF, v);
		} else if (addr < 0xFF00) {
			if (addr < 0xFEA0)
				Mem.set(addr, v);
		} else {
			wrIO(addr, v);
		}
	}

	// ------------------------------------------------------------------ cartridge

	function mbcWrite(addr:Int, v:Int) {
		touched = true;
		switch (mbc) {
			case 1:
				if (addr < 0x2000)
					ramEnabled = (v & 0xF) == 0xA;
				else if (addr < 0x4000) {
					bankLo = v & 0x1F;
					if (bankLo == 0)
						bankLo = 1;
				} else if (addr < 0x6000)
					bankHi = v & 3;
				else
					mbc1Mode = v & 1;
				romBank = ((bankHi << 5) | bankLo) % romBanks;
				rom0Bank = mbc1Mode == 1 ? ((bankHi << 5) % romBanks) : 0;
				ramBank = mbc1Mode == 1 ? bankHi : 0;
			case 2:
				if (addr < 0x4000) {
					if ((addr & 0x100) == 0)
						ramEnabled = (v & 0xF) == 0xA;
					else {
						// The zero check looks at the register, before it is cut to the ROM size
						var r = v & 0xF;
						romBank = (r == 0 ? 1 : r) % romBanks;
					}
				}
			case 3:
				if (addr < 0x2000)
					ramEnabled = (v & 0xF) == 0xA;
				else if (addr < 0x4000) {
					var r = v & 0x7F;
					romBank = (r == 0 ? 1 : r) % romBanks;
				} else if (addr < 0x6000)
					ramBank = v & 0xF;
				else if (rtc != null)
					rtc.latchWrite(v);
			case 5:
				if (addr < 0x2000)
					ramEnabled = (v & 0xF) == 0xA;
				else if (addr < 0x3000)
					romBank = ((romBank & 0x100) | v) % romBanks;
				else if (addr < 0x4000)
					romBank = ((romBank & 0xFF) | ((v & 1) << 8)) % romBanks;
				else if (addr < 0x6000)
					ramBank = rumble ? v & 7 : v & 0xF; // on rumble cartridges bit 3 drives the motor
			default:
		}
		updateBanks();
	}

	function updateBanks() {
		rom0Off = Mem.ROM + rom0Bank * 0x4000;
		romXOff = Mem.ROM + romBank * 0x4000 - 0x4000;
		var rb = ramSize > 0x2000 ? (ramBank & ((ramSize >> 13) - 1)) : 0;
		ramOff = Mem.ERAM + rb * 0x2000 - 0xA000;
	}

	// ------------------------------------------------------------------ IO

	public function rdIO(addr:Int):Int {
		if (addr == 0xFFFF)
			return ie;
		if (addr >= 0xFF80)
			return Mem.get(addr);
		sync();
		switch (addr) {
			case 0xFF00:
				var r = 0xC0 | (p1 & 0x30) | 0x0F;
				if ((p1 & 0x10) == 0)
					r &= ~(keys & 0x0F);
				if ((p1 & 0x20) == 0)
					r &= ~((keys >> 4) & 0x0F);
				return r;
			case 0xFF01:
				return sb;
			case 0xFF02:
				return sc | (cgb ? 0x7C : 0x7E);
			case 0xFF04:
				return (divCnt >> 8) & 0xFF;
			case 0xFF05:
				return tima;
			case 0xFF06:
				return tma;
			case 0xFF07:
				return tac | 0xF8;
			case 0xFF0F:
				return iflag | 0xE0;
			default:
		}
		if (addr >= 0xFF10 && addr < 0xFF40) {
			apu.advance(cycles);
			return apu.read(addr);
		}
		if (addr >= 0xFF40 && addr < 0xFF4C)
			return ppu.read(addr);
		if (!cgb)
			return 0xFF;
		return switch (addr) {
			case 0xFF4D: (ds << 7) | 0x7E | (key1 & 1);
			case 0xFF4F: 0xFE | vbk;
			case 0xFF55: hdmaActive ? ((hdmaLeft - 1) & 0x7F) : 0xFF;
			case 0xFF68, 0xFF69, 0xFF6A, 0xFF6B, 0xFF6C: ppu.read(addr);
			case 0xFF70: 0xF8 | svbk;
			case 0xFF72, 0xFF73, 0xFF74: Mem.get(addr);
			case 0xFF75: Mem.get(addr) | 0x8F;
			case 0xFF76, 0xFF77: 0x00;
			default: 0xFF;
		}
	}

	public function wrIO(addr:Int, v:Int):Void {
		if (addr == 0xFFFF) {
			ie = v;
			updateDeadline();
			return;
		}
		sync();
		switch (addr) {
			case 0xFF00:
				p1 = v & 0x30;
			case 0xFF01:
				sb = v;
			case 0xFF02:
				sc = v & (cgb ? 0x83 : 0x81);
				if ((v & 0x81) == 0x81) {
					// No second Game Boy connected: "sent" at once, 0xFF received
					serial.addChar(sb);
					sb = 0xFF;
					sc &= 0x7F;
					iflag |= 8;
				}
			case 0xFF04:
				// Resetting DIV can produce a falling edge, and so a TIMA tick
				if ((tac & 4) != 0 && (divCnt & (timerPeriod() >> 1)) != 0)
					timaTick(1);
				divCnt = 0;
			case 0xFF05:
				tima = v;
			case 0xFF06:
				tma = v;
			case 0xFF07:
				// Changing the timer input can also produce a falling edge
				var was = (tac & 4) != 0 && (divCnt & (timerPeriod() >> 1)) != 0;
				tac = v & 7;
				var now = (tac & 4) != 0 && (divCnt & (timerPeriod() >> 1)) != 0;
				if (was && !now)
					timaTick(1);
			case 0xFF0F:
				iflag = v & 0x1F;
			case 0xFF46:
				// OAM DMA, done at once (the CPU runs from HRAM during the transfer anyway)
				var src = v << 8;
				for (i in 0...0xA0)
					Mem.set(0xFE00 + i, rd(src + i));
			default:
				if (addr >= 0xFF10 && addr < 0xFF40) {
					apu.advance(cycles);
					apu.write(addr, v);
				} else if (addr >= 0xFF40 && addr < 0xFF4C)
					ppu.write(addr, v);
				else if (cgb)
					wrCgb(addr, v);
		}
		computeNextEvent();
	}

	function wrCgb(addr:Int, v:Int) {
		switch (addr) {
			case 0xFF4D:
				key1 = (key1 & 0x80) | (v & 1);
			case 0xFF4F:
				vbk = v & 1;
				vramOff = vbk == 0 ? 0 : Mem.VRAM1 - 0x8000;
			case 0xFF51:
				hdmaSrc = (hdmaSrc & 0xFF) | (v << 8);
			case 0xFF52:
				hdmaSrc = (hdmaSrc & 0xFF00) | (v & 0xF0);
			case 0xFF53:
				hdmaDst = (hdmaDst & 0xFF) | ((v & 0x1F) << 8);
			case 0xFF54:
				hdmaDst = (hdmaDst & 0xFF00) | (v & 0xF0);
			case 0xFF55:
				if (hdmaActive && (v & 0x80) == 0) {
					hdmaActive = false; // stops a running HBlank transfer
				} else if ((v & 0x80) == 0) {
					// General purpose DMA: everything now, the CPU waits
					var n = (v & 0x7F) + 1;
					for (i in 0...n)
						hdmaBlock();
					cycles += (32 << ds) * n;
				} else {
					hdmaLeft = (v & 0x7F) + 1;
					hdmaActive = true;
					if ((ppu.lcdc & 0x80) == 0 || ppu.mode == 0)
						hblankDma();
				}
			case 0xFF68, 0xFF69, 0xFF6A, 0xFF6B, 0xFF6C:
				ppu.write(addr, v);
			case 0xFF70:
				setWramBank(v & 7);
			case 0xFF72, 0xFF73, 0xFF74, 0xFF75:
				Mem.set(addr, v);
			default:
		}
	}

	function hdmaBlock() {
		for (i in 0...16) {
			var v = rd((hdmaSrc + i) & 0xFFFF);
			Mem.set(vramOff + 0x8000 + ((hdmaDst + i) & 0x1FFF), v);
		}
		hdmaSrc = (hdmaSrc + 16) & 0xFFFF;
		hdmaDst = (hdmaDst + 16) & 0x1FF0;
	}

	/** Called by the PPU at the start of every HBlank (lines 0-143). */
	public function hblankDma():Void {
		if (!hdmaActive)
			return;
		hdmaBlock();
		hdmaLeft--;
		if (hdmaLeft <= 0)
			hdmaActive = false;
	}

	/** WRAM bank switch: the selected bank always lives at 0xD000, the others are parked. */
	function setWramBank(n:Int) {
		if (n == 0)
			n = 1;
		if (n == svbk)
			return;
		var park = Mem.WRAMX + svbk * 0x1000;
		var load = Mem.WRAMX + n * 0x1000;
		for (i in 0...0x1000) {
			Mem.set(park + i, Mem.get(0xD000 + i));
			Mem.set(0xD000 + i, Mem.get(load + i));
		}
		svbk = n;
	}

	// ------------------------------------------------------------------ timer

	inline function timerPeriod():Int {
		return switch (tac & 3) {
			case 0: 1024;
			case 1: 16;
			case 2: 64;
			default: 256;
		}
	}

	inline function timerShift():Int {
		return switch (tac & 3) {
			case 0: 10;
			case 1: 4;
			case 2: 6;
			default: 8;
		}
	}

	function timaTick(n:Int) {
		tima += n;
		while (tima > 0xFF) {
			tima = tma + (tima - 0x100);
			iflag |= 4;
		}
	}

	function timerAdvance() {
		var dt = cycles - timerAt;
		if (dt <= 0)
			return;
		timerAt = cycles;
		var old = divCnt;
		var nw = old + dt;
		if ((tac & 4) != 0) {
			var s = timerShift();
			var ticks = (nw >> s) - (old >> s);
			if (ticks > 0)
				timaTick(ticks);
		}
		divCnt = nw & 0xFFFF;
	}

	/** Lets the peripherals catch up to `cycles`. */
	public function sync():Void {
		ppu.advance(cycles);
		timerAdvance();
		computeNextEvent();
	}

	public function computeNextEvent():Void {
		var nxt = ppu.nextEventAt();
		if ((tac & 4) != 0) {
			var per = timerPeriod();
			var t = timerAt + (per - (divCnt & (per - 1))) + (0xFF - tima) * per;
			if (t < nxt)
				nxt = t;
		}
		nextEvent = nxt;
		updateDeadline();
	}

	public function updateDeadline():Void {
		if (noChain || ppu.frameDone || (ime && (ie & iflag & 0x1F) != 0))
			deadline = -1;
		else
			deadline = nextEvent < frameLimit ? nextEvent : frameLimit;
	}

	/** After every frame all timestamps are shifted back so that `cycles` stays small. */
	public function rebase(dt:Int):Void {
		cycles -= dt;
		frameLimit -= dt;
		timerAt -= dt;
		ppu.at -= dt;
		apu.rebase(dt);
		clockSeconds += (dt >> ds) / 4194304.0;
		computeNextEvent();
	}

	// ------------------------------------------------------------------ CPU helpers

	/** Emulated time in seconds since power-on, to the cycle. */
	public function emulatedSeconds():Float
		return clockSeconds + (cycles >> ds) / 4194304.0;

	public function halt():Void {
		if (!ime && (ie & iflag & 0x1F) != 0)
			haltBug = true; // HALT with an interrupt already pending: the next byte is read twice
		else
			halted = true;
	}

	public function stop():Void {
		if (cgb && (key1 & 1) != 0) {
			// Speed switch
			sync();
			apu.advance(cycles);
			ds ^= 1;
			key1 = ds << 7;
			ppu.speed(ds);
			apu.speed(ds);
			divCnt = 0;
			computeNextEvent();
			return;
		}
		// Real STOP: everything sleeps until a button is pressed
		divCnt = 0;
		stopped = true;
		halted = true;
	}

	public function illegal(op:Int):Void {
		locked = true;
		halted = true;
	}

	public function setKeys(k:Int):Void {
		var pressed = k & ~keys;
		keys = k;
		if (pressed != 0) {
			iflag |= 0x10;
			if (stopped) {
				stopped = false;
				halted = false;
			}
		}
	}
}
