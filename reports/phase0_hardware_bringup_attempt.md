# Phase 0 Hardware Bring-Up Attempt

Date: `2026-04-22`

## Update After `task-4ad912d3`

- The UART byte-drop bug is fixed in the live RTL tree. [phase0_soc_stub.v](</E:/projects/piano-agents/rtl/control/phase0_soc_stub.v:168>) now holds each byte stable and advances `frame_index` only on a real `tx_valid && tx_ready` acceptance event, instead of advancing when `tx_valid` is first raised.
- [piano_phase0_top_tb.v](</E:/projects/piano-agents/rtl/top/piano_phase0_top_tb.v:3>) now includes a UART monitor that regression-checks complete `12`-byte `I=`, `S=`, and `R=` frames with `CRLF` termination, so this exact hardware-proven handshake bug is now covered in ModelSim.
- Windows verification after the fix:
  - `vlog` compile of the full Phase 0 RTL plus testbench: `0` errors, `0` warnings
  - `vsim -c -lib work piano_phase0_top_tb -do "run -all; quit -f"`: `TB_PASS ... uart_capture_count=36`
  - `vsim -c -lib work piano_phase0_top_nack_tb -do "run -all; quit -f"`: `TB_NACK_PASS ... nack_count=1 stop_count=1`
  - `powershell -ExecutionPolicy Bypass -File E:\projects\piano-agents\quartus\phase0\build.ps1 -Stage compile`: `Quartus II Full Compilation was successful. 0 errors, 3 warnings`
- Live board retest on the same host after programming the rebuilt `.sof` shows full frames on `COM3` at `115200 8N1`, for example:
  - `I=50303031`
  - `S=8019030A`
  - `R=80190314`
  - recurring `R=8019035A`
- The first post-fix capture taken while the board was still running the old image before reconfiguration included some leading truncated `R8105` traffic from the pre-program interval. An immediate second reprogram/capture, with the fixed image already resident, showed only full framed UART output and no every-other-byte loss.

## Findings

### [P1] Hardware UART output drops every other byte because the SOC stub advances the frame before `uart_tx` accepts it

With the CH340 UART path connected on `COM3`, a fresh `.sof` download produces repeatable serial output, but the frames are truncated in a highly regular way:

- observed text capture: `I5333`, `S8100`, repeated `R8105`
- observed raw bytes: `52 38 31 30 35 0D` repeating for runtime frames, which is `R8105<CR>`

That is not random line noise. It matches the shape you get if the intended frames drop every second byte:

- expected ident frame: `I=50303031<CR><LF>`
- observed ident frame: `I5333<CR>`
- observed boot-status frame: `S8100<CR>` with the `=` and alternating digits missing
- observed runtime frame shape: `R8105<CR>` with the `=` and alternating digits missing

The most likely root cause is the transmit handshake between [phase0_soc_stub.v](</E:/projects/piano-agents/rtl/control/phase0_soc_stub.v:166>) and [uart_tx.v](</E:/projects/piano-agents/rtl/peripherals/uart_tx.v:32>). `phase0_soc_stub` increments `frame_index` in the same clock edge where it raises registered `tx_valid`, while `uart_tx` only consumes the previous cycle's `tx_valid` because both blocks are synchronous. In effect, the formatter advances to the next character before the UART has actually accepted the current one, so every other byte is skipped.

This is a real hardware-backed bug, not just a missing cable or baud mismatch.

### [Info] JTAG download to the live board succeeded with the current packaged `.sof`

The live board is visible on the JTAG chain, and the current Phase 0 image downloads successfully:

- cable: `USB-Blaster [USB-0]`
- detected device: JTAG ID `0x020F10DD`, reported by Quartus/JTAG tools as `EP3C(10|5)/EP4CE(10|6)` class
- programming file: `quartus/phase0/output_files/piano_phase0_top.sof`
- result: `Configuration succeeded -- 1 device(s) configured`

So the current packaged build is loadable onto the real board through the connected downloader.

## Exact Actions And Results

### First pass: downloader-only attempt

1. Read the manual-reader artifact `reports/downloader_capabilities_report.md` and followed its constraints:
   - use external JTAG only
   - start with volatile `.sof` programming
   - do not assume UART over downloader
2. Confirmed the packaged image exists:
   - `E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof`
3. Confirmed cable and chain visibility:
   - command: `D:\quartus\quartus\bin\jtagconfig.exe`
   - result:
     - `1) USB-Blaster [USB-0]`
     - `020F10DD   EP3C(10|5)/EP4CE(10|6)`
4. Confirmed Quartus programmer sees the cable:
   - command: `D:\quartus\quartus\bin64\quartus_pgm.exe -l`
   - result: `1) USB-Blaster [USB-0]`
5. Confirmed Quartus programmer sees one device on that cable:
   - command: `D:\quartus\quartus\bin64\quartus_pgm.exe -c "USB-Blaster [USB-0]" -a`
   - result:
     - `Using programming cable "USB-Blaster [USB-0]"`
     - one device with JTAG ID `0x020F10DD`
6. First programming attempt:
   - command: `D:\quartus\quartus\bin64\quartus_pgm.exe -c "USB-Blaster [USB-0]" -m JTAG -o "PV;E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof@1"`
   - result: failed immediately with `Error (213002): Programming option PV is illegal`
   - interpretation: tool-syntax issue in this Quartus build, not a cable or board failure
7. Second programming attempt:
   - command: `D:\quartus\quartus\bin64\quartus_pgm.exe -c "USB-Blaster [USB-0]" -m JTAG -o "P;E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof@1"`
   - result:
     - `Using programming file ... piano_phase0_top.sof ... for device EP4CE10F17@1`
     - `Configuring device index 1`
     - `Device 1 contains JTAG ID code 0x020F10DD`
     - `Configuration succeeded -- 1 device(s) configured`
     - `Successfully performed operation(s)`

### Second pass: CH340 UART connected

8. Verified the UART path appeared on Windows after the user connected it:
   - `USB-SERIAL CH340 (COM3)`
9. Opened `COM3` at `115200 8N1`, then reconfigured the FPGA with the same `.sof` while capturing serial output.
10. Fresh programming result remained good:
   - `quartus_pgm ... -o "P;...piano_phase0_top.sof@1"`
   - `Configuration succeeded -- 1 device(s) configured`
11. Captured post-config UART output:
   - text capture:
     - `R8105`
     - `R8105`
     - `I5333`
     - `S8100`
     - `R8101`
     - then repeated `R8105`
   - steady-state raw-byte capture from the running design:
     - hex: `52 38 31 30 35 0D` repeating
     - ascii: `R8105<CR>` repeating

## Observations

- The board is powered and connected well enough for JTAG identification, volatile FPGA configuration, and UART observation through the CH340 path.
- The current Phase 0 `.sof` loads on hardware without an immediate programming-side failure.
- The UART path is alive, which means the design is running and emitting frames on real hardware.
- The UART frame content is truncated in a deterministic every-other-byte pattern, which points to an RTL transmit-handshake bug rather than a physical connection issue.

## Blockers And Next Actions

1. Fix the UART transmit handshake between `phase0_soc_stub` and `uart_tx`.
2. Re-run the same hardware capture after that fix and check for full frames:
   - `I=50303031`
   - `S=XXXXXXXX`
   - recurring `R=XXXXXXXX`
3. Once the UART framing is correct, use the boot/runtime status values to decide whether deeper probe work is needed on:
   - `audio_mclk`
   - `i2c_scl` / `i2c_sda`
   - `audio_bclk` / `audio_lrc`
   - `audio_dacdat`

Bottom line: the real board now confirms both that programming works and that the current RTL has a concrete UART framing bug on hardware. The next useful step is to fix that transmit handshake and rerun the same capture.
