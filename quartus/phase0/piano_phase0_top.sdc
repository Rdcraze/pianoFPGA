create_clock -name {sys_clk_50m} -period 20.000 [get_ports {sys_clk_50m}]

# Internal WM8978 control logic derives i2c_clk from sys_clk_50m by toggling
# every 25 sys_clk cycles, for a full-period divide-by-50 relationship.
create_generated_clock -name {i2c_clk} \
    -source [get_ports {sys_clk_50m}] \
    -divide_by 50 \
    [get_registers {wm8978_codec_stub:wm8978_codec_stub_inst|wm8978_i2c_ctrl:wm8978_i2c_ctrl_inst|i2c_clk}]

# audio_mclk is now produced by a dedicated PLL at 12.000 MHz from the same
# 50 MHz board clock. Let TimeQuest derive the PLL clocks from the declared
# base clock instead of hard-coding the fitter's auto-generated PLL node names.
derive_pll_clocks

# audio_mclk is a forwarded codec clock output rather than a data interface.
# Keep the internal PLL clock model from derive_pll_clocks, but exclude the
# board pin itself from setup/hold signoff because no local board-skew or codec
# input aperture number is available for a defensible output-delay constraint.
set_false_path -to [get_ports {audio_mclk}]

# Phase 0 uses the WM8978 in codec-master mode, so audio_bclk is an external
# clock entering the FPGA after the off-chip codec boundary. The current
# explicit Phase 0 contract drives the codec with a 12.000 MHz MCLK and keeps
# the direct-MCLK path, so model audio_bclk as a 1.500 MHz timing island
# (32 * 46.875 kHz for 16-bit stereo framing). Do not time this island against
# sys_clk_50m/i2c_clk until board-level codec I/O delays are modeled explicitly.
create_clock -name {audio_bclk} -period 666.667 [get_ports {audio_bclk}]

set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk_50m i2c_clk}] \
    -group [get_clocks {audio_bclk}]

# WM8978 master-mode timing from local datasheet/manual collateral:
# - audio_lrc and audio_adcdat arrive up to 10 ns after the falling BCLK edge
# - audio_dacdat must meet 10 ns setup and 10 ns hold around the rising BCLK
# No board trace skew value is available locally, so the 0 ns min arrival on
# the codec-driven inputs is an explicit conservative assumption.
set_input_delay -clock [get_clocks {audio_bclk}] -clock_fall -max 10.000 \
    [get_ports {audio_lrc}]
set_input_delay -clock [get_clocks {audio_bclk}] -clock_fall -min 0.000 \
    -add_delay [get_ports {audio_lrc}]
set_input_delay -clock [get_clocks {audio_bclk}] -clock_fall -max 10.000 \
    [get_ports {audio_adcdat}]
set_input_delay -clock [get_clocks {audio_bclk}] -clock_fall -min 0.000 \
    -add_delay [get_ports {audio_adcdat}]
set_output_delay -clock [get_clocks {audio_bclk}] -max 10.000 \
    [get_ports {audio_dacdat}]
set_output_delay -clock [get_clocks {audio_bclk}] -min -10.000 \
    -add_delay [get_ports {audio_dacdat}]

# sys_rst_n is an asynchronous board reset into the synchronizer, not a
# synchronous setup/hold interface. UART1 is CH340-backed asynchronous serial
# debug I/O with no board clock aperture to constrain at the FPGA pins.
set_false_path -from [get_ports {sys_rst_n}]
set_false_path -from [get_ports {uart1_rx}]
set_false_path -to [get_ports {uart1_tx}]

# I2C uses open-drain 2-wire protocol timing rather than a source-synchronous
# FPGA pin interface, and local board collateral does not provide bus-capacitance
# or trace-skew values for defensible point-to-point I/O delay signoff. The
# current 250 kHz controller remains functionally within the WM8978 526 kHz
# maximum and is therefore documented as an explicit board-I/O timing exclusion.
set_false_path -from [get_ports {i2c_sda}]
set_false_path -to [get_ports {i2c_scl i2c_sda}]

# The body filter is a purely combinational chain (10 multipliers + 10 adds
# across two cascaded biquads) between register stages that only update on
# audio sample_tick. The data path from voice sample_data registers through
# the mix adder and body filter to body filter z-registers is ~44 ns at slow-
# 85C, exceeding the 20 ns sys_clk_50m period by ~2.2x. The data only changes
# on sample_tick edges (period ~1066 sys_clk cycles), so a multicycle of 3
# (60 ns) covers the path with comfortable margin.
set_multicycle_path -setup -end -from [get_registers {*phase1_reduced_voice*|sample_data[*]}] \
    -to [get_registers {*phase0_body_filter_inst|*}] 3
set_multicycle_path -hold  -end -from [get_registers {*phase1_reduced_voice*|sample_data[*]}] \
    -to [get_registers {*phase0_body_filter_inst|*}] 2

# Remove the default "no uncertainty assignment" warning for the clocks we do
# model in Phase 0.
derive_clock_uncertainty
