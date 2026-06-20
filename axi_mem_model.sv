import cache_pkg::*;

localparam int LINE_B = LINE_WIDTH / 8;

module axi_mem_model #(
    parameter int MEM_SIZE = 1048576,
    parameter int LATENCY  = MEM_LATENCY
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // AW channel
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [7:0]              s_axi_awlen,
    input  logic [2:0]              s_axi_awsize,
    input  logic [1:0]              s_axi_awburst,

    // W channel
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,
    input  logic [LINE_WIDTH-1:0]   s_axi_wdata,
    input  logic [LINE_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                    s_axi_wlast,

    // B channel
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,
    output logic [1:0]              s_axi_bresp,

    // AR channel
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [7:0]              s_axi_arlen,
    input  logic [2:0]              s_axi_arsize,
    input  logic [1:0]              s_axi_arburst,

    // R channel
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,
    output logic [LINE_WIDTH-1:0]   s_axi_rdata,
    output logic                    s_axi_rlast,
    output logic [1:0]              s_axi_rresp
);

    logic [7:0] mem [0:MEM_SIZE-1];

    // read FSM
    localparam logic [1:0] RD_IDLE = 2'd0, RD_WAIT = 2'd1, RD_RESP = 2'd2;

    logic [1:0]             rd_state;
    logic [AXI_ADDR_W-1:0]  rd_addr_r;
    logic [7:0]             rd_cnt;
    logic [LINE_WIDTH-1:0]  rd_data_r;
    integer                 rd_b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rlast   <= 1'b0;
            s_axi_rresp   <= 2'b00;
            rd_cnt        <= 8'd0;
            rd_data_r     <= '0;
        end
        else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_addr_r     <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        rd_cnt        <= 8'd0;
                        rd_state      <= RD_WAIT;
                    end
                end
                RD_WAIT: begin
                    if (rd_cnt == LATENCY - 1) begin
                        for (rd_b = 0; rd_b < LINE_B; rd_b = rd_b + 1)
                            rd_data_r[rd_b*8 +: 8] <=
                                mem[(rd_addr_r & ~(LINE_B-1)) + rd_b];
                        rd_state <= RD_RESP;
                    end
                    else
                        rd_cnt <= rd_cnt + 8'd1;
                end
                RD_RESP: begin
                    s_axi_rvalid <= 1'b1;
                    s_axi_rdata  <= rd_data_r;
                    s_axi_rlast  <= 1'b1;
                    s_axi_rresp  <= 2'b00;
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid  <= 1'b0;
                        s_axi_rlast   <= 1'b0;
                        s_axi_arready <= 1'b1;
                        rd_state      <= RD_IDLE;
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // write FSM 
    localparam logic [1:0] WR_IDLE = 2'd0, WR_WAIT = 2'd1, WR_RESP = 2'd2;

    logic [1:0]               wr_state;
    logic [AXI_ADDR_W-1:0]   wr_addr_r;
    logic [LINE_WIDTH-1:0]    wr_data_r;
    logic [LINE_WIDTH/8-1:0]  wr_strb_r;
    logic [7:0]               wr_cnt;
    logic                     aw_ok;
    logic                     w_ok;
    integer                   wr_b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_ok         <= 1'b0;
            w_ok          <= 1'b0;
            wr_cnt        <= 8'd0;
            wr_data_r     <= '0;
            wr_strb_r     <= '0;
        end
        else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_r     <= s_axi_awaddr;
                        aw_ok         <= 1'b1;
                        s_axi_awready <= 1'b0;
                    end
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_r    <= s_axi_wdata;
                        wr_strb_r    <= s_axi_wstrb;
                        w_ok         <= 1'b1;
                        s_axi_wready <= 1'b0;
                    end
                    if ((aw_ok || (s_axi_awvalid && s_axi_awready)) &&
                        (w_ok  || (s_axi_wvalid  && s_axi_wready))) begin
                        aw_ok    <= 1'b0;
                        w_ok     <= 1'b0;
                        wr_cnt   <= 8'd0;
                        wr_state <= WR_WAIT;
                    end
                end
                WR_WAIT: begin
                    if (wr_cnt == LATENCY - 1) begin
                        for (wr_b = 0; wr_b < LINE_B; wr_b = wr_b + 1)
                            if (wr_strb_r[wr_b])
                                mem[(wr_addr_r & ~(LINE_B-1)) + wr_b]
                                    <= wr_data_r[wr_b*8 +: 8];
                        wr_state <= WR_RESP;
                    end
                    else
                        wr_cnt <= wr_cnt + 8'd1;
                end
                WR_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // backdoor tasks
    task automatic init_mem();
        integer ii;
        logic [31:0] vv;
        for (ii = 0; ii < MEM_SIZE; ii = ii + 4) begin
            vv        = ii >> 2;
            mem[ii]   = vv[7:0];
            mem[ii+1] = vv[15:8];
            mem[ii+2] = vv[23:16];
            mem[ii+3] = vv[31:24];
        end
    endtask

    task automatic backdoor_write(input logic [31:0] addr, input logic [31:0] data);
        mem[addr]   = data[7:0];
        mem[addr+1] = data[15:8];
        mem[addr+2] = data[23:16];
        mem[addr+3] = data[31:24];
    endtask

    task automatic backdoor_read(input logic [31:0] addr, output logic [31:0] data);
        data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
    endtask

endmodule : axi_mem_model
