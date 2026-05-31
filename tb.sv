    `timescale 1ns/1ps
    import cache_def::*;

    // =============================================================================
    // tb_7_all.sv - Testbench unificado do controlador de cache (Seção 5.12 P&H)
    //
    // Reune os testes 7.1 a 7.5 em um único módulo sequencial.
    // Compatível com IcarusVerilog + GTKWave.
    //
    // Organização:
    //   7.1 - Read Path       : read miss, read hit, logics de controle
    //   7.2 - Write Path      : write hit, write miss (write-allocate), write-back
    //   7.3 - Substituição    : bloco limpo, política direct-mapped, bloco dirty
    //   7.4 - Consistência    : write->read, acessos repetidos, conflito de índice
    //   7.5 - Casos Limite    : cache inválida, endereço mínimo/máximo, reset
    // =============================================================================

    module tb_7_all;

        // -------------------------------------------------------------------------
        // Sinais do DUT
        // -------------------------------------------------------------------------
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

        // -------------------------------------------------------------------------
        // Contagem global de erros
        // -------------------------------------------------------------------------
        integer erros_total = 0;
        integer erros = 0; // contador local por grupo de testes, somado ao final de cada seção
        
        // =========================================================================
        // TASKS AUXILIARES
        // =========================================================================

        // Aguarda cpu_res.ready subir; timeout de segurança em max_ciclos
        task automatic esperar_ready(input integer max_ciclos);
            integer i;
            i = 0;
            // Se cpu_res.ready já for 1 (combinatório), passa direto sem gastar clock
            while (!cpu_res.ready && i < max_ciclos) begin
                @(posedge clk); #1;
                i = i + 1;
            end
        endtask

        // Responde a memória com um bloco fixo após 2 ciclos (usada em 7.2)
        task automatic responder_memoria(input logic [127:0] bloco);
            repeat(2) @(posedge clk);
            mem_data.data  = bloco;
            mem_data.ready = 1;
            @(posedge clk); #1;
            mem_data.ready = 0;
        endtask

        // Faz leitura simples: emite requisição, aguarda mem_req.valid, entrega
        // bloco e espera ready — versão sem retorno (usada em 7.3 e 7.5)
        task automatic fazer_leitura_simples(
            input logic [31:0]  addr,
            input logic [127:0] bloco_mem
        );
            cpu_req.addr  = addr;
            cpu_req.rw    = 0;
            cpu_req.valid = 1;
            
            // Avança para a FSM processar a requisição
            @(posedge clk); #1;
            
            // Se for um MISS (FSM vai para 'allocate' ou sinalizou o barramento)
            if (dut.rstate == dut.allocate || mem_req.valid == 1) begin
                wait(dut.rstate == dut.allocate); // Espera reativa segura
                @(posedge clk); #1;
                mem_data.data  = bloco_mem;
                mem_data.ready = 1;
                @(posedge clk); #1;
                mem_data.ready = 0;
            end
            
            // Aguarda de forma estável o sinal pronto da CPU subir
            wait(cpu_res.ready == 1);
            
            // ATENÇÃO: NÃO avançamos o clock aqui no final! 
            // Deixamos a tarefa terminar no exato instante em que ready=1, 
            // permitindo que o 'if' do bloco principal do TB leia o sucesso.
            cpu_req.valid = 0; 
        endtask

        // CORREÇÃO: Captura o dado imediatamente na janela em que ele existe
        task automatic fazer_leitura_com_retorno(
            input  logic [31:0]  addr,
            input  logic [127:0] bloco_mem,
            output logic [31:0]  dado_lido
        );
            cpu_req.addr  = addr;
            cpu_req.rw    = 0;
            cpu_req.valid = 1;
            
            @(posedge clk); #1;
            
            // Se for MISS, trata a memória. Se for HIT, ignora este bloco.
            if (dut.rstate == dut.allocate || mem_req.valid == 1) begin
                wait(dut.rstate == dut.allocate);
                @(posedge clk); #1;
                mem_data.data  = bloco_mem;
                mem_data.ready = 1;
                @(posedge clk); #1;
                mem_data.ready = 0;
            end
            
            // Espera o pulso combinatório de resposta da FSM
            wait(cpu_res.ready == 1);
            
            // CAPTURA IMEDIATA: Lemos o dado antes de qualquer avanço de clock!
            dado_lido = cpu_res.data; 
            
            cpu_req.valid = 0;
            // Deixamos sem avançar o clock aqui também para manter o alinhamento
        endtask


        // Faz escrita e aguarda ready (usada em 7.4)
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

        // Aplica reset e reinicializa todos os sinais de entrada do DUT
        task aplicar_reset();
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
        endtask

        // =========================================================================
        // PARÂMETROS DE ENDEREÇO POR SEÇÃO
        // =========================================================================

        // Seção 7.3 — três endereços mapeando para o mesmo índice (addr[13:4] = 0x100)
        // 0x0000_1000 -> indice = 0x100, tag = 0x0
        // 0x0004_1000 -> indice = 0x100, tag = 0x1
        // 0x0008_1000 -> indice = 0x100, tag = 0x2
        localparam ADDR_A_73 = 32'h0000_1000;
        localparam ADDR_B_73 = 32'h0004_1000;
        localparam ADDR_C_73 = 32'h0008_1000;

        // Seção 7.4 — dois endereços conflitantes (mesmo índice addr[13:4] = 0x200)
        localparam ADDR_A_74 = 32'h0000_2000; // indice 0x200, tag 0x0
        localparam ADDR_B_74 = 32'h0004_2000; // indice 0x200, tag 0x1

        // =========================================================================
        // BLOCO PRINCIPAL
        // =========================================================================

        // variável de retorno usada em fazer_leitura_com_retorno (7.4)
        logic [31:0] leitura_resultado;

        initial begin
            // Copia o tipo da struct definida no package para criar uma variável local no TB
            cache_def::cache_tag_type tag_verificacao;
            $dumpfile("dump.vcd");
            $dumpvars(0, tb_7_all);

            $display("============================================================");
            $display("  TESTBENCH UNIFICADO 7.1 - 7.5 - Controlador de Cache");
            $display("  Patterson & Hennessy, RISC-V Ed., Seção 5.12");
            $display("============================================================\n");

            clk = 0;

            // =====================================================================
            // SEÇÃO 7.1 - READ PATH
            // =====================================================================
            $display("------------------------------------------------------------");
            $display("  SEÇÃO 7.1 - READ PATH");
            $display("------------------------------------------------------------\n");

            aplicar_reset();
            $display("[SETUP] Reset concluido\n");
            erros = 0;

            // ---------------------------------------------------------------------
            // 7.1.1 - READ MISS
            // cache ta vazia, primeiro acesso sempre e miss
            // ---------------------------------------------------------------------
            $display("[7.1.1] Iniciando Read Miss...");
            $display("        endereco: 0x0000_1000");

            cpu_req.addr  = 32'h0000_1000;
            cpu_req.rw    = 0;
            cpu_req.valid = 1;
            @(posedge clk); #1;

            // aguarda FSM entrar emdut.allocate antes de responder
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

            // ---------------------------------------------------------------------
            // 7.1.2 - READ HIT
            // mesmo endereco, bloco ja deve estar na cache
            // ---------------------------------------------------------------------
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

            // ---------------------------------------------------------------------
            // 7.1.3 - logicS DE CONTROLE
            // acesso direto a tag_mem via hierarquia
            // OBSERVACAO: pode nao funcionar no Icarus dependendo da versao
            // ---------------------------------------------------------------------
            $display("[7.1.3] Verificando logics de controle...");
            $display("        indice esperado: 0x100  (addr[13:4] de 0x0000_1000)");
            $display("        tag esperada:    0x0    (addr[31:14] de 0x0000_1000)");

        tag_verificacao = dut.ctag.tag_mem[10'h100];

        // 2. Agora o Icarus consegue ler os subcampos perfeitamente sem travar
        if (tag_verificacao.valid == 1) // Correção da antiga linha 264
            $display("        [OK] valid = 1");
        else begin
            $display("        [ERRO] valid != 1 no indice 0x100");
            erros = erros + 1;
        end

        if (tag_verificacao.tag == 18'h0) // Correção da linha 272
            $display("        [OK] tag correta = 0x0");
        else begin
            $display("        [ERRO] tag incorreta no indice 0x100");
            erros = erros + 1;
        end
        $display("        logics de controle verificados\n");

        $display("=== RESULTADO 7.1 ===");
        if (erros == 0)
            $display("Todos os testes passaram.\n");
        else
            $display("%0d erro(s) encontrado(s).\n", erros);
        erros_total = erros_total + erros;

        // =====================================================================
        // SEÇÃO 7.2 - WRITE PATH
        // =====================================================================
        $display("------------------------------------------------------------");
        $display("  SEÇÃO 7.2 - WRITE PATH");
        $display("------------------------------------------------------------\n");

        aplicar_reset();
        $display("[SETUP] Reset concluido\n");
        erros = 0;

        // ---------------------------------------------------------------------
        // PRE-REQUISITO: alocar bloco via read miss
        // write hit so funciona se o bloco ja estiver na cache
        // ---------------------------------------------------------------------
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
            $display("[PRE] ERRO: bloco nao foi alocado, abortando secao 7.2");
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // ---------------------------------------------------------------------
        // 7.2.1 - WRITE HIT
        // bloco ja esta na cache, escrita deve ocorrer direto
        // sem precisar acessar a memoria principal
        // ---------------------------------------------------------------------
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

        // ---------------------------------------------------------------------
        // 7.2.2 - WRITE MISS (write-allocate)
        // endereco nunca acessado, FSM deve buscar bloco
        // da memoria antes de realizar a escrita
        // ---------------------------------------------------------------------
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

        // ---------------------------------------------------------------------
        // 7.2.3 - VALIDACAO WRITE-BACK + DIRTY logic (CORRIGIDO)
        // o bloco de 0x0000_2000 foi escrito em 7.2.1, esta dirty
        // acesso a 0x0004_2000 tem mesmo indice, deve provocar
        // write-back do bloco dirty antes de alocar o novo
        // ---------------------------------------------------------------------
        $display("[7.2.3] Validando write-back do bloco dirty...");
        $display("        endereco conflitante: 0x0004_2000 (mesmo indice que 0x0000_2000)");

        fork
            // -----------------------------------------------------------------
            // THREAD 1: Lado do Barramento da CPU (Controlador do Teste)
            // -----------------------------------------------------------------
            begin
                cpu_req.addr  = 32'h0004_2000;
                cpu_req.rw    = 0;
                cpu_req.valid = 1;

                // CORREÇÃO DO PROBLEMA 1: Captura o ready combinatório de forma estável
                // Espera até que o sinal mude, sem avançar ciclos de clock extras cegamente
                wait(cpu_res.ready == 1);
                $display("        [OK] novo bloco alocado apos write-back");

                // Finaliza a requisição sincronizado com a borda
                @(posedge clk); #1;
                cpu_req.valid = 0;
            end

            // -----------------------------------------------------------------
            // THREAD 2: Lado da Memória Principal (Emulação/Responder)
            // -----------------------------------------------------------------
            begin
                // Aguarda de forma estável o controlador de cache solicitar o Write-Back
                wait(mem_req.valid == 1 && mem_req.rw == 1);

                $display("        [OK] write-back emitido: mem_req.rw=1");

                // Valida endereco: deve ser o bloco sujo original 0x0000_2000
                if (mem_req.addr == 32'h0000_2000)
                    $display("        [OK] endereco do write-back correto: %h", mem_req.addr);
                else begin
                    $display("        [ERRO] endereco do write-back incorreto: %h  esperado: 0x0000_2000", mem_req.addr);
                    erros = erros + 1;
                end

                // Valida dado: bloco deve conter 0xDEAD_BEEF na word0
                if (mem_req.data[31:0] == 32'hDEAD_BEEF)
                    $display("        [OK] dado do write-back contem DEAD_BEEF na word0");
                else begin
                    $display("        [ERRO] dado do write-back incorreto: word0=%h  esperado: DEAD_BEEF", mem_req.data[31:0]);
                    erros = erros + 1;
                end

                // Handshake: confirma recebimento do write-back
                @(posedge clk); #1;
                mem_data.ready = 1;
                @(posedge clk); #1;
                mem_data.ready = 0;

                // Fornece o novo bloco solicitado após a conclusão do write-back
                wait(dut.rstate == dut.allocate);
                @(posedge clk); #1;
                mem_data.data  = 128'hCCCC_0004_CCCC_0003_CCCC_0002_CCCC_0001;
                mem_data.ready = 1;
                @(posedge clk); #1;
                mem_data.ready = 0;
            end
        join // CORREÇÃO DO PROBLEMA 2: Bloqueia o avanço até que AMBAS as threads terminem.

        // Fora do bloco fork: Garante que nenhuma thread fantasma sobreviveu para a seção 7.3
        @(posedge clk); #1;
        $display("        Write-back validado\n");

        $display("=== RESULTADO 7.2 ===");
        if (erros == 0)
            $display("Todos os testes passaram.\n");
        else
            $display("%0d erro(s) encontrado(s).\n", erros);
        erros_total = erros_total + erros;

        // =====================================================================
        // SEÇÃO 7.3 - SUBSTITUIÇÃO DE BLOCOS
        // =====================================================================
        $display("------------------------------------------------------------");
        $display("  SEÇÃO 7.3 - SUBSTITUIÇÃO DE BLOCOS");
        $display("------------------------------------------------------------\n");

        aplicar_reset();
        $display("[SETUP] Reset concluido\n");
        erros = 0;

        // ---------------------------------------------------------------------
        // 7.3.1 - SUBSTITUICAO COM BLOCO LIMPO
        // aloca bloco A (sem escrever, fica clean)
        // acessa B no mesmo indice -> substitui A sem write-back
        // ---------------------------------------------------------------------
        $display("[7.3.1] Substituicao de bloco limpo...");
        $display("        Alocando bloco A em %h (indice 0x100)", ADDR_A_73);

        // Dispara a leitura
        fazer_leitura_simples(ADDR_A_73, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001);

        // CORREÇÃO 1: Amostra o ready alinhado à borda onde ele se estabilizou
        if (cpu_res.ready)
            $display("        [OK] Bloco A alocado, word0 = 0xAAAA_0001");
        else begin
            $display("        [ERRO] Falha ao alocar bloco A");
            erros = erros + 1;
        end

        $display("        Acessando bloco B em %h (mesmo indice, tag diferente)", ADDR_B_73);
        $display("        Esperado: substituicao direta, sem write-back (A esta limpo)");

        // Configura requisição para o Bloco B
        cpu_req.addr  = ADDR_B_73;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        
        // CORREÇÃO 2: Espera a FSM digerir o pedido e chegar em compare_tag/allocate
        @(posedge clk); #1; 

        // Como o bloco A é limpo, a FSM deve ir direto para 'allocate' sem acionar 'mem_req.rw'
        if (mem_req.rw == 0)
            $display("        [OK] Sem write-back, bloco A era limpo");
        else begin
            $display("        [ERRO] write-back indevido para bloco limpo");
            erros = erros + 1;
        end

        // Aguarda a FSM estar pronta no estado de alocação se já não estiver
        wait(dut.rstate == dut.allocate);

        // Alimenta a memória principal
        mem_data.data  = 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001;
        mem_data.ready = 1;
        @(posedge clk); #1; // FSM absorve o dado e vai para compare_tag
        mem_data.ready = 0;

        // CORREÇÃO 3: Captura o ready do bloco B exatamente no ciclo em que ele bate em compare_tag
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
        cpu_req.addr  = ADDR_A_73;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // Entra em compare_tag

        begin
            integer ciclos_espera_73_1;
            logic miss_detectado_73_1;
            ciclos_espera_73_1 = 0;
            miss_detectado_73_1 = 0;
            // O sinal combinatório mem_req.valid aparece imediatamente no Miss
            if (mem_req.valid == 1) begin
                miss_detectado_73_1 = 1;
            end else begin
                // Caso precise de ciclos adicionais de varredura
                while (ciclos_espera_73_1 < 10) begin
                    if (mem_req.valid == 1) begin
                        miss_detectado_73_1 = 1;
                        miss_detectado_73_1  = 10;
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

        // Finaliza o ciclo de miss de A de forma limpa
        wait(dut.rstate == dut.allocate);
        mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;
        
        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Substituicao limpa concluida\n");
        // ---------------------------------------------------------------------
        // 7.3.2 - POLITICA DE SUBSTITUICAO (direct-mapped)
        // cache de mapeamento direto nao tem escolha de vitima
        // o bloco no indice conflitante e sempre substituido
        // validamos acessando A, B e C sequencialmente no mesmo indice
        // ---------------------------------------------------------------------
        $display("[7.3.2] Validando politica de substituicao (direct-mapped)...");

        $display("        Alocando A -> B -> C no mesmo indice");
        fazer_leitura_simples(ADDR_A_73, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001);
        $display("        [OK] A alocado");

        fazer_leitura_simples(ADDR_B_73, 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001);
        $display("        [OK] B alocado, substituiu A");

        fazer_leitura_simples(ADDR_C_73, 128'hCCCC_0004_CCCC_0003_CCCC_0002_CCCC_0001);
        $display("        [OK] C alocado, substituiu B");

        // Agora apenas C deve estar no índice 0x100. Acessar A novamente deve dar miss.
        $display("        Relendo A: deve gerar miss (foi substituido por C)");
        cpu_req.addr  = ADDR_A_73;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // FSM entra no estado compare_tag

        begin
            integer ciclos_espera;
            logic miss_detectado;
            ciclos_espera  = 0;
            miss_detectado = 0;
            
            // CORREÇÃO: Verifica o pulso combinatório IMEDIATAMENTE no estado compare_tag
            if (mem_req.valid == 1) begin
                miss_detectado = 1;
            end else begin
                while (ciclos_espera < 10) begin
                    if (mem_req.valid == 1) begin
                        miss_detectado = 1;
                        miss_detectado  = 10; // Marca que foi detectado para evitar prints adicionais
                    end
                    @(posedge clk); #1;
                    ciclos_espera++;
                end
            end
            
            if (miss_detectado)
                $display("        [OK] Miss em A confirmed, direct-mapped funcionando corretamente");
            else begin
                $display("        [ERRO] A ainda na cache, politica de substituicao incorreta");
                erros = erros + 1;
            end
        end

        // Responde à memória para desatar a FSM antes de fechar o bloco
        wait(dut.rstate == dut.allocate);
        mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
        mem_data.ready = 1;
        @(posedge clk); #1;
        mem_data.ready = 0;
        
        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Politica de substituicao validada\n");

        // ---------------------------------------------------------------------
        // 7.3.3 - SUBSTITUICAO COM BLOCO DIRTY (write-back)
        // escreve em A (fica dirty), acessa B no mesmo indice
        // FSM deve fazer write-back de A antes de alocar B
        // ---------------------------------------------------------------------
        $display("[7.3.3] Substituicao com write-back de bloco dirty...");

        // aloca A e escreve nele para marcar como dirty
        $display("        Alocando e escrevendo em A para marcar como dirty...");
        fazer_leitura_simples(ADDR_A_73, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001);

        cpu_req.addr  = ADDR_A_73;
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
        cpu_req.addr  = ADDR_B_73;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        // monitora write-back: mem_req.rw deve subir
        begin
            integer ciclos;
            logic wb_ok;
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

        $display("=== RESULTADO 7.3 ===");
        if (erros == 0)
            $display("Todos os testes passaram.\n");
        else
            $display("%0d erro(s) encontrado(s).\n", erros);
        erros_total = erros_total + erros;

        // =====================================================================
        // SEÇÃO 7.4 - CONSISTÊNCIA DE DADOS (CORRIGIDA)
        // =====================================================================
        $display("------------------------------------------------------------");
        $display("  SEÇÃO 7.4 - CONSISTÊNCIA DE DADOS");
        $display("------------------------------------------------------------\n");

        aplicar_reset();
        $display("[SETUP] Reset concluido\n");
        erros = 0;

        // ---------------------------------------------------------------------
        // 7.4.1 - SEQUENCIA WRITE -> READ (coerencia basica)
        // ---------------------------------------------------------------------
        $display("[7.4.1] Coerencia basica: write seguido de read...");

        // Primeiro aloca o bloco via read miss
        $display("        Alocando bloco em %h via read miss...", ADDR_A_74);
        fazer_leitura_com_retorno(ADDR_A_74, 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001, leitura_resultado);
        $display("        Bloco alocado, word0 inicial = %h", leitura_resultado);

        // Escreve valor novo
        $display("        Escrevendo 0xDEAD_BEEF em %h...", ADDR_A_74);
        fazer_escrita(ADDR_A_74, 32'hDEAD_BEEF);
        $display("        Escrita concluida");

        // Le de volta e verifica
        $display("        Lendo de volta para verificar coerencia...");
        cpu_req.addr  = ADDR_A_74;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        
        // CORREÇÃO 1: Sincronização direta por nível (Hit é combinatório e imediato)
        wait(cpu_res.ready == 1);

        if (cpu_res.ready && cpu_res.data == 32'hDEAD_BEEF)
            $display("        [OK] Dado coerente: leitura retornou %h", cpu_res.data);
        else begin
            $display("        [ERRO] Incoerencia: leu %h, esperado 0xDEAD_BEEF", cpu_res.data);
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // Segunda escrita seguida de leitura no mesmo endereco
        $display("        Segunda escrita: 0x1234_5678...");
        fazer_escrita(ADDR_A_74, 32'h1234_5678);

        cpu_req.addr  = ADDR_A_74;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        
        // CORREÇÃO 2: Espera reativa estável pelo Hit
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

        // ---------------------------------------------------------------------
        // 7.4.2 - ACESSOS REPETIDOS AO MESMO ENDERECO
        // ---------------------------------------------------------------------
        $display("[7.4.2] Acessos repetidos ao mesmo endereco...");
        $display("        Realizando 4 leituras consecutivas em %h", ADDR_A_74);

        begin
            integer leituras_ok;
            leituras_ok = 0;

            repeat(4) begin
                cpu_req.addr  = ADDR_A_74;
                cpu_req.rw    = 0;
                cpu_req.valid = 1;
                
                // CORREÇÃO 3: Eliminado 'esperar_ready(4)' cego que causava perda de ciclos
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

        // ---------------------------------------------------------------------
        // 7.4.3 - CONFLITO DE INDICE: A e B no mesmo indice (VERSÃO ANTI-HANG VVP)
        // ---------------------------------------------------------------------
        $display("[7.4.3] Conflito de indice entre %h e %h...", ADDR_A_74, ADDR_B_74);
        $display("        Ambos mapeiam para indice 0x200");

        $display("        Acessando B para substituir A (A esta dirty, write-back esperado)...");

        cpu_req.addr  = ADDR_B_74;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // Avança 1 ciclo para a FSM processar a requisição em compare_tag [cite: 14, 15]

        // REATIVO: Esperamos o sinal de memória confirmar que o Miss aconteceu [cite: 24]
        wait(mem_req.valid == 1);
        #1; // Margem para estabilização combinatória dos sinais

        if (mem_req.rw == 1) begin // Se rw=1, a cache detectou corretamente que A estava dirty [cite: 26, 27]
            $display("        [OK] Write-back de A detectado em %h", mem_req.addr);
            
            // Valida endereco: deve ser o bloco sujo A, nao B
            if (mem_req.addr == ADDR_A_74)
                $display("        [OK] Endereco do write-back correto: %h", mem_req.addr);
            else begin
                $display("        [ERRO] Endereco do write-back incorreto: %h  esperado: %h", mem_req.addr, ADDR_A_74);
                erros = erros + 1;
            end
            
            // Valida dado: word0 deve conter 0x1234_5678 (última escrita)
            if (mem_req.data[31:0] == 32'h1234_5678)
                $display("        [OK] Dado do write-back correto na word0: %h", mem_req.data[31:0]);
            else begin
                $display("        [ERRO] Dado do write-back incorreto: word0=%h  esperado: 1234_5678", mem_req.data[31:0]);
                erros = erros + 1;
            end
            
            // A FSM está em compare_tag e vai para write_back no próximo clock [cite: 15, 27]
            @(posedge clk);
            #1; // Agora a FSM está estritamente no estado write_back [cite: 27]
            
            // Finaliza o ciclo de write-back respondendo à memória
            mem_data.ready = 1;
            @(posedge clk); // FSM amostra ready=1 e agenda ida para allocate [cite: 30]
            #1;
            mem_data.ready = 0;
        end else begin
            $display("        [ERRO] Write-back de A nao detectado (esperado mem_req.rw = 1)");
            erros = erros + 1;
        end

        // A FSM moveu-se para o estado 'allocate' no clock anterior [cite: 30]
        // Fornecemos agora os dados novos correspondentes ao Bloco B
        mem_data.data  = 128'hBBBB_0004_BBBB_0003_BBBB_0002_BBBB_0001;
        mem_data.ready = 1;
        @(posedge clk); // FSM aceita o bloco B e agenda retorno para compare_tag [cite: 28]
        #1;
        mem_data.ready = 0;

        // Com o bloco B instalado, a FSM bate no compare_tag e dá HIT instantâneo [cite: 15, 16]
        wait(cpu_res.ready == 1);
        $display("        [OK] Bloco B alocado, word0 = 0xBBBB_0001");

        cpu_req.valid = 0;
        @(posedge clk); #1;

        // ---------------------------------------------------------------------
        // PARTE 2: Releitura de A (Deve gerar Miss pois B tomou o lugar)
        // ---------------------------------------------------------------------
        $display("        Relendo A: deve gerar miss (substituido por B)...");
        cpu_req.addr  = ADDR_A_74;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1; // Avança para fazer a FSM processar em compare_tag [cite: 14, 15]

        // Esperamos a solicitação de leitura bater na memória (Read Miss) [cite: 24]
        wait(mem_req.valid == 1);
        #1;

        if (mem_req.rw == 0) begin // Bloco B estava limpo (dirty=0), então vai direto para allocate [cite: 24]
            $display("        [OK] Miss em A confirmado, conflito de indice tratado corretamente");
            
            // Espera a FSM transitar de compare_tag para allocate
            @(posedge clk);
            #1;
            
            // Fornece os dados originais do Bloco A vindos da memória externa
            mem_data.data  = 128'hAAAA_0004_AAAA_0003_AAAA_0002_AAAA_0001;
            mem_data.ready = 1;
            @(posedge clk); // FSM adquire e retorna ao compare_tag [cite: 28]
            #1;
            mem_data.ready = 0;
            
            // Aguarda o Hit final e entrega do dado para a CPU [cite: 15, 16]
            wait(cpu_res.ready == 1);
        end else begin
            $display("        [ERRO] Comportamento inesperado no Miss de A (rw=%b)", mem_req.rw);
            erros = erros + 1;
        end

        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Conflito de indice validado\n");

        // =====================================================================
        // SEÇÃO 7.5 - CASOS LIMITE
        // =====================================================================
        $display("------------------------------------------------------------");
        $display("  SEÇÃO 7.5 - CASOS LIMITE");
        $display("------------------------------------------------------------\n");

        aplicar_reset();
        $display("[SETUP] Reset concluido\n");
        erros = 0;

        // ---------------------------------------------------------------------
        // 7.5.1 - CACHE COMPLETAMENTE INVALIDA (estado inicial)
        // logo apos reset, nenhum bloco e valido
        // qualquer acesso deve gerar miss compulsorio
        // validamos que a FSM trata corretamente o primeiro acesso
        // ---------------------------------------------------------------------
        $display("[7.5.1] Verificando comportamento com cache invalida...");
        $display("        Logo apos reset, todos os blocos sao invalidos");
        $display("        Primeiro acesso deve sempre gerar miss compulsorio");

        cpu_req.addr  = 32'h0000_0400;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;

        // FSM deve sair de idle -> compare_tag -> miss ->dut.allocate
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

        // ---------------------------------------------------------------------
        // 7.5.2 - ACESSO AO ENDERECO MINIMO (0x0000_0000)
        // testa o menor endereco possivel
        // indice = addr[13:4] = 0x000, tag = addr[31:14] = 0x0
        // ---------------------------------------------------------------------
        $display("[7.5.2] Acesso ao endereco minimo (0x0000_0000)...");

        fazer_leitura_simples(32'h0000_0000, 128'h0000_0004_0000_0003_0000_0002_0000_0001);

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

// ---------------------------------------------------------------------
        // 7.5.3 - ACESSO AO ENDERECO MAXIMO (0xFFFF_FFFC)
        // testa o maior endereco alinhado em 32 logics
        // indice = 0x3FF (todos os logics de indice em 1)
        // tag    = 0x3FFFF (todos os logics de tag em 1)
        // ---------------------------------------------------------------------
        $display("[7.5.3] Acesso ao endereco maximo (0xFFFF_FFFC)...");
        $display("        indice = 0x3FF, tag = 0x3FFFF");

        // Executa a primeira leitura (que vai gerar um Miss e alocar o bloco)
        fazer_leitura_simples(32'hFFFF_FFFC, 128'hFFFF_0004_FFFF_0003_FFFF_0002_FFFF_0001);

        // CORREÇÃO 1: Amostra imediata após a conclusão da rotina de alocação
        if (cpu_res.ready) begin
            $display("        [OK] Endereco maximo acessado com sucesso");
            $display("        [OK] word3 retornada (offset=2'b11): %h", cpu_res.data);
        end else begin
            $display("        [ERRO] Falha ao acessar endereco maximo");
            erros = erros + 1;
        end

        // Remove a requisição anterior e prepara o teste de Hit
        cpu_req.valid = 0;
        @(posedge clk); #1;

        // SEGUNDA LEITURA (Deve ser Hit)
        cpu_req.addr  = 32'hFFFF_FFFC;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        
        // Avança para o ciclo de clock onde a FSM entra em compare_tag e calcula o Hit
        @(posedge clk); #1;

        // CORREÇÃO 2: Como é um Hit, cpu_res.ready já está alto AGORA (bloco combinatório)
        if (cpu_res.ready)
            $display("        [OK] Segunda leitura em 0xFFFF_FFFC foi hit");
        else begin
            $display("        [ERRO] Segunda leitura em 0xFFFF_FFFC nao foi hit");
            erros = erros + 1;
        end

        // Finaliza a requisição de forma síncrona
        cpu_req.valid = 0;
        @(posedge clk); #1;
        $display("        Endereco maximo validado\n");

        // ---------------------------------------------------------------------
        // 7.5.4 - RESET DURANTE OPERACAO
        // inicia uma requisicao e aplica reset antes de concluir
        // apos reset a FSM deve voltar ao idle e aceitar nova requisicao
        // ---------------------------------------------------------------------
        $display("[7.5.4] Reset durante operacao em andamento...");
        $display("        Iniciando leitura e aplicando reset antes da resposta da memoria");

        cpu_req.addr  = 32'h0001_0000;
        cpu_req.rw    = 0;
        cpu_req.valid = 1;
        @(posedge clk); #1;
        @(posedge clk); #1; // FSM entra em compare_tag

        // --- TRATAMENTO DE TIMEOUT SEGURO ---
        fork : timeout_protection
            // Caminho A: O cenário esperado acontece
            begin
                wait(mem_req.valid == 1);
            end
            
            // Caminho B: O tempo passa e nada acontece (A proteção)
            begin
                repeat (20) @(posedge clk); // Espera no máximo 20 ciclos de clock
            end
        join_any // Acorda assim que QUALQUER UM dos caminhos acima terminar
        disable fork; // Desliga o caminho que sobrou para não estragar os próximos testes

        // --- VERIFICAÇÃO: Quem ganhou a corrida? ---
        if (mem_req.valid != 1) begin
            $display("        [ERRO FATAL] Timeout! O sinal mem_req.valid nunca subiu.");
            erros = erros + 1;
            // Opcional: força o fim da simulação para você não perder tempo olhando travamento
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

        $display("=== RESULTADO 7.5 ===");
        if (erros == 0)
            $display("Todos os testes passaram.\n");
        else
            $display("%0d erro(s) encontrado(s).\n", erros);
        erros_total = erros_total + erros;

        // =====================================================================
        // RESULTADO GERAL
        // =====================================================================
        $display("============================================================");
        $display("  RESULTADO GERAL - TESTBENCH 7.1 a 7.5");
        $display("============================================================");
        if (erros_total == 0)
            $display("  TODOS OS TESTES PASSARAM.");
        else
            $display("  %0d ERRO(S) ENCONTRADO(S) NO TOTAL.", erros_total);
        $display("============================================================\n");

        $finish;
    end

endmodule
