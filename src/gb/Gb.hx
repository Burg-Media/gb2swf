// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package gb;

/**
 * The complete Game Boy. runFrame() runs until the next VBlank.
 *
 * Recompiled code: `blockIndex` maps a ROM offset (bank * 0x4000 + address within
 * the bank) to the number of a basic block in Blocks.run (generated per game).
 * Where there is none, the interpreter executes one instruction. Code in RAM
 * always goes through the interpreter, so a game never fails because code was
 * not recompiled; it only runs slower there.
 */
class Gb extends Cpu {
	public var blockIndex:haxe.ds.Vector<Int> = null;

	// Statistics: instructions executed by the interpreter and by recompiled blocks
	public var instrInterp = 0;
	public var instrRec = 0;

	// Profiling (interpreter only): per ROM offset how often it ran, and whether it was jumped to
	public var profile:haxe.ds.Vector<Int> = null;
	public var entries:haxe.ds.Vector<Int> = null;
	var expectNext = -1;

	/**
	 * Lockstep check: interrupts and frame ends only at block boundaries, and
	 * `traceFn` is called at every block entry. With useBlocks = false the
	 * interpreter runs the same code, so both runs must produce identical traces.
	 */
	public var lockstep = false;
	public var useBlocks = true;
	public var traceFn:Int->Void = null;
	/** Mooneye test ROMs signal the end with `ld b, b`. */
	public var stopOnLdBB = false;
	public var hitLdBB = false;

	public function new(rom:haxe.io.Bytes, ?forceDmg:Bool = false) {
		super(rom, forceDmg);
		ppu = new Ppu(this);
		apu = new Apu();
		computeNextEvent();
	}

	public function runFrame():Void {
		frameLimit = cycles + (Machine.FRAME << ds);
		noChain = lockstep && traceFn != null;
		if (profile != null || lockstep || stopOnLdBB)
			runFrameDebug();
		else
			runFrameFast();
		sync();
		apu.advance(cycles);
		rebase(cycles);
	}

	inline function romOffset(pc:Int):Int {
		return if (pc < 0x4000) (rom0Bank == 0 ? pc : -1) else if (pc < 0x8000) (romBank << 14) + pc - 0x4000 else -1;
	}

	/** Executes one "event" that is not a block: interrupt, halt, or one instruction. Returns false if nothing was done. */
	inline function special(pend:Int, limit:Int):Bool {
		var done = true;
		if (pend != 0 && !locked && !stopped && halted) {
			halted = false;
			cycles += 4; // leaving HALT takes one M-cycle
		}
		if (pend != 0 && ime && !locked && !halted) {
			service(pend);
		} else if (halted) {
			var t = nextEvent;
			if (t > limit)
				t = limit;
			cycles = t > cycles ? t : cycles + 4;
		} else if (haltBug || imeDelay) {
			var ei = imeDelay;
			step();
			instrInterp++;
			// EI takes effect after the next instruction, unless that one was DI
			if (ei && imeDelay) {
				imeDelay = false;
				ime = true;
			}
		} else
			done = false;
		return done;
	}

	inline function runBlocks(k:Int) {
		#if blocks
		updateDeadline();
		Blocks.run(this, k);
		#end
	}

	function runFrameFast():Void {
		ppu.frameDone = false;
		var limit = frameLimit;
		var bi = blockIndex;
		while (!ppu.frameDone && cycles < limit) {
			if (cycles >= nextEvent)
				sync();
			if (special(ie & iflag & 0x1F, limit))
				continue;
			if (bi != null) {
				var off = romOffset(pc);
				if (off >= 0) {
					var k = bi[off];
					if (k > 0) {
						runBlocks(k - 1);
						continue;
					}
				}
			}
			step();
			instrInterp++;
		}
	}

	function atBoundary():Bool {
		if (halted || blockIndex == null)
			return true;
		var o = romOffset(pc);
		return o < 0 || blockIndex[o] > 0;
	}

	function runFrameDebug():Void {
		ppu.frameDone = false;
		var limit = frameLimit;
		var bi = blockIndex;
		while (true) {
			// In lockstep mode the interpreter, like recompiled code, only catches up the
			// peripherals at block boundaries (and on IO access), so both draw identical frames
			if (cycles >= nextEvent && (!lockstep || atBoundary()))
				sync();
			// In lockstep mode a frame may only end where both runs can stop: at a block boundary
			if ((ppu.frameDone || cycles >= limit) && (!lockstep || atBoundary()))
				break;
			var pend = ie & iflag & 0x1F;
			if (lockstep && pend != 0 && !atBoundary())
				pend = 0;
			if (special(pend, limit))
				continue;
			var off = romOffset(pc);
			if (profile != null && off >= 0) {
				profile[off]++;
				if (pc != expectNext)
					entries[off] = 1;
				var op = rd(pc);
				expectNext = (pc + (op == 0xCB ? 2 : Cpu.LEN[op])) & 0xFFFF;
			} else
				expectNext = -1;
			if (stopOnLdBB && rd(pc) == 0x40) {
				hitLdBB = true;
				return;
			}
			if (bi != null && off >= 0) {
				var k = bi[off];
				if (k > 0) {
					if (traceFn != null)
						traceFn(off);
					if (useBlocks) {
						runBlocks(k - 1);
						continue;
					}
				}
			}
			step();
			instrInterp++;
		}
	}

	public function startProfile() {
		var n = romSize;
		profile = new haxe.ds.Vector<Int>(n);
		entries = new haxe.ds.Vector<Int>(n);
		for (i in 0...n) {
			profile[i] = 0;
			entries[i] = 0;
		}
	}

	/** Interrupt dispatch: 5 M-cycles; the vector is chosen after the high byte of PC is pushed. */
	function service(pend:Int) {
		ime = false;
		if (haltBug) {
			// EI; HALT with an interrupt pending: the handler returns to the HALT
			haltBug = false;
			pc = (pc - 1) & 0xFFFF;
		}
		sp = (sp - 1) & 0xFFFF;
		cycles += 12;
		wr(sp, pc >> 8);
		// Pushing onto IE (SP = 0) can cancel the interrupt
		var p2 = ie & iflag & 0x1F;
		sp = (sp - 1) & 0xFFFF;
		cycles += 4;
		wr(sp, pc & 0xFF);
		cycles += 4;
		if (p2 == 0) {
			pc = 0;
			return;
		}
		var bit = 0;
		while ((p2 & (1 << bit)) == 0)
			bit++;
		iflag &= ~(1 << bit);
		pc = 0x40 + (bit << 3);
	}

	/** Cartridge RAM (battery saves), followed by the 48-byte clock trailer for MBC3 + RTC. */
	public function getSave():haxe.io.Bytes {
		var n = ramSize;
		var tail = rtc != null ? rtc.save() : null;
		var b = haxe.io.Bytes.alloc(n + (tail != null ? tail.length : 0));
		for (i in 0...n)
			b.set(i, Mem.get(Mem.ERAM + i));
		if (tail != null)
			b.blit(n, tail, 0, tail.length);
		return b;
	}

	public function setSave(b:haxe.io.Bytes) {
		var n = b.length < ramSize ? b.length : ramSize;
		for (i in 0...n)
			Mem.set(Mem.ERAM + i, b.get(i));
		if (rtc != null && b.length >= ramSize + 44)
			rtc.load(b, ramSize);
	}

	/** Whether this cartridge keeps anything worth saving. */
	public function hasSave():Bool
		return battery && (ramSize > 0 || rtc != null);
}
