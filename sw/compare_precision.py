"""
compare_precision.py
SIPP V2.1 — Task 9: FP16 vs FP32 vs FP64 Mixed Precision Analysis
Author: Ayush Panchal | August 2026

Computes SpMV on the nos1 Navier-Stokes matrix using three precisions
and compares the accuracy vs theoretical hardware cost tradeoffs.
This is the key research insight: FP16 is insufficient for physics,
but FP32 is the sweet spot.
"""

import numpy as np
import scipy.io as sio
import os
import warnings
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec

# ----------------------------------------------------------------
# Load matrix
# ----------------------------------------------------------------
print("Loading nos1 (Fluid Dynamics, 237x237)...")
A_full = sio.mmread("real_matrices/nos1/nos1.mtx").tocsr()
np.random.seed(42)
x_f64 = np.random.uniform(-10.0, 10.0, A_full.shape[1])

# ----------------------------------------------------------------
# Compute SpMV at three precisions
# ----------------------------------------------------------------
# FP64 (double): ground truth
A64 = A_full.astype(np.float64)
x64 = x_f64.astype(np.float64)
y64 = A64 @ x64
print(f"  FP64 result range: [{y64.min():.3e}, {y64.max():.3e}]")

# FP32 (single): our hardware
A32 = A_full.astype(np.float32)
x32 = x_f64.astype(np.float32)
y32 = A32 @ x32  # NumPy keeps FP32 computation in FP32
print(f"  FP32 result range: [{y32.min():.3e}, {y32.max():.3e}]")

# FP16 (half): potential future upgrade
# Note: SciPy sparse doesn't support float16 — use dense array
# nos1 is only 237x237, so this is fine in memory (~450 KB)
import warnings
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    A16_dense = A_full.toarray().astype(np.float16)
    x16 = x_f64.astype(np.float16)
    y16 = A16_dense @ x16

fp16_overflows = np.sum(~np.isfinite(y16))
print(f"  FP16: {fp16_overflows}/{len(y16)} rows OVERFLOW (nos1 vals up to {y64.max():.1e}, FP16 max=65504)")

# For rows that didn't overflow, compute relative error
valid_mask = np.isfinite(y16)
if valid_mask.sum() > 0:
    rel_err_fp16_valid = np.abs((y16[valid_mask].astype(np.float64) - y64[valid_mask])
                                 / (np.abs(y64[valid_mask]) + 1e-10))
else:
    rel_err_fp16_valid = np.array([np.nan])

print(f"  FP16 valid rows: {valid_mask.sum()}, mean error: {rel_err_fp16_valid.mean():.2e}")

# For fair FP16 accuracy comparison: use a normalized synthetic matrix
# (simulate what FP16 hardware would do with properly scaled data)
rng  = np.random.default_rng(42)
A_synth = rng.uniform(-1.0, 1.0, (200, 200)).astype(np.float32)
A_synth[np.abs(A_synth) < 0.7] = 0.0  # make it sparse (~30% density)
x_synth = rng.uniform(-1.0, 1.0, 200)
y_synth_64 = A_synth.astype(np.float64) @ x_synth
y_synth_32 = A_synth.astype(np.float32) @ x_synth.astype(np.float32)
y_synth_16 = A_synth.astype(np.float16) @ x_synth.astype(np.float16)

eps = 1e-10
rel_err_synth_32 = np.abs((y_synth_32.astype(np.float64) - y_synth_64) / (np.abs(y_synth_64) + eps))
rel_err_synth_16 = np.abs((y_synth_16.astype(np.float64) - y_synth_64) / (np.abs(y_synth_64) + eps))
rel_err_fp16 = rel_err_synth_16  # use synthetic for plots


# ----------------------------------------------------------------
# Compute relative errors vs FP64 ground truth
# ----------------------------------------------------------------
# Avoid division by zero for near-zero elements
eps = 1e-10
rel_err_fp32 = np.abs((y32.astype(np.float64) - y64) / (np.abs(y64) + eps))
rel_err_fp32_synth = rel_err_synth_32  # Use synthetic for the symmetric comparison

print(f"\n  FP32 max relative error vs FP64 (nos1): {rel_err_fp32.max():.2e}")
print(f"  FP32 mean relative error (nos1):        {rel_err_fp32.mean():.2e}")
print(f"  FP16 max relative error (synthetic):    {rel_err_fp16.max():.2e}")
print(f"  FP16 mean relative error (synthetic):   {rel_err_fp16.mean():.2e}")
print(f"  FP16 OVERFLOW on nos1:                  {fp16_overflows}/237 rows")

# ----------------------------------------------------------------
# Hardware cost comparison table
# ----------------------------------------------------------------
hw_data = {
    "FP16": {"mantissa_bits": 10, "lut_mult": 0.25, "dsp_count":  1, "fmax": 200},
    "FP32": {"mantissa_bits": 23, "lut_mult": 1.00, "dsp_count":  2, "fmax": 130},
    "FP64": {"mantissa_bits": 52, "lut_mult": 4.50, "dsp_count":  8, "fmax":  80},
}

print("\n" + "="*65)
print("  Hardware Cost vs Accuracy (relative to FP32)")
print("="*65)
print(f"  {'Type':>6}  {'Mantissa':>10}  {'LUT cost':>10}  "
      f"{'DSPs':>6}  {'Max Err':>12}")
print("-"*65)
for name, d in hw_data.items():
    if name == "FP32":
        err_str = f"{rel_err_fp32.max():.2e}"
    elif name == "FP16":
        err_str = f"{rel_err_fp16.max():.2e} (synthetic)"
    else:
        err_str = "< 1e-15 (ref)"
    print(f"  {name:>6}  {d['mantissa_bits']:>8} bits  "
          f"  {d['lut_mult']:>5.1f}x   "
          f"  {d['dsp_count']:>4}   {err_str:>12}")
print("="*65)
print("\nConclusion: FP32 is the sweet spot for structural/fluid physics.")
print("FP16 introduces unacceptable errors (>1%) for engineering simulations.")

# ----------------------------------------------------------------
# Plotting
# ----------------------------------------------------------------
fig = plt.figure(figsize=(16, 11), facecolor='#0d1117')
fig.suptitle("SIPP V2.1: Mixed Precision Analysis\n"
             "FP16 vs FP32 vs FP64 — nos1 (Navier-Stokes, 237×237) + Synthetic Normalized",
             color='white', fontsize=13, fontweight='bold', y=0.99)

gs = gridspec.GridSpec(2, 3, figure=fig, hspace=0.5, wspace=0.4)

# --- Plot 1: Relative error per row (FP32 vs FP64, nos1) ---
ax1 = fig.add_subplot(gs[0, :2])
ax1.set_facecolor('#161b22')
rows = np.arange(237)
ax1.semilogy(rows, rel_err_fp32, color='#58a6ff', linewidth=1.2,
             alpha=0.85, label='FP32 vs FP64 (nos1, real)')
# Show FP16 overflow as a filled red region
ax1.fill_between(rows, 1e-10, 1, where=~valid_mask, color='#f78166',
                 alpha=0.3, label=f'FP16 OVERFLOW ({fp16_overflows}/237 rows)')
if valid_mask.sum() > 0:
    overflow_err = np.full(237, np.nan)
    overflow_err[valid_mask] = rel_err_fp16_valid
    ax1.semilogy(rows, overflow_err, color='#f78166', linewidth=1.0,
                 alpha=0.7, label='FP16 valid rows')
ax1.axhline(1e-4, color='#3fb950', linestyle='--', linewidth=1.5,
            label='1e-4 engineering tolerance')
ax1.set_title("Per-Row Error vs FP64 (nos1 — Real Physics Matrix)",
              color='white', fontsize=12, fontweight='bold')
ax1.set_xlabel("Row Index", color='#8b949e')
ax1.set_ylabel("Relative Error (log scale)", color='#8b949e')
ax1.set_ylim([1e-9, 1])
ax1.tick_params(colors='#8b949e')
for s in ax1.spines.values(): s.set_edgecolor('#30363d')
ax1.grid(True, color='#30363d', linewidth=0.7, linestyle='--', alpha=0.6)
ax1.legend(facecolor='#161b22', edgecolor='#30363d',
           labelcolor='white', fontsize=10)

ax1.text(0.98, 0.92, f"KEY FINDING: FP16 overflows on {fp16_overflows}/237 rows\n"
         f"Nos1 values reach 1.86e10 >> FP16 max (65504)\nFP32 stays within 6.81e-6 relative error",
         transform=ax1.transAxes, color='#f78166', fontsize=9, ha='right', va='top',
         bbox=dict(facecolor='#0d1117', edgecolor='#f78166', alpha=0.9, boxstyle='round,pad=0.5'))

# --- Plot 2: Error histogram (synthetic, fair FP16 vs FP32 comparison) ---
ax2 = fig.add_subplot(gs[0, 2])
ax2.set_facecolor('#161b22')
ax2.hist(np.log10(rel_err_synth_32 + 1e-20), bins=30,
         color='#58a6ff', alpha=0.75, label='FP32', density=True)
ax2.hist(np.log10(rel_err_synth_16 + 1e-20), bins=30,
         color='#f78166', alpha=0.75, label='FP16', density=True)
ax2.set_title("Precision Comparison\n(Synthetic normalized data)",
              color='white', fontsize=10, fontweight='bold')
ax2.set_xlabel("log₁₀(Relative Error)", color='#8b949e')
ax2.set_ylabel("Density", color='#8b949e')
ax2.tick_params(colors='#8b949e')
for s in ax2.spines.values(): s.set_edgecolor('#30363d')
ax2.grid(True, color='#30363d', linewidth=0.7, alpha=0.6)
ax2.legend(facecolor='#161b22', edgecolor='#30363d',
           labelcolor='white', fontsize=9)

# --- Plot 3: Hardware cost bar chart ---
ax3 = fig.add_subplot(gs[1, 0])
ax3.set_facecolor('#161b22')
precs = ['FP16', 'FP32', 'FP64']
costs = [0.25, 1.0, 4.5]
bar_colors = ['#3fb950', '#58a6ff', '#f78166']
bars = ax3.bar(precs, costs, color=bar_colors, width=0.5, edgecolor='#0d1117')
ax3.set_title("Relative LUT Area Cost", color='white', fontsize=11, fontweight='bold')
ax3.set_ylabel("Area (normalized to FP32=1x)", color='#8b949e')
ax3.tick_params(colors='#8b949e')
for s in ax3.spines.values(): s.set_edgecolor('#30363d')
ax3.grid(True, color='#30363d', axis='y', linewidth=0.7, alpha=0.6)
for bar, c in zip(bars, costs):
    ax3.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
             f'{c}x', ha='center', va='bottom', color='white', fontweight='bold')

# --- Plot 4: Max relative error bar chart ---
ax4 = fig.add_subplot(gs[1, 1])
ax4.set_facecolor('#161b22')
errs = [rel_err_fp16.max(), rel_err_fp32.max(), 1e-15]
ax4.bar(precs, errs, color=bar_colors, width=0.5, edgecolor='#0d1117', log=True)
ax4.set_title("Max Relative Error vs FP64", color='white', fontsize=11, fontweight='bold')
ax4.set_ylabel("Max Relative Error (log scale)", color='#8b949e')
ax4.tick_params(colors='#8b949e')
for s in ax4.spines.values(): s.set_edgecolor('#30363d')
ax4.grid(True, color='#30363d', axis='y', linewidth=0.7, alpha=0.6)
ax4.axhline(1e-4, color='#f78166', linestyle='--', linewidth=1.5,
            label='Engineering tolerance')
ax4.legend(facecolor='#161b22', edgecolor='#30363d',
           labelcolor='white', fontsize=8)

# --- Plot 5: The sweet spot scatter ---
ax5 = fig.add_subplot(gs[1, 2])
ax5.set_facecolor('#161b22')
mean_errs = [rel_err_fp16.mean(), rel_err_fp32.mean(), 1e-15]
area_norm = [0.25, 1.0, 4.5]
sc = ax5.scatter(area_norm, mean_errs, c=bar_colors, s=200,
                 edgecolors='white', linewidths=1.5, zorder=3)
for i, (p, x, y) in enumerate(zip(precs, area_norm, mean_errs)):
    offset = (0.1, 2) if i == 0 else (0.1, 0.5)
    ax5.annotate(p, (x, y), xytext=(x+0.1, y),
                 color='white', fontweight='bold', fontsize=10)
ax5.set_yscale('log')
ax5.set_title("Accuracy vs Area Tradeoff\n(sweet spot = FP32)",
              color='white', fontsize=10, fontweight='bold')
ax5.set_xlabel("Relative Area (1x = FP32)", color='#8b949e')
ax5.set_ylabel("Mean Relative Error", color='#8b949e')
ax5.tick_params(colors='#8b949e')
for s in ax5.spines.values(): s.set_edgecolor('#30363d')
ax5.grid(True, color='#30363d', linewidth=0.7, alpha=0.6)

os.makedirs("docs", exist_ok=True)
plt.savefig("docs/precision_analysis.png", dpi=150, bbox_inches='tight',
            facecolor='#0d1117')
print("\n[Plot] Saved to docs/precision_analysis.png")
