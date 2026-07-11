//=============================================================================
// Module : top
// Description : Full pipeline - UART RX -> RX FIFO -> Sobel -> TX FIFO -> UART TX
//
// Pipeline overview:
//   PC --[UART RX]--> RX_FIFO (2048B) --> sobel_top --> TX_FIFO (4096B) --> [UART TX] --> PC
//
// Image parameters (must match Python sender):
//   - Send a 130x130 padded grayscale image (16900 bytes)
//   - Sobel output: 128x128 = 16384 bytes
//
// FIFO sizing (v4 - increased to fix TX overflow):
//   RX FIFO : 2048 deep - handles burst from PC at 115200 baud
//   TX FIFO : 4096 deep - large enough to buffer a full row burst from Sobel
//
// Root cause of data loss in v3:
//   Sobel runs at 100MHz, UART TX drains at ~11520 bytes/sec (115200 baud).
//   Speed ratio = 100,000,000 / (115200 * 10) = ~868x
//   So Sobel produces pixels ~868x faster than UART can send them.
//   Backpressure pauses Sobel correctly, BUT there is a 2-cycle pipeline
//   delay between tx_fifo_full asserting and Sobel actually stopping.
//   During those 2 cycles, 2 pixels can still enter a full FIFO and get
//   dropped. Over 16384 pixels this accumulates to visible data loss.
//
// Fix: increase TX FIFO to 4096. At 115200 baud the FIFO drains at
//   ~11520 bytes/sec. With 4096 entries, it can hold ~355ms of output
//   before filling, giving backpressure plenty of time to react.
//
// Target Board : Boolean Board (Spartan-7 XC7S50)
// Clock        : 100 MHz
// UART         : 115200 baud, 8N1
//=============================================================================
module top #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       uart_rx,
    output wire       uart_tx,
    output reg  [7:0] led
);

    //=========================================================================
    // Auto-reset: hold rst HIGH for ~100 us after power-up
    //=========================================================================
    reg [15:0] rst_counter   = 16'd0;
    reg        rst_internal  = 1'b1;

    always @(posedge clk) begin
        if (rst_counter < 16'd10000) begin
            rst_counter  <= rst_counter + 1'b1;
            rst_internal <= 1'b1;
        end else begin
            rst_internal <= 1'b0;
        end
    end

    wire rst = rst_internal;

    //=========================================================================
    // Wire declarations - ALL declared before use (fixes Synth 8-6901)
    //=========================================================================
    wire [7:0] rx_data;
    wire       rx_done;

    wire [7:0] rx_fifo_dout;
    wire       rx_fifo_full;
    wire       rx_fifo_empty;

    wire [7:0] tx_fifo_dout;   // declared early so tx_fifo_full visible to RX drain
    wire       tx_fifo_full;
    wire       tx_fifo_empty;

    wire [7:0] sobel_pixel_out;
    wire       sobel_valid_out;

    wire       tx_busy;

    //=========================================================================
    // Registers
    //=========================================================================
    reg        rx_fifo_rd_en  = 1'b0;
    reg        sobel_valid_in = 1'b0;
    reg        rd_en_d1       = 1'b0;

    reg        tx_fifo_rd_en  = 1'b0;
    reg        tx_rd_en_d1    = 1'b0;
    reg [7:0]  tx_data        = 8'h00;
    reg        tx_start       = 1'b0;

    //=========================================================================
    // UART RX
    //=========================================================================
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk      (clk),
        .rst      (rst),
        .rx       (uart_rx),
        .rx_data  (rx_data),
        .rx_done  (rx_done)
    );

    //=========================================================================
    // RX FIFO - increased to 2048 for reliable burst absorption
    //=========================================================================
    fifo #(
        .DEPTH (2048),
        .WIDTH (8)
    ) u_rx_fifo (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (rx_done && !rx_fifo_full),
        .din    (rx_data),
        .rd_en  (rx_fifo_rd_en),
        .dout   (rx_fifo_dout),
        .full   (rx_fifo_full),
        .empty  (rx_fifo_empty)
    );

    //=========================================================================
    // RX FIFO drain + Sobel feed
    //
    // BACKPRESSURE: stop feeding Sobel when TX FIFO is full.
    // Pausing at the source (before pixel enters Sobel) keeps
    // the line-buffer state consistent across the pause.
    //
    // Timing: FIFO output is registered - 1 cycle latency
    //   Cycle N   : rx_fifo_rd_en = 1 (pop issued)
    //   Cycle N+1 : rx_fifo_dout valid -> sobel_valid_in = 1
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            rx_fifo_rd_en  <= 1'b0;
            rd_en_d1       <= 1'b0;
            sobel_valid_in <= 1'b0;
        end else begin
            rx_fifo_rd_en <= 1'b0;
            if (!rx_fifo_empty && !tx_fifo_full) begin
                rx_fifo_rd_en <= 1'b1;
            end
            rd_en_d1       <= rx_fifo_rd_en;
            sobel_valid_in <= rd_en_d1;
        end
    end

    //=========================================================================
    // Sobel Edge Detector
    //=========================================================================
    sobel_top #(
        .IMG_W (130),
        .OUT_W (128)
    ) u_sobel (
        .clk       (clk),
        .rst_n     (~rst),
        .pixel_in  (rx_fifo_dout),
        .valid_in  (sobel_valid_in),
        .sobel_out (sobel_pixel_out),
        .valid_out (sobel_valid_out)
    );

    //=========================================================================
    // TX FIFO - increased to 4096 to prevent overflow
    //
    // Why 4096:
    //   Sobel outputs 128x128 = 16384 pixels total.
    //   UART drains at 11520 bytes/sec @ 115200 baud.
    //   Without a large TX FIFO, backpressure asserts too late
    //   (2-cycle pipeline delay) and pixels get dropped.
    //   4096 entries = ~355ms drain time = safe margin for
    //   backpressure to propagate and pause Sobel cleanly.
    //=========================================================================
    fifo #(
        .DEPTH (4096),
        .WIDTH (8)
    ) u_tx_fifo (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (sobel_valid_out && !tx_fifo_full),
        .din    (sobel_pixel_out),
        .rd_en  (tx_fifo_rd_en),
        .dout   (tx_fifo_dout),
        .full   (tx_fifo_full),
        .empty  (tx_fifo_empty)
    );

    //=========================================================================
    // UART TX
    //=========================================================================
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_tx),
        .tx_busy  (tx_busy)
    );

    //=========================================================================
    // TX FIFO drain -> UART TX controller
    //
    // Timing: FIFO output is registered - 1 cycle latency
    //   Cycle N   : tx_fifo_rd_en = 1
    //   Cycle N+1 : tx_fifo_dout valid -> latch tx_data, assert tx_start
    //
    // Guard (!tx_rd_en_d1) prevents double-pop while first pop
    // data is still in-flight to the UART.
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            tx_fifo_rd_en <= 1'b0;
            tx_rd_en_d1   <= 1'b0;
            tx_start      <= 1'b0;
            tx_data       <= 8'h00;
            led           <= 8'h00;
        end else begin
            tx_start      <= 1'b0;
            tx_fifo_rd_en <= 1'b0;

            if (!tx_fifo_empty && !tx_busy && !tx_rd_en_d1) begin
                tx_fifo_rd_en <= 1'b1;
            end

            tx_rd_en_d1 <= tx_fifo_rd_en;

            if (tx_rd_en_d1) begin
                tx_data  <= tx_fifo_dout;
                tx_start <= 1'b1;
                led      <= tx_fifo_dout;
            end
        end
    end

endmodule