`timescale 1ns / 1ps

// Phase 5 M2 focused testbench for phase0_uart_command.
//
// Drives serial bytes into uart_rx_pin at 115200 8N1 (no bypass of the
// UART RX primitive) and verifies that:
//   - "!N\r\n" produces note_strobe with cmd_loop_len=106, cmd_velocity=0x7FFF
//   - "!N006A4000\r\n" produces note_strobe with loop_len=106, velocity=0x4000
//   - "!N006A7FFF\r\n" produces note_strobe with loop_len=106, velocity=0x7FFF
//   - "!F\r\n" produces release_strobe (no note_strobe)
//   - "!Z\r\n" yields error UNKNOWN_OPCODE (2)
//   - 18-byte malformed line yields error OVERLONG (3)
//   - command_count, error_count, last_error update as expected
//
// Speeds simulation by using a small CLK_FREQ_HZ override so each bit
// takes only ~10 sys_clk cycles.

module phase0_uart_command_tb;

// Use a much smaller CLK_FREQ_HZ so the BAUD_DIV inside uart_rx
// shrinks to a manageable count for sim wall time. CLK = 1.152 MHz,
// BAUD = 115200 -> BAUD_DIV = 10. Each bit lasts 10 sys_clk cycles.
localparam integer CLK_FREQ_HZ = 1_152_000;
localparam integer BAUD_RATE   = 115_200;
localparam integer BIT_CYCLES  = CLK_FREQ_HZ / BAUD_RATE;
// At 1.152 MHz a 20 ns half-period would be wrong. Use 868 ns period
// per cycle (~1.152 MHz). Half period = 434 ns.
localparam time HALF_PERIOD = 434;

reg sys_clk;
reg sys_rst_n;
reg uart_rx_pin;

wire        note_strobe;
wire        release_strobe;
wire [6:0]  cmd_loop_len;
wire [15:0] cmd_velocity;
wire [31:0] command_count;
wire [15:0] error_count;
wire [15:0] last_error;

phase0_uart_command #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) dut (
    .sys_clk        (sys_clk),
    .sys_rst_n      (sys_rst_n),
    .uart_rx_pin    (uart_rx_pin),
    .note_strobe    (note_strobe),
    .release_strobe (release_strobe),
    .cmd_loop_len   (cmd_loop_len),
    .cmd_velocity   (cmd_velocity),
    .command_count  (command_count),
    .error_count    (error_count),
    .last_error     (last_error)
);

initial sys_clk = 0;
always #(HALF_PERIOD) sys_clk = ~sys_clk;

// Counters maintained by the TB to verify strobe pulses
integer notes_seen;
integer releases_seen;
reg [6:0]  last_loop_len;
reg [15:0] last_velocity;

always @(posedge sys_clk) begin
    if (sys_rst_n) begin
        if (note_strobe) begin
            notes_seen     <= notes_seen + 1;
            last_loop_len  <= cmd_loop_len;
            last_velocity  <= cmd_velocity;
        end
        if (release_strobe) begin
            releases_seen <= releases_seen + 1;
        end
    end
end

// --- Serial byte injector -------------------------------------------------

task send_byte;
    input [7:0] data;
    integer bi;
    begin
        // Start bit
        uart_rx_pin = 1'b0;
        repeat (BIT_CYCLES) @(posedge sys_clk);
        // 8 data bits, LSB first
        for (bi = 0; bi < 8; bi = bi + 1) begin
            uart_rx_pin = data[bi];
            repeat (BIT_CYCLES) @(posedge sys_clk);
        end
        // Stop bit
        uart_rx_pin = 1'b1;
        repeat (BIT_CYCLES) @(posedge sys_clk);
        // Tiny idle gap
        repeat (4) @(posedge sys_clk);
    end
endtask

task send_string;
    input [8*32-1:0] data;
    input integer len;
    integer i;
    begin
        for (i = 0; i < len; i = i + 1) begin
            send_byte(data[(len-1-i)*8 +: 8]);
        end
    end
endtask

task send_crlf;
    begin
        send_byte(8'h0D);
        send_byte(8'h0A);
    end
endtask

// --- Expectations ---------------------------------------------------------

integer fails;

task expect_eq32;
    input [255:0] tag;
    input [31:0] got;
    input [31:0] want;
    begin
        if (got !== want) begin
            $display("UART_CMD_TB_FAIL %0s got=%08x want=%08x", tag, got, want);
            fails = fails + 1;
        end
    end
endtask

task expect_eq16;
    input [255:0] tag;
    input [15:0] got;
    input [15:0] want;
    begin
        if (got !== want) begin
            $display("UART_CMD_TB_FAIL %0s got=%04x want=%04x", tag, got, want);
            fails = fails + 1;
        end
    end
endtask

// --- Test driver ----------------------------------------------------------

initial begin
    fails         = 0;
    sys_rst_n     = 1'b0;
    uart_rx_pin   = 1'b1; // idle high
    notes_seen    = 0;
    releases_seen = 0;
    last_loop_len = 7'd0;
    last_velocity = 16'd0;

    repeat (16) @(posedge sys_clk);
    sys_rst_n = 1'b1;
    repeat (16) @(posedge sys_clk);

    // 1. Bare !N\r\n => note_strobe, loop_len=106, velocity=0x7FFF
    send_byte("!");
    send_byte("N");
    send_crlf();
    repeat (32) @(posedge sys_clk);
    expect_eq32("note_count_after_1", command_count, 32'd1);
    expect_eq32("error_count_after_1", {16'd0, error_count}, 32'd0);
    if (notes_seen !== 1) begin
        $display("UART_CMD_TB_FAIL notes_seen_after_1 got=%0d want=1",
                 notes_seen);
        fails = fails + 1;
    end
    expect_eq16("last_loop_len_after_1",
                {9'd0, last_loop_len}, 16'd106);
    expect_eq16("last_velocity_after_1", last_velocity, 16'h7FFF);

    // 2. !N006A4000\r\n => note_strobe, loop_len=0x6A=106, velocity=0x4000
    send_byte("!"); send_byte("N");
    send_byte("0"); send_byte("0"); send_byte("6"); send_byte("A");
    send_byte("4"); send_byte("0"); send_byte("0"); send_byte("0");
    send_crlf();
    repeat (32) @(posedge sys_clk);
    expect_eq32("note_count_after_2", command_count, 32'd2);
    if (notes_seen !== 2) begin
        $display("UART_CMD_TB_FAIL notes_seen_after_2 got=%0d want=2",
                 notes_seen);
        fails = fails + 1;
    end
    expect_eq16("loop_len_after_2",
                {9'd0, last_loop_len}, 16'd106);
    expect_eq16("velocity_after_2", last_velocity, 16'h4000);

    // 3. !N006A7FFF\r\n => note_strobe, loop_len=106, velocity=0x7FFF
    send_byte("!"); send_byte("N");
    send_byte("0"); send_byte("0"); send_byte("6"); send_byte("A");
    send_byte("7"); send_byte("F"); send_byte("F"); send_byte("F");
    send_crlf();
    repeat (32) @(posedge sys_clk);
    expect_eq32("note_count_after_3", command_count, 32'd3);
    expect_eq16("velocity_after_3", last_velocity, 16'h7FFF);

    // 4. !F\r\n => release_strobe
    send_byte("!"); send_byte("F");
    send_crlf();
    repeat (32) @(posedge sys_clk);
    expect_eq32("command_count_after_4", command_count, 32'd4);
    if (releases_seen !== 1) begin
        $display("UART_CMD_TB_FAIL releases_seen_after_4 got=%0d want=1",
                 releases_seen);
        fails = fails + 1;
    end
    if (notes_seen !== 3) begin
        $display("UART_CMD_TB_FAIL notes_seen_after_4 got=%0d want=3",
                 notes_seen);
        fails = fails + 1;
    end

    // 5. !Z\r\n => error UNKNOWN_OPCODE = 2
    send_byte("!"); send_byte("Z");
    send_crlf();
    repeat (32) @(posedge sys_clk);
    expect_eq16("error_count_after_5", error_count, 16'd1);
    expect_eq16("last_error_after_5",  last_error,  16'd2);
    expect_eq32("command_count_after_5", command_count, 32'd4);

    // 6. Overlong: 18 bytes of "X" + CRLF -> overlong (3)
    send_byte("X"); send_byte("X"); send_byte("X"); send_byte("X");
    send_byte("X"); send_byte("X"); send_byte("X"); send_byte("X");
    send_byte("X"); send_byte("X"); send_byte("X"); send_byte("X");
    send_byte("X"); send_byte("X"); send_byte("X"); send_byte("X");
    send_byte("X"); send_byte("X");
    send_crlf();
    repeat (64) @(posedge sys_clk);
    expect_eq16("error_count_after_6", error_count, 16'd2);
    expect_eq16("last_error_after_6",  last_error,  16'd3);

    // After overlong, parser should be back to clean state and another
    // !N should still work.
    send_byte("!"); send_byte("N");
    send_crlf();
    repeat (32) @(posedge sys_clk);
    expect_eq32("command_count_after_7", command_count, 32'd5);
    if (notes_seen !== 4) begin
        $display("UART_CMD_TB_FAIL notes_seen_after_7 got=%0d want=4",
                 notes_seen);
        fails = fails + 1;
    end

    if (fails == 0) begin
        $display("UART_CMD_TB_PASS notes=%0d releases=%0d errors=%0d",
                 notes_seen, releases_seen, error_count);
    end else begin
        $display("UART_CMD_TB_FAIL fails=%0d", fails);
    end
    $finish;
end

initial begin
    #200_000_000; // 200 ms timeout
    $display("UART_CMD_TB_FAIL timeout reached");
    $finish;
end

endmodule
