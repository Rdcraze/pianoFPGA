`timescale 1ns / 1ps

module phase1_reduced_voice_tb;

localparam integer TICK_DIV = 40;
localparam integer TOTAL_SAMPLES = 234375;
localparam integer FIVE_MS_SAMPLES = 234;
localparam integer RMS_WINDOW = 938;
localparam integer RMS_100MS_START = 4688;
localparam integer RMS_500MS_START = 23438;
localparam integer RMS_3S_START = 140625;
localparam integer CAPTURE_START = 9375;
localparam integer CAPTURE_COUNT = 4096;
localparam integer GOLDEN_COUNT = 4096;
localparam real FS_HZ = 46875.0;

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
integer first_nonzero_sample;
integer pre_trigger_valid_count;
integer fail_seen;
integer cap_count;
integer rms_100_count;
integer rms_500_count;
integer rms_3s_count;
integer sample_int;
integer golden_fd;
integer golden_mismatch_count;
reg trigger_seen;
reg write_golden;

real capture [0:CAPTURE_COUNT - 1];
reg [15:0] golden_samples [0:GOLDEN_COUNT - 1];
real rms_100_sum;
real rms_500_sum;
real rms_3s_sum;

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
    end else if (tick_count == TICK_DIV - 1) begin
        tick_count  <= 0;
        sample_tick <= 1'b1;
    end else begin
        tick_count  <= tick_count + 1;
        sample_tick <= 1'b0;
    end
end

task finish_checks;
    integer i;
    integer lag;
    integer best_lag;
    integer pair_count;
    real mean_value;
    real corr;
    real best_corr;
    real rms_100;
    real rms_500;
    real rms_3s;
    real measured_freq;
    begin
        mean_value = 0.0;
        for (i = 0; i < CAPTURE_COUNT; i = i + 1) begin
            mean_value = mean_value + capture[i];
        end
        mean_value = mean_value / CAPTURE_COUNT;

        best_lag = 0;
        best_corr = -1.0e30;
        for (lag = 100; lag <= 113; lag = lag + 1) begin
            corr = 0.0;
            pair_count = CAPTURE_COUNT - lag;
            for (i = 0; i < pair_count; i = i + 1) begin
                corr = corr + ((capture[i] - mean_value) * (capture[i + lag] - mean_value));
            end
            if (corr > best_corr) begin
                best_corr = corr;
                best_lag = lag;
            end
        end

        measured_freq = FS_HZ / best_lag;
        rms_100 = $sqrt(rms_100_sum / rms_100_count);
        rms_500 = $sqrt(rms_500_sum / rms_500_count);
        rms_3s = $sqrt(rms_3s_sum / rms_3s_count);

        if (write_golden) begin
            $fclose(golden_fd);
            $display("VOICE_TB_GOLDEN_WRITE samples=%0d file=rtl/audio/phase1_reduced_voice_golden_samples.hex",
                     GOLDEN_COUNT);
        end

        if (first_nonzero_sample < 0) begin
            $display("VOICE_TB_FAIL no_nonzero_output sample_count=%0d", sample_count);
            fail_seen = 1;
        end else if (golden_mismatch_count != 0) begin
            $display("VOICE_TB_FAIL golden_mismatch_count=%0d", golden_mismatch_count);
            fail_seen = 1;
        end else if (first_nonzero_sample > FIVE_MS_SAMPLES) begin
            $display("VOICE_TB_FAIL slow_attack first_nonzero_sample=%0d", first_nonzero_sample);
            fail_seen = 1;
        end else if (clip_seen) begin
            $display("VOICE_TB_FAIL clip_seen peak=%0d", peak_level);
            fail_seen = 1;
        end else if ((measured_freq < 425.0) || (measured_freq > 455.0)) begin
            $display("VOICE_TB_FAIL bad_frequency freq=%f best_lag=%0d", measured_freq, best_lag);
            fail_seen = 1;
        end else if (rms_500 >= rms_100) begin
            $display("VOICE_TB_FAIL nondecaying_rms rms_100=%f rms_500=%f", rms_100, rms_500);
            fail_seen = 1;
        end else if (rms_3s > (rms_100 * 0.1)) begin
            $display("VOICE_TB_FAIL insufficient_3s_decay rms_100=%f rms_3s=%f", rms_100, rms_3s);
            fail_seen = 1;
        end else if (sample_count < TOTAL_SAMPLES) begin
            $display("VOICE_TB_FAIL short_run sample_count=%0d", sample_count);
            fail_seen = 1;
        end

        if (!fail_seen) begin
            $display("VOICE_TB_PASS first_nonzero_sample=%0d freq=%f rms_100ms=%f rms_500ms=%f rms_3s=%f peak=%0d golden_samples=%0d",
                     first_nonzero_sample, measured_freq, rms_100, rms_500, rms_3s, peak_level, GOLDEN_COUNT);
        end
        $finish;
    end
endtask

always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
        sample_count <= 0;
        first_nonzero_sample <= -1;
        pre_trigger_valid_count <= 0;
        trigger_seen <= 1'b0;
        cap_count <= 0;
        rms_100_count <= 0;
        rms_500_count <= 0;
        rms_3s_count <= 0;
        rms_100_sum <= 0.0;
        rms_500_sum <= 0.0;
        rms_3s_sum <= 0.0;
        golden_mismatch_count <= 0;
    end else begin
        if (trigger_strobe) begin
            trigger_seen <= 1'b1;
        end

        if (sample_valid) begin
        sample_int = sample_data;

        if (!trigger_seen) begin
            pre_trigger_valid_count <= pre_trigger_valid_count + 1;
            if (sample_data !== 16'sd0) begin
                $display("VOICE_TB_FAIL reset_not_silent sample=%0d", sample_int);
                fail_seen = 1;
                $finish;
            end
        end

        if (trigger_seen) begin
            sample_count <= sample_count + 1;

            if ((first_nonzero_sample < 0) && (sample_data != 16'sd0)) begin
                first_nonzero_sample <= sample_count;
            end

            if (clip_seen) begin
                fail_seen = 1;
            end

            if ((sample_count >= CAPTURE_START) && (cap_count < CAPTURE_COUNT)) begin
                capture[cap_count] = sample_int;
                cap_count <= cap_count + 1;
            end

            if (sample_count < GOLDEN_COUNT) begin
                if (write_golden) begin
                    $fdisplay(golden_fd, "%04h", sample_data[15:0]);
                end else if (sample_data[15:0] !== golden_samples[sample_count]) begin
                    $display("VOICE_TB_FAIL golden_mismatch sample=%0d expected=%04h actual=%04h",
                             sample_count, golden_samples[sample_count], sample_data[15:0]);
                    golden_mismatch_count <= golden_mismatch_count + 1;
                    fail_seen = 1;
                    $finish;
                end
            end

            if ((sample_count >= RMS_100MS_START) && (sample_count < RMS_100MS_START + RMS_WINDOW)) begin
                rms_100_sum <= rms_100_sum + (sample_int * sample_int);
                rms_100_count <= rms_100_count + 1;
            end

            if ((sample_count >= RMS_500MS_START) && (sample_count < RMS_500MS_START + RMS_WINDOW)) begin
                rms_500_sum <= rms_500_sum + (sample_int * sample_int);
                rms_500_count <= rms_500_count + 1;
            end

            if ((sample_count >= RMS_3S_START) && (sample_count < RMS_3S_START + RMS_WINDOW)) begin
                rms_3s_sum <= rms_3s_sum + (sample_int * sample_int);
                rms_3s_count <= rms_3s_count + 1;
            end

            if (sample_count == TOTAL_SAMPLES) begin
                finish_checks;
            end
        end
        end
    end
end

initial begin
    write_golden = 1'b0;
    golden_fd = 0;
    golden_mismatch_count = 0;
    if ($test$plusargs("WRITE_GOLDEN")) begin
        write_golden = 1'b1;
        golden_fd = $fopen("rtl/audio/phase1_reduced_voice_golden_samples.hex", "w");
        if (golden_fd == 0) begin
            $display("VOICE_TB_FAIL golden_file_open");
            $finish;
        end
    end else begin
        $readmemh("rtl/audio/phase1_reduced_voice_golden_samples.hex", golden_samples);
    end

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
    body_mix_q15 = 16'd8192;
    fail_seen = 0;

    #5000;
    sys_rst_n = 1'b1;
    #20000;

    trigger_strobe = 1'b1;
    #20;
    trigger_strobe = 1'b0;
end

endmodule
