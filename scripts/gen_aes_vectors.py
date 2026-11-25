#!/usr/bin/env python3
"""Generate AES-128 test vectors from an independent reference (python 'cryptography').

Output format, one vector per line (all hex, big-endian bytes, block 0 first):
    mode op nblocks key iv din expected
mode: 0 ECB, 1 CBC, 2 CTR     op: 1 encrypt, 0 decrypt
din / expected hold nblocks * 128 bits each (nblocks <= 8).

The script also checks the standard vectors quoted in docs/aes/aes128-core-spec.md
against the reference library, so a typo in the spec table fails here.

Usage: python3 scripts/gen_aes_vectors.py [output_path]
"""
import os
import random
import sys

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

MAX_BLOCKS = 8
RANDOM_PER_CASE = 40
SEED = 20261125


def _cipher(mode, key, iv):
    if mode == 0:
        m = modes.ECB()
    elif mode == 1:
        m = modes.CBC(iv)
    else:
        m = modes.CTR(iv)
    return Cipher(algorithms.AES(key), m)


def run(mode, enc, key, iv, data):
    c = _cipher(mode, key, iv)
    ctx = c.encryptor() if (enc or mode == 2) else c.decryptor()
    return ctx.update(data) + ctx.finalize()


# (name, mode, key, iv, plaintext, expected ciphertext) from the spec table
STANDARD = [
    ("FIPS-197 App. B", 0, "2b7e151628aed2a6abf7158809cf4f3c", "0" * 32,
     "3243f6a8885a308d313198a2e0370734", "3925841d02dc09fbdc118597196a0b32"),
    ("FIPS-197 App. C.1", 0, "000102030405060708090a0b0c0d0e0f", "0" * 32,
     "00112233445566778899aabbccddeeff", "69c4e0d86a7b0430d8cdb78070b4c55a"),
    ("SP800-38A ECB blk1", 0, "2b7e151628aed2a6abf7158809cf4f3c", "0" * 32,
     "6bc1bee22e409f96e93d7e117393172a", "3ad77bb40d7a3660a89ecaf32466ef97"),
    ("SP800-38A CBC blk1", 1, "2b7e151628aed2a6abf7158809cf4f3c",
     "000102030405060708090a0b0c0d0e0f",
     "6bc1bee22e409f96e93d7e117393172a", "7649abac8119b246cee98e9b12e9197d"),
    ("SP800-38A CTR blk1", 2, "2b7e151628aed2a6abf7158809cf4f3c",
     "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
     "6bc1bee22e409f96e93d7e117393172a", "874d6191b620e3261bef6864990db6ce"),
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "tb", "aes", "vectors", "aes_vectors.txt")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    lines = []

    for name, mode, key, iv, pt, ct in STANDARD:
        k, i, p, c = (bytes.fromhex(x) for x in (key, iv, pt, ct))
        got = run(mode, True, k, i, p)
        if got != c:
            sys.exit(f"MISMATCH in spec vector '{name}': reference gives {got.hex()}")
        print(f"spec vector OK: {name}")
        lines.append(f"{mode} 1 1 {key} {iv} {pt} {ct}")
        if mode != 2:
            lines.append(f"{mode} 0 1 {key} {iv} {ct} {pt}")

    rng = random.Random(SEED)
    for mode in (0, 1, 2):
        for enc in (1, 0):
            if mode == 2 and enc == 0:
                continue  # CTR decrypt == CTR encrypt; the core forces encrypt
            for _ in range(RANDOM_PER_CASE):
                n = rng.randint(1, MAX_BLOCKS)
                key = rng.randbytes(16)
                iv = rng.randbytes(16)
                din = rng.randbytes(16 * n)
                exp = run(mode, enc, key, iv, din)
                lines.append(f"{mode} {enc} {n} {key.hex()} {iv.hex()} {din.hex()} {exp.hex()}")

    # CTR counter wraparound: counter near 2^128 - 1, three blocks
    key = rng.randbytes(16)
    iv = bytes.fromhex("ffffffffffffffffffffffffffffffff")
    din = rng.randbytes(48)
    lines.append(f"2 1 3 {key.hex()} {iv.hex()} {din.hex()} {run(2, True, key, iv, din).hex()}")

    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} vectors to {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
