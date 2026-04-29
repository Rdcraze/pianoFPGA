# Phase 0 RV32I Control-Plane Validation

Date: `2026-04-23`

## Findings

### No new functional verifier findings: the live board now boots through the real RV32I firmware-owned control path and preserves the existing Phase 0 hardware baseline

The new Phase 0 image is no longer behaving like the earlier deterministic stub family on hardware.

Rebuilt firmware/package evidence:

- firmware artifacts were regenerated at `2026-04-23 22:50:58`:
  - [phase0.elf](</E:/projects/piano-agents/fw/phase0/build/phase0.elf>)
  - [phase0.bin](</E:/projects/piano-agents/fw/phase0/build/phase0.bin>)
  - [phase0.mif](</E:/projects/piano-agents/fw/phase0/build/phase0.mif>)
  - [phase0_fw.mif](</E:/projects/piano-agents/phase0_fw.mif>)
  - [quartus/phase0/phase0_fw.mif](</E:/projects/piano-agents/quartus/phase0/phase0_fw.mif>)
- packaged FPGA image timestamp:
  - [piano_phase0_top.sof](</E:/projects/piano-agents/quartus/phase0/output_files/piano_phase0_top.sof>) at `2026-04-23 22:51:48`

Source integration evidence:

- [piano_phase0_top.v](</E:/projects/piano-agents/rtl/top/piano_phase0_top.v>) now instantiates [phase0_rv32i_soc.v](</E:/projects/piano-agents/rtl/control/phase0_rv32i_soc.v>) instead of the old stub in the live top-level path
- [phase0_rv32i_soc.v](</E:/projects/piano-agents/rtl/control/phase0_rv32i_soc.v>) drives the documented ROM/RAM/MMIO contract:
  - ROM `0x0000_0000`
  - RAM `0x0001_0000`
  - control block `0x4000_0000`
  - UART aperture `0x4000_1000`

Tool-backed pre-hardware confirmation on this host:

- ModelSim compile passed with `0` errors and `0` warnings
- happy-path sim passed:
  - `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`

Live hardware confirmation:

- JTAG programming succeeded on `USB-Blaster [USB-0]`
- Quartus Programmer used checksum `0x00405562`
- UART remained observable on `COM4` at `115200 8N1`
- fresh UART artifact: [phase0_rv32i_control_plane_uart.txt](</E:/projects/piano-agents/reports/phase0_rv32i_control_plane_uart.txt>)
- captured frames:
  - `I=50303031`
  - `S=8019073F`
  - recurring `R=8019077F`

That runtime signature materially differs from the old stub-family hardware frames:

- old stub-family recurring runtime frame: `R=8019035A`
- new RV32I hardware recurring runtime frame: `R=8019077F`

The new boot/runtime transition is also coherent with firmware-owned control activity:

- `S=8019073F` appears before the CPU-owned codec-write witness bit is reflected in the low status byte
- recurring `R=8019077F` then shows the later steady state after firmware-driven codec MMIO activity has occurred

Continuous default-tone behavior also survived the control-plane replacement:

- fresh analog artifact: [phase0_rv32i_control_plane_capture.wav](</E:/projects/piano-agents/reports/phase0_rv32i_control_plane_capture.wav>)
- dominant tone: `440.001772 Hz`
- intended nominal tone: `439.999625 Hz`
- error versus target: `+0.002147 Hz`
- harmonic structure remains square-wave-like rather than burst-like:
  - `H2`: `-42.89 dB`
  - `H3`: `-8.49 dB`
  - `H5`: `-12.78 dB`
  - `H7`: `-15.72 dB`
- envelope stability remains consistent with a continuous baseline tone:
  - `20 ms` RMS-window coefficient of variation: `0.221%`

Both recorded channels contain the same intended tone:

- left channel dominant tone: `440.001771 Hz`
- right channel dominant tone: `440.001771 Hz`

## Exact Actions And Results

1. Confirmed the new firmware/MIF collateral:
   - [phase0_fw.mif](</E:/projects/piano-agents/phase0_fw.mif>)
   - [quartus/phase0/phase0_fw.mif](</E:/projects/piano-agents/quartus/phase0/phase0_fw.mif>)
2. Confirmed the live top-level now routes through:
   - [phase0_rv32i_soc.v](</E:/projects/piano-agents/rtl/control/phase0_rv32i_soc.v>)
3. Recompiled and reran the current ModelSim happy-path testbench:
   - compile: passed with `0` errors and `0` warnings
   - sim: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
4. Re-enumerated the live hardware:
   - `USB-Blaster [USB-0]`
   - `USB-SERIAL CH340 (COM4)`
5. Reprogrammed the board with the current packaged image:
   - checksum `0x00405562`
   - configuration succeeded
6. Captured the post-config UART output:
   - [phase0_rv32i_control_plane_uart.txt](</E:/projects/piano-agents/reports/phase0_rv32i_control_plane_uart.txt>)
7. Recorded and analyzed a fresh analog capture from the external Realtek input path:
   - [phase0_rv32i_control_plane_capture.wav](</E:/projects/piano-agents/reports/phase0_rv32i_control_plane_capture.wav>)

## Interpretation

The current hardware evidence supports the intended conclusion:

- the board is no longer running the old deterministic top-level stub path
- the programmed image matches the integrated RV32I tree and fresh ROM-init collateral
- live UART behavior matches the new RV32I-backed simulation/status family
- firmware-owned MMIO activity is reflected in the changed status signature
- WM8978 init, CPU-owned codec writes, and the continuous default-tone baseline all still behave correctly on hardware

## Residual Limitations

- This pass validates functional behavior, not final timing sign-off.
- The known packaged compile limitation remains:
  - slow-`85C` `sys_clk_50m` setup slack is still negative (`-0.881 ns`) in the integrated RV32I build, per [phase0_rv32i_control_plane_report.md](</E:/projects/piano-agents/reports/phase0_rv32i_control_plane_report.md>)
- Board-level I/O delays for `WM8978` and `UART1` remain intentionally unconstrained in the current Quartus package.

Bottom line: the minimal RV32I control-plane replacement is functionally validated on the live board. It preserves clean programming, healthy UART observability, successful codec init/MMIO behavior, and the continuous `~440 Hz` default-tone baseline, while the main remaining risk stays where the implementation report already put it: timing closure, not functional bring-up behavior.
