# AES-128 golden model and reference vectors

Status: done (first version)

## 1. Purpose
A reference implementation of AES-128 (ECB/CBC/CTR, encrypt and decrypt) that the RTL and UVM scoreboard are checked against. It is written independently of the RTL and is itself checked against a second, unrelated implementation.

## 2. Background
FIPS-197 for the cipher; NIST SP 800-38A for the modes. Conventions (byte order, state layout, register word order) are fixed in [aes128-core-spec.md](aes128-core-spec.md) section 4.

## 3. Requirements and assumptions
- Pure functions, no simulator-specific features, usable from the UVM scoreboard in xsim.
- Tested against vectors from a different implementation, not against itself.
- Assumption: Icarus Verilog results carry over to xsim. Not yet checked in xsim.

## 4. Architecture and design choices
| Decision | Chosen | Alternatives rejected | Why |
|---|---|---|---|
| Language | SystemVerilog package of automatic functions (`tb/aes/aes_golden_pkg.sv`) | DPI-C to a C model | No C compiler or DPI setup needed in xsim; one language |
| S-box | Built at first use from the definition (GF inverse via log/antilog tables, affine map) | Hard-coded 256-byte table | Cannot contain a transcription typo; the spec-level definition is auditable |
| Reference vectors | Python `cryptography` library, script `scripts/gen_aes_vectors.py` | Only the NIST published vectors | Gives hundreds of random multi-block vectors; the NIST vectors are included and cross-checked too |
| Stream interface | Right-aligned `stream_t` of up to 8 blocks, block 0 most significant | Per-block calls only | Lets CBC/CTR chaining be checked with one call |

## 5. Implementation notes
- Package: `tb/aes/aes_golden_pkg.sv`. Key functions: `aes_encrypt_block`, `aes_decrypt_block`, `aes_stream`, `key_step_fwd`, `key_step_inv`, `expand_key`.
- Testbench: `tb/aes/tb_aes_golden.sv` reads `tb/aes/vectors/aes_vectors.txt`.
- Vector line format: `mode op nblocks key iv din expected` (hex). Mode 0 ECB, 1 CBC, 2 CTR; op 1 encrypt, 0 decrypt.
- Run: `scripts/run_golden_icarus.sh` (needs `iverilog` and python3 with `cryptography`).
- CTR counter is a full 128-bit increment, matching the spec; a wraparound vector is included.

## 6. Verification
- Spec-table vectors (FIPS-197 App. B and C.1, SP 800-38A ECB/CBC/CTR block 1) are checked against the reference library when the vector script runs.
- Self-check covers: S-box spot values, S-box/inverse round trip for all 256 inputs, `gmul({57},{83}) = {c1}`, last round key of the FIPS-197 A.1 key, and that the inverse key step undoes the forward step for all 10 rounds.
- Result: 210 vectors (5 standard encrypt vectors plus their decrypts, 40 random per mode and direction, one CTR wraparound), 0 errors under Icarus Verilog.
- Negative test: corrupting one expected value makes the testbench report FAIL, so a pass is meaningful.

## 7. Issues and debug log
- First version computed the field inverse by brute-force search on every S-box call; the run did not finish in 5 minutes. Replaced by tables built once on first use; the full run now takes about 5 seconds.
- Verilator 5.020 crashed with an internal error on the testbench, so Icarus is the runner for now.

## 8. Results
All vectors pass. The spec's vector table was confirmed correct by the independent reference.

## 9. Open items and sign-off
- [ ] Run the same testbench in Vivado xsim on Windows.
- [ ] Re-check on a newer Verilator, or report the crash.
