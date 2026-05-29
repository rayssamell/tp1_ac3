import cache_def::*;

// Memória de dados da cache: 1024 linhas de 128 bits (porta única)
module dm_cache_data(
  input  bit            clk,
  input  cache_req_type data_req,   // índice + write enable
  input  cache_data_type data_write, // linha a ser escrita
  output cache_data_type data_read   // linha lida (combinacional)
);
  timeunit 1ns; timeprecision 1ps;

  cache_data_type data_mem[0:1023];

  // Inicializa tudo com zero (cache começa vazia/inválida)
  initial begin
    for (int i = 0; i < 1024; i++)
      data_mem[i] = '0;
  end

  // Leitura combinacional: resultado disponível imediatamente
  assign data_read = data_mem[data_req.index];

  // Escrita síncrona: só ocorre na borda de subida se we == 1
  always_ff @(posedge clk) begin
    if (data_req.we)
      data_mem[data_req.index] <= data_write;
  end

endmodule
