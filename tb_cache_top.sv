import cache_pkg::*;


module tb_cache_top;

// clk/reset
    localparam real CLK_PERIOD = 10.0;
    logic clk   = 1'b0;
    logic rst_n;
    always #(CLK_PERIOD/2.0) clk = ~clk;

// CPU signals 
    logic                    cpu_valid;
    logic                    cpu_we;
    logic [ADDR_WIDTH-1:0]   cpu_addr;
    logic [DATA_WIDTH-1:0]   cpu_wdata;
    logic [DATA_WIDTH-1:0]   cpu_rdata;
    logic                    cpu_stall;

// AXI4 signals

    // AR channel
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;
    logic [AXI_ADDR_W-1:0]  m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;

    // R channel
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;
    logic [LINE_WIDTH-1:0] m_axi_rdata;
    logic                    m_axi_rlast;
    logic [1:0]              m_axi_rresp;

    // AW channel
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;
    logic [AXI_ADDR_W-1:0]  m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;

    // W channel
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;
    logic [LINE_WIDTH-1:0] m_axi_wdata;
    logic [LINE_WIDTH/8-1:0] m_axi_wstrb;
    logic                    m_axi_wlast;

    // B channel
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;
    logic [1:0]              m_axi_bresp;

// performance counters
    logic [31:0] perf_hits;
    logic [31:0] perf_misses;
    logic [31:0] perf_writebacks;
    logic [31:0] perf_evictions;

// DUT
    cache_top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cpu_valid        (cpu_valid),
        .cpu_we           (cpu_we),
        .cpu_addr         (cpu_addr),
        .cpu_wdata        (cpu_wdata),
        .cpu_rdata        (cpu_rdata),
        .cpu_stall        (cpu_stall),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),
        .m_axi_bresp      (m_axi_bresp),
        .perf_hits        (perf_hits),
        .perf_misses      (perf_misses),
        .perf_writebacks  (perf_writebacks),
        .perf_evictions   (perf_evictions)
    );

// memory model
    axi_mem_model u_mem (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axi_arvalid    (m_axi_arvalid),
        .s_axi_arready    (m_axi_arready),
        .s_axi_araddr     (m_axi_araddr),
        .s_axi_arlen      (m_axi_arlen),
        .s_axi_arsize     (m_axi_arsize),
        .s_axi_arburst    (m_axi_arburst),
        .s_axi_rvalid     (m_axi_rvalid),
        .s_axi_rready     (m_axi_rready),
        .s_axi_rdata      (m_axi_rdata),
        .s_axi_rlast      (m_axi_rlast),
        .s_axi_rresp      (m_axi_rresp),
        .s_axi_awvalid    (m_axi_awvalid),
        .s_axi_awready    (m_axi_awready),
        .s_axi_awaddr     (m_axi_awaddr),
        .s_axi_awlen      (m_axi_awlen),
        .s_axi_awsize     (m_axi_awsize),
        .s_axi_awburst    (m_axi_awburst),
        .s_axi_wvalid     (m_axi_wvalid),
        .s_axi_wready     (m_axi_wready),
        .s_axi_wdata      (m_axi_wdata),
        .s_axi_wstrb      (m_axi_wstrb),
        .s_axi_wlast      (m_axi_wlast),
        .s_axi_bvalid     (m_axi_bvalid),
        .s_axi_bready     (m_axi_bready),
        .s_axi_bresp      (m_axi_bresp)
    );

    // reference model
    logic [31:0] ref_mem [logic [31:0]];

    // test counters
    integer tests_run;
    integer tests_passed;
    integer tests_failed;


    // tasks

    task automatic wait_clk(input integer n);
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic do_read(
        input  logic [31:0] addr,
        output logic [31:0] rdata
    );
        @(posedge clk); #1;
        cpu_valid = 1'b1;
        cpu_we    = 1'b0;
        cpu_addr  = addr;
        cpu_wdata = 32'd0;
        @(posedge clk); #1;
        while (cpu_stall) begin
            @(posedge clk); #1;
        end
		cpu_valid = 1'b0;
		#2;
		rdata     = cpu_rdata;
        @(posedge clk); #1;
    endtask

    task automatic do_write(
        input logic [31:0] addr,
        input logic [31:0] wdata
    );
        @(posedge clk); #1;
        cpu_valid = 1'b1;
        cpu_we    = 1'b1;
        cpu_addr  = addr;
        cpu_wdata = wdata;
        @(posedge clk); #1;
        while (cpu_stall) begin
            @(posedge clk); #1;
        end
        cpu_valid     = 1'b0;
        ref_mem[addr] = wdata;
        u_mem.backdoor_write(addr, wdata);
        @(posedge clk); #1;
    endtask

    task automatic check_read(
        input logic [31:0] addr,
        input string       test_name
    );
        logic [31:0] got;
        logic [31:0] exp;
        do_read(addr, got);
        if (ref_mem.exists(addr))
            exp = ref_mem[addr];
        else begin
            u_mem.backdoor_read(addr, exp);
            ref_mem[addr] = exp;
        end
        tests_run++;
        if (got === exp) begin
            tests_passed++;
            $display("[PASS] %-32s  addr=0x%08h  exp=0x%08h  got=0x%08h",
                     test_name, addr, exp, got);
        end else begin
            tests_failed++;
            $display("[FAIL] %-32s  addr=0x%08h  exp=0x%08h  got=0x%08h  <-- MISMATCH",
                     test_name, addr, exp, got);
        end
    endtask

    task automatic check_write_read(
        input logic [31:0] addr,
        input logic [31:0] wdata,
        input string       test_name
    );
        logic [31:0] got;
        do_write(addr, wdata);
        do_read(addr, got);
        tests_run++;
        if (got === wdata) begin
            tests_passed++;
            $display("[PASS] %-32s  addr=0x%08h  wrote=0x%08h  readback=0x%08h",
                     test_name, addr, wdata, got);
        end else begin
            tests_failed++;
            $display("[FAIL] %-32s  addr=0x%08h  wrote=0x%08h  readback=0x%08h  <-- MISMATCH",
                     test_name, addr, wdata, got);
        end
    endtask


    // main test sequence

    initial begin
        tests_run    = 0;
        tests_passed = 0;
        tests_failed = 0;

        void'($system("mkdir -p sim"));
        $shm_open("sim/cache_waves.shm");
        $shm_probe(tb_cache_top, "AS");

        cpu_valid = 1'b0;
        cpu_we    = 1'b0;
        cpu_addr  = 32'd0;
        cpu_wdata = 32'd0;

        rst_n = 1'b0;
        u_mem.init_mem();
        @(posedge clk); @(posedge clk);
        rst_n = 1'b1;
        wait_clk(2);

        $display("\n========================================================");
        $display("  4-Way SA Cache + AXI4 128-bit — Testbench Start");
        $display("  Config: %0d sets  %0d ways  %0d-byte lines  %0d-cycle mem",
                 SETS, WAYS, LINE_BYTES, MEM_LATENCY);
        $display("========================================================\n");

        // T01: cold read miss
        $display("--- T01: Cold read miss ---");
        check_read(32'h0000_0000, "T01 cold miss 0x0000");
        check_read(32'h0000_1000, "T01 cold miss 0x1000");
        check_read(32'h0000_2000, "T01 cold miss 0x2000");

        // T02: read hit after miss
        $display("\n--- T02: Read hit ---");
        check_read(32'h0000_0000, "T02 hit 0x0000");
        check_read(32'h0000_1000, "T02 hit 0x1000");

        // T03: spatial locality
        $display("\n--- T03: Spatial locality ---");
        check_read(32'h0000_0004, "T03 spatial +4");
        check_read(32'h0000_0008, "T03 spatial +8");
        check_read(32'h0000_000C, "T03 spatial +12");

        // T04: write hit
        $display("\n--- T04: Write hit ---");
        check_write_read(32'h0000_0000, 32'hDEAD_BEEF, "T04 write-hit 0x0000");
        check_write_read(32'h0000_0004, 32'hCAFE_BABE, "T04 write-hit +4");

        // T05: write miss (write-allocate)
        $display("\n--- T05: Write miss ---");
        check_write_read(32'h0000_3000, 32'hAABB_CCDD, "T05 wr-miss 0x3000");
        check_write_read(32'h0000_4000, 32'h1234_5678, "T05 wr-miss 0x4000");

        // T06: dirty eviction
        $display("\n--- T06: Dirty eviction ---");
        begin
            logic [31:0] base;
            logic [31:0] stride;
            integer      ww;
            logic [31:0] dummy;
            base   = 32'h0002_0000;
            stride = 32'd1024;
            for (ww = 0; ww < 4; ww = ww + 1)
                do_write(base + ww*stride, 32'hF000_0000 | ww);
            check_read(base + 4*stride, "T06 5th forces dirty evict");
            check_read(base,            "T06 re-read evicted dirty line");
        end

        // T07: fill all 4 ways
        $display("\n--- T07: Fill 4 ways ---");
        begin
            logic [31:0] base;
            logic [31:0] stride;
            logic [31:0] vals[4];
            integer      ww;
            base      = 32'h0004_0000;
            stride    = 32'd1024;
            vals[0]   = 32'hAAAA_0000;
            vals[1]   = 32'hBBBB_1111;
            vals[2]   = 32'hCCCC_2222;
            vals[3]   = 32'hDDDD_3333;
            for (ww = 0; ww < 4; ww = ww + 1)
                do_write(base + ww*stride, vals[ww]);
            for (ww = 0; ww < 4; ww = ww + 1)
                check_read(base + ww*stride,
                           $sformatf("T07 way %0d readback", ww));
        end

        // T08: pLRU replacement
        $display("\n--- T08: pLRU replacement ---");
        begin
            logic [31:0] base;
            logic [31:0] stride;
            logic [31:0] dummy;
            integer      ww;
            base   = 32'h0006_0000;
            stride = 32'd1024;
            for (ww = 0; ww < 4; ww = ww + 1)
                do_read(base + ww*stride, dummy);
            do_write(base, 32'h5555_AAAA);
            do_read(base + 4*stride, dummy);
            check_read(base, "T08 pLRU way0 survived eviction");
        end

        // T09: read-after-write coherence
        $display("\n--- T09: Coherence ---");
        check_write_read(32'h0008_0000, 32'hFEED_FACE, "T09 coherence 1");
        check_write_read(32'h0008_0004, 32'h0BAD_C0DE, "T09 coherence 2");
        check_write_read(32'h0008_0008, 32'hC001_D00D, "T09 coherence 3");

        // T10: back-to-back requests
        $display("\n--- T10: Back-to-back ---");
        begin
            logic [31:0] base;
            integer      ii;
            base = 32'h000A_0000;
            for (ii = 0; ii < 8; ii = ii + 1)
                check_write_read(base + ii*4,
                                 32'hBEEF_0000 | ii,
                                 $sformatf("T10 back-to-back %0d", ii));
        end

        // T11: constrained random (5000 ops)
        $display("\n--- T11: Constrained random (5000 ops) ---");
        begin
            integer rand_pass;
            integer rand_fail;
            logic [31:0] raddr;
            logic [31:0] rwdata;
            logic [31:0] rgot;
            logic [31:0] rexp;
            integer      op;
            rand_pass = 0;
            rand_fail = 0;
            for (op = 0; op < 5000; op = op + 1) begin
                raddr  = {22'h000_010, 8'($urandom_range(0, 255)), 2'b00};
                rwdata = $urandom;
                if ($urandom_range(0, 1)) begin
                    do_write(raddr, rwdata);
                end else begin
                    do_read(raddr, rgot);
                    if (ref_mem.exists(raddr))
                        rexp = ref_mem[raddr];
                    else begin
                        u_mem.backdoor_read(raddr, rexp);
                        ref_mem[raddr] = rexp;
                    end
                    tests_run++;
                    if (rgot === rexp) begin
                        rand_pass++;
                        tests_passed++;
                    end else begin
                        rand_fail++;
                        tests_failed++;
                        $display("[FAIL] T11 op=%0d  addr=0x%08h  exp=0x%08h  got=0x%08h",
                                 op, raddr, rexp, rgot);
                    end
                end
            end
            $display("[T11] Random done: %0d checks  %0d pass  %0d fail",
                     rand_pass + rand_fail, rand_pass, rand_fail);
        end

        // T12: performance report
        wait_clk(5);
        $display("\n========================================");
        $display("  Cache Performance Report");
        $display("========================================");
        $display("  Hits        : %0d", perf_hits);
        $display("  Misses      : %0d", perf_misses);
        if ((perf_hits + perf_misses) > 0)
            $display("  Hit rate    : %0.1f%%",
                     100.0 * perf_hits / (perf_hits + perf_misses));
        $display("  Writebacks  : %0d", perf_writebacks);
        $display("  Evictions   : %0d", perf_evictions);
        $display("  AMAT (est.) : %0.1f cycles",
                 1.0 + (1.0*perf_misses / (perf_hits + perf_misses + 1))
                       * MEM_LATENCY);
        $display("========================================\n");

        // summary
        $display("========================================================");
        $display("  TEST SUMMARY");
        $display("  Total : %0d   Passed : %0d   Failed : %0d",
                 tests_run, tests_passed, tests_failed);
        if (tests_failed == 0)
            $display("  Result : *** ALL TESTS PASSED ***");
        else
            $display("  Result : *** %0d FAILURES ***", tests_failed);
        $display("========================================================\n");

        $shm_close();
        $finish;
    end

    // timeout watchdog
    initial begin
        #5_000_000;
        $display("\n[ERROR] Simulation TIMEOUT at %0t — possible deadlock!", $time);
        $display("        Check: cpu_stall stuck? AXI handshake deadlock? FSM loop?");
        $shm_close();
        $finish;
    end

endmodule : tb_cache_top

