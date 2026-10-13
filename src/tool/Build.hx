// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import haxe.io.Bytes;
import tool.Input;

typedef BuildOptions = {
	rom:String,
	outDir:String,
	workDir:String,
	name:String,
	interpOnly:Bool,
	recordings:Array<String>,
	seeds:Int,
	frames:Int,
	palette:Array<Int>,
	keys:String,
	forceDmg:Bool,
	names:String,
	check:Bool,
	force:Bool,
	title:String,
	player:Bool,
	verbose:Bool,
	strict:Bool
}

/**
 * The whole conversion: profile -> recompile -> lockstep check -> SWF -> HTML player.
 */
class Build {
	var o:BuildOptions;
	var rom:Bytes;
	var cart:Cart;
	var log = new StringBuf();
	var t0:Float;

	public function new(o:BuildOptions)
		this.o = o;

	function say(s:String) {
		Host.print(s);
		log.add(s + "\n");
	}

	function detail(s:String) {
		if (o.verbose)
			Host.print("  " + s);
		log.add("  " + s + "\n");
	}

	function elapsed():String
		return Std.string(Math.round((Host.now() - t0) / 100) / 10) + " s";

	public function run():Int {
		t0 = Host.now();
		rom = Host.readBytes(o.rom);
		cart = new Cart(rom);
		say("gb2swf " + Version.VERSION + "  " + Host.basename(o.rom));
		say(cart.describe());
		if (!cart.supported && !o.force) {
			say('\nThis cartridge type (${cart.typeName}) is not supported. Use --force to build anyway; it will most likely not work.');
			return 2;
		}
		if (!cart.headerOk)
			say("Warning: the header checksum is wrong. A real Game Boy would refuse this ROM; it may be a bad dump.");
		if (cart.cgbFlag & 0x80 != 0 && o.forceDmg)
			say("Running in Game Boy (DMG) mode as requested (--dmg).");
		Toolchain.check();
		Host.mkdir(o.workDir);
		Host.mkdir(o.outDir);
		var romCopy = Host.join(o.workDir, "rom.bin");
		Host.writeBytes(romCopy, rom);

		var recDir = Host.join(o.workDir, "rec");
		Host.remove(recDir);
		var report:Dynamic = {
			version: Version.VERSION,
			rom: Host.basename(o.rom),
			title: cart.title,
			sha1: cart.sha1,
			cartridge: cart.typeName,
			mode: (cart.cgbFlag & 0x80) != 0 && !o.forceDmg ? "cgb" : "dmg"
		};

		if (!o.interpOnly) {
			var rec = new Recompiler(rom);
			if (o.names != null && Host.exists(o.names))
				rec.loadNames(Host.readText(o.names));
			say("\n[1/4] Profiling (finding the code that runs)");
			for (p in profile())
				rec.addProfile(p);
			say('  (${elapsed()})');
			say("\n[2/4] Recompiling");
			var blacklist = new Map<Int, Bool>();
			var files = rec.run();
			writeRec(recDir, files);
			say('  ${rec.blockCount} blocks, ${rec.instrCount} instructions translated (of ${rec.executedCount} seen running)');
			report.blocks = rec.blockCount;
			report.instructions = rec.instrCount;

			say("\n[3/4] Checking: interpreter and recompiled code must behave identically");
			var tc = Host.now();
			var ok = !o.check;
			if (!o.check)
				say("  skipped (--no-check)");
			var attempt = 0;
			while (o.check && !ok) {
				attempt++;
				var r = lockstep(recDir);
				if (r.ok) {
					ok = true;
					for (run in (r.runs : Array<Dynamic>))
						detail('${run.name}: ${run.frames} frames, ${run.entries} block entries identical');
					say("  passed (" + [for (run in (r.runs : Array<Dynamic>)) run.name].join(", ") + ") in " + Math.round((Host.now() - tc) / 1000) + " s");
					break;
				}
				var bad:Dynamic = null;
				for (run in (r.runs : Array<Dynamic>))
					if (run.mismatch != null && bad == null)
						bad = run;
				var m:Dynamic = bad.mismatch;
				say('  difference in ${bad.name} at block entry ${m.entry}: expected ${m.expected}, got ${m.got}');
				if (m.previousBlock == null || m.previousBlock < 0 || attempt >= 8) {
					say("  could not isolate the difference: building with the interpreter only (slower, but correct)");
					o.interpOnly = true;
					report.fallback = "interpreter only after a failed check";
					break;
				}
				// Leave the block that produced the difference to the interpreter and try again
				blacklist.set(m.previousBlock, true);
				say('  excluding block ${StringTools.hex(m.previousBlock, 5)} from recompilation and checking again');
				var rec2 = new Recompiler(rom);
				if (o.names != null && Host.exists(o.names))
					rec2.loadNames(Host.readText(o.names));
				for (p in profile(true))
					rec2.addProfile(p);
				rec2.exclude(blacklist);
				files = rec2.run();
				rec = rec2;
				writeRec(recDir, files);
			}
			report.excludedBlocks = [for (k in blacklist.keys()) k];
			report.checked = o.check && !o.interpOnly;
			if (!o.interpOnly) {
				var tcov = Host.now();
				var cov = coverage(rec);
				report.coverage = cov;
				say('  recompiled share on unseen input: ${cov.validation}% of executed instructions (profiling runs: ${cov.profiled}%)');
				detail('coverage measured in ${Math.round((Host.now() - tcov) / 1000)} s');
			}
		} else
			say("\nInterpreter only (--interp-only): no profiling or recompilation.");

		say('\n[4/4] Building the SWF');
		var ts = Host.now();
		var swf = Host.join(o.outDir, o.name + ".swf");
		buildSwf(swf, o.interpOnly ? null : recDir);
		var swfSize = Host.size(swf);
		report.swfBytes = swfSize;
		say('  ${swf}  (${Math.round(swfSize / 1024)} KiB, ${Math.round((Host.now() - ts) / 1000)} s)');
		if (o.player) {
			var dir = Host.join(o.outDir, o.name + "_html");
			Player.write(dir, swf, o.name, o.title != null ? o.title : (cart.title != "" ? cart.title : o.name));
			say("  " + Host.join(dir, "index.html") + "  (open in a browser, works offline)");
		}
		report.seconds = Math.round((Host.now() - t0) / 100) / 10;
		Host.writeText(Host.join(o.workDir, "report.json"), haxe.Json.stringify(report, null, "  "));
		Host.writeText(Host.join(o.workDir, "build.log"), log.toString());
		say('\nDone in ${elapsed()}.');
		if (o.strict && (report.fallback != null || (report.excludedBlocks != null && report.excludedBlocks.length > 0))) {
			say("--strict: the check found differences (see above)");
			return 3;
		}
		return 0;
	}

	function writeRec(dir:String, files:Map<String, String>) {
		Host.remove(dir);
		Host.mkdir(dir);
		for (k in files.keys())
			Host.writeText(Host.join(dir, k), files.get(k));
	}

	// ------------------------------------------------------------------ profiling

	var profiles:Array<Array<Array<Int>>> = null;

	function inputs(validation:Bool):Array<{input:Input, frames:Int}> {
		var list:Array<{input:Input, frames:Int}> = [];
		if (validation) {
			list.push({input: new Fuzz(1000 + o.seeds), frames: o.frames});
			return list;
		}
		list.push({input: new Attract(), frames: Std.int(Math.min(o.frames, 5400))});
		for (s in 1...o.seeds + 1)
			list.push({input: new Fuzz(s), frames: o.frames});
		for (f in o.recordings) {
			var rp = new Replay(Host.readText(f), Host.basename(f));
			list.push({input: rp, frames: rp.frames});
		}
		return list;
	}

	function profile(cached:Bool = false):Array<Array<Array<Int>>> {
		if (cached && profiles != null)
			return profiles;
		profiles = [];
		var dir = Host.join(o.workDir, "profile");
		Host.remove(dir);
		Host.mkdir(dir);
		var i = 0;
		for (r in inputs(false)) {
			var t = Host.now();
			var g = Headless.machine(rom, o.forceDmg);
			if (Std.isOfType(r.input, Replay)) {
				var rp:Replay = cast r.input;
				if (rp.save != null)
					g.setSave(rp.save);
			}
			g.startProfile();
			var n = Headless.run(g, r.frames, r.input);
			var rows = Headless.profileRows(g);
			profiles.push(rows);
			Host.writeText(Host.join(dir, 'run${++i}.json'), haxe.Json.stringify(rows));
			var replay = "";
			if (Std.isOfType(r.input, Replay)) {
				var rp:Replay = cast r.input;
				if (rp.endHash != null)
					replay = rp.endHash == Headless.frameHash() ? "  [replayed exactly]" : "  [replay ended elsewhere than the recording; its code still counts]";
			}
			say('  ${r.input.describe()}: $n frames, ${rows.length} code bytes reached (${Math.round(Host.now() - t)} ms)'
				+ (g.locked ? "  [game hung on an illegal instruction]" : "") + replay);
		}
		return profiles;
	}

	/** Exact share of executed instructions that fall inside recompiled blocks. */
	function coverage(rec:Recompiler):{validation:Float, profiled:Float} {
		var covered = rec.coveredOffsets();
		function measure(list:Array<{input:Input, frames:Int}>):Float {
			var inBlocks = 0.0, total = 0.0;
			for (r in list) {
				var g = Headless.machine(rom, o.forceDmg);
				if (Std.isOfType(r.input, Replay)) {
					var rp:Replay = cast r.input;
					if (rp.save != null)
						g.setSave(rp.save);
				}
				g.startProfile();
				Headless.run(g, r.frames, r.input);
				for (j in 0...g.romSize) {
					var c = g.profile[j];
					if (c > 0) {
						total += c;
						if (covered.exists(j))
							inBlocks += c;
					}
				}
				total += g.instrInterp - sumProfile(g); // instructions outside ROM (RAM code): never recompiled
			}
			return total > 0 ? Math.floor(inBlocks / total * 1000) / 10 : 0;
		}
		return {validation: measure(inputs(true)), profiled: measure(inputs(false))};
	}

	static function sumProfile(g:gb.Gb):Float {
		var s = 0.0;
		for (j in 0...g.romSize)
			s += g.profile[j];
		return s;
	}

	// ------------------------------------------------------------------ check

	function lockstep(recDir:String):Dynamic {
		var js = Host.join(o.workDir, "harness.js");
		Toolchain.haxe([
			"-cp", Host.join(Host.root(), "src"), "-cp", recDir, "-D", "blocks", "-main", "tool.Harness", "-js", js, "-D", "js-es=6", "-dce",
			"full"
		]);
		var runs:Array<Dynamic> = [{type: "attract", frames: Std.int(Math.min(o.frames, 3600))}];
		runs.push({type: "fuzz", seed: 1, frames: Std.int(Math.min(o.frames, 3600))});
		runs.push({type: "fuzz", seed: 1000 + o.seeds, frames: Std.int(Math.min(o.frames, 3600))});
		for (f in o.recordings)
			runs.push({type: "replay", file: Host.resolve(f), frames: 0});
		for (r in runs)
			if (r.type == "replay")
				r.frames = new Replay(Host.readText(r.file), r.file).frames;
		var spec = Host.join(o.workDir, "lockstep.json");
		Host.writeText(spec, haxe.Json.stringify({forceDmg: o.forceDmg, runs: runs}));
		var r = Toolchain.node(js, ["lockstep", Host.join(o.workDir, "rom.bin"), spec]);
		if (r.code != 0)
			throw "lockstep check crashed:\n" + r.err;
		return haxe.Json.parse(StringTools.trim(r.out));
	}

	// ------------------------------------------------------------------ SWF

	function buildSwf(out:String, recDir:Null<String>) {
		var cfg = {
			keys: o.keys,
			palette: [for (c in o.palette) StringTools.hex(c, 6)].join(","),
			dmg: o.forceDmg,
			name: o.name
		};
		var cfgFile = Host.join(o.workDir, "config.json");
		Host.writeText(cfgFile, haxe.Json.stringify(cfg));
		var args = ["-cp", Host.join(Host.root(), "src")];
		if (recDir != null)
			args = args.concat(["-cp", recDir, "-D", "blocks"]);
		args = args.concat([
			"-main", "swf.Main", "-swf", out, "-swf-version", "11.4", "-D", "swf-header=640:576:60:000000", "-resource",
			Host.join(o.workDir, "rom.bin") + "@rom", "-resource", cfgFile + "@config", "-D", "network-sandbox", "-dce", "full", "-D", "no-traces"
		]);
		Toolchain.haxe(args);
	}
}
