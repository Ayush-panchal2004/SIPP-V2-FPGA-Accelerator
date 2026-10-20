// ============================================================
// tb_sipp_v2_parallel.sv
// SIPP V2.1 — N Parallel MAC Verification Testbench
// Author: Ayush Panchal | August 2026
// ============================================================
// Tests sipp_v2_parallel on REAL physics matrices.
// Feeds N elements per clock cycle (batched), verifies output.
//
// Key difference from sequential testbench:
//   - Elements are packed into batches of N
//   - Rows where K % N != 0 are zero-padded in the last batch
//   - Throughput = N elements per cycle (true parallel SpMV)
// ============================================================

`timescale 1ns/1ps

module tb_sipp_v2_parallel;

    localparam N        = 4;      // Parallel width — must match DUT
    localparam MAX_ROWS = 256;
    localparam MAX_COLS = 256;
    localparam MAX_NNZ  = 4096;
    localparam ULP_TOL  = 512;    // Accumulated FP32 truncation tolerance

    // ----------------------------------------------------------
    // Clock & Reset
    // ----------------------------------------------------------
    reg clk, rst_n;
    always #5 clk = ~clk;
    task tick; begin @(posedge clk); #1; end endtask

    // ----------------------------------------------------------
    // DUT
    // ----------------------------------------------------------
    reg  [N*32-1:0] mat_vals, x_elems;
    reg             valid_i, row_done;
    wire [31:0]     y_out;
    wire            y_valid;

    sipp_v2_parallel #(.N(N)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .mat_vals (mat_vals),
        .x_elems  (x_elems),
        .valid_i  (valid_i),
        .row_done (row_done),
        .y_out    (y_out),
        .y_valid  (y_valid)
    );

    // ----------------------------------------------------------
    // Memory arrays
    // ----------------------------------------------------------
    reg [31:0] A_val     [0:MAX_NNZ-1];
    reg [31:0] A_col_idx [0:MAX_NNZ-1];
    reg [31:0] A_row_ptr [0:MAX_ROWS];
    reg [31:0] x_val     [0:MAX_COLS-1];
    reg [31:0] y_expected[0:MAX_ROWS-1];

    // ----------------------------------------------------------
    // Test counters and cycle counter
    // ----------------------------------------------------------
    integer total_pass, total_fail;
    integer total_cycles, total_elements;

    task automatic check_row;
        input integer row_idx;
        input [31:0]  got, expected;
        reg   [31:0]  diff;
        begin
            diff = (got > expected) ? (got - expected) : (expected - got);
            if (diff <= ULP_TOL) begin
                $display("  [PASS] Row %0d: got=%08h  exp=%08h  diff=%0d ULP",
                         row_idx, got, expected, diff);
                total_pass = total_pass + 1;
            end else begin
                $display("  [FAIL] Row %0d: got=%08h  exp=%08h  diff=%0d ULP",
                         row_idx, got, expected, diff);
                total_fail = total_fail + 1;
            end
        end
    endtask

    // ----------------------------------------------------------
    // Task: run one matrix through the parallel DUT
    // ----------------------------------------------------------
    integer r, nnz_start, nnz_end, K, n_batches, b, k, nnz_i, col;
    reg [31:0] captured_y;
    reg [31:0] mat_v, x_v;

    task run_matrix;
        input integer n_rows;
        integer cycles_start;
        begin
            cycles_start = total_cycles;

            for (r = 0; r < n_rows; r = r+1) begin
                nnz_start = A_row_ptr[r];
                nnz_end   = A_row_ptr[r+1];
                K         = nnz_end - nnz_start;

                if (K == 0) begin
                    // Empty row — just pulse row_done
                    mat_vals = 0; x_elems = 0;
                    valid_i  = 0; row_done = 1;
                    tick; total_cycles = total_cycles + 1;
                    row_done = 0;
                end else begin
                    // Compute number of N-element batches (ceil division)
                    n_batches = (K + N - 1) / N;

                    for (b = 0; b < n_batches; b = b+1) begin
                        // Build packed batch of N elements
                        mat_vals = {N*32{1'b0}};
                        x_elems  = {N*32{1'b0}};

                        for (k = 0; k < N; k = k+1) begin
                            if (b*N + k < K) begin
                                // Real element
                                nnz_i = nnz_start + b*N + k;
                                col   = A_col_idx[nnz_i];
                                mat_vals[k*32 +: 32] = A_val[nnz_i];
                                x_elems [k*32 +: 32] = x_val[col];
                            end else begin
                                // Padding: A_val=0.0 → product=0, no effect
                                mat_vals[k*32 +: 32] = 32'h0000_0000; // 0.0
                                x_elems [k*32 +: 32] = 32'h3F800000; // 1.0
                            end
                        end

                        valid_i  = 1;
                        row_done = 0;
                        tick; total_cycles = total_cycles + 1;
                        valid_i  = 0;
                    end

                    total_elements = total_elements + K;

                    // Pulse row_done after last batch
                    mat_vals = 0; x_elems = 0;
                    valid_i  = 0; row_done = 1;
                    tick; total_cycles = total_cycles + 1;
                    row_done = 0;
                end

                // Wait for result from parallel pipeline
                @(posedge y_valid); #1;
                captured_y = y_out;
                check_row(r, captured_y, y_expected[r]);
            end
        end
    endtask

    // ----------------------------------------------------------
    // Main Test Sequence
    // ----------------------------------------------------------
    initial begin
        clk          = 0;
        rst_n        = 0;
        mat_vals     = 0; x_elems  = 0;
        valid_i      = 0; row_done = 0;
        total_pass   = 0; total_fail   = 0;
        total_cycles = 0; total_elements = 0;

        repeat(3) tick; rst_n = 1; tick;

        // ---- bcsstk01: 48x48 Boeing Structural Stiffness ----
        $display("");
        $display("=====================================================");
        $display("  SIPP V2.1 Parallel (%0d-wide) — bcsstk01", N);
        $display("  48x48 Structural Engineering (Boeing)");
        $display("=====================================================");
        $readmemh("test_data/bcsstk01/A_val.hex",      A_val);
        $readmemh("test_data/bcsstk01/A_col_idx.hex",  A_col_idx);
        $readmemh("test_data/bcsstk01/A_row_ptr.hex",  A_row_ptr);
        $readmemh("test_data/bcsstk01/x_val.hex",      x_val);
        $readmemh("test_data/bcsstk01/y_expected.hex", y_expected);
        run_matrix(48);

        // ---- nos1: 237x237 Navier-Stokes Fluid Dynamics ----
        $display("");
        $display("=====================================================");
        $display("  SIPP V2.1 Parallel (%0d-wide) — nos1", N);
        $display("  237x237 Fluid Dynamics (Navier-Stokes)");
        $display("=====================================================");
        $readmemh("test_data/nos1/A_val.hex",      A_val);
        $readmemh("test_data/nos1/A_col_idx.hex",  A_col_idx);
        $readmemh("test_data/nos1/A_row_ptr.hex",  A_row_ptr);
        $readmemh("test_data/nos1/x_val.hex",      x_val);
        $readmemh("test_data/nos1/y_expected.hex", y_expected);
        run_matrix(237);

        // ---- SUMMARY ----
        $display("");
        $display("=====================================================");
        $display("  FINAL: %0d PASSED / %0d FAILED", total_pass, total_fail);
        $display("  Total clock cycles:   %0d", total_cycles);
        $display("  Total FP32 elements:  %0d", total_elements);
        $display("  Effective throughput: %0.2f elements/cycle",
                 $itor(total_elements) / $itor(total_cycles));
        $display("  (Sequential would need: %0d cycles → %0.1fx speedup)",
                 total_elements + 285, // K cycles + 285 row_done cycles
                 $itor(total_elements + 285) / $itor(total_cycles));
        $display("=====================================================");
        if (total_fail == 0)
            $display("  *** ALL PASSED — N=%0d parallel SpMV VERIFIED! ***", N);
        $finish;
    end

    initial begin #10000000; $display("[TIMEOUT]"); $finish; end

endmodule
