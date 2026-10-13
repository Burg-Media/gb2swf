// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

/** Command line entry point (lib/gb2swf.js). */
class Cli {
	static final PALETTES:Map<String, Array<Int>> = [
		"green" => [0xE0F8D0, 0x88C070, 0x346856, 0x081820],
		"grey" => [0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000],
		"pocket" => [0xC4CFA1, 0x8B956D, 0x4D533C, 0x1F1F1F],
		"amber" => [0xFFE4A0, 0xD89A3C, 0x8A4A12, 0x2A1004]
	];

	static final USAGE = "gb2swf " + Version.VERSION + " - turns a Game Boy / Game Boy Color ROM into a Flash .swf

Usage:
  gb2swf <game.gb|game.gbc> [options]

Writes <name>.swf and the folder <name>_html/ (open index.html in a browser)
next to the ROM, plus a work folder <name>_work/ that can be deleted.

Options:
  -o, --out <dir>       write the results to <dir>
  --name <name>         base name of the output files (default: from the ROM file name)
  --title <text>        page title of the HTML player
  --palette <p>         colours for original Game Boy games: green (default), grey,
                        pocket, amber, or four hex colours light to dark: e0f8d0,88c070,346856,081820
  --keys <map>          default keys as JavaScript keyCodes, e.g.
                        \"up:38;down:40;left:37;right:39;a:88;b:90;start:13;select:16\"
  --record <file>       extra profiling run from an input recording made in the HTML player
                        (repeatable; improves the recompiled share for parts the automatic runs miss)
  --seeds <n>           number of automatic random-input runs (default 4)
  --frames <n>          frames per automatic run (default 6000, about 100 seconds of play)
  --interp-only         no profiling or recompilation: interpreter only (always works, slower)
  --dmg                 run a Game Boy Color game that also supports the original Game Boy in DMG mode
  --names <file>        names for code addresses (comments in the generated code)
  --no-check            skip the interpreter-vs-recompiled check (not recommended)
  --no-player           only write the .swf
  --force               build even if the cartridge type is not supported
  --strict              exit with an error if the check finds any difference (for tests)
  -v, --verbose         more details
  -h, --help            this text
  --version             print the version

Other commands:
  gb2swf info <rom>     show what is in the ROM header
  gb2swf doctor         check that Node.js, Haxe and Ruffle are found

gb2swf works offline and never connects to the internet.";

	static function main() {
		var args = Host.args();
		try {
			Host.exit(run(args));
		} catch (e:Dynamic) {
			Host.err("error: " + Std.string(e));
			Host.exit(1);
		}
	}

	static function run(args:Array<String>):Int {
		if (args.length == 0 || args[0] == "-h" || args[0] == "--help") {
			Host.print(USAGE);
			return args.length == 0 ? 1 : 0;
		}
		if (args[0] == "--version") {
			Host.print(Version.VERSION);
			return 0;
		}
		if (args[0] == "info") {
			if (args.length < 2)
				throw "usage: gb2swf info <rom>";
			Host.print(new Cart(Host.readBytes(args[1])).describe());
			return 0;
		}
		if (args[0] == "doctor")
			return doctor();
		if (args[0] == "dev")
			return DevTools.run(args.slice(1));
		return build(args);
	}

	static function doctor():Int {
		Host.print("gb2swf " + Version.VERSION);
		Host.print("installed in: " + Host.root());
		Host.print("Node.js:      " + js.Syntax.code("process.version") + " (" + Host.nodePath() + ")");
		var hv = Toolchain.haxeVersion();
		Host.print("Haxe:         " + (hv != null ? hv : "NOT FOUND"));
		if (hv == null)
			Host.print("\n" + Toolchain.INSTALL_HINT);
		var ruffle = Host.exists(Host.join(Host.root(), "player/ruffle/ruffle.js"));
		Host.print("Ruffle:       " + (ruffle ? "present" : "MISSING"));
		return hv != null && ruffle ? 0 : 1;
	}

	static function slug(s:String):String {
		var r = ~/[^A-Za-z0-9._-]+/g.replace(s, "-");
		r = ~/-+/g.replace(r, "-");
		r = ~/^-|-$/g.replace(r, "");
		return r == "" ? "game" : r;
	}

	static function build(args:Array<String>):Int {
		var rom:String = null;
		var o:Build.BuildOptions = {
			rom: null,
			outDir: null,
			workDir: null,
			name: null,
			interpOnly: false,
			recordings: [],
			seeds: 4,
			frames: 6000,
			palette: PALETTES.get("green"),
			keys: null,
			forceDmg: false,
			names: null,
			check: true,
			force: false,
			title: null,
			player: true,
			verbose: false,
			strict: false
		};
		var i = 0;
		function value():String {
			if (i + 1 >= args.length)
				throw 'option ${args[i]} needs a value';
			return args[++i];
		}
		function int(s:String):Int {
			var v = Std.parseInt(s);
			if (v == null || v < 0)
				throw 'not a number: $s';
			return v;
		}
		while (i < args.length) {
			var a = args[i];
			switch (a) {
				case "-o", "--out":
					o.outDir = value();
				case "--work":
					o.workDir = value();
				case "--name":
					o.name = slug(value());
				case "--title":
					o.title = value();
				case "--palette":
					var p = value();
					if (PALETTES.exists(p))
						o.palette = PALETTES.get(p);
					else {
						var cols = [for (c in p.split(",")) Std.parseInt("0x" + StringTools.trim(c).toLowerCase())];
						if (cols.length != 4 || cols.indexOf(null) >= 0)
							throw "--palette needs a name (" + [for (k in PALETTES.keys()) k].join(", ") + ") or four hex colours";
						o.palette = cols;
					}
				case "--keys":
					o.keys = value();
				case "--record":
					var f = value();
					if (!Host.exists(f))
						throw 'recording not found: $f';
					o.recordings.push(f);
				case "--seeds":
					o.seeds = int(value());
				case "--frames":
					o.frames = int(value());
				case "--interp-only":
					o.interpOnly = true;
				case "--dmg":
					o.forceDmg = true;
				case "--names":
					o.names = value();
				case "--no-check":
					o.check = false;
				case "--no-player":
					o.player = false;
				case "--force":
					o.force = true;
				case "-v", "--verbose":
					o.verbose = true;
				case "--strict":
					o.strict = true;
				default:
					if (StringTools.startsWith(a, "-"))
						throw 'unknown option $a (see gb2swf --help)';
					if (rom != null)
						throw "only one ROM per run";
					rom = a;
			}
			i++;
		}
		if (rom == null)
			throw "no ROM given (see gb2swf --help)";
		if (!Host.exists(rom))
			throw 'ROM not found: $rom';
		o.rom = rom;
		var base = Host.basename(rom);
		var ext = Host.extname(base);
		if (o.name == null)
			o.name = slug(base.substr(0, base.length - ext.length));
		if (o.outDir == null)
			o.outDir = Host.dirname(Host.resolve(rom));
		if (o.workDir == null)
			o.workDir = Host.join(o.outDir, o.name + "_work");
		if (o.names == null) {
			var n = Host.join(o.workDir, "names.txt");
			if (Host.exists(n))
				o.names = n;
		}
		return new Build(o).run();
	}
}
