// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package tool;

/**
 * Button input for headless runs, one value per frame (bit layout as Machine.keys:
 * 0 right, 1 left, 2 up, 3 down, 4 A, 5 B, 6 select, 7 start).
 */
interface Input {
	function keys(frame:Int):Int;
	function describe():String;
}

/** No buttons at all: shows title screens and attract/demo modes. */
class Attract implements Input {
	public function new() {}

	public function keys(frame:Int):Int
		return 0;

	public function describe()
		return "attract (no input)";
}

/**
 * Pseudo-random play, reproducible from its seed. Starts by mashing Start and A
 * to get through title screens and menus, then mostly moves and presses A/B with
 * varying hold times, and every now and then Start again.
 */
class Fuzz implements Input {
	public var seed(default, null):Int;

	var state:Int;
	var nextChange = 0;
	var current = 0;

	static final MOVES = [0, 1, 2, 4, 8, 1, 2, 4, 8, 16, 32, 16, 17, 18, 20, 24, 33, 34, 36, 40, 48, 0];

	public function new(seed:Int) {
		this.seed = seed;
		state = seed * 7919 + 17;
	}

	inline function rnd():Int {
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
		return state >> 8;
	}

	public function keys(frame:Int):Int {
		if (frame < nextChange)
			return current;
		var r = rnd();
		if (current != 0 && r % 3 == 0) {
			// Release for a moment, so that the next press is a new press
			current = 0;
			nextChange = frame + 1 + rnd() % 6;
			return current;
		}
		if (frame < 900) {
			// Menus: Start and A, with pauses in between
			current = switch (r % 6) {
				case 0: 128;
				case 1, 2: 16;
				case 3: 8;
				default: 0;
			}
			nextChange = frame + 4 + rnd() % 30;
		} else {
			var p = r % 1000;
			if (p < 12)
				current = 128; // Start (pause menus, continue screens)
			else if (p < 18)
				current = 64; // Select
			else
				current = MOVES[rnd() % MOVES.length];
			nextChange = frame + 2 + rnd() % 40;
		}
		return current;
	}

	public function describe()
		return 'fuzz seed $seed';
}

/** Replays an input recording made in the HTML player (gb2swf-input JSON). */
class Replay implements Input {
	var events:Array<Array<Int>>;
	var pos = 0;
	var current = 0;
	var name:String;

	public var save:Null<haxe.io.Bytes> = null;
	public var frames = 0;
	/** Hash of the last picture of the recording (null in old recordings). */
	public var endHash:Null<Int> = null;

	public function new(json:String, name:String) {
		this.name = name;
		var d:Dynamic = haxe.Json.parse(json);
		if (d.format != "gb2swf-input")
			throw '$name is not a gb2swf input recording';
		events = d.events;
		frames = d.frames;
		endHash = d.endHash;
		if (d.save != null && d.save != "")
			save = haxe.crypto.Base64.decode(d.save);
	}

	public function keys(frame:Int):Int {
		while (pos < events.length && events[pos][0] <= frame)
			current = events[pos++][1];
		return current;
	}

	public function describe()
		return 'recording $name';
}
