// ============================================================
// fp16_pkg.sv
// SIPP V2.1 — IEEE 754 Half-Precision (FP16) Math Package
// Author: Ayush Panchal | August 2026
// ============================================================
// Task 9: Mixed Precision — FP16 + FP32
//
// FP16 Format (IEEE 754-2008):
//   bit 15    : sign
//   bits 14:10: exponent (5 bits, bias = 15)
//   bits 9:0  : mantissa (10 bits, implied leading 1)
//
// Comparison with FP32:
//   Precision: ~3.3 decimal digits (vs 7.2 for FP32)
//   Range:     6.10e-5 to 65504 (vs 1.18e-38 to 3.4e38 for FP32)
//   Area:      ~25% of FP32 (fewer LUTs for 10-bit mantissa multiply)
//   Power:     ~30% of FP32
//   Use case:  ML inference, graphics — NOT recommended for structural physics
// ============================================================

`timescale 1ns/1ps

package fp16_pkg;

    // -------------------------------------------------------
    // fp16_mul: Half-Precision Floating Point Multiply
    // -------------------------------------------------------
    function automatic [15:0] fp16_mul;
        input [15:0] a, b;
        reg        sign_a, sign_b, sign_out;
        reg  [4:0] exp_a,  exp_b;
        reg  [9:0] man_a,  man_b;
        reg  [8:0] exp_sum;
        reg [21:0] man_product;
        begin
            sign_a = a[15]; exp_a = a[14:10]; man_a = a[9:0];
            sign_b = b[15]; exp_b = b[14:10]; man_b = b[9:0];

            // Zero check
            if (a == 16'h0 || b == 16'h0) begin
                fp16_mul = 16'h0; // 0.0
            end else begin
                sign_out    = sign_a ^ sign_b;
                exp_sum     = {1'b0, exp_a} + {1'b0, exp_b} - 9'd15; // bias adjust
                man_product = {1'b1, man_a} * {1'b1, man_b}; // 22-bit result (11x11)

                // Normalize
                if (man_product[21]) begin
                    man_product = man_product >> 1;
                    exp_sum     = exp_sum + 9'd1;
                end

                // Overflow → Infinity
                if (exp_sum >= 9'd31) begin
                    fp16_mul = {sign_out, 5'h1F, 10'h0};
                end else begin
                    fp16_mul = {sign_out, exp_sum[4:0], man_product[19:10]};
                end
            end
        end
    endfunction

    // -------------------------------------------------------
    // fp16_add: Half-Precision Floating Point Add
    // -------------------------------------------------------
    function automatic [15:0] fp16_add;
        input [15:0] a, b;
        reg        sign_a, sign_b, sign_out;
        reg  [4:0] exp_a, exp_b, exp_large, e_out;
        reg  [9:0] man_a, man_b;
        reg [11:0] man_large, man_small, man_sum;
        reg  [4:0] exp_diff;
        integer    k;
        begin
            if (a == 16'h0) begin fp16_add = b; end
            else if (b == 16'h0) begin fp16_add = a; end
            else begin
                sign_a = a[15]; exp_a = a[14:10]; man_a = a[9:0];
                sign_b = b[15]; exp_b = b[14:10]; man_b = b[9:0];

                // Align to larger exponent
                if (exp_a >= exp_b) begin
                    exp_large  = exp_a; e_out = exp_a;
                    man_large  = {1'b0, 1'b1, man_a};
                    exp_diff   = exp_a - exp_b;
                    man_small  = {1'b0, 1'b1, man_b} >> exp_diff;
                    sign_out   = sign_a;
                end else begin
                    exp_large  = exp_b; e_out = exp_b;
                    man_large  = {1'b0, 1'b1, man_b};
                    exp_diff   = exp_b - exp_a;
                    man_small  = {1'b0, 1'b1, man_a} >> exp_diff;
                    sign_out   = sign_b;
                end

                // Add or subtract mantissas
                if (sign_a == sign_b) begin
                    man_sum = man_large + man_small;
                    if (man_sum[11]) begin
                        man_sum = man_sum >> 1;
                        e_out   = e_out + 5'd1;
                    end
                end else begin
                    if (man_large >= man_small) begin
                        man_sum = man_large - man_small;
                    end else begin
                        man_sum  = man_small - man_large;
                        sign_out = ~sign_out;
                    end
                    // Normalize
                    for (k = 0; k < 10; k = k+1) begin
                        if (!man_sum[10] && (e_out > 5'd0)) begin
                            man_sum = man_sum << 1;
                            e_out   = e_out - 5'd1;
                        end
                    end
                    if (man_sum == 12'h0) begin
                        fp16_add = 16'h0;
                        // Return 0
                        e_out    = 5'd0;
                        sign_out = 1'b0;
                    end
                end

                fp16_add = {sign_out, e_out, man_sum[9:0]};
            end
        end
    endfunction

endpackage
