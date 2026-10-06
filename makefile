DIR_BUILD = build
DIR_CONS  = constraints
DIR_RTL   = rtl
DIR_SIM   = sim
DIR_TB    = tb
DIR_TCL   = tcl

TOP_LEVEL = tm1638
PROJ_TOP  = top_tm1638_demo

VERILOGS = $(DIR_RTL)/top_tm1638_demo.v $(DIR_RTL)/tm1638.v

compile:
	if not exist $(DIR_BUILD) mkdir $(DIR_BUILD)
	iverilog -o $(DIR_BUILD)/$(TOP_LEVEL)_sim $(VERILOGS) $(DIR_TB)/$(TOP_LEVEL)_tb.v

vvp:
	vvp $(DIR_BUILD)/$(TOP_LEVEL)_sim

gtk:
	gtkwave $(DIR_BUILD)/$(TOP_LEVEL)_tb.vcd

sim: compile vvp gtk

syn:
	if not exist $(DIR_BUILD) mkdir $(DIR_BUILD)
	yosys -p "synth_ice40 -top $(PROJ_TOP) -json $(DIR_BUILD)/$(TOP_LEVEL)_netlist.json" $(VERILOGS)

pnr: syn
	nextpnr-ice40 \
		--up5k \
		--package sg48 \
		--json $(DIR_BUILD)/$(TOP_LEVEL)_netlist.json \
		--pcf $(DIR_CONS)/$(TOP_LEVEL).pcf \
		--asc $(DIR_BUILD)/$(TOP_LEVEL).asc

bit: pnr
	icepack $(DIR_BUILD)/$(TOP_LEVEL).asc $(DIR_BUILD)/$(TOP_LEVEL).bin

flash: bit
	icesprog $(DIR_BUILD)/$(TOP_LEVEL).bin

all: bit

clean:
	if exist $(DIR_BUILD) rmdir $(DIR_BUILD) /S /Q