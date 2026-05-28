import cache_def::*;

module tb_dm_cache;
    // Testbench signals
    bit clk;
    bit rst;
    cpu_req_type cpu_req;
    mem_data_type mem_data;
    
    mem_req_type mem_req;
    cpu_result_type cpu_res;

    // Instantiate the Cache FSM (Design Under Test)
    dm_cache_fsm dut (
        .clk(clk),
        .rst(rst),
        .cpu_req(cpu_req),
        .mem_data(mem_data),
        .mem_req(mem_req),
        .cpu_res(cpu_res)
    );

    // Clock generator (50MHz / 20ns period)
    always #10 clk = ~clk;

    // Simulate Main Memory Behavior
    always @(posedge clk) begin
        if (mem_req.valid) begin
            // Simulate a 3-cycle memory latency delay
            repeat (3) @(posedge clk);
            mem_data.ready <= 1'b1;
            if (mem_req.rw == 1'b0) begin
                // On a memory read request, return a dummy pattern
                mem_data.data <= {32'hDEADBEEF, 32'hCAFEBABE, 32'hAAAA5555, 32'h12345678};
            end
        end else begin
            mem_data.ready <= 1'b0;
        end
    end

    // Stimulus block
    initial begin
        // Setup waveform dumping for GTKWave
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_dm_cache);

        // Initialize signals & Reset system
        clk = 0;
        rst = 1;
        cpu_req = '{0, 0, 0, 0};
        mem_data = '{0, 0};
        #40;
        rst = 0;
        #20;

        // --- TEST 1: Read Compulsory Miss ---
        $display("[TIME: %0t] Test 1: Reading Addr 32'h0000_1000 (Expect: MISS -> Allocate)", $time);
        cpu_req.addr  = 32'h0000_1000; 
        cpu_req.rw    = 1'b0; // Read
        cpu_req.valid = 1'b1;
        
        // Wait until cache declares data is ready
        while (!cpu_res.ready) @(posedge clk);
        $display("[TIME: %0t] Test 1 Success! Data Read: %h", $time, cpu_res.data);
        cpu_req.valid = 1'b0;
        #40;

        // --- TEST 2: Read Hit ---
        $display("[TIME: %0t] Test 2: Reading Addr 32'h0000_1000 again (Expect: HIT)", $time);
        cpu_req.addr  = 32'h0000_1000;
        cpu_req.rw    = 1'b0;
        cpu_req.valid = 1'b1;
        
        @(posedge clk);
        if (cpu_res.ready) 
            $display("[TIME: %0t] Test 2 Success! Cache Hit instantly. Data: %h", $time, cpu_res.data);
        cpu_req.valid = 1'b0;
        #40;

        // --- TEST 3: Write Hit (Dirtying the Line) ---
        $display("[TIME: %0t] Test 3: Writing to Addr 32'h0000_1000 (Expect: HIT -> Line marked Dirty)", $time);
        cpu_req.addr  = 32'h0000_1000;
        cpu_req.data  = 32'h5555_5555;
        cpu_req.rw    = 1'b1; // Write
        cpu_req.valid = 1'b1;
        
        while (!cpu_res.ready) @(posedge clk);
        cpu_req.valid = 1'b0;
        #40;

        // --- TEST 4: Conflict Miss with a Dirty Line (Write Back) ---
        $display("[TIME: %0t] Test 4: Reading Addr 32'h0004_1000 (Same index, diff tag. Expect: Conflict MISS -> Write_Back -> Allocate)", $time);
        cpu_req.addr  = 32'h0004_1000; // Maps to the same cache index
        cpu_req.rw    = 1'b0;
        cpu_req.valid = 1'b1;

        while (!cpu_res.ready) @(posedge clk);
        $display("[TIME: %0t] Test 4 Success! Data Read from new block: %h", $time, cpu_res.data);
        cpu_req.valid = 1'b0;
        
        #100;
        $finish;
    end

endmodule
