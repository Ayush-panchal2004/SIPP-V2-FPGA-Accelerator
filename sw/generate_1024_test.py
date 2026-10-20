"""
generate_1024_test.py
SIPP V2.1 — Speedup Proof (1024 elements)
Author: Ayush Panchal | August 2026

Generates 1024 random FP32 numbers and computes their sum
to prove the O(log N) vs O(N) scaling of SIPP vs CPU.
"""

import numpy as np
import struct
import os

def float_to_hex(f):
    return format(struct.unpack('<I', struct.pack('<f', f))[0], '08x')

os.makedirs("test_data/speedup", exist_ok=True)

# Generate 1024 random numbers
np.random.seed(42)
vec = np.random.uniform(-1.0, 1.0, 1024).astype(np.float32)

# Compute sequential sum (CPU style)
cpu_sum = np.float32(0.0)
for v in vec:
    cpu_sum += v

print(f"Generated 1024 elements. CPU Expected Sum: {cpu_sum}")

with open("test_data/speedup/vec_1024.hex", "w") as f:
    for v in vec:
        f.write(float_to_hex(v) + "\n")

with open("test_data/speedup/expected_sum.hex", "w") as f:
    f.write(float_to_hex(cpu_sum) + "\n")
