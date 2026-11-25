# DFT planning

Not started. DFT planning begins after the AES functional design is frozen, following the usual flow: functional RTL freeze, then DFT spec and test architecture, then scan insertion, ATPG, and verification, each with its own page.

## Features to plan (all in scope)
1. Scan insertion with multiple chains
2. Stuck-at ATPG, coverage analysis
3. Memory handling (wrap or bypass SRAMs)
4. Clock and reset test control (test clock mux, ICG test enable, reset override, lock-up latches)
5. TAP (IEEE 1149.1) with boundary scan
6. Security: lifecycle-controlled debug and scan lock
7. IEEE 1500 wrapper around the AES core
8. IJTAG (IEEE 1687) SIB network with test data registers
9. On-chip clock controller (shift vs capture)
10. MBIST (March algorithm) for the SoC memories

## Decisions deferred to DFT planning
These came up during AES functional design and were deliberately moved here.
- Scan chain count, and the split between key-bearing and other flops.
- Whether the 1500 wrapper covers the key bus or only data and control ports.
- Zeroize policy on scan entry (every entry, or only when leaving SECURE).
- Lifecycle states and what each state allows (JTAG access, scan-out visibility, key write, DOUT read).
- Scan-related ports: added by the insertion tools, not written into the functional RTL.
- Security requirements for the key store and scan observability (for example: no functional path from key flops to any scan-observable point when the lifecycle is SECURE; `key_clear` on any state downgrade).
- Observation points for debug (for example `busy`, `done`, round counter through an IJTAG TDR).
- Lock-up latches at clock-domain crossings in the scan chains.
