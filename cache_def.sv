package cache_def;
    // data structures for cache tag & data
    parameter int TAGMSB = 31; //tag msb
    parameter int TAGLSB = 14; //tag lsb

    //data structure for cache tag
    typedef struct packed {
        logic valid; //valid logic
        logic dirty; //dirty logic
        logic [TAGMSB:TAGLSB]tag; //tag logics
    } cache_tag_type;

    //data structure for cache memory request
    typedef struct packed{
        logic [9:0]index; //10-logic index
        logic we; //write enable
    } cache_req_type;

    //128-logic cache line data
    typedef logic [127:0] cache_data_type;

    // data structures for CPU<->Cache controller interface
    // CPU request (CPU->cache controller)
    typedef struct packed {
        logic [31:0]addr; //32-logic request addr
        logic [31:0]data; //32-logic request data (used when write)
        logic rw; //request type : 0 = read, 1 = write
        logic valid; //request is valid
    } cpu_req_type;

    // Cache result (cache controller->cpu)
    typedef struct packed {
        logic [31:0]data; //32-logic data
        logic ready; //result is ready
    } cpu_result_type;

    //----------------------------------------------------------------------
    // data structures for cache controller<->memory interface
    // memory request (cache controller->memory)
    typedef struct packed {
        logic [31:0]addr; //request byte addr
        logic [127:0]data; //128-logic request data (used when write)
        logic rw; //request type : 0 = read, 1 = write
        logic valid; //request is valid
    } mem_req_type;

    // memory controller response (memory -> cache controller)
    typedef struct packed {
        cache_data_type data; //128-logic read back data
        logic ready; //data is ready
    } mem_data_type;
endpackage