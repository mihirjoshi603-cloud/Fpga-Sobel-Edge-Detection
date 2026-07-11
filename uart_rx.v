//=============================================================================
// Module : uart_rx (unchanged from tested version)
//=============================================================================
module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_done
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
    reg [7:0] rx_data_reg = 0;

    reg rx_sync_0 = 1'b1;
    reg rx_sync   = 1'b1;

    always @(posedge clk) begin
        rx_sync_0 <= rx;
        rx_sync   <= rx_sync_0;
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; clk_count <= 0; bit_index <= 0;
            rx_data <= 0; rx_data_reg <= 0; rx_done <= 0;
        end else begin
            rx_done <= 0;
            case (state)
                IDLE: begin
                    clk_count <= 0; bit_index <= 0;
                    if (rx_sync == 1'b0) state <= START;
                end

                START: begin
                    if (clk_count == (CLKS_PER_BIT/2)-1) begin
                        if (rx_sync == 1'b0) begin clk_count <= 0; state <= DATA; end
                        else state <= IDLE;
                    end else clk_count <= clk_count + 1;
                end

                DATA: begin
                    if (clk_count < CLKS_PER_BIT-1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        rx_data_reg[bit_index] <= rx_sync;
                        if (bit_index < 7) bit_index <= bit_index + 1;
                        else begin bit_index <= 0; state <= STOP; end
                    end
                end

                STOP: begin
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0; rx_done <= 1'b1;
                        rx_data <= rx_data_reg; state <= CLEANUP;
                    end
                end

                CLEANUP: state <= IDLE;
                default:  state <= IDLE;
            endcase
        end
    end

endmodule