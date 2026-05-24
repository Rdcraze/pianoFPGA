`timescale 1ns / 1ps

module phase0_rv32i_soc (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        uart_rx,
    input  wire [31:0] reg_rdata,
    output wire        uart_tx,
    output wire        reg_wr_en,
    output wire        reg_rd_en,
    output wire [7:0]  reg_addr,
    output wire [31:0] reg_wdata,
    output wire [15:0] status_word,
    output wire [15:0] uart_status_word
);

localparam [7:0] REG_CODEC_CFG = 8'h14;
localparam [19:0] RAM_BASE_PAGE = 20'h00010;

wire [31:0] instr_addr;
wire [31:0] instr_rdata;
wire        data_req;
wire        data_we;
wire [3:0]  data_wstrb;
wire [31:0] data_addr;
wire [31:0] data_wdata;
wire [31:0] data_rdata;
wire [31:0] ram_rdata;
wire [31:0] uart_rdata;
wire [31:0] cpu_pc;
wire        firmware_started;
wire        illegal_insn_seen;
wire        load_seen;
wire        store_seen;
wire        branch_taken_seen;

reg         ctrl_access_seen;
reg         uart_access_seen;
reg         ram_access_seen;
reg         codec_cfg_write_seen;

wire is_ram_addr  = (data_addr[31:12] == RAM_BASE_PAGE);
wire is_ctrl_addr = (data_addr[31:8]  == 24'h400000);
wire is_uart_addr = (data_addr[31:8]  == 24'h400010);

wire [3:0] ram_wstrb = (data_req && data_we && is_ram_addr) ? data_wstrb : 4'b0000;
wire uart_wr_en = data_req && data_we && is_uart_addr && (data_wstrb == 4'b1111);
wire uart_rd_en = data_req && !data_we && is_uart_addr;

assign reg_wr_en = data_req && data_we && is_ctrl_addr && (data_wstrb == 4'b1111);
assign reg_rd_en = data_req && !data_we && is_ctrl_addr;
assign reg_addr  = data_addr[7:0];
assign reg_wdata = data_wdata;

assign data_rdata = is_ram_addr ? ram_rdata :
                    is_ctrl_addr ? reg_rdata :
                    is_uart_addr ? uart_rdata :
                    32'd0;

assign status_word = {
    6'd0,
    uart_rx,
    firmware_started,
    illegal_insn_seen,
    codec_cfg_write_seen,
    ctrl_access_seen,
    uart_access_seen,
    ram_access_seen,
    branch_taken_seen,
    store_seen,
    load_seen
};

localparam BOOT_ROM_FILE = "phase0_fw.mif";

phase0_rv32i_core cpu_inst (
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .instr_addr       (instr_addr),
    .instr_rdata      (instr_rdata),
    .data_req         (data_req),
    .data_we          (data_we),
    .data_wstrb       (data_wstrb),
    .data_addr        (data_addr),
    .data_wdata       (data_wdata),
    .data_rdata       (data_rdata),
    .pc               (cpu_pc),
    .firmware_started (firmware_started),
    .illegal_insn_seen(illegal_insn_seen),
    .load_seen        (load_seen),
    .store_seen       (store_seen),
    .branch_taken_seen(branch_taken_seen)
);

phase0_boot_rom #(
    .MEM_FILE(BOOT_ROM_FILE)
) boot_rom_inst (
    .sys_clk(sys_clk),
    .addr   (instr_addr),
    .rdata  (instr_rdata)
);

phase0_data_ram data_ram_inst (
    .sys_clk(sys_clk),
    .addr   (data_addr),
    .wstrb  (ram_wstrb),
    .wdata  (data_wdata),
    .rdata  (ram_rdata)
);

phase0_uart_mmio uart_mmio_inst (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .uart_rx    (uart_rx),
    .uart_tx    (uart_tx),
    .wr_en      (uart_wr_en),
    .rd_en      (uart_rd_en),
    .addr_word  (data_addr[4:2]),
    .wdata      (data_wdata),
    .rdata      (uart_rdata),
    .status_word(uart_status_word)
);

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        ctrl_access_seen    <= 1'b0;
        uart_access_seen    <= 1'b0;
        ram_access_seen     <= 1'b0;
        codec_cfg_write_seen<= 1'b0;
    end else begin
        if (reg_wr_en || reg_rd_en) begin
            ctrl_access_seen <= 1'b1;
        end
        if (uart_wr_en || uart_rd_en) begin
            uart_access_seen <= 1'b1;
        end
        if (data_req && is_ram_addr) begin
            ram_access_seen <= 1'b1;
        end
        if (reg_wr_en && (reg_addr == REG_CODEC_CFG)) begin
            codec_cfg_write_seen <= 1'b1;
        end
    end
end

endmodule
