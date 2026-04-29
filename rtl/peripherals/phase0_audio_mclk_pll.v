`timescale 1 ps / 1 ps

module phase0_audio_mclk_pll (
    input  wire areset,
    input  wire inclk0,
    output wire c0,
    output wire locked
);

wire [5:0] pll_clk_bus;
wire [0:0] sub_wire0 = 1'b0;
wire [0:0] sub_wire1 = 1'b1;
wire [5:0] pll_clkena_bus = {
    sub_wire0,
    sub_wire0,
    sub_wire0,
    sub_wire0,
    sub_wire0,
    sub_wire1
};
wire [3:0] pll_extclkena_bus = {
    sub_wire0,
    sub_wire0,
    sub_wire0,
    sub_wire0
};
wire [1:0] pll_inclk_bus = {sub_wire0, inclk0};

assign c0 = pll_clk_bus[0];

altpll altpll_component (
    .clkena    (pll_clkena_bus),
    .inclk     (pll_inclk_bus),
    .extclkena (pll_extclkena_bus),
    .areset    (areset),
    .clk       (pll_clk_bus),
    .locked    (locked)
    // synopsys translate_off
    ,
    .scanclk      (),
    .pllena       (),
    .sclkout1     (),
    .sclkout0     (),
    .fbin         (),
    .scandone     (),
    .clkloss      (),
    .extclk       (),
    .clkswitch    (),
    .pfdena       (),
    .scanaclr     (),
    .clkbad       (),
    .scandata     (),
    .enable1      (),
    .scandataout  (),
    .enable0      (),
    .scanwrite    (),
    .activeclock  (),
    .scanread     (),
    .phasecounterselect(),
    .phaseupdown  (),
    .phasestep    (),
    .configupdate (),
    .scanclkena   (),
    .fbmimicbidir (),
    .phasedone    (),
    .vcooverrange (),
    .vcounderrange(),
    .fbout        (),
    .fref         (),
    .icdrclk      ()
    // synopsys translate_on
);
defparam
    altpll_component.bandwidth_type = "AUTO",
    altpll_component.clk0_divide_by = 100,
    altpll_component.clk0_duty_cycle = 50,
    altpll_component.clk0_multiply_by = 24,
    altpll_component.clk0_phase_shift = "0",
    altpll_component.compensate_clock = "CLK0",
    altpll_component.inclk0_input_frequency = 20000,
    altpll_component.intended_device_family = "Cyclone IV E",
    altpll_component.lpm_type = "altpll",
    altpll_component.operation_mode = "NORMAL",
    altpll_component.pll_type = "AUTO";

endmodule
