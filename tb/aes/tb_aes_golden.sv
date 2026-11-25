// Self-check of the SystemVerilog golden model against independent reference vectors.
// Vectors come from scripts/gen_aes_vectors.py (python 'cryptography'), so the golden
// model is checked against a second, unrelated implementation.
//
// Run: <sim> tb_aes_golden.sv with +VEC=<path to aes_vectors.txt>

module tb_aes_golden;
  import aes_golden_pkg::*;

  int fd, n, errors, checked;
  int mode, op, nb;
  logic [127:0] key, iv;
  logic [MAX_BLOCKS*128-1:0] din, expv, got;
  string vec_path;

  task automatic check(input string what, input logic [127:0] a, input logic [127:0] b);
    if (a !== b) begin
      $display("FAIL %s: got %h expected %h", what, a, b);
      errors++;
    end
  endtask

  initial begin
    errors = 0;
    checked = 0;
    if (!$value$plusargs("VEC=%s", vec_path)) vec_path = "tb/aes/vectors/aes_vectors.txt";

    // S-box spot checks (FIPS-197 figure 7)
    check("sbox(00)", {120'h0, sbox(8'h00)}, 128'h63);
    check("sbox(53)", {120'h0, sbox(8'h53)}, 128'hed);
    check("sbox(ff)", {120'h0, sbox(8'hff)}, 128'h16);
    check("inv_sbox(63)", {120'h0, inv_sbox(8'h63)}, 128'h00);
    for (int x = 0; x < 256; x++)
      check("sbox/inv_sbox roundtrip", {120'h0, inv_sbox(sbox(x[7:0]))}, {120'h0, x[7:0]});

    // GF multiply example from FIPS-197 section 4.2: {57} x {83} = {c1}
    check("gmul(57,83)", {120'h0, gmul(8'h57, 8'h83)}, 128'hc1);

    // Key schedule: last round key for the FIPS-197 appendix A.1 key
    check("rk10 of 2b7e...", get_rk(expand_key(128'h2b7e151628aed2a6abf7158809cf4f3c), 10),
          128'hd014f9a8c9ee2589e13f0cc8b6630ca6);
    // Inverse key step must undo the forward step for every round
    begin
      logic [127:0] k0, k1;
      k0 = 128'h000102030405060708090a0b0c0d0e0f;
      for (int r = 1; r <= 10; r++) begin
        k1 = key_step_fwd(k0, r);
        check("key_step_inv(key_step_fwd)", key_step_inv(k1, r), k0);
        k0 = k1;
      end
    end

    // Vector file
    fd = $fopen(vec_path, "r");
    if (fd == 0) begin
      $display("FAIL: cannot open vector file %s", vec_path);
      $finish;
    end
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%d %d %d %h %h %h %h\n", mode, op, nb, key, iv, din, expv);
      if (n == 7) begin
        got = aes_stream(mode, op[0], key, iv, nb, din);
        for (int i = 0; i < nb; i++)
          check($sformatf("vec %0d mode %0d op %0d blk %0d", checked, mode, op, i),
                got[(nb-1-i)*128 +: 128], expv[(nb-1-i)*128 +: 128]);
        checked++;
      end
    end
    $fclose(fd);

    $display("vectors checked: %0d, errors: %0d", checked, errors);
    if (errors == 0 && checked > 0) $display("PASS: golden model matches reference");
    else $display("FAIL");
    $finish;
  end
endmodule
