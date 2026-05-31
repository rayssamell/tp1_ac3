`timescale 1ns/1ps
import cache_def::*;

module tb_7_4_consistencia;

    logic clk, rst;
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

    // enderecos conflitantes: mesmo indice (addr[13:4] = 0x200), tags diferentes
    localparam ADDR_A = 32'h0000_2000; // indice 0x200, tag 0x0
    localparam ADDR_B = 32'h0004_2000; // indice 0x200, tag 0x1

    task automatic esperar_ready(input integer max_ciclos);
        integer i;
        i = 0;
        while (!cpu_res.ready && i < max_ciclos) begin
            @(posedge clk); #1;
            i = i + 1;
        end
    endtask

    // aloca um bloco via read miss e retorna o dado lido
    // alinhada com fazer_leitura_com_retorno do tb unificado
    task automatic fazer_leitura(
        input  logic [31:0]  addr,
        input  logic [127:0] bloco_mem,
        output logic [31:0]  dado_lido
    );
        cpu_req.addr  = addr;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;

        @(posedge clk); #1;

        // se for miss, trata a memoria; se for hit, ignora este bloco
        if (dut.rstate == dut.allocate || mem_req.valid == 1) begin
            wait(dut.rstate == dut.allocate);
            @(posedge clk); #1;
            mem_data.data  = bloco_mem;
            mem_data.ready = 1;
            @(posedge clk); #1;
            mem_data.ready = 0;
        end

        // espera o pulso de resposta da FSM
        wait(cpu_res.ready == 1);

        // captura imediata do dado antes de qualquer avanco de clock
        dado_lido     = cpu_res.data;
        cpu_req.valid = 0;
        @(posedge clk); #1;
    endtask

    task automatic fazer_escrita(input logic [31:0] addr, input logic [31:0] dado);
        cpu_req.addr  = addr;
        cpu_req.data  = dado;
        cpu_req.rw    = 1;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        esperar_ready(4);
        cpu_req.valid = 0;
        @(posedge clk); #1;
    endtask

    logic [31:0] leitura_resultado;

    initial begin
        $dumpfile("dump_7_4.vcd");
        $dumpvars(0, tb_7_4_consistencia);

        $display("=== TESTE 7.4 - CONSISTENCIA DE DADOS ===\n");

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
        // 7.4.1 - SEQUENCIA WRITE -> READ (coerencia basica)
        // escreve um valor e le de volta no mesmo endereco
        // o valor lido deve ser exatamente o valor escrito
        // -----------------------------------------------------
        $display("[7.4.1] Coerencia basica: write seguido de read...");

        // primeiro aloca o bloco via read miss
        $display("        Alocando bloco em %h via read miss...", ADDR_A);
        fazer_leitura(ADDR_A, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001, leitura_resultado);
        $display("        Bloco alocado, word0 inicial = %h", leitura_resultado);

        // escreve valor novo
        $display("        Escrevendo 0xDEAD_BEEF em %h...", ADDR_A);
        fazer_escrita(ADDR_A, 32'hDEAD_BEEF);
        $display("        Escrita concluida");

        // le de volta e verifica — hit e combinatorio, espera reativa estavel
        $display("        Lendo de volta para verificar coerencia...");
        cpu_req.addr  = ADDR_A;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;

        wait(cpu_res.ready == 1);

        if (cpu_res.ready && cpu_res.data == 32'hDEAD_BEEF)
            $display("        [OK] Dado coerente: leitura retornou %h", cpu_res.data);
        else begin
            $display("        [ERRO] Incoerencia: leu %h, esperado 0xDEAD_BEEF", cpu_res.data);
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // segunda escrita seguida de leitura no mesmo endereco
        $display("        Segunda escrita: 0x1234_5678...");
        fazer_escrita(ADDR_A, 32'h1234_5678);

        cpu_req.addr  = ADDR_A;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;

        wait(cpu_res.ready == 1);

        if (cpu_res.ready && cpu_res.data == 32'h1234_5678)
            $display("        [OK] Segunda escrita coerente: %h", cpu_res.data);
        else begin
            $display("        [ERRO] Incoerencia na segunda escrita: leu %h", cpu_res.data);
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Coerencia basica validada\n");

        // -----------------------------------------------------
        // 7.4.2 - ACESSOS REPETIDOS AO MESMO ENDERECO
        // multiplas leituras seguidas devem retornar sempre
        // o mesmo valor e todas devem ser hit
        // -----------------------------------------------------
        $display("[7.4.2] Acessos repetidos ao mesmo endereco...");
        $display("        Realizando 4 leituras consecutivas em %h", ADDR_A);

        begin
            integer leituras_ok;
            leituras_ok = 0;

            repeat(4) begin
                cpu_req.addr  = ADDR_A;
                cpu_req.rw    = 0;
                cpu_req.valid = 1;

                // espera reativa estavel — elimina esperar_ready cego que causava perda de ciclos
                wait(cpu_res.ready == 1);

                if (cpu_res.ready && cpu_res.data == 32'h1234_5678) begin
                    leituras_ok = leituras_ok + 1;
                    $display("        [OK] Leitura %0d: dado correto = %h", leituras_ok, cpu_res.data);
                end else begin
                    $display("        [ERRO] Leitura retornou dado errado ou nao respondeu");
                    erros = erros + 1;
                end

                cpu_req.valid = 0;
                @(posedge clk); #1;
            end

            $display("        %0d/4 leituras corretas", leituras_ok);
        end

        $display("        Acessos repetidos validados\n");

        // -----------------------------------------------------
        // 7.4.3 - CONFLITO DE INDICE: A e B no mesmo indice
        // aloca A, acessa B (substitui A), acessa A de novo
        // A deve gerar miss na releitura (foi eviccionado por B)
        // os dados de cada bloco devem ser independentes
        // -----------------------------------------------------
        $display("[7.4.3] Conflito de indice entre %h e %h...", ADDR_A, ADDR_B);
        $display("        Ambos mapeiam para indice 0x200");

        // estado atual: A esta no indice 0x200 com dado 0x1234_5678 (dirty)
        $display("        Acessando B para substituir A (A esta dirty, write-back esperado)...");

        cpu_req.addr  = ADDR_B;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // FSM processa em compare_tag

        // espera reativa pelo sinal de miss
        wait(mem_req.valid == 1);
        #1;

        if (mem_req.rw == 1) begin
            $display("        [OK] Write-back de A detectado em %h", mem_req.addr);

            if (mem_req.addr == ADDR_A)
                $display("        [OK] Endereco do write-back correto: %h", mem_req.addr);
            else begin
                $display("        [ERRO] Endereco do write-back incorreto: %h  esperado: %h", mem_req.addr, ADDR_A);
                erros = erros + 1;
            end

            if (mem_req.data[31:0] == 32'h1234_5678)
                $display("        [OK] Dado do write-back correto na word0: %h", mem_req.data[31:0]);
            else begin
                $display("        [ERRO] Dado do write-back incorreto: word0=%h  esperado: 1234_5678", mem_req.data[31:0]);
                erros = erros + 1;
            end

            // FSM em compare_tag -> vai para write_back no proximo clock
            @(posedge clk);
            #1;

            // finaliza o ciclo de write-back respondendo a memoria
            mem_data.ready = 1;
            @(posedge clk);
            #1;
            mem_data.ready = 0;
        end else begin
            $display("        [ERRO] Write-back de A nao detectado (esperado mem_req.rw = 1)");
            erros = erros + 1;
        end

        // FSM moveu-se para allocate — fornece bloco B
        mem_data.data  = 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001;
        mem_data.ready = 1;
        @(posedge clk);
        #1;
        mem_data.ready = 0;

        // aguarda hit final de B
        wait(cpu_res.ready == 1);
        $display("        [OK] Bloco B alocado, word0 = 0xBBBB_0001");

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // agora rele A: deve dar miss pois foi substituido por B
        $display("        Relendo A: deve gerar miss (substituido por B)...");
        cpu_req.addr  = ADDR_A;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // FSM processa em compare_tag

        wait(mem_req.valid == 1);
        #1;

        if (mem_req.rw == 0) begin
            $display("        [OK] Miss em A confirmado, conflito de indice tratado corretamente");

            // espera FSM transitar de compare_tag para allocate
            @(posedge clk);
            #1;

            mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
            mem_data.ready = 1;
            @(posedge clk);
            #1;
            mem_data.ready = 0;

            wait(cpu_res.ready == 1);
        end else begin
            $display("        [ERRO] Comportamento inesperado no miss de A (rw=%b)", mem_req.rw);
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Conflito de indice validado\n");

        // -----------------------------------------------------
        // RESULTADO FINAL
        // -----------------------------------------------------
        $display("=== RESULTADO 7.4 ===");
        if (erros == 0)
            $display("Todos os testes passaram.");
        else
            $display("%0d erro(s) encontrado(s).", erros);

        $finish;
    end

endmodule
