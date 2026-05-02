`timescale 1ns / 1ps

module phase0_body_filter (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        sample_tick,
    input  wire signed [15:0] sample_in,
    output wire signed [15:0] sample_out
);

    // Q2.14 coefficients for Biquad 1: Low-shelf (+6 dB, fc~200 Hz, Q~0.7)
    localparam signed [15:0] B1_B0 = 16'sd16493;
    localparam signed [15:0] B1_B1 = -16'sd32236;
    localparam signed [15:0] B1_B2 =  16'sd15759;
    localparam signed [15:0] B1_A1 =  16'sd32240;
    localparam signed [15:0] B1_A2 = -16'sd15864;

    // Q2.14 coefficients for Biquad 2: Peaking (+3 dB, fc~200 Hz, Q~1.0)
    localparam signed [15:0] B2_B0 =  16'sd16459;
    localparam signed [15:0] B2_B1 = -16'sd32391;
    localparam signed [15:0] B2_B2 =  16'sd15943;
    localparam signed [15:0] B2_A1 =  16'sd32391;
    localparam signed [15:0] B2_A2 = -16'sd16019;

    // Stage 1 state
    reg signed [17:0] x1_z1, x1_z2;
    reg signed [17:0] y1_z1, y1_z2;

    // Stage 2 state
    reg signed [17:0] x2_z1, x2_z2;
    reg signed [17:0] y2_z1, y2_z2;

    // Stage 1 compute
    wire signed [17:0] x1;
    wire signed [35:0] b1b0_prod, b1b1_prod, b1b2_prod, b1a1_prod, b1a2_prod;
    wire signed [38:0] y1_sum;
    wire signed [17:0] y1_sat;

    // Stage 2 compute
    wire signed [17:0] x2;
    wire signed [35:0] b2b0_prod, b2b1_prod, b2b2_prod, b2a1_prod, b2a2_prod;
    wire signed [38:0] y2_sum;
    wire signed [17:0] y2_sat;

    assign x1 = {{2{sample_in[15]}}, sample_in};

    assign b1b0_prod = x1    * B1_B0;
    assign b1b1_prod = x1_z1 * B1_B1;
    assign b1b2_prod = x1_z2 * B1_B2;
    assign b1a1_prod = y1_z1 * B1_A1;
    assign b1a2_prod = y1_z2 * B1_A2;

    assign y1_sum = {{3{b1b0_prod[35]}}, b1b0_prod} +
                    {{3{b1b1_prod[35]}}, b1b1_prod} +
                    {{3{b1b2_prod[35]}}, b1b2_prod} +
                    {{3{b1a1_prod[35]}}, b1a1_prod} +
                    {{3{b1a2_prod[35]}}, b1a2_prod};

    assign y1_sat = (y1_sum > 39'sd131071)  ? 18'sh1ffff :
                    (y1_sum < -39'sd131072) ? 18'sh20000 :
                    y1_sum[17:0];

    assign x2 = y1_sat;

    assign b2b0_prod = x2    * B2_B0;
    assign b2b1_prod = x2_z1 * B2_B1;
    assign b2b2_prod = x2_z2 * B2_B2;
    assign b2a1_prod = y2_z1 * B2_A1;
    assign b2a2_prod = y2_z2 * B2_A2;

    assign y2_sum = {{3{b2b0_prod[35]}}, b2b0_prod} +
                    {{3{b2b1_prod[35]}}, b2b1_prod} +
                    {{3{b2b2_prod[35]}}, b2b2_prod} +
                    {{3{b2a1_prod[35]}}, b2a1_prod} +
                    {{3{b2a2_prod[35]}}, b2a2_prod};

    assign y2_sat = (y2_sum > 39'sd131071)  ? 18'sh1ffff :
                    (y2_sum < -39'sd131072) ? 18'sh20000 :
                    y2_sum[17:0];

    assign sample_out = (y2_sat > 18'sd32767)  ? 16'sh7fff :
                        (y2_sat < -18'sd32768) ? 16'sh8000 :
                        y2_sat[15:0];

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            x1_z1 <= 18'sd0;
            x1_z2 <= 18'sd0;
            y1_z1 <= 18'sd0;
            y1_z2 <= 18'sd0;
            x2_z1 <= 18'sd0;
            x2_z2 <= 18'sd0;
            y2_z1 <= 18'sd0;
            y2_z2 <= 18'sd0;
        end else if (sample_tick) begin
            x1_z1 <= x1;
            x1_z2 <= x1_z1;
            y1_z1 <= y1_sat;
            y1_z2 <= y1_z1;
            x2_z1 <= x2;
            x2_z2 <= x2_z1;
            y2_z1 <= y2_sat;
            y2_z2 <= y2_z1;
        end
    end

endmodule
