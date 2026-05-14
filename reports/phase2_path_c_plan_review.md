# Phase 2 Path C Plan Review

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-f5d899fb`
Reviewed artifact: `reports/phase2_audio_config_baseline_acceptance_plan.md`

## Verdict

**PASS — Path C is the safest choice, with minor revisions.**

The plan accurately characterizes the dirty diff, correctly identifies the reproducibility risk, and recommends the right path. Two revisions needed before execution: (1) clarify that only firmware changes go on the user branch, not other dirty files; (2) add user approval gate.

## Check 1: Dirty Diff Accuracy

**PASS.** The plan's diff characterization is accurate against the current worktree:

| Plan Claim | Actual Diff | Match |
| --- | --- | --- |
| GAIN 16384→4096 | `16384u` → `4096u` (-12 dB) | ✓ |
| R49 write removed | `0x0106u` write gone | ✓ |
| R52 0x0194→0x019E | `0x0194u` → `0x019Eu` (volume 20→30) | ✓ |
| R53 0x0194→0x019E | same | ✓ |
| R54 removed | `0x0180u` write gone | ✓ |
| R55 removed | `0x0180u` write gone | ✓ |

The diff is +3/-6 lines, firmware-only. No RTL, constraint, or build changes. The plan correctly identifies the impact: GAIN reduction, missing speaker re-initialization, changed headphone volume.

**Minor note**: The plan claims the baseline is `7ed2c62`, but HEAD is `c95f08a` (the diagnostic-code removal revert). This is not an error — `c95f08a` only removed firmware code that `7ed2c62` added, so the firmware files at `c95f08a` are identical to `7ed2c62` for Phase 1C baseline purposes. The plan should note this for clarity.

## Check 2: Path C Preserves User Work + Reproducibility

**PASS.** Path C cleanly separates concerns:

1. **User's audio config**: Saved on `user/audio-config` branch — independently validatable later
2. **Hammer excitation**: Proceeds on clean `codex/phase1c-uart-boundary-fix` with known validated baseline
3. **File-disjoint**: The plan correctly notes `fw/phase0/phase0_main.c` and `rtl/audio/phase1_reduced_voice.v` have no overlap — merge is text-level clean

The clean baseline provides the best possible before/after comparison for hammer validation: known SOF (0x005F5888 at `647edee`, or 0x005F4CC5 at `6934692`), known UART profiles, known audio levels, known K=0.

## Check 3: Git/Worktree Risks

**PASS with revisions.**

### Risks identified:

1. **Dirty `reports/orchestrator_pickup_note.md`**: The git status shows this is modified but untracked in the staging area. Path C step 1 commits `fw/phase0/phase0_main.c` — it must NOT accidentally include this file or any of the 40+ untracked report files.

   **Revision**: Step 1 should be `git add fw/phase0/phase0_main.c` only (the plan already says this), with explicit confirmation that no other files are staged.

2. **Untracked report files**: 40+ `??` files exist under `reports/`. These are harmless for Path C (not committed, not affected by checkout), but any report referencing commits between `7ed2c62` and `c95f08a` should note the branch state after Path C.

3. **`codex/phase1c-uart-boundary-fix` is the current branch**: Path C operates on this branch. The plan correctly names it. After step 3, it will be clean at `c95f08a` with the firmware matching `7ed2c62`.

4. **`vsim_stacktrace.vstf`**: Untracked simulation artifact — harmless, no action needed.

### Git operation validation:

```
git checkout -b user/audio-config codex/phase1c-uart-boundary-fix  ✓ creates branch from HEAD
git add fw/phase0/phase0_main.c                                      ✓ commits only firmware
git commit -m "..."                                                  ✓
git checkout codex/phase1c-uart-boundary-fix                         ✓ returns to worktree
git checkout HEAD -- fw/phase0/phase0_main.c                        ✓ restores clean file
```

The operations are correct. The only risk is human error — staging the wrong files or restoring the wrong path. These are standard git operations with minimal blast radius.

## Check 4: User Approval Requirement

**PASS — user approval required before execution.**

Path C is NOT a read-only operation. It:
- Creates a new branch (`user/audio-config`) in the user's repository
- Commits the user's uncommitted changes to that branch
- Modifies a file in the current worktree (`fw/phase0/phase0_main.c`)

The plan is a recommendation, not an authorization. Explicit user approval should be obtained before ANY of the Path C git operations are executed. The user should:

1. Confirm they want their dirty firmware changes committed to `user/audio-config`
2. Confirm they want `fw/phase0/phase0_main.c` reverted to the CC counter baseline on the current branch
3. Confirm they understand the hammer excitation work will proceed on the clean baseline, and their audio-config changes will be integrated later

This is especially important because the dirty firmware changes were described as "user-confirmed intentional uncommitted changes" — the user may have reasons for keeping them uncommitted on the current branch.

## Check 5: Post-Path-C Verification Gates

**Adequate with addition.** The plan's acceptance gates (section 5) are well-defined. Recommended additions:

| Gate | Current | Recommended Addition |
| --- | --- | --- |
| Firmware baseline committed | `git log -1` shows known commit | Confirm commit matches `7ed2c62` or `c95f08a` byte-for-byte (`git diff 7ed2c62 -- fw/phase0/phase0_main.c` is empty) |
| Firmware builds | exit 0 | ROM word count matches baseline (539 words) |
| Hardware evidence | UART, audio, K=0 | Explicitly note whether hardware access is available. If not, document as deferred but do not block |
| Git status | Not listed | `git status --short --untracked-files=normal` shows only expected untracked files, no dirty tracked files |
| user/audio-config branch | Not listed | Confirm branch exists with the user's firmware commit |

## Summary

| Check | Result |
| --- | --- |
| 1. Dirty diff accuracy | PASS |
| 2. Preserves work + reproducibility | PASS |
| 3. Git/worktree risks | PASS with revisions |
| 4. User approval required | PASS (explicit approval needed) |
| 5. Verification gates | PASS with additions |

## Recommendation

**PASS — proceed with Path C after user approval and revisions.**

Execute Path C as described, with these amendments to the implementer task:

1. Before any git operation, confirm user approval for branch creation + file restoration
2. Stage ONLY `fw/phase0/phase0_main.c` when creating `user/audio-config` — verify no other files are staged
3. After restore, verify `git diff 7ed2c62 -- fw/phase0/phase0_main.c` is empty (byte-identical to validated baseline)
4. After restore, verify `git status --short` shows no unexpected dirty tracked files
5. Confirm `user/audio-config` branch exists with exactly one commit containing the firmware diff

These amendments are procedural, not substantive — the plan's core logic is sound. Path C is the correct choice.
