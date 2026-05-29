import cache_def::*;

// Controlador de cache: FSM com 4 estados
//   idle        -> aguarda requisição do processador
//   compare_tag -> verifica hit/miss e atualiza tag memory
//   allocate    -> espera bloco chegar da memória principal (read miss)
//   write_back  -> escreve linha dirty na memória antes de alocar nova
module dm_cache_fsm(
  input  bit            clk,
  input  bit            rst,
  input  cpu_req_type   cpu_req,  // requisição do processador
  input  mem_data_type  mem_data, // resposta da memória principal
  output mem_req_type   mem_req,  // requisição para a memória principal
  output cpu_result_type cpu_res  // resultado para o processador
);
  timeunit 1ns; timeprecision 1ps;

  typedef enum {idle, compare_tag, allocate, write_back} cache_state_type;

  cache_state_type vstate, rstate; // próximo estado / estado atual

  // Sinais de interface com a tag memory
  cache_tag_type  tag_read;
  cache_tag_type  tag_write;
  cache_req_type  tag_req;

  // Sinais de interface com a data memory
  cache_data_type data_read;
  cache_data_type data_write;
  cache_req_type  data_req;

  // Variáveis combinacionais (saídas calculadas antes de registrar)
  cpu_result_type v_cpu_res;
  mem_req_type    v_mem_req;

  assign mem_req = v_mem_req;
  assign cpu_res = v_cpu_res;

  always_comb begin
    // --- valores padrão (evitam latches) ---
    vstate            = rstate;
    v_cpu_res.data    = '0;
    v_cpu_res.ready   = '0;
    tag_write.valid   = '0;
    tag_write.dirty   = '0;
    tag_write.tag     = '0;

    tag_req.we    = '0;
    tag_req.index = cpu_req.addr[13:4];  // bits de índice (direct-mapped)

    data_req.we    = '0;
    data_req.index = cpu_req.addr[13:4];

    // Prepara data_write com a linha atual, sobrescrevendo a palavra endereçada
    data_write = data_read;
    case (cpu_req.addr[3:2])  // offset de palavra dentro do bloco
      2'b00: data_write[31:0]   = cpu_req.data;
      2'b01: data_write[63:32]  = cpu_req.data;
      2'b10: data_write[95:64]  = cpu_req.data;
      2'b11: data_write[127:96] = cpu_req.data;
    endcase

    // Seleciona a palavra de 32 bits correta para enviar à CPU
    case (cpu_req.addr[3:2])
      2'b00: v_cpu_res.data = data_read[31:0];
      2'b01: v_cpu_res.data = data_read[63:32];
      2'b10: v_cpu_res.data = data_read[95:64];
      2'b11: v_cpu_res.data = data_read[127:96];
    endcase

    v_mem_req.addr  = cpu_req.addr;
    v_mem_req.data  = data_read;  // dado para write-back (se necessário)
    v_mem_req.rw    = '0;
    v_mem_req.valid = '0;

    // --- FSM ---
    case (rstate)

      idle: begin
        if (cpu_req.valid)
          vstate = compare_tag;
      end

      compare_tag: begin
        if (cpu_req.addr[TAGMSB:TAGLSB] == tag_read.tag && tag_read.valid) begin
          // HIT: dado está na cache
          v_cpu_res.ready = '1;

          if (cpu_req.rw) begin
            // Write hit: atualiza dado e marca linha como dirty
            tag_req.we  = '1;
            data_req.we = '1;
            tag_write.tag   = tag_read.tag;
            tag_write.valid = '1;
            tag_write.dirty = '1;
          end

          vstate = idle;
        end
        else begin
          // MISS: atualiza tag com novo endereço
          tag_req.we      = '1;
          tag_write.valid = '1;
          tag_write.tag   = cpu_req.addr[TAGMSB:TAGLSB];
          tag_write.dirty = cpu_req.rw; // sujo apenas se for write miss

          v_mem_req.valid = '1;

          if (tag_read.valid == 1'b0 || tag_read.dirty == 1'b0) begin
            // Miss com linha limpa ou inválida: apenas busca da memória
            vstate = allocate;
          end
          else begin
            // Miss com linha dirty: precisa fazer write-back antes
            v_mem_req.addr = {tag_read.tag, cpu_req.addr[TAGLSB-1:0]};
            v_mem_req.rw   = '1;
            vstate = write_back;
          end
        end
      end

      allocate: begin
        // Aguarda a memória principal responder com o novo bloco
        if (mem_data.ready) begin
          data_write  = mem_data.data;
          data_req.we = '1;
          vstate = compare_tag; // re-executa compare para tratar write miss
        end
      end

      write_back: begin
        // Aguarda confirmação de escrita na memória, depois busca novo bloco
        if (mem_data.ready) begin
          v_mem_req.valid = '1;
          v_mem_req.rw    = '0;
          vstate = allocate;
        end
      end

    endcase
  end

  // Registro de estado: atualiza na borda de subida ou reseta para idle
  always_ff @(posedge clk) begin
    if (rst)
      rstate <= idle;
    else
      rstate <= vstate;
  end

  // Instancia as memórias internas (conexão por nome implícita via .*)
  dm_cache_tag  ctag(.*);
  dm_cache_data cdata(.*);

endmodule
