# Phase 0 UART Fix Hardware Validation

Date: `2026-04-22`

## Findings

No new findings in this recheck. The earlier hardware UART truncation bug is fixed in the updated image.

On the live board, the CH340 path now emits full framed records at `115200 8N1` after JTAG programming:

- `I=50303031`
- `S=8019030A`
- initial runtime frame `R=80190314`
- recurring runtime frame `R=8019035A`

The previous truncated pattern (`I5333`, `S8100`, `R8105`) did not recur in this retest.

## Exact Actions And Results

1. Confirmed the live JTAG chain is still present:
   - command: `D:\quartus\quartus\bin\jtagconfig.exe`
   - result:
     - `1) USB-Blaster [USB-0]`
     - `020F10DD   EP3C(10|5)/EP4CE(10|6)`
2. Used the updated image:
   - file: `E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof`
   - timestamp: `2026-04-22 21:01:19`
3. Opened the known-good CH340 UART path on `COM3` at `115200 8N1`.
4. Reprogrammed the board while capturing serial output:
   - command:
     `D:\quartus\quartus\bin64\quartus_pgm.exe -c "USB-Blaster [USB-0]" -m JTAG -o "P;E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof@1"`
   - result:
     - checksum `0x00102FCA`
     - `Configuration succeeded -- 1 device(s) configured`
5. Captured post-config UART output:
   - `R=8019035A`
   - `R=8019035A`
   - `R=8019035A`
   - `R=8019035A`
   - `I=50303031`
   - `S=8019030A`
   - `R=80190314`
   - then recurring `R=8019035A`

## Runtime Status Interpretation

The full-frame capture shows the board is past the earlier UART-handshake defect and is now reporting real runtime state.

`I=50303031`

- matches the documented ident value from `phase0_soc_stub`

`S=8019030A`

- `STATUS[31:24] = 0x80`
  - codec init done asserted
  - no init-failed, error-seen, or timeout-seen bits set
- `STATUS[23:16] = 0x19`
  - audio enabled
  - tone enabled
  - audio path active
- `STATUS[15:8] = 0x03`
  - UART wiring/status byte is alive
- `STATUS[7:0] = 0x0A`
  - low nibble matches the SOC state machine's exported state nibble at boot-status capture time

`R=80190314` then recurring `R=8019035A`

- upper three bytes stay stable at `0x80 0x19 0x03`
  - codec init remains done
  - audio path remains enabled/active
  - UART path remains alive
- the low byte changes from `0x14` to recurring `0x5A`
  - this is consistent with the SOC stub progressing past boot and into its steady periodic-runtime loop
  - bit `6` becomes set in the recurring frame, which matches `codec_write_exercised`
  - bit `4` remains set, which matches `init_done_seen`

Because only the low four bits of the SOC state are exported in the status byte, the final low-nibble state family is not uniquely identifiable from `R=...` alone. But the recurring `R=8019035A` pattern is stable and does not indicate a codec-init failure.

## Conclusion

This hardware retest confirms the UART framing fix on the real EP4CE10 board:

- JTAG programming still succeeds
- the CH340 UART path now emits complete framed records
- the earlier every-other-byte loss is gone
- the current live runtime state reports codec init complete and a stable recurring runtime status rather than an immediate fault signature

The next debug step, if needed, should be driven by the meaning of `R=8019035A` and any audio/codec observability goals, not by UART transport concerns.
