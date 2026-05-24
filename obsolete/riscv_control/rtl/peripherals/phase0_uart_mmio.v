`timescale 1ns / 1ps

module phase0_uart_mmio (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [2:0]  addr_word,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire [15:0] status_word
);

localparam [2:0] REG_TXDATA   = 3'd0;
localparam [2:0] REG_STATUS   = 3'd1;
localparam [2:0] REG_RXDATA   = 3'd2;
localparam [2:0] REG_RXSTATUS = 3'd3;
localparam [2:0] REG_RXCONTROL= 3'd4;

reg  tx_seen;
reg  tx_drop_seen;
reg  rd_en_q;
reg [2:0] addr_word_q;
wire tx_ready;
wire tx_valid;
wire rx_byte_valid;
wire [7:0] rx_byte_data;
wire rx_frame_error_pulse;

reg [7:0] rx_fifo0;
reg [7:0] rx_fifo1;
reg [7:0] rx_fifo2;
reg [7:0] rx_fifo3;
reg [7:0] rx_fifo4;
reg [7:0] rx_fifo5;
reg [7:0] rx_fifo6;
reg [7:0] rx_fifo7;
reg [7:0] rx_fifo8;
reg [7:0] rx_fifo9;
reg [7:0] rx_fifo10;
reg [7:0] rx_fifo11;
reg [7:0] rx_fifo12;
reg [7:0] rx_fifo13;
reg [7:0] rx_fifo14;
reg [7:0] rx_fifo15;
reg [4:0] rx_count;
reg       rx_overrun_seen;
reg       rx_frame_error_seen;
reg       rx_dropped_seen;

wire rx_pop;
wire rx_has_space;
wire rx_store;
wire [4:0] rx_store_index;
wire rx_overrun_now;
wire rx_control_wr;
wire rx_clear_errors;
wire rx_flush_fifo;

assign tx_valid = wr_en && (addr_word == REG_TXDATA) && tx_ready;
assign rx_pop = rd_en && (addr_word == REG_RXDATA) &&
                rd_en_q && (addr_word_q == REG_RXDATA) &&
                (rx_count != 5'd0);
assign rx_has_space = (rx_count != 5'd16) || rx_pop;
assign rx_store = rx_byte_valid && rx_has_space;
assign rx_store_index = rx_count - {4'd0, rx_pop};
assign rx_overrun_now = rx_byte_valid && !rx_has_space;
assign rx_control_wr = wr_en && (addr_word == REG_RXCONTROL);
assign rx_clear_errors = rx_control_wr && wdata[0];
assign rx_flush_fifo = rx_control_wr && wdata[1];

uart_tx #(
    .CLK_FREQ_HZ(50_000_000),
    .BAUD_RATE  (115_200)
) uart_tx_inst (
    .sys_clk (sys_clk),
    .sys_rst_n(sys_rst_n),
    .tx_valid(tx_valid),
    .tx_data (wdata[7:0]),
    .tx_ready(tx_ready),
    .uart_tx (uart_tx)
);

uart_rx #(
    .CLK_FREQ_HZ(50_000_000),
    .BAUD_RATE  (115_200)
) uart_rx_inst (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .uart_rx    (uart_rx),
    .rx_valid   (rx_byte_valid),
    .rx_data    (rx_byte_data),
    .frame_error(rx_frame_error_pulse)
);

assign status_word = {
    8'd0,
    rx_dropped_seen,
    rx_frame_error_seen,
    rx_overrun_seen,
    (rx_count != 5'd0),
    tx_drop_seen,
    tx_seen,
    tx_ready,
    uart_rx
};

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tx_seen      <= 1'b0;
        tx_drop_seen <= 1'b0;
        rd_en_q      <= 1'b0;
        addr_word_q  <= 3'd0;
    end else begin
        rd_en_q     <= rd_en;
        addr_word_q <= addr_word;
        if (tx_valid) begin
            tx_seen <= 1'b1;
        end
        if (wr_en && (addr_word == REG_TXDATA) && !tx_ready) begin
            tx_drop_seen <= 1'b1;
        end
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rx_count           <= 5'd0;
        rx_overrun_seen    <= 1'b0;
        rx_frame_error_seen<= 1'b0;
        rx_dropped_seen    <= 1'b0;
        rx_fifo0           <= 8'd0;
        rx_fifo1           <= 8'd0;
        rx_fifo2           <= 8'd0;
        rx_fifo3           <= 8'd0;
        rx_fifo4           <= 8'd0;
        rx_fifo5           <= 8'd0;
        rx_fifo6           <= 8'd0;
        rx_fifo7           <= 8'd0;
        rx_fifo8           <= 8'd0;
        rx_fifo9           <= 8'd0;
        rx_fifo10          <= 8'd0;
        rx_fifo11          <= 8'd0;
        rx_fifo12          <= 8'd0;
        rx_fifo13          <= 8'd0;
        rx_fifo14          <= 8'd0;
        rx_fifo15          <= 8'd0;
    end else begin
        if (rx_clear_errors) begin
            rx_overrun_seen     <= 1'b0;
            rx_frame_error_seen <= 1'b0;
            rx_dropped_seen     <= 1'b0;
        end

        if (rx_frame_error_pulse) begin
            rx_frame_error_seen <= 1'b1;
        end
        if (rx_overrun_now) begin
            rx_overrun_seen <= 1'b1;
        end

        if (rx_flush_fifo) begin
            rx_count        <= 5'd0;
            rx_dropped_seen <= 1'b1;
        end else begin
            if (rx_pop) begin
                rx_fifo0  <= rx_fifo1;
                rx_fifo1  <= rx_fifo2;
                rx_fifo2  <= rx_fifo3;
                rx_fifo3  <= rx_fifo4;
                rx_fifo4  <= rx_fifo5;
                rx_fifo5  <= rx_fifo6;
                rx_fifo6  <= rx_fifo7;
                rx_fifo7  <= rx_fifo8;
                rx_fifo8  <= rx_fifo9;
                rx_fifo9  <= rx_fifo10;
                rx_fifo10 <= rx_fifo11;
                rx_fifo11 <= rx_fifo12;
                rx_fifo12 <= rx_fifo13;
                rx_fifo13 <= rx_fifo14;
                rx_fifo14 <= rx_fifo15;
            end
            if (rx_store) begin
                case (rx_store_index)
                    5'd0:  rx_fifo0  <= rx_byte_data;
                    5'd1:  rx_fifo1  <= rx_byte_data;
                    5'd2:  rx_fifo2  <= rx_byte_data;
                    5'd3:  rx_fifo3  <= rx_byte_data;
                    5'd4:  rx_fifo4  <= rx_byte_data;
                    5'd5:  rx_fifo5  <= rx_byte_data;
                    5'd6:  rx_fifo6  <= rx_byte_data;
                    5'd7:  rx_fifo7  <= rx_byte_data;
                    5'd8:  rx_fifo8  <= rx_byte_data;
                    5'd9:  rx_fifo9  <= rx_byte_data;
                    5'd10: rx_fifo10 <= rx_byte_data;
                    5'd11: rx_fifo11 <= rx_byte_data;
                    5'd12: rx_fifo12 <= rx_byte_data;
                    5'd13: rx_fifo13 <= rx_byte_data;
                    5'd14: rx_fifo14 <= rx_byte_data;
                    5'd15: rx_fifo15 <= rx_byte_data;
                    default: rx_fifo15 <= rx_fifo15;
                endcase
            end

            case ({rx_store, rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end
end

always @(*) begin
    rdata = 32'd0;
    if (rd_en) begin
        case (addr_word)
            REG_STATUS: begin
                rdata = {31'd0, tx_ready};
            end
            REG_RXDATA: begin
                rdata = (rx_count != 5'd0) ? {24'd0, rx_fifo0} : 32'd0;
            end
            REG_RXSTATUS: begin
                rdata = {
                    27'd0,
                    rx_dropped_seen,
                    rx_frame_error_seen,
                    rx_overrun_seen,
                    (rx_count == 5'd16),
                    (rx_count != 5'd0)
                };
            end
            default: begin
                rdata = 32'd0;
            end
        endcase
    end
end

endmodule

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       uart_rx,
    output reg        rx_valid,
    output reg  [7:0] rx_data,
    output reg        frame_error
);

localparam integer BAUD_DIV = (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
localparam [31:0] BAUD_DIV_LAST = BAUD_DIV - 1;
localparam [31:0] BAUD_DIV_HALF = (BAUD_DIV / 2);

localparam [1:0] STATE_IDLE  = 2'd0;
localparam [1:0] STATE_START = 2'd1;
localparam [1:0] STATE_DATA  = 2'd2;
localparam [1:0] STATE_STOP  = 2'd3;

reg [1:0] state;
reg [15:0] baud_count;
reg [2:0] bit_index;
reg [7:0] shift_reg;
reg rx_meta;
reg rx_sync;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        rx_meta <= uart_rx;
        rx_sync <= rx_meta;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state       <= STATE_IDLE;
        baud_count  <= 16'd0;
        bit_index   <= 3'd0;
        shift_reg   <= 8'd0;
        rx_valid    <= 1'b0;
        rx_data     <= 8'd0;
        frame_error <= 1'b0;
    end else begin
        rx_valid    <= 1'b0;
        frame_error <= 1'b0;

        case (state)
            STATE_IDLE: begin
                if (!rx_sync) begin
                    state      <= STATE_START;
                    baud_count <= BAUD_DIV_HALF[15:0];
                end
            end

            STATE_START: begin
                if (baud_count != 16'd0) begin
                    baud_count <= baud_count - 1'b1;
                end else if (!rx_sync) begin
                    state      <= STATE_DATA;
                    baud_count <= BAUD_DIV_LAST[15:0];
                    bit_index  <= 3'd0;
                end else begin
                    state <= STATE_IDLE;
                end
            end

            STATE_DATA: begin
                if (baud_count != 16'd0) begin
                    baud_count <= baud_count - 1'b1;
                end else begin
                    shift_reg[bit_index] <= rx_sync;
                    baud_count <= BAUD_DIV_LAST[15:0];
                    if (bit_index == 3'd7) begin
                        state <= STATE_STOP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end
            end

            STATE_STOP: begin
                if (baud_count != 16'd0) begin
                    baud_count <= baud_count - 1'b1;
                end else begin
                    if (rx_sync) begin
                        rx_data  <= shift_reg;
                        rx_valid <= 1'b1;
                    end else begin
                        frame_error <= 1'b1;
                    end
                    state <= STATE_IDLE;
                end
            end

            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end
end

endmodule
