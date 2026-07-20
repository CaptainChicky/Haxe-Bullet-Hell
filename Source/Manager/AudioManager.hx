package manager;

import openfl.media.Sound;
import openfl.media.SoundChannel;
import openfl.media.SoundTransform;
import openfl.utils.ByteArray;
import openfl.utils.Endian;

/**
 * All game audio, synthesized at startup — there are no audio assets yet, so
 * every cue is a generated sine wave (the roadmap's placeholder until real
 * music/SFX land). Static: any system can fire a cue without plumbing.
 *
 * Every cue is packaged as an in-memory 16-bit stereo WAV and loaded through
 * loadCompressedDataFromByteArray. Do NOT switch back to
 * loadPCMFromByteArray: raw float PCM buffers are silently unplayable on
 * BOTH shipping targets (lime 8.0.2's OpenAL backend only maps 8/16-bit
 * buffers to an AL format, and the HTML5 howler backend refuses to play a
 * buffer that has no Howl source) — that was the "sound is broken" bug.
 *
 *  - Music: a short looping note sequence per stage (distinct base pitch).
 *  - SFX: one-shot blips for firing / player death / bomb / item pickup.
 *  - Music volume and mute are player-facing (M and [ / ] keys); changing
 *    either applies live to the playing channel.
 */
class AudioManager {
	private static inline final SAMPLE_RATE:Int = 44100;
	private static inline final SFX_VOLUME:Float = 0.35;

	/** Frames between fire blips while the shot button is held. */
	private static inline final FIRE_THROTTLE_FRAMES:Int = 8;

	public static var musicVolume(default, null):Float = 0.5;
	public static var musicMuted(default, null):Bool = false;

	private static var initialized:Bool = false;

	private static var musicChannel:SoundChannel = null;
	private static var musicStage:Int = -1;
	private static var musicSounds:Array<Sound> = [];

	private static var sfxFireSound:Sound;
	private static var sfxDeathSound:Sound;
	private static var sfxBombSound:Sound;
	private static var sfxPickupSound:Sound;

	private static var fireCooldown:Int = 0;

	/** Build every buffer once (cheap: a few seconds of mono-ish sine). */
	public static function init():Void {
		if (initialized) return;
		initialized = true;

		// Placeholder stage tunes: same 8-step pattern, different base pitch
		// per stage (the roadmap's "400, 500, 200 Hz" idea made loopable).
		// Semitone steps of a minor-ish riff so it reads as music, not a drone.
		var riff = [0, 3, 5, 3, 7, 5, 3, 0];
		for (base in [220.0, 277.0, 196.0, 247.0]) {
			var notes:Array<{freq:Float, seconds:Float}> = [];
			for (step in riff) {
				notes.push({freq: base * Math.pow(2, step / 12), seconds: 0.28});
			}
			musicSounds.push(makeSequence(notes, 0.5));
		}

		sfxFireSound = makeSequence([{freq: 880, seconds: 0.05}], 0.4);
		sfxDeathSound = makeSequence([
			{freq: 440, seconds: 0.12},
			{freq: 330, seconds: 0.12},
			{freq: 220, seconds: 0.20}
		], 0.8);
		sfxBombSound = makeSequence([
			{freq: 110, seconds: 0.25},
			{freq: 82, seconds: 0.35}
		], 0.9);
		sfxPickupSound = makeSequence([{freq: 1320, seconds: 0.06}], 0.5);
	}

	/** Synthesize a note sequence into a playable Sound. Each note gets a
	 *  short attack/release envelope so transitions don't click, plus a soft
	 *  second harmonic so the tone reads less like a test signal. */
	private static function makeSequence(notes:Array<{freq:Float, seconds:Float}>, gain:Float):Sound {
		var totalSamples = 0;
		for (note in notes) {
			totalSamples += Std.int(note.seconds * SAMPLE_RATE);
		}

		// WAV container: 44-byte RIFF header + 16-bit little-endian stereo PCM
		var dataBytes = totalSamples * 4; // 2 channels x 2 bytes
		var bytes = new ByteArray();
		bytes.endian = Endian.LITTLE_ENDIAN;
		bytes.writeUTFBytes("RIFF");
		bytes.writeInt(36 + dataBytes);
		bytes.writeUTFBytes("WAVE");
		bytes.writeUTFBytes("fmt ");
		bytes.writeInt(16); // fmt chunk size
		bytes.writeShort(1); // PCM
		bytes.writeShort(2); // stereo
		bytes.writeInt(SAMPLE_RATE);
		bytes.writeInt(SAMPLE_RATE * 4); // byte rate
		bytes.writeShort(4); // block align
		bytes.writeShort(16); // bits per sample
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
				bytes.writeShort(pcm); // left
				bytes.writeShort(pcm); // right
			}
		}
		bytes.position = 0;

		var sound = new Sound();
		sound.loadCompressedDataFromByteArray(bytes, bytes.length);
		return sound;
	}

	// --- Music ---------------------------------------------------------------

	/** Loop the placeholder tune for a 1-based stage (restarts on change). */
	public static function playMusic(stageNumber:Int):Void {
		init();
		var index = (stageNumber - 1) % musicSounds.length;
		if (index == musicStage && musicChannel != null) return;

		stopMusic();
		musicStage = index;
		musicChannel = musicSounds[index].play(0, 0x3FFFFFFF, musicTransform());
	}

	public static function stopMusic():Void {
		if (musicChannel != null) {
			musicChannel.stop();
			musicChannel = null;
		}
		musicStage = -1;
	}

	/** Music mute toggle (M key). Returns the new muted state. */
	public static function toggleMusicMuted():Bool {
		musicMuted = !musicMuted;
		applyMusicVolume();
		return musicMuted;
	}

	/** Nudge music volume by a step ([ / ] keys), clamped to 0..1. */
	public static function nudgeMusicVolume(delta:Float):Float {
		musicVolume += delta;
		if (musicVolume < 0) musicVolume = 0;
		if (musicVolume > 1) musicVolume = 1;
		applyMusicVolume();
		return musicVolume;
	}

	/** Duck the music while the game is paused (no SoundChannel pause API). */
	public static function setMusicDucked(ducked:Bool):Void {
		if (musicChannel != null) {
			var transform = musicTransform();
			if (ducked) transform.volume *= 0.3;
			musicChannel.soundTransform = transform;
		}
	}

	private static function applyMusicVolume():Void {
		if (musicChannel != null) {
			musicChannel.soundTransform = musicTransform();
		}
	}

	private static function musicTransform():SoundTransform {
		return new SoundTransform(musicMuted ? 0 : musicVolume);
	}

	// --- SFX -----------------------------------------------------------------

	/** Fire blip, throttled — the volley fires every frame, the blip must not. */
	public static function sfxFire():Void {
		if (fireCooldown > 0) return;
		fireCooldown = FIRE_THROTTLE_FRAMES;
		play(sfxFireSound, SFX_VOLUME * 0.5);
	}

	/** Count down the fire throttle; call once per unpaused frame. */
	public static function tick():Void {
		if (fireCooldown > 0) fireCooldown--;
	}

	public static function sfxPlayerDeath():Void {
		play(sfxDeathSound, SFX_VOLUME);
	}

	public static function sfxBomb():Void {
		play(sfxBombSound, SFX_VOLUME);
	}

	public static function sfxItemPickup():Void {
		play(sfxPickupSound, SFX_VOLUME * 0.6);
	}

	private static function play(sound:Sound, volume:Float):Void {
		init();
		if (sound != null) {
			sound.play(0, 0, new SoundTransform(volume));
		}
	}
}
