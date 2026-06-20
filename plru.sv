// =============================================================================
// plru.sv
// pseudo-LRU — 3-bit binary tree per set
//
// point away from most recently used way, leads to the victim
//
//              bit[2]
//             /      \
//         bit[1]    bit[0]
//         /    \    /    \
//        W0    W1  W2    W3
//
// victim selection:
//   bit[2]=0 -> left  -> bit[1]=0 -> W0  (victim)
//   bit[2]=0 -> left  -> bit[1]=1 -> W1
//   bit[2]=1 -> right -> bit[0]=0 -> W2
//   bit[2]=1 -> right -> bit[0]=1 -> W3
//
// update after accessing way W (flip bits on the path TO that way)
// =============================================================================

import cache_pkg::*;

module plru (
    input logic clk,
    input logic rst_n,

    // query port
    input logic [INDEX_BITS-1:0] query_set,
    output logic [WAY_BITS-1:0] victim_way,

    // update port
    input logic update_en,
    input logic [INDEX_BITS-1:0] update_set,
    input logic [WAY_BITS-1:0] update_way
);


    logic [2:0] tree [0:SETS-1];


    // combinational query — decode tree[query_set] to find victim way

	logic [2:0] current_tree;

	always_comb begin
		current_tree = tree[query_set];
		casez (current_tree)
			3'b0?0: victim_way = 2'b00;
			3'b0?1: victim_way = 2'b01;
			3'b1?0: victim_way = 2'b10;
			3'b1?1: victim_way = 2'b11;
			default: victim_way = 2'b00;
		endcase
	end


    // sequential update — after access, flip bits


	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			for(int i = 0; i < SETS; i++) tree[i] <= '0;
		end
		else if (update_en) begin
			case (update_way) 
				2'b00: tree[update_set] <= {1'b1, 1'b1, tree[update_set][0]};
				2'b01: tree[update_set] <= {1'b1, 1'b0, tree[update_set][0]};
				2'b10: tree[update_set] <= {1'b0, tree[update_set][1], 1'b1};
				2'b11: tree[update_set] <= {1'b0, tree[update_set][1], 1'b0};
				default: tree[update_set] <= {1'b1, 1'b1, tree[update_set][0]}; 
			endcase
		end
	end

endmodule
