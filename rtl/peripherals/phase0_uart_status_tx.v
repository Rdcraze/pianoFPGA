`timescale 1ns / 1ps

// Phase 5 M2 status-frame transmitter.
//
// Emits a periodic ASCII status frame on UART1 TX at 115200 8N1. Format
// is fixed-length, exactly 62 bytes:
//
//   P5M2 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX Q=XXXXXXXX X=XXXXXXXX\r\n
//
// Field semantics:
//   P5M2            milestone tag (5 bytes including trailing space)
//   BOOT=XXXXXXXX   32-bit hex frame counter, increments once per frame
//   TICK=XXXXXXXX   32-bit hex sample_tick counter snapshot at frame
//                   start (mirrors the firmware-era R= tag's role)
//   VC=XX           voice index 00..03 from the fixed-control round
//                   robin sequencer at frame start
//   Q=XXXXXXXX      command_count (32-bit) snapshot at frame start
//   X=XXXXXXXX      {last_error[15:0], error_count[15:0]} snapshot at
//                   frame start (mirrors firmware X= tag semantics)
//   \r\n            CRLF terminator
//
// Cadence is one frame every CADENCE_CYCLES sys_clk cycles. Default at
// 50 MHz is 25,000,000 cycles, ~500 ms. Cadence is intentionally loose:
// every frame carries its own freshness counters, so jitter is harmless.
//
// If a cadence pulse fires while the previous frame is still draining
// over the UART, that pulse is dropped silently. The skipped count is
// kept locally as a saturating 8-bit counter for future inclusion.
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
    input  wire [31:0] command_count,
    input  wire [15:0] error_count,
    input  wire [15:0] last_error,
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
localparam integer FRAME_LEN = 62;

localparam [1:0] STATE_IDLE  = 2'd0;
localparam [1:0] STATE_SEND  = 2'd1;
localparam [1:0] STATE_WAIT  = 2'd2;

reg [1:0]  state;
reg [6:0]  byte_index; // 0..61
reg [31:0] boot_counter;
reg [31:0] tick_snapshot;
reg [1:0]  vc_snapshot;
reg [31:0] q_snapshot;
reg [31:0] x_snapshot;
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
        // "P5M2 "
        7'd0:  frame_byte = "P";
        7'd1:  frame_byte = "5";
        7'd2:  frame_byte = "M";
        7'd3:  frame_byte = "2";
        7'd4:  frame_byte = " ";
        // "BOOT="
        7'd5:  frame_byte = "B";
        7'd6:  frame_byte = "O";
        7'd7:  frame_byte = "O";
        7'd8:  frame_byte = "T";
        7'd9:  frame_byte = "=";
        // BOOT hex (8 chars MSB first)
        7'd10: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 0));
        7'd11: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 1));
        7'd12: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 2));
        7'd13: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 3));
        7'd14: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 4));
        7'd15: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 5));
        7'd16: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 6));
        7'd17: frame_byte = hex_to_ascii(hex_nibble32(boot_counter, 7));
        7'd18: frame_byte = " ";
        // "TICK="
        7'd19: frame_byte = "T";
        7'd20: frame_byte = "I";
        7'd21: frame_byte = "C";
        7'd22: frame_byte = "K";
        7'd23: frame_byte = "=";
        7'd24: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 0));
        7'd25: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 1));
        7'd26: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 2));
        7'd27: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 3));
        7'd28: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 4));
        7'd29: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 5));
        7'd30: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 6));
        7'd31: frame_byte = hex_to_ascii(hex_nibble32(tick_snapshot, 7));
        7'd32: frame_byte = " ";
        // "VC=" + 2 hex digits
        7'd33: frame_byte = "V";
        7'd34: frame_byte = "C";
        7'd35: frame_byte = "=";
        7'd36: frame_byte = "0"; // upper nibble of 2-bit voice_index is 0
        7'd37: frame_byte = hex_to_ascii({2'b00, vc_snapshot});
        7'd38: frame_byte = " ";
        // "Q=" + 8 hex digits
        7'd39: frame_byte = "Q";
        7'd40: frame_byte = "=";
        7'd41: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 0));
        7'd42: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 1));
        7'd43: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 2));
        7'd44: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 3));
        7'd45: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 4));
        7'd46: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 5));
        7'd47: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 6));
        7'd48: frame_byte = hex_to_ascii(hex_nibble32(q_snapshot, 7));
        7'd49: frame_byte = " ";
        // "X=" + 8 hex digits
        7'd50: frame_byte = "X";
        7'd51: frame_byte = "=";
        7'd52: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 0));
        7'd53: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 1));
        7'd54: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 2));
        7'd55: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 3));
        7'd56: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 4));
        7'd57: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 5));
        7'd58: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 6));
        7'd59: frame_byte = hex_to_ascii(hex_nibble32(x_snapshot, 7));
        // CRLF
        7'd60: frame_byte = 8'h0D;
        7'd61: frame_byte = 8'h0A;
        default: frame_byte = " ";
    endcase
end

// FSM
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state         <= STATE_IDLE;
        byte_index    <= 7'd0;
        boot_counter  <= 32'd0;
        tick_snapshot <= 32'd0;
        vc_snapshot   <= 2'd0;
        q_snapshot    <= 32'd0;
        x_snapshot    <= 32'd0;
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
                        q_snapshot    <= command_count;
                        x_snapshot    <= {last_error, error_count};
                        byte_index    <= 7'd0;
                        state         <= STATE_SEND;
                    end else begin
                        // uart_tx still draining a previous byte. The
                        // frame state machine should normally be idle
                        // when cadence fires because cadence_cycles is
                        // far longer than 62 bytes at 115200, but if
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
                    if (byte_index == FRAME_LEN[6:0] - 7'd1) begin
                        state <= STATE_IDLE;
                    end else begin
                        byte_index <= byte_index + 7'd1;
                        state      <= STATE_SEND;
                    end
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
