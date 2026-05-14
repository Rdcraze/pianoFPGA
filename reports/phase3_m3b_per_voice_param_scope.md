# Phase 3 M3b Per-Voice Parameter Register Scope

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-7c34223f`

## Verdict

**GO-with-constraints — per-voice loop_len and velocity registers. Tight LE budget requires gates.**

## Problem

M3a is monophonic: all 4 physical voices share the same `VOICE_LOOP_LEN` (0x2C) and `VOICE_VELOCITY` (0x28) registers. Parameterized `!N` must reset all voices before retuning. For true polyphonic pitch control, each physical voice needs independent loop_len and velocity.

## Proposed Register Map

| Register | Offset | Width | Reset | Description |
| --- | --- | --- | --- | --- |
| `VOICE0_LOOP_LEN` | 0x98 | 7 bits | 106 | Voice 0 per-instance loop length |
| `VOICE0_VELOCITY` | 0x9C | 16 bits | 0x4000 | Voice 0 per-instance velocity |
| `VOICE1_LOOP_LEN` | 0xA0 | 7 bits | 106 | Voice 1 per-instance loop length |
| `VOICE1_VELOCITY` | 0xA4 | 16 bits | 0x4000 | Voice 1 per-instance velocity |
| `VOICE2_LOOP_LEN` | 0xA8 | 7 bits | 106 | Voice 2 per-instance loop length |
| `VOICE2_VELOCITY` | 0xAC | 16 bits | 0x4000 | Voice 2 per-instance velocity |
| `VOICE3_LOOP_LEN` | 0xB0 | 7 bits | 106 | Voice 3 per-instance loop length |
| `VOICE3_VELOCITY` | 0xB4 | 16 bits | 0x4000 | Voice 3 per-instance velocity |

Existing shared registers (0x2C, 0x28) remain as backward-compatible defaults. Writing to shared registers writes all 4 per-voice registers. This preserves bare `!N` M2a behavior.

## RTL Changes

1. **`phase0_control_regs.v`**: Add 8 new localparams, output regs, write decode, read decode for 0x98-0xB4. Write to shared 0x28/0x2C propagates to all 4 per-voice registers.
2. **`phase0_audio_path.v`**: Add per-voice loop_len/velocity input ports, route to each `phase1_reduced_voice` instance instead of shared wires.

## Resource Estimate

| Resource | Current | Target Gate | Hard Gate | Risk |
| --- | --- | --- | --- | --- |
| LEs | 9,938 | ≤ 10,200 | ≤ 10,320 | Medium — +262 LE budget |
| M9Ks | 17 | ≤ 20 | ≤ 20 | Low |
| DSPs | 8 | — | — | Low |
| setup slack | +2.948 ns | ≥ +2.0 ns | ≥ +1.5 ns | Low |
| ROM | 791 words | ≤ 850 | ≤ 900 | Low |

**LE risk**: 8 registers with decode + per-voice routing adds ~150-300 LEs. At 9,938 + 300 = 10,238 — under 10,200 target. The existing 9,800 LE gate for M1 was already exceeded; 10,200 is the new realistic budget.

## Firmware Changes

- `phase0_lru_steal_note_event()`: after selecting physical voice `phys`, write loop_len and velocity to that voice's per-instance registers before trigger
- Remove monophonic guard (unconditional reset) — no longer needed
- Bare `!N` uses shared defaults, no change

ROM estimate: +40-60 words (per-voice register writes replace unconditional reset). Net delta: ~+20 words. ROM ~811 words, under 850.

## Verifier Plan

1. Quartus compile: LE ≤ 10,200, setup ≥ +2.0 ns
2. Bare `!N\r\n` regression: G increments, M2a behavior preserved
3. Two simultaneous parameterized notes: different pitches on different voices, confirm pitch separation via audio FFT
4. UART: K=0, X=0, existing tags unchanged

## Next Task

"Implement Phase 3 M3b: per-voice loop_len and velocity registers" — add 8 registers to control_regs, route through audio_path, update firmware scheduler.
