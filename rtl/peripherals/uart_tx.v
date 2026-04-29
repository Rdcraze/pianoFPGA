`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    output wire       tx_ready,
    output reg        uart_tx
);

localparam integer BAUD_DIV = (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
localparam [31:0] BAUD_DIV_LAST = BAUD_DIV - 1;

reg        busy;
reg [15:0] baud_count;
reg [3:0]  bits_remaining;
reg [9:0]  shift_reg;

assign tx_ready = !busy;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        busy           <= 1'b0;
        baud_count     <= 16'd0;
        bits_remaining <= 4'd0;
        shift_reg      <= 10'h3FF;
        uart_tx        <= 1'b1;
    end else if (!busy) begin
        uart_tx <= 1'b1;
        if (tx_valid) begin
            busy           <= 1'b1;
            baud_count     <= BAUD_DIV_LAST[15:0];
            bits_remaining <= 4'd9;
            shift_reg      <= {1'b1, tx_data, 1'b0};
            uart_tx        <= 1'b0;
        end
    end else if (baud_count != 16'd0) begin
        baud_count <= baud_count - 1'b1;
    end else begin
        baud_count <= BAUD_DIV_LAST[15:0];
        if (bits_remaining != 4'd0) begin
            uart_tx        <= shift_reg[1];
            shift_reg      <= {1'b1, shift_reg[9:1]};
            bits_remaining <= bits_remaining - 1'b1;
        end else begin
            busy    <= 1'b0;
            uart_tx <= 1'b1;
        end
    end
end

endmodule
