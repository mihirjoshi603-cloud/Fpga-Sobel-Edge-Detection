# FPGA Real-Time Sobel Edge Detection

A real-time image processing pipeline implementing Sobel edge detection on a 
Xilinx Spartan-7 FPGA (Digilent Boolean board), with UART-based image streaming 
from a Python host.

## Overview
This system streams padded grayscale images over UART from a Python host to the 
FPGA, where they're processed through a Sobel edge detection filter in real time, 
then streamed back to the host via UART.

## Architecture
- **UART RX**: receives incoming pixel stream from Python host
- **Line Buffer (BRAM)**: stores rows needed for 3x3 Sobel convolution window
- **Sobel Filter Pipeline**: computes gradient magnitude for edge detection
- **TX FIFO**: buffers processed pixels for UART transmission back to host
- **UART TX**: streams output image back to Python host

## Key Bugs Found & Fixed
Both simulation and real hardware testing surfaced significant bugs:

**Testbench-level:**
- Integer counter race condition from non-blocking assignment misuse
- UART RX back-to-back byte timing violation
- TX FIFO drain controller missing falling-edge detection
- Insufficient latency margin in Sobel pipeline timing

**Real hardware (post-simulation):**
- TX FIFO overflow — Sobel filter processes ~868× faster than UART TX can drain, 
  requiring FIFO depth increase to 16384 plus an in-flight pixel tracker
- Stale BRAM line buffer contents — synchronous reset on Spartan-7 doesn't clear 
  BRAM, fixed by sending dummy flush rows from the Python host at start
- `tx_busy` falling-edge race condition in the top-level UART TX control logic

## Files
- `sobel_top.v` — Sobel edge detection pipeline
- `Top_1.v` — Top-level module integrating Sobel pipeline with UART
- `uart_rx.v` — UART receiver module
- `uart_tx.v` — UART transmitter module
- `tb_top.v` — Testbench for full pipeline verification
- `sobel_work.xdc` — Board constraints file (Digilent Boolean, Spartan-7)

## Tools Used
- Verilog
- Xilinx Vivado (simulation & synthesis)
- Digilent Boolean board (Xilinx Spartan-7 XC7S50)

## Author
Madhukar — VLSI/RTL Design Engineer | BE ENTC, PICT
