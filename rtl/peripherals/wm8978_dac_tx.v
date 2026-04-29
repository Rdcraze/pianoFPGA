`timescale 1ns / 1ps

module wm8978_dac_tx (
    input  wire        audio_bclk,
    input  wire        sys_rst_n,
    input  wire        audio_lrc,
    input  wire [15:0] tx_sample,
    output reg         audio_dacdat,
    output reg         frame_start
);

reg        audio_lrc_d1;
reg [4:0]  bit_count;
reg [15:0] frame_sample;
reg [15:0] shift_sample;

wire lrc_edge;
wire frame_edge;

assign lrc_edge   = audio_lrc ^ audio_lrc_d1;
assign frame_edge = (~audio_lrc_d1) & audio_lrc;

always @(posedge audio_bclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_lrc_d1 <= 1'b0;
        bit_count    <= 5'd0;
        frame_sample <= 16'd0;
        shift_sample <= 16'd0;
        frame_start  <= 1'b0;
    end else begin
        audio_lrc_d1 <= audio_lrc;
        frame_start  <= 1'b0;

        if (lrc_edge) begin
            bit_count <= 5'd0;
            if (frame_edge) begin
                frame_sample <= tx_sample;
                shift_sample <= tx_sample;
                frame_start  <= 1'b1;
            end else begin
                shift_sample <= frame_sample;
            end
        end else if (bit_count < 5'd16) begin
            bit_count <= bit_count + 1'b1;
        end
    end
end

always @(negedge audio_bclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_dacdat <= 1'b0;
    end else if (bit_count < 5'd16) begin
        audio_dacdat <= shift_sample[15 - bit_count];
    end
end

endmodule
