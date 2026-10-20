## ============================================================
## constraints.xdc
## SIPP V2.1 — Xilinx Artix-7 FPGA Constraints
## Author: Ayush Panchal | August 2026
## ============================================================
## !! UPDATE for your specific lab board !!
##
## Basys 3 clock: W5 (100 MHz)
## Nexys A7 clock: E3 (100 MHz)
## Arty A7 clock: E3 (100 MHz)
##
## For demo, we target 100 MHz. The design can run at 130+ MHz
## based on synthesis estimates — keep to 100 MHz for safety.
## ============================================================

# ---- Primary Clock (100 MHz on Basys 3) ----
# UPDATE the pin location for your board:
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# ---- Reset (active-low, tied to BTNC on Basys 3) ----
set_property PACKAGE_PIN U18 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ---- Timing Constraints ----
# Input/Output delays (generous margins for demo)
set_input_delay  -clock sys_clk 2.0 [all_inputs]
set_output_delay -clock sys_clk 2.0 [all_outputs]

# ---- Bitstream Settings ----
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pulldown [current_design]

# ============================================================
# NOTE: The actual I/O pins (mat_val, x_elem, y_out etc.) are
# internal signals in this demo. For full UART communication,
# see fpga/uart_wrapper.sv (to be added in Phase 4).
# For the Sept 17 demo, connect with Vivado's ILA (Integrated
# Logic Analyzer) for in-circuit signal capture.
# ============================================================
