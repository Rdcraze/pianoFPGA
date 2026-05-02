# Phase 1C Speaker Output Enable — Implementation Report

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-e3050679`

## Root Cause

The WM8978 speaker output driver is disabled in hardware. R49 (Output Control, register 0x31) bit 8 (SPKOUTP_EN) = 0, which gates off the speaker output path entirely. The previous R54/R55 speaker volume fix (50→20) had no real effect because the speaker amplifier was never powered on. Audio leaking through the headphone ROUT1 path was what users heard at very low volume.

## Change

Set R49 SPKOUTP_EN = 1. Existing bits preserved:
- Bit 0 (LOUT1_EN) = 0 (unchanged, no left headphone)
- Bit 1 (ROUT1_EN) = 1 (unchanged, right headphone for monitoring)
- Bit 2 (OUT3MIX_EN) = 1 (unchanged)
- Bit 8 (SPKOUTP_EN): 0 → 1 **(changed)**
- Bit 9 (SPKOUTN_MUTE) = 0 (unchanged)

R49 value: `0x0006` → `0x0106`.

### Files Changed

| File | Change |
|------|--------|
| `rtl/peripherals/wm8978_boot_seq.v:40` | `9'b0_0000_0110` → `9'b1_0000_0110` (cold-boot I2C init) |
| `fw/phase0/phase0_main.c:445` | Added `phase0_codec_write(PHASE0_WM8978_WORD(49u, 0x0106u));` (warm-boot) |

### Registers NOT Changed

R50/R51 (speaker mixer routing), R52/R53 (headphone volume at 20), R54/R55 (speaker volume at 20).

## Verification

- Firmware build: PASS (compiles, elf/bin/mem produced)
- Quartus: not recompiled (single-bit constant change, zero resource/timing impact)
- Hardware smoke: pending programmer verification

## Commit

```
fix: enable WM8978 speaker output driver (R49 SPKOUTP_EN=1)

The speaker volume fix (R54/R55 50→20) was ineffective because the
speaker output driver was gated off at R49 bit 8. Audio was only
leaking through the headphone ROUT1 path.
```
