// =============================================================================
// cache_ctrl.sv
// 5-state FSM main controller. Coordinates tag_array, data_array, plru,
// and axi_master to handle CPU request
// =============================================================================

import cache_pkg::*;

module cache_ctrl (
    input logic                    clk,
    input logic                    rst_n,

    // CPU interface 
    input logic                    cpu_valid,
    input logic                    cpu_we,
    input logic [ADDR_WIDTH-1:0]   cpu_addr,
    input logic [DATA_WIDTH-1:0]   cpu_wdata,
    output logic [DATA_WIDTH-1:0]  cpu_rdata,
    output logic                   cpu_stall,

    // tag_array interface 
    output logic [INDEX_BITS-1:0]  ta_rd_index,
    input  cache_meta_t            ta_rd_meta [0:WAYS-1],

    output logic                   ta_wr_en,
    output logic [INDEX_BITS-1:0]  ta_wr_index,
    output logic [WAY_BITS-1:0]    ta_wr_way,
    output cache_meta_t            ta_wr_meta,

    output logic                   ta_dirty_en,
    output logic [INDEX_BITS-1:0]  ta_dirty_index,
    output logic [WAY_BITS-1:0]    ta_dirty_way,

    // data_array interface 
    output logic                   da_word_wr_en,
    output logic [INDEX_BITS-1:0]  da_word_wr_index,
    output logic [WAY_BITS-1:0]    da_word_wr_way,
    output logic [OFFSET_BITS-1:0] da_word_wr_offset,
    output logic [DATA_WIDTH-1:0]  da_word_wr_data,

    output logic                   da_line_wr_en,
    output logic [INDEX_BITS-1:0]  da_line_wr_index,
    output logic [WAY_BITS-1:0]    da_line_wr_way,
    output logic [LINE_WIDTH-1:0]  da_line_wr_data,

    output logic [INDEX_BITS-1:0]  da_rd_index,
    output logic [WAY_BITS-1:0]    da_rd_way,
    input logic [LINE_WIDTH-1:0]   da_rd_line,

    output logic [INDEX_BITS-1:0]  da_wb_index,
    output logic [WAY_BITS-1:0]    da_wb_way,
    input logic [LINE_WIDTH-1:0]   da_wb_line,

    // plru interface 
    output logic [INDEX_BITS-1:0]  plru_query_set,
    input logic [WAY_BITS-1:0]     plru_victim_way,

    output logic                   plru_update_en,
    output logic [INDEX_BITS-1:0]  plru_update_set,
    output logic [WAY_BITS-1:0]    plru_update_way,

    // axi_master interface 
    output logic                   axi_fetch_req,
    output logic [ADDR_WIDTH-1:0]  axi_fetch_addr,
    input logic                    axi_fetch_done,
    input logic [LINE_WIDTH-1:0]   axi_fetch_rdata,

    output logic                   axi_wb_req,
    output logic [ADDR_WIDTH-1:0]  axi_wb_addr,
    output logic [LINE_WIDTH-1:0]  axi_wb_wdata,
    input logic                    axi_wb_done,

    // performance counters 
    output logic [31:0]            perf_hits,
    output logic [31:0]            perf_misses,
    output logic [31:0]            perf_writebacks,
    output logic [31:0]            perf_evictions
);


	logic [OFFSET_BITS-1:0]  req_offset;
	logic [INDEX_BITS-1:0]   req_index;
	logic [TAG_BITS-1:0]     req_tag;

	assign req_offset = cpu_addr[OFFSET_BITS-1:0];
	assign req_index  = cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
	assign req_tag    = cpu_addr[ADDR_WIDTH-1 :OFFSET_BITS+INDEX_BITS];


    // request latch
    // capture the CPU request when transitioning IDLE -> TAG_CHECK

	logic [OFFSET_BITS-1:0]  req_offset_r;
	logic [INDEX_BITS-1:0]   req_index_r;
	logic [TAG_BITS-1:0]     req_tag_r;
	logic                    req_we_r;
	logic [DATA_WIDTH-1:0]   req_wdata_r;

	cache_state_t state, next_state;

	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			req_offset_r <= '0;
			req_index_r  <= '0;
			req_tag_r    <= '0;
			req_we_r     <= '0;
			req_wdata_r  <= '0;
		end
		else if(state == ST_IDLE && cpu_valid) begin
			req_offset_r <= req_offset;
			req_index_r  <= req_index;
			req_tag_r    <= req_tag;
			req_we_r     <= cpu_we;
			req_wdata_r  <= cpu_wdata;
		end
	end


    // 4-way parallel hit detection

	logic [WAYS-1:0]         hit_vec; 
	logic                    cache_hit;
	logic [WAY_BITS-1:0]     hit_way; 

	always_comb begin
		hit_vec = '0;
		hit_way = '0;

		for(int i = 0; i < WAYS; i++) begin
			hit_vec[i] = ta_rd_meta[i].valid && (ta_rd_meta[i].tag == req_tag_r);
			if (hit_vec[i]) hit_way = WAY_BITS'(i);
		end
	
		cache_hit = |hit_vec;
	end


	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) state <= ST_IDLE;
		else state <= next_state;
	end


    //  victim info latch 

	logic [WAY_BITS-1:0]     victim_way_r;
	logic                    victim_dirty_r;
	logic [TAG_BITS-1:0]     victim_tag_r;  

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			victim_way_r   <= '0;
			victim_dirty_r <= '0;
			victim_tag_r   <= '0;
		end 
		else if (state == ST_TAG_CHECK && !cache_hit) begin
			victim_way_r   <= plru_victim_way;
			victim_dirty_r <= ta_rd_meta[plru_victim_way].valid && ta_rd_meta[plru_victim_way].dirty;
			victim_tag_r   <= ta_rd_meta[plru_victim_way].tag;
		end
	end


	// latch hit_way -- updated on hit in TAG_CHECK or on fetch completion
	logic [WAY_BITS-1:0] hit_way_r;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) hit_way_r <= '0;
		else if (state == ST_TAG_CHECK && cache_hit) hit_way_r <= hit_way;
		else if (state == ST_FETCH && axi_fetch_done) hit_way_r <= victim_way_r;
	end

    // performance counters 

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
		    perf_hits       <= '0;
		    perf_misses     <= '0;
		    perf_writebacks <= '0;
		    perf_evictions  <= '0;
		end
		else begin
			perf_hits 	<= (state == ST_TAG_CHECK &&  cache_hit) ? perf_hits + 1 : perf_hits;		
			perf_misses 	<= (state == ST_TAG_CHECK &&  !cache_hit) ? perf_misses + 1 : perf_misses;
			perf_writebacks <= (axi_wb_done) ? perf_writebacks + 1 : perf_writebacks;
			perf_evictions  <= (axi_fetch_done) ? perf_evictions + 1 : perf_evictions;
		end
	end

	
	always_comb begin
		// default
		next_state        = state;
		cpu_stall         = 1'b0;
			
		ta_rd_index       = '0;
		ta_wr_en          = 1'b0;
		ta_wr_index       = '0;
		ta_wr_way         = '0;
		ta_wr_meta        = '{valid: 1'b0, dirty: 1'b0, tag: '0};
			
		ta_dirty_en       = 1'b0;
		ta_dirty_index    = '0;
		ta_dirty_way      = '0;
			
		da_word_wr_en     = 1'b0;
		da_word_wr_index  = '0;
		da_word_wr_way    = '0;
		da_word_wr_offset = '0;
		da_word_wr_data   = '0;
			
		da_line_wr_en     = 1'b0;
		da_line_wr_index  = '0;
		da_line_wr_way    = '0;
		da_line_wr_data   = '0;
			
		da_rd_index       = '0;
		da_rd_way         = '0;
			
		da_wb_index       = '0;
		da_wb_way         = '0;
			
		plru_query_set    = '0;
		plru_update_en    = 1'b0;
		plru_update_set   = '0;
		plru_update_way   = '0;
			
		axi_fetch_req     = 1'b0;
		axi_fetch_addr    = '0;
			
		axi_wb_req        = 1'b0;
		axi_wb_addr       = '0;
		axi_wb_wdata      = '0;
			
		cpu_rdata         = '0;

		// FSM

		case (state) 

			ST_IDLE: begin
				cpu_stall = 1'b0;
				next_state = cpu_valid ? ST_TAG_CHECK : ST_IDLE;
			end

			ST_TAG_CHECK: begin
				cpu_stall      = 1'b1;
				ta_rd_index    = req_index_r;
				plru_query_set = req_index_r;
				da_rd_index    = req_index_r;
				da_rd_way      = cache_hit ? hit_way : victim_way_r;

				if (cache_hit) next_state = ST_DONE;
				else begin
				    if (ta_rd_meta[plru_victim_way].valid && ta_rd_meta[plru_victim_way].dirty) next_state = 				ST_WRITEBACK;
				    else next_state = ST_FETCH;
				end
			end

			ST_WRITEBACK: begin
				cpu_stall 	= 1'b1;
				axi_wb_req 	= 1'b1;
				axi_wb_addr 	= {victim_tag_r, req_index_r, {OFFSET_BITS{1'b0}}};
				axi_wb_wdata	= da_wb_line;
				da_wb_index	= req_index_r;
				da_wb_way	= victim_way_r;
				next_state	= axi_wb_done ? ST_FETCH : ST_WRITEBACK; 
			end

			ST_FETCH: begin
				cpu_stall	= 1'b1;
				axi_fetch_req	= 1'b1;
				axi_fetch_addr 	= {req_tag_r, req_index_r, {OFFSET_BITS{1'b0}}};
				if (axi_fetch_done) begin
					ta_wr_en	= 1'b1;
					ta_wr_index	= req_index_r;
					ta_wr_way	= victim_way_r;
					ta_wr_meta	= '{valid: 1'b1, dirty: 1'b0, tag: req_tag_r};

					da_line_wr_en		= 1'b1;
					da_line_wr_index	= req_index_r;
					da_line_wr_way		= victim_way_r;
					da_line_wr_data		= axi_fetch_rdata;
				
				

					next_state = ST_FILL;
				end
				else next_state = ST_FETCH;	
			end


			ST_FILL: begin
				cpu_stall      = 1'b1;
				da_rd_index    = req_index_r;
				da_rd_way      = hit_way_r;
				ta_rd_index    = req_index_r;
				plru_query_set = req_index_r;
				next_state     = ST_TAG_CHECK;
			end

			ST_DONE: begin
				cpu_stall       = 1'b0;
				plru_update_en  = 1'b1;
				plru_update_set = req_index_r;
				plru_update_way = hit_way_r;

				// read
				if (!req_we_r) cpu_rdata = da_rd_line[32 * req_offset_r[3:2] +: 32];
				// write
				else begin
				    ta_dirty_en       = 1'b1;
				    ta_dirty_index    = req_index_r;
				    ta_dirty_way      = hit_way_r;
				    
				    da_word_wr_en     = 1'b1;
				    da_word_wr_index  = req_index_r;
				    da_word_wr_way    = hit_way_r;
				    da_word_wr_offset = req_offset_r;
				    da_word_wr_data   = req_wdata_r;
				end
				next_state = ST_IDLE;
			end

		endcase
	
	end

endmodule

