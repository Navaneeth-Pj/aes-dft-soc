# Project roadmap

Goal: take an AES-128 crypto SoC through a full DFT flow (scan, ATPG, boundary scan, 1500, IJTAG, OCC, MBIST, secure test access), the way an industry DFT team would, and verify and document every feature. This replaces the first draft, which assumed a RISC-V SoC; the agreed design is the crypto SoC below.

## Agreed design
- AES-128 crypto accelerator SoC: iterative encrypt/decrypt core, ECB/CBC/CTR wrapper.
- AXI4-Lite registers, AXI4 DMA master.
- Four clock domains (`clk_axi`, `clk_io` always on; `clk_aes`, `clk_mem` gated), plus a test-only TCK.
- Memories: input/output buffers and key store.
- Simplified DDR-style memory controller against a behavioral model.
- GPIO and UART behind a pad ring.
- See [architecture/soc-architecture.jpg](architecture/soc-architecture.jpg).
- Target size 20-40k gates before DFT, to stay within what open-source ATPG handles.

## Tools
| Task | Tool |
|---|---|
| RTL sim, SVA, UVM | Vivado xsim (Windows) |
| Synthesis | Yosys (Linux) |
| Scan insertion, ATPG | Fault and/or OpenROAD DFT (Linux) |
| Gate-level sim | Icarus Verilog / Verilator with sky130 cell models |
Known limits of the open-source flow: Fault's ATPG is stuck-at only and mostly pseudo-random plus fault simulation; transition-fault ATPG, compression, MBIST generation, OCC and IJTAG/1500 insertion are not covered and will be hand-written in RTL.

## Phases
Each phase ends with a feature page written from [templates/feature-doc-template.md](templates/feature-doc-template.md).

### Phase A: AES functional design (current)
1. Freeze the functional spec ([aes/aes128-core-spec.md](aes/aes128-core-spec.md)).
2. Golden model and vectors, then combinational pieces, round, core, mode wrapper.
3. Register slice, CDC, UVM environment.
4. Lint-clean RTL and first Yosys netlist.
Exit: all vectors pass in simulation, coverage targets met.

### Phase B: Rest of the SoC (functional)
AXI interconnect and DMA, buffers and key store, DDR-style controller, GPIO/UART, clock/reset controller, lifecycle controller. Integration tests.
Exit: SoC runs end-to-end encrypt/decrypt through AXI and DMA.

### Phase C: DFT planning
DFT architecture and test plan: scan strategy, chain budget, test modes, clocking for test, memory handling, security policy, access network. Settles the deferred decisions listed in [dft/README.md](dft/README.md).

### Phase D: Scan insertion and ATPG
Scan insertion with multiple chains, DRC handling, stuck-at ATPG, coverage and untestable-fault analysis, gate-level simulation of patterns.

### Phase E: Test access network
TAP and boundary scan, scan access through JTAG, IEEE 1500 wrapper on the AES core, IJTAG SIB network and TDRs, OCC, MBIST.

### Phase F: DFT verification
JTAG driver/monitor, per-feature test plans for BSCAN, SCAN, JTAG, 1500/IJTAG, clocking and security; assertions and coverage.

### Phase G: Wrap-up
Final report: coverage, area overhead, pattern counts, lessons learned. Clean reproducible scripts.

## Stretch goals
Transition-fault ATPG with custom scripts, test-data compression, hierarchical DFT, power-aware DFT.

## Milestones
- [ ] A: AES functional design frozen
- [ ] A: AES RTL passes all vectors
- [ ] A: UVM environment and coverage
- [ ] B: SoC integration
- [ ] C: DFT plan written
- [ ] D: Scan and ATPG results
- [ ] E: Access network built
- [ ] F: DFT verification closed
- [ ] G: Final report
