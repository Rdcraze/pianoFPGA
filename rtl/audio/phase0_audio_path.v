`timescale 1ns / 1ps

module phase0_audio_path (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        sample_tick,
    input  wire        audio_enable,
    input  wire        tone_enable,
    input  wire [1:0]  wave_sel,
    input  wire        trigger_strobe,
    input  wire [23:0] phase_step,
    input  wire [15:0] gain,
    input  wire [15:0] decay_step,
    input  wire        voice_enable,
    input  wire        voice_trigger_strobe,
    input  wire        voice_reset_strobe,
    input  wire        voice_clip_clear_strobe,
    input  wire        voice_body_bypass,
    input  wire        voice_disp_bypass,
    input  wire        voice_diag_clear_strobe,
    input  wire        voice1_enable,
    input  wire        voice1_trigger_strobe,
    input  wire        voice1_reset_strobe,
    input  wire        voice1_clip_clear_strobe,
    input  wire        voice2_enable,
    input  wire        voice2_trigger_strobe,
    input  wire        voice2_reset_strobe,
    input  wire        voice2_clip_clear_strobe,
    input  wire        voice3_enable,
    input  wire        voice3_trigger_strobe,
    input  wire        voice3_reset_strobe,
    input  wire        voice3_clip_clear_strobe,
    input  wire [15:0] voice_velocity,
    input  wire [6:0]  voice_loop_len,
    input  wire [15:0] voice_loop_gain,
    input  wire [15:0] voice_damp_mix,
    input  wire signed [15:0] voice_disp_coeff,
    input  wire [15:0] voice_body_mix,
    output wire        tx_valid,
    output wire [15:0] tx_sample,
    output wire [15:0] status_word,
    output wire [31:0] voice_status_word,
    output wire [31:0] voice_sample_count,
    output wire [31:0] voice_trigger_count,
    output wire [31:0] voice_active_count,
    output wire [31:0] voice_valid_count,
    output wire [31:0] voice1_status_word,
    output wire [31:0] voice1_trigger_count,
    output wire [31:0] voice1_active_count,
    output wire [31:0] voice1_valid_count,
    output wire [31:0] voice2_status_word,
    output wire [31:0] voice2_trigger_count,
    output wire [31:0] voice2_active_count,
    output wire [31:0] voice2_valid_count,
    output wire [31:0] voice3_status_word,
    output wire [31:0] voice3_trigger_count,
    output wire [31:0] voice3_active_count,
    output wire [31:0] voice3_valid_count,
    output wire [31:0] voice_mix_status_word,
    output wire [31:0] voice_mix_clip_count
);

wire               voice0_sample_valid;
wire               voice0_active;
wire               voice0_excite_busy;
wire               voice0_clip_seen;
wire [15:0]        voice0_peak_level;
wire signed [15:0] voice0_sample_data;
wire               voice0_runtime_enable;
wire               voice0_trigger_any;

wire               voice1_sample_valid;
wire               voice1_active;
wire               voice1_excite_busy;
wire               voice1_clip_seen;
wire [15:0]        voice1_peak_level;
wire signed [15:0] voice1_sample_data;
wire               voice1_runtime_enable;

wire               voice2_sample_valid;
wire               voice2_active;
wire               voice2_excite_busy;
wire               voice2_clip_seen;
wire [15:0]        voice2_peak_level;
wire signed [15:0] voice2_sample_data;
wire               voice2_runtime_enable;
	wire               voice3_sample_valid;
	wire               voice3_active;
	wire               voice3_excite_busy;
	wire               voice3_clip_seen;
	wire [15:0]        voice3_peak_level;
	wire signed [15:0] voice3_sample_data;
	wire               voice3_runtime_enable;

wire               sample_valid_any;
wire               active_any;
wire               excite_busy_any;
wire signed [17:0] voice0_mix_ext;
wire signed [17:0] voice1_mix_ext;
wire signed [17:0] voice2_mix_ext;
	wire signed [17:0] voice3_mix_ext;
wire signed [18:0] mix_sum;
wire signed [15:0] mix_sample_sat;
wire [15:0]        mix_peak_now;
wire               mix_clip_now;
wire               mix_clip_clear_any;

reg [31:0]         voice_sample_count_reg;
reg [31:0]         voice_trigger_count_reg;
reg [31:0]         voice_active_count_reg;
reg [31:0]         voice_valid_count_reg;
reg [31:0]         voice1_trigger_count_reg;
reg [31:0]         voice1_active_count_reg;
reg [31:0]         voice1_valid_count_reg;
reg [31:0]         voice2_trigger_count_reg;
reg [31:0]         voice2_active_count_reg;
reg [31:0]         voice2_valid_count_reg;
reg [31:0]         voice3_trigger_count_reg;
reg [31:0]         voice3_active_count_reg;
reg [31:0]         voice3_valid_count_reg;
reg [31:0]         voice_mix_clip_count_reg;
reg                voice_mix_clip_seen_reg;
reg [15:0]         voice_mix_peak_level_reg;

assign voice0_runtime_enable = audio_enable && tone_enable && voice_enable;
assign voice1_runtime_enable = audio_enable && tone_enable && voice1_enable;
assign voice2_runtime_enable = audio_enable && tone_enable && voice2_enable;
assign voice3_runtime_enable = audio_enable && tone_enable && voice3_enable;
assign voice0_trigger_any    = trigger_strobe || voice_trigger_strobe;

phase1_reduced_voice phase1_reduced_voice_inst (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .sample_tick      (sample_tick),
    .enable           (voice0_runtime_enable),
    .trigger_strobe   (voice0_trigger_any),
    .reset_strobe     (voice_reset_strobe),
    .clip_clear_strobe(voice_clip_clear_strobe),
    .body_bypass      (voice_body_bypass),
    .disp_bypass      (voice_disp_bypass),
    .velocity_q15     (voice_velocity),
    .loop_len         (voice_loop_len),
    .loop_gain_q15    (voice_loop_gain),
    .damp_mix_q15     (voice_damp_mix),
    .disp_coeff_q15   (voice_disp_coeff),
    .body_mix_q15     (voice_body_mix),
    .sample_data      (voice0_sample_data),
    .sample_valid     (voice0_sample_valid),
    .active           (voice0_active),
    .excite_busy      (voice0_excite_busy),
    .clip_seen        (voice0_clip_seen),
    .peak_level       (voice0_peak_level)
);

phase1_reduced_voice phase1_reduced_voice1_inst (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .sample_tick      (sample_tick),
    .enable           (voice1_runtime_enable),
    .trigger_strobe   (voice1_trigger_strobe),
    .reset_strobe     (voice1_reset_strobe),
    .clip_clear_strobe(voice1_clip_clear_strobe),
    .body_bypass      (voice_body_bypass),
    .disp_bypass      (voice_disp_bypass),
    .velocity_q15     (voice_velocity),
    .loop_len         (voice_loop_len),
    .loop_gain_q15    (voice_loop_gain),
    .damp_mix_q15     (voice_damp_mix),
    .disp_coeff_q15   (voice_disp_coeff),
    .body_mix_q15     (voice_body_mix),
    .sample_data      (voice1_sample_data),
    .sample_valid     (voice1_sample_valid),
    .active           (voice1_active),
    .excite_busy      (voice1_excite_busy),
    .clip_seen        (voice1_clip_seen),
    .peak_level       (voice1_peak_level)
);

phase1_reduced_voice phase1_reduced_voice2_inst (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .sample_tick      (sample_tick),
    .enable           (voice2_runtime_enable),
    .trigger_strobe   (voice2_trigger_strobe),
    .reset_strobe     (voice2_reset_strobe),
    .clip_clear_strobe(voice2_clip_clear_strobe),
    .body_bypass      (voice_body_bypass),
    .disp_bypass      (voice_disp_bypass),
    .velocity_q15     (voice_velocity),
    .loop_len         (voice_loop_len),
    .loop_gain_q15    (voice_loop_gain),
    .damp_mix_q15     (voice_damp_mix),
    .disp_coeff_q15   (voice_disp_coeff),
    .body_mix_q15     (voice_body_mix),
    .sample_data      (voice2_sample_data),
    .sample_valid     (voice2_sample_valid),
    .active           (voice2_active),
    .excite_busy      (voice2_excite_busy),
    .clip_seen        (voice2_clip_seen),
    .peak_level       (voice2_peak_level)
);
phase1_reduced_voice phase1_reduced_voice3_inst (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .sample_tick      (sample_tick),
    .enable           (voice3_runtime_enable),
    .trigger_strobe   (voice3_trigger_strobe),
    .reset_strobe     (voice3_reset_strobe),
    .clip_clear_strobe(voice3_clip_clear_strobe),
    .body_bypass      (voice_body_bypass),
    .disp_bypass      (voice_disp_bypass),
    .velocity_q15     (voice_velocity),
    .loop_len         (voice_loop_len),
    .loop_gain_q15    (voice_loop_gain),
    .damp_mix_q15     (voice_damp_mix),
    .disp_coeff_q15   (voice_disp_coeff),
    .body_mix_q15     (voice_body_mix),
    .sample_data      (voice3_sample_data),
    .sample_valid     (voice3_sample_valid),
    .active           (voice3_active),
    .excite_busy      (voice3_excite_busy),
    .clip_seen        (voice3_clip_seen),
    .peak_level       (voice3_peak_level)
);

assign sample_valid_any = voice0_sample_valid || voice1_sample_valid || voice2_sample_valid || voice3_sample_valid;
assign active_any       = voice0_active || voice1_active || voice2_active || voice3_active;
assign excite_busy_any  = voice0_excite_busy || voice1_excite_busy || voice2_excite_busy || voice3_excite_busy;
assign voice0_mix_ext   = {{2{voice0_sample_data[15]}}, voice0_sample_data};
assign voice1_mix_ext   = {{2{voice1_sample_data[15]}}, voice1_sample_data};
assign voice2_mix_ext   = {{2{voice2_sample_data[15]}}, voice2_sample_data};
assign voice3_mix_ext   = {{2{voice3_sample_data[15]}}, voice3_sample_data};
assign mix_sum          = {{1{voice0_mix_ext[17]}}, voice0_mix_ext} + {{1{voice1_mix_ext[17]}}, voice1_mix_ext} + {{1{voice2_mix_ext[17]}}, voice2_mix_ext} + {{1{voice3_mix_ext[17]}}, voice3_mix_ext};
assign mix_clip_now     = (mix_sum > 19'sd32767) || (mix_sum < -19'sd32768);
assign mix_sample_sat   = (mix_sum > 19'sd32767)  ? 16'sh7fff :
                          (mix_sum < -19'sd32768) ? 16'sh8000 :
                          mix_sum[15:0];
assign mix_peak_now     = (mix_sample_sat == 16'sh8000) ? 16'h8000 :
                          mix_sample_sat[15] ? (16'd0 - mix_sample_sat[15:0]) :
                          mix_sample_sat[15:0];
assign mix_clip_clear_any = voice_clip_clear_strobe || voice1_clip_clear_strobe ||
                            voice2_clip_clear_strobe || voice3_clip_clear_strobe;

wire signed [15:0] body_filter_out;
wire signed [15:0] sample_gen_data;
wire               sample_gen_valid;
wire               sample_gen_active;
wire               use_sample_gen;

phase0_body_filter phase0_body_filter_inst (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .sample_tick(sample_tick),
    .sample_in  (mix_sample_sat),
    .sample_out (body_filter_out)
);

phase0_sample_gen phase0_sample_gen_inst (
    .sys_clk        (sys_clk),
    .sys_rst_n      (sys_rst_n),
    .sample_tick    (sample_tick),
    .enable         (audio_enable),
    .tone_enable    (tone_enable),
    .trigger_strobe (trigger_strobe),
    .wave_sel       (wave_sel),
    .phase_step     (phase_step),
    .gain           (gain),
    .decay_step     (decay_step),
    .sample_data    (sample_gen_data),
    .sample_valid   (sample_gen_valid),
    .active         (sample_gen_active)
);

assign use_sample_gen = audio_enable && tone_enable &&
                        !voice_enable && !voice1_enable && !voice2_enable && !voice3_enable;

assign tx_valid  = use_sample_gen ? sample_gen_valid : sample_valid_any;
assign tx_sample = use_sample_gen ? sample_gen_data  : body_filter_out;
assign status_word = {
    3'd0,
    voice_enable,
    voice0_clip_seen || voice1_clip_seen || voice2_clip_seen || voice3_clip_seen || voice_mix_clip_seen_reg,
    excite_busy_any,
    wave_sel,
    3'd0,
    audio_enable,
    tone_enable,
    sample_tick,
    sample_valid_any,
    active_any
};
assign voice_status_word = {
    voice0_peak_level,
    11'd0,
    voice_enable,
    voice0_sample_valid,
    voice0_clip_seen,
    voice0_excite_busy,
    voice0_active
};
assign voice1_status_word = {
    voice1_peak_level,
    11'd0,
    voice1_enable,
    voice1_sample_valid,
    voice1_clip_seen,
    voice1_excite_busy,
    voice1_active
};
assign voice2_status_word = {
    voice2_peak_level,
    11'd0,
    voice2_enable,
    voice2_sample_valid,
    voice2_clip_seen,
    voice2_excite_busy,
    voice2_active
};
assign voice_mix_status_word = {
    voice_mix_peak_level_reg,
    11'd0,
    voice1_enable,
    sample_valid_any,
    voice_mix_clip_seen_reg,
    excite_busy_any,
    active_any
};
assign voice_sample_count    = voice_sample_count_reg;
assign voice_trigger_count   = voice_trigger_count_reg;
assign voice_active_count    = voice_active_count_reg;
assign voice_valid_count     = voice_valid_count_reg;
assign voice1_trigger_count  = voice1_trigger_count_reg;
assign voice1_active_count   = voice1_active_count_reg;
assign voice1_valid_count    = voice1_valid_count_reg;
assign voice2_trigger_count  = voice2_trigger_count_reg;
assign voice2_active_count   = voice2_active_count_reg;
assign voice2_valid_count    = voice2_valid_count_reg;
assign voice3_status_word = {
voice3_peak_level,
11'd0,
voice3_enable,
voice3_sample_valid,
voice3_clip_seen,
voice3_excite_busy,
voice3_active
};
assign voice3_trigger_count  = voice3_trigger_count_reg;
assign voice3_active_count   = voice3_active_count_reg;
assign voice3_valid_count    = voice3_valid_count_reg;
assign voice_mix_clip_count  = voice_mix_clip_count_reg;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        voice_sample_count_reg    <= 32'd0;
        voice_trigger_count_reg   <= 32'd0;
        voice_active_count_reg    <= 32'd0;
        voice_valid_count_reg     <= 32'd0;
        voice1_trigger_count_reg  <= 32'd0;
        voice1_active_count_reg   <= 32'd0;
        voice1_valid_count_reg    <= 32'd0;
        voice3_trigger_count_reg  <= 32'd0;
        voice3_active_count_reg   <= 32'd0;
        voice3_valid_count_reg    <= 32'd0;
        voice2_trigger_count_reg  <= 32'd0;
        voice2_active_count_reg   <= 32'd0;
        voice2_valid_count_reg    <= 32'd0;
        voice_mix_clip_count_reg  <= 32'd0;
        voice_mix_clip_seen_reg   <= 1'b0;
        voice_mix_peak_level_reg  <= 16'd0;
    end else if (voice_diag_clear_strobe) begin
        voice_sample_count_reg    <= 32'd0;
        voice_trigger_count_reg   <= 32'd0;
        voice_active_count_reg    <= 32'd0;
        voice_valid_count_reg     <= 32'd0;
        voice1_trigger_count_reg  <= 32'd0;
        voice1_active_count_reg   <= 32'd0;
        voice1_valid_count_reg    <= 32'd0;
        voice3_trigger_count_reg  <= 32'd0;
        voice3_active_count_reg   <= 32'd0;
        voice3_valid_count_reg    <= 32'd0;
        voice2_trigger_count_reg  <= 32'd0;
        voice2_active_count_reg   <= 32'd0;
        voice2_valid_count_reg    <= 32'd0;
        voice_mix_clip_count_reg  <= 32'd0;
        voice_mix_clip_seen_reg   <= 1'b0;
        voice_mix_peak_level_reg  <= 16'd0;
    end else begin
        if (mix_clip_clear_any) begin
            voice_mix_clip_seen_reg  <= 1'b0;
            voice_mix_peak_level_reg <= 16'd0;
        end

        if (sample_tick) begin
            voice_sample_count_reg <= voice_sample_count_reg + 1'b1;
        end

        if (voice0_trigger_any && voice0_runtime_enable) begin
            voice_trigger_count_reg <= voice_trigger_count_reg + 1'b1;
        end

        if (voice1_trigger_strobe && voice1_runtime_enable) begin
            voice1_trigger_count_reg <= voice1_trigger_count_reg + 1'b1;
        end

        if (voice2_trigger_strobe && voice2_runtime_enable) begin
n        if (voice3_trigger_strobe && voice3_runtime_enable) begin
            voice3_trigger_count_reg <= voice3_trigger_count_reg + 1'b1;
        end
            voice2_trigger_count_reg <= voice2_trigger_count_reg + 1'b1;
        end

        if (voice0_sample_valid) begin
            voice_valid_count_reg <= voice_valid_count_reg + 1'b1;
            if (voice0_active) begin
                voice_active_count_reg <= voice_active_count_reg + 1'b1;
            end
        end

        if (voice1_sample_valid) begin
            voice1_valid_count_reg <= voice1_valid_count_reg + 1'b1;
            if (voice1_active) begin
                voice1_active_count_reg <= voice1_active_count_reg + 1'b1;
            end
        end

        if (voice2_sample_valid) begin
            voice2_valid_count_reg <= voice2_valid_count_reg + 1'b1;
            if (voice2_active) begin
n        if (voice3_sample_valid) begin
            voice3_valid_count_reg <= voice3_valid_count_reg + 1'b1;
            if (voice3_active) begin
                voice3_active_count_reg <= voice3_active_count_reg + 1'b1;
            end
        end
                voice2_active_count_reg <= voice2_active_count_reg + 1'b1;
            end
        end

        if (sample_valid_any) begin
            if (mix_peak_now > voice_mix_peak_level_reg) begin
                voice_mix_peak_level_reg <= mix_peak_now;
            end
            if (mix_clip_now) begin
                voice_mix_clip_seen_reg  <= 1'b1;
                voice_mix_clip_count_reg <= voice_mix_clip_count_reg + 1'b1;
            end
        end
    end
end

endmodule
