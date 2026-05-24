`timescale 1ns / 1ps

// Phase 5 M2 UART command parser.
//
// Receives CRLF-terminated ASCII commands from a host wrapper and emits
// single-cycle note/release strobes plus parameter wires that the
// fixed-function controller consumes directly. No CPU, no firmware, no
// MMIO bus, no FIFO.
//
// Protocol (subset of the legacy firmware commands documented in
// obsolete/riscv_control/fw/phase0/phase0_main.c):
//
//   "!N\r\n"            bare note: cmd_loop_len = 106, cmd_velocity = 0x7FFF
//                       and one note_strobe pulse.
//   "!NLLLLVVVV\r\n"    parameterized note. LLLL is 4 hex digits of
//                       loop_len (clamped to 32..127). VVVV is 4 hex
//                       digits of velocity (clamped to 0..0x7FFF).
//                       Hex digits are case-insensitive.
//   "!F\r\n"            release: one release_strobe pulse, no trigger.
//
// Commands are accumulated into a 16-byte line buffer. A complete line
// is the bytes since the last CRLF, ending in CR LF. Anything longer
// than 14 payload bytes triggers an overlong recovery: the rest of the
// line is silently discarded until the next CRLF appears, and one
// error is recorded.
//
// Error codes (mirrors the legacy firmware semantics):
//   0  none
//   1  malformed (no leading '!')
//   2  unknown opcode (leading '!' but unrecognized command)
//   3  overlong line
//   4  frame error from the UART RX primitive
//   7  unsupported argument (bad hex in !NLLLLVVVV)
//
// The parser holds the most recently parsed cmd_loop_len and cmd_velocity
// stable on the output ports until the next note command rewrites them,
// so the consumer can latch them on note_strobe with no race.

module phase0_uart_command #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        uart_rx_pin,

    output reg         note_strobe,
    output reg         release_strobe,
    output reg  [6:0]  cmd_loop_len,
    output reg  [15:0] cmd_velocity,

    output reg  [31:0] command_count,
    output reg  [15:0] error_count,
    output reg  [15:0] last_error
);

// -------------------------------------------------------------------------
// UART RX primitive (8N1 115200, mid-bit sample, frame_error pulse)
// -------------------------------------------------------------------------
wire       rx_valid;
wire [7:0] rx_data;
wire       rx_frame_error;

uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) uart_rx_inst (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .uart_rx    (uart_rx_pin),
    .rx_valid   (rx_valid),
    .rx_data    (rx_data),
    .frame_error(rx_frame_error)
);

// -------------------------------------------------------------------------
// Line buffer and parser FSM
// -------------------------------------------------------------------------
localparam integer LINE_MAX_INT = 16; // includes CRLF; bare !N\r\n = 4 bytes,
                                       // !NLLLLVVVV\r\n = 12 bytes

// Error code symbolic constants
localparam [15:0] ERR_NONE             = 16'd0;
localparam [15:0] ERR_MALFORMED        = 16'd1;
localparam [15:0] ERR_UNKNOWN_OPCODE   = 16'd2;
localparam [15:0] ERR_OVERLONG         = 16'd3;
localparam [15:0] ERR_FRAME            = 16'd4;
localparam [15:0] ERR_UNSUPPORTED_ARG  = 16'd7;

reg [7:0]  line_buf [0:LINE_MAX_INT-1];
reg [4:0]  line_len;          // 0..LINE_MAX_INT
reg        discarding;
reg        discard_prev_cr;

// Combinational hex-digit decode helpers (used in functions below).
function [3:0] decode_hex;
    input [7:0] c;
    begin
        if ((c >= 8'h30) && (c <= 8'h39)) begin
            decode_hex = c[3:0];
        end else if ((c >= 8'h41) && (c <= 8'h46)) begin
            decode_hex = c[3:0] + 4'd9;
        end else if ((c >= 8'h61) && (c <= 8'h66)) begin
            decode_hex = c[3:0] + 4'd9;
        end else begin
            decode_hex = 4'h0;
        end
    end
endfunction

function is_hex;
    input [7:0] c;
    begin
        is_hex = ((c >= 8'h30) && (c <= 8'h39)) ||
                 ((c >= 8'h41) && (c <= 8'h46)) ||
                 ((c >= 8'h61) && (c <= 8'h66));
    end
endfunction

// -------------------------------------------------------------------------
// Combinational pre-computation for the !NLLLLVVVV decode path
// -------------------------------------------------------------------------
wire        hex_all_valid;
wire [15:0] parsed_loop_full;
wire [15:0] parsed_vel_full;
wire [6:0]  parsed_loop_clamped;
wire [15:0] parsed_vel_clamped;

assign hex_all_valid = is_hex(line_buf[2]) && is_hex(line_buf[3]) &&
                       is_hex(line_buf[4]) && is_hex(line_buf[5]) &&
                       is_hex(line_buf[6]) && is_hex(line_buf[7]) &&
                       is_hex(line_buf[8]) && is_hex(line_buf[9]);

assign parsed_loop_full = {decode_hex(line_buf[2]),
                           decode_hex(line_buf[3]),
                           decode_hex(line_buf[4]),
                           decode_hex(line_buf[5])};

assign parsed_vel_full  = {decode_hex(line_buf[6]),
                           decode_hex(line_buf[7]),
                           decode_hex(line_buf[8]),
                           decode_hex(line_buf[9])};

assign parsed_loop_clamped = (parsed_loop_full < 16'd32)  ? 7'd32  :
                             (parsed_loop_full > 16'd127) ? 7'd127 :
                             parsed_loop_full[6:0];

assign parsed_vel_clamped  = (parsed_vel_full > 16'h7FFF) ? 16'h7FFF :
                             parsed_vel_full;

// -------------------------------------------------------------------------
// Main parser FSM
//
// line_buf is intentionally not reset: line_len = 0 on reset means no
// existing content matters until new bytes are written, which avoids
// inferring a latch on any loop index inside the always block.
// -------------------------------------------------------------------------
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        line_len        <= 5'd0;
        discarding      <= 1'b0;
        discard_prev_cr <= 1'b0;

        note_strobe     <= 1'b0;
        release_strobe  <= 1'b0;
        cmd_loop_len    <= 7'd106;
        cmd_velocity    <= 16'h7FFF;

        command_count   <= 32'd0;
        error_count     <= 16'd0;
        last_error      <= ERR_NONE;
    end else begin
        // Default strobes low each cycle; pulse is one clock when set.
        note_strobe    <= 1'b0;
        release_strobe <= 1'b0;

        // RX primitive frame error: count, drop any partial line, and
        // enter discard until next CRLF so we resync cleanly.
        if (rx_frame_error) begin
            last_error <= ERR_FRAME;
            if (error_count != 16'hFFFF) begin
                error_count <= error_count + 16'd1;
            end
            line_len        <= 5'd0;
            discarding      <= 1'b1;
            discard_prev_cr <= 1'b0;
        end

        if (rx_valid) begin
            if (discarding) begin
                // Wait for CR followed by LF to resume normal operation.
                if (discard_prev_cr && (rx_data == 8'h0A)) begin
                    discarding      <= 1'b0;
                    discard_prev_cr <= 1'b0;
                end else begin
                    discard_prev_cr <= (rx_data == 8'h0D);
                end
            end else begin
                // Overlong-line guard. Total line including CRLF must fit
                // in 16 bytes. Detect overflow before storing the 17th byte.
                //
                // line_len is the count of bytes already stored. If we are
                // about to store the 15th byte (line_len == 14) and it is
                // not CR, and the last stored byte is not CR (otherwise
                // this byte could legitimately be LF completing CRLF for a
                // 15-byte command -- which is impossible since the longest
                // valid command is 12 bytes -- so guard is conservative),
                // we have an overlong line.
                if ((line_len == 5'd15) && (rx_data != 8'h0A)) begin
                    last_error <= ERR_OVERLONG;
                    if (error_count != 16'hFFFF) begin
                        error_count <= error_count + 16'd1;
                    end
                    line_len        <= 5'd0;
                    discarding      <= 1'b1;
                    discard_prev_cr <= (rx_data == 8'h0D);
                end else if ((line_len == 5'd14) && (rx_data != 8'h0D) &&
                             (rx_data != 8'h0A)) begin
                    last_error <= ERR_OVERLONG;
                    if (error_count != 16'hFFFF) begin
                        error_count <= error_count + 16'd1;
                    end
                    line_len        <= 5'd0;
                    discarding      <= 1'b1;
                    discard_prev_cr <= 1'b0;
                end else begin
                    // Append byte and check for CRLF terminator.
                    line_buf[line_len] <= rx_data;
                    line_len           <= line_len + 5'd1;

                    if ((rx_data == 8'h0A) &&
                        (line_len > 5'd0) &&
                        (line_buf[line_len - 5'd1] == 8'h0D)) begin
                        // Complete line. Total length is line_len + 1
                        // (the LF byte is being stored at index line_len).

                        case (line_len + 5'd1)
                            5'd4: begin
                                // 4-byte commands: !N\r\n or !F\r\n
                                if ((line_buf[0] == 8'h21) &&
                                    (line_buf[1] == 8'h4E) &&
                                    (line_buf[2] == 8'h0D)) begin
                                    // !N
                                    cmd_loop_len  <= 7'd106;
                                    cmd_velocity  <= 16'h7FFF;
                                    note_strobe   <= 1'b1;
                                    command_count <= command_count + 32'd1;
                                end else if ((line_buf[0] == 8'h21) &&
                                             (line_buf[1] == 8'h46) &&
                                             (line_buf[2] == 8'h0D)) begin
                                    // !F
                                    release_strobe <= 1'b1;
                                    command_count  <= command_count + 32'd1;
                                end else if (line_buf[0] == 8'h21) begin
                                    // !X for some unknown X
                                    last_error <= ERR_UNKNOWN_OPCODE;
                                    if (error_count != 16'hFFFF) begin
                                        error_count <= error_count + 16'd1;
                                    end
                                end else begin
                                    last_error <= ERR_MALFORMED;
                                    if (error_count != 16'hFFFF) begin
                                        error_count <= error_count + 16'd1;
                                    end
                                end
                                line_len <= 5'd0;
                            end

                            5'd12: begin
                                // !NLLLLVVVV\r\n
                                if ((line_buf[0] == 8'h21) &&
                                    (line_buf[1] == 8'h4E) &&
                                    (line_buf[10] == 8'h0D)) begin
                                    if (!hex_all_valid) begin
                                        last_error <= ERR_UNSUPPORTED_ARG;
                                        if (error_count != 16'hFFFF) begin
                                            error_count <= error_count + 16'd1;
                                        end
                                    end else begin
                                        cmd_loop_len  <= parsed_loop_clamped;
                                        cmd_velocity  <= parsed_vel_clamped;
                                        note_strobe   <= 1'b1;
                                        command_count <= command_count + 32'd1;
                                    end
                                end else if ((line_buf[0] == 8'h21) &&
                                             (line_buf[1] == 8'h4E)) begin
                                    last_error <= ERR_UNSUPPORTED_ARG;
                                    if (error_count != 16'hFFFF) begin
                                        error_count <= error_count + 16'd1;
                                    end
                                end else if (line_buf[0] == 8'h21) begin
                                    last_error <= ERR_UNKNOWN_OPCODE;
                                    if (error_count != 16'hFFFF) begin
                                        error_count <= error_count + 16'd1;
                                    end
                                end else begin
                                    last_error <= ERR_MALFORMED;
                                    if (error_count != 16'hFFFF) begin
                                        error_count <= error_count + 16'd1;
                                    end
                                end
                                line_len <= 5'd0;
                            end

                            default: begin
                                // Some other length terminated by CRLF.
                                if (line_buf[0] == 8'h21) begin
                                    if ((line_buf[1] == 8'h4E) ||
                                        (line_buf[1] == 8'h46)) begin
                                        last_error <= ERR_UNSUPPORTED_ARG;
                                    end else begin
                                        last_error <= ERR_UNKNOWN_OPCODE;
                                    end
                                end else begin
                                    last_error <= ERR_MALFORMED;
                                end
                                if (error_count != 16'hFFFF) begin
                                    error_count <= error_count + 16'd1;
                                end
                                line_len <= 5'd0;
                            end
                        endcase
                    end
                end
            end
        end
    end
end

endmodule
