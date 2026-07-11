`timescale 1ns / 1ps
//=============================================================================
// Testbench : tb_top
// DUT       : top (UART RX -> RX FIFO -> Sobel -> TX FIFO -> UART TX)
//
// What it does:
//   1. Builds a 130x130 synthetic test image (ramp pattern) in memory.
//   2. Bit-bangs it into uart_rx, byte by byte, back-to-back - exactly
//      the way the PC-side Python sender behaves.
//   3. In parallel, listens on uart_tx and decodes each received byte.
//   4. Counts bytes in vs bytes out, flags any drop/mismatch.
//   5. Dumps the received image to sobel_output.hex for offline
//      comparison against a reference Sobel result.
//
// Runtime note:
//   CLKS_PER_BIT = 100MHz / 115200 = 868
//   Each byte = 10 bit-periods (start+8 data+stop) = 8680 cycles
//   16900 input bytes * 8680 cycles * 10ns/cycle = ~1.47 seconds
//   simulated time just for the RX stream. TX trails at the same baud
//   rate, so total completion lands close to that same ~1.5s mark.
//   This is a LONG behavioral sim (~147M cycles) - expect several
//   minutes of real wall-clock time in xsim. That's expected for a
//   true end-to-end pipeline test, not a bug.
//
// Faster sanity-check tip: instantiate top with a much higher
// BAUD_RATE (e.g. 25_000_000) to shrink CLKS_PER_BIT and cut sim
// time ~200x while debugging logic, before running the real
// 115200-baud version as your final sign-off test.
//=============================================================================
module tb_top;

    // ------------------------------------------------------------------
    // Parameters - MUST match top.v / sobel_top.v
    // ------------------------------------------------------------------
    localparam CLK_FREQ     = 100_000_000;
    localparam BAUD_RATE    = 115200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;   // ~868

    localparam IMG_W      = 130;
    localparam OUT_W      = 128;
    localparam IMG_BYTES  = IMG_W * IMG_W;   // 16900
    localparam OUT_BYTES  = OUT_W * OUT_W;   // 16384

    // ------------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------------
    reg        clk;
    reg        uart_rx;
    wire       uart_tx;
    wire [7:0] led;

    top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk     (clk),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .led     (led)
    );

    // ------------------------------------------------------------------
    // Clock - 100 MHz, 10ns period
    // ------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Test image (input) and capture buffer (output)
    // ------------------------------------------------------------------
    reg [7:0] image_mem [0:IMG_BYTES-1];
    reg [7:0] out_mem   [0:OUT_BYTES-1];

    integer rx_byte_count;   // bytes sent into uart_rx
    integer tx_byte_count;   // bytes received from uart_tx

    // Build a synthetic ramp test image.
    // Swap this for $readmemh("real_image.hex", image_mem); to test
    // with an actual captured frame instead.
    integer img_i;
    initial begin
        for (img_i = 0; img_i < IMG_BYTES; img_i = img_i + 1)
            image_mem[img_i] = img_i[7:0];
    end

    initial uart_rx = 1'b1;   // UART idle = high

    // ------------------------------------------------------------------
    // send_uart_byte: drives one UART frame onto uart_rx.
    // Bit transitions happen on negedge clk so they land cleanly between
    // the DUT's posedge sampling points - avoids start-bit races from
    // unsynchronized drive.
    // ------------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer b;
        begin
            @(negedge clk);
            uart_rx <= 1'b0;                       // start bit
            repeat (CLKS_PER_BIT) @(negedge clk);

            for (b = 0; b < 8; b = b + 1) begin     // 8 data bits, LSB first
                uart_rx <= data[b];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end

            uart_rx <= 1'b1;                        // stop bit
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Drive the whole image into uart_rx, back-to-back
    // ------------------------------------------------------------------
    initial begin
        rx_byte_count = 0;

        // Wait out the DUT's internal auto-reset (10000 cycles ~ 100us)
        repeat (10100) @(posedge clk);

        for (rx_byte_count = 0; rx_byte_count < IMG_BYTES; rx_byte_count = rx_byte_count + 1)
            send_uart_byte(image_mem[rx_byte_count]);

        $display("[%0t] TX to DUT complete: %0d bytes sent", $time, IMG_BYTES);
    end

    // ------------------------------------------------------------------
    // recv_uart_byte: waits for a start bit on uart_tx, samples each
    // data bit at its midpoint - mirrors the DUT's own uart_rx sampling
    // scheme so the testbench isn't "cheating" relative to a real PC.
    // ------------------------------------------------------------------
    task recv_uart_byte(output [7:0] data);
        integer b;
        begin
            @(negedge uart_tx);                       // start bit edge
            #(CLKS_PER_BIT/2 * 10);                    // mid of start bit
            #(CLKS_PER_BIT * 10);                       // mid of bit 0

            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_tx;
                #(CLKS_PER_BIT * 10);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Continuously receive bytes from uart_tx, store + count
    // ------------------------------------------------------------------
    reg [7:0] rx_byte;
    initial begin
        tx_byte_count = 0;
        while (tx_byte_count < OUT_BYTES) begin
            recv_uart_byte(rx_byte);
            out_mem[tx_byte_count] = rx_byte;
            tx_byte_count = tx_byte_count + 1;
            if (tx_byte_count % 1024 == 0)
                $display("[%0t] Received %0d / %0d output bytes", $time, tx_byte_count, OUT_BYTES);
        end

        $display("[%0t] RX from DUT complete: %0d bytes received", $time, OUT_BYTES);
        $writememh("sobel_output.hex", out_mem);

        $display("=====================================================");
        $display("TEST SUMMARY");
        $display("  Bytes sent to DUT      : %0d (expected %0d)", rx_byte_count, IMG_BYTES);
        $display("  Bytes received from DUT: %0d (expected %0d)", tx_byte_count, OUT_BYTES);
        if (tx_byte_count == OUT_BYTES)
            $display("  RESULT: PASS - no data loss");
        else
            $display("  RESULT: FAIL - byte count mismatch (check FIFO sizing/backpressure)");
        $display("=====================================================");

        $finish;
    end

    // ------------------------------------------------------------------
    // Safety timeout - bail if the DUT stalls and never finishes
    //
    // Math: 16900 bytes * 10 bits/byte * 868 clks/bit * 10ns/clk
    //     = ~1.467 seconds of simulated time just for the RX stream.
    //     TX trails RX slightly but runs at the same baud rate, so total
    //     completion lands close to that same ~1.5s mark.
    // (Earlier estimate of "~15M cycles / 200ms" was wrong by ~10x -
    //  corrected here with margin. That earlier bug is what caused
    //  out_mem / rx_byte entries to show up as Xs - $finish fired
    //  mid-receive, before every index in out_mem had been written.)
    // ------------------------------------------------------------------
    initial begin
        #3_000_000_000; // 3 seconds simulated time - generous margin over ~1.5s expected
        $display("[%0t] ERROR: TIMEOUT - simulation did not complete", $time);
        $display("  Bytes sent     : %0d", rx_byte_count);
        $display("  Bytes received : %0d", tx_byte_count);
        $finish;
    end

    // ------------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule