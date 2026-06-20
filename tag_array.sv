// =============================================================================
// tag_array.sv
// stores valid/dirty/tag metadata for all 64 sets × 4 ways
//
//   Port 1 (wr_*)    — full line update after a FETCH completes
//                      sets valid=1, dirty=0, tag=new address tag
//   Port 2 (dirty_*) — set dirty=1 only, used on a write hit in DONE 
// =============================================================================

import cache_pkg::*;

module tag_array (
    input logic clk,
    input logic rst_n,

    // read port (combinational) 
    input logic [INDEX_BITS-1:0] rd_index,
    output cache_meta_t rd_meta [0:WAYS-1],

    // write port 1 (after FETCH) 
    input logic                    wr_en,
    input logic [INDEX_BITS-1:0]   wr_index,
    input logic [WAY_BITS-1:0]     wr_way,
    input cache_meta_t             wr_meta,

    // write port 2 (write hit in DONE) 
    input logic                    dirty_en,
    input logic [INDEX_BITS-1:0]   dirty_index,
    input logic [WAY_BITS-1:0]     dirty_way
);

	cache_meta_t mem [0:SETS-1][0:WAYS-1];

	always_comb begin
	for(int i = 0; i < WAYS; i++) begin
		if (wr_en && (wr_index == rd_index) && (WAY_BITS'(i) == wr_way))
			rd_meta[i] = wr_meta;
		else
			rd_meta[i] = mem[rd_index][i];
		end
	end

	
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			for(int i = 0; i < SETS; i++) begin
				for(int j = 0; j < WAYS; j++) mem[i][j] <= '0;
			end
		end else begin
		if (wr_en) mem[wr_index][wr_way] <= wr_meta; // port 1
			if (dirty_en) mem[dirty_index][dirty_way].dirty <= 1'b1; // port 2
		end
	end

endmodule

