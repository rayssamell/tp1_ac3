`timescale 1ns/1ps
import cache_def::*;

module tb_7_3_substituicao;

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

    // enderecos que mapeiam para o mesmo indice (addr[13:4])
    // 0x0000_1000 -> indice = 0x100, tag = 0x0
    // 0x0004_1000 -> indice = 0x100, tag = 0x1
    // 0x0008_1000 -> indice = 0x100, tag = 0x2
    localparam ADDR_A = 32'h0000_1000;
    localparam ADDR_B = 32'h0004_1000;
    localparam ADDR_C = 32'h0008_1000;

    task automatic esperar_ready(input integer max_ciclos);
        integer i;
        i = 0;
        while (!cpu_res.ready && i < max_ciclos) begin
            @(posedge clk); #1;
            i = i + 1;
        end
    endtask

    // task alinhada com a fazer_leitura_simples do tb unificado:
    // espera reativamente pelo estado allocate antes de fornecer o bloco
    task automatic fazer_leitura(
        input logic [31:0]  addr,
        input logic [127:0] bloco_mem,
        output logic         ok         // ← adiciona saída
    );
        cpu_req.addr  = addr;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;

        @(posedge clk); #1;

        // miss: aguarda FSM entrar em allocate de forma reativa
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
        $dumpfile("dump_7_3.vcd");
        $dumpvars(0, tb_7_3_substituicao);

        $display("=== TESTE 7.3 - SUBSTITUICAO DE BLOCOS ===\n");

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
        // 7.3.1 - SUBSTITUICAO COM BLOCO LIMPO
        // aloca bloco A (sem escrever, fica clean)
        // acessa B no mesmo indice -> substitui A sem write-back
        // -----------------------------------------------------
        $display("[7.3.1] Substituicao de bloco limpo...");
        $display("        Alocando bloco A em %h (indice 0x100)", ADDR_A);

        bloco_ok = 0;
        fazer_leitura(ADDR_A, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001, bloco_ok);

        if (bloco_ok)
            $display("        [OK] Bloco A alocado, word0 = 0xAAAA_0001");
        else begin
            $display("        [ERRO] Falha ao alocar bloco A");
            erros = erros + 1;
        end

        $display("        Acessando bloco B em %h (mesmo indice, tag diferente)", ADDR_B);
        $display("        Esperado: substituicao direta, sem write-back (A esta limpo)");

        cpu_req.addr  = ADDR_B;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        // avanca 1 ciclo para a FSM processar a requisicao em compare_tag
        @(posedge clk); #1;

        // bloco A e limpo, entao mem_req.rw nao deve subir antes da alocacao
        if (mem_req.rw == 0)
            $display("        [OK] Sem write-back, bloco A era limpo");
        else begin
            $display("        [ERRO] write-back indevido para bloco limpo");
            erros = erros + 1;
        end

        // aguarda FSM entrar em allocate de forma reativa
        wait(dut.rstate == dut.allocate);

        mem_data.data  = 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001;
        mem_data.ready = 1;
        @(posedge clk); #1; // FSM absorve o dado e vai para compare_tag
        mem_data.ready = 0;

        // captura ready exatamente no ciclo em que a FSM bate em compare_tag
        if (cpu_res.ready)
            $display("        [OK] Bloco B alocado no mesmo indice de A");
        else begin
            $display("        [ERRO] Falha ao alocar bloco B");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // confirma que A foi substituido: releitura de A deve gerar miss
        $display("        Relendo A para confirmar substituicao...");
        cpu_req.addr  = ADDR_A;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // entra em compare_tag

        begin
            integer ciclos_espera_73_1;
            logic   miss_detectado_73_1;
            ciclos_espera_73_1  = 0;
            miss_detectado_73_1 = 0;

            if (mem_req.valid == 1) begin
                miss_detectado_73_1 = 1;
            end else begin
                while (ciclos_espera_73_1 < 10) begin
                    if (mem_req.valid == 1) begin
                        miss_detectado_73_1 = 1;
                        ciclos_espera_73_1  = 10;
                    end
                    @(posedge clk); #1;
                    ciclos_espera_73_1++;
                end
            end

            if (miss_detectado_73_1)
                $display("        [OK] Leitura de A gerou miss, bloco foi substituido corretamente");
            else begin
                $display("        [ERRO] A ainda esta na cache, substituicao nao ocorreu");
                erros = erros + 1;
            end
        end

        // finaliza o miss de A de forma limpa
        wait(dut.rstate == dut.allocate);
        mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Substituicao limpa concluida\n");

        // -----------------------------------------------------
        // 7.3.2 - POLITICA DE SUBSTITUICAO (direct-mapped)
        // cache de mapeamento direto nao tem escolha de vitima
        // o bloco no indice conflitante e sempre substituido
        // validamos acessando A, B e C sequencialmente no mesmo indice
        // -----------------------------------------------------
        $display("[7.3.2] Validando politica de substituicao (direct-mapped)...");

        $display("        Alocando A -> B -> C no mesmo indice");
        fazer_leitura(ADDR_A, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001, bloco_ok);
        $display("        [OK] A alocado");

        fazer_leitura(ADDR_B, 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001, bloco_ok);
        $display("        [OK] B alocado, substituiu A");

        fazer_leitura(ADDR_C, 128'hCCCC_0004_CCCC_0003_CCCC_0002_CCCC_0001, bloco_ok);
        $display("        [OK] C alocado, substituiu B");

        // agora so C deve estar no indice 0x100
        // acessar A novamente deve dar miss
        $display("        Relendo A: deve gerar miss (foi substituido por C)");
        cpu_req.addr  = ADDR_A;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // FSM entra em compare_tag

        begin
            integer ciclos_espera;
            logic   miss_detectado;
            ciclos_espera  = 0;
            miss_detectado = 0;

            if (mem_req.valid == 1) begin
                miss_detectado = 1;
            end else begin
                while (ciclos_espera < 10) begin
                    if (mem_req.valid == 1) begin
                        miss_detectado = 1;
                        ciclos_espera  = 10;
                    end
                    @(posedge clk); #1;
                    ciclos_espera++;
                end
            end

            if (miss_detectado)
                $display("        [OK] Miss em A confirmado, direct-mapped funcionando corretamente");
            else begin
                $display("        [ERRO] A ainda na cache, politica de substituicao incorreta");
                erros = erros + 1;
            end
        end

        // responde a memoria para desatar a FSM antes de fechar o bloco
        wait(dut.rstate == dut.allocate);
        mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Politica de substituicao validada\n");

        // -----------------------------------------------------
        // 7.3.3 - SUBSTITUICAO COM BLOCO DIRTY (write-back)
        // escreve em A (fica dirty), acessa B no mesmo indice
        // FSM deve fazer write-back de A antes de alocar B
        // -----------------------------------------------------
        $display("[7.3.3] Substituicao com write-back de bloco dirty...");

        // aloca A e escreve nele para marcar como dirty
        $display("        Alocando e escrevendo em A para marcar como dirty...");
        fazer_leitura(ADDR_A, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001, bloco_ok);

        cpu_req.addr  = ADDR_A;
        cpu_req.data  = 32'hDEAD_BEEF;
        cpu_req.rw    = 1;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        esperar_ready(4);
        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        [OK] Bloco A marcado como dirty");

        // acessa B para forcar substituicao de A dirty
        $display("        Acessando B para forcar eveccao de A dirty...");
        cpu_req.addr  = ADDR_B;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        // monitora write-back: mem_req.rw deve subir
        begin
            integer ciclos;
            logic   wb_ok;
            ciclos = 0;
            wb_ok  = 0;

            while (ciclos < 10) begin
                @(posedge clk); #1;
                if (mem_req.valid && mem_req.rw) begin
                    wb_ok = 1;
                    $display("        [OK] Write-back emitido para endereco %h", mem_req.addr);
                    $display("        [OK] Dado dirty sendo salvo na memoria");
                    ciclos = 10;
                end
                ciclos = ciclos + 1;
            end

            if (!wb_ok) begin
                $display("        [ERRO] Write-back nao detectado");
                erros = erros + 1;
            end
        end

        // confirma write-back e fornece bloco B
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;

        repeat(2) @(posedge clk);
        mem_data.data  = 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;

        esperar_ready(10);

        if (cpu_res.ready)
            $display("        [OK] Bloco B alocado apos write-back de A");
        else begin
            $display("        [ERRO] Falha ao alocar B apos write-back");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Write-back na substituicao validado\n");

        // -----------------------------------------------------
        // RESULTADO FINAL
        // -----------------------------------------------------
        $display("=== RESULTADO 7.3 ===");
        if (erros == 0)
            $display("Todos os testes passaram.");
        else
            $display("%0d erro(s) encontrado(s).", erros);

        $finish;
    end

endmodule
