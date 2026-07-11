`timescale 1ns / 1ps
//=============================================================================
// Module : sobel_top (unchanged - all fixes already applied)
// Input  : 130x130 padded image streamed pixel by pixel
// Output : 128x128 edge-detected image
//=============================================================================
module sobel_top #(
    parameter IMG_W = 130,
    parameter OUT_W = 128
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] pixel_in,
    input  wire       valid_in,
    output reg  [7:0] sobel_out,
    output reg        valid_out
);

    reg [7:0] lb1 [0:IMG_W-1];
    reg [7:0] lb2 [0:IMG_W-1];

    reg [7:0] p11, p12, p13;
    reg [7:0] p21, p22, p23;
    reg [7:0] p31, p32, p33;

    reg [7:0] col;
    reg [7:0] row;

    reg signed [17:0] Gx, Gy;
    wire [17:0] abs_Gx, abs_Gy;
    assign abs_Gx = Gx[17] ? (~Gx + 1'b1) : Gx;
    assign abs_Gy = Gy[17] ? (~Gy + 1'b1) : Gy;

    reg valid_pipe;
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            col <= 0; row <= 0; valid_pipe <= 0; Gx <= 0; Gy <= 0;
            p11<=0; p12<=0; p13<=0; p21<=0; p22<=0; p23<=0; p31<=0; p32<=0; p33<=0;
            for (i=0; i<IMG_W; i=i+1) begin lb1[i]<=0; lb2[i]<=0; end
        end else if (valid_in) begin
            p11<=p12; p12<=p13; p13<=lb1[col];
            p21<=p22; p22<=p23; p23<=lb2[col];
            p31<=p32; p32<=p33; p33<=pixel_in;

            lb1[col] <= lb2[col];
            lb2[col] <= pixel_in;

            if (row>=2 && col>=2 && row<=OUT_W+1 && col<=OUT_W+1) begin
                Gx <= (-$signed({1'b0,p11})) + ($signed({1'b0,p13})) +
                      (-2*$signed({1'b0,p21})) + (2*$signed({1'b0,p23})) +
                      (-$signed({1'b0,p31})) + ($signed({1'b0,p33}));

                Gy <= ($signed({1'b0,p11})) + (2*$signed({1'b0,p12})) + ($signed({1'b0,p13})) +
                      (-$signed({1'b0,p31})) + (-2*$signed({1'b0,p32})) + (-$signed({1'b0,p33}));

                valid_pipe <= 1'b1;
            end else begin
                Gx<=0; Gy<=0; valid_pipe<=1'b0;
            end

            if (col == IMG_W-1) begin
                col <= 0;
                if (row == IMG_W-1) row <= 0;
                else row <= row + 1;
            end else col <= col + 1;
        end else begin
            valid_pipe <= 1'b0;
        end
    end

    wire [17:0] mag_sum;
    assign mag_sum = abs_Gx + abs_Gy;

    always @(posedge clk) begin
        if (!rst_n) begin sobel_out<=0; valid_out<=0; end
        else begin
            valid_out <= valid_pipe;
            if (valid_pipe)
                sobel_out <= (mag_sum > 18'd255) ? 8'hFF : mag_sum[7:0];
            else
                sobel_out <= 8'd0;
        end
    end

endmodule