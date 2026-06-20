// =============================================================================
// cache_top.sv
// =============================================================================

import cache_pkg::*;


module cache_top (
    input  logic                      clk,
    input  logic                      rst_n,

    // CPU interface 
    input  logic                      cpu_valid,
    input  logic                      cpu_we,
    input  logic [ADDR_WIDTH-1:0]     cpu_addr,
    input  logic [DATA_WIDTH-1:0]     cpu_wdata,
    output logic [DATA_WIDTH-1:0]     cpu_rdata,
    output logic                      cpu_stall,

    // AXI4 master interface 

    // AR channel
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr,
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
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr,
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
    input  logic [1:0]                m_axi_bresp,

    // performance counters
    output logic [31:0]               perf_hits,
    output logic [31:0]               perf_misses,
    output logic [31:0]               perf_writebacks,
    output logic [31:0]               perf_evictions
);


    // internal wires


    // tag_array
    logic [INDEX_BITS-1:0]   ta_rd_index;
    cache_meta_t             ta_rd_meta [0:WAYS-1];
    logic                    ta_wr_en;
    logic [INDEX_BITS-1:0]   ta_wr_index;
    logic [WAY_BITS-1:0]     ta_wr_way;
    cache_meta_t             ta_wr_meta;
    logic                    ta_dirty_en;
    logic [INDEX_BITS-1:0]   ta_dirty_index;
    logic [WAY_BITS-1:0]     ta_dirty_way;

    // data_array
    logic                    da_word_wr_en;
    logic [INDEX_BITS-1:0]   da_word_wr_index;
    logic [WAY_BITS-1:0]     da_word_wr_way;
    logic [OFFSET_BITS-1:0]  da_word_wr_offset;
    logic [DATA_WIDTH-1:0]   da_word_wr_data;
    logic                    da_line_wr_en;
    logic [INDEX_BITS-1:0]   da_line_wr_index;
    logic [WAY_BITS-1:0]     da_line_wr_way;
    logic [LINE_WIDTH-1:0]   da_line_wr_data;
    logic [INDEX_BITS-1:0]   da_rd_index;
    logic [WAY_BITS-1:0]     da_rd_way;
    logic [LINE_WIDTH-1:0]   da_rd_line;
    logic [INDEX_BITS-1:0]   da_wb_index;
    logic [WAY_BITS-1:0]     da_wb_way;
    logic [LINE_WIDTH-1:0]   da_wb_line;

    // plru
    logic [INDEX_BITS-1:0]   plru_query_set;
    logic [WAY_BITS-1:0]     plru_victim_way;
    logic                    plru_update_en;
    logic [INDEX_BITS-1:0]   plru_update_set;
    logic [WAY_BITS-1:0]     plru_update_way;

    // axi_master
    logic                    axi_fetch_req;
    logic [ADDR_WIDTH-1:0]   axi_fetch_addr;
    logic                    axi_fetch_done;
    logic [LINE_WIDTH-1:0]   axi_fetch_rdata;
    logic                    axi_wb_req;
    logic [ADDR_WIDTH-1:0]   axi_wb_addr;
    logic [LINE_WIDTH-1:0]   axi_wb_wdata;
    logic                    axi_wb_done;


    // instantiations


    cache_ctrl u_ctrl (
        .clk                (clk),
        .rst_n              (rst_n),
        .cpu_valid          (cpu_valid),
        .cpu_we             (cpu_we),
        .cpu_addr           (cpu_addr),
        .cpu_wdata          (cpu_wdata),
        .cpu_rdata          (cpu_rdata),
        .cpu_stall          (cpu_stall),
        .ta_rd_index        (ta_rd_index),
        .ta_rd_meta         (ta_rd_meta),
        .ta_wr_en           (ta_wr_en),
        .ta_wr_index        (ta_wr_index),
        .ta_wr_way          (ta_wr_way),
        .ta_wr_meta         (ta_wr_meta),
        .ta_dirty_en        (ta_dirty_en),
        .ta_dirty_index     (ta_dirty_index),
        .ta_dirty_way       (ta_dirty_way),
        .da_word_wr_en      (da_word_wr_en),
        .da_word_wr_index   (da_word_wr_index),
        .da_word_wr_way     (da_word_wr_way),
        .da_word_wr_offset  (da_word_wr_offset),
        .da_word_wr_data    (da_word_wr_data),
        .da_line_wr_en      (da_line_wr_en),
        .da_line_wr_index   (da_line_wr_index),
        .da_line_wr_way     (da_line_wr_way),
        .da_line_wr_data    (da_line_wr_data),
        .da_rd_index        (da_rd_index),
        .da_rd_way          (da_rd_way),
        .da_rd_line         (da_rd_line),
        .da_wb_index        (da_wb_index),
        .da_wb_way          (da_wb_way),
        .da_wb_line         (da_wb_line),
        .plru_query_set     (plru_query_set),
        .plru_victim_way    (plru_victim_way),
        .plru_update_en     (plru_update_en),
        .plru_update_set    (plru_update_set),
        .plru_update_way    (plru_update_way),
        .axi_fetch_req      (axi_fetch_req),
        .axi_fetch_addr     (axi_fetch_addr),
        .axi_fetch_done     (axi_fetch_done),
        .axi_fetch_rdata    (axi_fetch_rdata),
        .axi_wb_req         (axi_wb_req),
        .axi_wb_addr        (axi_wb_addr),
        .axi_wb_wdata       (axi_wb_wdata),
        .axi_wb_done        (axi_wb_done),
        .perf_hits          (perf_hits),
        .perf_misses        (perf_misses),
        .perf_writebacks    (perf_writebacks),
        .perf_evictions     (perf_evictions)
    );

    tag_array u_tag (
        .clk                (clk),
        .rst_n              (rst_n),
        .rd_index           (ta_rd_index),
        .rd_meta            (ta_rd_meta),
        .wr_en              (ta_wr_en),
        .wr_index           (ta_wr_index),
        .wr_way             (ta_wr_way),
        .wr_meta            (ta_wr_meta),
        .dirty_en           (ta_dirty_en),
        .dirty_index        (ta_dirty_index),
        .dirty_way          (ta_dirty_way)
    );

    data_array u_data (
        .clk                (clk),
        .word_wr_en         (da_word_wr_en),
        .word_wr_index      (da_word_wr_index),
        .word_wr_way        (da_word_wr_way),
        .word_wr_offset     (da_word_wr_offset),
        .word_wr_data       (da_word_wr_data),
        .line_wr_en         (da_line_wr_en),
        .line_wr_index      (da_line_wr_index),
        .line_wr_way        (da_line_wr_way),
        .line_wr_data       (da_line_wr_data),
        .rd_index           (da_rd_index),
        .rd_way             (da_rd_way),
        .rd_line            (da_rd_line),
        .wb_index           (da_wb_index),
        .wb_way             (da_wb_way),
        .wb_line            (da_wb_line)
    );

    plru u_plru (
        .clk                (clk),
        .rst_n              (rst_n),
        .query_set          (plru_query_set),
        .victim_way         (plru_victim_way),
        .update_en          (plru_update_en),
        .update_set         (plru_update_set),
        .update_way         (plru_update_way)
    );

    axi_master u_axi (
        .clk                (clk),
        .rst_n              (rst_n),
        .fetch_req          (axi_fetch_req),
        .fetch_addr         (axi_fetch_addr),
        .fetch_done         (axi_fetch_done),
        .fetch_rdata        (axi_fetch_rdata),
        .wb_req             (axi_wb_req),
        .wb_addr            (axi_wb_addr),
        .wb_wdata           (axi_wb_wdata),
        .wb_done            (axi_wb_done),
        .m_axi_arvalid      (m_axi_arvalid),
        .m_axi_arready      (m_axi_arready),
        .m_axi_araddr       (m_axi_araddr),
        .m_axi_arlen        (m_axi_arlen),
        .m_axi_arsize       (m_axi_arsize),
        .m_axi_arburst      (m_axi_arburst),
        .m_axi_rvalid       (m_axi_rvalid),
        .m_axi_rready       (m_axi_rready),
        .m_axi_rdata        (m_axi_rdata),
        .m_axi_rlast        (m_axi_rlast),
        .m_axi_rresp        (m_axi_rresp),
        .m_axi_awvalid      (m_axi_awvalid),
        .m_axi_awready      (m_axi_awready),
        .m_axi_awaddr       (m_axi_awaddr),
        .m_axi_awlen        (m_axi_awlen),
        .m_axi_awsize       (m_axi_awsize),
        .m_axi_awburst      (m_axi_awburst),
        .m_axi_wvalid       (m_axi_wvalid),
        .m_axi_wready       (m_axi_wready),
        .m_axi_wdata        (m_axi_wdata),
        .m_axi_wstrb        (m_axi_wstrb),
        .m_axi_wlast        (m_axi_wlast),
        .m_axi_bvalid       (m_axi_bvalid),
        .m_axi_bready       (m_axi_bready),
        .m_axi_bresp        (m_axi_bresp)
    );

endmodule
