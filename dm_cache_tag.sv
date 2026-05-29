import cache_def::*;

// Memória de tags da cache: 1024 entradas (valid + dirty + tag)
module dm_cache_tag(
  input  bit            clk,
  input  cache_req_type tag_req,   // índice + write enable
  input  cache_tag_type tag_write, // entrada a ser escrita
  output cache_tag_type tag_read   // entrada lida (combinacional)
);
  timeunit 1ns; timeprecision 1ps;

  cache_tag_type tag_mem[0:1023];

  initial begin
    for (int i = 0; i < 1024; i++)
      tag_mem[i] = '0;  // valid e dirty começam em 0
  end

  // Leitura combinacional
  assign tag_read = tag_mem[tag_req.index];

  // Escrita síncrona
  always_ff @(posedge clk) begin
    if (tag_req.we)
      tag_mem[tag_req.index] <= tag_write;
  end

endmodule
