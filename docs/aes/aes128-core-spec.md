# AES-128 Core: Functional Design Specification (v0.2)

Status: draft for review. Functional design only. Test and security architecture is planned separately in [../dft/README.md](../dft/README.md).

Changes from v0.1: DFT requirements and security requirements moved out to DFT planning; scan ports removed (insertion tools add them); a short list of DFT-friendly coding rules kept in section 12.

## 1. Decisions (agreed)
| Topic | Decision |
|---|---|
| Datapath | Iterative 128-bit, one round per clock |
| Operations | Encrypt and decrypt |
| Modes | ECB in the core; CBC and CTR in a wrapper around it |
| S-box | 256-entry combinational lookup table (forward and inverse) |
| Key size | 128 bit only |
| Clock domain | `clk_aes` (gated); registers and DMA live on `clk_axi` |

## 2. Scope
In scope: AES-128 per FIPS-197, ECB/CBC/CTR per NIST SP 800-38A, AXI-Lite register slice, clock-domain crossing to `clk_aes`.
Out of scope for v1: AES-192/256, GCM/XTS, side-channel countermeasures, key wrapping, and all test/security architecture (see DFT planning).

## 3. Block structure
```
 regs (clk_axi) --CDC--> aes_mode_wrap --> aes_core --> aes_mode_wrap --CDC--> regs
                                              |
                      key_store (clk_aes) ----+
```
Modules:
- `aes_sbox`, `aes_inv_sbox`: byte lookup tables
- `aes_subbytes`, `aes_inv_subbytes`: 16 parallel S-boxes each
- `aes_shiftrows`, `aes_inv_shiftrows`: wiring only
- `aes_mixcolumns`, `aes_inv_mixcolumns`: GF(2^8) column mixing
- `aes_key_step`: one forward or inverse key-schedule step
- `aes_round`: one round, enc/dec selectable
- `aes_core_ctrl`: FSM and round counter
- `aes_core`: state and round-key registers plus the above
- `aes_mode_wrap`: ECB/CBC/CTR logic and the `iv_ctr` register
- `aes_regs`: AXI-Lite register slice
- `aes_cdc`: toggle handshake between `clk_axi` and `clk_aes`

## 4. Byte and bit conventions
- 128-bit vectors are big-endian by byte: byte 0 is bits [127:120], byte 15 is bits [7:0].
- FIPS-197 state is column-major: state[r][c] = byte[r + 4c].
- Key-schedule words: w0 = bits [127:96] ... w3 = bits [31:0].
- Register words in the AXI map: most-significant word at the lowest address (`DIN0` = bits [127:96]).
The golden model and testbench must use the same convention.

## 5. Datapath
### 5.1 Encrypt round
`state' = AddRoundKey( MixColumns( ShiftRows( SubBytes(state) ) ), rk_r )`
Round 10 skips MixColumns. The initial AddRoundKey with rk0 happens in the load cycle.

### 5.2 Decrypt round (straightforward inverse cipher)
Load cycle: `state = ct XOR rk10`.
Rounds 9 down to 1: `state' = InvMixColumns( AddRoundKey( InvSubBytes( InvShiftRows(state) ), rk_r ) )`
Final round: `state' = AddRoundKey( InvSubBytes( InvShiftRows(state) ), rk0 )` with no InvMixColumns.

### 5.3 GF(2^8) arithmetic
- Polynomial 0x11B. `xtime(b) = (b << 1) XOR (b[7] ? 0x1B : 0x00)`.
- MixColumns matrix rows: [2 3 1 1], [1 2 3 1], [1 1 2 3], [3 1 1 2].
- InvMixColumns matrix rows: [14 11 13 9], [9 14 11 13], [13 9 14 11], [11 13 9 14].
- Build all constant multiplies from xtime; no multiplier cells.

### 5.4 Shared hardware
- AddRoundKey XOR bank shared between enc and dec.
- Forward S-boxes: 16 in the state path plus 4 in the key step (20 total).
- Inverse S-boxes: 16.
- Separate MixColumns and InvMixColumns (no folding tricks in v1, for readability).
- Muxes select enc or dec per round via `enc_dec`.

## 6. Key schedule
Round key register `rk` (128 bit) holds the current round key; the 11 keys are not stored.

Forward step for round r (1 to 10):
```
temp = SubWord(RotWord(w3)) XOR {Rcon[r], 24'h0}
w0' = w0 XOR temp
w1' = w1 XOR w0'
w2' = w2 XOR w1'
w3' = w3 XOR w2'
```
Inverse step (from rk_r back to rk_(r-1)):
```
w3 = w3' XOR w2'
w2 = w2' XOR w1'
w1 = w1' XOR w0'
temp = SubWord(RotWord(w3)) XOR {Rcon[r], 24'h0}
w0 = w0' XOR temp
```
Rcon[1..10] = 01, 02, 04, 08, 10, 20, 40, 80, 1B, 36.

Decrypt needs rk10 first. On the first decrypt after a key load, the core runs a key pre-roll (10 forward steps, no state update), caches rk10 and sets `key_expanded`. Later decrypts with the same key load rk10 directly. Writing a new key clears `key_expanded`.

## 7. Control FSM and timing
States: `IDLE`, `PREROLL`, `LOAD`, `ROUND`, `DONE`.
- `IDLE`: wait for `start`. Encrypt goes to `LOAD`. Decrypt goes to `PREROLL` if not `key_expanded`, otherwise `LOAD` (with rk = cached rk10).
- `PREROLL`: 10 cycles of forward key steps; rk ends at rk10; round counter runs 1 to 10. On exit, cache rk10 and set `key_expanded`.
- `LOAD`: state = data XOR (enc ? rk0 : rk10); round counter set (enc: 1, dec: 10).
- `ROUND`: 10 cycles. Encrypt counts 1 to 10 using forward steps; decrypt counts 10 to 1 using inverse steps. The last round omits (Inv)MixColumns as in section 5.
- `DONE`: `dout_valid` pulses for one cycle; `busy` falls; return to `IDLE`.

Latency from `start`:
| Case | Cycles |
|---|---|
| Encrypt | 11 (1 load + 10 rounds) |
| Decrypt, key already expanded | 11 |
| First decrypt after key load | 21 (10 pre-roll + 11) |
Throughput at 50 MHz, ECB encrypt: 128 bit x 50 MHz / 11 = about 580 Mbit/s. The 50 MHz target is a planning number to confirm in synthesis.

Illegal operations (`start` while busy, `start` with no valid key, mode change while busy) are ignored and set `ERR` in STATUS.

## 8. Mode wrapper
The core is ECB. The wrapper adds a 128-bit XOR in front of and behind the core and one 128-bit feedback register `iv_ctr`.
| Mode | Encrypt | Decrypt |
|---|---|---|
| ECB | C = E(P) | P = D(C) |
| CBC | C_i = E(P_i XOR C_(i-1)), C_0 = IV; iv_ctr <= C_i | P_i = D(C_i) XOR C_(i-1); iv_ctr <= C_i |
| CTR | keystream = E(iv_ctr); out = in XOR keystream; iv_ctr <= iv_ctr + 1 | same as encrypt (the core always runs encrypt in CTR) |
- CTR counter is a full 128-bit increment, modulo 2^128.
- In CTR mode `enc_dec` is ignored and the core is forced to encrypt.
- CBC decrypt must save C_i before the output is produced (the input block is the next feedback value).
- `iv_ctr` is software-loadable through the IV registers; hardware updates it after each block.

## 9. AXI-Lite register map (AES slice; base address set by the SoC memory map)
| Offset | Name | Access | Bits |
|---|---|---|---|
| 0x00 | CTRL | RW | [0] START (self-clear), [1] KEY_LOAD (self-clear), [2] ENC_DEC (1=enc), [4:3] MODE (00 ECB, 01 CBC, 10 CTR), [5] IV_LOAD (self-clear), [8] IRQ_EN, [31] SOFT_RESET (self-clear) |
| 0x04 | STATUS | RO / W1C | [0] BUSY, [1] DONE (W1C), [2] KEY_VALID, [3] KEY_EXPANDED, [4] ERR (W1C), [5] reserved (lifecycle lock, defined in DFT/security planning) |
| 0x10-0x1C | KEY0..3 | WO | key words; reads return 0 |
| 0x20-0x2C | IV0..3 | RW | IV / nonce / counter |
| 0x30-0x3C | DIN0..3 | WO | input block |
| 0x40-0x4C | DOUT0..3 | RO | output block; reads return 0 while BUSY |
Rules: writes to KEY/DIN/IV while BUSY are ignored and set ERR. START latches the registers into the core through the CDC handshake.

## 10. Clocking, reset, CDC
- Core, wrapper and key store run on `clk_aes`, gated by an ICG controlled by the clock/reset controller. The enable is raised before the handshake request and held until `DONE` plus 2 cycles.
- The register block is on `clk_axi`. Control crosses with a toggle handshake (`req` toggles on `clk_axi`, 2-flop sync in `clk_aes`, `ack` back the same way). Data buses (KEY, IV, DIN, DOUT) are quasi-static: held stable between `req` and `ack`, so they cross without synchronizers.
- Reset: asynchronous assert, synchronous deassert per domain (reset synchronizers in the controller). Core flops are all positive-edge.

## 11. Verification plan
### 11.1 Reference vectors (check against FIPS-197 and SP 800-38A before use)
| Test | Key | Input | Expected |
|---|---|---|---|
| FIPS-197 App. B enc | 2b7e151628aed2a6abf7158809cf4f3c | 3243f6a8885a308d313198a2e0370734 | 3925841d02dc09fbdc118597196a0b32 |
| FIPS-197 App. C.1 enc | 000102030405060708090a0b0c0d0e0f | 00112233445566778899aabbccddeeff | 69c4e0d86a7b0430d8cdb78070b4c55a |
| SP800-38A ECB block 1 | 2b7e151628aed2a6abf7158809cf4f3c | 6bc1bee22e409f96e93d7e117393172a | 3ad77bb40d7a3660a89ecaf32466ef97 |
| SP800-38A CBC block 1 (IV 000102...0f) | 2b7e151628aed2a6abf7158809cf4f3c | 6bc1bee22e409f96e93d7e117393172a | 7649abac8119b246cee98e9b12e9197d |
| SP800-38A CTR block 1 (counter f0f1...ff) | 2b7e151628aed2a6abf7158809cf4f3c | 6bc1bee22e409f96e93d7e117393172a | 874d6191b620e3261bef6864990db6ce |
Each encrypt vector also runs as decrypt (swap input and expected).

### 11.2 Testbench structure (UVM, xsim)
- AXI-Lite agent (driver, monitor, sequencer) and register model.
- Scoreboard with a golden AES model written in SystemVerilog (a pure function, independent of the RTL), covering ECB/CBC/CTR, enc/dec.
- Random sequences: random keys, blocks, mode switches, back-to-back operations, key changes mid-stream, illegal operations.
- Directed tests: the vectors above, multi-block CBC/CTR streams, counter wraparound, decrypt with and without cached rk10.

### 11.3 Assertions
- FSM: legal transitions only; `busy` high in every non-IDLE state.
- Latency: encrypt done exactly 11 cycles after START; decrypt 11 or 21 depending on `key_expanded`.
- `dout_valid` one cycle wide, never while idle.
- Handshake: `req`/`ack` toggle ordering; data buses stable between `req` and `ack`.
- Key registers never readable; DOUT reads 0 while BUSY.

### 11.4 Coverage
Functional: mode x enc_dec cross, key_expanded hit/miss on decrypt, illegal-operation types, back-to-back starts, counter wrap. Code: line, toggle and FSM coverage on all AES modules; target 100% FSM and 95%+ line.

## 12. RTL coding rules (including DFT-friendly practice)
- Plain synthesizable Verilog/SystemVerilog subset that both xsim and Yosys accept: no interfaces, classes, or unpacked struct ports in synthesizable code.
- One module per file, file name = module name.
- Parameters only where needed (none for key size in v1).
- All sequential logic in `always_ff` with a single clock and a documented reset style; all flops positive-edge.
- No `initial` blocks in synthesizable code.
- No latches, no tri-states, no combinational loops, no internally generated clocks (the ICG is the only gating element).
- S-boxes written as logic (a case statement), not a ROM macro, so synthesis and ATPG see ordinary gates.
- All state flops have a defined reset value (no X sources).

## 13. Deliverables and milestones
1. Golden model with vector self-check.
2. Combinational pieces with unit tests: S-boxes, MixColumns, key step.
3. `aes_round` and `aes_core` with ECB enc/dec passing all vectors.
4. Mode wrapper with CBC/CTR passing SP800-38A.
5. Register slice, CDC, and the UVM environment.
6. Lint-clean RTL, then Yosys synthesis to sky130 as the first netlist for the later scan flow.

## 14. Open items
- Register base address, once the SoC memory map exists.
- Final port list and handshake timing for `aes_core`, to be fixed at the start of RTL.
- Reset and clock-gate enable timing details (cycle margins) to confirm in simulation.
