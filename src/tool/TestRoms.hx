// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import haxe.io.Bytes;
import tool.Input;

/**
 * `gb2swf dev testroms [--rec] [--only <text>] [--md <file>] [--json <file>]`
 *
 * Runs the test ROMs listed in tests/testroms.json (fetch them first with
 * `node scripts/fetch-testroms.mjs`) and decides pass/fail automatically:
 *   serial   Blargg: "Passed" / "Failed" on the serial port
 *   memory   Blargg: result code in cartridge RAM (signature DE B0 61 at A001)
 *   acid     dmg-acid2 / cgb-acid2: screen compared pixel by pixel with the reference image
 *   mooneye  Mooneye: Fibonacci registers after `ld b, b`
 *   rtc      rtc3test: screenshot only, judged by eye (it needs real seconds to pass)
 *
 * With --rec every ROM is also profiled, recompiled, lockstep-checked and run
 * from its recompiled code, which tests the recompiler with the same ROMs.
 */
class TestRoms {
	static var root:String;

	public static function run(args:Array<String>):Int {
		root = Host.root();
		var withRec = args.indexOf("--rec") >= 0;
		var only = optional(args, "--only");
		var md = optional(args, "--md");
		var jsonOut = optional(args, "--json");
		var shots = optional(args, "--shots");
		var manifest:Dynamic = haxe.Json.parse(Host.readText(Host.join(root, "tests/testroms.json")));
		var romDir = Host.join(root, "testroms");
		var rows:Array<Dynamic> = [];
		var failures = 0;
		for (suite in (manifest.suites : Array<Dynamic>)) {
			for (t in (suite.tests : Array<Dynamic>)) {
				var path = Host.join(romDir, Host.join(suite.dir, t.rom));
				var name:String = suite.name + ": " + t.rom;
				if (only != null && name.indexOf(only) < 0)
					continue;
				if (!Host.exists(path)) {
					rows.push({suite: suite.name, rom: t.rom, interp: "missing", rec: "", note: "run scripts/fetch-testroms.mjs"});
					continue;
				}
				var rom = Host.readBytes(path);
				var r = interp(rom, t, suite, shots);
				var row:Dynamic = {
					suite: suite.name,
					rom: t.rom,
					model: t.model != null ? t.model : (rom.get(0x143) & 0x80 != 0 ? "CGB" : "DMG"),
					interp: r.verdict,
					note: r.note,
					expected: t.expect != null ? t.expect : "pass"
				};
				if (withRec && t.kind != "mooneye" && t.kind != "rtc" || withRec && args.indexOf("--rec-all") >= 0) {
					var rr = recompiled(rom, t, suite);
					row.rec = rr.verdict;
					if (rr.note != "")
						row.note = (row.note != "" ? row.note + "; " : "") + rr.note;
				} else
					row.rec = "";
				rows.push(row);
				var bad = row.interp != "pass" || (row.rec != "" && row.rec != "pass");
				if (bad && row.expected == "pass")
					failures++;
				if (row.expected == "fail") {
					row.reason = t.reason;
					if (!bad)
						Host.print("  (expected to fail but passes now: update tests/testroms.json)");
				}
				Host.print('${pad(row.interp, 8)} ${pad(row.rec, 8)} $name${row.note != "" ? "  (" + row.note + ")" : ""}');
			}
		}
		var total = rows.length;
		var passed = [for (r in rows) if (r.interp == "pass") r].length;
		Host.print('\n$passed of $total pass on the interpreter' + (failures > 0 ? '; $failures UNEXPECTED failure(s)' : "; all other results are known limitations (see tests/testroms.json)"));
		if (md != null)
			Host.writeText(md, markdown(rows, withRec));
		if (jsonOut != null)
			Host.writeText(jsonOut, haxe.Json.stringify(rows, null, "  "));
		return failures > 0 ? 1 : 0;
	}

	static function optional(args:Array<String>, name:String):Null<String> {
		var i = args.indexOf(name);
		return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
	}

	static function pad(s:String, n:Int):String
		return StringTools.rpad(s, " ", n);

	static function judge(g:gb.Gb, t:Dynamic, suite:Dynamic):{verdict:String, note:String} {
		switch (t.kind) {
			case "serial":
				var s = g.serial.toString();
				if (s.indexOf("Passed") >= 0)
					return {verdict: "pass", note: ""};
				if (s.indexOf("Failed") >= 0)
					return {verdict: "fail", note: firstLines(s)};
				return {verdict: "timeout", note: firstLines(s)};
			case "memory":
				var m = Headless.blarggMemory(g);
				if (!m.done) {
					if (Headless.screenHas("Passed"))
						return {verdict: "pass", note: "result read from screen"};
					if (Headless.screenHas("Failed"))
						return {verdict: "fail", note: "result read from screen"};
					return {verdict: "timeout", note: firstLines(m.text)};
				}
				return {verdict: m.pass ? "pass" : "fail", note: m.pass ? "" : firstLines(m.text)};
			case "acid":
				var refPath = Host.join(Host.join(root, "testroms"), Host.join(suite.dir, t.reference));
				var diff = Headless.compareImage(Png.decode(Host.readBytes(refPath)));
				return {verdict: diff == 0 ? "pass" : "fail", note: diff == 0 ? "" : '$diff pixels differ'};
			case "mooneye":
				if (!g.hitLdBB)
					return {verdict: "timeout", note: ""};
				return {verdict: Headless.mooneyePass(g) ? "pass" : "fail", note: ""};
			default:
				return {verdict: "manual", note: "screenshot only"};
		}
	}

	static function firstLines(s:String):String {
		var lines = [for (l in s.split("\n")) if (StringTools.trim(l) != "") StringTools.trim(l)];
		var bad = [for (l in lines) if (l.indexOf("Failed") >= 0 || l.indexOf(":") >= 0 && l.indexOf("ok") < 0) l];
		var out = (bad.length > 0 ? bad : lines).slice(0, 3).join(" | ");
		return out.length > 120 ? out.substr(0, 117) + "..." : out;
	}

	static function setup(g:gb.Gb, t:Dynamic) {
		if (t.kind == "acid" && !g.cgb)
			g.ppu.setPalette([0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000]);
		g.stopOnLdBB = t.kind == "mooneye";
	}

	/** rtc3test: runs its three test pages; results are coloured green (pass) or red (fail). */
	static function rtc(rom:Bytes, shots:Null<String>):{verdict:String, note:String} {
		var scripts = [[60 => 16, 66 => 0], [50 => 8, 56 => 0, 60 => 16, 66 => 0], [50 => 8, 56 => 0, 58 => 8, 64 => 0, 70 => 16, 76 => 0]];
		var names = ["basic", "range", "sub-second"];
		var failed = [];
		for (i in 0...3) {
			var g = Headless.machine(rom);
			for (f in 0...2400) {
				if (scripts[i].exists(f))
					g.setKeys(scripts[i].get(f));
				g.runFrame();
			}
			var px = Headless.rgba();
			var red = 0, green = 0;
			for (j in 0...160 * 144) {
				var r = px.get(j * 4), gr = px.get(j * 4 + 1), b = px.get(j * 4 + 2);
				if (r > 180 && gr < 100 && b < 100)
					red++;
				if (gr > 150 && r < 100 && b < 100)
					green++;
			}
			if (red > 0 || green == 0)
				failed.push(names[i]);
			if (shots != null) {
				Host.mkdir(shots);
				Host.writeBytes(Host.join(shots, "rtc3test_" + names[i] + ".png"), Headless.png(2));
			}
		}
		return failed.length == 0 ? {verdict: "pass", note: "basic, range and sub-second pages all green"} : {verdict: "fail", note: "red results on: " + failed.join(", ")};
	}

	static function interp(rom:Bytes, t:Dynamic, suite:Dynamic, shots:Null<String>):{verdict:String, note:String} {
		if (t.kind == "rtc")
			return rtc(rom, shots);
		var g = Headless.machine(rom);
		setup(g, t);
		var frames:Int = t.frames != null ? t.frames : 3000;
		var f = 0;
		while (f < frames) {
			g.runFrame();
			f++;
			if (g.locked || g.hitLdBB)
				break;
			if (f % 30 == 0) {
				if (t.kind == "serial") {
					var s = g.serial.toString();
					if (s.indexOf("Passed") >= 0 || s.indexOf("Failed") >= 0)
						break;
				} else if (t.kind == "memory" && Headless.blarggMemory(g).done)
					break;
			}
		}
		if (shots != null) {
			Host.mkdir(shots);
			Host.writeBytes(Host.join(shots, ~/[^A-Za-z0-9]+/g.replace(suite.dir + "_" + t.rom, "_") + ".png"), Headless.png(2));
		}
		var j = judge(g, t, suite);
		if (g.locked && j.verdict != "pass")
			j.note = (j.note != "" ? j.note + "; " : "") + "hung on an illegal opcode";
		return j;
	}

	/** Full pipeline: profile, recompile, lockstep check, run the recompiled code. */
	static function recompiled(rom:Bytes, t:Dynamic, suite:Dynamic):{verdict:String, note:String} {
		var work = Host.join(root, "build/testroms-rec");
		Host.remove(work);
		Host.mkdir(work);
		var frames:Int = t.frames != null ? t.frames : 3000;
		var g = Headless.machine(rom);
		setup(g, t);
		g.startProfile();
		Headless.run(g, frames, new Attract());
		var rec = new Recompiler(rom);
		rec.addProfile(Headless.profileRows(g));
		var files = rec.run();
		var recDir = Host.join(work, "rec");
		Host.mkdir(recDir);
		for (k in files.keys())
			Host.writeText(Host.join(recDir, k), files.get(k));
		var js = Host.join(work, "harness.js");
		Toolchain.haxe([
			"-cp", Host.join(root, "src"), "-cp", recDir, "-D", "blocks", "-main", "tool.Harness", "-js", js, "-D", "js-es=6", "-dce", "full"
		]);
		var romFile = Host.join(work, "rom.bin");
		Host.writeBytes(romFile, rom);
		var spec = Host.join(work, "spec.json");
		var lockFrames = Std.int(Math.min(frames, 1500));
		Host.writeText(spec, haxe.Json.stringify({runs: [{type: "attract", frames: lockFrames}]}));
		var r = Toolchain.node(js, ["lockstep", romFile, spec]);
		if (r.code != 0)
			return {verdict: "error", note: "lockstep crashed"};
		var lock:Dynamic = haxe.Json.parse(StringTools.trim(r.out));
		if (lock.ok != true)
			return {verdict: "mismatch", note: "lockstep: " + haxe.Json.stringify(lock.runs[0].mismatch)};
		var runSpec:Dynamic = {
			type: "attract",
			frames: frames,
			mooneye: t.kind == "mooneye",
			blarggMemory: t.kind == "memory",
			until: t.kind == "serial" ? "assed" : null
		};
		if (t.kind == "acid" && rom.get(0x143) & 0x80 == 0)
			runSpec.palette = [0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000];
		var png = Host.join(work, "screen.png");
		runSpec.png = png;
		Host.writeText(spec, haxe.Json.stringify(runSpec));
		r = Toolchain.node(js, ["run", romFile, spec]);
		if (r.code != 0)
			return {verdict: "error", note: "run crashed"};
		var res:Dynamic = haxe.Json.parse(StringTools.trim(r.out));
		var share = res.instrRec + res.instrInterp > 0 ? Math.round(res.instrRec * 100 / (res.instrRec + res.instrInterp)) : 0;
		var v = switch (t.kind) {
			case "serial":
				var s:String = res.serial;
				s.indexOf("Passed") >= 0 ? "pass" : (s.indexOf("Failed") >= 0 ? "fail" : "timeout");
			case "memory":
				res.memory.done ? (res.memory.pass ? "pass" : "fail") : (res.screenPassed ? "pass" : (res.screenFailed ? "fail" : "timeout"));
			case "mooneye":
				res.mooneye;
			case "acid":
				var refPath = Host.join(Host.join(root, "testroms"), Host.join(suite.dir, t.reference));
				var ref = Png.decode(Host.readBytes(refPath));
				var mine = Png.decode(Host.readBytes(png));
				var diff = 0;
				for (i in 0...160 * 144)
					if (mine.rgba.getInt32(i * 4) & 0xFFFFFF != ref.rgba.getInt32(i * 4) & 0xFFFFFF)
						diff++;
				diff == 0 ? "pass" : "fail";
			default: "manual";
		}
		return {verdict: v, note: 'rec share ~$share%'};
	}

	static function markdown(rows:Array<Dynamic>, withRec:Bool):String {
		var b = new StringBuf();
		b.add("| Suite | Test ROM | Model | Interpreter | " + (withRec ? "Recompiled | " : "") + "Notes |\n");
		b.add("|---|---|---|---|" + (withRec ? "---|" : "") + "---|\n");
		for (r in rows)
			b.add('| ${r.suite} | ${r.rom} | ${r.model} | ${r.interp} | ' + (withRec ? '${r.rec == "" ? "not run" : r.rec} | ' : "")
				+ '${[for (x in [r.reason, r.note]) if (x != null && x != "") x].join("; ")} |\n');
		return b.toString();
	}
}
