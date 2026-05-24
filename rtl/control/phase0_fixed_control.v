`timescale 1ns / 1ps

// Phase 5 M0 fixed-function RTL controller.
//
// Replaces the layered RISC-V SoC + firmware + MMIO + phase0_control_regs
// stack with a small sys_clk-domain state machine that drives the audio
// and codec control wires directly. Provides:
//
//   - hardwired audio defaults equivalent to the accepted M5/M7 baseline:
//       audio_enable = 1, tone_enable = 1, wave_sel = 2'b00 (square)
//       phase_step = 157482, gain = 4096, decay_step = 0
//       loop_len = 106, velocity = 16'h4000 (TB-default-equivalent)
//       loop_gain = 32640, damp_mix = 16384, disp_coeff = 9952
//       body_mix = 8192
//       four physical voice instances all enabled
//
//   - a small periodic round-robin trigger sequencer that fires voice0
//     -> voice1 -> voice2 -> voice3 with a fixed inter-trigger interval
//     so the board produces audible output without firmware. This matches
//     the role the firmware "round-robin smoke" loop used to play.
//
//   - the codec config valid/word path tied off. wm8978_codec_stub already
//     owns its own boot sequence, so the fixed controller does not need
//     to inject post-boot codec writes.
//
// What is intentionally deferred:
//   - UART RX command parsing. uart1_rx is not consumed by this controller.
//   - UART TX telemetry. uart1_tx is driven idle high. A later milestone
//     can add a small RTL telemetry transmitter or a small command parser
//     without revisiting the whole control stack.
//   - Run-time per-voice retuning. Velocity/loop_len/etc are compile-time
//     constants for now; they can be promoted to localparam/wire ports
//     later without re-introducing a CPU/MMIO bus.

module phase0_fixed_control (
    input  wire               sys_clk,
    input  wire               sys_rst_n,

    // Sample-tick from codec to pace the trigger sequencer
    input  wire               sample_tick,

    // Sample-generator / global control
    output wire               audio_enable,
    output wire               tone_enable,
    output wire [1:0]         wave_sel,
    output wire               trigger_strobe,
    output wire               codec_cfg_valid,
    output wire [23:0]        phase_step,
    output wire [15:0]        gain,
    output wire [15:0]        decay_step,
    output wire [15:0]        codec_cfg_word,

    // Voice-bank controls
    output wire               voice_enable,
    output wire               voice_trigger_strobe,
    output wire               voice_reset_strobe,
    output wire               voice_clip_clear_strobe,
    output wire               voice_diag_clear_strobe,
    output wire               voice_body_bypass,
    output wire               voice_disp_bypass,
    output wire               voice1_enable,
    output wire               voice1_trigger_strobe,
    output wire               voice1_reset_strobe,
    output wire               voice1_clip_clear_strobe,
    output wire               voice2_enable,
    output wire               voice2_trigger_strobe,
    output wire               voice2_reset_strobe,
    output wire               voice2_clip_clear_strobe,
    output wire               voice3_enable,
    output wire               voice3_trigger_strobe,
    output wire               voice3_reset_strobe,
    output wire               voice3_clip_clear_strobe,

    // Per-voice parameter outputs
    output wire [15:0]        voice_velocity,
    output wire [6:0]         voice_loop_len,
    output wire [15:0]        voice0_velocity,
    output wire [6:0]         voice0_loop_len,
    output wire [15:0]        voice1_velocity,
    output wire [6:0]         voice1_loop_len,
    output wire [15:0]        voice2_velocity,
    output wire [6:0]         voice2_loop_len,
    output wire [15:0]        voice3_velocity,
    output wire [6:0]         voice3_loop_len,
    output wire [15:0]        voice_loop_gain,
    output wire [15:0]        voice_damp_mix,
    output wire signed [15:0] voice_disp_coeff,
    output wire [15:0]        voice_body_mix,

    // Idle UART TX. Held high (RS-232 idle / 8N1 mark).
    output wire               uart1_tx
);

// -------------------------------------------------------------------------
// Hardwired global / sample-gen defaults
// -------------------------------------------------------------------------
assign audio_enable    = 1'b1;
assign tone_enable     = 1'b1;
assign wave_sel        = 2'b00;
assign codec_cfg_valid = 1'b0;
assign codec_cfg_word  = 16'd0;
assign phase_step      = 24'd157482;
assign gain            = 16'd4096;
assign decay_step      = 16'd0;

// Legacy "global" trigger_strobe path is unused by the four-voice path; we
// drive it inactive. Per-voice strobes below are the only live triggers.
assign trigger_strobe = 1'b0;

// -------------------------------------------------------------------------
// Voice-bank static enables and bypass
// -------------------------------------------------------------------------
assign voice_enable           = 1'b1;
assign voice1_enable          = 1'b1;
assign voice2_enable          = 1'b1;
assign voice3_enable          = 1'b1;
assign voice_body_bypass      = 1'b0;
assign voice_disp_bypass      = 1'b0;
assign voice_reset_strobe     = 1'b0;
assign voice1_reset_strobe    = 1'b0;
assign voice2_reset_strobe    = 1'b0;
assign voice3_reset_strobe    = 1'b0;
assign voice_clip_clear_strobe  = 1'b0;
assign voice1_clip_clear_strobe = 1'b0;
assign voice2_clip_clear_strobe = 1'b0;
assign voice3_clip_clear_strobe = 1'b0;
assign voice_diag_clear_strobe  = 1'b0;

// -------------------------------------------------------------------------
// Per-voice parameter defaults
// -------------------------------------------------------------------------
assign voice_velocity   = 16'h4000;
assign voice_loop_len   = 7'd106;
assign voice0_velocity  = 16'h4000;
assign voice0_loop_len  = 7'd106;
assign voice1_velocity  = 16'h4000;
assign voice1_loop_len  = 7'd106;
assign voice2_velocity  = 16'h4000;
assign voice2_loop_len  = 7'd106;
assign voice3_velocity  = 16'h4000;
assign voice3_loop_len  = 7'd106;
assign voice_loop_gain  = 16'd32640;
assign voice_damp_mix   = 16'd16384;
assign voice_disp_coeff = 16'sd9952;
assign voice_body_mix   = 16'd8192;

// -------------------------------------------------------------------------
// Periodic round-robin trigger sequencer
//
// At ~46.875 kHz sample rate, an inter-trigger gap of ~16384 sample ticks
// is roughly 350 ms, similar to the firmware-managed round-robin demo
// cadence. The exact value is documented but not load-bearing: it just
// produces continuous audible activity across all four voices.
// -------------------------------------------------------------------------
localparam [13:0] TICK_INTERVAL = 14'd16383; // 16384 sample ticks per voice

reg [13:0] tick_counter;
reg [1:0]  voice_index;
reg        trigger_pulse;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tick_counter  <= 14'd0;
        voice_index   <= 2'd0;
        trigger_pulse <= 1'b0;
    end else begin
        trigger_pulse <= 1'b0;
        if (sample_tick) begin
            if (tick_counter == TICK_INTERVAL) begin
                tick_counter  <= 14'd0;
                voice_index   <= voice_index + 2'd1;
                trigger_pulse <= 1'b1;
            end else begin
                tick_counter <= tick_counter + 14'd1;
            end
        end
    end
end

assign voice_trigger_strobe  = trigger_pulse && (voice_index == 2'd0);
assign voice1_trigger_strobe = trigger_pulse && (voice_index == 2'd1);
assign voice2_trigger_strobe = trigger_pulse && (voice_index == 2'd2);
assign voice3_trigger_strobe = trigger_pulse && (voice_index == 2'd3);

// -------------------------------------------------------------------------
// UART1 TX idle. RS-232 idle state is high (mark). A future milestone may
// replace this with a small RTL transmitter without revisiting top-level.
// -------------------------------------------------------------------------
assign uart1_tx = 1'b1;

endmodule
