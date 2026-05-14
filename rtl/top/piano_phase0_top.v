`timescale 1ns / 1ps

module piano_phase0_top (
    input  wire       sys_clk_50m,
    input  wire       sys_rst_n,
    input  wire       audio_bclk,
    input  wire       audio_lrc,
    input  wire       audio_adcdat,
    input  wire       uart1_rx,
    output wire       audio_mclk,
    output wire       audio_dacdat,
    output wire       i2c_scl,
    inout  wire       i2c_sda,
    output wire       uart1_tx
);

wire        core_rst_n;
wire        reg_wr_en;
wire        reg_rd_en;
wire [7:0]  reg_addr;
wire [31:0] reg_wdata;
wire [31:0] reg_rdata;
wire        audio_enable;
wire        tone_enable;
wire [1:0]  wave_sel;
wire        trigger_strobe;
wire        codec_cfg_valid;
wire [23:0] phase_step;
wire [15:0] gain;
wire [15:0] decay_step;
wire [15:0] codec_cfg_word;
wire        voice_enable;
wire        voice_trigger_strobe;
wire        voice_reset_strobe;
wire        voice_clip_clear_strobe;
wire        voice_diag_clear_strobe;
wire        voice_body_bypass;
wire        voice_disp_bypass;
wire        voice1_enable;
wire        voice1_trigger_strobe;
wire        voice1_reset_strobe;
wire        voice1_clip_clear_strobe;
wire        voice2_enable;
wire        voice2_trigger_strobe;
wire        voice2_reset_strobe;
wire        voice2_clip_clear_strobe;
wire        voice3_enable;
assign voice3_enable = 1'b0;
assign voice3_trigger_strobe = 1'b0;
assign voice3_reset_strobe = 1'b0;
assign voice3_clip_clear_strobe = 1'b0;
wire        voice3_trigger_strobe;
wire        voice3_reset_strobe;
wire        voice3_clip_clear_strobe;
wire [15:0] voice_velocity;
wire [6:0]  voice_loop_len;
wire [15:0] voice_loop_gain;
wire [15:0] voice_damp_mix;
wire signed [15:0] voice_disp_coeff;
wire [15:0] voice_body_mix;
wire        codec_cfg_busy;
wire        sample_tick;
wire        tx_valid;
wire [15:0] tx_sample;
wire [15:0] soc_status;
wire [15:0] uart_status;
wire [15:0] audio_status;
wire [7:0]  codec_status;
wire [31:0] fabric_status;
wire [31:0] voice_status_word;
wire [31:0] voice_sample_count;
wire [31:0] voice_trigger_count;
wire [31:0] voice_active_count;
wire [31:0] voice_valid_count;
wire [31:0] voice1_status_word;
wire [31:0] voice1_trigger_count;
wire [31:0] voice1_active_count;
wire [31:0] voice1_valid_count;
wire [31:0] voice2_status_word;
wire [31:0] voice2_trigger_count;
wire [31:0] voice2_active_count;
wire [31:0] voice2_valid_count;
wire [31:0] voice3_status_word;
wire [31:0] voice3_trigger_count;
wire [31:0] voice3_active_count;
wire [31:0] voice3_valid_count;
wire [31:0] voice_mix_status_word;
wire [31:0] voice_mix_clip_count;

phase0_reset_sync phase0_reset_sync_inst (
    .clk   (sys_clk_50m),
    .arst_n(sys_rst_n),
    .srst_n(core_rst_n)
);

phase0_rv32i_soc phase0_soc_inst (
    .sys_clk   (sys_clk_50m),
    .sys_rst_n (core_rst_n),
    .uart_rx   (uart1_rx),
    .reg_rdata (reg_rdata),
    .uart_tx   (uart1_tx),
    .reg_wr_en (reg_wr_en),
    .reg_rd_en (reg_rd_en),
    .reg_addr  (reg_addr),
    .reg_wdata (reg_wdata),
    .status_word(soc_status),
    .uart_status_word(uart_status)
);

assign fabric_status = {
    codec_status[7:0],
    audio_status[7:0],
    uart_status[7:0],
    soc_status[7:0]
};

phase0_control_regs phase0_control_regs_inst (
    .sys_clk       (sys_clk_50m),
    .sys_rst_n     (core_rst_n),
    .reg_wr_en     (reg_wr_en),
    .reg_rd_en     (reg_rd_en),
    .reg_addr      (reg_addr),
    .reg_wdata     (reg_wdata),
    .status_word   (fabric_status),
    .voice_status_word(voice_status_word),
    .voice_sample_count(voice_sample_count),
    .voice_trigger_count(voice_trigger_count),
    .voice_active_count(voice_active_count),
    .voice_valid_count(voice_valid_count),
    .voice1_status_word(voice1_status_word),
    .voice1_trigger_count(voice1_trigger_count),
    .voice1_active_count(voice1_active_count),
    .voice1_valid_count(voice1_valid_count),
    .voice2_status_word(voice2_status_word),
    .voice3_status_word(voice3_status_word),
    .voice3_trigger_count(voice3_trigger_count),
    .voice3_active_count(voice3_active_count),
    .voice3_valid_count(voice3_valid_count),
    .voice2_trigger_count(voice2_trigger_count),
    .voice2_active_count(voice2_active_count),
    .voice2_valid_count(voice2_valid_count),
    .voice_mix_status_word(voice_mix_status_word),
    .voice_mix_clip_count(voice_mix_clip_count),
    .reg_rdata     (reg_rdata),
    .audio_enable  (audio_enable),
    .tone_enable   (tone_enable),
    .wave_sel      (wave_sel),
    .trigger_strobe(trigger_strobe),
    .codec_cfg_valid(codec_cfg_valid),
    .phase_step    (phase_step),
    .gain          (gain),
    .decay_step    (decay_step),
    .codec_cfg_word(codec_cfg_word),
    .voice_enable  (voice_enable),
    .voice_trigger_strobe(voice_trigger_strobe),
    .voice_reset_strobe(voice_reset_strobe),
    .voice_clip_clear_strobe(voice_clip_clear_strobe),
    .voice_diag_clear_strobe(voice_diag_clear_strobe),
    .voice_body_bypass(voice_body_bypass),
    .voice_disp_bypass(voice_disp_bypass),
    .voice1_enable (voice1_enable),
    .voice1_trigger_strobe(voice1_trigger_strobe),
    .voice1_reset_strobe(voice1_reset_strobe),
    .voice1_clip_clear_strobe(voice1_clip_clear_strobe),
    .voice2_enable (voice2_enable),
    .voice2_trigger_strobe(voice2_trigger_strobe),
    .voice2_reset_strobe(voice2_reset_strobe),
    .voice2_clip_clear_strobe(voice2_clip_clear_strobe),

    .voice_velocity(voice_velocity),
    .voice_loop_len(voice_loop_len),
    .voice_loop_gain(voice_loop_gain),
    .voice_damp_mix(voice_damp_mix),
    .voice_disp_coeff(voice_disp_coeff),
    .voice_body_mix(voice_body_mix)
);

phase0_audio_path phase0_audio_path_inst (
    .sys_clk       (sys_clk_50m),
    .sys_rst_n     (core_rst_n),
    .sample_tick   (sample_tick),
    .audio_enable  (audio_enable),
    .tone_enable   (tone_enable),
    .wave_sel      (wave_sel),
    .trigger_strobe(trigger_strobe),
    .phase_step    (phase_step),
    .gain          (gain),
    .decay_step    (decay_step),
    .voice_enable  (voice_enable),
    .voice_trigger_strobe(voice_trigger_strobe),
    .voice_reset_strobe(voice_reset_strobe),
    .voice_clip_clear_strobe(voice_clip_clear_strobe),
    .voice_diag_clear_strobe(voice_diag_clear_strobe),
    .voice_body_bypass(voice_body_bypass),
    .voice_disp_bypass(voice_disp_bypass),
    .voice1_enable (voice1_enable),
    .voice1_trigger_strobe(voice1_trigger_strobe),
    .voice1_reset_strobe(voice1_reset_strobe),
    .voice1_clip_clear_strobe(voice1_clip_clear_strobe),
    .voice2_enable (voice2_enable),
    .voice2_trigger_strobe(voice2_trigger_strobe),
    .voice2_reset_strobe(voice2_reset_strobe),
    .voice2_clip_clear_strobe(voice2_clip_clear_strobe),

    .voice_velocity(voice_velocity),
    .voice_loop_len(voice_loop_len),
    .voice_loop_gain(voice_loop_gain),
    .voice_damp_mix(voice_damp_mix),
    .voice_disp_coeff(voice_disp_coeff),
    .voice_body_mix(voice_body_mix),
    .tx_valid      (tx_valid),
    .tx_sample     (tx_sample),
    .status_word   (audio_status),
    .voice_status_word(voice_status_word),
    .voice_sample_count(voice_sample_count),
    .voice_trigger_count(voice_trigger_count),
    .voice_active_count(voice_active_count),
    .voice_valid_count(voice_valid_count),
    .voice1_status_word(voice1_status_word),
    .voice1_trigger_count(voice1_trigger_count),
    .voice1_active_count(voice1_active_count),
    .voice1_valid_count(voice1_valid_count),
    .voice2_status_word(voice2_status_word),
    .voice3_status_word(voice3_status_word),
    .voice3_trigger_count(voice3_trigger_count),
    .voice3_active_count(voice3_active_count),
    .voice3_valid_count(voice3_valid_count),
    .voice2_trigger_count(voice2_trigger_count),
    .voice2_active_count(voice2_active_count),
    .voice2_valid_count(voice2_valid_count),
    .voice_mix_status_word(voice_mix_status_word),
    .voice_mix_clip_count(voice_mix_clip_count)
);

wm8978_codec_stub wm8978_codec_stub_inst (
    .sys_clk       (sys_clk_50m),
    .sys_rst_n     (core_rst_n),
    .audio_bclk    (audio_bclk),
    .audio_lrc     (audio_lrc),
    .audio_adcdat  (audio_adcdat),
    .codec_cfg_valid(codec_cfg_valid),
    .codec_cfg_word(codec_cfg_word),
    .tx_valid      (tx_valid),
    .tx_sample     (tx_sample),
    .sample_tick   (sample_tick),
    .cfg_busy      (codec_cfg_busy),
    .audio_mclk    (audio_mclk),
    .audio_dacdat  (audio_dacdat),
    .i2c_scl       (i2c_scl),
    .i2c_sda       (i2c_sda),
    .status_word   (codec_status)
);

endmodule
