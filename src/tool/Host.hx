// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

import haxe.io.Bytes;
import js.Syntax;

/** The few Node.js facilities the tools need (files, processes, paths). No network. */
class Host {
	static var fs:Dynamic = Syntax.code("require('fs')");
	static var path:Dynamic = Syntax.code("require('path')");
	static var cp:Dynamic = Syntax.code("require('child_process')");
	static var crypto:Dynamic = Syntax.code("require('crypto')");
	static var zlib:Dynamic = Syntax.code("require('zlib')");

	public static function args():Array<String>
		return Syntax.code("process.argv.slice(2)");

	public static function print(s:String)
		Syntax.code("process.stdout.write({0} + '\\n')", s);

	public static function err(s:String)
		Syntax.code("process.stderr.write({0} + '\\n')", s);

	public static function exit(code:Int):Dynamic
		return Syntax.code("process.exit({0})", code);

	public static function now():Float
		return Syntax.code("Date.now()");

	public static function env(name:String):Null<String>
		return Syntax.code("process.env[{0}]", name);

	public static function platform():String
		return Syntax.code("process.platform");

	public static function exists(p:String):Bool
		return fs.existsSync(p);

	public static function isDir(p:String):Bool
		return fs.existsSync(p) && fs.statSync(p).isDirectory();

	public static function readBytes(p:String):Bytes {
		var buf:Dynamic = fs.readFileSync(p);
		return Bytes.ofData(Syntax.code("{0}.buffer.slice({0}.byteOffset, {0}.byteOffset + {0}.length)", buf));
	}

	public static function writeBytes(p:String, b:Bytes)
		fs.writeFileSync(p, Syntax.code("Buffer.from({0}, 0, {1})", b.getData(), b.length));

	public static function readText(p:String):String
		return fs.readFileSync(p, "utf8");

	public static function writeText(p:String, s:String)
		fs.writeFileSync(p, s, "utf8");

	public static function mkdir(p:String)
		fs.mkdirSync(p, {recursive: true});

	public static function remove(p:String)
		if (fs.existsSync(p))
			fs.rmSync(p, {recursive: true, force: true});

	public static function list(p:String):Array<String>
		return fs.existsSync(p) ? fs.readdirSync(p) : [];

	public static function copy(src:String, dst:String)
		fs.copyFileSync(src, dst);

	public static function copyDir(src:String, dst:String)
		fs.cpSync(src, dst, {recursive: true});

	public static function size(p:String):Int
		return fs.statSync(p).size;

	public static function join(a:String, b:String):String
		return path.join(a, b);

	public static function resolve(p:String):String
		return path.resolve(p);

	public static function dirname(p:String):String
		return path.dirname(p);

	public static function basename(p:String):String
		return path.basename(p);

	public static function extname(p:String):String
		return path.extname(p);

	/** Directory of the gb2swf installation (the folder that holds lib/ and src/). */
	public static function root():String
		return path.resolve(Syntax.code("__dirname"), "..");

	public static function sha256(b:Bytes):String
		return crypto.createHash("sha256").update(Syntax.code("Buffer.from({0}, 0, {1})", b.getData(), b.length)).digest("hex");

	public static function sha1(b:Bytes):String
		return crypto.createHash("sha1").update(Syntax.code("Buffer.from({0}, 0, {1})", b.getData(), b.length)).digest("hex");

	public static function deflate(b:Bytes):Bytes {
		var out:Dynamic = zlib.deflateSync(Syntax.code("Buffer.from({0}, 0, {1})", b.getData(), b.length));
		return Bytes.ofData(Syntax.code("{0}.buffer.slice({0}.byteOffset, {0}.byteOffset + {0}.length)", out));
	}

	public static function gzip(b:Bytes):Bytes {
		var out:Dynamic = zlib.gzipSync(Syntax.code("Buffer.from({0}, 0, {1})", b.getData(), b.length), {level: 9});
		return Bytes.ofData(Syntax.code("{0}.buffer.slice({0}.byteOffset, {0}.byteOffset + {0}.length)", out));
	}

	public static function inflate(b:Bytes):Bytes {
		var out:Dynamic = zlib.inflateSync(Syntax.code("Buffer.from({0}, 0, {1})", b.getData(), b.length));
		return Bytes.ofData(Syntax.code("{0}.buffer.slice({0}.byteOffset, {0}.byteOffset + {0}.length)", out));
	}

	/**
	 * Runs a program and waits for it. Output is captured; returns exit code,
	 * stdout and stderr. No shell is involved, so paths with spaces are safe.
	 */
	public static function run(cmd:String, argv:Array<String>, ?envExtra:Dynamic, ?cwd:String):{code:Int, out:String, err:String} {
		var env:Dynamic = Syntax.code("Object.assign({}, process.env, {0} || {})", envExtra);
		var r:Dynamic = cp.spawnSync(cmd, argv, {
			encoding: "utf8",
			env: env,
			cwd: cwd,
			maxBuffer: 256 * 1024 * 1024,
			windowsHide: true
		});
		if (r.error != null)
			return {code: -1, out: "", err: Std.string(r.error.message)};
		return {code: r.status == null ? -1 : r.status, out: r.stdout, err: r.stderr};
	}

	/** Path of the running Node.js binary. */
	public static function nodePath():String
		return Syntax.code("process.execPath");
}
