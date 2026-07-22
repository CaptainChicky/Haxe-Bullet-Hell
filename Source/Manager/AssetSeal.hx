package manager;

import haxe.io.Bytes;
import haxe.crypto.Sha256;
import haxe.crypto.Hmac;

/**
 * Opens the sealed container that level/pattern JSON ships in.
 * tools/bh/crypt.js is the authoring half and must stay in sync — see that
 * file for the layout and for why this is obfuscation and not security.
 *
 * Deliberately free of openfl imports so the round-trip against real .dat
 * files can be tested headlessly (Tests/TestSeal.hx). Asset lookup lives in
 * SecureAssets.
 */
class AssetSeal {
	private static inline final MAGIC:String = "BHD1";
	private static inline final SALT_LEN:Int = 16;
	private static inline final TAG_LEN:Int = 8;
	private static inline final BLOCK:Int = 32;

	private static var cachedKey:Bytes = null;

	/** Reverse the container. Returns null on any structural or tag mismatch. */
	public static function open(container:Bytes):String {
		if (container == null || container.length < MAGIC.length + SALT_LEN + TAG_LEN) return null;
		if (container.getString(0, MAGIC.length) != MAGIC) return null;

		var cipherStart = MAGIC.length + SALT_LEN;
		var cipherLen = container.length - cipherStart - TAG_LEN;

		var salt = container.sub(MAGIC.length, SALT_LEN);
		var cipher = container.sub(cipherStart, cipherLen);
		var tag = container.sub(container.length - TAG_LEN, TAG_LEN);

		var fileKey = Sha256.make(concat([master(), salt]));
		if (tag.compare(tagFor(fileKey, salt, cipher)) != 0) return null;

		return keystreamXor(cipher, fileKey).toString();
	}

	/** Truncated HMAC-SHA256 over magic|salt|ciphertext. */
	private static function tagFor(fileKey:Bytes, salt:Bytes, cipher:Bytes):Bytes {
		var msg = concat([Bytes.ofString(MAGIC), salt, cipher]);
		return new Hmac(SHA256).make(fileKey, msg).sub(0, TAG_LEN);
	}

	/** XOR against SHA256(fileKey || counter) blocks; self-inverse. */
	private static function keystreamXor(data:Bytes, fileKey:Bytes):Bytes {
		var out = Bytes.alloc(data.length);
		var counter = Bytes.alloc(4);
		var block = 0;
		var offset = 0;

		while (offset < data.length) {
			counter.set(0, (block >> 24) & 0xFF);
			counter.set(1, (block >> 16) & 0xFF);
			counter.set(2, (block >> 8) & 0xFF);
			counter.set(3, block & 0xFF);

			var pad = Sha256.make(concat([fileKey, counter]));
			var n = data.length - offset;
			if (n > BLOCK) n = BLOCK;
			for (i in 0...n) {
				out.set(offset + i, data.get(offset + i) ^ pad.get(i));
			}

			offset += BLOCK;
			block++;
		}

		return out;
	}

	private static function concat(parts:Array<Bytes>):Bytes {
		var total = 0;
		for (p in parts) total += p.length;

		var out = Bytes.alloc(total);
		var offset = 0;
		for (p in parts) {
			out.blit(offset, p, 0, p.length);
			offset += p.length;
		}
		return out;
	}

	/**
	 * The shared secret, stored XOR-masked so the key never appears as a
	 * contiguous constant in the binary and `strings` on the executable turns
	 * up nothing useful. Assembled once, then cached.
	 */
	private static function master():Bytes {
		if (cachedKey != null) return cachedKey;

		var masked = [
			0xe0, 0xf5, 0x86, 0xd3, 0x74, 0xe3, 0x5b, 0x17, 0xe8, 0xf1, 0x6b, 0xb4, 0x94, 0x2c, 0xb6, 0x7f,
			0x14, 0x5f, 0x92, 0x7e, 0xc1, 0xe9, 0xcb, 0x0f, 0xc8, 0x94, 0x86, 0x21, 0x30, 0x1d, 0x62, 0xa6
		];
		var mask = [
			0x9c, 0xbc, 0x39, 0xc4, 0x50, 0xc4, 0x5f, 0xf0, 0xee, 0x1b, 0x8e, 0x10, 0xf1, 0x94, 0x84, 0xe0,
			0x9c, 0x16, 0x16, 0xba, 0x06, 0x9e, 0xc1, 0x4d, 0x49, 0x83, 0xfb, 0x9e, 0x25, 0x6b, 0xff, 0x7f
		];

		var key = Bytes.alloc(masked.length);
		for (i in 0...masked.length) key.set(i, masked[i] ^ mask[i]);

		cachedKey = key;
		return key;
	}
}
