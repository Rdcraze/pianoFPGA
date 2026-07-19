`timescale 1ns / 1ps

module wm8978_codec_stub (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        audio_bclk,
    input  wire        audio_lrc,
    input  wire        audio_adcdat,
    input  wire        codec_cfg_valid,
    input  wire [15:0] codec_cfg_word,
    input  wire        tx_valid,
    input  wire [15:0] tx_sample,
    output wire        sample_tick,
    output wire        cfg_busy,
    output wire        audio_mclk,
    output wire        audio_dacdat,
    output wire        i2c_scl,
    inout  wire        i2c_sda,
    output wire [7:0]  status_word
);

reg        frame_toggle_bclk;
reg  [2:0] frame_toggle_sys;
reg        cpu_cfg_pending_sys;
reg        cpu_cfg_outstanding_sys;
reg        cpu_cfg_busy_seen_sys;
reg [15:0] cpu_cfg_word_sys;
reg        cpu_cfg_req_toggle_sys;
reg  [2:0] cpu_cfg_ack_sync_sys;
reg  [2:0] boot_cfg_busy_sync_sys;
reg  [2:0] init_done_sync_sys;
reg  [2:0] init_failed_sync_sys;
reg  [2:0] cfg_error_sync_sys;
reg  [2:0] cfg_timeout_sync_sys;
reg  [2:0] cpu_cfg_req_sync_i2c;
reg        cpu_cfg_req_seen_i2c;
reg [15:0] cpu_cfg_word_i2c;
reg        cpu_cfg_valid_i2c;
reg        cpu_cfg_ack_toggle_i2c;
reg  [2:0] mclk_locked_sync_i2c;
wire       init_done;
wire       init_failed;
wire       cfg_error_seen;
wire       cfg_timeout_seen;
wire       cfg_start;
wire [15:0] cfg_word;
wire       i2c_clk;
wire       i2c_rst_n;
wire       audio_bclk_rst_n;
wire       i2c_end;
wire       i2c_error;
wire       i2c_nack_error;
wire       i2c_timeout_error;
wire       boot_cfg_busy;
wire       frame_start_bclk;
wire       cpu_cfg_ack_pulse_sys;
wire       startup_complete_i2c;
wire       mclk_locked;

assign cpu_cfg_ack_pulse_sys = cpu_cfg_ack_sync_sys[2] ^ cpu_cfg_ack_sync_sys[1];
assign startup_complete_i2c = init_done || init_failed;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        frame_toggle_sys    <= 3'd0;
        cpu_cfg_pending_sys <= 1'b0;
        cpu_cfg_outstanding_sys <= 1'b0;
        cpu_cfg_busy_seen_sys   <= 1'b0;
        cpu_cfg_word_sys    <= 16'd0;
        cpu_cfg_req_toggle_sys <= 1'b0;
        cpu_cfg_ack_sync_sys   <= 3'd0;
        boot_cfg_busy_sync_sys <= 3'd0;
        init_done_sync_sys     <= 3'd0;
        init_failed_sync_sys   <= 3'd0;
        cfg_error_sync_sys     <= 3'd0;
        cfg_timeout_sync_sys   <= 3'd0;
    end else begin
        frame_toggle_sys    <= {frame_toggle_sys[1:0], frame_toggle_bclk};
        cpu_cfg_ack_sync_sys <= {cpu_cfg_ack_sync_sys[1:0], cpu_cfg_ack_toggle_i2c};
        boot_cfg_busy_sync_sys <= {boot_cfg_busy_sync_sys[1:0], boot_cfg_busy};
        init_done_sync_sys     <= {init_done_sync_sys[1:0], init_done};
        init_failed_sync_sys   <= {init_failed_sync_sys[1:0], init_failed};
        cfg_error_sync_sys     <= {cfg_error_sync_sys[1:0], cfg_error_seen};
        cfg_timeout_sync_sys   <= {cfg_timeout_sync_sys[1:0], cfg_timeout_seen};

        if (cpu_cfg_ack_pulse_sys) begin
            cpu_cfg_pending_sys <= 1'b0;
        end

        if (codec_cfg_valid && !cpu_cfg_pending_sys) begin
            cpu_cfg_pending_sys    <= 1'b1;
            cpu_cfg_outstanding_sys <= 1'b1;
            cpu_cfg_busy_seen_sys   <= 1'b0;
            cpu_cfg_word_sys       <= codec_cfg_word;
            cpu_cfg_req_toggle_sys <= ~cpu_cfg_req_toggle_sys;
        end

        if (cpu_cfg_outstanding_sys) begin
            if (boot_cfg_busy_sync_sys[2]) begin
                cpu_cfg_busy_seen_sys <= 1'b1;
            end else if (cpu_cfg_busy_seen_sys) begin
                cpu_cfg_outstanding_sys <= 1'b0;
                cpu_cfg_busy_seen_sys   <= 1'b0;
            end
        end
    end
end

always @(posedge audio_bclk or negedge audio_bclk_rst_n) begin
    if (!audio_bclk_rst_n) begin
        frame_toggle_bclk <= 1'b0;
    end else if (frame_start_bclk) begin
        frame_toggle_bclk <= ~frame_toggle_bclk;
    end
end

always @(posedge i2c_clk or negedge i2c_rst_n) begin
    if (!i2c_rst_n) begin
        cpu_cfg_req_sync_i2c   <= 3'd0;
        cpu_cfg_req_seen_i2c   <= 1'b0;
        cpu_cfg_word_i2c       <= 16'd0;
        cpu_cfg_valid_i2c      <= 1'b0;
        cpu_cfg_ack_toggle_i2c <= 1'b0;
        mclk_locked_sync_i2c   <= 3'd0;
    end else begin
        cpu_cfg_req_sync_i2c <= {cpu_cfg_req_sync_i2c[1:0], cpu_cfg_req_toggle_sys};
        cpu_cfg_valid_i2c    <= 1'b0;
        mclk_locked_sync_i2c <= {mclk_locked_sync_i2c[1:0], mclk_locked};

        if ((cpu_cfg_req_sync_i2c[2] != cpu_cfg_req_seen_i2c) && !boot_cfg_busy && startup_complete_i2c) begin
            cpu_cfg_req_seen_i2c   <= cpu_cfg_req_sync_i2c[2];
            cpu_cfg_word_i2c       <= cpu_cfg_word_sys;
            cpu_cfg_valid_i2c      <= 1'b1;
            cpu_cfg_ack_toggle_i2c <= ~cpu_cfg_ack_toggle_i2c;
        end
    end
end

assign sample_tick = frame_toggle_sys[2] ^ frame_toggle_sys[1];
assign cfg_busy    = cpu_cfg_outstanding_sys || boot_cfg_busy_sync_sys[2];

// sys_rst_n is released synchronously to sys_clk by the top-level reset
// synchronizer. Re-synchronize its release before using it as an asynchronous
// reset in either secondary clock domain. Assertion remains asynchronous, but
// every downstream register observes deassertion on a local clock edge.
//
// The I2C clock divider itself remains on sys_rst_n so i2c_clk can start and
// provide the edges needed to release i2c_rst_n.
phase0_reset_sync phase0_i2c_reset_sync_inst (
    .clk   (i2c_clk),
    .arst_n(sys_rst_n),
    .srst_n(i2c_rst_n)
);

phase0_reset_sync phase0_audio_bclk_reset_sync_inst (
    .clk   (audio_bclk),
    .arst_n(sys_rst_n),
    .srst_n(audio_bclk_rst_n)
);

phase0_audio_mclk_pll phase0_audio_mclk_pll_inst (
    .areset (~sys_rst_n),
    .inclk0 (sys_clk),
    .c0     (audio_mclk),
    .locked (mclk_locked)
);

wm8978_boot_seq wm8978_boot_seq_inst (
    .i2c_clk         (i2c_clk),
    .sys_rst_n       (i2c_rst_n),
    .codec_clk_ready (mclk_locked_sync_i2c[2]),
    .cfg_end         (i2c_end),
    .cfg_error       (i2c_error),
    .cfg_timeout     (i2c_timeout_error),
    .cpu_cfg_valid   (cpu_cfg_valid_i2c),
    .cpu_cfg_word    (cpu_cfg_word_i2c),
    .cfg_start       (cfg_start),
    .cfg_word        (cfg_word),
    .init_done       (init_done),
    .init_failed     (init_failed),
    .cfg_error_seen  (cfg_error_seen),
    .cfg_timeout_seen(cfg_timeout_seen),
    .cfg_busy        (boot_cfg_busy)
);

wm8978_i2c_ctrl #(
    .DEVICE_ADDR (7'b0011_010),
    .SYS_CLK_FREQ(26'd50_000_000),
    .SCL_FREQ    (18'd250_000)
) wm8978_i2c_ctrl_inst (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .i2c_rst_n  (i2c_rst_n),
    .wr_en      (1'b1),
    .rd_en      (1'b0),
    .i2c_start  (cfg_start),
    .addr_num   (1'b0),
    .byte_addr  ({8'd0, cfg_word[15:8]}),
    .wr_data    (cfg_word[7:0]),
    .i2c_clk    (i2c_clk),
    .i2c_end    (i2c_end),
    .i2c_busy   (),
    .i2c_error  (i2c_error),
    .i2c_nack_error(i2c_nack_error),
    .i2c_timeout_error(i2c_timeout_error),
    .rd_data    (),
    .i2c_scl    (i2c_scl),
    .i2c_sda    (i2c_sda)
);

wm8978_dac_tx wm8978_dac_tx_inst (
    .audio_bclk  (audio_bclk),
    .sys_rst_n   (audio_bclk_rst_n),
    .audio_lrc   (audio_lrc),
    .tx_sample   (tx_sample),
    .audio_dacdat(audio_dacdat),
    .frame_start (frame_start_bclk)
);

assign status_word = {
    init_done_sync_sys[2],
    init_failed_sync_sys[2],
    cfg_error_sync_sys[2],
    cfg_timeout_sync_sys[2],
    cpu_cfg_pending_sys,
    tx_valid,
    sample_tick,
    cfg_busy
};

endmodule
