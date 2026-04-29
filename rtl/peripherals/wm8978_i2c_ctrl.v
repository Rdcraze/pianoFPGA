`timescale 1ns / 1ps

module wm8978_i2c_ctrl #(
    parameter DEVICE_ADDR  = 7'b0011_010,
    parameter SYS_CLK_FREQ = 26'd50_000_000,
    parameter SCL_FREQ     = 18'd250_000
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire        i2c_start,
    input  wire        addr_num,
    input  wire [15:0] byte_addr,
    input  wire [7:0]  wr_data,
    output reg         i2c_clk,
    output reg         i2c_end,
    output wire        i2c_busy,
    output wire        i2c_error,
    output wire        i2c_nack_error,
    output wire        i2c_timeout_error,
    output reg [7:0]  rd_data,
    output reg         i2c_scl,
    inout  wire        i2c_sda
);

localparam CNT_CLK_MAX = (SYS_CLK_FREQ / SCL_FREQ) >> 3;
localparam [11:0] TXN_TIMEOUT_CYCLES = 12'd2048;

localparam IDLE         = 4'd0;
localparam START_1      = 4'd1;
localparam SEND_D_ADDR  = 4'd2;
localparam ACK_1        = 4'd3;
localparam SEND_B_ADDR_H= 4'd4;
localparam ACK_2        = 4'd5;
localparam SEND_B_ADDR_L= 4'd6;
localparam ACK_3        = 4'd7;
localparam WR_DATA      = 4'd8;
localparam ACK_4        = 4'd9;
localparam START_2      = 4'd10;
localparam SEND_RD_ADDR = 4'd11;
localparam ACK_5        = 4'd12;
localparam RD_DATA      = 4'd13;
localparam N_ACK        = 4'd14;
localparam STOP         = 4'd15;

wire       sda_in;
wire       sda_en;
wire [7:0] byte_addr_low;
reg  [7:0] cnt_clk;
reg  [3:0] state;
reg        cnt_i2c_clk_en;
reg  [1:0] cnt_i2c_clk;
reg  [2:0] cnt_bit;
reg        ack;
reg        nack_error;
reg        timeout_error;
reg        i2c_sda_reg;
reg  [7:0] rd_data_reg;
reg  [11:0] timeout_count;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        cnt_clk <= 8'd0;
    end else if (cnt_clk == CNT_CLK_MAX - 1'b1) begin
        cnt_clk <= 8'd0;
    end else begin
        cnt_clk <= cnt_clk + 1'b1;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        i2c_clk <= 1'b1;
    end else if (cnt_clk == CNT_CLK_MAX - 1'b1) begin
        i2c_clk <= ~i2c_clk;
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        cnt_i2c_clk_en <= 1'b0;
    end else if ((state == STOP) && (cnt_bit == 3'd3) && (cnt_i2c_clk == 2'd3)) begin
        cnt_i2c_clk_en <= 1'b0;
    end else if (i2c_start) begin
        cnt_i2c_clk_en <= 1'b1;
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        cnt_i2c_clk <= 2'd0;
    end else if (cnt_i2c_clk_en) begin
        cnt_i2c_clk <= cnt_i2c_clk + 1'b1;
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        cnt_bit <= 3'd0;
    end else if ((state == IDLE) || (state == START_1) || (state == START_2) ||
                 (state == ACK_1) || (state == ACK_2) || (state == ACK_3) ||
                 (state == ACK_4) || (state == ACK_5) || (state == N_ACK)) begin
        cnt_bit <= 3'd0;
    end else if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) begin
        cnt_bit <= 3'd0;
    end else if ((cnt_i2c_clk == 2'd3) && (state != IDLE)) begin
        cnt_bit <= cnt_bit + 1'b1;
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= IDLE;
    end else if (timeout_error && (state != IDLE) && (state != STOP)) begin
        state <= STOP;
    end else begin
        case (state)
            IDLE: begin
                if (i2c_start) state <= START_1;
            end
            START_1: begin
                if (cnt_i2c_clk == 2'd3) state <= SEND_D_ADDR;
            end
            SEND_D_ADDR: begin
                if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) state <= ACK_1;
            end
            ACK_1: begin
                if (cnt_i2c_clk == 2'd3) begin
                    state <= ack ? STOP : (addr_num ? SEND_B_ADDR_H : SEND_B_ADDR_L);
                end
            end
            SEND_B_ADDR_H: begin
                if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) state <= ACK_2;
            end
            ACK_2: begin
                if (cnt_i2c_clk == 2'd3) state <= ack ? STOP : SEND_B_ADDR_L;
            end
            SEND_B_ADDR_L: begin
                if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) state <= ACK_3;
            end
            ACK_3: begin
                if (cnt_i2c_clk == 2'd3) begin
                    if (ack) begin
                        state <= STOP;
                    end else if (wr_en) begin
                        state <= WR_DATA;
                    end else if (rd_en) begin
                        state <= START_2;
                    end else begin
                        state <= STOP;
                    end
                end
            end
            WR_DATA: begin
                if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) state <= ACK_4;
            end
            ACK_4: begin
                if (cnt_i2c_clk == 2'd3) state <= STOP;
            end
            START_2: begin
                if (cnt_i2c_clk == 2'd3) state <= SEND_RD_ADDR;
            end
            SEND_RD_ADDR: begin
                if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) state <= ACK_5;
            end
            ACK_5: begin
                if (cnt_i2c_clk == 2'd3) state <= ack ? STOP : RD_DATA;
            end
            RD_DATA: begin
                if ((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) state <= N_ACK;
            end
            N_ACK: begin
                if (cnt_i2c_clk == 2'd3) state <= STOP;
            end
            STOP: begin
                if ((cnt_bit == 3'd3) && (cnt_i2c_clk == 2'd3)) state <= IDLE;
            end
            default: begin
                state <= IDLE;
            end
        endcase
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        ack <= 1'b1;
    end else begin
        case (state)
            ACK_1, ACK_2, ACK_3, ACK_4, ACK_5: begin
                // Sample ACK/NACK while SCL is high and still treat anything
                // other than a driven-low ACK as a deterministic NACK so
                // undriven/X simulation states fail cleanly.
                if (cnt_i2c_clk == 2'd2) ack <= (sda_in !== 1'b0);
            end
            default: begin
                ack <= 1'b1;
            end
        endcase
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        nack_error    <= 1'b0;
        timeout_error <= 1'b0;
        timeout_count <= 12'd0;
    end else if ((state == IDLE) && i2c_start) begin
        nack_error    <= 1'b0;
        timeout_error <= 1'b0;
        timeout_count <= 12'd0;
    end else if (state == IDLE) begin
        timeout_count <= 12'd0;
    end else begin
        if (cnt_i2c_clk_en && !timeout_error) begin
            if (timeout_count == TXN_TIMEOUT_CYCLES - 1'b1) begin
                timeout_error <= 1'b1;
            end else begin
                timeout_count <= timeout_count + 1'b1;
            end
        end

        case (state)
            ACK_1, ACK_2, ACK_3, ACK_4, ACK_5: begin
                if ((cnt_i2c_clk == 2'd3) && ack) begin
                    nack_error <= 1'b1;
                end
            end
            default: begin
            end
        endcase
    end
end

always @(*) begin
    case (state)
        IDLE: i2c_scl = 1'b1;
        START_1: i2c_scl = (cnt_i2c_clk == 2'd3) ? 1'b0 : 1'b1;
        SEND_D_ADDR, ACK_1, SEND_B_ADDR_H, ACK_2, SEND_B_ADDR_L,
        ACK_3, WR_DATA, ACK_4, START_2, SEND_RD_ADDR, ACK_5, RD_DATA, N_ACK:
            i2c_scl = ((cnt_i2c_clk == 2'd1) || (cnt_i2c_clk == 2'd2)) ? 1'b1 : 1'b0;
        STOP: i2c_scl = ((cnt_bit == 3'd0) && (cnt_i2c_clk == 2'd0)) ? 1'b0 : 1'b1;
        default: i2c_scl = 1'b1;
    endcase
end

always @(*) begin
    case (state)
        IDLE: begin
            i2c_sda_reg = 1'b1;
        end
        START_1: begin
            i2c_sda_reg = (cnt_i2c_clk <= 2'd0) ? 1'b1 : 1'b0;
        end
        SEND_D_ADDR: begin
            i2c_sda_reg = (cnt_bit <= 3'd6) ? DEVICE_ADDR[6 - cnt_bit] : 1'b0;
        end
        ACK_1: begin
            i2c_sda_reg = 1'b1;
        end
        SEND_B_ADDR_H: begin
            i2c_sda_reg = byte_addr[15 - cnt_bit];
        end
        ACK_2: begin
            i2c_sda_reg = 1'b1;
        end
        SEND_B_ADDR_L: begin
            i2c_sda_reg = byte_addr_low[7 - cnt_bit];
        end
        ACK_3: begin
            i2c_sda_reg = 1'b1;
        end
        WR_DATA: begin
            i2c_sda_reg = wr_data[7 - cnt_bit];
        end
        ACK_4: begin
            i2c_sda_reg = 1'b1;
        end
        START_2: begin
            i2c_sda_reg = (cnt_i2c_clk <= 2'd1) ? 1'b1 : 1'b0;
        end
        SEND_RD_ADDR: begin
            i2c_sda_reg = (cnt_bit <= 3'd6) ? DEVICE_ADDR[6 - cnt_bit] : 1'b1;
        end
        ACK_5: begin
            i2c_sda_reg = 1'b1;
        end
        RD_DATA: begin
            i2c_sda_reg = 1'b1;
        end
        N_ACK: begin
            i2c_sda_reg = 1'b1;
        end
        STOP: begin
            i2c_sda_reg = ((cnt_bit == 3'd0) && (cnt_i2c_clk < 2'd3)) ? 1'b0 : 1'b1;
        end
        default: begin
            i2c_sda_reg = 1'b1;
        end
    endcase
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rd_data_reg <= 8'd0;
    end else if (state == IDLE) begin
        rd_data_reg <= 8'd0;
    end else if ((state == RD_DATA) && (cnt_i2c_clk == 2'd2)) begin
        rd_data_reg[7 - cnt_bit] <= sda_in;
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rd_data <= 8'd0;
    end else if ((state == RD_DATA) && (cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3)) begin
        rd_data <= rd_data_reg;
    end
end

always @(posedge i2c_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        i2c_end <= 1'b0;
    end else if ((state == STOP) && (cnt_bit == 3'd3) && (cnt_i2c_clk == 2'd3)) begin
        i2c_end <= 1'b1;
    end else begin
        i2c_end <= 1'b0;
    end
end

assign sda_in  = i2c_sda;
assign sda_en  = ((state == RD_DATA) || (state == ACK_1) || (state == ACK_2) ||
                 (state == ACK_3) || (state == ACK_4) || (state == ACK_5)) ? 1'b0 : 1'b1;
assign byte_addr_low = byte_addr[7:0];
assign i2c_sda = sda_en ? i2c_sda_reg : 1'bz;
assign i2c_busy = cnt_i2c_clk_en || (state != IDLE);
assign i2c_error = nack_error || timeout_error;
assign i2c_nack_error = nack_error;
assign i2c_timeout_error = timeout_error;

endmodule
