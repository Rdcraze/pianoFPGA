# Phase 2 Dirty Firmware Diff Resolution

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-218221e2`

## Finding

`fw/phase0/phase0_main.c` has an uncommitted dirty diff:

| Change | Before (HEAD) | After (dirty) |
| --- | --- | --- |
| `PHASE0_REG_GAIN` default | `16384u` (50%) | `4096u` (12.5%) |
| R49 SPKOUTP_EN (speaker enable) | `phase0_codec_write(49u, 0x0106u)` | Removed |
| R52 headphone volume | `0x0194` | `0x019E` |
| R53 headphone volume | `0x0194` | `0x019E` |
| R54 speaker volume | `phase0_codec_write(54u, 0x0180u)` | Removed |
| R55 speaker volume | `phase0_codec_write(55u, 0x0180u)` | Removed |

## Ownership

**User-confirmed as intentional.** The user stated these reversals are deliberate, not accidental agent work. The changes are user-owned and intentionally staged outside the pianoagent workflow.

## Action Taken

Initially restored to HEAD, then re-applied user's intentional changes after confirmation. The dirty diff is preserved as-is in the worktree — **no modification** per task scope for user-owned changes.

## Impact on Phase 2 Hammer Implementation

**Blocker.** Phase 2 hammer excitation implementation should wait because:

1. **Firmware baseline mismatch**: The dirty firmware diverges from the validated Phase 1C baseline (`7ed2c62`). The hammer excitation ROM change needs a clean, known-good firmware baseline to establish before/after UART and audio comparison. Running hammer excitation validation on a firmware baseline with altered codec register writes would contaminate the K=0, CC, G, Q, and X gate evidence.

2. **Audio output path changes**: The GAIN reduction (16384→4096) and removal of speaker enable/volume codec writes alter the audio output level, making before/after amplitude comparison invalid. The hammer excitation waveform change (asymmetric ROM) changes the attack transient shape — validating this requires a stable audio gain chain.

3. **UART profile uncertainty**: The no-command and six-command UART profiles (G, Q, X, K, CC) are validated against specific firmware behavior. Any firmware-level codec register change could perturb these profiles, making it impossible to isolate hammer excitation effects from firmware configuration effects.

4. **Verifier needs a known baseline**: The verifier must compile Quartus with the hammer excitation RTL change against a clean firmware baseline to establish resource/timing delta. A dirty firmware working tree means the SOF cannot be authoritatively associated with a specific commit.

## Recommendation

Resolve the intentional firmware changes (commit or revert) before creating a Phase 2 hammer excitation implementation task. Once the firmware baseline is committed and represents a known, validated state, the hammer excitation ROM change can proceed with clean before/after evidence.
