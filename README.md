# sv-l1-cache-controller

A 4-way set-associative L1 data cache controller in SystemVerilog with a full AXI4 128-bit master interface. Verified on Cadence XCelium with a self-checking testbench — 2532/2532 tests passing.

---

## Cache Configuration

| Parameter | Value |
|---|---|
| Total size | 4 KB |
| Sets | 64 |
| Ways | 4 |
| Line size | 16 bytes |
| Write policy | Write-back, write-allocate |
| Replacement | Pseudo-LRU |
| AXI4 bus width | 128 bits |
| Memory latency | 10 cycles |

---

## Performance

| Metric | Value |
|---|---|
| Hit rate | 98.3% |
| Hits | 5059 |
| Misses | 87 |
| Writebacks | 11 |
| AMAT | 1.2 cycles |

---

## Test Suite

12 directed tests followed by a constrained random stress test. Every read is self-checked against a software reference model.

| Test | Description |
|---|---|
| T01 — Cold read miss | Reads 3 addresses on an empty cache. Every access is a miss and triggers a DRAM fetch. Verifies the full fetch path and AXI4 read transaction end to end. |
| T02 — Read hit | Re-reads the same addresses from T01. Lines are now cached so no DRAM access should occur. Verifies hit detection works correctly and that fetched lines survive in the cache between requests. |
| T03 — Spatial locality | Reads word offsets +4, +8, +12 within a line fetched in T01. Since a full 16-byte line is fetched on every miss, all 4 words arrive together and should be instant hits. Verifies that reading different byte offsets within a line returns the correct word. |
| T04 — Write hit | Writes new values to addresses already in the cache. Read-back must return the written value directly from the cache without touching DRAM. Verifies the write-hit path and dirty bit. |
| T05 — Write miss | Writes to addresses never accessed before. The cache must fetch the full line first (write-allocate policy) before writing the word into it. Verifies the write-miss → fetch → write path. |
| T06 — Dirty eviction | Fills all 4 ways of one set with dirty lines, then forces a 5th access to trigger an eviction and writeback. Re-reads the evicted address to confirm the writeback correctly committed the dirty data to DRAM before replacing the line. |
| T07 — Fill 4 ways | Writes 4 distinct values to all 4 ways of one set and reads each back. Verifies that ways are fully independent with no data corruption between them. |
| T08 — pLRU replacement | Accesses all 4 ways in sequence to build a known pLRU tree state, then re-accesses one way to make it MRU. Forces an eviction and verifies the pLRU-selected victim way was replaced, not the recently accessed one. |
| T09 — Write then read | Writes a value to an address then immediately reads it back with no clock cycles in between. Verifies the cache returns exactly what was just written — both on write-miss (first access fetches the line) and write-hit (subsequent accesses to the same line). |
| T10 — Back-to-back requests | 8 consecutive write-read pairs with no idle cycles between them. Verifies the stall handshake correctly handles back-to-back requests with no idle gap between them without dropping or corrupting data. |
| T11 — Constrained random | 5000 random read/write operations across 256 word-aligned addresses in a fixed region. The address range is constrained to create set collisions, forcing repeated evictions, dirty writebacks, and pLRU replacements under pressure. Writes update the reference model to keep expected values in sync. Only reads are directly self-checked. |
| T12 — Performance report | Reads hardware counters for hits, misses, writebacks, and evictions. Computes hit rate and AMAT. No pass/fail — informational only. |

---

## Race Conditions Found During Verification: Root Cause Analysis and Fixes
 
Two race conditions were discovered and fixed during simulation. Both caused silent data corruption — the simulation completed with no crashes but reads returned wrong values.
 
 
### Bug 1 — Combinational Hazard on `hit_way`
 
**Problems:** 2179 failures. Reads returned stale data from a prior test instead of the value just written.
 
**Cause:** `hit_way` is a purely combinational signal that outputs which cache way matches the current request. In `ST_DONE` it was used directly to select which way to write data into. As the FSM transitioned out of `ST_DONE`, `hit_way`'s inputs changed and it glitched to a wrong value before the clock edge arrived — causing the write to commit to the wrong way.
 
**Fix:** Added a registered copy `hit_way_r` that latches only when `ST_TAG_CHECK` confirms a hit or a fetch completes. `ST_DONE` uses `hit_way_r` instead of the live combinational `hit_way`, so the write always goes to the correct way regardless of any glitching during the state transition.
 
 
### Bug 2 — Read/Write Race on `tag_array` at the Same Clock Edge
 
**Problems:** 166 failures after fixing the above problem. After a DRAM fetch, the re-check returned data from the wrong way as if the fetch never happened.
 
**Cause:** When a fetch completes, `tag_array` commits the new tag in `always_ff` on the rising clock edge while the FSM simultaneously re-checks `tag_array` via a combinational `always_comb` read. The combinational read evaluated before the flip-flop write committed, so the re-check saw `valid=0` — the pre-write value — missed the hit, and pre-loaded `data_array` from the wrong way.
 
**Fix:** Two changes together. Write-to-read forwarding was added to `tag_array` so the combinational read returns `wr_meta` directly when a write is in progress to the same location, resolving the same-cycle conflict. A one-cycle intermediate state `ST_FILL` was also inserted between `ST_FETCH` and the re-check to give `data_array` time to settle and `hit_way_r` time to update to `victim_way_r` before the re-check runs.
 
---

## File Structure

```
├── cache_pkg.sv        # parameters, typedefs, state enums
├── cache_ctrl.sv       # main FSM controller
├── tag_array.sv        # valid/dirty/tag metadata
├── data_array.sv       # 128-bit cache line storage
├── plru.sv             # pseudo-LRU replacement
├── axi_master.sv       # AXI4 master — fetch and writeback
├── cache_top.sv        # top-level integration
├── axi_mem_model.sv    # AXI4 slave memory model for simulation
├── tb_cache_top.sv     # self-checking testbench
└── Makefile
```

---

## How to Run

Requires Cadence XCelium.

```bash
make run      # compile and simulate
make clean    # delete generated files
```

Expected output:
```
  TEST SUMMARY
  Total : 2532   Passed : 2532   Failed : 0
  Result : *** ALL TESTS PASSED ***
```

To view waveforms:
```bash
simvision sim/cache_waves.shm &
```
