TOPLEVEL  = tb_cache_top
TIMESCALE = 1ns/1ps

SRCS = \
	cache_pkg.sv      \
	tag_array.sv      \
	data_array.sv     \
	plru.sv           \
	cache_ctrl.sv     \
	axi_master.sv     \
	cache_top.sv      \
	axi_mem_model.sv  \
	tb_cache_top.sv

run:
	xrun -timescale $(TIMESCALE) \
	     -sv \
	     -top $(TOPLEVEL) \
	     -access +rw \
	     $(SRCS)

clean:
	rm -rf xrun.log xrun.history INCA_libs sim/ xcelium.d

