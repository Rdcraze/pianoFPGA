`timescale 1ns / 1ps

// Phase 6 M6.2 body_mix MSB-saturating regression check.
//
// Drives phase1_reduced_voice with two back-to-back single-shot
// strikes that reset the voice between strikes:
//   strike A: body_mix_q15 = 16'h7FFF
//   strike B: body_mix_q15 = 16'hFFFF
//
// With the M6.2 fix at STATE_BODY_TAP30, both values map to the
// same body multiplier coefficient (+32767, signed), so the
// captured output samples must be bit-identical.
//
// Before the fix, body_mix_q15 = 16'hFFFF was reinterpreted as
// signed -1, phase-flipping the body contribution and producing
// a different (and typically much smaller in magnitude) sample
// stream. This TB locks that regression out.
//
// The TB also exercises body_mix_q15 = 16'hC000 to confirm it
// does NOT silently become a negative coefficient: it must
// also saturate to the same mapping as 16'h7FFF.
//
// Compatibility: keeps the existing in-range body_mix golden
// behavior unchanged because it does not touch body_mix
// values <= 0x7FFF; it only adds high-range coverage.

module phase1_reduced_voice_body_mix_sat_tb;

localparam integer TICK_DIV = 40;
localparam integer CAPTURE_START = 9375;        // ~200 ms
localparam integer CAPTURE_COUNT = 1024;
localparam integer TOTAL_SAMPLES = CAPTURE_START + CAPTURE_COUNT + 200;

reg sys_clk;
reg sys_rst_n;
reg sample_tick;
reg enable;
reg trigger_strobe;
reg reset_strobe;
reg clip_clear_strobe;
reg body_bypass;
reg disp_bypass;
reg [15:0] velocity_q15;
reg [6:0] loop_len;
reg [15:0] loop_gain_q15;
reg [15:0] damp_mix_q15;
reg signed [15:0] disp_coeff_q15;
reg [15:0] body_mix_q15;

wire signed [15:0] sample_data;
wire sample_valid;
wire active;
wire excite_busy;
wire clip_seen;
wire [15:0] peak_level;

integer tick_count;
integer sample_count;
integer cap_count;
integer cap_index;
integer mismatch_count;
integer fails;
integer trigger_count;
integer i;
reg trigger_seen;
reg capturing;
reg awaiting_idle;
reg signed [15:0] cap_a [0:CAPTURE_COUNT - 1];
reg signed [15:0] cap_b [0:CAPTURE_COUNT - 1];
reg cap_target;  // 0 = strike A, 1 = strike B

phase1_reduced_voice dut (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .sample_tick      (sample_tick),
    .enable           (enable),
    .trigger_strobe   (trigger_strobe),
    .reset_strobe     (reset_strobe),
    .clip_clear_strobe(clip_clear_strobe),
    .body_bypass      (body_bypass),
    .disp_bypass      (disp_bypass),
    .velocity_q15     (velocity_q15),
    .loop_len         (loop_len),
    .loop_gain_q15    (loop_gain_q15),
    .damp_mix_q15     (damp_mix_q15),
    .disp_coeff_q15   (disp_coeff_q15),
    .body_mix_q15     (body_mix_q15),
    .sample_data      (sample_data),
    .sample_valid     (sample_valid),
    .active           (active),
    .excite_busy      (excite_busy),
    .clip_seen        (clip_seen),
    .peak_level       (peak_level)
);

always #10 sys_clk = ~sys_clk;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tick_count  <= 0;
        sample_tick <= 1'b0;
    end else begin
        if (tick_count == (TICK_DIV - 1)) begin
            tick_count  <= 0;
            sample_tick <= 1'b1;
        end else begin
            tick_count  <= tick_count + 1;
            sample_tick <= 1'b0;
        end
    end
end

// Capture sample stream for the current strike.
always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
        sample_count <= 0;
        cap_count    <= 0;
        trigger_seen <= 1'b0;
    end else begin
        if (trigger_strobe) begin
            trigger_seen <= 1'b1;
            sample_count <= 0;
            cap_count    <= 0;
        end
        if (reset_strobe) begin
            trigger_seen <= 1'b0;
            sample_count <= 0;
            cap_count    <= 0;
        end
        if (sample_valid && trigger_seen) begin
            sample_count <= sample_count + 1;
            if ((sample_count >= CAPTURE_START) &&
                (cap_count < CAPTURE_COUNT)) begin
                if (cap_target == 1'b0) begin
                    cap_a[cap_count] <= sample_data;
                end else begin
                    cap_b[cap_count] <= sample_data;
                end
                cap_count <= cap_count + 1;
            end
        end
    end
end

task run_strike(input [15:0] body_mix_value, input target);
begin
    cap_target = target;
    // Reset voice between strikes so delay/body history are clean.
    reset_strobe = 1'b1;
    @(posedge sys_clk);
    reset_strobe = 1'b0;
    // Wait for clear sweep to complete (32 entries x ~20 cycles
    // worst case) plus a settle margin.
    repeat (200) @(posedge sys_clk);

    // Set the test body_mix value.
    body_mix_q15 = body_mix_value;
    repeat (10) @(posedge sys_clk);

    // Trigger.
    trigger_strobe = 1'b1;
    repeat (2) @(posedge sys_clk);
    trigger_strobe = 1'b0;

    // Run long enough for capture window to fill.
    while (sample_count < TOTAL_SAMPLES) begin
        @(posedge sys_clk);
    end
end
endtask

initial begin
    sys_clk = 1'b0;
    sys_rst_n = 1'b0;
    enable = 1'b1;
    trigger_strobe = 1'b0;
    reset_strobe = 1'b0;
    clip_clear_strobe = 1'b0;
    body_bypass = 1'b0;
    disp_bypass = 1'b0;
    velocity_q15 = 16'h4000;
    loop_len = 7'd106;
    loop_gain_q15 = 16'd32640;
    damp_mix_q15 = 16'd16384;
    disp_coeff_q15 = 16'sd9952;
    body_mix_q15 = 16'd12288;
    cap_target = 1'b0;
    fails = 0;

    #5000;
    sys_rst_n = 1'b1;
    #20000;

    // ---- Strike A: body_mix = 0x7FFF (max in-range, MSB clear) ----
    run_strike(16'h7FFF, 1'b0);

    // ---- Strike B: body_mix = 0xFFFF (MSB set, must saturate) ----
    run_strike(16'hFFFF, 1'b1);

    // Compare cap_a vs cap_b sample-by-sample. With the M6.2 fix
    // both runs should produce mult_coeff = +32767 in
    // STATE_BODY_TAP30, so every captured sample must match.
    mismatch_count = 0;
    for (i = 0; i < CAPTURE_COUNT; i = i + 1) begin
        if (cap_a[i] !== cap_b[i]) begin
            if (mismatch_count < 8) begin
                $display("VOICE_BMSAT_TB_FAIL_DETAIL i=%0d a=%0d b=%0d",
                         i, $signed(cap_a[i]), $signed(cap_b[i]));
            end
            mismatch_count = mismatch_count + 1;
        end
    end

    if (mismatch_count != 0) begin
        $display("VOICE_BMSAT_TB_FAIL mismatches=%0d / %0d",
                 mismatch_count, CAPTURE_COUNT);
        fails = fails + 1;
    end else begin
        $display("VOICE_BMSAT_TB_PASS_FFFF samples_compared=%0d",
                 CAPTURE_COUNT);
    end

    // ---- Strike C: body_mix = 0xC000 (MSB set, mid range) ----
    // Reuse cap_b array.
    cap_count = 0;
    run_strike(16'hC000, 1'b1);

    mismatch_count = 0;
    for (i = 0; i < CAPTURE_COUNT; i = i + 1) begin
        if (cap_a[i] !== cap_b[i]) begin
            if (mismatch_count < 8) begin
                $display("VOICE_BMSAT_TB_FAIL_DETAIL_C000 i=%0d a=%0d b=%0d",
                         i, $signed(cap_a[i]), $signed(cap_b[i]));
            end
            mismatch_count = mismatch_count + 1;
        end
    end

    if (mismatch_count != 0) begin
        $display("VOICE_BMSAT_TB_FAIL_C000 mismatches=%0d / %0d",
                 mismatch_count, CAPTURE_COUNT);
        fails = fails + 1;
    end else begin
        $display("VOICE_BMSAT_TB_PASS_C000 samples_compared=%0d",
                 CAPTURE_COUNT);
    end

    if (fails == 0) begin
        $display("VOICE_BMSAT_TB_PASS body_mix saturation verified at 0xFFFF and 0xC000");
    end else begin
        $display("VOICE_BMSAT_TB_FAIL fails=%0d", fails);
    end
    $finish;
end

endmodule
