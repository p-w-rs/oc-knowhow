---
name: c-crypto
description: Practical cryptography in C (and from Odin) with Monocypher (single .c/.h: crypto_aead_lock/unlock XChaCha20-Poly1305, incremental AEAD, X25519, EdDSA vs optional Ed25519, BLAKE2b, Argon2, crypto_verify, crypto_wipe) and libsodium (sodium_init, randombytes, crypto_box/secretbox/box_seal, crypto_aead_xchacha20poly1305_ietf and AEGIS, crypto_kx, crypto_kdf, crypto_sign, crypto_pwhash, secretstream, ML-KEM/X-Wing), choosing between them, wire compatibility between them and Odin core:crypto (aead, x25519, ed25519, blake2b, argon2id, noise), and a tested design for encrypting ENet/UDP traffic (signed ephemeral X25519 handshake, per-direction and per-channel keys, counter nonces, replay window for unreliable packets, rekeying, 26-byte overhead, tamper/replay tests). Pitfalls: nonce reuse, unauthenticated encryption, timing leaks, key wiping. Load before adding encryption, signatures, password hashing or a secure channel to C or Odin code.
---

# C crypto: Monocypher, libsodium, encrypted ENet

## Ground truth first

- Versions as of Nov 2026 (verify with `git ls-remote --tags`): **Monocypher 4.0.3** (2026-06-15; fixes a timing leak in
  EdDSA/Ed25519 signing, so upgrade from 4.0.2), **libsodium 1.0.22** (tags `1.0.22` and `1.0.22-RELEASE`; adds ML-KEM768,
  X-Wing `crypto_kem_*` and SHA-3). conda-forge has `libsodium` 1.0.22 (`pixi add libsodium`, then
  `pkg-config --cflags --libs libsodium`). Monocypher has no conda-forge package: vendor `src/monocypher.{c,h}` (and
  `src/optional/monocypher-ed25519.{c,h}` for Ed25519/SHA-512).
- Proposed library references: `monocypher-source` (`src/`, `doc/*.3monocypher` man pages with examples) and
  `libsodium-source` (`src/libsodium/include/sodium/*.h`). `library_search` them for exact signatures and sizes
  (e.g. `query="crypto_aead_unlock" sources=["monocypher-source"]`). Docs: https://monocypher.org/manual/,
  https://doc.libsodium.org/. The headers are the truth: the API changed between Monocypher 3 and 4
  (`crypto_lock` → `crypto_aead_lock`, `crypto_sign` → `crypto_eddsa_sign`, Argon2 takes structs).
- Odin: `core:crypto` (pure Odin, not independently audited per its README) has `aead` (ChaCha20-Poly1305,
  XChaCha20-Poly1305, AES-GCM, AEGIS, Deoxys-II), `x25519`, `ecdh`, `ed25519`, `blake2b/s`, `argon2id`, `hkdf`, `hmac`,
  `sha2/3`, `mlkem`, `mldsa`, `noise`, `crypto.rand_bytes`, `compare_constant_time`, `zero_explicit`. No vendor
  binding for libsodium or Monocypher. See odin.

## Which one

| Need | Pick |
|---|---|
| One file to drop in, embedded/MCU/WASM, no allocations, no RNG dependency in the lib | Monocypher (you supply random bytes) |
| Batteries: RNG, sealed boxes, secretstream, KDF, pwhash strings, guarded memory, AES-GCM/AEGIS with hardware AES, post-quantum KEM | libsodium |
| Odin program | `core:crypto` first; bind Monocypher or libsodium only for interop or speed |

They interoperate (validated byte for byte on Mac arm64 and Linux x86_64): Monocypher `crypto_aead_lock` output ==
libsodium `crypto_aead_xchacha20poly1305_ietf_encrypt_detached` (ciphertext and tag); libsodium's combined form is
`ciphertext || tag` (+16 bytes). `crypto_blake2b_keyed` == `crypto_generichash`. Monocypher `crypto_argon2` with
`CRYPTO_ARGON2_ID`, lanes 1 == `crypto_pwhash(..., crypto_pwhash_ALG_ARGON2ID13)` with the same memory (KiB = blocks)
and passes. `crypto_ed25519_sign` (optional/) is verified by `crypto_sign_verify_detached`, and the same 32-byte seed
gives the same Ed25519 key in both. Odin `core:crypto` matched Monocypher on all of these too.
**Monocypher's main `crypto_eddsa_*` is EdDSA with BLAKE2b, not Ed25519**: different public key, libsodium rejects
the signature. Use `crypto_ed25519_*` from `optional/` whenever anything else must verify.

## Monocypher 4 (validated)

```c
#include "monocypher.h"                      /* cc -O3 monocypher.c [optional/monocypher-ed25519.c] */
uint8_t key[32], nonce[24], mac[16];         /* random bytes from the OS: getrandom/arc4random_buf/BCryptGenRandom */
crypto_aead_lock(ct, mac, key, nonce, ad, ad_len, pt, pt_len);           /* XChaCha20-Poly1305 */
if (crypto_aead_unlock(pt, mac, key, nonce, ad, ad_len, ct, ct_len)) { /* -1: forged/corrupt, pt untouched */ }
crypto_aead_ctx s; crypto_aead_init_x(&s, key, nonce);  /* incremental: crypto_aead_write/read, nonce auto-advances */
crypto_x25519_public_key(pk, sk); crypto_x25519(shared, my_sk, their_pk);  /* raw shared secret is NOT a key: hash it */
crypto_blake2b_ctx h; crypto_blake2b_init(&h, 64); crypto_blake2b_update(&h, shared, 32);
crypto_blake2b_update(&h, pk_a, 32); crypto_blake2b_update(&h, pk_b, 32); crypto_blake2b_final(&h, two_keys);
crypto_ed25519_key_pair(sk64, pk, seed32);   /* wipes seed32! keep a copy if you need it */
crypto_ed25519_sign(sig, sk64, msg, len); crypto_ed25519_check(sig, pk, msg, len) /* 0 ok, -1 bad */;
crypto_argon2_config c = {CRYPTO_ARGON2_ID, 19*1024 /*KiB blocks*/, 2 /*passes*/, 1 /*lanes*/};
crypto_argon2_inputs in = {pw, salt, pw_len, 16};
void *work = malloc((size_t)c.nb_blocks * 1024); crypto_argon2(out, 32, work, c, in, crypto_argon2_no_extras);
crypto_verify16(a, b) /* 0 equal, constant time; also 32, 64 */; crypto_wipe(secret, size);
```
- No RNG, no malloc inside (Argon2 takes your work area), no error codes except unlock/check. The 24-byte XChaCha nonce
  may be random; the `djb`/`ietf` variants (8/12-byte nonces) must use counters (doc `crypto_aead_lock(3)`).

## libsodium 1.0.22 (validated)

```c
if (sodium_init() < 0) abort();               /* once, before anything; thread-safe afterwards */
randombytes_buf(buf, n);
crypto_aead_xchacha20poly1305_ietf_encrypt(c, &clen, m, mlen, ad, adlen, NULL, npub24, key);   /* clen = mlen+16 */
crypto_aead_xchacha20poly1305_ietf_decrypt(m, &mlen, NULL, c, clen, ad, adlen, npub24, key);   /* -1 on forgery */
crypto_kx_keypair(pk, sk);
crypto_kx_client_session_keys(rx, tx, cli_pk, cli_sk, srv_pk);  /* = BLAKE2b-512(X25519(q) || cli_pk || srv_pk) */
crypto_kx_server_session_keys(rx, tx, srv_pk, srv_sk, cli_pk);  /* client tx == server rx and vice versa */
crypto_kdf_derive_from_key(sub, 32, id, "8bytectx", master);   /* context is exactly 8 chars */
crypto_sign_keypair(pk, sk); crypto_sign_detached(sig, NULL, m, mlen, sk); crypto_sign_verify_detached(sig, m, mlen, pk);
crypto_secretbox_easy / crypto_box_easy / crypto_box_seal (anonymous sender, +48 B) / *_open_*;
crypto_pwhash_str(out, pw, len, crypto_pwhash_OPSLIMIT_INTERACTIVE, crypto_pwhash_MEMLIMIT_INTERACTIVE);  /* "$argon2id$v=19$m=65536,t=2,p=1$..." */
crypto_secretstream_xchacha20poly1305_init_push/push/init_pull/pull;  /* files & streams: 24 B header, +17 B per chunk, TAG_FINAL, rekey */
sodium_memzero(p, n); sodium_memcmp(a, b, n); sodium_malloc/sodium_free (guard pages); sodium_bin2hex/hex2bin;
```
- secretstream detects reordered, dropped and truncated chunks (validated: a reordered chunk fails); use it for files
  and TCP-like streams, not for UDP.
- Post-quantum: `crypto_kem_keypair/enc/dec` is X-Wing (ML-KEM768 + X25519; pk 1216 B, ciphertext 1120 B, both
  fit one ENet packet). Not exercised in these tests.

## Speed (validated, 1200-byte packet / 1 MiB bulk, single core)

| Machine | XChaCha20-Poly1305 per 1200 B packet (Mono / sodium) | bulk GB/s (Mono / sodium) | sodium AEGIS-256 | Argon2id 19 MiB t=2 |
|---|---|---|---|---|
| Mac M2 Max | 3.1 / 2.6 µs | 0.45 / 0.52 | 8.6 GB/s | 16 ms (both) |
| Core Ultra 9 285K | 1.75 / 0.84 µs | 0.79 / 2.40 (AVX2) | 14.1 GB/s | 23 / 15 ms |
| Jetson AGX Orin | 4.4 / 4.2 µs | 0.33 / 0.32 | 2.8 GB/s | 34 / 53 ms |

So per-packet AEAD costs a few µs: fine for game/robot traffic (10k packets/s ≈ 4% of an Orin core). For bulk data on
CPUs with AES instructions, `crypto_aead_aegis256_*` (32 B key, 32 B nonce) is 5–20× faster.

## Encrypting ENet traffic (tested design)

ENet has no security (see c-networking). Validated with zpl-c/enet v2.7.0: `tests/enet_secure.c` (both AEAD backends),
1000 reliable + 1000 unsequenced 500-byte packets echoed, loopback on Mac and Linux and Mac → Jetson over a VPN
tunnel (RTT 66 ms), with and without simulated loss.

1. **Handshake** on channel 0 (reliable) right after `ENET_EVENT_TYPE_CONNECT`:
   `C→S HELLO = 0x01 | ver | client_eph_pk[32]`; `S→C WELCOME = 0x02 | ver | server_eph_pk[32] | sig[64]` with
   `sig = Ed25519(server_identity_sk, "ESEC1" | client_eph_pk | server_eph_pk)`. The client **pins** the server's
   identity public key (shipped with the client) and verifies before deriving keys: a wrong key aborted with
   "HANDSHAKE FAIL" in the test. Without authentication an attacker in the middle can run two key exchanges. Both sides
   then call `crypto_kx_*_session_keys` (or X25519 + BLAKE2b-512 in Monocypher, which gives identical keys) and wipe the
   ephemeral secret (forward secrecy). Authenticate clients inside the encrypted channel (token, password, signature).
2. **Keys per direction and per channel**: `key[dir][ch] = crypto_kdf_derive_from_key(ch, "ENETCHAN", kx_key[dir])`.
   Never use one key for both directions (two senders with counter nonces would collide).
3. **Record** = `0x10 | epoch u8 | counter u64 LE | ciphertext | tag16` → **26 bytes overhead** per packet
   (5% of a 500 B payload; keep payload + 26 under the MTU 1392). Nonce (24 B) = counter ‖ channel ‖ epoch ‖ zeros, AD =
   the 10-byte header + channel id, so header fields can't be altered. Counter per (direction, channel), never reset
   under the same key; abort on wrap.
4. **Receive rules**: reliable channel: ENet already delivers in order exactly once, so require
   `counter == expected`. Unreliable/unsequenced channels: 64-entry sliding window (bitmap of the last 64 counters):
   reject `counter <= highest - 64` and already-seen counters; update the window **only after** the tag verifies.
5. **Rekey**: after N packets (or minutes) per (direction, channel): `key = KDF(key, epoch+1)`, epoch++, wipe the old
   key. Receivers ratchet forward on an authenticated packet with a newer epoch, accept up to `MAX_SKIP` (4) epochs
   ahead on unreliable channels (packets were lost), keep the previous key for late packets, and reject anything else.
6. **Attack tests** (all rejected, server counted exactly `auth_fail=3, replay=1`): flipped ciphertext bit, a resent
   old valid packet (replay), forged epoch byte, truncated 12-byte packet. Loss test: 40% of unsequenced packets dropped
   including a 300-packet gap (1.5 epochs) → all 600 delivered packets decrypted.

**Bug found while testing**: the first version shared one epoch per direction across channels. ENet delivers
unsequenced packets immediately but holds reliable ones back for ordering, so the epoch advanced on one channel and
valid packets on the other were rejected (Linux: 408/1000 delivered, 114 auth failures; Mac happened to pass). Keep all
crypto state per (direction, channel).

Alternatives: hook raw datagrams with `enet_host_set_intercept` to encrypt ENet's own headers too (more work: you
must handle ENet's connect packets), or use a protocol with built-in security (QUIC/msquic, DTLS,
GameNetworkingSockets, WireGuard between hosts). `core:crypto/noise` (Odin) implements the Noise framework for the
handshake (below).

## From Odin

- `core:crypto` (validated, `-vet -strict-style`): equal to Monocypher on XChaCha20-Poly1305, X25519, Ed25519,
  keyed BLAKE2b, Argon2id; Argon2id OWASP params 20 ms (Mac), 28 ms (285K).
  ```odin
  aead.seal_oneshot(.XCHACHA20POLY1305, ct, tag[:], key[:], nonce[:], aad, pt)
  ok := aead.open_oneshot(.XCHACHA20POLY1305, out, key[:], nonce[:], aad, ct, tag[:])   // @(require_results); zeroes out on failure
  x25519.scalarmult_basepoint(pk[:], sk[:]); x25519.scalarmult(shared[:], sk[:], their_pk[:])
  ed25519.private_key_generate(&sk); ed25519.public_key_set_priv(&pk, &sk); ed25519.sign(&sk, msg, sig[:]); ed25519.verify(&pk, msg, sig[:])
  blake2b.init_mac(&ctx, key[:], 32); blake2b.update(&ctx, msg); blake2b.final(&ctx, out[:])
  params := argon2id.PARAMS_OWASP; err := argon2id.derive(&params, pw, salt, out[:])   // also PARAMS_RFC9106(_SMALL), OWASP_SMALL
  crypto.rand_bytes(buf[:]); crypto.compare_constant_time(a, b) == 1; crypto.zero_explicit(&key, size_of(key))
  ```
- `core:crypto/noise`: `handshake_init(&hs, initiator, prologue, &static_sk, peer_static_pk_or_nil,
  "Noise_XX_25519_ChaChaPoly_BLAKE2b")`, then `handshake_initiator_step` / `handshake_responder_step` until
  `.Handshake_Complete` (XX: messages of 32, 96, 64 bytes), `handshake_split`, `seal_message` / `open_message`.
  Transport nonces are implicit counters: a replayed or reordered message fails (`Decryption_Failure`, validated), so over
  UDP send the counter explicitly and use `cipherstates_set_n` or your own AEAD as above. The parser accepts the
  `25519`/`448`, `ChaChaPoly`/`AESGCM` and `SHA256`/`SHA512`/`BLAKE2s`/`BLAKE2b` names.
- Monocypher from Odin: build a static lib (`cc -O3 -c monocypher.c optional/monocypher-ed25519.c && ar rcs
  libmonocypher.a *.o`), then `foreign import mono "libmonocypher.a"` and declare procs with fixed arrays as pointers:
  `crypto_aead_lock :: proc(ct: [^]u8, mac: ^[16]u8, key: ^[32]u8, nonce: ^[24]u8, ad: [^]u8, ad_size: uint, pt: [^]u8, size: uint) ---`.
  Structs passed by value (Argon2 config/inputs/extras) map to Odin structs of `u32`/pointers. libsodium: same with
  `foreign import sodium "system:sodium"` (add `-extra-linker-flags:"-L$CONDA_PREFIX/lib"`).
- Odin pitfall seen: `-vet` rejects a `defer` in a scope that ends with `os.exit` ("Unreachable defer statement"); put the
  work in a proc and call `os.exit` from `main`.

## Pitfalls

- **Nonce reuse** with the same key reveals plaintext XOR and lets attackers forge (Poly1305 key recovery). Random
  nonces only with 24-byte XChaCha (or AEGIS-256); counters for 8/12-byte nonces; separate keys per sender.
- **Encryption without authentication is not security**: never use raw `crypto_chacha20_*`/stream ciphers for messages;
  always an AEAD and check its return value before touching the plaintext. Put headers you rely on into the AD.
- **Hash the X25519 output** (or use `crypto_kx`) and include both public keys; an all-zero shared secret means a
  low-order point (`crypto_kx_*` returns -1; with Monocypher check with `crypto_verify32` against zeros).
- **Constant time**: compare MACs, tokens, password hashes with `crypto_verify16/32/64`, `sodium_memcmp`,
  `crypto.compare_constant_time`, never `memcmp`/`==`. Don't branch on secret data.
- **Wipe secrets** (`crypto_wipe`, `sodium_memzero`, `crypto.zero_explicit`; a plain `memset` before `free` can be
  optimised away). Keep session keys in `sodium_malloc` memory if swap/core dumps matter. Monocypher's key-pair
  functions wipe the seed you pass in (validated) — copy it first if you need it again.
- **RNG**: OS only (`randombytes_buf`, `getrandom`, `arc4random_buf`, `crypto.rand_bytes`); never `rand()`, never a
  user-space PRNG seeded from time; on MCUs use the hardware TRNG (see odin-targets).
- **Passwords**: Argon2id with a random 16-byte salt per user; store the `$argon2id$…` string; tune memory to ~50–100 ms.
- **Signatures ≠ encryption**, and Monocypher EdDSA ≠ Ed25519 (above). Pin long-term public keys; rotate session keys.
- Don't invent primitives; only compose AEAD + key exchange + KDF + signatures as above, and test tampering, replay,
  wrong keys and loss explicitly, as the ENet test does.
