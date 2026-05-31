`timescale 1ns/1ps
import cache_def::*;

module tb_7_5_casos_limite;

    logic clk, rst, bloco_ok;
    cpu_req_type    cpu_req;
    mem_data_type   mem_data;
    mem_req_type    mem_req;
    cpu_result_type cpu_res;

    dm_cache_fsm dut(
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req),
        .mem_data(mem_data),
        .mem_req(mem_req),
        .cpu_res(cpu_res)
    );

    always #5 clk = ~clk;

    integer erros = 0;

    task automatic esperar_ready(input integer max_ciclos);
        integer i;
        i = 0;
        while (!cpu_res.ready && i < max_ciclos) begin
            @(posedge clk); #1;
            i = i + 1;
        end
    endtask

    // task alinhada com fazer_leitura_simples do tb unificado:
    // espera reativamente pelo estado allocate antes de fornecer o bloco
    task automatic fazer_leitura(
        input logic [31:0]  addr,
        input logic [127:0] bloco_mem,
        output logic ok
    );
        cpu_req.addr  = addr;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;

        @(posedge clk); #1;

        if (dut.rstate == dut.allocate || mem_req.valid == 1) begin
            wait(dut.rstate == dut.allocate);
            @(posedge clk); #1;
            mem_data.data  = bloco_mem;
            mem_data.ready = 1;
            @(posedge clk); #1;
            mem_data.ready = 0;
        end

        wait(cpu_res.ready == 1);
        ok = 1;                // ← captura aqui, enquanto ready ainda é 1
        cpu_req.valid = 0;
        @(posedge clk); #1;
    endtask

    initial begin
        $dumpfile("dump_7_5.vcd");
        $dumpvars(0, tb_7_5_casos_limite);

        $display("=== TESTE 7.5 - CASOS LIMITE ===\n");

        clk = 0;
        rst = 1;
        cpu_req.addr  = 0;
        cpu_req.data  = 0;
        cpu_req.rw    = 0;
        cpu_req.valid = 0;
        mem_data.data  = 0;
        mem_data.ready = 0;

        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk); #1;
        $display("[SETUP] Reset concluido\n");

        // -----------------------------------------------------
        // 7.5.1 - CACHE COMPLETAMENTE INVALIDA (estado inicial)
        // logo apos reset, nenhum bloco e valido
        // qualquer acesso deve gerar miss compulsorio
        // validamos que a FSM trata corretamente o primeiro acesso
        // -----------------------------------------------------
        $display("[7.5.1] Verificando comportamento com cache invalida...");
        $display("        Logo apos reset, todos os blocos sao invalidos");
        $display("        Primeiro acesso deve sempre gerar miss compulsorio");

        cpu_req.addr  = 32'h0000_0400;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        // FSM deve sair de idle -> compare_tag -> miss -> allocate
        // mem_req.valid deve subir indicando busca na memoria
        repeat(3) @(posedge clk); #1;

        if (mem_req.valid) begin
            $display("        [OK] Miss compulsorio detectado, mem_req.valid=1");
            $display("        [OK] FSM solicitou bloco da memoria corretamente");
        end else begin
            $display("        [ERRO] Primeiro acesso nao gerou miss, cache nao estava invalida");
            erros = erros + 1;
        end

        mem_data.data  = 128'h0000_0004_0000_0003_0000_0002_0000_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;
        esperar_ready(10);

        if (cpu_res.ready)
            $display("        [OK] Miss tratado, bloco alocado com sucesso");
        else begin
            $display("        [ERRO] FSM nao respondeu apos fornecimento do bloco");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Cache invalida validada\n");

        // -----------------------------------------------------
        // 7.5.2 - ACESSO AO ENDERECO MINIMO (0x0000_0000)
        // testa o menor endereco possivel
        // indice = addr[13:4] = 0x000, tag = addr[31:14] = 0x0
        // -----------------------------------------------------
        $display("[7.5.2] Acesso ao endereco minimo (0x0000_0000)...");

        fazer_leitura(32'h0000_0000, 128'h0000_0004_0000_0003_0000_0002_0000_0001, bloco_ok);

        // segunda leitura deve ser hit
        cpu_req.addr  = 32'h0000_0000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        esperar_ready(4);

        if (cpu_res.ready)
            $display("        [OK] Segunda leitura em 0x0 foi hit, dado = %h", cpu_res.data);
        else begin
            $display("        [ERRO] Segunda leitura em 0x0 nao foi hit");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Endereco minimo validado\n");

        // -----------------------------------------------------
        // 7.5.3 - ACESSO AO ENDERECO MAXIMO (0xFFFF_FFFC)
        // testa o maior endereco alinhado em 32 bits
        // indice = 0x3FF (todos os bits de indice em 1)
        // tag    = 0x3FFFF (todos os bits de tag em 1)
        // -----------------------------------------------------
        $display("[7.5.3] Acesso ao endereco maximo (0xFFFF_FFFC)...");
        $display("        indice = 0x3FF, tag = 0x3FFFF");

        // primeira leitura (miss — aloca o bloco)
        bloco_ok = 0;
        fazer_leitura(32'hFFFF_FFFC, 128'hFFFF_0004_FFFF_0003_FFFF_0002_FFFF_0001, bloco_ok);

        // amostra imediata: fazer_leitura retorna com ready=1 ainda valido
        if (bloco_ok) begin
            $display("        [OK] Endereco maximo acessado com sucesso");
            $display("        [OK] word3 retornada (offset=2'b11): %h", cpu_res.data);
        end else begin
            $display("        [ERRO] Falha ao acessar endereco maximo");
            erros = erros + 1;
        end

        // segunda leitura (hit — sem acesso a memoria)
        cpu_req.addr  = 32'hFFFF_FFFC;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;

        // avanca para o ciclo onde a FSM entra em compare_tag e calcula o hit
        @(posedge clk); #1;

        // hit e combinatorio: ready ja esta alto agora
        if (cpu_res.ready)
            $display("        [OK] Segunda leitura em 0xFFFF_FFFC foi hit");
        else begin
            $display("        [ERRO] Segunda leitura em 0xFFFF_FFFC nao foi hit");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Endereco maximo validado\n");

        // -----------------------------------------------------
        // 7.5.4 - RESET DURANTE OPERACAO
        // inicia uma requisicao e aplica reset antes de concluir
        // apos reset a FSM deve voltar ao idle e aceitar nova requisicao
        // -----------------------------------------------------
        $display("[7.5.4] Reset durante operacao em andamento...");
        $display("        Iniciando leitura e aplicando reset antes da resposta da memoria");

        cpu_req.addr  = 32'h0001_0000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        @(posedge clk); #1; // FSM entra em compare_tag

        // tratamento de timeout seguro — igual ao tb unificado
        fork : timeout_protection
            begin
                wait(mem_req.valid == 1);
            end
            begin
                repeat(20) @(posedge clk);
            end
        join_any
        disable fork;

        if (mem_req.valid != 1) begin
            $display("        [ERRO FATAL] Timeout! O sinal mem_req.valid nunca subiu.");
            erros = erros + 1;
        end else begin
            $display("        [OK] mem_req.valid detectado com sucesso. Aplicando reset...");
        end

        // aplica reset sem responder a memoria
        cpu_req.valid = 0;
        rst = 1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;
        $display("        Reset aplicado, aguardando estabilizacao...");

        // apos reset, FSM deve aceitar nova requisicao normalmente
        $display("        Enviando nova requisicao apos reset...");
        cpu_req.addr  = 32'h0002_0000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        repeat(2) @(posedge clk); #1;

        mem_data.data  = 128'hABCD_0004_ABCD_0003_ABCD_0002_ABCD_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;
        esperar_ready(10);

        if (cpu_res.ready) begin
            $display("        [OK] FSM voltou ao normal apos reset");
            $display("        [OK] Nova requisicao atendida, dado = %h", cpu_res.data);
        end else begin
            $display("        [ERRO] FSM nao recuperou apos reset");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Reset durante operacao validado\n");

        // -----------------------------------------------------
        // RESULTADO FINAL
        // -----------------------------------------------------
        $display("=== RESULTADO 7.5 ===");
        if (erros == 0)
            $display("Todos os testes passaram.");
        else
            $display("%0d erro(s) encontrado(s).", erros);

        $finish;
    end

endmodule
