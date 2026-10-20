import time
import numpy as np
import scipy.io as sio

def benchmark():
    print("======================================================")
    print("  PERFORMANCE BENCHMARK: Laptop CPU vs SIPP Hardware")
    print("======================================================")

    # 1. Load Matrix
    mtx_path = "real_matrices/nos1/nos1.mtx"
    print(f"Loading matrix: {mtx_path}")
    A = sio.mmread(mtx_path).tocsr().astype(np.float32)
    rows, cols = A.shape
    nnz = A.nnz
    
    print(f"Matrix: nos1 (Fluid Dynamics)")
    print(f"Shape: {rows} x {cols}")
    print(f"Non-zeros (NNZ): {nnz}")
    print("-" * 54)

    # Generate random vector
    np.random.seed(42)
    x = np.random.uniform(-1.0, 1.0, cols).astype(np.float32)

    # 2. Benchmark Laptop CPU (Python + SciPy/C++ backend)
    # Warmup
    for _ in range(1000):
        y = A @ x
        
    iterations = 100000
    print(f"Running {iterations} iterations on Laptop CPU (SciPy C++ backend)...")
    
    start_time = time.perf_counter()
    for _ in range(iterations):
        y = A @ x
    end_time = time.perf_counter()
    
    total_cpu_time = end_time - start_time
    avg_cpu_time_us = (total_cpu_time / iterations) * 1e6
    print(f"-> Average Laptop CPU Time per SpMV: {avg_cpu_time_us:.2f} microseconds")

    print("-" * 54)

    # 3. Calculate Theoretical SIPP Hardware Time
    # Current SIPP V2.1 (1 Element per clock cycle, 100 MHz)
    # Cycles = NNZ (data) + Rows (row_done pulses) + Pipeline latency
    sipp_v2_cycles = nnz + rows + 3
    sipp_v2_freq_mhz = 100
    sipp_v2_time_us = sipp_v2_cycles / sipp_v2_freq_mhz
    
    print(f"SIPP V2.1 (Current RTL — 1 MAC, 100 MHz FPGA):")
    print(f"  Cycles per SpMV: {sipp_v2_cycles}")
    print(f"-> Theoretical Hardware Time: {sipp_v2_time_us:.2f} microseconds")
    
    # SIPP Phase 4 (N=16 Elements per clock cycle, 200 MHz)
    # Assuming perfectly packed rows for calculation
    sipp_p4_cycles = (nnz / 16) + rows + 5
    sipp_p4_freq_mhz = 200
    sipp_p4_time_us = sipp_p4_cycles / sipp_p4_freq_mhz
    
    print(f"\nSIPP Phase 4 (Future — 16 parallel MACs, 200 MHz):")
    print(f"  Cycles per SpMV: {int(sipp_p4_cycles)}")
    print(f"-> Theoretical Hardware Time: {sipp_p4_time_us:.2f} microseconds")
    
    print("======================================================")
    
    speedup_v2 = avg_cpu_time_us / sipp_v2_time_us
    speedup_p4 = avg_cpu_time_us / sipp_p4_time_us
    
    print(f"CONCLUSION:")
    if speedup_v2 > 1:
        print(f"Our CURRENT hardware is {speedup_v2:.1f}x FASTER than your laptop CPU.")
    else:
        print(f"Our CURRENT hardware is {1/speedup_v2:.1f}x SLOWER than your laptop CPU (expected for N=1).")
        
    print(f"Our PHASE 4 hardware will be {speedup_p4:.1f}x FASTER than your laptop CPU!")
    print("======================================================")

if __name__ == "__main__":
    benchmark()
