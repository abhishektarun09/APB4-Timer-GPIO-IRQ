
# Verilator Makefile for APB4 register slave

TOP      = tb_apb_slave
RTL      = rtl/apb_slave.sv
TB       = tb/tb_apb_slave.sv

OBJ_DIR  = obj_dir
EXE      = $(OBJ_DIR)/V$(TOP)

VERILATOR = verilator

VFLAGS = --binary --timing --trace \
         --Wall -Wno-fatal \
         --top-module $(TOP) \
         --Mdir $(OBJ_DIR)

.PHONY: all sim lint clean

# Default target
all: sim

# Compile and run the testbench
sim:
	$(VERILATOR) $(VFLAGS) $(RTL) $(TB)
	./$(EXE)

# Check RTL and testbench without running simulation
lint:
	$(VERILATOR) --lint-only --timing \
		-Wall -Wno-fatal \
		--top-module $(TOP) $(RTL) $(TB)

# Remove generated files
clean:
	rm -rf $(OBJ_DIR) waveform.vcd