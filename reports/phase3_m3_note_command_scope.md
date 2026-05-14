# Phase 3 M3 Playable Note Command Scope

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-f92ef528`
Sources: Phase 3 architecture scope, M2a baseline acceptance

## Verdict

**GO-with-constraints — firmware-only pitch+velocity via per-voice registers. Two-phase implementation (M3a firmware-only, M3b RTL if needed).**

The key constraint: per-voice pitch, velocity, and damper parameters require new RTL registers. The current register map shares voice parameters (velocity, loop_len, loop_gain, damp_mix, disp_coeff, body_mix) across all 4 voices. Per-voice pitch control is impossible without either (a) per-voice parameter registers in RTL, or (b) firmware pre-loads voice parameters before each trigger (which works for single-voice but not for polyphonic use).

## Current Register Map Assessment

| Register | Offset | Scope | Note |
| --- | --- | --- | --- |
| PHASE_STEP | 0x08 | Global | sample_gen pitch (not waveguide) |
| VOICE_VELOCITY | 0x28 | **Shared** | Applied to all 4 voices |
| VOICE_LOOP_LEN | 0x2C | **Shared** | String length / pitch |
| VOICE_LOOP_GAIN | 0x30 | **Shared** | Decay rate |
| VOICE_DAMP_MIX | 0x34 | **Shared** | Damping |
| VOICE_DISP_COEFF | 0x38 | **Shared** | String dispersion |
| VOICE_BODY_MIX | 0x3C | **Shared** | Body resonance mix |

**Finding**: The current register map does NOT support per-voice pitch or velocity. For true polyphonic note commands, per-voice parameter registers are needed in RTL.

## Proposed Command Syntax

### Phase 3 M3a: Firmware-only pitch + velocity (per-trigger preload)

```
!N<hex_pitch><hex_velocity>\r\n   — Note-On with pitch and velocity
!F\r\n                            — Note-Off (all voices)
```

Format: `!N` prefix + 8 hex chars (4 pitch + 4 velocity). Total line: 12 bytes.

Firmware parses the hex fields, loads VOICE_LOOP_LEN and VOICE_VELOCITY registers, then triggers via the existing M2a LRU steal path. This works for MONOPHONIC play (one note at a time) but not for polyphonic since all voices share the same parameter registers.

### Phase 3 M3b: RTL per-voice parameter registers (needed for true polyphony)

Add per-voice loop_len and velocity registers at 0x98-0xBC, duplicating the shared register layout per voice (similar to voice1/voice2/voice3 control pattern). This enables true polyphonic pitch control — each voice can hold a different note.

### Note-Off / Damper

`!F\r\n` sends a "release all" command. Firmware iterates all active physical voices and writes increased damp_mix to simulate damper engagement. This stays in firmware and does not require RTL changes.

## Implementation Milestones

### M3a: Monophonic Pitch + Velocity (Firmware Only)

- Extend `!N` parser to accept `!N<8 hex chars>\r\n`
- Write pitch (loop_len) and velocity to shared registers before trigger
- Firmware-only — no RTL changes
- Works for single-note play but same pitch/velocity for all voices

**Gates**: Firmware builds, ROM < 750 words. `!N3A80007FFF\r\n` triggers note with loop_len=149 (A4), velocity=max. Backward compatible with bare `!N\r\n`.

### M3b: Per-Voice Parameter Registers (RTL)

- Add per-voice loop_len, velocity registers to `phase0_control_regs.v`
- Wire through `phase0_audio_path.v` to each `phase1_reduced_voice` instance  
- Update `phase0_hw.h` register map (0x98-0xBC range)
- Update firmware to write per-voice params before trigger

**Gates**: LEs ≤ 10,000, setup ≥ +2.0 ns, M9Ks unchanged, existing register map preserved.

### M3c: Note-Off via Firmware Damper

- `!F\r\n` parser in firmware
- Increase damp_mix on all active voices
- No RTL changes

## Resource Estimate

| Milestone | ROM Delta | RTL Delta | Risk |
| --- | --- | --- | --- |
| M3a (monophonic) | +50 words | 0 | Low — firmware parser extension |
| M3b (per-voice regs) | +20 words | +200 LEs, 0 M9Ks | Medium — register map, audio_path wiring |
| M3c (note-off) | +40 words | 0 | Low — firmware damp_mix write |

ROM: 705 → M3a ~755 → M3c ~795 words. Under 800/1024 (78%). Headroom adequate.

## UART Impact

| Tag | M2a Meaning | M3 Meaning |
| --- | --- | --- |
| G | Total note events | Total note events (including note-off if counted) |
| ST | LRU steal count | Unchanged |
| Q | Accepted command count | Unchanged — counts all `!N` and `!F` commands |
| X | Parser error count | Unchanged |
| New tags | — | Append note-off counter, velocity range tags if needed |

## Next Implementer Task

**"Implement Phase 3 M3a: firmware monophonic pitch+velocity parser"** — extend `!N` handler to parse 8 hex chars for loop_len and velocity. Firmware-only, RTL unchanged. Expected ROM ~755 words. No hardware changes required.
