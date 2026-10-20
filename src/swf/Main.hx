// gb2swf - Game Boy ROM to Flash SWF converter
// Copyright (c) 2026 Burg Media. MIT License, see LICENSE.
package swf;

import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.Sprite;
import flash.display.StageQuality;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.SampleDataEvent;
import flash.external.ExternalInterface;
import flash.geom.Rectangle;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.net.SharedObject;
import flash.text.TextField;
import flash.text.TextFormat;
import gb.Apu;
import gb.Gb;
import gb.Mem;

/**
 * Flash frontend. The ROM is embedded as resource "rom", build options as
 * resource "config", recompiled code (if any) through the class Blocks.
 *
 * FlashVars (all optional, they override the build options):
 *   keys  = keyCodes per button, e.g. "up:38,87;down:40,83;left:37,65;right:39,68;a:88,75;b:90,74;start:13;select:16"
 *   pal   = 4 colours light to dark for original Game Boy games, e.g. "e0f8d0,88c070,346856,081820"
 *   sound = "0" to switch sound off
 *   fps   = "1" for an fps / recompiled-share overlay
 *
 * Saves: battery-backed cartridge RAM (and the MBC3 clock) go into a local
 * SharedObject, which works in the Flash Player projector and in Ruffle.
 *
 * Sound: the Flash Player plays the samples itself (SampleDataEvent). Ruffle does
 * not support that, so there the samples go to gb2swf-audio.js on the page through
 * ExternalInterface.
 */
class Main extends Sprite {
	static inline var SCALE = 4;
	static var BUTTONS = ["right", "left", "up", "down", "a", "b", "select", "start"];

	var gb:Gb;
	var rom:haxe.io.Bytes;
	var cfg:Dynamic;
	var bmd:BitmapData;
	var rect = new Rectangle(0, 0, 160, 144);
	var keyMap = new Map<Int, Int>(); // keyCode -> button bit
	var held = new Map<Int, Bool>();
	var padKeys = 0; // buttons from the page (gamepad, touch)
	var palette:String = null;
	var lastTime = 0.0;
	var acc = 0.0;
	var info:TextField;
	var fpsFrames = 0;
	var fpsAt = 0.0;
	var fps = 0;
	var recShare = 0;
	var busyMs = 0.0; // time spent in onFrame during the current second
	var frameMs = 0.0; // average time per Game Boy frame over the last second (16.7 ms is the budget)

	// Saves
	var so:SharedObject;
	var saveDirtyFrames = 0;
	var saveAge = 0;

	// Sound
	var sound:Sound;
	var channel:SoundChannel;
	var soundOn = true;
	var lastL = 0.0;
	var lastR = 0.0;
	var sampleCalls = 0;
	var jsAudio = false;
	var audioCheck = 30;
	var jsBuf:Array<Float> = [];
	var stemAudio = false; // the host takes every channel on its own (gb2swfAudioStems)

	// Input recording (for an extra profiling run, see `gb2swf --record`)
	var recording:Array<Array<Int>> = null;
	var recFrame = 0;
	var recLastKeys = -1;
	var recSave:String = null;

	static function main() {
		flash.Lib.current.addChild(new Main());
	}

	public function new() {
		super();
		var params:Dynamic = flash.Lib.current.loaderInfo.parameters;
		rom = haxe.Resource.getBytes("rom");
		var cfgText = haxe.Resource.getString("config");
		cfg = cfgText != null ? haxe.Json.parse(cfgText) : {};
		palette = params.pal != null ? params.pal : cfg.palette;
		boot();

		parseKeys(params.keys != null ? params.keys : (cfg.keys != null ? cfg.keys : "up:38;down:40;left:37;right:39;a:88;b:90;start:13;select:16"));

		bmd = new BitmapData(160, 144, false, 0);
		var bm = new Bitmap(bmd);
		bm.smoothing = false;
		bm.scaleX = bm.scaleY = SCALE;
		addChild(bm);

		if (params.fps == "1")
			showInfo(true);

		if (params.sound != "0") {
			sound = new Sound();
			sound.addEventListener(SampleDataEvent.SAMPLE_DATA, onSample);
			channel = sound.play();
		} else {
			soundOn = false;
			gb.apu.enabled = false;
		}

		if (ExternalInterface.available) {
			try {
				ExternalInterface.addCallback("gbSetKeys", parseKeys);
				ExternalInterface.addCallback("gbSetPalette", setPalette);
				ExternalInterface.addCallback("gbPad", function(mask:Int) {
					padKeys = mask & 0xFF;
					updateKeys();
				});
				ExternalInterface.addCallback("gbInfo", function() return {
					title: gb.title,
					cgb: gb.cgb,
					hasSave: gb.hasSave(),
					name: cfg.name
				});
				ExternalInterface.addCallback("gbStats", function() return {
					fps: fps,
					msPerFrame: frameMs,
					rec: recShare,
					jsAudio: jsAudio
				});
				ExternalInterface.addCallback("gbShowInfo", showInfo);
				ExternalInterface.addCallback("gbGetSave", function() return gb.hasSave() ? haxe.crypto.Base64.encode(gb.getSave()) : null);
				ExternalInterface.addCallback("gbSetSave", importSave);
				ExternalInterface.addCallback("gbReset", function() boot());
				ExternalInterface.addCallback("gbRecStart", recStart);
				ExternalInterface.addCallback("gbRecStop", recStop);
			} catch (e:Dynamic) {}
		}

		addEventListener(Event.ADDED_TO_STAGE, onStage);
	}

	/** (Re)starts the Game Boy, with the saved game if there is one. */
	function boot() {
		if (gb != null)
			flushSave();
		gb = new Gb(rom, cfg.dmg == true);
		#if blocks
		Blocks.install(gb);
		#end
		if (gb.rtc != null) {
			// The cartridge clock follows emulated time (so games measure it exactly as on
			// hardware) and is pulled forward to the real time whenever it falls more than
			// two seconds behind: time the page was closed or in the background.
			var g = gb;
			var offset = Date.now().getTime() / 1000 - g.emulatedSeconds();
			g.rtc.setClock(function() {
				var e = g.emulatedSeconds();
				var wall = Date.now().getTime() / 1000;
				if (wall - (e + offset) > 2)
					offset = wall - e;
				return e + offset;
			});
		}
		if (palette != null)
			setPalette(palette);
		if (!soundOn)
			gb.apu.enabled = false;
		gb.apu.stems = stemAudio;
		so = null;
		if (gb.hasSave()) {
			try {
				so = SharedObject.getLocal(saveName(), "/");
				if (so.data.ram != null)
					gb.setSave(haxe.crypto.Base64.decode(so.data.ram));
			} catch (e:Dynamic) {}
		}
		updateKeys();
	}

	/** One save slot per game: title plus global checksum, so two games with the same title don't collide. */
	function saveName():String {
		var t = ~/[^A-Za-z0-9_-]/g.replace(gb.title, "_");
		return "gb2swf_" + t + "_" + StringTools.hex(gb.globalChecksum, 4);
	}

	function flushSave() {
		if (so == null || gb == null)
			return;
		saveDirtyFrames = 0;
		saveAge = 0;
		gb.ramDirty = false;
		try {
			so.data.ram = haxe.crypto.Base64.encode(gb.getSave());
			so.flush();
		} catch (e:Dynamic) {}
	}

	function importSave(b64:String):Bool {
		if (!gb.hasSave())
			return false;
		try {
			var data = haxe.crypto.Base64.decode(b64);
			if (so != null) {
				so.data.ram = b64;
				so.flush();
			}
			boot();
			gb.setSave(data);
			flushSave();
			return true;
		} catch (e:Dynamic) {
			return false;
		}
	}

	function onStage(_) {
		stage.quality = StageQuality.LOW;
		// Haxe defaults to top-left / no-scale; we want centred and scaled
		stage.align = cast "";
		stage.scaleMode = flash.display.StageScaleMode.SHOW_ALL;
		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKey);
		stage.addEventListener(KeyboardEvent.KEY_UP, onKey);
		stage.addEventListener(Event.DEACTIVATE, function(_) {
			held = new Map();
			updateKeys();
			flushSave();
		});
		lastTime = flash.Lib.getTimer();
		addEventListener(Event.ENTER_FRAME, onFrame);
	}

	function showInfo(on:Bool) {
		if (on && info == null) {
			info = new TextField();
			info.defaultTextFormat = new TextFormat("_typewriter", 14, 0xFFFFFF);
			info.background = true;
			info.backgroundColor = 0x000000;
			info.autoSize = flash.text.TextFieldAutoSize.LEFT;
			info.selectable = false;
			addChild(info);
		} else if (!on && info != null) {
			removeChild(info);
			info = null;
		}
	}

	function parseKeys(s:String) {
		var m = new Map<Int, Int>();
		for (part in s.split(";")) {
			var kv = part.split(":");
			if (kv.length != 2)
				continue;
			var bit = BUTTONS.indexOf(StringTools.trim(kv[0]).toLowerCase());
			if (bit < 0)
				continue;
			for (code in kv[1].split(",")) {
				var c = Std.parseInt(code);
				if (c != null && c > 0)
					m.set(c, bit);
			}
		}
		keyMap = m;
		held = new Map();
		if (gb != null)
			updateKeys();
	}

	function setPalette(s:String) {
		palette = s;
		var cols = [for (p in s.split(",")) Std.parseInt("0x" + StringTools.trim(p))];
		if (cols.length == 4 && cols.indexOf(null) < 0)
			gb.ppu.setPalette(cols);
	}

	function onKey(e:KeyboardEvent) {
		if (!keyMap.exists(e.keyCode))
			return;
		if (e.type == KeyboardEvent.KEY_DOWN)
			held.set(e.keyCode, true);
		else
			held.remove(e.keyCode);
		updateKeys();
	}

	function updateKeys() {
		var k = padKeys;
		for (code in held.keys())
			k |= 1 << keyMap.get(code);
		gb.setKeys(k);
	}

	function recStart():Bool {
		// A recording starts from power-on, with the current save, and runs on the
		// interpreter (recompiled code takes interrupts only between blocks), so that
		// gb2swf's profiler, which uses the interpreter, can replay it exactly
		flushSave();
		recSave = gb.hasSave() && so != null && so.data.ram != null ? so.data.ram : null;
		boot();
		gb.blockIndex = null;
		recording = [];
		recFrame = 0;
		recLastKeys = -1;
		return true;
	}

	function recStop():String {
		if (recording == null)
			return null;
		// Hash of the last picture, so that a replay can tell whether it ended in the same place
		var hsh = 0;
		var p = Mem.FB;
		for (q in 0...160 * 144) {
			hsh = (hsh * 31 + Mem.get32(p)) | 0;
			p += 4;
		}
		var json = haxe.Json.stringify({
			format: "gb2swf-input",
			version: 1,
			title: gb.title,
			globalChecksum: gb.globalChecksum,
			frames: recFrame,
			save: recSave,
			endHash: hsh,
			events: recording
		});
		recording = null;
		#if blocks
		Blocks.install(gb); // back to the recompiled code
		#end
		return json;
	}

	function onFrame(_) {
		var now = flash.Lib.getTimer();
		var t0 = now;
		var dt = now - lastTime;
		lastTime = now;
		if (dt > 100)
			dt = 100; // after a hiccup, don't try to catch up everything
		acc += dt;
		var period = 1000 * 70224 / 4194304; // 16.74 ms
		var n = 0;
		while (acc >= period && n < 3) {
			if (recording != null) {
				if (gb.keys != recLastKeys) {
					recording.push([recFrame, gb.keys]);
					recLastKeys = gb.keys;
				}
				recFrame++;
			}
			gb.runFrame();
			acc -= period;
			n++;
			fpsFrames++;
		}
		if (n == 3)
			acc = 0;
		if (sound != null && audioCheck > 0 && n > 0 && --audioCheck == 0 && sampleCalls == 0) {
			// Ruffle: no SampleDataEvent, so send the samples to the page (gb2swf-audio.js)
			try {
				if (ExternalInterface.available && ExternalInterface.call("gb2swfAudioReady") == true) {
					jsAudio = true;
					stemAudio = gb.apu.stems = ExternalInterface.call("gb2swfStemsReady") == true;
					channel.stop();
					gb.apu.rpos = gb.apu.wpos;
				}
			} catch (e:Dynamic) {}
			if (!jsAudio)
				gb.apu.enabled = false;
		}
		if (jsAudio)
			pushJsAudio();
		if (n > 0) {
			Mem.bytes.position = Mem.FB;
			bmd.setPixels(rect, Mem.bytes);
		}
		// Everything this frame took (emulation, sound hand-over, picture), for the stats
		busyMs += flash.Lib.getTimer() - t0;
		// Save a moment after the game stops writing, and at least every 10 seconds while it keeps writing
		if (so != null) {
			if (gb.ramDirty) {
				gb.ramDirty = false;
				saveDirtyFrames = 1;
			} else if (saveDirtyFrames > 0)
				saveDirtyFrames++;
			if (saveDirtyFrames > 0)
				saveAge++;
			if (saveDirtyFrames > 60 || saveAge > 600)
				flushSave();
		}
		if (now - fpsAt >= 1000) {
			var tot = gb.instrRec + gb.instrInterp;
			fps = fpsFrames;
			frameMs = fpsFrames > 0 ? Math.round(busyMs / fpsFrames * 10) / 10 : 0;
			busyMs = 0;
			recShare = tot > 0 ? Std.int(gb.instrRec * 100 / tot) : 0;
			if (info != null)
				info.text = fps + " fps  " + frameMs + " ms/frame  rec " + recShare + "%" + (jsAudio ? "  js-audio" : (sampleCalls > 0 ? "  snd" : ""));
			fpsFrames = 0;
			fpsAt = now;
			gb.instrRec = gb.instrInterp = 0;
		}
	}

	function pushJsAudio() {
		var apu = gb.apu;
		var avail = apu.wpos - apu.rpos;
		if (avail <= 0)
			return;
		if (avail > 8192) {
			apu.rpos = apu.wpos - 2048;
			avail = 2048;
		}
		if (stemAudio) {
			pushJsStems(avail);
			return;
		}
		var buf = apu.out;
		var mask = Apu.BUF - 1;
		var len = avail << 1;
		var a = jsBuf;
		if (a.length != len)
			a = jsBuf = [for (i in 0...len) 0.0];
		var r = apu.rpos;
		var k = 0;
		for (i in 0...avail) {
			var j = (r & mask) << 1;
			// Rounding keeps the ExternalInterface message short
			a[k++] = Math.round(buf[j] * 10000) / 10000;
			a[k++] = Math.round(buf[j + 1] * 10000) / 10000;
			r++;
		}
		apu.rpos = r;
		try {
			ExternalInterface.call("gb2swfAudio", a);
		} catch (e:Dynamic) {}
	}

	/** Stems mode: 8 values per sample (Pulse 1, Pulse 2, Wave, Noise; L, R), unrounded. */
	function pushJsStems(avail:Int) {
		var apu = gb.apu;
		var buf = apu.outStems;
		var mask = Apu.BUF - 1;
		var len = avail << 3;
		var a = jsBuf;
		if (a.length != len)
			a = jsBuf = [for (i in 0...len) 0.0];
		var r = apu.rpos;
		var k = 0;
		for (i in 0...avail) {
			var j = (r & mask) << 3;
			for (c in 0...8)
				a[k++] = buf[j + c];
			r++;
		}
		apu.rpos = r;
		try {
			ExternalInterface.call("gb2swfAudioStems", a);
		} catch (e:Dynamic) {}
	}

	function onSample(e:SampleDataEvent) {
		sampleCalls++;
		var apu = gb.apu;
		var avail = apu.wpos - apu.rpos;
		if (avail > 6000) {
			// Too far behind (e.g. after a hiccup): bring the latency back down
			apu.rpos = apu.wpos - 3000;
			avail = 3000;
		}
		var n = avail < 2048 ? 2048 : (avail > 4096 ? 4096 : avail);
		var data = e.data;
		var buf = apu.out;
		var mask = Apu.BUF - 1;
		var r = apu.rpos;
		for (i in 0...n) {
			if (r < apu.wpos) {
				var j = (r & mask) << 1;
				lastL = buf[j];
				lastR = buf[j + 1];
				r++;
			} else {
				lastL *= 0.995;
				lastR *= 0.995;
			}
			data.writeFloat(lastL);
			data.writeFloat(lastR);
		}
		apu.rpos = r;
	}
}
