`timescale 1ns/1ps
import cache_def::*;

module tb_7_2_write;

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

    task automatic esperar_ready(input integer max_ciclos);
        integer i;
        i = 0;
        while (!cpu_res.ready && i < max_ciclos) begin
            @(posedge clk); #1;
            i = i + 1;
        end
    endtask

    task automatic responder_memoria(input logic [127:0] bloco);
        repeat(2) @(posedge clk);
        mem_data.data  = bloco;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;
    endtask

    initial begin
        $dumpfile("dump_7_2.vcd");
        $dumpvars(0, tb_7_2_write);

        $display("=== TESTE 7.2 - WRITE PATH ===\n");

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
        // PRE-REQUISITO: alocar bloco via read miss
        // write hit so funciona se o bloco ja estiver na cache
        // -----------------------------------------------------
        $display("[PRE] Alocando bloco via read miss em 0x0000_2000...");

        cpu_req.addr  = 32'h0000_2000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        fork
            responder_memoria(128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001);
        join_none

        esperar_ready(10);

        if (cpu_res.ready)
            $display("[PRE] Bloco alocado, dado inicial word0 = 0xBBBB_0001\n");
        else begin
            $display("[PRE] ERRO: bloco nao foi alocado, abortando");
            $finish;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // -----------------------------------------------------
        // 7.2.1 - WRITE HIT
        // bloco ja esta na cache, escrita deve ocorrer direto
        // sem precisar acessar a memoria principal
        // -----------------------------------------------------
        $display("[7.2.1] Iniciando Write Hit...");
        $display("        endereco: 0x0000_2000  dado: 0xDEAD_BEEF");

        cpu_req.addr  = 32'h0000_2000;
        cpu_req.data  = 32'hDEAD_BEEF;
        cpu_req.rw    = 1;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        esperar_ready(4);

        if (cpu_res.ready)
            $display("        [OK] ready subiu = write hit confirmado");
        else begin
            $display("        [ERRO] ready nao subiu no tempo esperado");
            erros = erros + 1;
        end

        if (!mem_req.valid)
            $display("        [OK] mem_req.valid=0, dado ficou na cache (write-back)");
        else begin
            $display("        [ERRO] mem_req.valid subiu indevidamente");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // le de volta para confirmar que o dado foi escrito
        $display("        Verificando dado escrito com leitura de retorno...");
        cpu_req.addr  = 32'h0000_2000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        esperar_ready(4);

        if (cpu_res.data == 32'hDEAD_BEEF)
            $display("        [OK] dado correto: %h", cpu_res.data);
        else begin
            $display("        [ERRO] dado errado: %h  esperado: DEAD_BEEF", cpu_res.data);
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Write Hit concluido\n");

        // -----------------------------------------------------
        // 7.2.2 - WRITE MISS (write-allocate)
        // endereco nunca acessado, FSM deve buscar bloco
        // da memoria antes de realizar a escrita
        // -----------------------------------------------------
        $display("[7.2.2] Iniciando Write Miss (write-allocate)...");
        $display("        endereco: 0x0000_3000  dado: 0xCAFE_BABE");

        cpu_req.addr  = 32'h0000_3000;
        cpu_req.data  = 32'hCAFE_BABE;
        cpu_req.rw    = 1;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        begin
            logic mem_respondeu;
            mem_respondeu = 0;

            fork
                begin
                    wait(dut.rstate == dut.allocate);
                    @(posedge clk); #1;
                    mem_data.data  = 128'h0;
                    mem_data.ready = 1;
                    mem_respondeu  = 1;
                    @(posedge clk); #1;
                    mem_data.ready = 0;
                end
            join_none

            esperar_ready(10);

            if (cpu_res.ready && mem_respondeu) begin
                $display("        [OK] write miss tratado corretamente");
                $display("        [OK] bloco alocado antes da escrita (write-allocate)");
            end else begin
                $display("        [ERRO] write miss nao foi tratado");
                erros = erros + 1;
            end
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Write Miss concluido\n");

        // -----------------------------------------------------
        // 7.2.3 - VALIDACAO WRITE-BACK + DIRTY BIT
        // o bloco de 0x0000_2000 foi escrito em 7.2.1, esta dirty
        // acesso a 0x0004_2000 tem mesmo indice, deve provocar
        // write-back do bloco dirty antes de alocar o novo
        // -----------------------------------------------------
        $display("[7.2.3] Validando write-back do bloco dirty...");
        $display("        endereco conflitante: 0x0004_2000 (mesmo indice que 0x0000_2000)");

        fork
            // -----------------------------------------------------------------
            // THREAD 1: Lado da CPU
            // -----------------------------------------------------------------
            begin
                cpu_req.addr  = 32'h0004_2000;
                cpu_req.rw    = 0;
                cpu_req.valid = 1;

                wait(cpu_res.ready == 1);
                $display("        [OK] novo bloco alocado apos write-back");

                @(posedge clk); #1;
                cpu_req.valid = 0;
            end

            // -----------------------------------------------------------------
            // THREAD 2: Lado da memoria
            // -----------------------------------------------------------------
            begin
                wait(mem_req.valid == 1 && mem_req.rw == 1);

                $display("        [OK] write-back emitido: mem_req.rw=1");

                if (mem_req.addr == 32'h0000_2000)
                    $display("        [OK] endereco do write-back correto: %h", mem_req.addr);
                else begin
                    $display("        [ERRO] endereco do write-back incorreto: %h  esperado: 0x0000_2000", mem_req.addr);
                    erros = erros + 1;
                end

                if (mem_req.data[31:0] == 32'hDEAD_BEEF)
                    $display("        [OK] dado do write-back contem DEAD_BEEF na word0");
                else begin
                    $display("        [ERRO] dado do write-back incorreto: word0=%h  esperado: DEAD_BEEF", mem_req.data[31:0]);
                    erros = erros + 1;
                end

                // handshake: confirma recebimento do write-back
                @(posedge clk); #1;
                mem_data.ready = 1;
                @(posedge clk); #1;
                mem_data.ready = 0;

                // fornece novo bloco apos write-back
                wait(dut.rstate == dut.allocate);
                @(posedge clk); #1;
                mem_data.data  = 128'hCCCC_0004_CCCC_0003_CCCC_0002_CCCC_0001;
                mem_data.ready = 1;
                @(posedge clk); #1;
                mem_data.ready = 0;
            end
        join // bloqueia ate AMBAS as threads terminarem

        @(posedge clk); #1;
        $display("        Write-back validado\n");

        // -----------------------------------------------------
        // RESULTADO FINAL
        // -----------------------------------------------------
        $display("=== RESULTADO 7.2 ===");
        if (erros == 0)
            $display("Todos os testes passaram.");
        else
            $display("%0d erro(s) encontrado(s).", erros);

        $finish;
    end

endmodule
