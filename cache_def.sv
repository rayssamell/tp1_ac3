// Pacote com tipos e constantes usados por todos os módulos da cache
package cache_def;

  // Endereço de 32 bits: [31:14] = tag (18 bits), [13:4] = índice (10 bits),
  //                      [3:2] = offset de palavra, [1:0] = offset de byte
  parameter int TAGMSB = 31;
  parameter int TAGLSB = 14;

  // Entrada da tag memory: valid, dirty e o próprio campo de tag
  typedef struct packed {
    bit         valid;
    bit         dirty;
    bit [TAGMSB:TAGLSB] tag;
  } cache_tag_type;

  // Comando enviado às memórias internas (tag ou data): índice + write enable
  typedef struct packed {
    bit [9:0] index;
    bit       we;
  } cache_req_type;

  // Linha de cache: 4 palavras de 32 bits = 128 bits
  typedef bit [127:0] cache_data_type;

  // Requisição do processador para o controlador
  typedef struct packed {
    bit [31:0] addr;
    bit [31:0] data;  // usado apenas em writes
    bit        rw;    // 0 = leitura, 1 = escrita
    bit        valid;
  } cpu_req_type;

  // Resposta do controlador para o processador
  typedef struct packed {
    bit [31:0] data;
    bit        ready; // 1 quando o dado está disponível
  } cpu_result_type;

  // Requisição do controlador para a memória principal
  typedef struct packed {
    bit [31:0]  addr;
    bit [127:0] data; // linha inteira (128 bits) para write-back
    bit         rw;   // 0 = leitura, 1 = escrita
    bit         valid;
  } mem_req_type;

  // Resposta da memória principal para o controlador
  typedef struct packed {
    cache_data_type data;
    bit             ready;
  } mem_data_type;

endpackage
