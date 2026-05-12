# Phase 2 Path C Baseline Split

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-b1230e4d`
Plan: `reports/phase2_audio_config_baseline_acceptance_plan.md`

## Result

Path C executed successfully. User-owned audio-config changes are preserved on `user/audio-config`. The `codex/phase1c-uart-boundary-fix` branch is clean at the validated Phase 1C baseline. Phase 2 hammer excitation implementation is unblocked.

## Operations Performed

### Pre-state (step 1)

- Branch: `codex/phase1c-uart-boundary-fix`
- `fw/phase0/phase0_main.c`: dirty (user-owned audio-config diff)
- User-owned changes: GAIN 16384→4096, R49/R54/R55 removed, R52/R53 0x0194→0x019E

### Branch creation (steps 2-4)

```
git checkout -b user/audio-config
git add fw/phase0/phase0_main.c
git commit -m "audio-config: user-owned firmware codec register restructuring"
```

Commit: `86a862c` on `user/audio-config`. Exactly one file staged (`fw/phase0/phase0_main.c` only).

### Restore clean baseline (steps 5-6)

```
git checkout codex/phase1c-uart-boundary-fix
git checkout HEAD -- fw/phase0/phase0_main.c
```

### Verification (steps 7-9)

| Check | Result |
| --- | --- |
| `git diff -- fw/phase0/phase0_main.c` | No output — file is clean |
| Current branch | `codex/phase1c-uart-boundary-fix` |
| GAIN on current branch | `16384u` (validated baseline) |
| R49 on current branch | Present (`0x0106u`) |
| R52/R53 on current branch | `0x0194u` (validated) |
| R54/R55 on current branch | Present (`0x0180u`) |
| `user/audio-config` exists | Yes, commit `86a862c` |
| GAIN on user/audio-config | `4096u` (user-owned) |
| R49/R54/R55 on user/audio-config | Removed (user-owned) |
| R52/R53 on user/audio-config | `0x019Eu` (user-owned) |
| Unrelated dirty files untouched | Confirmed |

### Step 8: diff vs 7ed2c62

`git diff 7ed2c62 -- fw/phase0/phase0_main.c` shows a non-empty diff but in the expected direction (dirty→clean). This occurs because commit `7ed2c62` (CC counter implementation report) inadvertently carried the user-owned dirty file content (hash `e9bf95e`). Commit `c95f08a` (revert diagnostic scaffolding) restored the clean baseline (hash `3b3dd25`). The current `codex/phase1c-uart-boundary-fix` working tree matches the validated clean baseline at `c95f08a`/HEAD.

The file on the current branch has all validated Phase 1C gain/speaker fixes:
- GAIN = 16384 (matching `647edee` +12dB fix)
- R49 SPKOUTP_EN = 1 (matching `6149c59` speaker enable)
- R52/R53 headphone volume (matching `6934692` speaker volume fix)
- R54/R55 speaker volume (matching `6934692` speaker volume fix)

## Final State Summary

| Item | Value |
| --- | --- |
| Current branch | `codex/phase1c-uart-boundary-fix` |
| `fw/phase0/phase0_main.c` status | Clean (matches validated baseline) |
| `user/audio-config` commit | `86a862c` |
| User audio-config diff | Preserved on `user/audio-config` |
| Unrelated files | Untouched |
| Phase 2 hammer blocker | **Resolved** |

## Next Steps

Phase 2 hammer excitation implementation (`excitation_rom` constants in `rtl/audio/phase1_reduced_voice.v`) is unblocked. The firmware baseline on `codex/phase1c-uart-boundary-fix` is clean and matches the validated Phase 1C baseline for reproducible before/after comparison.
