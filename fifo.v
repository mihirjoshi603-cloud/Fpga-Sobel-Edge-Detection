//=============================================================================
// Module      : fifo
// Description : Synchronous FIFO with parameterizable depth and width
//
// Ports:
//   clk    - System clock
//   rst    - Active-high synchronous reset
//   wr_en  - Write enable
//   din    - Data in
//   rd_en  - Read enable
//   dout   - Data out (registered - 1 cycle latency after rd_en)
//   full   - FIFO is full
//   empty  - FIFO is empty
//
// Instantiated twice in top.v: once as the RX FIFO (DEPTH=2048),
// once as the TX FIFO (DEPTH=4096).
//=============================================================================
module fifo #(
    parameter DEPTH = 512,
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] din,
    input  wire             rd_en,
    output reg  [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Extra MSB on pointers = wrap bit, used to distinguish full vs empty
    localparam PTR_W = $clog2(DEPTH) + 1;
    reg [PTR_W-1:0] wr_ptr = 0;
    reg [PTR_W-1:0] rd_ptr = 0;

    // Empty when both pointers identical; full when lower bits match but MSBs differ
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[PTR_W-2:0] == rd_ptr[PTR_W-2:0]) &&
                   (wr_ptr[PTR_W-1]   != rd_ptr[PTR_W-1]);

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[$clog2(DEPTH)-1:0]] <= din;
            wr_ptr <= wr_ptr + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
            dout   <= 0;
        end else if (rd_en && !empty) begin
            dout   <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
            rd_ptr <= rd_ptr + 1;
        end
    end

endmodule