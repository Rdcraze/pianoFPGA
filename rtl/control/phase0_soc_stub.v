`timescale 1ns / 1ps

module phase0_soc_stub (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        uart_rx,
    input  wire [31:0] reg_rdata,
    output wire        uart_tx,
    output reg         reg_wr_en,
    output reg         reg_rd_en,
    output reg  [7:0]  reg_addr,
    output reg  [31:0] reg_wdata,
    output wire [15:0] status_word
);

localparam [7:0] REG_IDENT      = 8'h00;
localparam [7:0] REG_CONTROL    = 8'h04;
localparam [7:0] REG_PHASE_STEP = 8'h08;
localparam [7:0] REG_GAIN       = 8'h0C;
localparam [7:0] REG_DECAY_STEP = 8'h10;
localparam [7:0] REG_CODEC_CFG  = 8'h14;
localparam [7:0] REG_STATUS     = 8'h18;

localparam [31:0] CONTROL_BASE      = 32'h0000_0003;
localparam [31:0] CONTROL_TRIGGER   = 32'h0000_0100;
localparam [31:0] CONTROL_CODEC_CFG = 32'h0000_0200;
localparam [31:0] STATUS_INIT_DONE  = 32'h8000_0000;
localparam [31:0] STATUS_INIT_FAIL  = 32'h4000_0000;
localparam [31:0] STATUS_CODEC_BUSY = 32'h0100_0000;
localparam [31:0] DEFAULT_PHASE     = 32'd157482;
localparam [31:0] DEFAULT_GAIN      = 32'd4096;
localparam [31:0] DEFAULT_DECAY     = 32'd0;
localparam [31:0] DEFAULT_CFG_0     = 32'h0000_699E;
localparam [31:0] DEFAULT_CFG_1     = 32'h0000_6B9E;
localparam [31:0] RESET_WAIT_CYCLES = 32'd50_000;
localparam [31:0] INIT_POLL_LIMIT   = 32'd10_000_000;
localparam [31:0] REPORT_INTERVAL   = 32'd12_500_000;

localparam [4:0] ST_RESET_WAIT             = 5'd0;
localparam [4:0] ST_WRITE_PHASE            = 5'd1;
localparam [4:0] ST_WRITE_GAIN             = 5'd2;
localparam [4:0] ST_WRITE_DECAY            = 5'd3;
localparam [4:0] ST_WRITE_CONTROL          = 5'd4;
localparam [4:0] ST_READ_IDENT_REQ         = 5'd5;
localparam [4:0] ST_READ_IDENT_CAPTURE     = 5'd6;
localparam [4:0] ST_SEND_IDENT_START       = 5'd7;
localparam [4:0] ST_SEND_IDENT_WAIT        = 5'd8;
localparam [4:0] ST_WAIT_INIT_REQ          = 5'd9;
localparam [4:0] ST_WAIT_INIT_CAPTURE      = 5'd10;
localparam [4:0] ST_SEND_BOOT_STATUS_START = 5'd11;
localparam [4:0] ST_SEND_BOOT_STATUS_WAIT  = 5'd12;
localparam [4:0] ST_WRITE_CODEC0_WORD      = 5'd13;
localparam [4:0] ST_PULSE_CODEC0           = 5'd14;
localparam [4:0] ST_WAIT_CODEC0_REQ        = 5'd15;
localparam [4:0] ST_WAIT_CODEC0_CAPTURE    = 5'd16;
localparam [4:0] ST_WRITE_CODEC1_WORD      = 5'd17;
localparam [4:0] ST_PULSE_CODEC1           = 5'd18;
localparam [4:0] ST_WAIT_CODEC1_REQ        = 5'd19;
localparam [4:0] ST_WAIT_CODEC1_CAPTURE    = 5'd20;
localparam [4:0] ST_TRIGGER_NOTE           = 5'd21;
localparam [4:0] ST_SEND_RUNTIME_START     = 5'd22;
localparam [4:0] ST_SEND_RUNTIME_WAIT      = 5'd23;
localparam [4:0] ST_PERIODIC_WAIT          = 5'd24;
localparam [4:0] ST_PERIODIC_STATUS_REQ    = 5'd25;
localparam [4:0] ST_PERIODIC_STATUS_CAPTURE= 5'd26;
localparam [4:0] ST_PERIODIC_TRIGGER       = 5'd27;

reg  [4:0]  state;
reg  [31:0] ident_value;
reg  [31:0] status_value;
reg  [31:0] wait_count;
reg  [31:0] init_poll_count;
reg         init_done_seen;
reg         init_failed_seen;
reg         codec_write_exercised;
reg         codec_busy_seen;
reg         frame_active;
reg  [3:0]  frame_index;
reg  [7:0]  frame_tag;
reg  [31:0] frame_value;
reg         tx_valid;
reg  [7:0]  tx_data;
wire        tx_ready;
wire        tx_accept;

function [7:0] hex_ascii;
    input [3:0] nibble;
    begin
        if (nibble < 4'd10) begin
            hex_ascii = 8'h30 + nibble;
        end else begin
            hex_ascii = 8'h41 + nibble - 4'd10;
        end
    end
endfunction

function [7:0] frame_byte;
    input [7:0]  tag;
    input [31:0] value;
    input [3:0]  index;
    begin
        case (index)
            4'd0: frame_byte = tag;
            4'd1: frame_byte = 8'h3D;
            4'd2: frame_byte = hex_ascii(value[31:28]);
            4'd3: frame_byte = hex_ascii(value[27:24]);
            4'd4: frame_byte = hex_ascii(value[23:20]);
            4'd5: frame_byte = hex_ascii(value[19:16]);
            4'd6: frame_byte = hex_ascii(value[15:12]);
            4'd7: frame_byte = hex_ascii(value[11:8]);
            4'd8: frame_byte = hex_ascii(value[7:4]);
            4'd9: frame_byte = hex_ascii(value[3:0]);
            4'd10: frame_byte = 8'h0D;
            default: frame_byte = 8'h0A;
        endcase
    end
endfunction

uart_tx #(
    .CLK_FREQ_HZ(50_000_000),
    .BAUD_RATE  (115_200)
) uart_tx_inst (
    .sys_clk (sys_clk),
    .sys_rst_n(sys_rst_n),
    .tx_valid(tx_valid),
    .tx_data (tx_data),
    .tx_ready(tx_ready),
    .uart_tx (uart_tx)
);

assign tx_accept = tx_valid && tx_ready;

assign status_word = {
    7'd0,
    uart_rx,
    frame_active,
    codec_write_exercised,
    init_failed_seen,
    init_done_seen,
    state[3:0]
};

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state                 <= ST_RESET_WAIT;
        ident_value           <= 32'd0;
        status_value          <= 32'd0;
        wait_count            <= 32'd0;
        init_poll_count       <= 32'd0;
        init_done_seen        <= 1'b0;
        init_failed_seen      <= 1'b0;
        codec_write_exercised <= 1'b0;
        codec_busy_seen       <= 1'b0;
        frame_active          <= 1'b0;
        frame_index           <= 4'd0;
        frame_tag             <= 8'd0;
        frame_value           <= 32'd0;
        tx_valid              <= 1'b0;
        tx_data               <= 8'd0;
        reg_wr_en             <= 1'b0;
        reg_rd_en             <= 1'b0;
        reg_addr              <= 8'd0;
        reg_wdata             <= 32'd0;
    end else begin
        reg_wr_en <= 1'b0;
        reg_rd_en <= 1'b0;

        // Hold the current byte stable until the UART consumes it.
        if (tx_accept) begin
            tx_valid <= 1'b0;
            if (frame_index == 4'd11) begin
                frame_active <= 1'b0;
                frame_index  <= 4'd0;
            end else begin
                frame_index <= frame_index + 1'b1;
            end
        end else if (frame_active && !tx_valid) begin
            tx_valid <= 1'b1;
            tx_data  <= frame_byte(frame_tag, frame_value, frame_index);
        end

        case (state)
            ST_RESET_WAIT: begin
                if (wait_count < RESET_WAIT_CYCLES - 1'b1) begin
                    wait_count <= wait_count + 1'b1;
                end else begin
                    wait_count <= 32'd0;
                    state      <= ST_WRITE_PHASE;
                end
            end
            ST_WRITE_PHASE: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_PHASE_STEP;
                reg_wdata <= DEFAULT_PHASE;
                state     <= ST_WRITE_GAIN;
            end
            ST_WRITE_GAIN: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_GAIN;
                reg_wdata <= DEFAULT_GAIN;
                state     <= ST_WRITE_DECAY;
            end
            ST_WRITE_DECAY: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_DECAY_STEP;
                reg_wdata <= DEFAULT_DECAY;
                state     <= ST_WRITE_CONTROL;
            end
            ST_WRITE_CONTROL: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_CONTROL;
                reg_wdata <= CONTROL_BASE;
                state     <= ST_READ_IDENT_REQ;
            end
            ST_READ_IDENT_REQ: begin
                reg_rd_en <= 1'b1;
                reg_addr  <= REG_IDENT;
                state     <= ST_READ_IDENT_CAPTURE;
            end
            ST_READ_IDENT_CAPTURE: begin
                ident_value <= reg_rdata;
                state       <= ST_SEND_IDENT_START;
            end
            ST_SEND_IDENT_START: begin
                if (!frame_active) begin
                    frame_active <= 1'b1;
                    frame_index  <= 4'd0;
                    frame_tag    <= 8'h49;
                    frame_value  <= ident_value;
                    state        <= ST_SEND_IDENT_WAIT;
                end
            end
            ST_SEND_IDENT_WAIT: begin
                if (!frame_active) begin
                    state <= ST_WAIT_INIT_REQ;
                end
            end
            ST_WAIT_INIT_REQ: begin
                reg_rd_en <= 1'b1;
                reg_addr  <= REG_STATUS;
                state     <= ST_WAIT_INIT_CAPTURE;
            end
            ST_WAIT_INIT_CAPTURE: begin
                status_value <= reg_rdata;
                if ((reg_rdata & STATUS_INIT_DONE) != 32'd0) begin
                    init_done_seen <= 1'b1;
                    state          <= ST_SEND_BOOT_STATUS_START;
                end else if ((reg_rdata & STATUS_INIT_FAIL) != 32'd0) begin
                    init_failed_seen <= 1'b1;
                    state            <= ST_SEND_BOOT_STATUS_START;
                end else if (init_poll_count >= INIT_POLL_LIMIT) begin
                    init_failed_seen <= 1'b1;
                    state            <= ST_SEND_BOOT_STATUS_START;
                end else begin
                    init_poll_count <= init_poll_count + 1'b1;
                    state           <= ST_WAIT_INIT_REQ;
                end
            end
            ST_SEND_BOOT_STATUS_START: begin
                if (!frame_active) begin
                    frame_active <= 1'b1;
                    frame_index  <= 4'd0;
                    frame_tag    <= 8'h53;
                    frame_value  <= status_value;
                    state        <= ST_SEND_BOOT_STATUS_WAIT;
                end
            end
            ST_SEND_BOOT_STATUS_WAIT: begin
                if (!frame_active) begin
                    if (init_done_seen && !init_failed_seen) begin
                        state <= ST_WRITE_CODEC0_WORD;
                    end else begin
                        wait_count <= 32'd0;
                        state      <= ST_PERIODIC_WAIT;
                    end
                end
            end
            ST_WRITE_CODEC0_WORD: begin
                codec_busy_seen <= 1'b0;
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_CODEC_CFG;
                reg_wdata <= DEFAULT_CFG_0;
                state     <= ST_PULSE_CODEC0;
            end
            ST_PULSE_CODEC0: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_CONTROL;
                reg_wdata <= CONTROL_BASE | CONTROL_CODEC_CFG;
                state     <= ST_WAIT_CODEC0_REQ;
            end
            ST_WAIT_CODEC0_REQ: begin
                reg_rd_en <= 1'b1;
                reg_addr  <= REG_STATUS;
                state     <= ST_WAIT_CODEC0_CAPTURE;
            end
            ST_WAIT_CODEC0_CAPTURE: begin
                status_value <= reg_rdata;
                if (!codec_busy_seen) begin
                    if ((reg_rdata & STATUS_CODEC_BUSY) != 32'd0) begin
                        codec_busy_seen <= 1'b1;
                    end
                    state <= ST_WAIT_CODEC0_REQ;
                end else if ((reg_rdata & STATUS_CODEC_BUSY) == 32'd0) begin
                    state <= ST_WRITE_CODEC1_WORD;
                end else begin
                    state <= ST_WAIT_CODEC0_REQ;
                end
            end
            ST_WRITE_CODEC1_WORD: begin
                codec_busy_seen <= 1'b0;
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_CODEC_CFG;
                reg_wdata <= DEFAULT_CFG_1;
                state     <= ST_PULSE_CODEC1;
            end
            ST_PULSE_CODEC1: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_CONTROL;
                reg_wdata <= CONTROL_BASE | CONTROL_CODEC_CFG;
                state     <= ST_WAIT_CODEC1_REQ;
            end
            ST_WAIT_CODEC1_REQ: begin
                reg_rd_en <= 1'b1;
                reg_addr  <= REG_STATUS;
                state     <= ST_WAIT_CODEC1_CAPTURE;
            end
            ST_WAIT_CODEC1_CAPTURE: begin
                status_value <= reg_rdata;
                if (!codec_busy_seen) begin
                    if ((reg_rdata & STATUS_CODEC_BUSY) != 32'd0) begin
                        codec_busy_seen <= 1'b1;
                    end
                    state <= ST_WAIT_CODEC1_REQ;
                end else if ((reg_rdata & STATUS_CODEC_BUSY) == 32'd0) begin
                    codec_write_exercised <= 1'b1;
                    state                 <= ST_TRIGGER_NOTE;
                end else begin
                    state <= ST_WAIT_CODEC1_REQ;
                end
            end
            ST_TRIGGER_NOTE: begin
                reg_wr_en <= 1'b1;
                reg_addr  <= REG_CONTROL;
                reg_wdata <= CONTROL_BASE | CONTROL_TRIGGER;
                state     <= ST_SEND_RUNTIME_START;
            end
            ST_SEND_RUNTIME_START: begin
                if (!frame_active) begin
                    frame_active <= 1'b1;
                    frame_index  <= 4'd0;
                    frame_tag    <= 8'h52;
                    frame_value  <= status_value;
                    state        <= ST_SEND_RUNTIME_WAIT;
                end
            end
            ST_SEND_RUNTIME_WAIT: begin
                if (!frame_active) begin
                    wait_count <= 32'd0;
                    state      <= ST_PERIODIC_WAIT;
                end
            end
            ST_PERIODIC_WAIT: begin
                if (wait_count < REPORT_INTERVAL - 1'b1) begin
                    wait_count <= wait_count + 1'b1;
                end else begin
                    wait_count <= 32'd0;
                    state      <= ST_PERIODIC_STATUS_REQ;
                end
            end
            ST_PERIODIC_STATUS_REQ: begin
                reg_rd_en <= 1'b1;
                reg_addr  <= REG_STATUS;
                state     <= ST_PERIODIC_STATUS_CAPTURE;
            end
            ST_PERIODIC_STATUS_CAPTURE: begin
                status_value <= reg_rdata;
                state        <= ST_SEND_RUNTIME_START;
            end
            ST_PERIODIC_TRIGGER: begin
                state     <= ST_SEND_RUNTIME_START;
            end
            default: begin
                state <= ST_RESET_WAIT;
            end
        endcase
    end
end

endmodule
