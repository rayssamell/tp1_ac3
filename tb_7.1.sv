`timescale 1ns/1ps
import cache_def::*;

module tb_7_1_read;

    // sinais do DUT
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

    // conta erros pra mostrar no final
    integer erros = 0;

    // espera o ready subir, timeout de segurança
    task automatic esperar_ready(input integer max_ciclos);
        integer i;
        i = 0;
        while (!cpu_res.ready && i < max_ciclos) begin
            @(posedge clk); #1;
            i = i + 1;
        end
    endtask

    initial begin
        // variável local para leitura de tag (mesmo padrão do tb unificado)
        cache_def::cache_tag_type tag_verificacao;

        $dumpfile("dump_7_1.vcd");
        $dumpvars(0, tb_7_1_read);

        $display("=== TESTE 7.1 - READ PATH ===\n");

        // inicializa tudo zerado
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
        $display("[SETUP] Reset concluido, sistema pronto\n");

        // -----------------------------------------------------
        // 7.1.1 - READ MISS
        // cache ta vazia, primeiro acesso sempre e miss
        // -----------------------------------------------------
        $display("[7.1.1] Iniciando Read Miss...");
        $display("        endereco: 0x0000_1000");

        cpu_req.addr  = 32'h0000_1000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        // aguarda FSM entrar em allocate antes de responder
        wait(dut.rstate == dut.allocate);
        @(posedge clk); #1;

        // memoria responde com bloco conhecido
        // word0=0xAAAA_0001, word1=0xAAAA_0002, word2=0xAAAA_0003, word3=0xAAAA_0004
        mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;

        esperar_ready(10);

        // addr[3:2] = 2'b00, entao deve retornar word0 = 0xAAAA_0001
        if (cpu_res.ready == 1)
            $display("        [OK] cpu_res.ready subiu");
        else begin
            $display("        [ERRO] cpu_res.ready nao subiu - miss nao foi tratado");
            erros = erros + 1;
        end

        if (cpu_res.data == 32'hAAAA_0001)
            $display("        [OK] dado retornado correto");
        else
            $display("        [INFO] dado=%h  (esperado word0=0xAAAA_0001 para offset 2'b00)", cpu_res.data);

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Read Miss concluido\n");

        // -----------------------------------------------------
        // 7.1.2 - READ HIT
        // mesmo endereco, bloco ja deve estar na cache
        // -----------------------------------------------------
        $display("[7.1.2] Iniciando Read Hit...");
        $display("        mesmo endereco: 0x0000_1000");

        cpu_req.addr  = 32'h0000_1000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        // hit nao deve precisar de resposta da memoria
        // espera poucos ciclos, se ready subir sem mem_data e hit confirmado
        esperar_ready(4);

        if (cpu_res.ready == 1) begin
            $display("        [OK] cpu_res.ready subiu sem resposta da memoria = HIT confirmado");
            if (cpu_res.data == 32'hAAAA_0001)
                $display("        [OK] dado correto: %h", cpu_res.data);
            else begin
                $display("        [ERRO] dado incorreto: %h  esperado: 0xAAAA_0001", cpu_res.data);
                erros = erros + 1;
            end
        end else begin
            $display("        [ERRO] ready nao subiu - esperado hit, pode ter dado miss");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Read Hit concluido\n");

        // -----------------------------------------------------
        // 7.1.3 - BITS DE CONTROLE
        // acesso direto a tag_mem via hierarquia
        // OBSERVACAO: pode nao funcionar no Icarus dependendo da versao
        // -----------------------------------------------------
        $display("[7.1.3] Verificando bits de controle...");
        $display("        indice esperado: 0x100  (addr[13:4] de 0x0000_1000)");
        $display("        tag esperada:    0x0    (addr[31:14] de 0x0000_1000)");

        // leitura via variavel intermediaria (compativel com Icarus)
        tag_verificacao = dut.ctag.tag_mem[10'h100];

        if (tag_verificacao.valid == 1)
            $display("        [OK] valid = 1");
        else begin
            $display("        [ERRO] valid != 1 no indice 0x100");
            erros = erros + 1;
        end

        if (tag_verificacao.tag == 18'h0)
            $display("        [OK] tag correta = 0x0");
        else begin
            $display("        [ERRO] tag incorreta: %h", tag_verificacao.tag);
            erros = erros + 1;
        end

        $display("        Bits de controle verificados\n");

        // -----------------------------------------------------
        // RESULTADO FINAL
        // -----------------------------------------------------
        $display("=== RESULTADO 7.1 ===");
        if (erros == 0)
            $display("Todos os testes passaram.");
        else
            $display("%0d erro(s) encontrado(s).", erros);

        $finish;
    end

endmodule
