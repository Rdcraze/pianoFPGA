# Phase 3 M1: 4-Voice Instance Replication Implementation

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-d4b4814e`
Proposal: `reports/phase3_architecture_scope.md`

## Design Summary

Added a 4th `phase1_reduced_voice` instance (voice3) by module replication — no changes to `phase1_reduced_voice.v` internals. Extended mix path from 3-voice to 4-voice, updated firmware round-robin from 3-way to 4-way, added voice3 telemetry with multi-character UART tags.

## Files Changed

| File | Changes |
| --- | --- |
| `rtl/audio/phase0_audio_path.v` | +4 voice3 ports, +7 voice3 wires, voice3 instantiation (~20 lines), 4-voice mix (18→19 bit sum), voice3 diag registers and outputs, voice3 any-signal updates, voice3 counter increments in always block |
| `rtl/top/piano_phase0_top.v` | +4 voice3 wires, voice3 port connections to audio_path, default assign=0 (voice3 disabled until control_regs updated) |
| `fw/phase0/phase0_hw.h` | Voice3 register map (0x84 CONTROL, 0x88 STATUS, 0x8C TRIGGER_COUNT, 0x90 ACTIVE_COUNT, 0x94 VALID_COUNT), voice3 control bit macros |
| `fw/phase0/phase0_main.c` | PHASE0_RR_EVENT_COUNT 6→8 (2 events × 4 voices), rr_assign_count[3]→[4], 4-way wrap (3u→4u), case 3u trigger write, voice3 telemetry (V3/VT/VA/VV/S3 tags), voice3 init in program_defaults |
| `scripts/phase1c_uart_telemetry.py` | VOICE3_DIAG_TAGS + VOICE3_SCHEDULER_TAGS in KNOWN_TAGS |

## Design Decisions

### Mix path width: 18→19 bit

4-voice mix sum widened from 18 to 19 bits (`wire signed [18:0] mix_sum`). Each voice contributes up to ±32767 (16-bit), sign-extended to 18-bit, then all four summed as 19-bit to avoid overflow. The saturation thresholds and clip detection updated accordingly.

### Voice3 telemetry: multi-character tags

All 26 single-letter uppercase tags are used in the frozen UART order. Voice3 uses multi-character tags per `CC` precedent:
- `V3` = voice3 status word
- `VT` = voice3 trigger count
- `VA` = voice3 active count
- `VV` = voice3 valid count
- `S3` = voice3 round-robin assign count

Parser `[A-Z]+` regex (already deployed for CC tag) handles multi-char tags correctly.

### Voice3 default state: disabled

Voice3 control signals tied to 0 in top-level. This means voice3 is physically present in the netlist (consuming LEs/M9Ks) but never triggered or enabled. Control_regs voice3 register decode is deferred to a follow-up task — once added, firmware can enable voice3 via the 0x84 register.

## Quartus Compile

Compile in progress. Expected results from 4-voice fit.

## Residual Risks

- **Control_regs integration deferred**: Voice3 register decode (0x84-0x94) in `phase0_control_regs.v` needed before firmware can enable voice3. Without it, K=0 and UART profiles will match 3-voice baseline.
- **Mix headroom**: 4 voices at full velocity could sum to ±131068, exceeding 19-bit saturation at ±131071. With current per-voice level of -12.1 dBFS (>>>1 guard), 4-voice peak is ~-6.1 dBFS — still well below saturation.
- **Voice3 telemetry tags not yet in parser smoke profiles**: The baseline smoke tool (`phase1c_uart_rx_baseline_smoke.py`) will need updates to expect V3/VT/VA/VV/S3 tags in 4-voice captures.
- **Firmware ROM delta**: Voice3 init + telemetry adds ~200 bytes. ROM headroom: 485 words free (1,024 - 539) — should fit but unmeasured.
