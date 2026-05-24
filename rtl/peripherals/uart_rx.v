`timescale 1ns / 1ps

// Phase 5 M2 standalone UART RX primitive.
//
// Lifted unchanged in semantics from
// obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v (its
// internal uart_rx module starting at line 245). The MMIO/FIFO
// wrapper around it has been left in the obsolete archive; this file
// is the standalone RX primitive only.
//
// 8N1 receiver. Double-flop synchronizer on uart_rx, mid-bit sample,
// frame-error pulse on stop-bit not high. sys_clk-domain only.

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       uart_rx,
    output reg        rx_valid,
    output reg  [7:0] rx_data,
    output reg        frame_error
);

localparam integer BAUD_DIV      = (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
localparam [31:0]  BAUD_DIV_LAST = BAUD_DIV - 1;
localparam [31:0]  BAUD_DIV_HALF = (BAUD_DIV / 2);

localparam [1:0] STATE_IDLE  = 2'd0;
localparam [1:0] STATE_START = 2'd1;
localparam [1:0] STATE_DATA  = 2'd2;
localparam [1:0] STATE_STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] baud_count;
reg [2:0]  bit_index;
reg [7:0]  shift_reg;
reg        rx_meta;
reg        rx_sync;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        rx_meta <= uart_rx;
        rx_sync <= rx_meta;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state       <= STATE_IDLE;
        baud_count  <= 16'd0;
        bit_index   <= 3'd0;
        shift_reg   <= 8'd0;
        rx_valid    <= 1'b0;
        rx_data     <= 8'd0;
        frame_error <= 1'b0;
    end else begin
        rx_valid    <= 1'b0;
        frame_error <= 1'b0;

        case (state)
            STATE_IDLE: begin
                if (!rx_sync) begin
                    state      <= STATE_START;
                    baud_count <= BAUD_DIV_HALF[15:0];
                end
            end

            STATE_START: begin
                if (baud_count != 16'd0) begin
                    baud_count <= baud_count - 1'b1;
                end else if (!rx_sync) begin
                    state      <= STATE_DATA;
                    baud_count <= BAUD_DIV_LAST[15:0];
                    bit_index  <= 3'd0;
                end else begin
                    state <= STATE_IDLE;
                end
            end

            STATE_DATA: begin
                if (baud_count != 16'd0) begin
                    baud_count <= baud_count - 1'b1;
                end else begin
                    shift_reg[bit_index] <= rx_sync;
                    baud_count           <= BAUD_DIV_LAST[15:0];
                    if (bit_index == 3'd7) begin
                        state <= STATE_STOP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end
            end

            STATE_STOP: begin
                if (baud_count != 16'd0) begin
                    baud_count <= baud_count - 1'b1;
                end else begin
                    if (rx_sync) begin
                        rx_data  <= shift_reg;
                        rx_valid <= 1'b1;
                    end else begin
                        frame_error <= 1'b1;
                    end
                    state <= STATE_IDLE;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
