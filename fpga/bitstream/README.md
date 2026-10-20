# SIPP V2 Hardware Handoff & Bitstream Artifacts

This directory contains the verified, lab-tested hardware handoff files generated in Xilinx Vivado for the **PYNQ-Z2** (Xilinx Zynq-7000 SoC, `xc7z020clg400-1`).

## Files Overview

| File | Size | Description |
| :--- | :--- | :--- |
| **`design_1_V4.bit`** | ~4.05 MB | Full FPGA fabric bitstream containing the AXI4-Stream `sipp_v2_axis_wrapper`, AXI DMA engine, and ZYNQ7 Processing System interconnect. |
| **`design_1_V4.hwh`** | ~290 KB | Hardware Handoff XML file consumed by the PYNQ framework (`pynq.Overlay`) to map registers, DMA channels, and base memory addresses. |

## Target Specifications

- **Device Part:** `xc7z020clg400-1`
- **Board Target:** Tul PYNQ-Z2
- **Interface:** AXI4-Stream (`s_axis` 256-bit input, `m_axis` 32-bit output)
- **DMA Configuration:** Direct Register Mode (Scatter-Gather disabled for low latency)
- **Fabric Clock:** 100 MHz (`FCLK_CLK0`)

## Usage via Python (PYNQ Framework)

```python
from pynq import Overlay, allocate
import numpy as np

# Load hardware overlay
overlay = Overlay("design_1_V4.bit")
dma = overlay.axi_dma_0

# Allocate contiguous DMA buffers
input_buffer = allocate(shape=(4,), dtype=np.uint64)
output_buffer = allocate(shape=(1,), dtype=np.uint32)

# Pack inputs (upper 32-bit = x_elem, lower 32-bit = mat_val)
# Trigger DMA transfer
dma.sendchannel.transfer(input_buffer)
dma.recvchannel.transfer(output_buffer)
dma.sendchannel.wait()
dma.recvchannel.wait()
```
