package manager;

import manager.BgmLibrary.BgmTrackData;
import openfl.events.Event;
import openfl.media.Sound;
import openfl.media.SoundChannel;
import openfl.media.SoundTransform;
import openfl.utils.ByteArray;
import openfl.utils.Endian;
import openfl.Assets;

/**
 * Game audio: file-based BGM/SFX when assets exist, synthesized fallbacks
 * otherwise. Public API shape is unchanged for Main and gameplay callers.
 *
 * BGM: consults Assets/bgm/bgm.json. Missing .ogg → stage synth riff.
 * Supports loopStart/loopEnd (seconds) and intro + loop file pairs.
 *
 * SFX: Assets/sfx/sfx.json via sfx(name); missing .wav → synth blip.
 *
 * In-memory synth still uses 16-bit WAV via loadCompressedDataFromByteArray
 * (never loadPCMFromByteArray — see plan invariants).
 */
class AudioManager {
	private static inline final SAMPLE_RATE:Int = 44100;
	private static inline final SFX_VOLUME:Float = 0.35;
	private static inline final MANIFEST_SFX:String = "assets/sfx/sfx.json";

	private static inline final FIRE_THROTTLE_FRAMES:Int = 8;
	private static inline final GRAZE_THROTTLE_FRAMES:Int = 6;
	private static inline final HIT_THROTTLE_FRAMES:Int = 4;

	public static var musicVolume(default, null):Float = 0.5;
	public static var musicMuted(default, null):Bool = false;

	private static var initialized:Bool = false;
	private static var musicDucked:Bool = false;

	private static var musicChannel:SoundChannel = null;
	private static var musicTrackId:String = "";
	/** Synth fallback riff index (0..3); -1 when file BGM is playing. */
	private static var musicSynthIndex:Int = -1;

	private static var musicSounds:Array<Sound> = [];
	private static var loadedFileMusic:Map<String, Sound> = new Map();
	private static var loadedFileSfx:Map<String, Sound> = new Map();
	private static var sfxPaths:Map<String, String> = new Map();

	private static var synthFire:Sound;
	private static var synthDeath:Sound;
	private static var synthBomb:Sound;
	private static var synthPickup:Sound;
	private static var synthSpellDeclare:Sound;
	private static var synthSpellCapture:Sound;
	private static var synthSpellFail:Sound;
	private static var synthGraze:Sound;
	private static var synthHit:Sound;

	private static var fireCooldown:Int = 0;
	private static var grazeCooldown:Int = 0;
	private static var hitCooldown:Int = 0;

	// Active BGM loop policy (file playback)
	private static var loopStartMs:Float = 0;
	private static var loopEndMs:Float = 0;
	private static var pendingLoopPath:String = null;
	private static var awaitingIntro:Bool = false;

	public static function init():Void {
		if (initialized) return;
		initialized = true;

		BgmLibrary.ensureLoaded();
		loadSfxManifest();
		buildSynthMusic();
		buildSynthSfx();
	}

	private static function loadSfxManifest():Void {
		sfxPaths = new Map();
		if (!Assets.exists(MANIFEST_SFX)) return;
		try {
			var doc:Dynamic = haxe.Json.parse(Assets.getText(MANIFEST_SFX));
			var sounds:Dynamic = doc.sounds;
			if (sounds == null) return;
			for (key in Reflect.fields(sounds)) {
				var path:Dynamic = Reflect.field(sounds, key);
				if (path is String) sfxPaths.set(key, path);
			}
		} catch (e:Dynamic) {
			trace("AudioManager: failed to parse " + MANIFEST_SFX + ": " + e);
		}
	}

	private static function buildSynthMusic():Void {
		var riff = [0, 3, 5, 3, 7, 5, 3, 0];
		for (base in [220.0, 277.0, 196.0, 247.0]) {
			var notes:Array<{freq:Float, seconds:Float}> = [];
			for (step in riff) {
				notes.push({freq: base * Math.pow(2, step / 12), seconds: 0.28});
			}
			musicSounds.push(makeSequence(notes, 0.5));
		}
	}

	private static function buildSynthSfx():Void {
		synthFire = makeSequence([{freq: 880, seconds: 0.05}], 0.4);
		synthDeath = makeSequence([
			{freq: 440, seconds: 0.12},
			{freq: 330, seconds: 0.12},
			{freq: 220, seconds: 0.20}
		], 0.8);
		synthBomb = makeSequence([
			{freq: 110, seconds: 0.25},
			{freq: 82, seconds: 0.35}
		], 0.9);
		synthPickup = makeSequence([{freq: 1320, seconds: 0.06}], 0.5);
		synthSpellDeclare = makeSequence([
			{freq: 523, seconds: 0.08},
			{freq: 659, seconds: 0.12},
			{freq: 784, seconds: 0.18}
		], 0.55);
		synthSpellCapture = makeSequence([
			{freq: 880, seconds: 0.1},
			{freq: 1175, seconds: 0.14},
			{freq: 1568, seconds: 0.22}
		], 0.6);
		synthSpellFail = makeSequence([
			{freq: 330, seconds: 0.14},
			{freq: 262, seconds: 0.22}
		], 0.5);
		synthGraze = makeSequence([{freq: 1200, seconds: 0.03}], 0.25);
		synthHit = makeSequence([{freq: 520, seconds: 0.04}], 0.35);
	}

	private static function makeSequence(notes:Array<{freq:Float, seconds:Float}>, gain:Float):Sound {
		var totalSamples = 0;
		for (note in notes) {
			totalSamples += Std.int(note.seconds * SAMPLE_RATE);
		}

		var dataBytes = totalSamples * 4;
		var bytes = new ByteArray();
		bytes.endian = Endian.LITTLE_ENDIAN;
		bytes.writeUTFBytes("RIFF");
		bytes.writeInt(36 + dataBytes);
		bytes.writeUTFBytes("WAVE");
		bytes.writeUTFBytes("fmt ");
		bytes.writeInt(16);
		bytes.writeShort(1);
		bytes.writeShort(2);
		bytes.writeInt(SAMPLE_RATE);
		bytes.writeInt(SAMPLE_RATE * 4);
		bytes.writeShort(4);
		bytes.writeShort(16);
		bytes.writeUTFBytes("data");
		bytes.writeInt(dataBytes);

		for (note in notes) {
			var samples = Std.int(note.seconds * SAMPLE_RATE);
			var attack = Std.int(samples * 0.08);
			var release = Std.int(samples * 0.25);
			for (i in 0...samples) {
				var envelope = 1.0;
				if (i < attack) envelope = i / attack;
				else if (i > samples - release) envelope = (samples - i) / release;
				var phase = 2 * Math.PI * note.freq * i / SAMPLE_RATE;
				var wave = Math.sin(phase) + 0.28 * Math.sin(phase * 2);
				var sample = wave * gain * envelope * 0.75;
				if (sample > 1) sample = 1;
				if (sample < -1) sample = -1;
				var pcm = Std.int(sample * 32767);
				bytes.writeShort(pcm);
				bytes.writeShort(pcm);
			}
		}
		bytes.position = 0;

		var sound = new Sound();
		sound.loadCompressedDataFromByteArray(bytes, bytes.length);
		return sound;
	}

	// --- Music ---------------------------------------------------------------

	public static function playMusic(stageNumber:Int):Void {
		playStageTrack(stageNumber, false);
	}

	public static function playBossTrack(stageNumber:Int):Void {
		playStageTrack(stageNumber, true);
	}

	private static function playStageTrack(stageNumber:Int, boss:Bool):Void {
		init();
		var track = boss ? BgmLibrary.trackForBoss(stageNumber) : BgmLibrary.trackForStage(stageNumber);
		if (track == null) {
			playSynthStage(stageNumber);
			return;
		}

		var intro = BgmLibrary.introPath(track);
		var loopPath = BgmLibrary.mainLoopPath(track);
		var canIntro = intro != null && BgmLibrary.assetReady(intro);
		var canLoop = loopPath != null && BgmLibrary.assetReady(loopPath);

		if (canIntro && canLoop) {
			if (musicTrackId == track.id && musicChannel != null) return;
			stopMusicChannelOnly();
			musicTrackId = track.id;
			musicSynthIndex = -1;
			configureLoopPoints(track);
			pendingLoopPath = loopPath;
			awaitingIntro = true;
			startFileMusic(intro, false);
			return;
		}

		if (canLoop) {
			if (musicTrackId == track.id && musicChannel != null) return;
			stopMusicChannelOnly();
			musicTrackId = track.id;
			musicSynthIndex = -1;
			pendingLoopPath = null;
			awaitingIntro = false;
			configureLoopPoints(track);
			startFileMusic(loopPath, usesSegmentLoop(track));
			return;
		}

		playSynthStage(stageNumber);
	}

	private static function configureLoopPoints(track:BgmTrackData):Void {
		loopStartMs = (track.loopStart != null ? track.loopStart : 0) * 1000;
		loopEndMs = track.loopEnd != null ? track.loopEnd * 1000 : 0;
	}

	private static function usesSegmentLoop(track:BgmTrackData):Bool {
		return track.loopEnd != null && track.loopEnd > (track.loopStart != null ? track.loopStart : 0);
	}

	private static function playSynthStage(stageNumber:Int):Void {
		var index = (stageNumber - 1) % musicSounds.length;
		if (index < 0) index = 0;
		if (musicTrackId == "" && index == musicSynthIndex && musicChannel != null) return;

		stopMusicChannelOnly();
		musicTrackId = "";
		musicSynthIndex = index;
		pendingLoopPath = null;
		awaitingIntro = false;
		loopStartMs = 0;
		loopEndMs = 0;
		musicChannel = musicSounds[index].play(0, 0x3FFFFFFF, musicTransform());
	}

	private static function loadMusicSound(path:String):Sound {
		var cached = loadedFileMusic.get(path);
		if (cached != null) return cached;
		var sound = Assets.getSound(path);
		loadedFileMusic.set(path, sound);
		return sound;
	}

	private static function startFileMusic(path:String, segmentLoop:Bool):Void {
		var sound = loadMusicSound(path);
		var loops = segmentLoop || loopEndMs > loopStartMs ? 0 : 0x3FFFFFFF;
		musicChannel = sound.play(loopStartMs, loops, musicTransform());
		if (musicChannel != null) {
			musicChannel.addEventListener(Event.SOUND_COMPLETE, onMusicComplete);
		}
	}

	private static function onMusicComplete(_:Event):Void {
		detachMusicListener();
		if (awaitingIntro && pendingLoopPath != null) {
			awaitingIntro = false;
			var path = pendingLoopPath;
			pendingLoopPath = null;
			var track = BgmLibrary.trackById(musicTrackId);
			var segment = track != null && usesSegmentLoop(track);
			startFileMusic(path, segment);
			return;
		}
		if (musicChannel != null && loopEndMs > loopStartMs) {
			restartMusicAtLoopPoint();
			return;
		}
		if (musicChannel != null && musicTrackId.length > 0) {
			var track = BgmLibrary.trackById(musicTrackId);
			var loopPath = track != null ? BgmLibrary.mainLoopPath(track) : null;
			if (loopPath != null && BgmLibrary.assetReady(loopPath)) {
				startFileMusic(loopPath, track != null && usesSegmentLoop(track));
			}
		}
	}

	private static function restartMusicAtLoopPoint():Void {
		detachMusicListener();
		if (musicChannel != null) {
			musicChannel.stop();
			musicChannel = null;
		}
		var track = BgmLibrary.trackById(musicTrackId);
		var path = track != null ? BgmLibrary.mainLoopPath(track) : null;
		if (path == null) return;
		var segment = track != null && usesSegmentLoop(track);
		startFileMusic(path, segment);
	}

	private static function detachMusicListener():Void {
		if (musicChannel != null) {
			musicChannel.removeEventListener(Event.SOUND_COMPLETE, onMusicComplete);
		}
	}

	private static function stopMusicChannelOnly():Void {
		detachMusicListener();
		if (musicChannel != null) {
			musicChannel.stop();
			musicChannel = null;
		}
	}

	public static function stopMusic():Void {
		stopMusicChannelOnly();
		musicSynthIndex = -1;
		musicTrackId = "";
		pendingLoopPath = null;
		awaitingIntro = false;
	}

	public static function toggleMusicMuted():Bool {
		musicMuted = !musicMuted;
		applyMusicVolume();
		return musicMuted;
	}

	public static function nudgeMusicVolume(delta:Float):Float {
		musicVolume += delta;
		if (musicVolume < 0) musicVolume = 0;
		if (musicVolume > 1) musicVolume = 1;
		applyMusicVolume();
		return musicVolume;
	}

	public static function setMusicDucked(ducked:Bool):Void {
		musicDucked = ducked;
		applyMusicVolume();
	}

	private static function applyMusicVolume():Void {
		if (musicChannel != null) {
			musicChannel.soundTransform = musicTransform();
		}
	}

	private static function musicTransform():SoundTransform {
		var vol = musicMuted ? 0 : musicVolume;
		if (musicDucked && vol > 0) vol *= 0.3;
		return new SoundTransform(vol);
	}

	// --- SFX -----------------------------------------------------------------

	public static function tick():Void {
		if (fireCooldown > 0) fireCooldown--;
		if (grazeCooldown > 0) grazeCooldown--;
		if (hitCooldown > 0) hitCooldown--;

		if (musicChannel != null && loopEndMs > loopStartMs && musicTrackId.length > 0) {
			var pos = musicChannel.position;
			if (pos >= loopEndMs - 50) {
				musicChannel.position = loopStartMs;
			}
		}
	}

	/** Named SFX from manifest; falls back to synth when the file is missing. */
	public static function sfx(name:String, ?volume:Float):Void {
		init();
		var vol = volume != null ? volume : SFX_VOLUME;
		var path = sfxPaths.get(name);
		if (path != null && Assets.exists(path)) {
			playFileSfx(path, vol);
			return;
		}
		playSynthNamed(name, vol);
	}

	private static function playFileSfx(path:String, volume:Float):Void {
		var sound = loadedFileSfx.get(path);
		if (sound == null) {
			sound = Assets.getSound(path);
			loadedFileSfx.set(path, sound);
		}
		if (sound != null) sound.play(0, 0, new SoundTransform(volume));
	}

	private static function playSynthNamed(name:String, volume:Float):Void {
		var sound:Sound = switch (name) {
			case "fire": synthFire;
			case "player_death": synthDeath;
			case "bomb": synthBomb;
			case "item_pickup": synthPickup;
			case "spell_declare": synthSpellDeclare;
			case "spell_capture": synthSpellCapture;
			case "spell_fail": synthSpellFail;
			case "graze": synthGraze;
			case "enemy_hit": synthHit;
			default: null;
		}
		if (sound != null) sound.play(0, 0, new SoundTransform(volume));
	}

	public static function sfxFire():Void {
		if (fireCooldown > 0) return;
		fireCooldown = FIRE_THROTTLE_FRAMES;
		sfx("fire", SFX_VOLUME * 0.5);
	}

	public static function sfxPlayerDeath():Void {
		sfx("player_death", SFX_VOLUME);
	}

	public static function sfxBomb():Void {
		sfx("bomb", SFX_VOLUME);
	}

	public static function sfxItemPickup():Void {
		sfx("item_pickup", SFX_VOLUME * 0.6);
	}

	public static function sfxSpellDeclare():Void {
		sfx("spell_declare", SFX_VOLUME * 0.7);
	}

	public static function sfxSpellCapture():Void {
		sfx("spell_capture", SFX_VOLUME * 0.75);
	}

	public static function sfxSpellFail():Void {
		sfx("spell_fail", SFX_VOLUME * 0.55);
	}

	public static function sfxGraze():Void {
		if (grazeCooldown > 0) return;
		grazeCooldown = GRAZE_THROTTLE_FRAMES;
		sfx("graze", SFX_VOLUME * 0.35);
	}

	public static function sfxEnemyHit():Void {
		if (hitCooldown > 0) return;
		hitCooldown = HIT_THROTTLE_FRAMES;
		sfx("enemy_hit", SFX_VOLUME * 0.4);
	}
}
