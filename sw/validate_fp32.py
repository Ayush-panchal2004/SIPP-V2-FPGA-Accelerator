#!/usr/bin/env python3
# ==============================================================
# validate_fp32.py
# SIPP V2.0 — FP32 Reference Validator
# Author: Ayush Panchal | August 2026
# ==============================================================
# Generates random sparse matrices, computes SpMV using scipy
# (the gold reference), and compares against SIPP hardware output.
#
# Usage:
#   python validate_fp32.py               → run validation
#   python validate_fp32.py --gen-only    → only print test vectors
# ==============================================================

import numpy as np
import struct
import argparse
import sys

# ---------------------------------------------------------------
# IEEE 754 utilities
# ---------------------------------------------------------------
def float_to_fp32_hex(f: float) -> str:
    """Convert Python float to 32-bit IEEE 754 hex string."""
    bits = struct.unpack('>I', struct.pack('>f', f))[0]
    return f"32'h{bits:08X}"

def fp32_hex_to_float(hex_val: int) -> float:
    """Convert raw 32-bit integer to Python float."""
    return struct.unpack('>f', struct.pack('>I', hex_val & 0xFFFFFFFF))[0]

# ---------------------------------------------------------------
# Test Case Generator
# ---------------------------------------------------------------
def generate_test_case(rows: int, cols: int, density: float, seed: int):
    """
    Generate a random sparse matrix A and dense vector x.
    Returns: (A_dense, x, expected_y = A @ x)
    """
    rng = np.random.default_rng(seed)

    # Generate sparse matrix (random values, controlled density)
    mask = rng.random((rows, cols)) < density
    A = np.where(mask, rng.uniform(-10.0, 10.0, (rows, cols)), 0.0).astype(np.float32)
    x = rng.uniform(-5.0, 5.0, cols).astype(np.float32)

    # Gold reference: y = A @ x (scipy/numpy float32)
    y = A @ x

    return A, x, y

# ---------------------------------------------------------------
# CSR Encoder
# ---------------------------------------------------------------
def to_csr(A: np.ndarray):
    """Convert dense matrix to CSR (values, col_idx, row_ptr)."""
    rows, cols = A.shape
    values, col_idx, row_ptr = [], [], [0]

    for i in range(rows):
        for j in range(cols):
            if A[i, j] != 0.0:
                values.append(A[i, j])
                col_idx.append(j)
        row_ptr.append(len(values))

    return (np.array(values, dtype=np.float32),
            np.array(col_idx, dtype=np.int32),
            np.array(row_ptr, dtype=np.int32))

# ---------------------------------------------------------------
# Validation
# ---------------------------------------------------------------
def validate_case(A, x, expected_y, hw_results=None):
    """
    Compare hardware output to numpy reference.
    hw_results: list of raw 32-bit integers from simulation (optional)
    """
    rows = A.shape[0]
    values, col_idx, row_ptr = to_csr(A)
    nnz = len(values)

    print(f"\n  Matrix: {A.shape[0]}×{A.shape[1]}, NNZ={nnz}, "
          f"density={nnz/(A.shape[0]*A.shape[1]):.1%}")
    print(f"  Vector x: {x}")

    if hw_results is not None:
        # Compare hardware vs reference
        passes, fails = 0, 0
        for i in range(rows):
            ref = expected_y[i]
            hw  = fp32_hex_to_float(hw_results[i])
            err = abs(hw - ref) / (abs(ref) + 1e-9)
            status = "PASS" if err < 1e-4 else "FAIL"
            if status == "PASS":
                passes += 1
            else:
                fails += 1
            print(f"  Row {i:3d}: ref={ref:12.5f}  hw={hw:12.5f}  "
                  f"rel_err={err:.2e}  [{status}]")
        print(f"\n  Summary: {passes} PASS / {fails} FAIL")
        return fails == 0
    else:
        # Just print reference results and test vectors
        print(f"\n  Reference output y = A @ x:")
        for i, yi in enumerate(expected_y):
            print(f"  y[{i}] = {yi:12.5f}  ({float_to_fp32_hex(yi)})")
        return True

# ---------------------------------------------------------------
# Print SystemVerilog Test Vectors
# ---------------------------------------------------------------
def print_sv_vectors(A, x, expected_y):
    """Print test vectors in SystemVerilog format for copy-paste into testbench."""
    values, col_idx, row_ptr = to_csr(A)

    print("\n  // ---- Copy into testbench ----")
    print(f"  // Matrix {A.shape[0]}×{A.shape[1]}")
    print(f"  localparam int NNZ      = {len(values)};")
    print(f"  localparam int NUM_ROWS = {A.shape[0]};")
    print()
    print(f"  reg [31:0] values   [0:{len(values)-1}] = {{")
    vals_hex = [float_to_fp32_hex(v) for v in values]
    print("    " + ", ".join(vals_hex))
    print("  };")
    print()
    print(f"  reg [31:0] x_vec    [0:{A.shape[1]-1}] = {{")
    x_hex = [float_to_fp32_hex(xi) for xi in x]
    print("    " + ", ".join(x_hex))
    print("  };")
    print()
    print(f"  reg [31:0] expected [0:{A.shape[0]-1}] = {{")
    y_hex = [float_to_fp32_hex(yi) for yi in expected_y]
    print("    " + ", ".join(y_hex))
    print("  };")
    print("  // ---- End test vectors ----")

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="SIPP V2 FP32 Reference Validator")
    parser.add_argument("--rows",     type=int,   default=8,    help="Matrix rows")
    parser.add_argument("--cols",     type=int,   default=8,    help="Matrix cols")
    parser.add_argument("--density",  type=float, default=0.4,  help="Sparsity density")
    parser.add_argument("--seed",     type=int,   default=42,   help="RNG seed")
    parser.add_argument("--gen-only", action="store_true",      help="Only print vectors")
    parser.add_argument("--tests",    type=int,   default=5,    help="Number of test cases")
    args = parser.parse_args()

    print("=" * 55)
    print("  SIPP V2.0 — FP32 Reference Validator")
    print("=" * 55)

    total_pass, total_fail = 0, 0

    for t in range(args.tests):
        print(f"\n--- Test Case {t+1}/{args.tests} (seed={args.seed + t}) ---")
        A, x, y = generate_test_case(
            rows=args.rows,
            cols=args.cols,
            density=args.density,
            seed=args.seed + t
        )

        if args.gen_only:
            print_sv_vectors(A, x, y)
        else:
            validate_case(A, x, y, hw_results=None)
            total_pass += 1

    print(f"\n{'='*55}")
    print(f"  Validation complete: {total_pass} cases generated")
    print(f"{'='*55}\n")

if __name__ == "__main__":
    main()
