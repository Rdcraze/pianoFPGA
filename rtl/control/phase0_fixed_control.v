`timescale 1ns / 1ps

// Phase 5 M2 fixed-function RTL controller.
//
// Replaces the layered RISC-V SoC + firmware + MMIO + phase0_control_regs
// stack with a small sys_clk-domain state machine that drives the audio
// and codec control wires directly. Provides:
//
//   - hardwired audio defaults equivalent to the accepted M5/M7 baseline:
//       audio_enable = 1, tone_enable = 1, wave_sel = 2'b00 (square)
//       phase_step = 157482, gain = 4096, decay_step = 0
//       loop_gain = 32640, damp_mix = 16384 (default), disp_coeff = 9952
//       body_mix = 8192
//       four physical voice instances all enabled
//
//   - a small periodic round-robin trigger sequencer that fires voice0
//     -> voice1 -> voice2 -> voice3 with a fixed inter-trigger interval
//     so the board produces audible output without firmware. This matches
//     the role the firmware "round-robin smoke" loop used to play.
//
//   - in Phase 5 M2: optional UART command override. When the parser
//     emits a note_strobe the controller latches the command parameters
//     into the next-up voice's per-voice loop_len/velocity registers and
//     routes the trigger to that voice; when it emits release_strobe the
//     controller raises voice_damp_mix to 16'd32767 (release damping).
//     The next note after a release restores damp_mix to its default
//     16'd16384. Once any command arrives, autonomous round-robin
//     triggering is suppressed so host control is exclusive.
//
// What is intentionally deferred:
//   - UART TX command-feedback tags are owned by phase0_uart_status_tx.
//   - LRU / voice-stealing semantics. M2 always fires the next voice in
//     a round-robin order for command-driven notes, mirroring the M0
//     autonomous sequencer.
//   - Per-voice independent release. M2 release raises shared damp_mix
//     for all voices.

module phase0_fixed_control (
    input  wire               sys_clk,
    input  wire               sys_rst_n,

    // Sample-tick from codec to pace the trigger sequencer
    input  wire               sample_tick,

    // Phase 5 M2 UART command interface
    input  wire               note_strobe,
    input  wire               release_strobe,
    input  wire [6:0]         cmd_loop_len,
    input  wire [15:0]        cmd_velocity,

    // Phase 6 M1.1 single-voice isolation mode. When high, every
    // command-driven note_strobe routes to voice0 only; voices 1/2/3
    // see no command trigger from this controller. The top-level
    // audio path additionally mutes voices 1/2/3 from the mix while
    // isolation_mode is high so prior ringing cannot contaminate the
    // captured strike. The four physical voices remain instantiated.
    input  wire               isolation_mode,

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

    // Round-robin voice index for telemetry consumers (e.g. M1 UART
    // status TX). Tracks the next voice the sequencer will fire.
    output wire [1:0]         voice_index_status
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
// Static voice parameters (unchanged from M1)
// -------------------------------------------------------------------------
assign voice_loop_gain  = 16'd32640;
assign voice_disp_coeff = 16'sd9952;
assign voice_body_mix   = 16'd8192;

// -------------------------------------------------------------------------
// Per-voice loop_len / velocity registers
//
// Default values match the accepted M5/M7 baseline (loop_len=106,
// velocity=0x4000) so that with no UART activity the audible output is
// bit-identical to the M0/M1 baseline. UART command notes write the
// selected voice's pair before the trigger pulse fires.
// -------------------------------------------------------------------------
reg [6:0]  voice0_loop_len_reg, voice1_loop_len_reg;
reg [6:0]  voice2_loop_len_reg, voice3_loop_len_reg;
reg [15:0] voice0_velocity_reg, voice1_velocity_reg;
reg [15:0] voice2_velocity_reg, voice3_velocity_reg;

// "voice_velocity" / "voice_loop_len" without an index are legacy
// catch-all wires that the audio path no longer routes per voice. Tie
// them to the voice0 values so older diagnostic bench code still sees a
// consistent default.
assign voice_velocity  = voice0_velocity_reg;
assign voice_loop_len  = voice0_loop_len_reg;
assign voice0_velocity = voice0_velocity_reg;
assign voice0_loop_len = voice0_loop_len_reg;
assign voice1_velocity = voice1_velocity_reg;
assign voice1_loop_len = voice1_loop_len_reg;
assign voice2_velocity = voice2_velocity_reg;
assign voice2_loop_len = voice2_loop_len_reg;
assign voice3_velocity = voice3_velocity_reg;
assign voice3_loop_len = voice3_loop_len_reg;

// Damp mix register: default 16384, raised to 32767 on release.
reg [15:0] voice_damp_mix_reg;
assign voice_damp_mix = voice_damp_mix_reg;

// -------------------------------------------------------------------------
// Round-robin sequencer
//
// voice_index points at the voice that will fire on the NEXT trigger.
// Both autonomous cadence and command-driven note_strobe assert
// trigger_pulse and post-increment voice_index in the same cycle. The
// per-voice trigger fan-out compares against the post-incremented value,
// matching the M1 scheme that was hardware-accepted.
//
// Once any command arrives the autonomous cadence is suppressed and
// voice_index advances only on note_strobe.
// -------------------------------------------------------------------------
localparam [13:0] TICK_INTERVAL = 14'd16383; // 16384 sample ticks per voice

reg [13:0] tick_counter;
reg [1:0]  voice_index;
reg        trigger_pulse;
reg        command_mode;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tick_counter        <= 14'd0;
        voice_index         <= 2'd0;
        trigger_pulse       <= 1'b0;
        command_mode        <= 1'b0;
        voice_damp_mix_reg  <= 16'd16384;

        voice0_loop_len_reg <= 7'd106;
        voice1_loop_len_reg <= 7'd106;
        voice2_loop_len_reg <= 7'd106;
        voice3_loop_len_reg <= 7'd106;
        voice0_velocity_reg <= 16'h4000;
        voice1_velocity_reg <= 16'h4000;
        voice2_velocity_reg <= 16'h4000;
        voice3_velocity_reg <= 16'h4000;
    end else begin
        trigger_pulse <= 1'b0;

        // Autonomous round-robin sequencer (suppressed once any command
        // arrives so host control is exclusive).
        if (sample_tick && !command_mode) begin
            if (tick_counter == TICK_INTERVAL) begin
                tick_counter  <= 14'd0;
                voice_index   <= voice_index + 2'd1;
                trigger_pulse <= 1'b1;
            end else begin
                tick_counter <= tick_counter + 14'd1;
            end
        end

        // UART command path. note_strobe and release_strobe are
        // single-cycle pulses out of phase0_uart_command. They have
        // priority over the autonomous cadence (in practice both will
        // never fire on the same cycle once command_mode is set).
        if (note_strobe) begin
            command_mode       <= 1'b1;
            // First note after a release should clear release damping.
            voice_damp_mix_reg <= 16'd16384;

            if (isolation_mode) begin
                // Phase 6 M1.1: in isolation mode, every command note
                // is routed to voice0 (no voice_index advance). The
                // delay-line clear inside phase1_reduced_voice on
                // trigger_strobe ensures the strike starts from a
                // silent buffer.
                voice0_loop_len_reg <= cmd_loop_len;
                voice0_velocity_reg <= cmd_velocity;
                voice_index         <= 2'd0;
                trigger_pulse       <= 1'b1;
                tick_counter        <= 14'd0;
            end else begin
                // Normal command-mode round-robin: write parameters
                // to the voice that will fire next cycle (post-
                // incremented voice_index points at that voice).
                case (voice_index + 2'd1)
                    2'd0: begin
                        voice0_loop_len_reg <= cmd_loop_len;
                        voice0_velocity_reg <= cmd_velocity;
                    end
                    2'd1: begin
                        voice1_loop_len_reg <= cmd_loop_len;
                        voice1_velocity_reg <= cmd_velocity;
                    end
                    2'd2: begin
                        voice2_loop_len_reg <= cmd_loop_len;
                        voice2_velocity_reg <= cmd_velocity;
                    end
                    default: begin
                        voice3_loop_len_reg <= cmd_loop_len;
                        voice3_velocity_reg <= cmd_velocity;
                    end
                endcase

                voice_index   <= voice_index + 2'd1;
                trigger_pulse <= 1'b1;
                tick_counter  <= 14'd0;
            end
        end else if (release_strobe) begin
            command_mode       <= 1'b1;
            voice_damp_mix_reg <= 16'd32767;
        end
    end
end

assign voice_trigger_strobe  = trigger_pulse && (voice_index == 2'd0);
assign voice1_trigger_strobe = trigger_pulse && (voice_index == 2'd1);
assign voice2_trigger_strobe = trigger_pulse && (voice_index == 2'd2);
assign voice3_trigger_strobe = trigger_pulse && (voice_index == 2'd3);

// Telemetry handle on the round-robin voice index. Stays in sys_clk;
// no CDC required at the consumer.
assign voice_index_status = voice_index;

endmodule
