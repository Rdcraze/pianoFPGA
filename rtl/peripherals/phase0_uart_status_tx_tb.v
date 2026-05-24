`timescale 1ns / 1ps

// Phase 5 M2 focused testbench for phase0_uart_status_tx.
//
// Exercises reset, runs the cadence FSM for two frames using a small
// CADENCE_CYCLES override to keep simulation fast, decodes the
// bit-banged uart_tx output at 115200 8N1, and checks that two CRLF-
// terminated 62-byte P5M2 frames appear with monotonic BOOT counters,
// expected Q (command_count) and X ({last_error, error_count}) fields.

module phase0_uart_status_tx_tb;

localparam integer CLK_FREQ_HZ    = 50_000_000;
localparam integer BAUD_RATE      = 115_200;
// Cadence ~32 ms (1.6M cycles at 50 MHz). The frame at 115200 baud is
// ~5.4 ms (62 bytes x 87 us), so cadence > frame length; no skip.
localparam integer CADENCE_CYCLES = 1_600_000;
localparam integer FRAME_LEN      = 62;

reg sys_clk;
reg sys_rst_n;
reg sample_tick;
reg [1:0] voice_index;
reg [31:0] command_count;
reg [15:0] error_count;
reg [15:0] last_error;
wire uart_tx;

phase0_uart_status_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE),
    .CADENCE_CYCLES(CADENCE_CYCLES)
) dut (
    .sys_clk      (sys_clk),
    .sys_rst_n    (sys_rst_n),
    .sample_tick  (sample_tick),
    .voice_index  (voice_index),
    .command_count(command_count),
    .error_count  (error_count),
    .last_error   (last_error),
    .uart_tx      (uart_tx)
);

// 50 MHz clock => 20 ns period
always #10 sys_clk = ~sys_clk;

// Generate a periodic sample_tick at ~46.875 kHz (every ~1066 sys_clk).
reg [10:0] tick_div;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tick_div    <= 11'd0;
        sample_tick <= 1'b0;
    end else begin
        sample_tick <= 1'b0;
        if (tick_div == 11'd1065) begin
            tick_div <= 11'd0;
            sample_tick <= 1'b1;
        end else begin
            tick_div <= tick_div + 1'b1;
        end
    end
end

// Cycle voice_index every few ticks so we exercise different VC bytes.
reg [3:0] vi_div;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        voice_index <= 2'd0;
        vi_div      <= 4'd0;
    end else if (sample_tick) begin
        if (vi_div == 4'd15) begin
            vi_div      <= 4'd0;
            voice_index <= voice_index + 2'd1;
        end else begin
            vi_div <= vi_div + 1'b1;
        end
    end
end

// UART decoder: sample uart_tx mid-bit at 115200 baud and decode bytes.
localparam integer BAUD_DIV      = (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
localparam integer BAUD_DIV_HALF = BAUD_DIV / 2;

integer rx_bit_count;
integer rx_baud_count;
reg     rx_active;
reg [7:0] rx_shift;
reg [7:0] rx_byte;
reg       rx_byte_valid;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rx_bit_count  <= 0;
        rx_baud_count <= 0;
        rx_active     <= 1'b0;
        rx_shift      <= 8'd0;
        rx_byte       <= 8'd0;
        rx_byte_valid <= 1'b0;
    end else begin
        rx_byte_valid <= 1'b0;

        if (!rx_active) begin
            if (uart_tx == 1'b0) begin
                // Start bit detected
                rx_active     <= 1'b1;
                rx_baud_count <= BAUD_DIV_HALF + BAUD_DIV;
                rx_bit_count  <= 0;
            end
        end else begin
            if (rx_baud_count != 0) begin
                rx_baud_count <= rx_baud_count - 1;
            end else begin
                if (rx_bit_count < 8) begin
                    rx_shift <= {uart_tx, rx_shift[7:1]};
                    rx_bit_count <= rx_bit_count + 1;
                    rx_baud_count <= BAUD_DIV;
                end else begin
                    rx_byte       <= rx_shift;
                    rx_byte_valid <= 1'b1;
                    rx_active     <= 1'b0;
                end
            end
        end
    end
end

// Frame collector: 2 frames x 62 bytes = 124 bytes
localparam integer COLLECT_LEN = 2 * FRAME_LEN;
integer collected_count;
reg [7:0] frame [0:COLLECT_LEN-1];
integer frame_idx;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        collected_count <= 0;
        frame_idx       <= 0;
    end else if (rx_byte_valid) begin
        if (frame_idx < COLLECT_LEN) begin
            frame[frame_idx] <= rx_byte;
            frame_idx <= frame_idx + 1;
        end
        collected_count <= collected_count + 1;
    end
end

// Test driver
initial begin
    sys_clk       = 1'b0;
    sys_rst_n     = 1'b0;
    command_count = 32'h12345678;
    error_count   = 16'h0007;
    last_error    = 16'h0003;
    #200;
    sys_rst_n     = 1'b1;
end

integer i;
integer fails;
initial begin
    fails = 0;
    // Two cadences = 64 ms, plus frame drain time. Use 100 ms.
    #100_000_000;

    if (collected_count < COLLECT_LEN) begin
        $display("UART_TX_TB_FAIL collected_count=%0d expected_at_least=%0d",
                 collected_count, COLLECT_LEN);
        fails = fails + 1;
    end

    // Frame 0: P5M2 tag
    if (frame[0]  !== "P" || frame[1] !== "5" || frame[2] !== "M" ||
        frame[3] !== "2" || frame[4] !== " ") begin
        $display("UART_TX_TB_FAIL frame0_tag bytes=%c%c%c%c%c",
                 frame[0], frame[1], frame[2], frame[3], frame[4]);
        fails = fails + 1;
    end
    // BOOT field
    if (frame[5] !== "B" || frame[9] !== "=" || frame[18] !== " ") begin
        $display("UART_TX_TB_FAIL frame0_boot field");
        fails = fails + 1;
    end
    // TICK field
    if (frame[19] !== "T" || frame[23] !== "=" || frame[32] !== " ") begin
        $display("UART_TX_TB_FAIL frame0_tick field");
        fails = fails + 1;
    end
    // VC field
    if (frame[33] !== "V" || frame[34] !== "C" || frame[35] !== "=" ||
        frame[38] !== " ") begin
        $display("UART_TX_TB_FAIL frame0_vc field");
        fails = fails + 1;
    end
    // Q field at index 39
    if (frame[39] !== "Q" || frame[40] !== "=" || frame[49] !== " ") begin
        $display("UART_TX_TB_FAIL frame0_q field bytes=%c%c%c%c..%c",
                 frame[39], frame[40], frame[41], frame[42], frame[49]);
        fails = fails + 1;
    end
    // X field at index 50
    if (frame[50] !== "X" || frame[51] !== "=") begin
        $display("UART_TX_TB_FAIL frame0_x field bytes=%c%c",
                 frame[50], frame[51]);
        fails = fails + 1;
    end
    // CRLF at indices 60, 61
    if (frame[60] !== 8'h0D || frame[61] !== 8'h0A) begin
        $display("UART_TX_TB_FAIL frame0_crlf %02h %02h",
                 frame[60], frame[61]);
        fails = fails + 1;
    end

    // Frame 1: same structure offset by 62
    if (frame[62] !== "P" || frame[63] !== "5" || frame[64] !== "M" ||
        frame[65] !== "2") begin
        $display("UART_TX_TB_FAIL frame1_tag");
        fails = fails + 1;
    end
    if (frame[122] !== 8'h0D || frame[123] !== 8'h0A) begin
        $display("UART_TX_TB_FAIL frame1_crlf %02h %02h",
                 frame[122], frame[123]);
        fails = fails + 1;
    end

    // BOOT counter monotonic: parse hex digits 10..17 from each frame
    begin : check_boot
        integer boot0;
        integer boot1;
        integer h;
        boot0 = 0;
        boot1 = 0;
        for (i = 0; i < 8; i = i + 1) begin
            h = frame[10 + i];
            if (h >= "0" && h <= "9")      h = h - "0";
            else if (h >= "A" && h <= "F") h = h - "A" + 10;
            else                           h = -1;
            if (h < 0) begin
                $display("UART_TX_TB_FAIL frame0_boot_hex_byte i=%0d val=%0d",
                         i, frame[10+i]);
                fails = fails + 1;
            end else begin
                boot0 = (boot0 << 4) | h;
            end
        end
        for (i = 0; i < 8; i = i + 1) begin
            h = frame[72 + i];
            if (h >= "0" && h <= "9")      h = h - "0";
            else if (h >= "A" && h <= "F") h = h - "A" + 10;
            else                           h = -1;
            if (h < 0) begin
                $display("UART_TX_TB_FAIL frame1_boot_hex_byte i=%0d val=%0d",
                         i, frame[72+i]);
                fails = fails + 1;
            end else begin
                boot1 = (boot1 << 4) | h;
            end
        end
        if (boot1 != boot0 + 1) begin
            $display("UART_TX_TB_FAIL boot_monotonic boot0=%08x boot1=%08x",
                     boot0, boot1);
            fails = fails + 1;
        end
        $display("UART_TX_TB_INFO boot0=%08x boot1=%08x", boot0, boot1);
    end

    // Q field decode for frame 0: should be 12345678
    begin : check_q
        integer q0;
        integer h;
        q0 = 0;
        for (i = 0; i < 8; i = i + 1) begin
            h = frame[41 + i];
            if (h >= "0" && h <= "9")      h = h - "0";
            else if (h >= "A" && h <= "F") h = h - "A" + 10;
            else                           h = -1;
            if (h < 0) begin
                $display("UART_TX_TB_FAIL frame0_q_hex_byte i=%0d val=%0d",
                         i, frame[41+i]);
                fails = fails + 1;
            end else begin
                q0 = (q0 << 4) | h;
            end
        end
        if (q0 !== 32'h12345678) begin
            $display("UART_TX_TB_FAIL q_value got=%08x expected=12345678", q0);
            fails = fails + 1;
        end
        $display("UART_TX_TB_INFO q0=%08x", q0);
    end

    // X field decode for frame 0: {last_error, error_count} = 0003_0007
    begin : check_x
        integer x0;
        integer h;
        x0 = 0;
        for (i = 0; i < 8; i = i + 1) begin
            h = frame[52 + i];
            if (h >= "0" && h <= "9")      h = h - "0";
            else if (h >= "A" && h <= "F") h = h - "A" + 10;
            else                           h = -1;
            if (h < 0) begin
                $display("UART_TX_TB_FAIL frame0_x_hex_byte i=%0d val=%0d",
                         i, frame[52+i]);
                fails = fails + 1;
            end else begin
                x0 = (x0 << 4) | h;
            end
        end
        if (x0 !== 32'h00030007) begin
            $display("UART_TX_TB_FAIL x_value got=%08x expected=00030007", x0);
            fails = fails + 1;
        end
        $display("UART_TX_TB_INFO x0=%08x", x0);
    end

    if (fails == 0) begin
        $display("UART_TX_TB_PASS frames=%0d collected_count=%0d",
                 2, collected_count);
    end else begin
        $display("UART_TX_TB_FAIL fails=%0d", fails);
    end
    $finish;
end

endmodule
