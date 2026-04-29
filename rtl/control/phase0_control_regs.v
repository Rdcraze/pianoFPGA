`timescale 1ns / 1ps

module phase0_control_regs (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        reg_wr_en,
    input  wire        reg_rd_en,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire [31:0] status_word,
    input  wire [31:0] voice_status_word,
    input  wire [31:0] voice_sample_count,
    input  wire [31:0] voice_trigger_count,
    input  wire [31:0] voice_active_count,
    input  wire [31:0] voice_valid_count,
    input  wire [31:0] voice1_status_word,
    input  wire [31:0] voice1_trigger_count,
    input  wire [31:0] voice1_active_count,
    input  wire [31:0] voice1_valid_count,
    input  wire [31:0] voice2_status_word,
    input  wire [31:0] voice2_trigger_count,
    input  wire [31:0] voice2_active_count,
    input  wire [31:0] voice2_valid_count,
    input  wire [31:0] voice_mix_status_word,
    input  wire [31:0] voice_mix_clip_count,
    output reg  [31:0] reg_rdata,
    output reg         audio_enable,
    output reg         tone_enable,
    output reg  [1:0]  wave_sel,
    output reg         trigger_strobe,
    output reg         codec_cfg_valid,
    output reg  [23:0] phase_step,
    output reg  [15:0] gain,
    output reg  [15:0] decay_step,
    output reg  [15:0] codec_cfg_word,
    output reg         voice_enable,
    output reg         voice_trigger_strobe,
    output reg         voice_reset_strobe,
    output reg         voice_clip_clear_strobe,
    output reg         voice_diag_clear_strobe,
    output reg         voice_body_bypass,
    output reg         voice_disp_bypass,
    output reg         voice1_enable,
    output reg         voice1_trigger_strobe,
    output reg         voice1_reset_strobe,
    output reg         voice1_clip_clear_strobe,
    output reg         voice2_enable,
    output reg         voice2_trigger_strobe,
    output reg         voice2_reset_strobe,
    output reg         voice2_clip_clear_strobe,
    output reg  [15:0] voice_velocity,
    output reg  [6:0]  voice_loop_len,
    output reg  [15:0] voice_loop_gain,
    output reg  [15:0] voice_damp_mix,
    output reg signed [15:0] voice_disp_coeff,
    output reg  [15:0] voice_body_mix
);

localparam [7:0] REG_IDENT      = 8'h00;
localparam [7:0] REG_CONTROL    = 8'h04;
localparam [7:0] REG_PHASE_STEP = 8'h08;
localparam [7:0] REG_GAIN       = 8'h0C;
localparam [7:0] REG_DECAY_STEP = 8'h10;
localparam [7:0] REG_CODEC_CFG  = 8'h14;
localparam [7:0] REG_STATUS     = 8'h18;
localparam [7:0] REG_VOICE_CONTROL    = 8'h20;
localparam [7:0] REG_VOICE_STATUS     = 8'h24;
localparam [7:0] REG_VOICE_VELOCITY   = 8'h28;
localparam [7:0] REG_VOICE_LOOP_LEN   = 8'h2C;
localparam [7:0] REG_VOICE_LOOP_GAIN  = 8'h30;
localparam [7:0] REG_VOICE_DAMP_MIX   = 8'h34;
localparam [7:0] REG_VOICE_DISP_COEFF = 8'h38;
localparam [7:0] REG_VOICE_BODY_MIX   = 8'h3C;
localparam [7:0] REG_VOICE_SAMPLE_COUNT  = 8'h40;
localparam [7:0] REG_VOICE_TRIGGER_COUNT = 8'h44;
localparam [7:0] REG_VOICE_ACTIVE_COUNT  = 8'h48;
localparam [7:0] REG_VOICE_VALID_COUNT   = 8'h4C;
localparam [7:0] REG_VOICE_DIAG_CONTROL  = 8'h50;
localparam [7:0] REG_VOICE1_CONTROL       = 8'h54;
localparam [7:0] REG_VOICE1_STATUS        = 8'h58;
localparam [7:0] REG_VOICE1_TRIGGER_COUNT = 8'h5C;
localparam [7:0] REG_VOICE1_ACTIVE_COUNT  = 8'h60;
localparam [7:0] REG_VOICE1_VALID_COUNT   = 8'h64;
localparam [7:0] REG_VOICE_MIX_STATUS     = 8'h68;
localparam [7:0] REG_VOICE_MIX_CLIP_COUNT = 8'h6C;
localparam [7:0] REG_VOICE2_CONTROL       = 8'h70;
localparam [7:0] REG_VOICE2_STATUS        = 8'h74;
localparam [7:0] REG_VOICE2_TRIGGER_COUNT = 8'h78;
localparam [7:0] REG_VOICE2_ACTIVE_COUNT  = 8'h7C;
localparam [7:0] REG_VOICE2_VALID_COUNT   = 8'h80;

function [15:0] clamp_uq15;
    input [31:0] value;
    begin
        if (value[31:15] != 17'd0) begin
            clamp_uq15 = 16'h7fff;
        end else begin
            clamp_uq15 = {1'b0, value[14:0]};
        end
    end
endfunction

function [6:0] clamp_loop_len;
    input [31:0] value;
    begin
        if (value[31:7] != 25'd0) begin
            clamp_loop_len = 7'd127;
        end else if (value[6:0] < 7'd32) begin
            clamp_loop_len = 7'd32;
        end else begin
            clamp_loop_len = value[6:0];
        end
    end
endfunction

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_enable   <= 1'b1;
        tone_enable    <= 1'b1;
        wave_sel       <= 2'b00;
        trigger_strobe <= 1'b0;
        codec_cfg_valid <= 1'b0;
        phase_step     <= 24'd157482;
        gain           <= 16'd4096;
        decay_step     <= 16'd0;
        codec_cfg_word <= 16'd0;
        voice_enable   <= 1'b1;
        voice_trigger_strobe <= 1'b0;
        voice_reset_strobe <= 1'b0;
        voice_clip_clear_strobe <= 1'b0;
        voice_diag_clear_strobe <= 1'b0;
        voice_body_bypass <= 1'b0;
        voice_disp_bypass <= 1'b0;
        voice1_enable <= 1'b1;
        voice1_trigger_strobe <= 1'b0;
        voice1_reset_strobe <= 1'b0;
        voice1_clip_clear_strobe <= 1'b0;
        voice2_enable <= 1'b1;
        voice2_trigger_strobe <= 1'b0;
        voice2_reset_strobe <= 1'b0;
        voice2_clip_clear_strobe <= 1'b0;
        voice_velocity <= 16'h4000;
        voice_loop_len <= 7'd106;
        voice_loop_gain <= 16'd32640;
        voice_damp_mix <= 16'd16384;
        voice_disp_coeff <= 16'sd9952;
        voice_body_mix <= 16'd8192;
    end else begin
        trigger_strobe  <= 1'b0;
        codec_cfg_valid <= 1'b0;
        voice_trigger_strobe <= 1'b0;
        voice_reset_strobe <= 1'b0;
        voice_clip_clear_strobe <= 1'b0;
        voice_diag_clear_strobe <= 1'b0;
        voice1_trigger_strobe <= 1'b0;
        voice1_reset_strobe <= 1'b0;
        voice1_clip_clear_strobe <= 1'b0;
        voice2_trigger_strobe <= 1'b0;
        voice2_reset_strobe <= 1'b0;
        voice2_clip_clear_strobe <= 1'b0;

        if (reg_wr_en) begin
            case (reg_addr)
                REG_CONTROL: begin
                    audio_enable   <= reg_wdata[0];
                    tone_enable    <= reg_wdata[1];
                    wave_sel       <= reg_wdata[5:4];
                    trigger_strobe <= reg_wdata[8];
                    codec_cfg_valid<= reg_wdata[9];
                end
                REG_PHASE_STEP: begin
                    phase_step <= reg_wdata[23:0];
                end
                REG_GAIN: begin
                    gain <= reg_wdata[15:0];
                end
                REG_DECAY_STEP: begin
                    decay_step <= reg_wdata[15:0];
                end
                REG_CODEC_CFG: begin
                    codec_cfg_word <= reg_wdata[15:0];
                end
                REG_VOICE_CONTROL: begin
                    voice_enable <= reg_wdata[0];
                    voice_trigger_strobe <= reg_wdata[1];
                    voice_reset_strobe <= reg_wdata[2];
                    voice_body_bypass <= reg_wdata[3];
                    voice_disp_bypass <= reg_wdata[4];
                    voice_clip_clear_strobe <= reg_wdata[8];
                end
                REG_VOICE_VELOCITY: begin
                    voice_velocity <= clamp_uq15(reg_wdata);
                end
                REG_VOICE_LOOP_LEN: begin
                    voice_loop_len <= clamp_loop_len(reg_wdata);
                end
                REG_VOICE_LOOP_GAIN: begin
                    voice_loop_gain <= clamp_uq15(reg_wdata);
                end
                REG_VOICE_DAMP_MIX: begin
                    voice_damp_mix <= clamp_uq15(reg_wdata);
                end
                REG_VOICE_DISP_COEFF: begin
                    voice_disp_coeff <= reg_wdata[15:0];
                end
                REG_VOICE_BODY_MIX: begin
                    voice_body_mix <= clamp_uq15(reg_wdata);
                end
                REG_VOICE_DIAG_CONTROL: begin
                    voice_diag_clear_strobe <= reg_wdata[0];
                end
                REG_VOICE1_CONTROL: begin
                    voice1_enable <= reg_wdata[0];
                    voice1_trigger_strobe <= reg_wdata[1];
                    voice1_reset_strobe <= reg_wdata[2];
                    voice1_clip_clear_strobe <= reg_wdata[8];
                end
                REG_VOICE2_CONTROL: begin
                    voice2_enable <= reg_wdata[0];
                    voice2_trigger_strobe <= reg_wdata[1];
                    voice2_reset_strobe <= reg_wdata[2];
                    voice2_clip_clear_strobe <= reg_wdata[8];
                end
                default: begin
                end
            endcase
        end
    end
end

always @(*) begin
    reg_rdata = 32'd0;
    if (reg_rd_en) begin
        case (reg_addr)
            REG_IDENT: begin
                reg_rdata = 32'h5030_3031;
            end
            REG_CONTROL: begin
                reg_rdata = {
                    22'd0,
                    2'd0,
                    wave_sel,
                    2'd0,
                    tone_enable,
                    audio_enable
                };
            end
            REG_PHASE_STEP: begin
                reg_rdata = {8'd0, phase_step};
            end
            REG_GAIN: begin
                reg_rdata = {16'd0, gain};
            end
            REG_DECAY_STEP: begin
                reg_rdata = {16'd0, decay_step};
            end
            REG_CODEC_CFG: begin
                reg_rdata = {16'd0, codec_cfg_word};
            end
            REG_STATUS: begin
                reg_rdata = status_word;
            end
            REG_VOICE_CONTROL: begin
                reg_rdata = {
                    27'd0,
                    voice_disp_bypass,
                    voice_body_bypass,
                    2'd0,
                    voice_enable
                };
            end
            REG_VOICE_STATUS: begin
                reg_rdata = voice_status_word;
            end
            REG_VOICE_VELOCITY: begin
                reg_rdata = {16'd0, voice_velocity};
            end
            REG_VOICE_LOOP_LEN: begin
                reg_rdata = {25'd0, voice_loop_len};
            end
            REG_VOICE_LOOP_GAIN: begin
                reg_rdata = {16'd0, voice_loop_gain};
            end
            REG_VOICE_DAMP_MIX: begin
                reg_rdata = {16'd0, voice_damp_mix};
            end
            REG_VOICE_DISP_COEFF: begin
                reg_rdata = {16'd0, voice_disp_coeff[15:0]};
            end
            REG_VOICE_BODY_MIX: begin
                reg_rdata = {16'd0, voice_body_mix};
            end
            REG_VOICE_SAMPLE_COUNT: begin
                reg_rdata = voice_sample_count;
            end
            REG_VOICE_TRIGGER_COUNT: begin
                reg_rdata = voice_trigger_count;
            end
            REG_VOICE_ACTIVE_COUNT: begin
                reg_rdata = voice_active_count;
            end
            REG_VOICE_VALID_COUNT: begin
                reg_rdata = voice_valid_count;
            end
            REG_VOICE_DIAG_CONTROL: begin
                reg_rdata = 32'd0;
            end
            REG_VOICE1_CONTROL: begin
                reg_rdata = {
                    31'd0,
                    voice1_enable
                };
            end
            REG_VOICE1_STATUS: begin
                reg_rdata = voice1_status_word;
            end
            REG_VOICE1_TRIGGER_COUNT: begin
                reg_rdata = voice1_trigger_count;
            end
            REG_VOICE1_ACTIVE_COUNT: begin
                reg_rdata = voice1_active_count;
            end
            REG_VOICE1_VALID_COUNT: begin
                reg_rdata = voice1_valid_count;
            end
            REG_VOICE_MIX_STATUS: begin
                reg_rdata = voice_mix_status_word;
            end
            REG_VOICE_MIX_CLIP_COUNT: begin
                reg_rdata = voice_mix_clip_count;
            end
            REG_VOICE2_CONTROL: begin
                reg_rdata = {
                    31'd0,
                    voice2_enable
                };
            end
            REG_VOICE2_STATUS: begin
                reg_rdata = voice2_status_word;
            end
            REG_VOICE2_TRIGGER_COUNT: begin
                reg_rdata = voice2_trigger_count;
            end
            REG_VOICE2_ACTIVE_COUNT: begin
                reg_rdata = voice2_active_count;
            end
            REG_VOICE2_VALID_COUNT: begin
                reg_rdata = voice2_valid_count;
            end
            default: begin
                reg_rdata = 32'd0;
            end
        endcase
    end
end

endmodule
