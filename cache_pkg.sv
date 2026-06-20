// =============================================================================
// cache_pkg.sv: shared parameters
// other module imports: import cache_pkg::*;
// =============================================================================

package cache_pkg;

    parameter int ADDR_WIDTH  = 32;   // CPU address bits
    parameter int DATA_WIDTH  = 32;   // CPU data word bits
    parameter int LINE_BYTES  = 16;   // bytes per cache line
    parameter int WAYS        = 4;    // associativity
    parameter int SETS        = 64;   

    parameter int LINE_WIDTH  = LINE_BYTES * 8;             // 128 bits
    parameter int OFFSET_BITS = $clog2(LINE_BYTES);         // 4 bits addr[3:0]
    parameter int INDEX_BITS  = $clog2(SETS);               // 6 bits addr[9:4]
    parameter int TAG_BITS    = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS; // 22 bits addr[31:10]
    parameter int WAY_BITS    = $clog2(WAYS);               // 2 bits

    // -------------------------------------------------------------------------

    // AXI parameters
    parameter int AXI_ADDR_W  = 32;
    parameter int AXI_DATA_W  = LINE_WIDTH; // 128-bit bus: full cache line

    // -------------------------------------------------------------------------

    // testbench / memory model
    parameter int MEM_LATENCY = 10; // clock cycles for memory to respond

    // -------------------------------------------------------------------------
    // cache_meta_t
    // metadata for one cache line (one way inside one set).
    // replaces the separate valid_array / tag_array flat arrays
    //
    // example:
    //   cache_meta_t meta [0:SETS-1][0:WAYS-1];
    //   if (meta[idx][w].valid && meta[idx][w].tag == req_tag) ...
    //   meta[idx][way] <= '{ valid:1'b1, dirty:1'b0, tag:new_tag };
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic valid; // line holds real data
        logic dirty; // written since last fetch, must write back
        logic [TAG_BITS-1:0] tag; // upper address bits stored with the line
    } cache_meta_t;

    // -------------------------------------------------------------------------
    // cache_state_t
    // FSM states for cache_ctrl
    
    //   IDLE 	   -> TAG_CHECK  
    //   TAG_CHECK -> DONE (hit)
    //   TAG_CHECK -> FETCH (miss, victim is clean)
    //   TAG_CHECK -> WRITEBACK (miss, victim is dirty)
    //   WRITEBACK -> FETCH (writeback AXI transaction done)
    //   FETCH     -> TAG_CHECK (fetch AXI transaction done — re-checks the tag)
    //   DONE      -> IDLE
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE = 3'd0,
        ST_TAG_CHECK = 3'd1,
        ST_WRITEBACK = 3'd2,
        ST_FETCH = 3'd3,
        ST_DONE  = 3'd4,
        ST_FILL  = 3'd5
    } cache_state_t;

    // -------------------------------------------------------------------------
    // mesi_t  (future multi-core extension — defined but not used yet)
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        MESI_I = 2'd0,   // Invalid
        MESI_S = 2'd1,   // Shared
        MESI_E = 2'd2,   // Exclusive
        MESI_M = 2'd3    // Modified
    } mesi_t;

endpackage

