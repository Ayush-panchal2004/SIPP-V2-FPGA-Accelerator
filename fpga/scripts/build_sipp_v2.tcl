# ============================================================
# build_sipp_v2.tcl
# SIPP V2.1 — Vivado Project Setup Script (Task 10)
# Author: Ayush Panchal | August 2026
# ============================================================
# USAGE (at IITM lab on Sept 16):
#   1. Open Vivado 2023.x
#   2. In Tcl Console: cd <path_to_SIPP_V2>
#   3. source fpga/build_sipp_v2.tcl
#
# This script will:
#   - Create a new Vivado project
#   - Add all RTL source files
#   - Set the top module
#   - Run synthesis + implementation
#   - Generate a bitstream
#
# IMPORTANT: Update FPGA_PART below for your lab board:
#   Basys 3:  xc7a35tcpg236-1
#   Nexys A7: xc7a100tcsg324-1
#   Arty A7:  xc7a35ticsg324-1L
# ============================================================

set PROJECT_NAME  "SIPP_V2_FPGA"
set PROJECT_DIR   "./vivado_project"
set RTL_DIR       "./rtl"
set FPGA_PART     "xc7a35tcpg236-1"   ;# <-- UPDATE for your board!
set FPGA_BOARD    "Basys 3"           ;# <-- UPDATE for your board!
set TOP_MODULE    "sipp_v2_top"

puts "========================================================"
puts "  SIPP V2.1 — Vivado Build Script"
puts "  Target Board : $FPGA_BOARD"
puts "  FPGA Part    : $FPGA_PART"
puts "  Top Module   : $TOP_MODULE"
puts "========================================================"

# ---- Create project ----
create_project $PROJECT_NAME $PROJECT_DIR -part $FPGA_PART -force
puts "\[Step 1\] Project created: $PROJECT_DIR/$PROJECT_NAME"

# ---- Add RTL sources ----
add_files -fileset sources_1 [list \
    $RTL_DIR/fp32_pkg.sv    \
    $RTL_DIR/fp16_pkg.sv    \
    $RTL_DIR/sipp_fp32_mac.sv    \
    $RTL_DIR/sipp_adder_tree.sv  \
    $RTL_DIR/sipp_v2_top.sv      \
    $RTL_DIR/sipp_v2_parallel.sv \
]
set_property file_type {SystemVerilog} [get_files *.sv]
puts "\[Step 2\] RTL files added."

# ---- Set top module ----
set_property top $TOP_MODULE [current_fileset]
puts "\[Step 3\] Top module set to: $TOP_MODULE"

# ---- Add constraints ----
add_files -fileset constrs_1 ./fpga/constraints.xdc
puts "\[Step 4\] Constraints file added."

# ---- Run synthesis ----
puts "\[Step 5\] Starting synthesis (this takes ~2-5 minutes)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis FAILED! Check the synthesis log in Vivado."
}
puts "  Synthesis COMPLETE."

# ---- Run implementation ----
puts "\[Step 6\] Starting implementation (place and route)..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation FAILED! Check the implementation log."
}

# Print timing summary
open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "  Implementation COMPLETE."
puts "  Worst Negative Slack (WNS): $wns ns"
if {[expr {$wns >= 0}]} {
    puts "  TIMING MET! Design runs cleanly at target frequency."
} else {
    puts "  WARNING: Timing violation. Consider reducing clock frequency."
}

# ---- Generate bitstream ----
puts "\[Step 7\] Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bitfile "$PROJECT_DIR/$PROJECT_NAME.runs/impl_1/$TOP_MODULE.bit"
puts "\[Step 8\] Bitstream generated: $bitfile"

# ---- Program the board ----
puts ""
puts "========================================================"
puts "  BUILD COMPLETE!"
puts "  To program the FPGA board:"
puts "    1. Connect the board via USB"
puts "    2. Open Hardware Manager in Vivado"
puts "    3. Auto Connect → Program Device"
puts "    4. Select: $bitfile"
puts "========================================================"
