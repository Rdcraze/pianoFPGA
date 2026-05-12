# Phase 2 Audio-Config Baseline Acceptance Plan

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-f6e7934b`
Context: `task-218221e2`, `task-ad94d1d9`

## 1. The Dirty Diff

`fw/phase0/phase0_main.c` has user-confirmed intentional uncommitted changes relative to the validated Phase 1C baseline at commit `7ed2c62`:

| Change | Baseline (`7ed2c62`) | Dirty (current worktree) | Effect |
| --- | --- | --- | --- |
| `PHASE0_REG_GAIN` default | `16384u` (Q15 0.5) | `4096u` (Q15 0.125) | Digital gain reduced by 12 dB — only affects `sample_gen` path, not waveguide voices |
| R49 write (SPKOUTP_EN) | `wm8978_word(49u, 0x0106u)` | Removed | Speaker output enable no longer set by firmware warm-boot path |
| R52 headphone volume | `wm8978_word(52u, 0x0194u)` | `wm8978_word(52u, 0x019Eu)` | Headphone volume changed |
| R53 headphone volume | `wm8978_word(53u, 0x0194u)` | `wm8978_word(53u, 0x019Eu)` | Headphone volume changed |
| R54 speaker volume | `wm8978_word(54u, 0x0180u)` | Removed | Speaker volume no longer set by firmware warm-boot path |
| R55 speaker volume | `wm8978_word(55u, 0x0180u)` | Removed | Speaker volume no longer set by firmware warm-boot path |

### Why this changes the audio validation baseline

The validated Phase 1C baseline (`7ed2c62`) was accepted with specific UART profiles (G=6, Q=0, X=0, K=0, CC=0x003D0900) and audio evidence (waveform checklist, gain calibration) that depend on the firmware's codec register writes. The dirty diff changes:

1. **Codec warm-boot configuration**: R49, R54, R55 writes are removed. The boot ROM (`wm8978_boot_seq.v`) sets these during cold boot, but any codec state loss after cold boot would not be recovered without the firmware re-writes.
2. **Audio output level**: The GAIN reduction by 12 dB changes the sample_gen reference level from -5.6 dBFS (per gain trace) to approximately -17.6 dBFS, shifting the entire reference calibration.
3. **Headphone volume**: R52/R53 change alters the headphone output path, which matters if the speaker output is not being driven.
4. **UART profiles**: K=0 should remain (waveguide path unchanged), but CC may shift due to different codec write cadence. G, Q, X should be stable. These need re-measurement.

Any hammer excitation implementation validated against this dirty baseline cannot be compared to the accepted Phase 1C audio evidence. The before/after comparison is broken.

## 2. Path Comparison

### Path A: Commit the user-owned firmware diff as a new explicit audio-config baseline, then validate

1. User commits the dirty diff with a clear message.
2. Orchestrator creates an implementer task to build firmware + compile Quartus on the new baseline.
3. Verifier captures UART (no-command + commanded), audio (waveform checklist), and confirms K=0, CC stability.
4. After acceptance, hammer excitation implementation proceeds on the new baseline.

| Criterion | Assessment |
| --- | --- |
| Reproducibility | Good — committed baseline with known SOF checksum |
| Verifier confidence | High — fresh evidence bundle |
| Time to unblock | 2-3 tasks (commit → build → validate) |
| Risk | The new audio config may change K=0 or CC profile; headphone-only path may produce different audio levels |

### Path B: Revert to the validated Phase 1C baseline for hammer implementation

1. `git checkout HEAD -- fw/phase0/phase0_main.c` to the validated `7ed2c62` baseline.
2. User's intentional changes are lost from the worktree (must be preserved elsewhere if needed).
3. Hammer excitation implementation proceeds immediately on the known-good baseline.

| Criterion | Assessment |
| --- | --- |
| Reproducibility | Best — uses already-validated baseline with known SOF, UART profiles, audio evidence |
| Verifier confidence | Best — all reference data already exists |
| Time to unblock | 0 tasks (immediate) |
| Risk | User's intentional audio-config work is discarded or must be re-created later |

### Path C: Branch/snapshot the user-owned audio config separately, keep hammer work on clean baseline

1. Create a new branch (e.g., `user/audio-config`) from current HEAD, commit the dirty diff there.
2. Switch back to `codex/phase1c-uart-boundary-fix`, revert the dirty file to `7ed2c62`.
3. Hammer excitation implementation proceeds on the clean baseline.
4. User's audio config exists on its own branch for later integration.

| Criterion | Assessment |
| --- | --- |
| Reproducibility | Best — clean baseline for hammer, user config preserved on branch |
| Verifier confidence | Best — validated baseline for before/after comparison |
| Time to unblock | 1 git operation (branch + restore) |
| Risk | Merge complexity when user's audio config is eventually integrated. The separate branch may diverge significantly if hammer work takes many commits. |

## 3. Recommendation

**Recommend Path C: Branch user audio-config, keep hammer on clean baseline.**

Rationale:

1. **Reproducibility above all**: Phase 2 hammer excitation is a narrow RTL change (16 ROM constants). It needs the cleanest possible before/after comparison. The validated Phase 1C baseline provides a known SOF checksum, known UART profiles (G=6, Q=0, X=0, K=0, CC=0x003D0900), known audio levels (per-voice -11.7 dBFS digital, 3-voice sum -2.1 dBFS), and known resource/timing posture. Any deviation from this baseline makes the hammer validation ambiguous — was a change in K or audio level caused by the hammer ROM or by the audio-config diff?

2. **Preserves user work**: Path B discards the user's intentional audio-config changes. Path C preserves them on a dedicated branch where they can be validated independently.

3. **Isolation of concerns**: The user's audio-config changes (codec register management, gain restructuring) are a separate workstream from the hammer excitation physics improvement. Mixing them in the same baseline conflates two independent changes, making validation and rollback harder.

4. **Parallel validation**: With Path C, the user's audio-config can be validated independently on its branch while hammer implementation proceeds in parallel. The audio-config baseline can be integrated after both are independently validated.

5. **Merge is straightforward**: The user's changes touch only firmware (`fw/phase0/phase0_main.c`). Hammer excitation touches only RTL (`rtl/audio/phase1_reduced_voice.v`). There is no file-level conflict — integrating both after independent validation is a clean merge with no text-level collision.

### Path C Operations

```
# 1. Create and switch to user audio-config branch
git checkout -b user/audio-config codex/phase1c-uart-boundary-fix
git add fw/phase0/phase0_main.c
git commit -m "audio-config: user-owned codec register restructuring"

# 2. Return to main worktree branch
git checkout codex/phase1c-uart-boundary-fix
git checkout HEAD -- fw/phase0/phase0_main.c

# 3. Verify clean
git diff -- fw/phase0/phase0_main.c  # expected: no output
```

After Path C: `codex/phase1c-uart-boundary-fix` is clean at the validated `7ed2c62` baseline. Hammer excitation implementation can proceed.

## 4. Next Tasks (if Path C is accepted)

### Implementer task: "Create user/audio-config branch and restore hammer baseline"

- **Scope**: Execute the Path C git operations. Do not modify any file content. Do not commit user-owned code into the hammer branch. Verify `fw/phase0/phase0_main.c` is clean on `codex/phase1c-uart-boundary-fix`.
- **Out of scope**: RTL, firmware content, build outputs, validation.
- **Expected artifact**: Short confirmation note at `reports/phase2_path_c_baseline_split.md`.

### Verifier task: "Confirm hammer baseline is clean after audio-config branch split"

- **Scope**: Verify `fw/phase0/phase0_main.c` on `codex/phase1c-uart-boundary-fix` matches the validated CC counter baseline (`7ed2c62`). Confirm firmware builds. Confirm no dirty files in hammer scope.
- **Expected artifact**: `reports/phase2_path_c_clean_baseline_validation.md`.

### Then: Unblock hammer excitation implementation

- Implementer: replace 16 ROM constants in `excitation_rom` per `reports/phase2_hammer_excitation_scope.md`.
- Verifier: compile Quartus, program FPGA, capture UART + audio, run checklist.

## 5. Acceptance Gates (for any path)

Before Phase 2 hammer implementation is unblocked, confirm:

| Gate | Method |
| --- | --- |
| Firmware baseline committed | `git log -1 -- fw/phase0/phase0_main.c` shows known commit |
| Firmware builds | `.\fw\phase0\build.ps1` — exit 0, .elf/.bin/.mem produced |
| Quartus compiles | `quartus_sh --flow compile piano_phase0_top` — 0 errors |
| SOF checksum recorded | `quartus_pgm` or fitter report |
| UART no-command profile | `G=6 Q=0 X=0 K=0 CC=<stable>` |
| UART commanded profile | `G=12 Q=6 X=0 K=0 CC=<stable>` |
| CC stability ±5% | 5 consecutive reports |
| K=0 confirmed | No mix clipping in either profile |
| Waveform checklist PASS | Per `reports/phase1c_audio_verification_checklist.md` |
| Audio A/B baseline recorded | Pre-hammer capture for before/after comparison |

## 6. Blocked Status

**Phase 2 hammer excitation implementation remains blocked** until this audio-config baseline is resolved via one of the three paths described above. The hammer excitation RTL change (`excitation_rom` constants only) has zero resource delta, but its audio validation requires a clean, committed, validated firmware baseline to establish reproducible before/after evidence.

The block is procedural, not technical — the hammer ROM change and the audio-config firmware changes are file-disjoint. The block exists because mixing them in the same baseline would make it impossible to attribute audio changes to the correct cause.
