`timescale 1ns / 1ps

module wm8978_i2c_model #(
    parameter [6:0] DEVICE_ADDR = 7'b0011_010,
    parameter integer MAX_WRITES = 32,
    parameter integer NACK_ENABLE = 0,
    parameter [7:0] NACK_CFG_HIGH_BYTE = 8'hFF
) (
    input  wire       sys_rst_n,
    input  wire       i2c_scl,
    inout  wire       i2c_sda,
    output reg  [7:0] write_count,
    output reg  [7:0] malformed_count,
    output reg  [7:0] nack_count,
    output reg  [7:0] stop_count,
    output reg [15:0] last_write_word,
    output reg  [7:0] last_rx_byte,
    output reg  [1:0] last_rx_byte_index,
    output reg  [3:0] last_error_reason
);

reg        sda_drive_low;
reg        in_transaction;
reg        ignore_until_stop;
reg        ack_pending;
reg        ack_active;
reg        ack_low;
reg        store_write_after_ack;
reg  [2:0] bit_count;
reg  [1:0] byte_index;
reg  [7:0] shift_reg;
reg  [7:0] pending_byte;
reg  [7:0] current_high_byte;
reg [15:0] pending_write_word;
reg [15:0] captured_words [0:MAX_WRITES-1];
integer    idx;

assign i2c_sda = sda_drive_low ? 1'b0 : 1'bz;

initial begin
    sda_drive_low       = 1'b0;
    in_transaction      = 1'b0;
    ignore_until_stop   = 1'b0;
    ack_pending         = 1'b0;
    ack_active          = 1'b0;
    ack_low             = 1'b0;
    store_write_after_ack = 1'b0;
    bit_count           = 3'd0;
    byte_index          = 2'd0;
    shift_reg           = 8'd0;
    pending_byte        = 8'd0;
    current_high_byte   = 8'd0;
    pending_write_word  = 16'd0;
    write_count         = 8'd0;
    malformed_count     = 8'd0;
    nack_count          = 8'd0;
    stop_count          = 8'd0;
    last_write_word     = 16'd0;
    last_rx_byte        = 8'd0;
    last_rx_byte_index  = 2'd0;
    last_error_reason   = 4'd0;

    for (idx = 0; idx < MAX_WRITES; idx = idx + 1) begin
        captured_words[idx] = 16'd0;
    end
end

always @(negedge sys_rst_n) begin
    sda_drive_low       = 1'b0;
    in_transaction      = 1'b0;
    ignore_until_stop   = 1'b0;
    ack_pending         = 1'b0;
    ack_active          = 1'b0;
    ack_low             = 1'b0;
    store_write_after_ack = 1'b0;
    bit_count           = 3'd0;
    byte_index          = 2'd0;
    shift_reg           = 8'd0;
    pending_byte        = 8'd0;
    current_high_byte   = 8'd0;
    pending_write_word  = 16'd0;
    write_count         = 8'd0;
    malformed_count     = 8'd0;
    nack_count          = 8'd0;
    stop_count          = 8'd0;
    last_write_word     = 16'd0;
    last_rx_byte        = 8'd0;
    last_rx_byte_index  = 2'd0;
    last_error_reason   = 4'd0;

    for (idx = 0; idx < MAX_WRITES; idx = idx + 1) begin
        captured_words[idx] = 16'd0;
    end
end

always @(negedge i2c_sda) begin
    if ((sys_rst_n === 1'b1) && !in_transaction &&
        (i2c_scl === 1'b1) && !sda_drive_low) begin
        in_transaction      = 1'b1;
        ignore_until_stop   = 1'b0;
        ack_pending         = 1'b0;
        ack_active          = 1'b0;
        ack_low             = 1'b0;
        store_write_after_ack = 1'b0;
        bit_count           = 3'd0;
        byte_index          = 2'd0;
        shift_reg           = 8'd0;
        pending_byte        = 8'd0;
        current_high_byte   = 8'd0;
        pending_write_word  = 16'd0;
        sda_drive_low       = 1'b0;
    end
end

always @(posedge i2c_sda) begin
    if ((sys_rst_n === 1'b1) && in_transaction &&
        (i2c_scl === 1'b1) && !sda_drive_low &&
        (ignore_until_stop || (byte_index == 2'd3))) begin
        stop_count = stop_count + 1'b1;

        in_transaction      = 1'b0;
        ignore_until_stop   = 1'b0;
        ack_pending         = 1'b0;
        ack_active          = 1'b0;
        ack_low             = 1'b0;
        store_write_after_ack = 1'b0;
        bit_count           = 3'd0;
        byte_index          = 2'd0;
        shift_reg           = 8'd0;
        pending_byte        = 8'd0;
        current_high_byte   = 8'd0;
        pending_write_word  = 16'd0;
        sda_drive_low       = 1'b0;
    end
end

always @(posedge i2c_scl) begin
    if ((sys_rst_n === 1'b1) && in_transaction &&
        !ack_pending && !ack_active && !ignore_until_stop) begin
        if (bit_count == 3'd7) begin
            pending_byte = {shift_reg[6:0], i2c_sda};
            last_rx_byte = {shift_reg[6:0], i2c_sda};
            last_rx_byte_index = byte_index;
            ack_pending  = 1'b1;
            bit_count    = 3'd0;
            shift_reg    = 8'd0;
        end else begin
            shift_reg = {shift_reg[6:0], i2c_sda};
            bit_count = bit_count + 1'b1;
        end
    end
end

always @(negedge i2c_scl) begin
    if ((sys_rst_n === 1'b1) && in_transaction) begin
        if (ack_pending) begin
            ack_low = 1'b0;
            store_write_after_ack = 1'b0;

            case (byte_index)
                2'd0: begin
                    if ((pending_byte[7:1] == DEVICE_ADDR) && (pending_byte[0] == 1'b0)) begin
                        ack_low = 1'b1;
                    end else begin
                        malformed_count = malformed_count + 1'b1;
                        last_error_reason = 4'd1;
                        ignore_until_stop = 1'b1;
                    end
                end
                2'd1: begin
                    current_high_byte = pending_byte;
                    ack_low = 1'b1;
                end
                2'd2: begin
                    ack_low = 1'b1;
                    pending_write_word = {current_high_byte, pending_byte};
                    store_write_after_ack = 1'b1;

                    if ((NACK_ENABLE != 0) && (current_high_byte == NACK_CFG_HIGH_BYTE)) begin
                        ack_low = 1'b0;
                        store_write_after_ack = 1'b0;
                        last_error_reason = 4'd3;
                        ignore_until_stop = 1'b1;
                    end
                end
                default: begin
                    malformed_count = malformed_count + 1'b1;
                    last_error_reason = 4'd2;
                    ignore_until_stop = 1'b1;
                end
            endcase

            sda_drive_low = ack_low;
            ack_active    = 1'b1;
            ack_pending   = 1'b0;
        end else if (ack_active) begin
            sda_drive_low = 1'b0;
            ack_active    = 1'b0;

            if (ack_low && !ignore_until_stop) begin
                if (store_write_after_ack) begin
                    if (write_count < MAX_WRITES) begin
                        captured_words[write_count] = pending_write_word;
                    end
                    write_count     = write_count + 1'b1;
                    last_write_word = pending_write_word;
                end

                byte_index = byte_index + 1'b1;
            end else begin
                nack_count = nack_count + 1'b1;
            end

            ack_low = 1'b0;
            store_write_after_ack = 1'b0;
        end
    end
end

endmodule
