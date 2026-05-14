# Phase 3 M3b RTL Per-Voice Parameter Registers — Implementation

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-9723f616` | Commit: `a886b68`

## Verdict: PASS — RTL slice complete, all gates met

## Files Changed

| File | Changes |
| --- | --- |
| `rtl/control/phase0_control_regs.v` | +8 output ports, +8 localparams (0x98-0xB4), +8 reset init, shared-write propagation, +8 per-voice write decode cases, +8 read decode cases |
| `rtl/audio/phase0_audio_path.v` | +8 input ports, per-voice routing to voice instances |
| `rtl/top/piano_phase0_top.v` | +8 wires, control_regs + audio_path per-voice connections |

## Register Map

| Offset | Name | Description |
| --- | --- | --- |
| 0x98 | VOICE0_LOOP_LEN | Voice 0 per-instance loop length |
| 0x9C | VOICE0_VELOCITY | Voice 0 per-instance velocity |
| 0xA0 | VOICE1_LOOP_LEN | Voice 1 per-instance loop length |
| 0xA4 | VOICE1_VELOCITY | Voice 1 per-instance velocity |
| 0xA8 | VOICE2_LOOP_LEN | Voice 2 per-instance loop length |
| 0xAC | VOICE2_VELOCITY | Voice 2 per-instance velocity |
| 0xB0 | VOICE3_LOOP_LEN | Voice 3 per-instance loop length |
| 0xB4 | VOICE3_VELOCITY | Voice 3 per-instance velocity |

Shared `VOICE_LOOP_LEN` (0x2C) and `VOICE_VELOCITY` (0x28) writes propagate to all 4 per-voice registers. Shared readback returns the shared register value. Per-voice registers have independent readback via their own addresses.

## Quartus Results

| Gate | Target | Actual | Result |
| --- | --- | --- | --- |
| Errors | 0 | 0 | PASS |
| LEs | ≤10,200 | 9,992 (97%) | PASS |
| M9Ks | Unchanged | 17/46 | PASS |
| setup slack | ≥+2.0 ns | +2.914 ns | PASS |
| hold slack | Clean | +0.405 ns | PASS |
| Timing violations | 0 | 0 (TNS=0) | PASS |

## Remaining: Slice 2 (Firmware)

Firmware needs to update `phase0_hw.h` with register constants and refactor `phase0_lru_steal_note_event()` to write per-voice parameters to the selected voice before triggering. The monophonic guard can be removed once per-voice writes are in place.
