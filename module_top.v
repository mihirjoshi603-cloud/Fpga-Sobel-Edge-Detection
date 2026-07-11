
//
// Fix: increase TX FIFO to 4096. At 115200 baud the FIFO drains at
// ~11520 bytes/sec. With 4096 entries, it can hold ~355ms of output
// before filling, giving backpressure plenty of time to react.
//
// Target Board : Boolean Board (Spartan-7 XC7S50)
// Clock : 100 MHz
// UART : 115200 baud, 8N1
//

module top #(
parameter CLK_FREQ = 100_000_000,
parameter BAUD_RATE = 115200
)(
input wire clk,
input wire uart_rx,
output wire uart_tx,
output reg [7:0] led
);
//
=========================================================================
// Auto-reset: hold rst HIGH for ~100 μs after power-up
//
=========================================================================
reg [15:0] rst_counter = 16'd0;
reg rst_internal = 1'b1;
always @(posedge clk) begin
if (rst_counter < 16'd10000) begin
rst_counter <= rst_counter + 1'b1;
rst_internal <= 1'b1;
end else begin
rst_internal <= 1'b0;
end
end
wire rst = rst_internal;
//
=========================================================================
// Wire declarations - ALL declared before use (fixes Synth 8-6901)
//
=========================================================================
wire [7:0] rx_data;
wire rx_done;
wire [7:0] rx_fifo_dout;
wire rx_fifo_full;
wire rx_fifo_empty;
wire [7:0] tx_fifo_dout; // declared early so tx_fifo_full visible to RX drain
wire tx_fifo_full;
wire tx_fifo_empty;
wire [7:0] sobel_pixel_out;
wire sobel_valid_out;
wire tx_busy;
//
=========================================================================
// Registers
//
=========================================================================
reg rx_fifo_rd_en = 1'b0;
reg sobel_valid_in = 1'b0;
reg rd_en_d1 = 1'b0;
reg tx_fifo_rd_en = 1'b0;
reg tx_rd_en_d1 = 1'b0;
reg [7:0] tx_data = 8'h00;
reg tx_start = 1'b0;