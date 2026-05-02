`timescale 1ns / 1ps

module wm8978_boot_seq (
    input  wire        i2c_clk,
    input  wire        sys_rst_n,
    input  wire        codec_clk_ready,
    input  wire        cfg_end,
    input  wire        cfg_error,
    input  wire        cfg_timeout,
    input  wire        cpu_cfg_valid,
    input  wire [15:0] cpu_cfg_word,
    output reg         cfg_start,
    output reg  [15:0] cfg_word,
    output reg         init_done,
    output reg         init_failed,
    output reg         cfg_error_seen,
    output reg         cfg_timeout_seen,
    output reg         cfg_busy
);

localparam integer INIT_WORD_COUNT = 16;
localparam [9:0]   STARTUP_WAIT_CYCLES = 10'd1000;

reg [9:0] wait_count;
reg [4:0] init_index;
wire      startup_complete;

function [15:0] init_word;
    input [4:0] index;
    begin
        case (index)
            5'd0:  init_word = {7'd0 , 9'd0           };
            5'd1:  init_word = {7'd1 , 9'b1_0010_1111 };
            5'd2:  init_word = {7'd2 , 9'b1_1000_0000 };
            5'd3:  init_word = {7'd4 , 9'b0_0001_0000 };
            5'd4:  init_word = {7'd6 , 9'b0_0000_0001 };
            5'd5:  init_word = {7'd7 , 9'd0           };
            5'd6:  init_word = {7'd10, 9'b0_0000_1000 };
            5'd7:  init_word = {7'd43, 9'b0_0001_0000 };
            5'd8:  init_word = {7'd49, 9'b1_0000_0110 };
            5'd9:  init_word = {7'd50, 9'b0_0000_0001 };
            5'd10: init_word = {7'd51, 9'b0_0000_0001 };
            5'd11: init_word = {7'd52, 9'b110_010100 };
            5'd12: init_word = {7'd53, 9'b110_010100 };
            5'd13: init_word = {7'd54, 9'b110_000000 };
            5'd14: init_word = {7'd55, 9'b110_000000 };
            5'd15: init_word = {7'd3 , 9'b0_0110_1111 };
            default: init_word = 16'd0;
        endcase
    end
endfunction

assign startup_complete = init_done || init_failed;

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        wait_count       <= 10'd0;
        init_index       <= 5'd0;
        cfg_start        <= 1'b0;
        cfg_word         <= 16'd0;
        init_done        <= 1'b0;
        init_failed      <= 1'b0;
        cfg_error_seen   <= 1'b0;
        cfg_timeout_seen <= 1'b0;
        cfg_busy         <= 1'b0;
    end else begin
        cfg_start <= 1'b0;

        if (!startup_complete) begin
            if (!codec_clk_ready) begin
                wait_count <= 10'd0;
                init_index <= 5'd0;
                cfg_busy   <= 1'b0;
            end else if (wait_count < STARTUP_WAIT_CYCLES) begin
                wait_count <= wait_count + 1'b1;
            end else if (cfg_end) begin
                cfg_busy <= 1'b0;
                if (cfg_error) begin
                    init_failed    <= 1'b1;
                    cfg_error_seen <= 1'b1;
                    if (cfg_timeout) begin
                        cfg_timeout_seen <= 1'b1;
                    end
                end else if (init_index == INIT_WORD_COUNT - 1) begin
                    init_done <= 1'b1;
                end else begin
                    init_index <= init_index + 1'b1;
                end
            end else if (!cfg_busy) begin
                cfg_word  <= init_word(init_index);
                cfg_start <= 1'b1;
                cfg_busy  <= 1'b1;
            end
        end else begin
            if (cfg_end) begin
                cfg_busy <= 1'b0;
                if (cfg_error) begin
                    cfg_error_seen <= 1'b1;
                    if (cfg_timeout) begin
                        cfg_timeout_seen <= 1'b1;
                    end
                end
            end
            if (cpu_cfg_valid && !cfg_busy && !cfg_end) begin
                cfg_word  <= cpu_cfg_word;
                cfg_start <= 1'b1;
                cfg_busy  <= 1'b1;
            end
        end
    end
end

endmodule
