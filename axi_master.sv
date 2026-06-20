// =============================================================================
// axi_master.sv
//
// FSM:
//
//   AXI_IDLE
//     wait for fetch_req or wb_req from cache_ctrl.
//     fetch_req takes priority if both arrive simultaneously (shouldn't happen).
//
//   AXI_AR  (address read)
//     drive ARVALID + ARADDR.
//     wait for ARREADY from memory — one-cycle handshake.
//     move to AXI_R once memory accepts the address.
//
//   AXI_R   (read data)
//     drive RREADY.
//     wait for RVALID from memory (after MEM_LATENCY cycles).
//     latch RDATA, assert fetch_done for one cycle, return to AXI_IDLE.
//
//   AXI_AW_W  (address write + write data, simultaneous)
//     drive AWVALID + AWADDR + WVALID + WDATA + WSTRB all at once.
//     AXI4 allows AW and W to be driven simultaneously — saves one cycle.
//     use two flags (aw_done_r, w_done_r) to track each channel independently
//     because memory may accept AW before W or vice versa.
//     move to AXI_B once BOTH channels are accepted.
//
//   AXI_B   (write response)
//     drive BREADY.
//     wait for BVALID from memory.
//     assert wb_done for one cycle, return to AXI_IDLE.
//
// =============================================================================

module axi_master
    import cache_pkg::*;
(
    input  logic                      clk,
    input  logic                      rst_n,

    // cache_ctrl interface
    input  logic                      fetch_req,
    input  logic [ADDR_WIDTH-1:0]     fetch_addr,
    output logic                      fetch_done,
    output logic [LINE_WIDTH-1:0]     fetch_rdata,

    input  logic                      wb_req,
    input  logic [ADDR_WIDTH-1:0]     wb_addr,
    input  logic [LINE_WIDTH-1:0]     wb_wdata,
    output logic                      wb_done,

    // AR channel
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    output logic [AXI_ADDR_W-1:0]     m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,

    // R channel
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,
    input  logic [LINE_WIDTH-1:0]     m_axi_rdata,
    input  logic                      m_axi_rlast,
    input  logic [1:0]                m_axi_rresp,

    // AW channel
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [AXI_ADDR_W-1:0]     m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,

    // W channel
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    output logic [LINE_WIDTH-1:0]     m_axi_wdata,
    output logic [LINE_WIDTH/8-1:0]   m_axi_wstrb,
    output logic                      m_axi_wlast,

    // B channel
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    input  logic [1:0]                m_axi_bresp
);

    typedef enum logic [2:0] {
        AXI_IDLE  = 3'd0,
        AXI_AR    = 3'd1,
        AXI_R     = 3'd2,
        AXI_AW_W  = 3'd3,
        AXI_B     = 3'd4
    } axi_state_t;

    axi_state_t state, next_state;

    logic [ADDR_WIDTH-1:0]  addr_r;
    logic [LINE_WIDTH-1:0]  wdata_r;

    logic aw_done_r;
    logic w_done_r;

    // state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= AXI_IDLE;
        else        state <= next_state;
    end

    // address and data latches — captured in IDLE so cache_ctrl is free after handoff
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_r  <= '0;
            wdata_r <= '0;
        end
        else if (state == AXI_IDLE) begin
            if      (fetch_req) addr_r  <= fetch_addr;
            else if (wb_req)  begin
                addr_r  <= wb_addr;
                wdata_r <= wb_wdata;
            end
        end
    end

    // AW/W completion flags — AW and W are independent channels,
    // memory may accept them in different cycles
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done_r <= 1'b0;
            w_done_r  <= 1'b0;
        end
        else if (state == AXI_IDLE) begin
            aw_done_r <= 1'b0;
            w_done_r  <= 1'b0;
        end
        else if (state == AXI_AW_W) begin
            if (m_axi_awvalid && m_axi_awready) aw_done_r <= 1'b1;
            if (m_axi_wvalid  && m_axi_wready)  w_done_r  <= 1'b1;
        end
    end

    // next-state and output logic
    always_comb begin
        next_state    = state;

        fetch_done    = 1'b0;
        fetch_rdata   = '0;
        wb_done       = 1'b0;

        m_axi_arvalid = 1'b0;
        m_axi_araddr  = '0;
        m_axi_arlen   = 8'd0;
        m_axi_arsize  = 3'b100;  // 16 bytes per beat
        m_axi_arburst = 2'b01;   // INCR

        m_axi_rready  = 1'b0;

        m_axi_awvalid = 1'b0;
        m_axi_awaddr  = '0;
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = 3'b100;
        m_axi_awburst = 2'b01;

        m_axi_wvalid  = 1'b0;
        m_axi_wdata   = '0;
        m_axi_wstrb   = {(LINE_WIDTH/8){1'b1}};  // all 16 bytes
        m_axi_wlast   = 1'b1;   // always 1 — only one beat

        m_axi_bready  = 1'b0;

        case (state)

            AXI_IDLE: begin
                if      (fetch_req) next_state = AXI_AR;
                else if (wb_req)    next_state = AXI_AW_W;
            end

            AXI_AR: begin
                m_axi_arvalid = 1'b1;
                m_axi_araddr  = addr_r;
                m_axi_arlen   = 8'd0;
                m_axi_arsize  = 3'b100;
                m_axi_arburst = 2'b01;
                if (m_axi_arready) next_state = AXI_R;
            end

            AXI_R: begin
                m_axi_rready = 1'b1;
                if (m_axi_rvalid) begin
                    fetch_rdata = m_axi_rdata;
                    fetch_done  = 1'b1;
                    next_state  = AXI_IDLE;
                end
            end

            AXI_AW_W: begin
                if (!aw_done_r) begin
                    m_axi_awvalid = 1'b1;
                    m_axi_awaddr  = addr_r;
                    m_axi_awlen   = 8'd0;
                    m_axi_awsize  = 3'b100;
                    m_axi_awburst = 2'b01;
                end
                if (!w_done_r) begin
                    m_axi_wvalid = 1'b1;
                    m_axi_wdata  = wdata_r;
                    m_axi_wstrb  = {(LINE_WIDTH/8){1'b1}};
                    m_axi_wlast  = 1'b1;
                end
                if ((aw_done_r || (m_axi_awvalid && m_axi_awready)) &&
                    (w_done_r  || (m_axi_wvalid  && m_axi_wready)))
                    next_state = AXI_B;
            end

            AXI_B: begin
                m_axi_bready = 1'b1;
                if (m_axi_bvalid) begin
                    wb_done    = 1'b1;
                    next_state = AXI_IDLE;
                end
            end

            default: next_state = AXI_IDLE;

        endcase
    end

endmodule

