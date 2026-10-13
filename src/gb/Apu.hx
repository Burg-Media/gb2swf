// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package gb;

/**
 * Sound chip. Brought up to date lazily (on register access and at the end of
 * every frame) and writes stereo samples (44.1 kHz) into a ring buffer that the
 * frontend drains.
 *
 * The channel state is kept in plain fields rather than arrays: in Flash/Ruffle
 * every array access costs noticeably more, and advance() runs ~735 times a frame.
 */
class Apu {
	public static inline var RATE = 44100;
	static inline var CLOCK = 4194304.0;
	public static inline var BUF = 16384; // stereo pairs, power of 2

	/** Time (CPU T-cycles) up to which the APU has been brought up to date. */
	public var at = 0;
	var shift = 0; // 1 in double speed mode
	var tNow = 0.0; // own clock (4.194304 MHz), reset every frame
	var nextSample = 0.0;
	var fsTimer = 8192;
	var fsStep = 0;

	public var out:haxe.ds.Vector<Float>;
	public var wpos = 0; // write position (pairs)
	public var rpos = 0; // read position (pairs), advanced by the frontend
	public var enabled = true;

	var regs:Array<Int> = [for (i in 0...0x30) 0];
	var power = true;
	var nr50 = 0x77;
	var nr51 = 0xF3;
	var capL = 0.0;
	var capR = 0.0;

	// Channel 1 (square with sweep)
	var s1On = false;
	var s1Dac = true;
	var s1Len = 0;
	var s1LenEn = false;
	var s1Vol = 0;
	var s1EnvDir = 0;
	var s1EnvPer = 0;
	var s1EnvT = 0;
	var s1Freq = 0;
	var s1Timer = 0;
	var s1Pos = 0;
	var s1Duty = 2;
	var swPer = 0;
	var swT = 0;
	var swShift = 0;
	var swNeg = false;
	var swShadow = 0;
	var swOn = false;

	// Channel 2 (square)
	var s2On = false;
	var s2Dac = false;
	var s2Len = 0;
	var s2LenEn = false;
	var s2Vol = 0;
	var s2EnvDir = 0;
	var s2EnvPer = 0;
	var s2EnvT = 0;
	var s2Freq = 0;
	var s2Timer = 0;
	var s2Pos = 0;
	var s2Duty = 0;

	// Channel 3 (wave table)
	var wvOn = false;
	var wvDac = false;
	var wvLen = 0;
	var wvLenEn = false;
	var wvShift = 4;
	var wvFreq = 0;
	var wvTimer = 0;
	var wvPos = 0;

	// Channel 4 (noise)
	var nzOn = false;
	var nzDac = false;
	var nzLen = 0;
	var nzLenEn = false;
	var nzVol = 0;
	var nzEnvDir = 0;
	var nzEnvPer = 0;
	var nzEnvT = 0;
	var nzLfsr = 0x7FFF;
	var nzWide = true;
	var nzPeriod = 8;
	var nzTimer = 8;
	var nzClock = true;

	static var DUTY:Array<Int> = [0x01, 0x81, 0x87, 0x7E];
	static var MASK:Array<Int> = [
		0x80, 0x3F, 0x00, 0xFF, 0xBF, 0xFF, 0x3F, 0x00, 0xFF, 0xBF, 0x7F, 0xFF, 0x9F, 0xFF, 0xBF, 0xFF,
		0xFF, 0x00, 0x00, 0xBF, 0x00, 0x00, 0x70, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
	];

	public function new() {
		out = new haxe.ds.Vector<Float>(BUF * 2);
		for (i in 0...BUF * 2)
			out[i] = 0;
		var init = [0x80, 0xBF, 0xF3, 0xFF, 0xBF, 0xFF, 0x3F, 0x00, 0xFF, 0xBF, 0x7F, 0xFF, 0x9F, 0xFF, 0xBF, 0xFF, 0xFF, 0x00, 0x00, 0xBF, 0x77, 0xF3];
		for (i in 0...init.length)
			regs[i] = init[i];
	}

	public function rebase(dt:Int) {
		at -= dt;
		nextSample -= tNow;
		tNow = 0;
	}

	public function speed(ds:Int) {
		shift = ds;
	}

	public function read(addr:Int):Int {
		if (addr >= 0xFF30)
			return Mem.get(addr);
		var r = addr - 0xFF10;
		if (addr == 0xFF26)
			return (power ? 0x80 : 0) | 0x70 | (s1On ? 1 : 0) | (s2On ? 2 : 0) | (wvOn ? 4 : 0) | (nzOn ? 8 : 0);
		return regs[r] | MASK[r];
	}

	public function write(addr:Int, v:Int) {
		if (addr >= 0xFF30) {
			Mem.set(addr, v);
			return;
		}
		var r = addr - 0xFF10;
		if (addr == 0xFF26) {
			var on = (v & 0x80) != 0;
			if (power && !on) {
				for (i in 0...0x16)
					writeReg(i, 0);
				s1On = s2On = wvOn = nzOn = false;
			}
			if (!power && on)
				fsStep = 0;
			power = on;
			return;
		}
		if (!power)
			return;
		writeReg(r, v);
	}

	function writeReg(r:Int, v:Int) {
		regs[r] = v;
		switch (r) {
			case 0x00:
				swPer = (v >> 4) & 7;
				swNeg = (v & 8) != 0;
				swShift = v & 7;
			case 0x01:
				s1Duty = v >> 6;
				s1Len = 64 - (v & 63);
			case 0x06:
				s2Duty = v >> 6;
				s2Len = 64 - (v & 63);
			case 0x02:
				s1Dac = (v & 0xF8) != 0;
				if (!s1Dac)
					s1On = false;
			case 0x07:
				s2Dac = (v & 0xF8) != 0;
				if (!s2Dac)
					s2On = false;
			case 0x03:
				s1Freq = (s1Freq & 0x700) | v;
			case 0x08:
				s2Freq = (s2Freq & 0x700) | v;
			case 0x04:
				s1Freq = (s1Freq & 0xFF) | ((v & 7) << 8);
				s1LenEn = (v & 0x40) != 0;
				if ((v & 0x80) != 0)
					trigger1();
			case 0x09:
				s2Freq = (s2Freq & 0xFF) | ((v & 7) << 8);
				s2LenEn = (v & 0x40) != 0;
				if ((v & 0x80) != 0)
					trigger2();
			case 0x0A:
				wvDac = (v & 0x80) != 0;
				if (!wvDac)
					wvOn = false;
			case 0x0B:
				wvLen = 256 - v;
			case 0x0C:
				var s = (v >> 5) & 3;
				wvShift = s == 0 ? 4 : s - 1;
			case 0x0D:
				wvFreq = (wvFreq & 0x700) | v;
			case 0x0E:
				wvFreq = (wvFreq & 0xFF) | ((v & 7) << 8);
				wvLenEn = (v & 0x40) != 0;
				if ((v & 0x80) != 0) {
					wvOn = wvDac;
					if (wvLen == 0)
						wvLen = 256;
					wvTimer = (2048 - wvFreq) * 2;
					wvPos = 0;
				}
			case 0x10:
				nzLen = 64 - (v & 63);
			case 0x11:
				nzDac = (v & 0xF8) != 0;
				if (!nzDac)
					nzOn = false;
			case 0x12:
				var s = v >> 4;
				var dv = v & 7;
				nzPeriod = (dv == 0 ? 8 : dv * 16) << s;
				nzWide = (v & 8) == 0;
				nzClock = s < 14;
			case 0x13:
				nzLenEn = (v & 0x40) != 0;
				if ((v & 0x80) != 0) {
					nzOn = nzDac;
					if (nzLen == 0)
						nzLen = 64;
					var e = regs[0x11];
					nzVol = e >> 4;
					nzEnvDir = (e & 8) != 0 ? 1 : -1;
					nzEnvPer = e & 7;
					nzEnvT = nzEnvPer;
					nzLfsr = 0x7FFF;
					nzTimer = nzPeriod;
				}
			case 0x14:
				nr50 = v;
			case 0x15:
				nr51 = v;
			default:
		}
	}

	function trigger1() {
		s1On = s1Dac;
		if (s1Len == 0)
			s1Len = 64;
		s1Timer = (2048 - s1Freq) * 4;
		var e = regs[0x02];
		s1Vol = e >> 4;
		s1EnvDir = (e & 8) != 0 ? 1 : -1;
		s1EnvPer = e & 7;
		s1EnvT = s1EnvPer;
		swShadow = s1Freq;
		swT = swPer != 0 ? swPer : 8;
		swOn = swPer != 0 || swShift != 0;
		if (swShift != 0)
			sweepCalc();
	}

	function trigger2() {
		s2On = s2Dac;
		if (s2Len == 0)
			s2Len = 64;
		s2Timer = (2048 - s2Freq) * 4;
		var e = regs[0x07];
		s2Vol = e >> 4;
		s2EnvDir = (e & 8) != 0 ? 1 : -1;
		s2EnvPer = e & 7;
		s2EnvT = s2EnvPer;
	}

	function sweepCalc():Int {
		var d = swShadow >> swShift;
		var f = swNeg ? swShadow - d : swShadow + d;
		if (f > 2047)
			s1On = false;
		return f;
	}

	/** Frame sequencer (512 Hz): length counters, sweep, volume envelopes. */
	function frameSeq() {
		var s = fsStep;
		fsStep = (fsStep + 1) & 7;
		if ((s & 1) == 0) {
			if (s1LenEn && s1Len > 0 && --s1Len == 0)
				s1On = false;
			if (s2LenEn && s2Len > 0 && --s2Len == 0)
				s2On = false;
			if (wvLenEn && wvLen > 0 && --wvLen == 0)
				wvOn = false;
			if (nzLenEn && nzLen > 0 && --nzLen == 0)
				nzOn = false;
		}
		if (s == 2 || s == 6) {
			if (--swT <= 0) {
				swT = swPer != 0 ? swPer : 8;
				if (swOn && swPer != 0) {
					var f = sweepCalc();
					if (f <= 2047 && swShift != 0) {
						swShadow = f;
						s1Freq = f;
						sweepCalc();
					}
				}
			}
		}
		if (s == 7) {
			if (s1EnvPer != 0 && --s1EnvT <= 0) {
				s1EnvT = s1EnvPer;
				var nv = s1Vol + s1EnvDir;
				if (nv >= 0 && nv <= 15)
					s1Vol = nv;
			}
			if (s2EnvPer != 0 && --s2EnvT <= 0) {
				s2EnvT = s2EnvPer;
				var nv = s2Vol + s2EnvDir;
				if (nv >= 0 && nv <= 15)
					s2Vol = nv;
			}
			if (nzEnvPer != 0 && --nzEnvT <= 0) {
				nzEnvT = nzEnvPer;
				var nv = nzVol + nzEnvDir;
				if (nv >= 0 && nv <= 15)
					nzVol = nv;
			}
		}
	}

	/** Runs the channels `n` cycles ahead. */
	inline function stepChannels(n:Int) {
		var t = s1Timer - n;
		if (t <= 0) {
			var per = (2048 - s1Freq) * 4;
			var p = s1Pos;
			while (t <= 0) {
				t += per;
				p = (p + 1) & 7;
			}
			s1Pos = p;
		}
		s1Timer = t;
		t = s2Timer - n;
		if (t <= 0) {
			var per = (2048 - s2Freq) * 4;
			var p = s2Pos;
			while (t <= 0) {
				t += per;
				p = (p + 1) & 7;
			}
			s2Pos = p;
		}
		s2Timer = t;
		t = wvTimer - n;
		if (t <= 0) {
			var per = (2048 - wvFreq) * 2;
			var p = wvPos;
			while (t <= 0) {
				t += per;
				p = (p + 1) & 31;
			}
			wvPos = p;
		}
		wvTimer = t;
		if (nzClock && nzOn) {
			t = nzTimer - n;
			if (t <= 0) {
				var lfsr = nzLfsr, per = nzPeriod, wide = nzWide;
				while (t <= 0) {
					t += per;
					var x = (lfsr ^ (lfsr >> 1)) & 1;
					lfsr = (lfsr >> 1) | (x << 14);
					if (!wide)
						lfsr = (lfsr & ~0x40) | (x << 6);
				}
				nzLfsr = lfsr;
			}
			nzTimer = t;
		}
	}

	function emit() {
		var l = 0.0, r = 0.0;
		if (power) {
			var mix = nr51;
			if (s1On) {
				var v = ((DUTY[s1Duty] >> s1Pos) & 1) * s1Vol;
				if ((mix & 0x10) != 0)
					l += v;
				if ((mix & 1) != 0)
					r += v;
			}
			if (s2On) {
				var v = ((DUTY[s2Duty] >> s2Pos) & 1) * s2Vol;
				if ((mix & 0x20) != 0)
					l += v;
				if ((mix & 2) != 0)
					r += v;
			}
			if (wvOn) {
				var bt = Mem.get(0xFF30 + (wvPos >> 1));
				var v = ((wvPos & 1) == 0 ? bt >> 4 : bt & 0xF) >> wvShift;
				if ((mix & 0x40) != 0)
					l += v;
				if ((mix & 4) != 0)
					r += v;
			}
			if (nzOn) {
				var v = (nzLfsr & 1) == 0 ? nzVol : 0;
				if ((mix & 0x80) != 0)
					l += v;
				if ((mix & 8) != 0)
					r += v;
			}
			l *= (((nr50 >> 4) & 7) + 1) / (15 * 4 * 8);
			r *= ((nr50 & 7) + 1) / (15 * 4 * 8);
		}
		// High-pass filter (like the capacitor in the real Game Boy)
		var ol = l - capL;
		capL = l - ol * 0.996;
		var or = r - capR;
		capR = r - or * 0.996;
		var i = (wpos & (BUF - 1)) << 1;
		out[i] = ol;
		out[i + 1] = or;
		wpos++;
	}

	public function advance(now:Int) {
		var dt = (now - at) >> shift;
		if (dt <= 0)
			return;
		at += dt << shift;
		var t = tNow;
		var end = tNow + dt;
		var ns = nextSample;
		var fs = fsTimer;
		while (t < end) {
			// Next event: a sample, the frame sequencer or the end
			var step = Std.int(Math.ceil(ns - t));
			if (step < 1)
				step = 1;
			if (fs < step)
				step = fs;
			if (end - t < step)
				step = Std.int(Math.ceil(end - t));
			stepChannels(step);
			t += step;
			fs -= step;
			if (fs <= 0) {
				fs += 8192;
				frameSeq();
			}
			if (t >= ns) {
				ns += CLOCK / RATE;
				if (enabled)
					emit();
			}
		}
		tNow = t;
		nextSample = ns;
		fsTimer = fs;
	}
}
