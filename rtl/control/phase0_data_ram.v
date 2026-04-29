`timescale 1ns / 1ps

module phase0_data_ram #(
    parameter ADDR_WIDTH = 10,
    parameter MEM_WORDS = 1024
) (
    input  wire        sys_clk,
    input  wire [31:0] addr,
    input  wire [3:0]  wstrb,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

wire [31:0] sub_wire0;
wire wren = |wstrb;
wire [ADDR_WIDTH-1:0] word_addr = addr[ADDR_WIDTH+1:2];

assign rdata = sub_wire0;

altsyncram altsyncram_component (
    .aclr0         (1'b0),
    .aclr1         (1'b0),
    .address_a     (word_addr),
    .address_b     (1'b1),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .byteena_a     (wstrb),
    .byteena_b     (1'b1),
    .clock0        (sys_clk),
    .clock1        (1'b1),
    .clocken0      (1'b1),
    .clocken1      (1'b1),
    .clocken2      (1'b1),
    .clocken3      (1'b1),
    .data_a        (wdata),
    .data_b        (1'b1),
    .eccstatus     (),
    .q_a           (sub_wire0),
    .q_b           (),
    .rden_a        (1'b1),
    .rden_b        (1'b1),
    .wren_a        (wren),
    .wren_b        (1'b0)
);
defparam
    altsyncram_component.clock_enable_input_a = "BYPASS",
    altsyncram_component.clock_enable_output_a = "BYPASS",
    altsyncram_component.intended_device_family = "Cyclone IV E",
    altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
    altsyncram_component.lpm_type = "altsyncram",
    altsyncram_component.numwords_a = MEM_WORDS,
    altsyncram_component.operation_mode = "SINGLE_PORT",
    altsyncram_component.outdata_aclr_a = "NONE",
    altsyncram_component.outdata_reg_a = "UNREGISTERED",
    altsyncram_component.power_up_uninitialized = "FALSE",
    altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    altsyncram_component.widthad_a = ADDR_WIDTH,
    altsyncram_component.width_a = 32,
    altsyncram_component.width_byteena_a = 4;

endmodule
