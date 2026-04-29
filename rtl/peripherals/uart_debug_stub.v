`timescale 1ns / 1ps

module uart_debug_stub (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        board_uart_rx,
    input  wire        core_uart_tx,
    output wire        board_uart_tx,
    output wire        core_uart_rx,
    output wire [15:0] status_word
);

wire unused_ok;

assign unused_ok = sys_clk & sys_rst_n;

assign board_uart_tx = core_uart_tx;
assign core_uart_rx  = board_uart_rx;
assign status_word   = {13'd0, unused_ok, core_uart_tx, board_uart_rx};

endmodule
