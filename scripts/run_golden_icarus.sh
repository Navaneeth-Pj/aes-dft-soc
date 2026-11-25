#!/usr/bin/env bash
# Run the AES golden model self-check with Icarus Verilog.
# Regenerates the reference vectors first (needs python3 + 'cryptography').
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I scripts/gen_aes_vectors.py
mkdir -p build
iverilog -g2012 -o build/golden.vvp tb/aes/aes_golden_pkg.sv tb/aes/tb_aes_golden.sv
vvp build/golden.vvp +VEC=tb/aes/vectors/aes_vectors.txt
