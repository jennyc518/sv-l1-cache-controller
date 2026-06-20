// =============================================================================
// data_array.sv
// 64 sets × 4 ways × 128-bit synchronous SRAM model
//
// 2 write ports (clocked):
//   word_wr — 32-bit CPU word write (used on write hit, and after write-allocate)
//             offset[3:2] selects which quarter of the 128-bit line to update
//   line_wr — full 128-bit line write (used after a FETCH completes)
//
// 2 read ports:
//   rd  — synchronous (1-cycle latency), used in TAG_CHECK so data is ready in DONE
//   wb  — combinational (zero latency), used in WRITEBACK to immediately feed AXI
// =============================================================================

import cache_pkg::*;

module data_array (
    input logic clk,

    // write port 1: 32-bit word write (CPU write hit / write-allocate) 
    input logic                    word_wr_en,
    input logic [INDEX_BITS-1:0]   word_wr_index,
    input logic [WAY_BITS-1:0]     word_wr_way,
    input logic [OFFSET_BITS-1:0]  word_wr_offset, // offset[3:2] selects word
    input logic [DATA_WIDTH-1:0]   word_wr_data,

    // write port 2: full 128-bit line write (after FETCH) 
    input logic                    line_wr_en,
    input logic [INDEX_BITS-1:0]   line_wr_index,
    input logic [WAY_BITS-1:0]     line_wr_way,
    input logic [LINE_WIDTH-1:0]   line_wr_data,

    // read port 1: synchronous, 1-cycle latency (CPU read path) 
    input logic [INDEX_BITS-1:0]   rd_index,
    input logic [WAY_BITS-1:0]     rd_way,
    output logic [LINE_WIDTH-1:0]  rd_line,

    // read port 2: combinational, zero latency (WRITEBACK path) 
    input logic [INDEX_BITS-1:0]   wb_index,
    input logic [WAY_BITS-1:0]     wb_way,
    output logic [LINE_WIDTH-1:0]  wb_line 
);


	logic [LINE_WIDTH-1:0] mem [0:SETS-1][0:WAYS-1];

	// write ports
	always_ff @(posedge clk) begin
		if(word_wr_en) begin
			case (word_wr_offset[3:2])
				2'b00: mem[word_wr_index][word_wr_way][31:0] <= word_wr_data;
				2'b01: mem[word_wr_index][word_wr_way][63:32] <= word_wr_data;
				2'b10: mem[word_wr_index][word_wr_way][95:64] <= word_wr_data;
				2'b11: mem[word_wr_index][word_wr_way][127:96] <= word_wr_data;
			endcase
		end
		if (line_wr_en) begin
			mem[line_wr_index][line_wr_way] <= line_wr_data;
		end
	end

	// read ports
	always_ff @(posedge clk) begin
		rd_line <= mem[rd_index][rd_way];
	end

	assign wb_line = mem[wb_index][wb_way];

endmodule

