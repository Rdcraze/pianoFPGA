`timescale 1ns / 1ps

// Phase 6 M1.1 isolation-mode focused TB for phase0_fixed_control.
//
// Verifies two routing behaviors of the controller's command path:
//
//   Normal mode (isolation_mode = 0):
//     Four consecutive note_strobes fan out across voice0..voice3 in
//     round-robin order, exactly as accepted in Phase 5 M2/M3.
//
//   Isolation mode (isolation_mode = 1):
//     Four consecutive note_strobes all route to voice0; voices 1..3
//     receive zero trigger pulses. voice_index_status remains at 0.
//
// The TB drives the controller's command interface directly with
// strobes and parameter wires; it does NOT involve the UART RX path or
// the audio synthesis blocks. Pure controller-routing test.

module phase0_fixed_control_isolation_tb;

reg sys_clk;
reg sys_rst_n;
reg sample_tick;
reg note_strobe;
reg release_strobe;
reg [6:0] cmd_loop_len;
reg [15:0] cmd_velocity;
reg isolation_mode;

// Outputs we care about
wire voice_trigger_strobe;
wire voice1_trigger_strobe;
wire voice2_trigger_strobe;
wire voice3_trigger_strobe;
wire [1:0] voice_index_status;
wire [6:0] voice0_loop_len;
wire [6:0] voice1_loop_len;
wire [6:0] voice2_loop_len;
wire [6:0] voice3_loop_len;
wire [15:0] voice0_velocity;
wire [15:0] voice1_velocity;
wire [15:0] voice2_velocity;
wire [15:0] voice3_velocity;
wire [15:0] voice_damp_mix;

// Other outputs we ignore
wire audio_enable, tone_enable, trigger_strobe, codec_cfg_valid;
wire [1:0] wave_sel;
wire [23:0] phase_step;
wire [15:0] gain;
wire [15:0] decay_step;
wire [15:0] codec_cfg_word;
wire voice_enable, voice_reset_strobe, voice_clip_clear_strobe;
wire voice_diag_clear_strobe, voice_body_bypass, voice_disp_bypass;
wire voice1_enable, voice1_reset_strobe, voice1_clip_clear_strobe;
wire voice2_enable, voice2_reset_strobe, voice2_clip_clear_strobe;
wire voice3_enable, voice3_reset_strobe, voice3_clip_clear_strobe;
wire [15:0] voice_velocity_legacy;
wire [6:0] voice_loop_len_legacy;
wire [15:0] voice_loop_gain;
wire signed [15:0] voice_disp_coeff;
wire [15:0] voice_body_mix;

phase0_fixed_control dut (
    .sys_clk                  (sys_clk),
    .sys_rst_n                (sys_rst_n),
    .sample_tick              (sample_tick),
    .note_strobe              (note_strobe),
    .release_strobe           (release_strobe),
    .cmd_loop_len             (cmd_loop_len),
    .cmd_velocity             (cmd_velocity),
    .isolation_mode           (isolation_mode),
    .body_mix_runtime         (16'd12288),
    .damp_mix_runtime         (16'd16384),
    .disp_coeff_runtime       (16'sd9952),
    .audio_enable             (audio_enable),
    .tone_enable              (tone_enable),
    .wave_sel                 (wave_sel),
    .trigger_strobe           (trigger_strobe),
    .codec_cfg_valid          (codec_cfg_valid),
    .phase_step               (phase_step),
    .gain                     (gain),
    .decay_step               (decay_step),
    .codec_cfg_word           (codec_cfg_word),
    .voice_enable             (voice_enable),
    .voice_trigger_strobe     (voice_trigger_strobe),
    .voice_reset_strobe       (voice_reset_strobe),
    .voice_clip_clear_strobe  (voice_clip_clear_strobe),
    .voice_diag_clear_strobe  (voice_diag_clear_strobe),
    .voice_body_bypass        (voice_body_bypass),
    .voice_disp_bypass        (voice_disp_bypass),
    .voice1_enable            (voice1_enable),
    .voice1_trigger_strobe    (voice1_trigger_strobe),
    .voice1_reset_strobe      (voice1_reset_strobe),
    .voice1_clip_clear_strobe (voice1_clip_clear_strobe),
    .voice2_enable            (voice2_enable),
    .voice2_trigger_strobe    (voice2_trigger_strobe),
    .voice2_reset_strobe      (voice2_reset_strobe),
    .voice2_clip_clear_strobe (voice2_clip_clear_strobe),
    .voice3_enable            (voice3_enable),
    .voice3_trigger_strobe    (voice3_trigger_strobe),
    .voice3_reset_strobe      (voice3_reset_strobe),
    .voice3_clip_clear_strobe (voice3_clip_clear_strobe),
    .voice_velocity           (voice_velocity_legacy),
    .voice_loop_len           (voice_loop_len_legacy),
    .voice0_velocity          (voice0_velocity),
    .voice0_loop_len          (voice0_loop_len),
    .voice1_velocity          (voice1_velocity),
    .voice1_loop_len          (voice1_loop_len),
    .voice2_velocity          (voice2_velocity),
    .voice2_loop_len          (voice2_loop_len),
    .voice3_velocity          (voice3_velocity),
    .voice3_loop_len          (voice3_loop_len),
    .voice_loop_gain          (voice_loop_gain),
    .voice_damp_mix           (voice_damp_mix),
    .voice_disp_coeff         (voice_disp_coeff),
    .voice_body_mix           (voice_body_mix),
    .voice_index_status       (voice_index_status)
);

// 50 MHz clock
always #10 sys_clk = ~sys_clk;

// Counters
integer v0_trig, v1_trig, v2_trig, v3_trig;
integer v0_reset_seen;
always @(posedge sys_clk) begin
    if (sys_rst_n) begin
        if (voice_trigger_strobe)  v0_trig <= v0_trig + 1;
        if (voice1_trigger_strobe) v1_trig <= v1_trig + 1;
        if (voice2_trigger_strobe) v2_trig <= v2_trig + 1;
        if (voice3_trigger_strobe) v3_trig <= v3_trig + 1;
        if (voice_reset_strobe)    v0_reset_seen <= v0_reset_seen + 1;
    end
end

task pulse_release;
    begin
        @(posedge sys_clk);
        release_strobe = 1'b1;
        @(posedge sys_clk);
        release_strobe = 1'b0;
        // Allow several cycles for the reset pulse to propagate.
        repeat (4) @(posedge sys_clk);
    end
endtask

task pulse_note;
    input [6:0] ll;
    input [15:0] vel;
    begin
        cmd_loop_len  = ll;
        cmd_velocity  = vel;
        @(posedge sys_clk);
        note_strobe = 1'b1;
        @(posedge sys_clk);
        note_strobe = 1'b0;
        // Allow several cycles for the trigger pulse to propagate.
        repeat (4) @(posedge sys_clk);
    end
endtask

integer fails;
initial begin
    fails       = 0;
    sys_clk     = 1'b0;
    sys_rst_n   = 1'b0;
    sample_tick = 1'b0;
    note_strobe = 1'b0;
    release_strobe = 1'b0;
    cmd_loop_len  = 7'd106;
    cmd_velocity  = 16'h7FFF;
    isolation_mode = 1'b0;
    v0_trig = 0; v1_trig = 0; v2_trig = 0; v3_trig = 0;
    v0_reset_seen = 0;

    repeat (8) @(posedge sys_clk);
    sys_rst_n = 1'b1;
    repeat (8) @(posedge sys_clk);

    if (voice_damp_mix !== 16'h4000) begin
        $display("ISO_TB_FAIL reset_damp expected=0x4000 got=0x%04h",
                 voice_damp_mix);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS reset_damp=0x4000");
    end

    // ----- Normal mode round-robin ------------------------------------
    // Send 4 notes; expect each to land on a different voice in
    // round-robin order, matching M2/M3 behavior.
    isolation_mode = 1'b0;
    pulse_note(7'd106, 16'h2000);
    pulse_note(7'd89,  16'h4000);
    pulse_note(7'd53,  16'h7FFF);
    pulse_note(7'd32,  16'h6000);

    if (v0_trig != 1 || v1_trig != 1 || v2_trig != 1 || v3_trig != 1) begin
        $display("ISO_TB_FAIL normal_mode_roundrobin v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS normal_mode_roundrobin v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
    end

    // ----- Isolation mode: all to voice0 ------------------------------
    // Reset trigger counters and enable isolation.
    v0_trig = 0; v1_trig = 0; v2_trig = 0; v3_trig = 0;
    isolation_mode = 1'b1;
    repeat (4) @(posedge sys_clk);

    pulse_note(7'd106, 16'h2000);
    pulse_note(7'd89,  16'h4000);
    pulse_note(7'd53,  16'h7FFF);
    pulse_note(7'd32,  16'h6000);

    if (v0_trig != 4 || v1_trig != 0 || v2_trig != 0 || v3_trig != 0) begin
        $display("ISO_TB_FAIL isolation_mode v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS isolation_mode v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
    end

    // voice_index_status should still read 0 in isolation mode (the
    // controller does not advance it).
    if (voice_index_status !== 2'd0) begin
        $display("ISO_TB_FAIL voice_index_after_isolation got=%0d want=0",
                 voice_index_status);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS voice_index_after_isolation=0");
    end

    // The latest cmd parameters should have landed on voice0.
    if (voice0_loop_len !== 7'd32 || voice0_velocity !== 16'h6000) begin
        $display("ISO_TB_FAIL voice0_params loop_len=%0d vel=%04x",
                 voice0_loop_len, voice0_velocity);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS voice0_params loop_len=32 vel=0x6000");
    end

    // ----- Phase 6 M1.2: !F in isolation mode pulses voice0 reset ----
    // isolation_mode is still 1 from above. Reset the local reset
    // counter and verify a single release_strobe asserts the
    // voice_reset_strobe pulse exactly once.
    v0_reset_seen = 0;
    pulse_release();
    if (v0_reset_seen != 1) begin
        $display("ISO_TB_FAIL release_in_isolation_resets_voice0 got=%0d want=1",
                 v0_reset_seen);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS release_in_isolation_resets_voice0 reset_count=%0d",
                 v0_reset_seen);
    end
    // Damp mix should be raised to 32767 like normal release.
    if (voice_damp_mix !== 16'd32767) begin
        $display("ISO_TB_FAIL release_in_isolation_damp got=%04x want=7FFF",
                 voice_damp_mix);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS release_in_isolation_damp=0x7FFF");
    end
    // Triggers must NOT fire on a release.
    if (v0_trig != 4 || v1_trig != 0 || v2_trig != 0 || v3_trig != 0) begin
        $display("ISO_TB_FAIL release_in_isolation_no_trigger v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS release_in_isolation_no_trigger");
    end

    // A subsequent isolated note still routes to voice0; reset is
    // only on release, not on note.
    pulse_note(7'd106, 16'h4000);
    if (v0_trig != 5 || v1_trig != 0 || v2_trig != 0 || v3_trig != 0) begin
        $display("ISO_TB_FAIL isolated_note_after_reset v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS isolated_note_after_reset");
    end

    // ----- Disable isolation; resume round-robin from voice_index 0 ---
    v0_trig = 0; v1_trig = 0; v2_trig = 0; v3_trig = 0;
    isolation_mode = 1'b0;
    repeat (4) @(posedge sys_clk);

    pulse_note(7'd106, 16'h7FFF);  // expected voice1 (post-increment from 0)
    pulse_note(7'd89,  16'h7FFF);  // expected voice2
    pulse_note(7'd53,  16'h7FFF);  // expected voice3
    pulse_note(7'd32,  16'h7FFF);  // expected voice0

    if (v0_trig != 1 || v1_trig != 1 || v2_trig != 1 || v3_trig != 1) begin
        $display("ISO_TB_FAIL post_isolation_roundrobin v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS post_isolation_roundrobin v0=%0d v1=%0d v2=%0d v3=%0d",
                 v0_trig, v1_trig, v2_trig, v3_trig);
    end

    // ----- Phase 6 M1.2: !F in normal mode does NOT pulse voice0 reset
    // isolation_mode is 0 here (just disabled above). Pulse a release
    // and confirm the reset counter does NOT advance, while damp mix
    // still rises (preserving Phase 5 M2/M3 release semantics).
    v0_reset_seen = 0;
    pulse_release();
    if (v0_reset_seen != 0) begin
        $display("ISO_TB_FAIL release_in_normal_no_reset got=%0d want=0",
                 v0_reset_seen);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS release_in_normal_no_reset");
    end
    if (voice_damp_mix !== 16'd32767) begin
        $display("ISO_TB_FAIL release_in_normal_damp got=%04x want=7FFF",
                 voice_damp_mix);
        fails = fails + 1;
    end else begin
        $display("ISO_TB_PASS release_in_normal_damp=0x7FFF");
    end

    if (fails == 0) begin
        $display("ISOLATION_TB_PASS");
    end else begin
        $display("ISOLATION_TB_FAIL fails=%0d", fails);
    end
    $finish;
end

initial begin
    #1_000_000; // 1 ms safety timeout
    $display("ISOLATION_TB_FAIL timeout");
    $finish;
end

endmodule
