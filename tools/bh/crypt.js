"use strict";
/**
 * Asset sealing for level/pattern JSON.
 *
 * This is obfuscation, NOT security: the key ships inside the game binary, so
 * anyone willing to disassemble it can recover the plaintext. The goal is only
 * to make casual editing of shipped content nontrivial — you can't open a
 * .dat in a text editor and bump a bullet count.
 *
 * Container format (all big-endian):
 *
 *   "BHD1"        4 bytes   magic
 *   salt         16 bytes   per-file, derived from the plaintext (deterministic)
 *   ciphertext    n bytes   plaintext XOR keystream
 *   tag           8 bytes   truncated HMAC over magic|salt|ciphertext
 *
 *   fileKey        = SHA256(MASTER || salt)
 *   keystream[i]   = SHA256(fileKey || uint32be(i))     (32-byte blocks)
 *   tag            = HMAC-SHA256(fileKey, magic|salt|ciphertext)[0..8]
 *
 * The salt is derived (not random) so recompiling unchanged content produces
 * byte-identical output — same reason compile.js emits stable key order.
 *
 * Source/Manager/SecureAssets.hx is the Haxe half and must stay in sync.
 */

const crypto = require("crypto");

const MAGIC = Buffer.from("BHD1", "ascii");
const SALT_LEN = 16;
const TAG_LEN = 8;

// Kept as a plain constant here on purpose: tools/ is authoring-side and never
// ships. The runtime half stores it masked so it isn't greppable in the binary.
const MASTER = Buffer.from(
	"7c49bf17242704e706eae5a465b8329f884984c4c7770a4281177dbf15769dd9",
	"hex"
);

function sha256(...parts) {
	const h = crypto.createHash("sha256");
	for (const p of parts) h.update(p);
	return h.digest();
}

function deriveSalt(plaintext) {
	return crypto.createHmac("sha256", MASTER).update(plaintext).digest().subarray(0, SALT_LEN);
}

function keystreamXor(data, fileKey) {
	const out = Buffer.allocUnsafe(data.length);
	for (let off = 0; off < data.length; off += 32) {
		const counter = Buffer.allocUnsafe(4);
		counter.writeUInt32BE(off / 32, 0);
		const block = sha256(fileKey, counter);
		const n = Math.min(32, data.length - off);
		for (let i = 0; i < n; i++) out[off + i] = data[off + i] ^ block[i];
	}
	return out;
}

function tagFor(fileKey, salt, cipher) {
	return crypto.createHmac("sha256", fileKey)
		.update(MAGIC).update(salt).update(cipher)
		.digest().subarray(0, TAG_LEN);
}

/** Seal a UTF-8 string (or Buffer) into the .dat container. */
function seal(plaintext) {
	const data = Buffer.isBuffer(plaintext) ? plaintext : Buffer.from(plaintext, "utf8");
	const salt = deriveSalt(data);
	const fileKey = sha256(MASTER, salt);
	const cipher = keystreamXor(data, fileKey);
	return Buffer.concat([MAGIC, salt, cipher, tagFor(fileKey, salt, cipher)]);
}

/** Inverse of seal(). Throws if the container is malformed or tampered with. */
function unseal(container) {
	if (container.length < MAGIC.length + SALT_LEN + TAG_LEN) throw new Error("sealed file too short");
	if (!container.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error("bad magic");

	const salt = container.subarray(MAGIC.length, MAGIC.length + SALT_LEN);
	const cipher = container.subarray(MAGIC.length + SALT_LEN, container.length - TAG_LEN);
	const tag = container.subarray(container.length - TAG_LEN);
	const fileKey = sha256(MASTER, salt);

	if (!crypto.timingSafeEqual(tag, tagFor(fileKey, salt, cipher))) throw new Error("integrity check failed");
	return keystreamXor(cipher, fileKey).toString("utf8");
}

module.exports = { seal, unseal, MAGIC };
