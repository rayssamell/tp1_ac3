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
