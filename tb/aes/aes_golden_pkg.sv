// AES-128 golden model (pure functions, independent of the RTL).
// Conventions follow docs/aes/aes128-core-spec.md section 4:
//   128-bit vectors are big-endian by byte: byte 0 = bits [127:120].
//   FIPS-197 state is column-major: byte i is row (i % 4), column (i / 4).
// Written in a conservative SystemVerilog subset (package + automatic functions).

package aes_golden_pkg;

  // Round keys: rk0 in bits [1407:1280] ... rk10 in bits [127:0]
  typedef logic [1407:0] round_keys_t;

  localparam int MAX_BLOCKS = 8;
  typedef logic [MAX_BLOCKS*128-1:0] stream_t;

  localparam int MODE_ECB = 0;
  localparam int MODE_CBC = 1;
  localparam int MODE_CTR = 2;

  function automatic logic [7:0] xtime(input logic [7:0] b);
    return {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
  endfunction

  function automatic logic [7:0] gmul(input logic [7:0] a, input logic [7:0] b);
    logic [7:0] p, x, y;
    p = 8'h00;
    x = a;
    y = b;
    for (int i = 0; i < 8; i++) begin
      if (y[0]) p = p ^ x;
      x = xtime(x);
      y = y >> 1;
    end
    return p;
  endfunction

  // Lookup tables are built once, on first use, from the mathematical definition
  // (GF(2^8) inverse via log/antilog tables with generator 3, then the affine map).
  logic [7:0] exp_tab [0:255];
  logic [7:0] log_tab [0:255];
  logic [7:0] sb_tab  [0:255];
  logic [7:0] isb_tab [0:255];
  bit         tabs_ready = 1'b0;

  function automatic logic [7:0] rotl8(input logic [7:0] v, input int n);
    return (v << n) | (v >> (8 - n));
  endfunction

  function automatic void init_tabs();
    logic [7:0] e, inv, s;
    if (!tabs_ready) begin
      e = 8'h01;
      for (int i = 0; i < 255; i++) begin
        exp_tab[i] = e;
        log_tab[e] = i[7:0];
        e = gmul(e, 8'h03);
      end
      exp_tab[255] = exp_tab[0];
      log_tab[0] = 8'h00;
      for (int x = 0; x < 256; x++) begin
        inv = (x == 0) ? 8'h00 : exp_tab[(255 - log_tab[x]) % 255];
        s = inv ^ rotl8(inv, 1) ^ rotl8(inv, 2) ^ rotl8(inv, 3) ^ rotl8(inv, 4) ^ 8'h63;
        sb_tab[x] = s;
        isb_tab[s] = x[7:0];
      end
      tabs_ready = 1'b1;
    end
  endfunction

  function automatic logic [7:0] sbox(input logic [7:0] x);
    init_tabs();
    return sb_tab[x];
  endfunction

  function automatic logic [7:0] inv_sbox(input logic [7:0] s);
    init_tabs();
    return isb_tab[s];
  endfunction

  function automatic logic [7:0] get_byte(input logic [127:0] v, input int i);
    return v[127 - 8*i -: 8];
  endfunction

  function automatic logic [127:0] sub_bytes(input logic [127:0] s);
    logic [127:0] r;
    for (int i = 0; i < 16; i++) r[127 - 8*i -: 8] = sbox(get_byte(s, i));
    return r;
  endfunction

  function automatic logic [127:0] inv_sub_bytes(input logic [127:0] s);
    logic [127:0] r;
    for (int i = 0; i < 16; i++) r[127 - 8*i -: 8] = inv_sbox(get_byte(s, i));
    return r;
  endfunction

  // new[r + 4c] = old[r + 4*((c + r) % 4)]
  function automatic logic [127:0] shift_rows(input logic [127:0] s);
    logic [127:0] r;
    for (int c = 0; c < 4; c++)
      for (int row = 0; row < 4; row++)
        r[127 - 8*(row + 4*c) -: 8] = get_byte(s, row + 4*((c + row) % 4));
    return r;
  endfunction

  function automatic logic [127:0] inv_shift_rows(input logic [127:0] s);
    logic [127:0] r;
    for (int c = 0; c < 4; c++)
      for (int row = 0; row < 4; row++)
        r[127 - 8*(row + 4*((c + row) % 4)) -: 8] = get_byte(s, row + 4*c);
    return r;
  endfunction

  function automatic logic [127:0] mix_columns(input logic [127:0] s);
    logic [127:0] r;
    logic [7:0] a0, a1, a2, a3;
    for (int c = 0; c < 4; c++) begin
      a0 = get_byte(s, 4*c);
      a1 = get_byte(s, 4*c + 1);
      a2 = get_byte(s, 4*c + 2);
      a3 = get_byte(s, 4*c + 3);
      r[127 - 8*(4*c)     -: 8] = gmul(a0, 8'd2) ^ gmul(a1, 8'd3) ^ a2 ^ a3;
      r[127 - 8*(4*c + 1) -: 8] = a0 ^ gmul(a1, 8'd2) ^ gmul(a2, 8'd3) ^ a3;
      r[127 - 8*(4*c + 2) -: 8] = a0 ^ a1 ^ gmul(a2, 8'd2) ^ gmul(a3, 8'd3);
      r[127 - 8*(4*c + 3) -: 8] = gmul(a0, 8'd3) ^ a1 ^ a2 ^ gmul(a3, 8'd2);
    end
    return r;
  endfunction

  function automatic logic [127:0] inv_mix_columns(input logic [127:0] s);
    logic [127:0] r;
    logic [7:0] a0, a1, a2, a3;
    for (int c = 0; c < 4; c++) begin
      a0 = get_byte(s, 4*c);
      a1 = get_byte(s, 4*c + 1);
      a2 = get_byte(s, 4*c + 2);
      a3 = get_byte(s, 4*c + 3);
      r[127 - 8*(4*c)     -: 8] = gmul(a0, 8'd14) ^ gmul(a1, 8'd11) ^ gmul(a2, 8'd13) ^ gmul(a3, 8'd9);
      r[127 - 8*(4*c + 1) -: 8] = gmul(a0, 8'd9)  ^ gmul(a1, 8'd14) ^ gmul(a2, 8'd11) ^ gmul(a3, 8'd13);
      r[127 - 8*(4*c + 2) -: 8] = gmul(a0, 8'd13) ^ gmul(a1, 8'd9)  ^ gmul(a2, 8'd14) ^ gmul(a3, 8'd11);
      r[127 - 8*(4*c + 3) -: 8] = gmul(a0, 8'd11) ^ gmul(a1, 8'd13) ^ gmul(a2, 8'd9)  ^ gmul(a3, 8'd14);
    end
    return r;
  endfunction

  function automatic logic [7:0] rcon(input int r);
    logic [7:0] v;
    v = 8'h01;
    for (int i = 1; i < r; i++) v = xtime(v);
    return v;
  endfunction

  // One forward key-schedule step: rk_(r-1) -> rk_r  (spec section 6)
  function automatic logic [127:0] key_step_fwd(input logic [127:0] k, input int r);
    logic [31:0] w0, w1, w2, w3, t;
    w0 = k[127:96]; w1 = k[95:64]; w2 = k[63:32]; w3 = k[31:0];
    t = {w3[23:16], w3[15:8], w3[7:0], w3[31:24]};            // RotWord
    t = {sbox(t[31:24]), sbox(t[23:16]), sbox(t[15:8]), sbox(t[7:0])};
    t = t ^ {rcon(r), 24'h0};
    w0 = w0 ^ t;
    w1 = w1 ^ w0;
    w2 = w2 ^ w1;
    w3 = w3 ^ w2;
    return {w0, w1, w2, w3};
  endfunction

  // One inverse key-schedule step: rk_r -> rk_(r-1)  (spec section 6)
  function automatic logic [127:0] key_step_inv(input logic [127:0] k, input int r);
    logic [31:0] w0, w1, w2, w3, t;
    w0 = k[127:96]; w1 = k[95:64]; w2 = k[63:32]; w3 = k[31:0];
    w3 = w3 ^ w2;
    w2 = w2 ^ w1;
    w1 = w1 ^ w0;
    t = {w3[23:16], w3[15:8], w3[7:0], w3[31:24]};
    t = {sbox(t[31:24]), sbox(t[23:16]), sbox(t[15:8]), sbox(t[7:0])};
    t = t ^ {rcon(r), 24'h0};
    w0 = w0 ^ t;
    return {w0, w1, w2, w3};
  endfunction

  function automatic round_keys_t expand_key(input logic [127:0] key);
    round_keys_t rk;
    logic [127:0] k;
    k = key;
    rk[1407 -: 128] = k;
    for (int r = 1; r <= 10; r++) begin
      k = key_step_fwd(k, r);
      rk[1407 - 128*r -: 128] = k;
    end
    return rk;
  endfunction

  function automatic logic [127:0] get_rk(input round_keys_t rk, input int r);
    return rk[1407 - 128*r -: 128];
  endfunction

  function automatic logic [127:0] aes_encrypt_block(input logic [127:0] key,
                                                     input logic [127:0] pt);
    round_keys_t rk;
    logic [127:0] s;
    rk = expand_key(key);
    s = pt ^ get_rk(rk, 0);
    for (int r = 1; r <= 9; r++)
      s = mix_columns(shift_rows(sub_bytes(s))) ^ get_rk(rk, r);
    s = shift_rows(sub_bytes(s)) ^ get_rk(rk, 10);
    return s;
  endfunction

  function automatic logic [127:0] aes_decrypt_block(input logic [127:0] key,
                                                     input logic [127:0] ct);
    round_keys_t rk;
    logic [127:0] s;
    rk = expand_key(key);
    s = ct ^ get_rk(rk, 10);
    for (int r = 9; r >= 1; r--)
      s = inv_mix_columns(inv_sub_bytes(inv_shift_rows(s)) ^ get_rk(rk, r));
    s = inv_sub_bytes(inv_shift_rows(s)) ^ get_rk(rk, 0);
    return s;
  endfunction

  // Multi-block stream. din/return hold nblocks*128 bits right-aligned,
  // block 0 in the most significant position of that field.
  function automatic stream_t aes_stream(input int mode, input bit enc,
                                         input logic [127:0] key,
                                         input logic [127:0] iv,
                                         input int nblocks,
                                         input stream_t din);
    stream_t dout;
    logic [127:0] fb, blk, o, ctr;
    int sh;
    dout = '0;
    fb = iv;
    ctr = iv;
    for (int i = 0; i < nblocks; i++) begin
      sh = (nblocks - 1 - i) * 128;
      blk = din[sh +: 128];
      case (mode)
        MODE_ECB: o = enc ? aes_encrypt_block(key, blk) : aes_decrypt_block(key, blk);
        MODE_CBC: begin
          if (enc) begin
            o = aes_encrypt_block(key, blk ^ fb);
            fb = o;
          end else begin
            o = aes_decrypt_block(key, blk) ^ fb;
            fb = blk;
          end
        end
        default: begin  // CTR: always encrypt the counter
          o = blk ^ aes_encrypt_block(key, ctr);
          ctr = ctr + 128'd1;
        end
      endcase
      dout[sh +: 128] = o;
    end
    return dout;
  endfunction

endpackage
