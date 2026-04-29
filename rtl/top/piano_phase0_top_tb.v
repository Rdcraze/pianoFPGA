`timescale 1ns / 1ps

module piano_phase0_tb_env #(
    parameter integer NACK_ENABLE = 0,
    parameter [7:0]  NACK_CFG_HIGH_BYTE = 8'hFF
);

localparam integer EXPECTED_INIT_WRITE_COUNT = 16;
localparam integer EXPECTED_TOTAL_WRITE_COUNT = 18;
localparam integer UART_BIT_PERIOD_NS = 8680;
localparam integer UART_HALF_BIT_NS = UART_BIT_PERIOD_NS / 2;
localparam integer EXPECTED_UART_BYTE_COUNT = 36;
localparam real    AUDIO_BCLK_HALF_PERIOD_NS = 333.333;
localparam real    AUDIO_LRC_HALF_PERIOD_NS = 10666.667;

reg sys_clk_50m;
reg sys_rst_n;
reg audio_bclk;
reg audio_lrc;
reg audio_adcdat;
reg uart1_rx;

wire audio_mclk;
wire audio_dacdat;
wire i2c_scl;
wire i2c_sda;
wire uart1_tx;

wire [15:0] soc_status;
wire [31:0] fabric_status;
wire firmware_started;
wire illegal_insn_seen;
wire codec_init_done;
wire codec_init_failed;
wire codec_i2c_error;
wire [7:0] codec_write_count;
wire [7:0] codec_malformed_count;
wire [7:0] codec_nack_count;
wire [7:0] codec_stop_count;
wire [7:0] codec_last_rx_byte;
wire [1:0] codec_last_rx_byte_index;
wire [3:0] codec_last_error_reason;
wire voice_active;
wire voice_clip_seen;
wire [15:0] voice_peak_level;
wire voice1_active;
wire voice1_clip_seen;
wire [15:0] voice1_peak_level;
wire voice2_active;
wire voice2_clip_seen;
wire [15:0] voice2_peak_level;
wire voice_mix_clip_seen;
wire [15:0] voice_mix_peak_level;
wire [31:0] voice_sample_count;
wire [31:0] voice_trigger_count;
wire [31:0] voice_active_count;
wire [31:0] voice_valid_count;
wire [31:0] voice1_trigger_count;
wire [31:0] voice1_active_count;
wire [31:0] voice1_valid_count;
wire [31:0] voice2_trigger_count;
wire [31:0] voice2_active_count;
wire [31:0] voice2_valid_count;
wire [31:0] voice_mix_clip_count;
wire [17:0] expected_mix_peak_level;

integer dac_toggle_count;
integer uart_capture_count;
integer uart_frame_error_count;
integer uart_index;
integer uart_mismatch_index;
reg     uart_bytes_match;
reg [7:0] uart_expected_mismatch;
reg [7:0] uart_observed_mismatch;
reg [7:0] uart_captured_bytes [0:EXPECTED_UART_BYTE_COUNT - 1];

function [7:0] expected_uart_byte;
    input integer index;
    begin
        case (index)
            0: expected_uart_byte = 8'h49;  // I
            1: expected_uart_byte = 8'h3D;  // =
            2: expected_uart_byte = 8'h35;
            3: expected_uart_byte = 8'h30;
            4: expected_uart_byte = 8'h33;
            5: expected_uart_byte = 8'h30;
            6: expected_uart_byte = 8'h33;
            7: expected_uart_byte = 8'h30;
            8: expected_uart_byte = 8'h33;
            9: expected_uart_byte = 8'h31;
            10: expected_uart_byte = 8'h0D;
            11: expected_uart_byte = 8'h0A;
            12: expected_uart_byte = 8'h53; // S
            13: expected_uart_byte = 8'h3D; // =
            22: expected_uart_byte = 8'h0D;
            23: expected_uart_byte = 8'h0A;
            24: expected_uart_byte = 8'h52; // R
            25: expected_uart_byte = 8'h3D; // =
            34: expected_uart_byte = 8'h0D;
            35: expected_uart_byte = 8'h0A;
            default: expected_uart_byte = 8'h00;
        endcase
    end
endfunction

function is_hex_ascii;
    input [7:0] value;
    begin
        is_hex_ascii = ((value >= 8'h30) && (value <= 8'h39)) ||
                       ((value >= 8'h41) && (value <= 8'h46));
    end
endfunction

task automatic capture_uart_byte;
    integer bit_index;
    reg [7:0] sampled_byte;
    begin
        sampled_byte = 8'h00;

        @(negedge uart1_tx);
        #UART_HALF_BIT_NS;
        if (uart1_tx !== 1'b0) begin
            uart_frame_error_count = uart_frame_error_count + 1;
        end

        #UART_BIT_PERIOD_NS;
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            sampled_byte[bit_index] = uart1_tx;
            #UART_BIT_PERIOD_NS;
        end

        if (uart1_tx !== 1'b1) begin
            uart_frame_error_count = uart_frame_error_count + 1;
        end

        if (uart_capture_count < EXPECTED_UART_BYTE_COUNT) begin
            uart_captured_bytes[uart_capture_count] = sampled_byte;
        end
        uart_capture_count = uart_capture_count + 1;

        #UART_HALF_BIT_NS;
    end
endtask

assign soc_status = dut.phase0_soc_inst.status_word;
assign fabric_status = dut.fabric_status;
assign firmware_started = dut.phase0_soc_inst.cpu_inst.firmware_started;
assign illegal_insn_seen = dut.phase0_soc_inst.cpu_inst.illegal_insn_seen;
assign codec_init_done = dut.wm8978_codec_stub_inst.init_done;
assign codec_init_failed = dut.wm8978_codec_stub_inst.init_failed;
assign codec_i2c_error = dut.wm8978_codec_stub_inst.i2c_error;
assign codec_write_count = codec_model_inst.write_count;
assign codec_malformed_count = codec_model_inst.malformed_count;
assign codec_nack_count = codec_model_inst.nack_count;
assign codec_stop_count = codec_model_inst.stop_count;
assign codec_last_rx_byte = codec_model_inst.last_rx_byte;
assign codec_last_rx_byte_index = codec_model_inst.last_rx_byte_index;
assign codec_last_error_reason = codec_model_inst.last_error_reason;
assign voice_active = dut.phase0_audio_path_inst.phase1_reduced_voice_inst.active;
assign voice_clip_seen = dut.phase0_audio_path_inst.phase1_reduced_voice_inst.clip_seen;
assign voice_peak_level = dut.phase0_audio_path_inst.phase1_reduced_voice_inst.peak_level;
assign voice1_active = dut.phase0_audio_path_inst.phase1_reduced_voice1_inst.active;
assign voice1_clip_seen = dut.phase0_audio_path_inst.phase1_reduced_voice1_inst.clip_seen;
assign voice1_peak_level = dut.phase0_audio_path_inst.phase1_reduced_voice1_inst.peak_level;
assign voice2_active = dut.phase0_audio_path_inst.phase1_reduced_voice2_inst.active;
assign voice2_clip_seen = dut.phase0_audio_path_inst.phase1_reduced_voice2_inst.clip_seen;
assign voice2_peak_level = dut.phase0_audio_path_inst.phase1_reduced_voice2_inst.peak_level;
assign voice_mix_clip_seen = dut.phase0_audio_path_inst.voice_mix_clip_seen_reg;
assign voice_mix_peak_level = dut.phase0_audio_path_inst.voice_mix_peak_level_reg;
assign voice_sample_count = dut.voice_sample_count;
assign voice_trigger_count = dut.voice_trigger_count;
assign voice_active_count = dut.voice_active_count;
assign voice_valid_count = dut.voice_valid_count;
assign voice1_trigger_count = dut.voice1_trigger_count;
assign voice1_active_count = dut.voice1_active_count;
assign voice1_valid_count = dut.voice1_valid_count;
assign voice2_trigger_count = dut.voice2_trigger_count;
assign voice2_active_count = dut.voice2_active_count;
assign voice2_valid_count = dut.voice2_valid_count;
assign voice_mix_clip_count = dut.voice_mix_clip_count;
assign expected_mix_peak_level = {2'd0, voice_peak_level} +
                                 {2'd0, voice1_peak_level} +
                                 {2'd0, voice2_peak_level};

piano_phase0_top dut (
    .sys_clk_50m  (sys_clk_50m),
    .sys_rst_n    (sys_rst_n),
    .audio_bclk   (audio_bclk),
    .audio_lrc    (audio_lrc),
    .audio_adcdat (audio_adcdat),
    .uart1_rx     (uart1_rx),
    .audio_mclk   (audio_mclk),
    .audio_dacdat (audio_dacdat),
    .i2c_scl      (i2c_scl),
    .i2c_sda      (i2c_sda),
    .uart1_tx     (uart1_tx)
);

wm8978_i2c_model #(
    .NACK_ENABLE      (NACK_ENABLE),
    .NACK_CFG_HIGH_BYTE(NACK_CFG_HIGH_BYTE)
) codec_model_inst (
    .sys_rst_n      (sys_rst_n),
    .i2c_scl        (i2c_scl),
    .i2c_sda        (i2c_sda),
    .write_count    (codec_write_count),
    .malformed_count(codec_malformed_count),
    .nack_count     (codec_nack_count),
    .stop_count     (codec_stop_count),
    .last_write_word(),
    .last_rx_byte   (codec_last_rx_byte),
    .last_rx_byte_index(codec_last_rx_byte_index),
    .last_error_reason(codec_last_error_reason)
);

always #10 sys_clk_50m = ~sys_clk_50m;
always #AUDIO_BCLK_HALF_PERIOD_NS audio_bclk = ~audio_bclk;
always #AUDIO_LRC_HALF_PERIOD_NS audio_lrc = ~audio_lrc;

always @(audio_dacdat) begin
    if ((sys_rst_n === 1'b1) && codec_init_done) begin
        dac_toggle_count = dac_toggle_count + 1;
    end
end

initial begin
    sys_clk_50m     = 1'b0;
    sys_rst_n       = 1'b0;
    audio_bclk      = 1'b0;
    audio_lrc       = 1'b0;
    audio_adcdat    = 1'b0;
    uart1_rx        = 1'b1;
    dac_toggle_count = 0;
    uart_capture_count = 0;
    uart_frame_error_count = 0;
    uart_bytes_match = 1'b0;
    uart_mismatch_index = -1;
    uart_expected_mismatch = 8'h00;
    uart_observed_mismatch = 8'h00;

    for (uart_index = 0; uart_index < EXPECTED_UART_BYTE_COUNT; uart_index = uart_index + 1) begin
        uart_captured_bytes[uart_index] = 8'h00;
    end

    #200;
    sys_rst_n = 1'b1;
end

initial begin
    @(posedge sys_rst_n);
    forever begin
        capture_uart_byte;
    end
end

initial begin
    #12_000_000;

    uart_bytes_match = (uart_capture_count >= EXPECTED_UART_BYTE_COUNT) &&
                       (uart_frame_error_count == 0);
    uart_mismatch_index = -1;
    if (uart_bytes_match) begin
        for (uart_index = 0; uart_index < EXPECTED_UART_BYTE_COUNT; uart_index = uart_index + 1) begin
            if (((uart_index >= 2) && (uart_index <= 9)) ||
                ((uart_index >= 14) && (uart_index <= 21)) ||
                ((uart_index >= 26) && (uart_index <= 33))) begin
                if (!is_hex_ascii(uart_captured_bytes[uart_index])) begin
                    uart_bytes_match = 1'b0;
                    if (uart_mismatch_index < 0) begin
                        uart_mismatch_index = uart_index;
                        uart_expected_mismatch = 8'h58;
                        uart_observed_mismatch = uart_captured_bytes[uart_index];
                    end
                end
            end else if (uart_captured_bytes[uart_index] != expected_uart_byte(uart_index)) begin
                uart_bytes_match = 1'b0;
                if (uart_mismatch_index < 0) begin
                    uart_mismatch_index = uart_index;
                    uart_expected_mismatch = expected_uart_byte(uart_index);
                    uart_observed_mismatch = uart_captured_bytes[uart_index];
                end
            end
        end
    end

    if (NACK_ENABLE == 0) begin
        if (!codec_init_done || codec_init_failed || !firmware_started ||
             illegal_insn_seen || codec_i2c_error ||
             (codec_write_count != EXPECTED_TOTAL_WRITE_COUNT) ||
             (codec_malformed_count != 8'd0) || (codec_nack_count != 8'd0) ||
             (codec_model_inst.captured_words[0] != 16'h0000) ||
             (codec_model_inst.captured_words[EXPECTED_INIT_WRITE_COUNT] != 16'h699E) ||
             (codec_model_inst.captured_words[EXPECTED_INIT_WRITE_COUNT + 1] != 16'h6B9E) ||
             (dac_toggle_count <= 0) || !uart_bytes_match ||
             !voice_active || voice_clip_seen || (voice_peak_level == 16'd0) ||
             (voice_sample_count == 32'd0) || (voice_trigger_count != 32'd1) ||
             (voice_active_count == 32'd0) || (voice_valid_count == 32'd0) ||
             !voice1_active || voice1_clip_seen || (voice1_peak_level == 16'd0) ||
             (voice1_trigger_count != 32'd1) || (voice1_active_count == 32'd0) ||
             (voice1_valid_count == 32'd0) ||
             !voice2_active || voice2_clip_seen || (voice2_peak_level == 16'd0) ||
             (voice2_trigger_count != 32'd1) || (voice2_active_count == 32'd0) ||
             (voice2_valid_count == 32'd0) || voice_mix_clip_seen ||
             (voice_mix_clip_count != 32'd0) ||
             (expected_mix_peak_level > 18'd32767) ||
             (voice_mix_peak_level != expected_mix_peak_level[15:0])) begin
            $display("TB_FAIL fabric_status=%h soc_status=%h firmware_started=%b illegal_insn_seen=%b init_done=%b init_failed=%b codec_i2c_error=%b write_count=%0d malformed_count=%0d nack_count=%0d dac_toggle_count=%0d voice_active=%b voice_clip_seen=%b voice_peak_level=%0d voice_sample_count=%0d voice_trigger_count=%0d voice_active_count=%0d voice_valid_count=%0d voice1_active=%b voice1_clip_seen=%b voice1_peak_level=%0d voice1_trigger_count=%0d voice1_active_count=%0d voice1_valid_count=%0d voice2_active=%b voice2_clip_seen=%b voice2_peak_level=%0d voice2_trigger_count=%0d voice2_active_count=%0d voice2_valid_count=%0d expected_mix_peak=%0d mix_clip_seen=%b mix_peak_level=%0d mix_clip_count=%0d uart_capture_count=%0d uart_frame_error_count=%0d uart_mismatch_index=%0d uart_expected=%h uart_observed=%h first_write=%h cpu_write0=%h cpu_write1=%h first_uart=%h%h%h%h%h%h%h%h%h%h%h%h last_rx_byte=%h last_rx_byte_index=%0d last_error_reason=%0d",
                     fabric_status, soc_status, firmware_started, illegal_insn_seen,
                     codec_init_done, codec_init_failed, codec_i2c_error,
                     codec_write_count, codec_malformed_count, codec_nack_count, dac_toggle_count,
                     voice_active, voice_clip_seen, voice_peak_level,
                     voice_sample_count, voice_trigger_count, voice_active_count, voice_valid_count,
                     voice1_active, voice1_clip_seen, voice1_peak_level,
                     voice1_trigger_count, voice1_active_count, voice1_valid_count,
                     voice2_active, voice2_clip_seen, voice2_peak_level,
                     voice2_trigger_count, voice2_active_count, voice2_valid_count,
                     expected_mix_peak_level,
                     voice_mix_clip_seen, voice_mix_peak_level, voice_mix_clip_count,
                     uart_capture_count, uart_frame_error_count,
                     uart_mismatch_index, uart_expected_mismatch, uart_observed_mismatch,
                     codec_model_inst.captured_words[0],
                     codec_model_inst.captured_words[EXPECTED_INIT_WRITE_COUNT],
                     codec_model_inst.captured_words[EXPECTED_INIT_WRITE_COUNT + 1],
                     uart_captured_bytes[0], uart_captured_bytes[1], uart_captured_bytes[2],
                     uart_captured_bytes[3], uart_captured_bytes[4], uart_captured_bytes[5],
                     uart_captured_bytes[6], uart_captured_bytes[7], uart_captured_bytes[8],
                     uart_captured_bytes[9], uart_captured_bytes[10], uart_captured_bytes[11],
                     codec_last_rx_byte, codec_last_rx_byte_index, codec_last_error_reason);
        end else begin
            $display("TB_PASS fabric_status=%h soc_status=%h write_count=%0d dac_toggle_count=%0d voice_peak_level=%0d voice1_peak_level=%0d voice2_peak_level=%0d expected_mix_peak=%0d mix_peak_level=%0d voice_sample_count=%0d voice_trigger_count=%0d voice1_trigger_count=%0d voice2_trigger_count=%0d voice_active_count=%0d voice1_active_count=%0d voice2_active_count=%0d voice_valid_count=%0d voice1_valid_count=%0d voice2_valid_count=%0d mix_clip_count=%0d uart_capture_count=%0d",
                     fabric_status, soc_status,
                     codec_write_count, dac_toggle_count, voice_peak_level,
                     voice1_peak_level, voice2_peak_level, expected_mix_peak_level,
                     voice_mix_peak_level,
                     voice_sample_count, voice_trigger_count, voice1_trigger_count,
                     voice2_trigger_count,
                     voice_active_count, voice1_active_count, voice2_active_count,
                     voice_valid_count, voice1_valid_count, voice2_valid_count,
                     voice_mix_clip_count,
                     uart_capture_count);
        end
    end else begin
        if (codec_init_done || !codec_init_failed || !firmware_started ||
            illegal_insn_seen || !codec_i2c_error ||
            (codec_write_count != 8'd0) || (codec_nack_count != 8'd1) ||
            (codec_malformed_count != 8'd0) || (codec_stop_count == 8'd0)) begin
            $display("TB_NACK_FAIL fabric_status=%h soc_status=%h firmware_started=%b illegal_insn_seen=%b init_done=%b init_failed=%b codec_i2c_error=%b write_count=%0d malformed_count=%0d nack_count=%0d stop_count=%0d last_rx_byte=%h last_rx_byte_index=%0d last_error_reason=%0d",
                     fabric_status, soc_status, firmware_started, illegal_insn_seen,
                     codec_init_done, codec_init_failed, codec_i2c_error,
                     codec_write_count, codec_malformed_count, codec_nack_count, codec_stop_count,
                     codec_last_rx_byte, codec_last_rx_byte_index, codec_last_error_reason);
        end else begin
            $display("TB_NACK_PASS fabric_status=%h soc_status=%h nack_count=%0d stop_count=%0d",
                     fabric_status, soc_status, codec_nack_count, codec_stop_count);
        end
    end

    $finish;
end

endmodule

module piano_phase0_top_tb;
    piano_phase0_tb_env #(
        .NACK_ENABLE(0)
    ) env ();
endmodule

module piano_phase0_top_nack_tb;
    piano_phase0_tb_env #(
        .NACK_ENABLE(1),
        .NACK_CFG_HIGH_BYTE(8'h00)
    ) env ();
endmodule
