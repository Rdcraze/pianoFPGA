# Orchestrator Pickup Note

Date: `2026-04-24`
Repo: `/mnt/e/projects/piano-agents`
Active orchestrator id: `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`

## Current State

Phase 0 is closed at the current defensible scope:

- RV32I control-plane functional validation passed on live board.
- Internal modeled-clock timing closure passed.
- Board-I/O timing model validation passed with zero unconstrained setup/hold paths in TimeQuest.
- Live board UART/audio smoke remained healthy after the timing work.

TeamBus at handoff:

- `43` done, `1` in progress, `1` todo, `0` blocked.
- The `8` failed tasks are superseded/duplicate historical tasks.
- No unread orchestrator inbox messages at handoff.

## Active Work

`task-9fb09496` is in progress with implementer `1031725a-758c-4fd7-8ffd-014794524bb8`.

Task: implement Phase 1 single reduced piano voice from `reports/phase1_reduced_voice_model_spec.md`.

Important constraint: do not implement directly as orchestrator. Let implementer own code edits. The user explicitly asked earlier not to write code directly.

Implementer currently holds edit locks for the Phase 1 implementation paths, including:

- `rtl/audio/phase1_reduced_voice.v`
- `rtl/audio/phase1_reduced_voice_tb.v`
- `rtl/audio/phase0_audio_path.v`
- `rtl/control/phase0_control_regs.v`
- `rtl/top/piano_phase0_top.v`
- `rtl/top/piano_phase0_top_tb.v`
- `fw/phase0/phase0_hw.h`
- `fw/phase0/phase0_main.c`
- `quartus/phase0/piano_phase0_top.qsf`
- `docs/phase0_impl_notes.md`
- `reports/phase1_reduced_voice_impl_report.md`

`task-42106eb1` is queued for verifier and depends on `task-9fb09496`.

## Essential Artifacts

Use these first before asking agents to rediscover context:

- `docs/project_brief.md`: phase plan and architecture split.
- `docs/platform_decisions.md`: locked board/platform decisions.
- `docs/phase0_impl_notes.md`: current RTL/firmware implementation map.
- `reports/phase1_reduced_voice_model_spec.md`: active Phase 1 implementation contract.
- `reports/phase0_board_io_timing_validation.md`: latest board-I/O timing PASS.
- `reports/phase0_board_io_timing_model_report.md`: SDC model details and residual exclusions.
- `reports/phase0_rv32i_timing_closure_validation.md`: internal timing closure PASS.
- `reports/phase0_rv32i_control_plane_validation.md`: RV32I control-plane live hardware PASS.

## Next Orchestrator Move

Wait for implementer to finish `task-9fb09496`.

When the artifact arrives:

- acknowledge implementer message,
- read `reports/phase1_reduced_voice_impl_report.md`,
- check whether `task-9fb09496` is marked done,
- ensure verifier picks up `task-42106eb1`,
- do not start Phase 2 until verifier has produced `reports/phase1_reduced_voice_validation.md`.

If implementer stalls, check TeamBus locks and inbox before intervening. The current active work is legitimate and should not be duplicated.
