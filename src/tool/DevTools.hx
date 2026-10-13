// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

/** Developer commands: `gb2swf dev <command>`. */
class DevTools {
	/**
	 * Runs a ROM headless on the interpreter. --keys "120:S,130:,200:A" presses buttons
	 * at frames (R L U D A B s=select S=start; empty = release).
	 */
	static function runRom(args:Array<String>):Int {
		var rom = Host.readBytes(args[0]);
		var frames = Std.parseInt(args[1]);
		var script = new Map<Int, Int>();
		var ki = args.indexOf("--keys");
		if (ki >= 0)
			for (part in args[ki + 1].split(",")) {
				var kv = part.split(":");
				var mask = 0;
				for (ch in kv[1].split(""))
					mask |= switch (ch) {
						case "R": 1;
						case "L": 2;
						case "U": 4;
						case "D": 8;
						case "A": 16;
						case "B": 32;
						case "s": 64;
						case "S": 128;
						default: 0;
					};
				script.set(Std.parseInt(kv[0]), mask);
			}
		var g = Headless.machine(rom, args.indexOf("--dmg") >= 0);
		var t0 = Host.now();
		var f = 0;
		while (f < frames) {
			if (script.exists(f))
				g.setKeys(script.get(f));
			g.runFrame();
			f++;
			if (g.locked)
				break;
		}
		var ms = Host.now() - t0;
		if (args.indexOf("--serial") >= 0)
			Host.print(g.serial.toString());
		Host.print('$f frames in ${Math.round(ms)} ms, pc=${StringTools.hex(g.pc, 4)} bank=${g.romBank}${g.locked ? " (hung on an illegal opcode)" : ""}');
		var pi = args.indexOf("--png");
		if (pi >= 0) {
			var si = args.indexOf("--scale");
			Host.writeBytes(args[pi + 1], Headless.png(si >= 0 ? Std.parseInt(args[si + 1]) : 1));
		}
		return 0;
	}

	/** Where does the interpreter still run on an unseen input? (ROM offsets and RAM) */
	static function uncovered(romPath:String, work:String):Int {
		var rom = Host.readBytes(romPath);
		var rec = new Recompiler(rom);
		var dir = Host.join(work, "profile");
		for (f in Host.list(dir))
			rec.addProfile(haxe.Json.parse(Host.readText(Host.join(dir, f))));
		rec.run();
		var covered = rec.coveredOffsets();
		var g = Headless.machine(rom);
		g.startProfile();
		var ram = new Map<Int, Int>();
		var total = 0;
		Headless.run(g, 6000, new tool.Input.Fuzz(1004));
		var rows = [];
		for (j in 0...g.romSize)
			if (g.profile[j] > 0) {
				total += g.profile[j];
				if (!covered.exists(j))
					rows.push([j, g.profile[j]]);
			}
		rows.sort((a, b) -> b[1] - a[1]);
		var unc = 0;
		for (r in rows)
			unc += r[1];
		Host.print('ROM instructions: $total, not recompiled: $unc; all interpreter steps: ${g.instrInterp} (the rest ran from RAM or after EI/HALT)');
		for (r in rows.slice(0, 15))
			Host.print('  ${StringTools.hex(r[0], 5)}  ${r[1]}x  ${Sm83.mnemonic(rom.get(r[0]), Sm83.LENGTH[rom.get(r[0])] == 2 ? rom.get(r[0] + 1) : rom.get(r[0] + 1) | (rom.get(r[0] + 2) << 8), r[0] & 0x3FFF | (r[0] >= 0x4000 ? 0x4000 : 0), rom.get(r[0] + 1))}');
		return 0;
	}

	public static function run(args:Array<String>):Int {
		switch (args[0]) {
			case "gen-interp":
				var out = Host.join(Host.root(), "src/gb/Cpu.hx");
				Host.writeText(out, GenInterp.generate());
				Host.print("written: " + out);
				return 0;
			case "player-cache":
				Player.prepare();
				Host.print("player/ruffle/ruffle-wasm.js is ready");
				return 0;
			case "run":
				return runRom(args.slice(1));
			case "uncovered":
				return uncovered(args[1], args[2]);
			case "testroms":
				return TestRoms.run(args.slice(1));
			default:
				Host.print("dev commands: gen-interp, testroms, run <rom> <frames> [--keys f:BTN,...] [--png file] [--scale n] [--serial], uncovered <rom> <workdir>");
				return 1;
		}
	}
}
