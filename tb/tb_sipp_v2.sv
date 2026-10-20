// ============================================================
// tb_sipp_v2.sv
// SIPP V2.1 (Research Edition) — Verification Testbench
// Author: Ayush Panchal | August 2026
// ============================================================
// Tests:
//   TEST 1: FP32 MAC — Single product:    1.5 * 2.0 = 3.0
//   TEST 2: FP32 MAC — 3-element dot:     [2,3,4]·[1.5,2,0.5] = 11.0
//   TEST 3: FP32 MAC — Negative values:   [5,-2]·[3,4] = 7.0
//   TEST 4: FP32 MAC — Zero element:      [0,6]·[99,2] = 12.0
//   TEST 5: Adder Tree — 4-input sum:     1+2+3+4 = 10.0
//   TEST 6: Adder Tree — Negative mix:    5+(-3)+2+(-1) = 3.0
//   TEST 7: FP32 MAC — Physics scale:     [1000.5,250]·[9.81,0.5] ≈ 9939.9
//
// All IEEE 754 hex constants pre-computed via Python:
//   import struct; struct.unpack('>I', struct.pack('>f', val))[0]
//
// Pass criteria: result matches expected within 2 ULP
// ============================================================

`timescale 1ns/1ps

module tb_sipp_v2;

    // ---------------------------------------------------------
    // Pre-computed IEEE 754 FP32 constants (Python-verified)
    // ---------------------------------------------------------
    localparam [31:0]
        FP_0p0    = 32'h00000000,   //   0.0
        FP_0p5    = 32'h3F000000,   //   0.5
        FP_1p0    = 32'h3F800000,   //   1.0
        FP_1p5    = 32'h3FC00000,   //   1.5
        FP_2p0    = 32'h40000000,   //   2.0
        FP_3p0    = 32'h40400000,   //   3.0
        FP_4p0    = 32'h40800000,   //   4.0
        FP_5p0    = 32'h40A00000,   //   5.0
        FP_6p0    = 32'h40C00000,   //   6.0
        FP_7p0    = 32'h40E00000,   //   7.0
        FP_9p81   = 32'h411CF5C3,   //   9.81
        FP_10p0   = 32'h41200000,   //  10.0
        FP_11p0   = 32'h41300000,   //  11.0
        FP_12p0   = 32'h41400000,   //  12.0
        FP_99p0   = 32'h42C60000,   //  99.0
        FP_250p0  = 32'h437A0000,   // 250.0
        FP_1000p5 = 32'h447A2000,   // 1000.5
        FP_9939p9 = 32'h461B4F9F,   // 9939.905 (expected result of TEST 7)
        FP_NEG1   = 32'hBF800000,   //  -1.0
        FP_NEG2   = 32'hC0000000,   //  -2.0
        FP_NEG3   = 32'hC0400000;   //  -3.0

    // ---------------------------------------------------------
    // Clock and Reset
    // ---------------------------------------------------------
    reg clk, rst_n;
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // DUT: FP32 MAC Unit
    // ---------------------------------------------------------
    reg  [31:0] mac_value, mac_x;
    reg         mac_valid, mac_row_done;
    wire [31:0] mac_result;
    wire        mac_result_we;

    sipp_fp32_mac dut_mac (
        .clk        (clk),
        .rst_n      (rst_n),
        .value_i    (mac_value),
        .x_elem_i   (mac_x),
        .valid_i    (mac_valid),
        .row_done_i (mac_row_done),
        .result_o   (mac_result),
        .result_we  (mac_result_we)
    );

    // ---------------------------------------------------------
    // DUT: FP32 Adder Tree (Parametric — N=4 for this testbench)
    // in_flat packing: in_flat[k*32 +: 32] = in[k]
    //   in_flat[31:0]   = in[0]
    //   in_flat[63:32]  = in[1]
    //   in_flat[95:64]  = in[2]
    //   in_flat[127:96] = in[3]
    // ---------------------------------------------------------
    reg  [127:0] at_in_flat;   // 4 x 32-bit inputs packed into one bus
    reg          at_valid;
    wire [31:0]  at_sum;
    wire         at_valid_o;

    sipp_adder_tree #(.N(4)) dut_tree (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid_i (at_valid),
        .in_flat (at_in_flat),
        .sum_o   (at_sum),
        .valid_o (at_valid_o)
    );

    // ---------------------------------------------------------
    // Test Infrastructure
    // ---------------------------------------------------------
    integer pass_count, fail_count;

    // Check result within 2 ULP tolerance
    task automatic check;
        input [31:0] got, expected;
        input [63:0] test_name;  // simplified: use integer tag
        reg [31:0] diff;
        begin
            diff = (got > expected) ? (got - expected) : (expected - got);
            if (diff <= 32'd2) begin
                $display("  [PASS] got=32'h%08h  expected=32'h%08h  diff=%0d ULP",
                         got, expected, diff);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] got=32'h%08h  expected=32'h%08h  diff=%0d ULP",
                         got, expected, diff);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task tick; begin @(posedge clk); #1; end endtask

    task mac_feed;
        input [31:0] v, x;
        begin
            mac_value    = v;
            mac_x        = x;
            mac_valid    = 1;
            mac_row_done = 0;
            tick;
            mac_valid = 0;
        end
    endtask

    task mac_flush;
        output [31:0] result;
        begin
            mac_valid    = 0;
            mac_row_done = 1;
            tick;
            mac_row_done = 0;
            result = mac_result;
            tick;
        end
    endtask

    // ---------------------------------------------------------
    // Main Test Sequence
    // ---------------------------------------------------------
    reg [31:0] result;

    initial begin
        clk          = 0;
        rst_n        = 0;
        mac_value    = 0;
        mac_x        = 0;
        mac_valid    = 0;
        mac_row_done = 0;
        at_in_flat   = 128'h0;
        at_valid     = 0;
        pass_count   = 0;
        fail_count   = 0;

        repeat(3) tick;
        rst_n = 1;
        tick;

        $display("");
        $display("========================================");
        $display("  SIPP V2.1 -- FP32 Verification Suite ");
        $display("========================================");

        // ---- TEST 1: 1.5 * 2.0 = 3.0 ----
        $display("\n[TEST 1] FP32 MAC: 1.5 * 2.0 = 3.0");
        mac_feed(FP_1p5, FP_2p0);
        mac_flush(result);
        check(result, FP_3p0, 1);

        // ---- TEST 2: [2,3,4].[1.5,2,0.5] = 11.0 ----
        $display("\n[TEST 2] FP32 MAC: [2,3,4].[1.5,2,0.5] = 11.0");
        mac_feed(FP_2p0, FP_1p5);   // 3.0
        mac_feed(FP_3p0, FP_2p0);   // 6.0
        mac_feed(FP_4p0, FP_0p5);   // 2.0
        mac_flush(result);
        check(result, FP_11p0, 2);

        // ---- TEST 3: [5,-2].[3,4] = 7.0 ----
        $display("\n[TEST 3] FP32 MAC: [5,-2].[3,4] = 7.0");
        mac_feed(FP_5p0,  FP_3p0);  //  15.0
        mac_feed(FP_NEG2, FP_4p0);  //  -8.0
        mac_flush(result);
        check(result, FP_7p0, 3);

        // ---- TEST 4: [0,6].[99,2] = 12.0 ----
        $display("\n[TEST 4] FP32 MAC: [0,6].[99,2] = 12.0 (zero element)");
        mac_feed(FP_0p0, FP_99p0);  //   0.0
        mac_feed(FP_6p0, FP_2p0);   //  12.0
        mac_flush(result);
        check(result, FP_12p0, 4);

        // ---- TEST 5: Adder Tree 1+2+3+4 = 10.0 ----
        // in_flat = {in[3], in[2], in[1], in[0]} = {4.0, 3.0, 2.0, 1.0}
        $display("\n[TEST 5] Adder Tree (N=4): 1+2+3+4 = 10.0 (log2(4)=2 cycle latency)");
        at_in_flat = {FP_4p0, FP_3p0, FP_2p0, FP_1p0};
        at_valid = 1; tick;
        at_valid = 0; tick;   // Stage 0 registered
        tick;                 // Stage 1 registered → result ready
        check(at_sum, FP_10p0, 5);

        // ---- TEST 6: Adder Tree 5+(-3)+2+(-1) = 3.0 ----
        // in_flat = {in[3], in[2], in[1], in[0]} = {-1.0, 2.0, -3.0, 5.0}
        $display("\n[TEST 6] Adder Tree (N=4): 5+(-3)+2+(-1) = 3.0");
        at_in_flat = {FP_NEG1, FP_2p0, FP_NEG3, FP_5p0};
        at_valid = 1; tick;
        at_valid = 0; tick;
        tick;
        check(at_sum, FP_3p0, 6);

        // ---- TEST 7: Physics scale ----
        $display("\n[TEST 7] FP32 MAC: [1000.5,250].[9.81,0.5] = 9939.905");
        mac_feed(FP_1000p5, FP_9p81);   // 9814.905
        mac_feed(FP_250p0,  FP_0p5);    //  125.0
        mac_flush(result);
        check(result, FP_9939p9, 7);

        // ---- SUMMARY ----
        $display("");
        $display("========================================");
        $display("  Results: %0d PASSED  /  %0d FAILED",
                 pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED *** SIPP V2 FP32 Verified!\n");
        else
            $display("  *** FAILURES DETECTED -- See above ***\n");

        $finish;
    end

    initial begin #50000; $display("[TIMEOUT]"); $finish; end

endmodule
