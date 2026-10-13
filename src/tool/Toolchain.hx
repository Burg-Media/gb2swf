// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

/**
 * Finds the Haxe compiler, which the user installs separately (https://haxe.org):
 * $GB2SWF_HAXE, `haxe` on the PATH, or the usual install locations.
 */
class Toolchain {
	public static inline var INSTALL_HINT = "Install Haxe 4.3 from https://haxe.org/download/ (free), then run gb2swf again.\n"
		+ "If it is installed somewhere unusual, set GB2SWF_HAXE to the full path of the haxe program.";

	static var haxeCmd:String = null;

	static function find():String {
		if (haxeCmd != null)
			return haxeCmd;
		var custom = Host.env("GB2SWF_HAXE");
		if (custom != null && custom != "")
			return haxeCmd = custom;
		var win = Host.platform() == "win32";
		var candidates = ["haxe"];
		if (win)
			candidates = candidates.concat(["C:\\HaxeToolkit\\haxe\\haxe.exe"]);
		else
			candidates = candidates.concat(["/opt/homebrew/bin/haxe", "/usr/local/bin/haxe", "/usr/bin/haxe"]);
		for (c in candidates)
			if (Host.run(c, ["--version"]).code == 0)
				return haxeCmd = c;
		return haxeCmd = "haxe";
	}

	/** Version string, or null when no Haxe compiler can be started. */
	public static function haxeVersion():String {
		var r = Host.run(find(), ["--version"]);
		return r.code == 0 ? StringTools.trim(r.out + r.err) : null;
	}

	/** Throws a helpful error when Haxe is missing or too old. */
	public static function check():Void {
		var v = haxeVersion();
		if (v == null)
			throw "the Haxe compiler was not found.\n" + INSTALL_HINT;
		var parts = v.split(".");
		var major = Std.parseInt(parts[0]), minor = parts.length > 1 ? Std.parseInt(parts[1]) : 0;
		if (major == null || major < 4 || (major == 4 && minor < 3))
			throw 'Haxe $v is too old: gb2swf needs Haxe 4.3 or later.\n' + INSTALL_HINT;
	}

	/** Runs the Haxe compiler; throws with its output on failure. */
	public static function haxe(args:Array<String>):Void {
		var r = Host.run(find(), args);
		if (r.code != 0) {
			var msg = StringTools.trim(r.err + "\n" + r.out);
			if (r.code == -1)
				msg = 'could not start the Haxe compiler: $msg\n' + INSTALL_HINT;
			throw "Haxe compiler failed:\n" + msg;
		}
	}

	/** Runs a JavaScript file with the same Node.js that runs gb2swf. */
	public static function node(script:String, args:Array<String>):{code:Int, out:String, err:String}
		return Host.run(Host.nodePath(), [script].concat(args));
}
