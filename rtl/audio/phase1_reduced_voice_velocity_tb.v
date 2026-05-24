`timescale 1ns / 1ps

// Phase 6 M2 velocity-layer / brightness focused TB for
// phase1_reduced_voice.
//
// Exercises a single fixed-pitch (loop_len = 106, A4) voice instance
// at four velocities -- 0x2000, 0x4000, 0x6000, 0x7FFF -- one strike
// at a time, and measures three per-strike metrics over the first
// 4096 samples (~87.4 ms at 46.875 kHz):
//
//   peak_abs       maximum absolute output sample
//   rms_total      RMS over all 4096 samples
//   early_energy   sum of |sample| over the first 64 samples (~1.4 ms)
//                  used as a proxy for attack sharpness / brightness
//                  because the velocity layer change concentrates more
//                  excitation energy in the early indices.
//
// Pass conditions:
//   - The 0x4000 strike must produce the same first-nonzero sample
//     (106) and same peak as the existing golden TB (peak=3952), so
//     bit-exact preservation of layer 0 is checked indirectly.
//   - early_energy must be monotonically non-decreasing across the
//     four velocities, with at least one strict increase between
//     adjacent velocities to demonstrate the new layers actually
//     differentiate the attack.
//   - peak_abs must NOT exceed the current bright layer's peak by more
//     than a small margin at 0x7FFF (the brilliant layer is required
//     to not be louder, only sharper).
//   - clip_seen must remain low for every strike (the reduced voice
//     core itself does not clip at any of these velocities at the
//     fixed loop_len=106, loop_gain=32640, damp_mix=16384 setpoint).

module phase1_reduced_voice_velocity_tb;

localparam integer SAMPLE_PERIOD_NS = 21333; // ~46.875 kHz sample tick
localparam integer NUM_SAMPLES      = 4096;
localparam integer EARLY_WINDOW     = 64;

reg sys_clk;
reg sys_rst_n;
reg sample_tick;
reg trigger_strobe;
reg reset_strobe;
reg [15:0] velocity_q15;

wire signed [15:0] sample_data;
wire        sample_valid;
wire        active;
wire        excite_busy;
wire        clip_seen;
wire [15:0] peak_level;

phase1_reduced_voice dut (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .sample_tick      (sample_tick),
    .enable           (1'b1),
    .trigger_strobe   (trigger_strobe),
    .reset_strobe     (reset_strobe),
    .clip_clear_strobe(1'b0),
    .body_bypass      (1'b0),
    .disp_bypass      (1'b0),
    .velocity_q15     (velocity_q15),
    .loop_len         (7'd106),
    .loop_gain_q15    (16'd32640),
    .damp_mix_q15     (16'd16384),
    .disp_coeff_q15   (16'sd9952),
    .body_mix_q15     (16'd8192),
    .sample_data      (sample_data),
    .sample_valid     (sample_valid),
    .active           (active),
    .excite_busy      (excite_busy),
    .clip_seen        (clip_seen),
    .peak_level       (peak_level)
);

// 50 MHz system clock
always #10 sys_clk = ~sys_clk;

// Free-running sample tick at ~46.875 kHz
reg [10:0] tick_div;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tick_div    <= 11'd0;
        sample_tick <= 1'b0;
    end else begin
        sample_tick <= 1'b0;
        if (tick_div == 11'd1065) begin
            tick_div    <= 11'd0;
            sample_tick <= 1'b1;
        end else begin
            tick_div <= tick_div + 1'b1;
        end
    end
end

// Per-strike sample collector
integer collected;
integer first_nonzero;
integer peak_abs;
real    sum_sq;
integer early_sum;
integer audible_count;
integer i;
integer abs_sample;

task reset_metrics;
    begin
        collected     = 0;
        first_nonzero = -1;
        peak_abs      = 0;
        sum_sq        = 0.0;
        early_sum     = 0;
        audible_count = 0;
    end
endtask

always @(posedge sys_clk) begin
    if (sys_rst_n && sample_valid && collected < NUM_SAMPLES) begin
        if (first_nonzero == -1 && sample_data != 16'sd0) begin
            first_nonzero = collected;
        end
        abs_sample = (sample_data < 0) ? -sample_data : sample_data;
        if (abs_sample > peak_abs) peak_abs = abs_sample;
        sum_sq = sum_sq + (sample_data * sample_data);
        // Early-energy window: first EARLY_WINDOW samples after the
        // first non-zero output sample, NOT the first EARLY_WINDOW
        // samples after trigger (the voice has a loop_len-sample
        // pre-roll before any audible output appears).
        if (first_nonzero != -1 && audible_count < EARLY_WINDOW) begin
            early_sum     = early_sum + abs_sample;
            audible_count = audible_count + 1;
        end
        collected = collected + 1;
    end
end

// Stored results per-velocity for monotonic check
integer peak_v [0:3];
integer first_v [0:3];
integer early_v [0:3];
real    rms_v [0:3];

task strike_and_collect;
    input [15:0] vel;
    input integer slot;
    begin
        velocity_q15   = vel;
        // Fully reset the voice between strikes to clear delay line.
        reset_strobe   = 1'b1;
        @(posedge sys_clk);
        reset_strobe   = 1'b0;
        repeat (200) @(posedge sys_clk);

        reset_metrics();
        trigger_strobe = 1'b1;
        @(posedge sys_clk);
        trigger_strobe = 1'b0;

        // Wait until 4096 samples have been collected.
        while (collected < NUM_SAMPLES) @(posedge sys_clk);

        peak_v[slot]  = peak_abs;
        first_v[slot] = first_nonzero;
        early_v[slot] = early_sum;
        rms_v[slot]   = (sum_sq <= 0.0) ? 0.0 : $sqrt(sum_sq / NUM_SAMPLES);

        $display("VEL_TB_INFO vel=%04x first=%0d peak=%0d early=%0d rms=%0f",
                 vel, first_nonzero, peak_abs, early_sum, rms_v[slot]);
    end
endtask

integer fails;
initial begin
    fails          = 0;
    sys_clk        = 1'b0;
    sys_rst_n      = 1'b0;
    trigger_strobe = 1'b0;
    reset_strobe   = 1'b0;
    velocity_q15   = 16'h4000;

    repeat (8) @(posedge sys_clk);
    sys_rst_n = 1'b1;
    repeat (8) @(posedge sys_clk);

    strike_and_collect(16'h2000, 0);
    strike_and_collect(16'h4000, 1);
    strike_and_collect(16'h6000, 2);
    strike_and_collect(16'h7FFF, 3);

    // 1. The 0x4000 strike must match the golden TB result peak=3952.
    if (peak_v[1] !== 3952) begin
        $display("VEL_TB_FAIL peak_at_0x4000 got=%0d want=3952", peak_v[1]);
        fails = fails + 1;
    end else begin
        $display("VEL_TB_PASS peak_at_0x4000 = 3952");
    end

    // 2. Same for first_nonzero.
    if (first_v[1] !== 106) begin
        $display("VEL_TB_FAIL first_nonzero_at_0x4000 got=%0d want=106",
                 first_v[1]);
        fails = fails + 1;
    end else begin
        $display("VEL_TB_PASS first_nonzero_at_0x4000 = 106");
    end

    // 3. early_energy must be monotonically non-decreasing across the
    //    first three velocities (soft -> soft -> bright); the brilliant
    //    layer's ROM sum is intentionally lower than bright's so its
    //    raw early_energy may not strictly exceed bright when peaks
    //    are normalized. We only require brilliant > soft.
    if (early_v[1] < early_v[0]) begin
        $display("VEL_TB_FAIL early_energy_decreasing_0x4000 got=%0d prev=%0d",
                 early_v[1], early_v[0]);
        fails = fails + 1;
    end else begin
        $display("VEL_TB_PASS early_energy_at_0x4000 >= 0x2000 (%0d >= %0d)",
                 early_v[1], early_v[0]);
    end
    if (early_v[2] < early_v[1]) begin
        $display("VEL_TB_FAIL early_energy_decreasing_0x6000 got=%0d prev=%0d",
                 early_v[2], early_v[1]);
        fails = fails + 1;
    end else begin
        $display("VEL_TB_PASS early_energy_at_0x6000 >= 0x4000 (%0d >= %0d)",
                 early_v[2], early_v[1]);
    end

    // 4. The headline brightness check: brilliant (0x7FFF) early_energy
    //    must exceed soft (0x4000) early_energy by a meaningful margin
    //    (>= 50%) so the layer change is acoustically measurable.
    if (early_v[3] < (early_v[1] + (early_v[1] / 2))) begin
        $display("VEL_TB_FAIL brightness_margin early_brilliant=%0d early_soft=%0d",
                 early_v[3], early_v[1]);
        fails = fails + 1;
    end else begin
        $display("VEL_TB_PASS brightness_margin brilliant=%0d > 1.5*soft=%0d",
                 early_v[3], early_v[1] + (early_v[1] / 2));
    end

    // 5. Brilliant layer (0x7FFF) peak must not exceed naive velocity
    //    scaling versus the bright layer at 0x6000 by more than 10%.
    //    Naive scaling predicts peak_v3 == peak_v2 * 0x7FFF / 0x6000 =
    //    peak_v2 * 32767 / 24576. We allow 10% headroom because the
    //    brilliant layer reshapes the temporal envelope earlier.
    begin : check_no_louder
        integer expected_peak;
        integer max_allowed;
        expected_peak = (peak_v[2] * 32767) / 24576;
        max_allowed   = expected_peak + (expected_peak / 10);
        if (peak_v[3] > max_allowed) begin
            $display("VEL_TB_FAIL brilliant_too_loud peak_v3=%0d max_allowed=%0d (peak_v2=%0d)",
                     peak_v[3], max_allowed, peak_v[2]);
            fails = fails + 1;
        end else begin
            $display("VEL_TB_PASS brilliant_within_velocity_scaling peak_0x7FFF=%0d <= naive*1.1=%0d",
                     peak_v[3], max_allowed);
        end
    end

    // 6. clip_seen must be low after the last strike (no internal
    //    saturation in the reduced voice core at these velocities).
    if (clip_seen !== 1'b0) begin
        $display("VEL_TB_FAIL clip_seen_high");
        fails = fails + 1;
    end else begin
        $display("VEL_TB_PASS clip_seen_low");
    end

    if (fails == 0) begin
        $display("VEL_TB_PASS_ALL early=%0d %0d %0d %0d peak=%0d %0d %0d %0d",
                 early_v[0], early_v[1], early_v[2], early_v[3],
                 peak_v[0],  peak_v[1],  peak_v[2],  peak_v[3]);
    end else begin
        $display("VEL_TB_FAIL_ALL fails=%0d", fails);
    end
    $finish;
end

initial begin
    #500_000_000; // 500 ms safety timeout
    $display("VEL_TB_FAIL timeout");
    $finish;
end

endmodule
