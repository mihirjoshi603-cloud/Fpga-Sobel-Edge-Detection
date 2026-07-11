//=============================================================================
// Module : uart_tx (unchanged from tested version)
//=============================================================================
module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam IDLE    = 3'd0;
    localparam START   = 3'd1;
    localparam DATA    = 3'd2;
    localparam STOP    = 3'd3;
    localparam CLEANUP = 3'd4;

    reg [2:0] state = IDLE;
    reg [$clog2(CLKS_PER_BIT):0] clk_count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] tx_data_r = 0;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; tx <= 1'b1; tx_busy <= 1'b0;
            clk_count <= 0; bit_index <= 0; tx_data_r <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1; tx_busy <= 1'b0;
                    clk_count <= 0; bit_index <= 0;
                    if (tx_start) begin tx_data_r <= tx_data; tx_busy <= 1'b1; state <= START; end
                end

                START: begin
                    tx <= 1'b0;
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin clk_count <= 0; state <= DATA; end
                end

                DATA: begin
                    tx <= tx_data_r[bit_index];
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0;
                        if (bit_index < 7) bit_index <= bit_index + 1;
                        else begin bit_index <= 0; state <= STOP; end
                    end
                end

                STOP: begin
                    tx <= 1'b1;
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin clk_count <= 0; state <= CLEANUP; end
                end

                CLEANUP: begin tx_busy <= 1'b0; state <= IDLE; end
                default:  state <= IDLE;
            endcase
        end
    end

endmodule