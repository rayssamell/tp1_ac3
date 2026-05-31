# <img src="https://media.tenor.com/QC3oCl9WdzoAAAAj/heart-crystal-heart.gif" width="50"> TP01 - Arquitetura de Computadores III

Repositório dedicado ao tp01 da disciplina arquitetura de computadores III da PUC Minas.

## Alunos integrantes da equipe

* Ana Clara Lonczynski
* Bruno Rafael Santos Oliveira
* Izadora Galarza Alves
* Matheus Eduardo Campos Soares
* Rayssa Mell de Souza Silva
* Thiago Pereira de Oliveira

## Professores responsáveis

* Lucas Bragança da Silva

---
## 💻 Sobre o Projeto

Este repositório contém o desenvolvimento e a validação de um Controlador de Cache L1 de Dados com mapeamento direto, baseado no modelo descrito no livro Computer Organization and Design: The Hardware/Software Interface (RISC-V Edition).

O objetivo principal do projeto foi implementar e corrigir uma Máquina de Estados Finitos (FSM) em SystemVerilog capaz de gerenciar com eficiência as requisições da CPU, o tratamento de falhas (Cache Hits e Misses) e a consistência de dados com a Memória Principal.

## 🛠️ Especificações Técnicas

O objetivo principal é mitigar o gargalo de desempenho entre o processador (RISC-V) e a memória principal. O controlador gerencia uma cache com as seguintes características:
* **Tipo:** Cache L1 de Dados.
* **Mapeamento:** Direto.
* **Capacidade:** 1024 blocos.
* **Tamanho da Linha/Bloco:** 128 bits (16 bytes / 4 palavras de 32 bits).
* **Políticas de Escrita:** *Write-Back* (com bit *dirty*) e *Write-Allocate*.

## 🏗️ Estrutura do Hardware

O circuito foi modularizado nos seguintes arquivos principais:
* `cache_def`: Definições de tipos, structs e constantes (mapeando os 18 bits mais significativos para *Tag* e 10 bits para índice).
* `dm_cache_tag`: Memória assíncrona que armazena os metadados de controle (*Tag*, bit de validade e bit *dirty*).
* `dm_cache_data`: Memória de 1024 posições que armazena os blocos de dados de 128 bits vindos da memória principal.
* `dm_cache_fsm`: O núcleo do controlador. Instancia as memórias e gerencia a comunicação CPU-Memória através de uma **Máquina de Estados Finitos (FSM)** composta por 4 estados: `IDLE`, `COMPARE_TAG`, `ALLOCATE` e `WRITE_BACK`.

## 🛠️ Correções e Ajustes de Engenharia

Durante o desenvolvimento, o grupo identificou e corrigiu erros de sintaxe/compatibilidade e bugs lógicos presentes no código oficial do livro:

1. **Compatibilidade (Icarus Verilog):** Substituição do tipo `bit` por `logic`, troca de `always_comb` por `always @(*)` e ajuste na sintaxe de inicialização de *structs* (`'0`).
2. **Correção de Sinais Fantasmas:** Correção da ausência do valor padrão para o sinal `v_mem_req.valid`, evitando requisições falsas contínuas à memória após o primeiro *miss*.
3. **Sincronismo no Miss Limpo:** Ajuste no tempo do sinal de validação no estado de `COMPARE_TAG` para evitar atrasos de ciclo.
4. **Persistência no Write-Back:** Correção de bugs em que os sinais `valid` e `rw` caíam antes do sinal `ready` da memória, além de evitar a sobrescrita precoce da *tag* antes da conclusão do *write-back*.

## 🧪 Resultados e Validação

A validação foi feita através do testbench unificado `tb_7_all`. Utilizando o **GTKWave**, foram comprovados com **zero erros**:
* O correto funcionamento de *Read/Write Hits* e *Misses*.
* O funcionamento da política *Write-Back* salvando blocos alterados na memória externa antes de substituições.
* Robustez em casos limite (extremos da memória) e comportamento seguro do reset assíncrono durante requisições pendentes.

---
## 💻 Dependências

As dependências necessárias para rodas o projeto são *systemverilog* e *gtkwave*.

---
## 🐧 Instalação no Ubuntu / Linux

```bash
sudo apt update
sudo apt install iverilog gtkwave
```

Verificar:

```bash
iverilog -V
gtkwave --version
```

---

## ▶️ Compilar e Executar

```bash
iverilog -g2012 -o cache_sim cache_def.sv dm_cache_data.sv dm_cache_tag.sv dm_cache_fsm.sv tb*.sv
vvp cache_sim
```

Waveform:

```bash
gtkwave dump.vcd
```
