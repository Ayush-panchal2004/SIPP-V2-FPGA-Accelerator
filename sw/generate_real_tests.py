import os
import struct
import numpy as np
import scipy.io as sio

def float_to_hex(f):
    """Convert float32 to IEEE 754 hex string"""
    return hex(struct.unpack('<I', struct.pack('<f', f))[0])[2:].zfill(8)

def process_matrix(matrix_name, mtx_path):
    print(f"\nProcessing {matrix_name}...")
    
    # 1. Load Matrix Market file
    if not os.path.exists(mtx_path):
        print(f"Error: {mtx_path} not found.")
        return
        
    mat = sio.mmread(mtx_path)
    A = mat.tocsr().astype(np.float32)
    rows, cols = A.shape
    nnz = A.nnz
    
    print(f"  Shape: {rows} x {cols}")
    print(f"  Non-zeros: {nnz} ({(nnz/(rows*cols))*100:.2f}% density)")
    
    # 2. Generate random dense input vector x (FP32)
    # Using specific seed for reproducibility
    np.random.seed(42)
    x = np.random.uniform(-10.0, 10.0, cols).astype(np.float32)
    
    # 3. Compute gold reference output y (FP32)
    y_expected = A @ x
    
    # 4. Export to files for SystemVerilog testbench
    os.makedirs(f"test_data/{matrix_name}", exist_ok=True)
    
    # Export CSR format: Values (A), Column Indices (col_idx), Row Pointers (row_ptr)
    with open(f"test_data/{matrix_name}/A_val.hex", "w") as f:
        for val in A.data:
            f.write(f"{float_to_hex(val)}\n")
            
    with open(f"test_data/{matrix_name}/A_col_idx.hex", "w") as f:
        for idx in A.indices:
            f.write(f"{hex(idx)[2:].zfill(8)}\n")
            
    with open(f"test_data/{matrix_name}/A_row_ptr.hex", "w") as f:
        for ptr in A.indptr:
            f.write(f"{hex(ptr)[2:].zfill(8)}\n")
            
    # Export vectors x and y
    with open(f"test_data/{matrix_name}/x_val.hex", "w") as f:
        for val in x:
            f.write(f"{float_to_hex(val)}\n")
            
    with open(f"test_data/{matrix_name}/y_expected.hex", "w") as f:
        for val in y_expected:
            f.write(f"{float_to_hex(val)}\n")
            
    print(f"  Successfully exported to test_data/{matrix_name}/")
    print(f"  Sample first 3 expected outputs: {y_expected[:3]}")

if __name__ == "__main__":
    process_matrix("bcsstk01", "real_matrices/bcsstk01/bcsstk01.mtx")
    process_matrix("nos1", "real_matrices/nos1/nos1.mtx")
