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
