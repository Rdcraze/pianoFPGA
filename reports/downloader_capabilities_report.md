# Downloader Capabilities Report

Target consumer: blocked hardware bring-up task `task-58e29474`.

## Bottom line

- The EP4CE10 board does not show an on-board USB-Blaster. The programming path is an external JTAG downloader connected to the board's `2x5` JTAG header (`硬件规格书` pp. 12, 18; `原理图` p. 12).
- That JTAG path supports two distinct jobs:
  - volatile FPGA configuration with a `.sof`, which is lost on power-off (`硬件规格书` p. 18)
  - indirect programming of the on-board SPI flash for persistent boot, using a `.jic` flow in Quartus Programmer (`硬件规格书` pp. 14, 18; `开发板必读说明` PDF pp. 34-38)
- The downloader path is separate from the board's `CH340` Type-C USB-UART path. The local docs do not show UART riding over JTAG. If you want runtime text/status, you still need the board's USB-UART path or external probes (`硬件规格书` p. 23; `原理图` p. 15).

## What the downloader path can do

- Configure the FPGA over JTAG with a `.sof` for immediate bring-up. The hardware spec explicitly says the JTAG interface is the bridge for downloading the compiled `.sof` into the FPGA, and that the image disappears after power loss (`硬件规格书` p. 18).
- Indirectly program the configuration flash so the image survives power cycles. The board connects the flash to `FLASH_NCE`, `EPCS_CLK`, `EPCS_ASDO`, and `EPCS_DATA0` (`硬件规格书` p. 14; `原理图` p. 8). The bundled must-read manual shows a Quartus Programmer flow that adds a `.jic` file and programs/configures flash (`开发板必读说明` PDF pp. 34-38).
- Detect a single EP4CE10 JTAG device. Local Quartus collateral uses single-device JTAG chain files:
  - bundled example `01_led/quartus_prj/output_files/Chain1.cdf` shows `ChainType(JTAG)` with one `EP4CE10F17`
  - local build artifact `quartus/phase0/output_files/piano_phase0_top.jdi` targets `EP4CE10F17C8`

## What the downloader path does not do

- The local docs do not show any UART connection on the JTAG header. JTAG page material only discusses download/programming, while UART is handled by a separate `CH340` Type-C interface and jumper block (`硬件规格书` pp. 18, 23; `原理图` pp. 12, 15).
- The JTAG header is not documented as a board-power source. Board power is described separately: `12V DC` is the main method, with `5V` or the Type-C USB path also usable (`硬件规格书` p. 12; `原理图` p. 3).
- The local board docs do not promise runtime observability through JTAG beyond successful device detect and program/configure status. Do not assume SignalTap, virtual JTAG UART, or other live-debug features for Phase 0 unless the compiled design explicitly includes them.

## Required setup for first bring-up

- Install or point Windows to the Quartus `USB-Blaster` driver. The troubleshooting section in the bundled must-read manual points to the Quartus install tree, specifically `quartus/drivers/usb-blaster` (`开发板必读说明` PDF p. 155).
- Verify the JTAG cable connection and orientation against the board manual photo before powering/programming. The same troubleshooting page explicitly says to confirm the JTAG hookup, and the hardware spec warns not to hot-plug the JTAG connector because it can damage the FPGA JTAG pins (`开发板必读说明` PDF p. 155; `硬件规格书` p. 18).
- Power the board separately from the JTAG cable. For cautious bring-up, use the supported board power input first, then connect JTAG. The schematic warns that when external power is used, USB power should be disconnected to avoid back-feeding the PC USB port (`硬件规格书` p. 12; `原理图` p. 3).
- If you also want UART logs, connect the board's Type-C USB-UART port and set the jumper links for the CH340 path:
  - connect `TX` to `RXD`
  - connect `RX` to `TXD`
  Sources: `硬件规格书` p. 23; `原理图` p. 15.

## What you can observe through downloader alone

- Whether the `USB-Blaster` driver is working and Quartus can see the cable.
- Whether Quartus can detect the EP4CE10 on the JTAG chain.
- Whether a `.sof` download succeeds.
- Whether a flash-programming `.jic` operation succeeds.
- Whether the board comes up with a persistent image after a power cycle, if flash programming was used.

## What still requires USB-UART or probes

- Phase 0 UART status frames or any other text/debug console output.
- Confirmation of reset behavior, `sys_clk`, codec `I2C`, `audio_mclk`, `audio_bclk`, `audio_lrc`, or DAC data activity.
- Any RS232/RS485 observations, which use different transceivers and jumper settings (`硬件规格书` pp. 22, 25; `原理图` pp. 7, 15).

## Phase 0 recommendation

1. Power the board in a controlled way first.
2. Connect the external JTAG downloader and verify Quartus sees a single EP4CE10 device.
3. Start with `.sof` download only; this is the lowest-risk first check.
4. Also connect CH340 Type-C plus the UART jumpers if runtime logs matter for this attempt.
5. Only after volatile bring-up works should you move to `.jic` flash programming for persistent boot.

## Source set

- `Manuals_Examples/[野火]征途_Pro开发板硬件规格书V1.0.1.pdf`
- `Manuals_Examples/[野火]《FPGA开发板必读说明》_20211220.pdf`
- `Manuals_Examples/EBF EP4CE10 Pro/征途_PRO_EBF410202v1_SCH_20230915_原理图.pdf`
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/01_led/quartus_prj/output_files/Chain1.cdf`
- `quartus/phase0/output_files/piano_phase0_top.jdi`
