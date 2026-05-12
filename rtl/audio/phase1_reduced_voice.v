`timescale 1ns / 1ps

module phase1_reduced_voice (
    input  wire               sys_clk,
    input  wire               sys_rst_n,
    input  wire               sample_tick,
    input  wire               enable,
    input  wire               trigger_strobe,
    input  wire               reset_strobe,
    input  wire               clip_clear_strobe,
    input  wire               body_bypass,
    input  wire               disp_bypass,
    input  wire [15:0]        velocity_q15,
    input  wire [6:0]         loop_len,
    input  wire [15:0]        loop_gain_q15,
    input  wire [15:0]        damp_mix_q15,
    input  wire signed [15:0] disp_coeff_q15,
    input  wire [15:0]        body_mix_q15,
    output reg  signed [15:0] sample_data,
    output reg                sample_valid,
    output reg                active,
    output reg                excite_busy,
    output reg                clip_seen,
    output reg  [15:0]        peak_level
);

localparam signed [17:0] Q18_MAX = 18'sd131071;
localparam signed [17:0] Q18_MIN = -18'sd131071 - 18'sd1;

localparam [3:0] STATE_IDLE          = 4'd0;
localparam [3:0] STATE_AP_FINISH     = 4'd1;
localparam [3:0] STATE_DAMP_A_SETUP  = 4'd2;
localparam [3:0] STATE_DAMP_A_FINISH = 4'd3;
localparam [3:0] STATE_DAMP_B_FINISH = 4'd4;
localparam [3:0] STATE_GAIN_FINISH   = 4'd5;
localparam [3:0] STATE_EXCITE_FINISH = 4'd6;
localparam [3:0] STATE_BODY_FINISH   = 4'd7;
localparam [3:0] STATE_WRITE_SAMPLE  = 4'd8;
localparam [3:0] STATE_READ_DELAY    = 4'd9;
localparam [3:0] STATE_BODY_WAIT6    = 4'd10;
localparam [3:0] STATE_BODY_TAP6     = 4'd11;
localparam [3:0] STATE_BODY_WAIT16   = 4'd12;
localparam [3:0] STATE_BODY_TAP16    = 4'd13;
localparam [3:0] STATE_BODY_WAIT30   = 4'd14;
localparam [3:0] STATE_BODY_TAP30    = 4'd15;

reg [3:0] state;
reg [6:0] wr_ptr;
reg [6:0] rd_addr_q;
reg [6:0] clear_index;
reg       clear_active;
reg       clear_for_trigger;
reg [3:0] excite_index;
reg [15:0] quiet_count;

(* ramstyle = "M9K" *) reg signed [17:0] delay_line [0:127];
(* ramstyle = "M9K" *) reg signed [17:0] body_history [0:31];
reg signed [17:0] dl_sample;
reg signed [17:0] disp_sample;
reg signed [17:0] lp_state;
reg signed [17:0] ap_x_prev;
reg signed [17:0] ap_y_prev;
reg signed [17:0] damp_part_a;
reg signed [17:0] fb_sample;
reg signed [17:0] excite_sample;
reg signed [17:0] output_sample_q18;
reg signed [17:0] body_read_data;
reg signed [17:0] body_tap6;
reg signed [17:0] body_tap16;
reg [4:0] body_wr_ptr;
reg [4:0] body_read_addr;

reg signed [17:0] mult_sample;
reg signed [15:0] mult_coeff;
wire signed [33:0] mult_product = mult_sample * mult_coeff;

wire [6:0] rd_addr = wr_ptr - loop_len;
wire [15:0] damp_inv_q15 = 16'd32767 - damp_mix_q15;

wire [4:0] body_tap6_addr = body_wr_ptr - 5'd7;
wire [4:0] body_tap16_addr = body_wr_ptr - 5'd17;
wire [4:0] body_tap30_addr = body_wr_ptr - 5'd31;
wire       body_clear_we = clear_active && (clear_index < 7'd32);
wire       body_sample_we = (state == STATE_WRITE_SAMPLE);
wire       body_write_en = body_clear_we || body_sample_we;
wire [4:0] body_write_addr = body_clear_we ? clear_index[4:0] : body_wr_ptr;
wire signed [17:0] body_write_data = body_clear_we ? 18'sd0 : disp_sample;

function signed [31:0] q18_ext;
    input signed [17:0] value;
    begin
        q18_ext = {{14{value[17]}}, value};
    end
endfunction

function signed [17:0] sat_q18;
    input signed [31:0] value;
    begin
        if (value > 32'sd131071) begin
            sat_q18 = Q18_MAX;
        end else if (value < -32'sd131072) begin
            sat_q18 = Q18_MIN;
        end else begin
            sat_q18 = value[17:0];
        end
    end
endfunction

function signed [17:0] product_to_q18;
    input signed [33:0] value;
    reg signed [33:0] shifted;
    begin
        shifted = value >>> 15;
        if (shifted > 34'sd131071) begin
            product_to_q18 = Q18_MAX;
        end else if (shifted < -34'sd131072) begin
            product_to_q18 = Q18_MIN;
        end else begin
            product_to_q18 = shifted[17:0];
        end
    end
endfunction

function signed [15:0] q18_to_q15;
    input signed [17:0] value;
    begin
        q18_to_q15 = value[17:2];
    end
endfunction

function [15:0] abs_q15;
    input signed [15:0] value;
    begin
        if (value == 16'sh8000) begin
            abs_q15 = 16'h8000;
        end else if (value[15]) begin
            abs_q15 = 16'd0 - value[15:0];
        end else begin
            abs_q15 = value[15:0];
        end
    end
endfunction

function [15:0] excitation_rom;
    input [3:0] index;
    begin
        case (index)
            4'd0:  excitation_rom = 16'd1200;
            4'd1:  excitation_rom = 16'd9000;
            4'd2:  excitation_rom = 16'd24000;
            4'd3:  excitation_rom = 16'd32627;
            4'd4:  excitation_rom = 16'd26000;
            4'd5:  excitation_rom = 16'd19500;
            4'd6:  excitation_rom = 16'd14300;
            4'd7:  excitation_rom = 16'd10400;
            4'd8:  excitation_rom = 16'd7500;
            4'd9:  excitation_rom = 16'd5300;
            4'd10: excitation_rom = 16'd3700;
            4'd11: excitation_rom = 16'd2500;
            4'd12: excitation_rom = 16'd1600;
            4'd13: excitation_rom = 16'd1000;
            4'd14: excitation_rom = 16'd500;
            default: excitation_rom = 16'd200;
        endcase
    end
endfunction

always @(posedge sys_clk) begin
    if (body_write_en) begin
        body_history[body_write_addr] <= body_write_data;
    end
    body_read_data <= body_history[body_read_addr];
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state             <= STATE_IDLE;
        wr_ptr            <= 7'd0;
        rd_addr_q         <= 7'd0;
        body_wr_ptr       <= 5'd0;
        body_read_addr    <= 5'd0;
        clear_active      <= 1'b1;
        clear_for_trigger <= 1'b0;
        clear_index       <= 7'd0;
        excite_index      <= 4'd0;
        quiet_count       <= 16'd0;
        sample_data       <= 16'sd0;
        sample_valid      <= 1'b0;
        active            <= 1'b0;
        excite_busy       <= 1'b0;
        clip_seen         <= 1'b0;
        peak_level        <= 16'd0;
        dl_sample         <= 18'sd0;
        disp_sample       <= 18'sd0;
        lp_state          <= 18'sd0;
        ap_x_prev         <= 18'sd0;
        ap_y_prev         <= 18'sd0;
        damp_part_a       <= 18'sd0;
        fb_sample         <= 18'sd0;
        excite_sample     <= 18'sd0;
        output_sample_q18 <= 18'sd0;
        body_tap6         <= 18'sd0;
        body_tap16        <= 18'sd0;
        mult_sample       <= 18'sd0;
        mult_coeff        <= 16'sd0;
    end else begin
        sample_valid <= 1'b0;

        if (clip_clear_strobe) begin
            clip_seen  <= 1'b0;
            peak_level <= 16'd0;
        end

        if (reset_strobe || (trigger_strobe && enable)) begin
            state             <= STATE_IDLE;
            wr_ptr            <= 7'd0;
            rd_addr_q         <= 7'd0;
            body_wr_ptr       <= 5'd0;
            body_read_addr    <= 5'd0;
            clear_active      <= 1'b1;
            clear_for_trigger <= trigger_strobe && enable;
            clear_index       <= 7'd0;
            excite_index      <= 4'd0;
            quiet_count       <= 16'd0;
            sample_data       <= 16'sd0;
            active            <= 1'b0;
            excite_busy       <= 1'b0;
            dl_sample         <= 18'sd0;
            disp_sample       <= 18'sd0;
            lp_state          <= 18'sd0;
            ap_x_prev         <= 18'sd0;
            ap_y_prev         <= 18'sd0;
            damp_part_a       <= 18'sd0;
            fb_sample         <= 18'sd0;
            excite_sample     <= 18'sd0;
            output_sample_q18 <= 18'sd0;
            body_tap6         <= 18'sd0;
            body_tap16        <= 18'sd0;
            mult_sample       <= 18'sd0;
            mult_coeff        <= 16'sd0;
        end else if (clear_active) begin
            delay_line[clear_index] <= 18'sd0;

            if (clear_index == 7'd127) begin
                clear_active <= 1'b0;
                if (clear_for_trigger && enable) begin
                    active      <= 1'b1;
                    excite_busy <= 1'b1;
                end
                clear_for_trigger <= 1'b0;
            end else begin
                clear_index <= clear_index + 1'b1;
            end
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (sample_tick) begin
                        if (enable && active) begin
                            rd_addr_q <= rd_addr;
                            state     <= STATE_READ_DELAY;
                        end else begin
                            active            <= 1'b0;
                            excite_busy       <= 1'b0;
                            sample_data       <= 16'sd0;
                            output_sample_q18 <= 18'sd0;
                            sample_valid      <= 1'b1;
                        end
                    end
                end
                STATE_READ_DELAY: begin
                    dl_sample <= delay_line[rd_addr_q];
                    if (disp_bypass) begin
                        disp_sample <= delay_line[rd_addr_q];
                        state       <= STATE_DAMP_A_SETUP;
                    end else begin
                        mult_sample <= sat_q18(q18_ext(delay_line[rd_addr_q]) - q18_ext(ap_y_prev));
                        mult_coeff  <= disp_coeff_q15;
                        state       <= STATE_AP_FINISH;
                    end
                end
                STATE_AP_FINISH: begin
                    disp_sample <= sat_q18(q18_ext(ap_x_prev) + q18_ext(product_to_q18(mult_product)));
                    ap_x_prev   <= dl_sample;
                    ap_y_prev   <= sat_q18(q18_ext(ap_x_prev) + q18_ext(product_to_q18(mult_product)));
                    state       <= STATE_DAMP_A_SETUP;
                end
                STATE_DAMP_A_SETUP: begin
                    mult_sample <= disp_sample;
                    mult_coeff  <= $signed(damp_inv_q15[15:0]);
                    state       <= STATE_DAMP_A_FINISH;
                end
                STATE_DAMP_A_FINISH: begin
                    damp_part_a <= product_to_q18(mult_product);
                    mult_sample <= lp_state;
                    mult_coeff  <= $signed(damp_mix_q15[15:0]);
                    state       <= STATE_DAMP_B_FINISH;
                end
                STATE_DAMP_B_FINISH: begin
                    lp_state    <= sat_q18(q18_ext(damp_part_a) + q18_ext(product_to_q18(mult_product)));
                    mult_sample <= sat_q18(q18_ext(damp_part_a) + q18_ext(product_to_q18(mult_product)));
                    mult_coeff  <= $signed(loop_gain_q15[15:0]);
                    state       <= STATE_GAIN_FINISH;
                end
                STATE_GAIN_FINISH: begin
                    fb_sample <= product_to_q18(mult_product);
                    if (excite_busy) begin
                        mult_sample <= $signed({1'b0, excitation_rom(excite_index), 1'b0});
                        mult_coeff  <= $signed(velocity_q15[15:0]);
                        state       <= STATE_EXCITE_FINISH;
                    end else begin
                        excite_sample <= 18'sd0;
                        if (body_bypass) begin
                            output_sample_q18 <= disp_sample;
                            state             <= STATE_WRITE_SAMPLE;
                        end else begin
                            body_read_addr <= body_tap6_addr;
                            state          <= STATE_BODY_WAIT6;
                        end
                    end
                end
                STATE_EXCITE_FINISH: begin
                    excite_sample <= product_to_q18(mult_product) >>> 1;
                    if (excite_index == 4'd15) begin
                        excite_busy  <= 1'b0;
                        excite_index <= 4'd15;
                    end else begin
                        excite_index <= excite_index + 1'b1;
                    end

                    if (body_bypass) begin
                        output_sample_q18 <= disp_sample;
                        state             <= STATE_WRITE_SAMPLE;
                    end else begin
                        body_read_addr <= body_tap6_addr;
                        state          <= STATE_BODY_WAIT6;
                    end
                end
                STATE_BODY_WAIT6: begin
                    state <= STATE_BODY_TAP6;
                end
                STATE_BODY_TAP6: begin
                    body_tap6      <= body_read_data;
                    body_read_addr <= body_tap16_addr;
                    state          <= STATE_BODY_WAIT16;
                end
                STATE_BODY_WAIT16: begin
                    state <= STATE_BODY_TAP16;
                end
                STATE_BODY_TAP16: begin
                    body_tap16     <= body_read_data;
                    body_read_addr <= body_tap30_addr;
                    state          <= STATE_BODY_WAIT30;
                end
                STATE_BODY_WAIT30: begin
                    state <= STATE_BODY_TAP30;
                end
                STATE_BODY_TAP30: begin
                    mult_sample <= sat_q18((q18_ext(body_tap6) >>> 2) -
                                           (q18_ext(body_tap16) >>> 3) +
                                           (q18_ext(body_read_data) >>> 4));
                    mult_coeff  <= $signed(body_mix_q15[15:0]);
                    state       <= STATE_BODY_FINISH;
                end
                STATE_BODY_FINISH: begin
                    if ((q18_ext(disp_sample) + q18_ext(product_to_q18(mult_product)) > 32'sd131071) ||
                        (q18_ext(disp_sample) + q18_ext(product_to_q18(mult_product)) < -32'sd131072)) begin
                        clip_seen <= 1'b1;
                    end
                    output_sample_q18 <= sat_q18(q18_ext(disp_sample) + q18_ext(product_to_q18(mult_product)));
                    state             <= STATE_WRITE_SAMPLE;
                end
                STATE_WRITE_SAMPLE: begin
                    if ((q18_ext(fb_sample) + q18_ext(excite_sample) > 32'sd131071) ||
                        (q18_ext(fb_sample) + q18_ext(excite_sample) < -32'sd131072)) begin
                        clip_seen <= 1'b1;
                    end
                    delay_line[wr_ptr] <= sat_q18(q18_ext(fb_sample) + q18_ext(excite_sample));
                    wr_ptr <= wr_ptr + 1'b1;
                    body_wr_ptr <= body_wr_ptr + 1'b1;

                    sample_data  <= q18_to_q15(output_sample_q18);
                    sample_valid <= 1'b1;

                    if (abs_q15(q18_to_q15(output_sample_q18)) > peak_level) begin
                        peak_level <= abs_q15(q18_to_q15(output_sample_q18));
                    end

                    if (!excite_busy && (abs_q15(q18_to_q15(output_sample_q18)) < 16'd16)) begin
                        if (quiet_count == 16'hffff) begin
                            active <= 1'b0;
                        end else begin
                            quiet_count <= quiet_count + 1'b1;
                        end
                    end else begin
                        quiet_count <= 16'd0;
                    end

                    state <= STATE_IDLE;
                end
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
end

endmodule
