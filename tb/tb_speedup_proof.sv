// ============================================================
// tb_speedup_proof.sv
// SIPP V2.1 — 1024-Element Speedup Proof
// Author: Ayush Panchal | August 2026
// ============================================================
// Compares the theoretical latency of a Sequential CPU (MAC)
// vs SIPP Parallel Adder Tree (N=1024).
//
// Proof Goals:
// 1. CPU (Sequential) takes 1024 cycles to accumulate 1024 items.
// 2. SIPP (Parallel) takes log2(1024) = 10 cycles.
// ============================================================

`timescale 1ns/1ps

module tb_speedup_proof;

    localparam N = 1024;
    localparam ULP_TOL = 2048; // Higher tolerance for 1024 accumulators

    reg clk, rst_n;
    always #5 clk = ~clk;

    // --------------------------------------------------------
    // Memories
    // --------------------------------------------------------
    reg [31:0] vec [0:N-1];
    reg [31:0] expected_sum [0:0];

    // --------------------------------------------------------
    // 1. CPU / Sequential Architecture (simulated via MAC)
    // --------------------------------------------------------
    reg         seq_valid_i;
    reg  [31:0] seq_a;
    reg         seq_row_done;
    wire [31:0] seq_y;
    wire        seq_valid_o;
    
    // Using sipp_fp32_mac (a single MAC unit) to simulate the CPU sequential accumulation
    // We feed it A=vec[i] and x=1.0, so it accumulates vec[i].
    sipp_fp32_mac seq_cpu (
        .clk        (clk),
        .rst_n      (rst_n),
        .value_i    (seq_a),
        .x_elem_i   (32'h3F800000), // 1.0
        .valid_i    (seq_valid_i),
        .row_done_i (seq_row_done),
        .result_o   (seq_y),
        .result_we  (seq_valid_o)
    );

    // --------------------------------------------------------
    // 2. SIPP Parallel Architecture (N=1024 Adder Tree)
    // --------------------------------------------------------
    reg  [N*32-1:0] parallel_in;
    reg             parallel_valid_i;
    wire [31:0]     parallel_out;
    wire            parallel_valid_o;

    sipp_adder_tree #(.N(N)) sipp_parallel (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_flat  (parallel_in),
        .valid_i  (parallel_valid_i),
        .sum_o    (parallel_out),
        .valid_o  (parallel_valid_o)
    );

    // --------------------------------------------------------
    // Test Sequence
    // --------------------------------------------------------
    integer i, seq_cycles, par_cycles;
    integer seq_start, par_start;
    reg [31:0] seq_result, par_result;

    task tick; begin @(posedge clk); #1; end endtask

    initial begin
        $readmemh("test_data/speedup/vec_1024.hex", vec);
        $readmemh("test_data/speedup/expected_sum.hex", expected_sum);

        clk = 0; rst_n = 0;
        seq_valid_i = 0; seq_row_done = 0; seq_a = 0;
        parallel_valid_i = 0; parallel_in = 0;
        
        repeat(5) tick;
        rst_n = 1;
        tick;
        
        $display("\n=======================================================");
        $display("  SIPP V2.1 — 1024-Element SPEEDUP PROOF");
        $display("=======================================================\n");

        // --------------------------------------------------------
        // RUN 1: SIPP Parallel (N=1024)
        // --------------------------------------------------------
        $display("[SIPP] Packing 1024 elements into parallel bus...");
        for (i = 0; i < N; i = i+1) begin
            parallel_in[i*32 +: 32] = vec[i];
        end

        par_start = $time;
        parallel_valid_i = 1;
        tick;
        parallel_valid_i = 0;

        // Wait for result
        par_cycles = 1; // Count the insertion cycle
        while (!parallel_valid_o) begin
            tick;
            par_cycles = par_cycles + 1;
        end
        par_result = parallel_out;
        
        $display("[SIPP] Parallel Result: %08h (Expected: %08h)", par_result, expected_sum[0]);
        $display("[SIPP] >>> CYCLES TAKEN: %0d <<<", par_cycles);
        
        // --------------------------------------------------------
        // RUN 2: CPU Sequential (MAC)
        // --------------------------------------------------------
        $display("\n[CPU] Starting sequential accumulation (1 item/cycle)...");
        seq_start = $time;
        seq_cycles = 0;

        for (i = 0; i < N; i = i+1) begin
            seq_a = vec[i];
            seq_valid_i = 1;
            seq_row_done = (i == N-1) ? 1 : 0;
            tick;
            seq_valid_i = 0;
            seq_row_done = 0;
            seq_cycles = seq_cycles + 1;
        end
        
        // Wait for final result valid
        while (!seq_valid_o) begin
            tick;
            seq_cycles = seq_cycles + 1;
        end
        seq_result = seq_y;

        $display("[CPU] Sequential Result: %08h (Expected: %08h)", seq_result, expected_sum[0]);
        $display("[CPU] >>> CYCLES TAKEN: %0d <<<\n", seq_cycles);

        // --------------------------------------------------------
        // Summary
        // --------------------------------------------------------
        $display("=======================================================");
        $display("  FINAL SPEEDUP RESULTS (N = 1024 elements)");
        $display("=======================================================");
        $display("  CPU Cycles : %0d", seq_cycles);
        $display("  SIPP Cycles: %0d", par_cycles);
        $display("  Speedup    : %0dx faster!", seq_cycles / par_cycles);
        $display("=======================================================\n");

        $finish;
    end
endmodule
