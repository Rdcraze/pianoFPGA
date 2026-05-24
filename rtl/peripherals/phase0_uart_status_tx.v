`timescale 1ns / 1ps

// Phase 5 M1 status-frame transmitter.
//
// Emits a periodic ASCII status frame on UART1 TX at 115200 8N1. Format
// is fixed-length, exactly 40 bytes:
//
//   P5M1 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX\r\n
//
// Field semantics:
//   P5M1            milestone tag (5 bytes including trailing space)
//   BOOT=XXXXXXXX   32-bit hex frame counter, increments once per frame
//   TICK=XXXXXXXX   32-bit hex sample_tick counter snapshot at frame
//                   start (mirrors the firmware-era R= tag's role)
//   VC=XX           voice index 00..03 from the fixed-control round
//                   robin sequencer at frame start
//   \r\n            CRLF terminator
//
// Cadence is one frame every CADENCE_CYCLES sys_clk cycles. Default at
// 50 MHz is 25,000,000 cycles, ~500 ms. The cadence is intentionally
// loose: every frame carries its own freshness counters, so jitter in
// the cadence is harmless for verification.
//
// If a cadence pulse fires while the previous frame is still draining
// over the UART, that pulse is dropped silently. The skipped count is
// kept locally as a saturating 8-bit counter for future M2 inclusion.
//
// Pure sys_clk-domain design. No CDC, no audio path interaction.

module phase0_uart_status_tx #(
    parameter integer CLK_FREQ_HZ    = 50_000_000,
    parameter integer BAUD_RATE      = 115_200,
    parameter integer CADENCE_CYCLES = 25_000_000
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        sample_tick,
    input  wire [1:0]  voice_index,
    output wire        uart_tx
);

// -------------------------------------------------------------------------
// Cadence counter and free-running tick snapshot
// -------------------------------------------------------------------------
localparam integer CADENCE_LAST = CADENCE_CYCLES - 1;
localparam integer CADENCE_W    = 25; // covers 25,000,000

reg [CADENCE_W-1:0] cadence_counter;
reg                 cadence_pulse;
reg [31:0]          tick_counter_free;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        cadence_counter   <= {CADENCE_W{1'b0}};
        cadence_pulse     <= 1'b0;
        tick_counter_free <= 32'd0;
    end else begin
        cadence_pulse <= 1'b0;
        if (cadence_counter == CADENCE_LAST[CADENCE_W-1:0]) begin
            cadence_counter <= {CADENCE_W{1'b0}};
            cadence_pulse   <= 1'b1;
        end else begin
            cadence_counter <= cadence_counter + 1'b1;
        end
        if (sample_tick) begin
            tick_counter_free <= tick_counter_free + 32'd1;
        end
    end
end

// -------------------------------------------------------------------------
// Frame state machine
// -------------------------------------------------------------------------
localparam integer FRAME_LEN = 40;

localparam [1:0] STATE_IDLE  = 2'd0;
localparam [1:0] STATE_SEND  = 2'd1;
localparam [1:0] STATE_WAIT  = 2'd2;

reg [1:0]  state;
reg [5:0]  byte_index; // 0..39
reg [31:0] boot_counter;
reg [31:0] tick_snapshot;
reg [1:0]  vc_snapshot;
reg [7:0]  skipped_count;

reg        tx_valid;
reg [7:0]  tx_data;
wire       tx_ready;

uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) uart_tx_inst (
    .sys_clk  (sys_clk),
    .sys_rst_n(sys_rst_n),
    .tx_valid (tx_valid),
    .tx_data  (tx_data),
    .tx_ready (tx_ready),
    .uart_tx  (uart_tx)
);

// Combinational byte selector. Picks the ASCII byte for byte_index based
// on the snapshotted counters. The snapshots are static during a frame
// so this lookup is purely combinational.
function [3:0] hex_nibble32;
    input [31:0] value;
    input integer position; // 0 = MSB nibble, 7 = LSB nibble
    begin
        hex_nibble32 = value[((7 - position) << 2) +: 4];
    end
endfunction

function [7:0] hex_to_ascii;
    input [3:0] nibble;
    begin
        if (nibble < 4'd10)
            hex_to_ascii = 8'h30 + {4'd0, nibble};
        else
            hex_to_ascii = 8'h41 + {4'd0, nibble - 4'd10}; // uppercase
    end
endfunction

reg [7:0] frame_byte;
always @(*) begin
    case (byte_index)
        // "P5M1 "
        6'd0:  frame_byte = "P";
        6'd1:  frame_byte = "5";
        6'd2:  frame_byte = "M";
        6'd3:  frame_byte = "1";
        6'd4:  frame_byte = " ";
        // "BOOT="
        6'd5:  frame_byte = "B";
        6'd6:  frame_byte = "O";
        6'd7:  frame_byte = "O";
        6'd8:  frame_byte = "T";
        6'd9:  frame_byte = "=";
        // BOOT hex (8 chars MSB first)
        6'd10: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 0));
        6'd11: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 1));
        6'd12: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 2));
        6'd13: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 3));
        6'd14: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 4));
        6'd15: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 5));
        6'd16: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 6));
        6'd17: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 7));
        6'd18: frame_byte = " ";
        // "TICK="
        6'd19: frame_byte = "T";
        6'd20: frame_byte = "I";
        6'd21: frame_byte = "C";
        6'd22: frame_byte = "K";
        6'd23: frame_byte = "=";
        6'd24: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 0));
        6'd25: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 1));
        6'd26: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 2));
        6'd27: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 3));
        6'd28: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 4));
        6'd29: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 5));
        6'd30: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 6));
        6'd31: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 7));
        6'd32: frame_byte = " ";
        // "VC=" + 2 hex digits
        6'd33: frame_byte = "V";
        6'd34: frame_byte = "C";
        6'd35: frame_byte = "=";
        6'd36: frame_byte = "0"; // upper nibble of 2-bit voice_index is always 0
        6'd37: frame_byte = hex_to_ascii({2'b00, vc_snapshot});
        // CRLF
        6'd38: frame_byte = 8'h0D;
        6'd39: frame_byte = 8'h0A;
        default: frame_byte = " ";
    endcase
end

// FSM
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state         <= STATE_IDLE;
        byte_index    <= 6'd0;
        boot_counter  <= 32'd0;
        tick_snapshot <= 32'd0;
        vc_snapshot   <= 2'd0;
        skipped_count <= 8'd0;
        tx_valid      <= 1'b0;
        tx_data       <= 8'd0;
    end else begin
        tx_valid <= 1'b0;

        case (state)
            STATE_IDLE: begin
                if (cadence_pulse) begin
                    if (tx_ready) begin
                        // Start a new frame: snapshot dynamic fields.
                        boot_counter  <= boot_counter + 32'd1;
                        tick_snapshot <= tick_counter_free;
                        vc_snapshot   <= voice_index;
                        byte_index    <= 6'd0;
                        state         <= STATE_SEND;
                    end else begin
                        // uart_tx still draining a previous byte. The
                        // frame state machine should normally be idle
                        // when cadence fires because cadence_cycles is
                        // far longer than 40 bytes at 115200, but if
                        // it does happen we simply skip the frame.
                        if (skipped_count != 8'hFF) begin
                            skipped_count <= skipped_count + 8'd1;
                        end
                    end
                end
            end

            STATE_SEND: begin
                if (tx_ready) begin
                    tx_valid <= 1'b1;
                    tx_data  <= frame_byte;
                    state    <= STATE_WAIT;
                end
            end

            STATE_WAIT: begin
                // Wait for uart_tx to accept the byte and finish it,
                // then advance index or finish the frame.
                if (!tx_valid && tx_ready) begin
                    if (byte_index == FRAME_LEN[5:0] - 6'd1) begin
                        state <= STATE_IDLE;
                    end else begin
                        byte_index <= byte_index + 6'd1;
                        state      <= STATE_SEND;
                    end
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
