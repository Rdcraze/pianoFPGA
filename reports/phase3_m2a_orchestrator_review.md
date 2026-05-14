# Phase 3 M2a Orchestrator Review

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-096f904e`, `task-5debc3fa`

## Verdict

M2a is not yet accepted as the promoted baseline. The verifier artifact is useful hardware evidence, but its PASS recommendation is blocked by a firmware status-register mapping bug and by missing forced-steal evidence.

## Findings

1. The M2a firmware scans physical voice activity using `PHASE0_REG_VOICE_STATUS + vi * 0x34`. That is only correct for voice0 (`0x24`) and voice1 (`0x58`). The current register map defines voice2 status at `0x74` and voice3 status at `0x88`, so the scheduler reads the wrong addresses for voices 2 and 3.

2. The verifier did not observe `ST>0`. The appended `ST` telemetry path is present, but `ST=0` across no-command, commanded, and rapid captures does not validate the steal path while the active/free scan is reading incorrect status registers.

3. The hardware captures do not match the M2a expected profile from the implementation task: no-command reported `G=14` rather than `G=12`, and commanded reported `G=21` rather than the expected approximate `G=18`. These differences need to be explained or corrected before acceptance.

4. `scripts/phase1c_uart_telemetry.py` still treats `ST` as an unknown tag and retains older exact scheduler expectations. The host parser should be updated or versioned for the Phase 3 M2a telemetry contract.

## Required Follow-Up

Queue an implementer fix task to:

- Replace the computed voice-status address expression with an explicit helper using `PHASE0_REG_VOICE_STATUS`, `PHASE0_REG_VOICE1_STATUS`, `PHASE0_REG_VOICE2_STATUS`, and `PHASE0_REG_VOICE3_STATUS`.
- Preserve firmware ROM at or below the 700-word gate if feasible; if the fix exceeds it, reduce other code or request a narrow exception with exact word count.
- Update the host telemetry parser for the appended `ST` tag and M2a expected values, or add a clearly named M2a validation mode.
- Rebuild firmware and report ROM/data usage.
- Produce a deterministic verifier handoff that can actually drive `ST>0`, or clearly define why the hardware decay/release behavior prevents a forced steal with the current command path.

The verifier artifacts from `task-5debc3fa` should be retained as pre-fix evidence, not final acceptance evidence.
